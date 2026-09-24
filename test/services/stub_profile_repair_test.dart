// P0 REGRESSION GATE — a stub `users/{uid}` document must be repaired, not
// swallowed.
//
// The defect (residential path audit 2026-09-23 §1.3 / §9.1 items 6 and 7):
// the FCM token path wrote `{fcmToken, fcmTokenUpdatedAt}` with merge:true on
// every non-anonymous sign-in, which CREATES the document. Two things then
// went wrong at once:
//
//   • route_guards keyed "does this account have a profile?" on `doc.exists`,
//     so the stub counted as one and the skeleton was never written. The
//     account sat on /link-account forever.
//   • `UserModel.fromJson` does unguarded non-null casts on six keys, so the
//     stub threw on parse, `currentUserProfileProvider` became an AsyncError,
//     and 40+ consumers swallowed it through `maybeWhen(orElse: null)`. First
//     run's "Get started" did nothing, the house-photo upload reported success
//     and wrote nothing, and BLE pairing refused with "Only system owners can
//     add new controllers".
//
// Production census 2026-09-23: 25 of 52 /users documents are exactly that
// stub, and 32 email Auth accounts with no document at all were one sign-in
// away from joining them.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/route_guards.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Waits for [cond], polling on a short tick, up to [maxTicks].
///
/// Deliberately NOT a fixed `Future.delayed`: a fixed wall-clock wait against
/// an async store is a load-sensitive flake (the full suite runs ~16 isolates
/// in parallel, which is enough to starve one). This returns the instant the
/// condition holds and gives a bounded 2 s ceiling when it never does, so the
/// failure is a real failure rather than a scheduling accident.
Future<void> _until(bool Function() cond, {int maxTicks = 200}) async {
  for (var i = 0; i < maxTicks && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

const _uid = 'stubbed_customer';

/// The exact shape production holds: 24 of the 25 stubs are these three keys.
Map<String, dynamic> get _stub => {
      'fcmToken': 'tok-abc123',
      'fcmTokenUpdatedAt': Timestamp.now(),
      'referralCode': 'ABC123',
    };

Map<String, dynamic> _realProfile() => {
      'id': _uid,
      'email': 'someone@example.test',
      'display_name': 'Someone',
      'owner_id': _uid,
      'created_at': Timestamp.now(),
      'updated_at': Timestamp.now(),
      'installation_role': 'primary',
    };

void main() {
  group('UserService.missingProfileKeys', () {
    test('a stub is missing all six required keys', () {
      expect(UserService.missingProfileKeys(_stub), [
        'id',
        'email',
        'display_name',
        'owner_id',
        'created_at',
        'updated_at',
      ]);
    });

    test('a real profile is missing none', () {
      expect(UserService.missingProfileKeys(_realProfile()), isEmpty);
    });

    test('a wrong-typed timestamp counts as missing', () {
      // The cast at user_model.dart is `json['created_at'] as Timestamp` —
      // a String there throws exactly like an absent key.
      final data = _realProfile()..['created_at'] = '2026-09-23';
      expect(UserService.missingProfileKeys(data), ['created_at']);
    });
  });

  group('hasProvisionedProfile', () {
    test('THE REGRESSION: a stub does NOT count as having a profile',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(_uid).set(_stub);
      final doc = await db.collection('users').doc(_uid).get();

      expect(doc.exists, isTrue,
          reason: 'the stub is a real document — that is the whole trap');
      expect(hasProvisionedProfile(doc), isFalse,
          reason: 'route_guards must write the skeleton over it');
    });

    test('an absent document does not count', () async {
      final db = FakeFirebaseFirestore();
      final doc = await db.collection('users').doc(_uid).get();
      expect(hasProvisionedProfile(doc), isFalse);
    });

    test('an empty owner_id does not count', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(_uid).set({'owner_id': ''});
      final doc = await db.collection('users').doc(_uid).get();
      expect(hasProvisionedProfile(doc), isFalse);
    });

    test('a real profile counts', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(_uid).set(_realProfile());
      final doc = await db.collection('users').doc(_uid).get();
      expect(hasProvisionedProfile(doc), isTrue);
    });
  });

  group('repairProfileSkeleton', () {
    test('writes exactly the missing keys onto a stub and keeps the rest',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(_uid).set(_stub);

      await UserService(firestore: db).repairProfileSkeleton(
        _uid,
        _stub,
        authEmail: 'someone@example.test',
        authDisplayName: 'Someone',
      );

      final data = (await db.collection('users').doc(_uid).get()).data()!;
      expect(data['id'], _uid);
      expect(data['owner_id'], _uid);
      expect(data['email'], 'someone@example.test');
      expect(data['display_name'], 'Someone');
      expect(data['created_at'], isA<Timestamp>());
      expect(data['updated_at'], isA<Timestamp>());
      // The repair deliberately does NOT decide the role — that stays with
      // route_guards.createUnlinkedUserProfile and ReviewerSeedService, so it
      // cannot race the App Review seed and downgrade it to /link-account.
      expect(data.containsKey('installation_role'), isFalse);
      // The stub's own fields survive — the repair is a merge, not a reset.
      expect(data['fcmToken'], 'tok-abc123');
      expect(data['referralCode'], 'ABC123');
      // And the repaired document parses.
      expect(UserService.missingProfileKeys(data), isEmpty);
    });

    test('falls back to the email local part when Auth has no display name',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(_uid).set(_stub);

      await UserService(firestore: db).repairProfileSkeleton(
        _uid,
        _stub,
        authEmail: 'jo.smith@example.test',
      );

      final data = (await db.collection('users').doc(_uid).get()).data()!;
      expect(data['display_name'], 'jo.smith');
    });

    test('a complete profile is left completely alone', () async {
      final db = FakeFirebaseFirestore();
      final profile = _realProfile();
      await db.collection('users').doc(_uid).set(profile);

      await UserService(firestore: db).repairProfileSkeleton(_uid, profile);

      final data = (await db.collection('users').doc(_uid).get()).data()!;
      expect(data['installation_role'], 'primary',
          reason: 'a linked customer must never be downgraded to unlinked');
      expect(data['display_name'], 'Someone');
    });

    test('a partially broken profile keeps its good fields', () async {
      final db = FakeFirebaseFirestore();
      // owner_id is fine; created_at is the wrong type (a real production
      // shape — see the camelCase reviewer-seed drift).
      final broken = _realProfile()..['created_at'] = 'not-a-timestamp';
      await db.collection('users').doc(_uid).set(broken);

      await UserService(firestore: db).repairProfileSkeleton(_uid, broken);

      final data = (await db.collection('users').doc(_uid).get()).data()!;
      expect(data['created_at'], isA<Timestamp>());
      expect(data['email'], 'someone@example.test');
      expect(data['installation_role'], 'primary');
      expect(UserService.missingProfileKeys(data), isEmpty);
    });
  });

  // 2.5.10+108 — the build-107 repair WRITE LOOP.
  //
  // A `serverTimestamp()` still in flight reads back as null in the local
  // snapshot. build-107 repaired that null with another serverTimestamp(),
  // whose local snapshot was null again: one ordinary
  // `updated_at: serverTimestamp()` write started an unbounded write loop on
  // `users/{uid}` (239 repair writes in 4 s, reproduced with the real client
  // SDK against the Firestore emulator). fake_cloud_firestore resolves server
  // timestamps instantly and never reports pending writes, which is why the
  // suite could not see it — so the decision is pinned directly here.
  group('decideProfileSnapshot', () {
    final now = DateTime(2026, 9, 24, 12);
    Map<String, dynamic> pendingStamp() =>
        {..._realProfile(), 'updated_at': null};

    test('THE REGRESSION: a pending updated_at is being written, not missing',
        () {
      final d = UserService.decideProfileSnapshot(pendingStamp(),
          hasPendingWrites: true, now: now);
      expect(d.repair, isFalse);
      expect(d.parseable, isNotNull);
      expect(UserModel.fromJson(d.parseable!).id, _uid,
          reason: 'the profile keeps parsing while the write is in flight');
    });

    test('both stamps pending (a skeleton write in flight) still parse', () {
      final d = UserService.decideProfileSnapshot(
          {..._realProfile(), 'created_at': null, 'updated_at': null},
          hasPendingWrites: true,
          now: now);
      expect(d.repair, isFalse);
      expect(d.parseable, isNotNull);
    });

    test('a pending snapshot never repairs, even when a string key is missing',
        () {
      final d = UserService.decideProfileSnapshot(
          {..._realProfile()}..remove('display_name'),
          hasPendingWrites: true,
          now: now);
      expect(d.parseable, isNull);
      expect(d.repair, isFalse,
          reason: 'the server-confirmed snapshot decides, not a local one');
    });

    test('a confirmed stub is repaired once, then waits out the cooldown', () {
      final first = UserService.decideProfileSnapshot(_stub,
          hasPendingWrites: false, now: now);
      expect(first.repair, isTrue);

      final soon = UserService.decideProfileSnapshot(_stub,
          hasPendingWrites: false,
          now: now.add(const Duration(seconds: 5)),
          lastRepairAt: now);
      expect(soon.repair, isFalse,
          reason: 'a rejected repair (reject → revert → repair) must not loop');

      final later = UserService.decideProfileSnapshot(_stub,
          hasPendingWrites: false,
          now: now.add(UserService.profileRepairCooldown),
          lastRepairAt: now);
      expect(later.repair, isTrue);
    });

    test('a complete confirmed profile parses and is left alone', () {
      final d = UserService.decideProfileSnapshot(_realProfile(),
          hasPendingWrites: false, now: now);
      expect(d.repair, isFalse);
      expect(d.parseable, isNotNull);
    });

    test('LOOP GATE: the write→null→repair cycle stops at zero repairs', () {
      // Model of the client: every repair write is another pending
      // serverTimestamp, so the next local snapshot shows updated_at null
      // with hasPendingWrites true. build-107's rule ("repair whenever
      // missingProfileKeys is non-empty") repairs on every one of them.
      var build107Repairs = 0;
      var fixedRepairs = 0;
      DateTime? lastRepair;
      for (var i = 0; i < 200; i++) {
        final snapshot = pendingStamp();
        if (UserService.missingProfileKeys(snapshot).isNotEmpty) {
          build107Repairs++;
        }
        final d = UserService.decideProfileSnapshot(snapshot,
            hasPendingWrites: true,
            now: now.add(Duration(milliseconds: i * 16)),
            lastRepairAt: lastRepair);
        if (d.repair) {
          fixedRepairs++;
          lastRepair = now;
        }
      }
      expect(build107Repairs, 200, reason: 'the defect, reproduced');
      expect(fixedRepairs, 0);
    });
  });

  group('streamUser', () {
    setUp(UserService.resetProfileRepairThrottleForTest);

    test('THE REGRESSION: a stub emits null and triggers a repair instead of '
        'an AsyncError nobody reads', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(_uid).set(_stub);

      final svc = UserService(firestore: db);
      final emissions = <Object?>[];
      final sub = svc
          .streamUser(_uid, authEmail: 'someone@example.test')
          .listen(emissions.add, onError: emissions.add);

      // First emission: the stub. Must be null, never a thrown cast.
      await _until(() => emissions.isNotEmpty);
      expect(emissions.first, isNull);

      // The repair lands and the snapshot listener fires again, this time with
      // a parseable document.
      await _until(() => emissions.length >= 2);
      expect(emissions.last, isA<UserModel>(),
          reason: 'the repaired document must parse');

      await sub.cancel();
    });

    test('an absent document still emits null without a repair write',
        () async {
      final db = FakeFirebaseFirestore();
      final svc = UserService(firestore: db);
      final emissions = <Object?>[];
      final sub = svc.streamUser(_uid).listen(emissions.add);

      // Wait for the stream to actually emit, then assert nothing was written
      // — so the negative assertion cannot pass vacuously because the listener
      // had not run yet.
      await _until(() => emissions.isNotEmpty);
      expect(emissions.single, isNull);
      expect((await db.collection('users').doc(_uid).get()).exists, isFalse,
          reason: 'streamUser must not fabricate a profile either');

      await sub.cancel();
    });
  });
}
