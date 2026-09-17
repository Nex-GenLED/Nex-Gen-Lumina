import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_notification_service.dart';

/// REGRESSION TEST — the FCM token must be stored when a user signs in AFTER
/// launch, not only when one is already signed in at cold start.
///
/// The bug: `initialize()` set `_initialized = true` on ENTRY, and
/// `_storeToken` early-returns when `uid == null`. A cold start with no user
/// therefore skipped the token write, and because the method was
/// idempotent-by-flag it never ran again for that session. Push (weekly brief,
/// sync events) was silently dead for every user who signed in after launch.
///
/// These tests drive the real `startAuthWatch()` path against fakes rather than
/// asserting on code shape.

class _FakeUser implements User {
  @override
  final String uid;
  _FakeUser(this.uid);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements FirebaseAuth {
  final _authState = StreamController<User?>.broadcast();
  User? _current;

  @override
  User? get currentUser => _current;

  @override
  Stream<User?> authStateChanges() => _authState.stream;

  /// Simulate a sign-in happening some time AFTER startAuthWatch() was called.
  void emitSignIn(String uid) {
    _current = _FakeUser(uid);
    _authState.add(_current);
  }

  void emitSignOut() {
    _current = null;
    _authState.add(null);
  }

  Future<void> close() => _authState.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMessaging implements FirebaseMessaging {
  final String? token;

  /// When true, `requestPermission` throws — standing in for a wedged Play
  /// Services / unavailable platform channel. The token half must still run.
  final bool permissionThrows;

  int getTokenCalls = 0;
  int requestPermissionCalls = 0;

  _FakeMessaging({this.token = 'tok-abc123', this.permissionThrows = true});

  @override
  Future<String?> getToken({String? vapidKey}) async {
    getTokenCalls++;
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    requestPermissionCalls++;
    if (permissionThrows) {
      throw Exception('platform unavailable (simulated)');
    }
    throw UnimplementedError('not needed by these tests');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Only needed because the constructor eagerly resolves
/// `FirebaseFunctions.instance`, which requires a real Firebase app. These
/// tests never send a notification, so nothing on it is ever called.
class _FakeFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SyncNotificationService _build({
  required FakeFirebaseFirestore firestore,
  required _FakeAuth auth,
  required _FakeMessaging messaging,
}) {
  return SyncNotificationService(
    firestore: firestore,
    auth: auth,
    messaging: messaging,
    functions: _FakeFunctions(),
  );
}

void main() {
  group('FCM token on late sign-in', () {
    test(
        'THE REGRESSION: signing in AFTER startAuthWatch() stores the token',
        () async {
      final firestore = FakeFirebaseFirestore();
      final auth = _FakeAuth();
      final messaging = _FakeMessaging();
      final service = _build(
        firestore: firestore,
        auth: auth,
        messaging: messaging,
      );

      // Cold start: watcher armed while NOBODY is signed in.
      service.startAuthWatch();
      await Future<void>.delayed(Duration.zero);

      // Nothing should have been written, and critically, no permission
      // prompt should have been raised on the cold-launch frame.
      expect(messaging.requestPermissionCalls, 0,
          reason: 'must not prompt for notifications before a user exists');
      final before = await firestore.collection('users').doc('u1').get();
      expect(before.exists, isFalse);

      // The user signs in later in the same session.
      auth.emitSignIn('u1');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The token must now be stored. Under the old code this document was
      // never written, because initialize() had already burned its flag.
      final after = await firestore.collection('users').doc('u1').get();
      expect(after.exists, isTrue,
          reason: 'FCM token doc must be created on late sign-in');
      expect(after.data()!['fcmToken'], 'tok-abc123');
      expect(after.data()!.containsKey('fcmTokenUpdatedAt'), isTrue);

      await auth.close();
      service.dispose();
    });

    test(
        'the token half survives the wiring half throwing',
        () async {
      final firestore = FakeFirebaseFirestore();
      final auth = _FakeAuth();
      // requestPermission throws, i.e. initialize() blows up.
      final messaging = _FakeMessaging(permissionThrows: true);
      final service = _build(
        firestore: firestore,
        auth: auth,
        messaging: messaging,
      );

      service.startAuthWatch();
      auth.emitSignIn('u2');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(messaging.requestPermissionCalls, greaterThan(0),
          reason: 'initialize() should have been attempted');
      final doc = await firestore.collection('users').doc('u2').get();
      expect(doc.exists, isTrue,
          reason:
              'a throw inside initialize() must not prevent the token write');
      expect(doc.data()!['fcmToken'], 'tok-abc123');

      await auth.close();
      service.dispose();
    });

    test('a second account on the same device also gets its token stored',
        () async {
      final firestore = FakeFirebaseFirestore();
      final auth = _FakeAuth();
      final messaging = _FakeMessaging();
      final service = _build(
        firestore: firestore,
        auth: auth,
        messaging: messaging,
      );

      service.startAuthWatch();

      auth.emitSignIn('first');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      auth.emitSignOut();
      await Future<void>.delayed(Duration.zero);
      auth.emitSignIn('second');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Both users must hold the token. The old idempotency flag would have
      // stopped after the first.
      expect((await firestore.collection('users').doc('first').get()).exists,
          isTrue);
      expect((await firestore.collection('users').doc('second').get()).exists,
          isTrue);

      await auth.close();
      service.dispose();
    });

    test('a null FCM token writes nothing', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = _FakeAuth();
      // getToken() can legitimately return null (no Play Services, no APNs
      // token yet). _refreshAndStoreToken must not write an empty field.
      final messaging = _FakeMessaging(token: null);
      final service = _build(
        firestore: firestore,
        auth: auth,
        messaging: messaging,
      );

      service.startAuthWatch();
      auth.emitSignIn('u3');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(messaging.getTokenCalls, greaterThan(0));
      expect((await firestore.collection('users').doc('u3').get()).exists,
          isFalse,
          reason: 'a null token must not produce a document');

      await auth.close();
      service.dispose();
    });

    test('a null auth emission writes nothing', () async {
      final firestore = FakeFirebaseFirestore();
      final auth = _FakeAuth();
      final messaging = _FakeMessaging();
      final service = _build(
        firestore: firestore,
        auth: auth,
        messaging: messaging,
      );

      service.startAuthWatch();
      auth.emitSignOut();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(messaging.getTokenCalls, 0);
      expect(messaging.requestPermissionCalls, 0);

      await auth.close();
      service.dispose();
    });
  });
}
