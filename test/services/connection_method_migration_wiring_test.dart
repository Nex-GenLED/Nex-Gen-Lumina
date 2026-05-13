import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/services/connection_method_migration.dart';

/// These tests cover the auth-listener wiring point — the small adapter
/// that sits between `authStateProvider`'s `User?` and
/// `ConnectionMethodMigration.runOnce`. The real `runOnce` is replaced
/// with a spy so we can assert call shape without touching Firestore.
void main() {
  group('ConnectionMethodMigration.tryRunForUid', () {
    test('signed-in non-anonymous user → runner called with that uid',
        () async {
      final calls = <String>[];
      await ConnectionMethodMigration.tryRunForUid(
        uid: 'real-customer-uid',
        isAnonymous: false,
        runner: (uid) async => calls.add(uid),
      );
      expect(calls, ['real-customer-uid']);
    });

    test('anonymous installer session → runner NOT called', () async {
      final calls = <String>[];
      await ConnectionMethodMigration.tryRunForUid(
        uid: 'anon-installer-uid',
        isAnonymous: true,
        runner: (uid) async => calls.add(uid),
      );
      expect(calls, isEmpty,
          reason: 'Migration must skip anonymous installer-mode sessions — '
              'their /users/{uid}/controllers/ collection is the staging '
              'area, not the customer data we want to backfill');
    });

    test('null uid (signed out) → runner NOT called', () async {
      final calls = <String>[];
      await ConnectionMethodMigration.tryRunForUid(
        uid: null,
        // When Firebase Auth returns null, the call site forwards
        // `isAnonymous: true` defensively. The null check must beat it.
        isAnonymous: true,
        runner: (uid) async => calls.add(uid),
      );
      expect(calls, isEmpty);
    });

    test('empty uid (defensive) → runner NOT called', () async {
      final calls = <String>[];
      await ConnectionMethodMigration.tryRunForUid(
        uid: '',
        isAnonymous: false,
        runner: (uid) async => calls.add(uid),
      );
      expect(calls, isEmpty);
    });

    test('sign-out then sign-in same user → runner called again', () async {
      // The auth-state listener fires once per transition. The
      // SharedPreferences guard inside the real `runOnce` makes the
      // second invocation a no-op, but `tryRunForUid` itself must not
      // short-circuit on its own state — it must defer to the runner.
      final calls = <String>[];
      Future<void> spyRunner(String uid) async => calls.add(uid);

      await ConnectionMethodMigration.tryRunForUid(
        uid: 'returning-user',
        isAnonymous: false,
        runner: spyRunner,
      );
      // Simulate sign-out (null user).
      await ConnectionMethodMigration.tryRunForUid(
        uid: null,
        isAnonymous: true,
        runner: spyRunner,
      );
      // Simulate sign-in by the same user again.
      await ConnectionMethodMigration.tryRunForUid(
        uid: 'returning-user',
        isAnonymous: false,
        runner: spyRunner,
      );

      expect(calls, ['returning-user', 'returning-user'],
          reason: 'tryRunForUid is stateless; idempotency is the runner\'s '
              'responsibility (handled by the SharedPreferences guard in '
              'the real runOnce)');
    });

    test('runner throws → tryRunForUid swallows and resolves', () async {
      // The contract: a migration failure must NOT block app startup.
      // If the runner throws, `tryRunForUid` must catch and resolve
      // normally rather than letting the exception escape into the
      // auth-state listener callback (which would surface as an
      // unhandled future error in production).
      var ran = false;
      await ConnectionMethodMigration.tryRunForUid(
        uid: 'unlucky-user',
        isAnonymous: false,
        runner: (uid) async {
          ran = true;
          throw StateError('simulated Firestore outage');
        },
      );
      expect(ran, isTrue,
          reason: 'runner must have been invoked before throwing');
    });
  });
}
