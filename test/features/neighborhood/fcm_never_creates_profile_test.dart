// P0 REGRESSION GATE — the FCM token path must NEVER create `users/{uid}`.
//
// The defect (residential path audit 2026-09-23 §0, §1.1 A2b, §1.3 C4b): the
// token write was
//
//     users/{uid}.set({fcmToken, fcmTokenUpdatedAt}, SetOptions(merge: true))
//
// and merge:true CREATES the document when it is absent. It fires from the
// auth-state listener on every non-anonymous sign-in, so it raced every
// profile writer in the app. Whoever lost left a two-field STUB that
// `UserModel.fromJson` cannot parse and that `route_guards` then read as "this
// account already has a profile", because it keyed on `doc.exists`. Production
// census 2026-09-23: 25 of 52 /users documents are exactly that stub — and the
// 32 email Auth accounts with no document at all are each one sign-in away
// from becoming another.
//
// The replacement contract, pinned here:
//   • no profile → write NOTHING, park the token
//   • a stub (exists, but no owner_id) → still write NOTHING; a stub is not a
//     profile
//   • a real profile → store the token
//   • once the profile lands, the parked token is stored on replay

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_notification_service.dart';

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

  void emitSignIn(String uid) {
    _current = _FakeUser(uid);
    _authState.add(_current);
  }

  Future<void> close() => _authState.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMessaging implements FirebaseMessaging {
  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async =>
      'tok-abc123';

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
    // Stand-in for a wedged platform channel; the token half must still run.
    throw Exception('platform unavailable (simulated)');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Only needed because the constructor eagerly resolves
/// `FirebaseFunctions.instance`, which requires a real Firebase app.
class _FakeFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SyncNotificationService _build(FakeFirebaseFirestore db, _FakeAuth auth) =>
    SyncNotificationService(
      firestore: db,
      auth: auth,
      messaging: _FakeMessaging(),
      functions: _FakeFunctions(),
    );

/// Waits for [cond], polling on a short tick, up to [maxTicks].
///
/// Deliberately NOT a fixed `Future.delayed`: a fixed wall-clock wait against
/// an async store is a load-sensitive flake (the full suite runs ~16 isolates
/// in parallel, which is enough to starve one). Returns the instant the
/// condition holds, with a bounded 2 s ceiling so a real failure still fails.
Future<void> _until(bool Function() cond, {int maxTicks = 200}) async {
  for (var i = 0; i < maxTicks && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// The token path has run and found nothing to write onto.
Future<void> _untilParked(SyncNotificationService s) =>
    _until(() => s.hasPendingTokenStore);

/// `users/{uid}` carries an fcmToken.
Future<bool> _hasToken(FakeFirebaseFirestore db, String uid) async {
  final d = await db.collection('users').doc(uid).get();
  return d.exists && d.data()?['fcmToken'] != null;
}

Map<String, dynamic> _profile(String uid) => {
      'id': uid,
      'owner_id': uid,
      'email': '$uid@example.test',
      'display_name': uid,
      'created_at': Timestamp.now(),
      'updated_at': Timestamp.now(),
    };

void main() {
  group('the FCM token path never creates users/{uid}', () {
    test('THE REGRESSION: no profile document → no document is created',
        () async {
      final db = FakeFirebaseFirestore();
      final auth = _FakeAuth();
      final service = _build(db, auth);

      service.startAuthWatch();
      auth.emitSignIn('no_profile_yet');
      await _untilParked(service);

      final doc = await db.collection('users').doc('no_profile_yet').get();
      expect(doc.exists, isFalse,
          reason: 'this write used to fabricate the stub that broke 25 of 52 '
              'production profiles');
      expect(service.hasPendingTokenStore, isTrue,
          reason: 'the token is parked, not lost — push must not stay dead');

      await auth.close();
      service.dispose();
    });

    test('an EXISTING STUB is not a profile — the token is still not written',
        () async {
      final db = FakeFirebaseFirestore();
      // The exact production shape: 24 of the 25 stubs are these keys.
      await db.collection('users').doc('stubbed').set({
        'fcmToken': 'old-token',
        'fcmTokenUpdatedAt': Timestamp.now(),
        'referralCode': 'ABC123',
      });
      final auth = _FakeAuth();
      final service = _build(db, auth);

      service.startAuthWatch();
      auth.emitSignIn('stubbed');
      await _untilParked(service);

      final data = (await db.collection('users').doc('stubbed').get()).data()!;
      expect(data['fcmToken'], 'old-token',
          reason: 'writing onto a stub keeps it alive and unparseable');
      expect(service.hasPendingTokenStore, isTrue);

      await auth.close();
      service.dispose();
    });

    test('a REAL profile gets the token', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc('real').set(_profile('real'));
      final auth = _FakeAuth();
      final service = _build(db, auth);

      service.startAuthWatch();
      auth.emitSignIn('real');
      var stored = false;
      await _until(() {
        unawaited(_hasToken(db, 'real').then((v) => stored = v));
        return stored;
      });

      final data = (await db.collection('users').doc('real').get()).data()!;
      expect(data['fcmToken'], 'tok-abc123');
      expect(data['fcmTokenUpdatedAt'], isNotNull);
      expect(service.hasPendingTokenStore, isFalse);

      await auth.close();
      service.dispose();
    });

    test('the parked token is stored once the profile is written', () async {
      final db = FakeFirebaseFirestore();
      final auth = _FakeAuth();
      final service = _build(db, auth);

      service.startAuthWatch();
      auth.emitSignIn('late_profile');
      await _untilParked(service);
      expect((await db.collection('users').doc('late_profile').get()).exists,
          isFalse);

      // The installer wizard / route guard / signup writes the profile.
      await db
          .collection('users')
          .doc('late_profile')
          .set(_profile('late_profile'));

      // main.dart replays on the first parsed currentUserProfileProvider emit.
      await service.retryPendingTokenStore();

      final data =
          (await db.collection('users').doc('late_profile').get()).data()!;
      expect(data['fcmToken'], 'tok-abc123',
          reason: 'push must not stay dead for the rest of the session');
      expect(data['owner_id'], 'late_profile',
          reason: 'the replay is an update — it cannot clobber the profile');
      expect(service.hasPendingTokenStore, isFalse);

      await auth.close();
      service.dispose();
    });

    test('a replay after the account switched is dropped, not misdirected',
        () async {
      final db = FakeFirebaseFirestore();
      final auth = _FakeAuth();
      final service = _build(db, auth);

      service.startAuthWatch();
      auth.emitSignIn('first_account');
      await _untilParked(service);
      expect(service.hasPendingTokenStore, isTrue);

      // A different account signs in before the first one's profile lands.
      await db.collection('users').doc('second').set(_profile('second'));
      auth.emitSignIn('second');
      var secondStored = false;
      await _until(() {
        unawaited(_hasToken(db, 'second').then((v) => secondStored = v));
        return secondStored;
      });

      await service.retryPendingTokenStore();

      expect((await db.collection('users').doc('first_account').get()).exists,
          isFalse);

      await auth.close();
      service.dispose();
    });
  });
}
