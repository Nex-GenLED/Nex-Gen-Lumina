import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/services/account_deletion_service.dart';

/// Records the exact order of side effects so an ORDERING bug can be asserted
/// on directly. `audit/OVERNIGHT_DATA_LIFECYCLE_AUDIT.md` F-2 is not a "wrong
/// value" bug — every individual step was correct — so nothing short of
/// checking the sequence would have caught it.
class _Journal {
  final List<String> events = [];
  void add(String e) => events.add(e);
}

class _FakeAccount implements DeletableAccount {
  _FakeAccount(
    this._journal, {
    this.email = 'customer@example.com',
    this.reauthError,
    this.deleteError,
  });

  final _Journal _journal;

  @override
  final String? email;

  final Object? reauthError;
  final Object? deleteError;

  @override
  String get uid => 'uid_under_test';

  @override
  Future<void> reauthenticate(String password) async {
    _journal.add('reauth');
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> deleteAuthAccount() async {
    _journal.add('authDelete');
    if (deleteError != null) throw deleteError!;
  }
}

AccountDeletionService _service(
  _Journal journal, {
  Object? purgeError,
  bool photoDeleted = true,
}) {
  return AccountDeletionService(
    deleteHousePhoto: (uid) async {
      journal.add('photoDelete:$uid');
      return photoDeleted;
    },
    purgeAccountData: () async {
      journal.add('purge');
      if (purgeError != null) throw purgeError!;
    },
  );
}

void main() {
  group('happy path', () {
    test('runs reauth → photo → purge → auth delete, in that order', () async {
      final journal = _Journal();
      final result = await _service(journal).deleteAccount(
        account: _FakeAccount(journal),
        password: 'correct-horse',
      );

      expect(result.success, isTrue);
      expect(journal.events, [
        'reauth',
        'photoDelete:uid_under_test',
        'purge',
        'authDelete',
      ]);
    });

    test('reports every stage to the caller in order', () async {
      final journal = _Journal();
      final stages = <AccountDeletionStage>[];
      await _service(journal).deleteAccount(
        account: _FakeAccount(journal),
        password: 'correct-horse',
        onStage: stages.add,
      );

      expect(stages, [
        AccountDeletionStage.reauthenticating,
        AccountDeletionStage.deletingPhoto,
        AccountDeletionStage.purgingData,
        AccountDeletionStage.deletingAuthAccount,
      ]);
    });

    test('a photo that will not delete does not stop the purge', () async {
      // Until the Part C storage.rules split reaches production, this is the
      // NORMAL case, not an edge case: on a delete `request.resource` is null,
      // so the old combined write clause denied every owner delete. The server
      // purge sweeps the prefix regardless.
      final journal = _Journal();
      final result = await _service(journal, photoDeleted: false).deleteAccount(
        account: _FakeAccount(journal),
        password: 'correct-horse',
      );

      expect(result.success, isTrue);
      expect(journal.events, contains('purge'));
    });
  });

  group('F-2 — a re-auth failure must leave the data untouched', () {
    test('requires-recent-login: nothing after reauth ever runs', () async {
      // THE regression test for the P0. Under the old flow this sequence
      // deleted users/{uid} first and only then discovered the session was
      // stale, leaving a live Auth account pointing at a profile that no
      // longer existed — with nothing in the app able to recreate it.
      final journal = _Journal();
      final result = await _service(journal).deleteAccount(
        account: _FakeAccount(
          journal,
          reauthError: fb.FirebaseAuthException(code: 'requires-recent-login'),
        ),
        password: 'correct-horse',
      );

      expect(result.success, isFalse);
      expect(result.failure, AccountDeletionFailure.reauthRequired);
      expect(result.stage, AccountDeletionStage.reauthenticating);
      expect(result.dataWasDeleted, isFalse);

      // No purge, no photo delete, no auth delete. Only the attempt itself.
      expect(journal.events, ['reauth']);
    });

    test('wrong password is reported as such and touches nothing', () async {
      final journal = _Journal();
      final result = await _service(journal).deleteAccount(
        account: _FakeAccount(
          journal,
          reauthError: fb.FirebaseAuthException(code: 'wrong-password'),
        ),
        password: 'nope',
      );

      expect(result.failure, AccountDeletionFailure.wrongPassword);
      expect(result.message, contains('Nothing has been deleted'));
      expect(journal.events, ['reauth']);
    });

    test('invalid-credential is treated as a wrong password', () async {
      // Newer Identity Toolkit responses collapse wrong-password into
      // invalid-credential; telling the user "could not verify your sign-in"
      // when they simply mistyped would be a dead end.
      final journal = _Journal();
      final result = await _service(journal).deleteAccount(
        account: _FakeAccount(
          journal,
          reauthError: fb.FirebaseAuthException(code: 'invalid-credential'),
        ),
        password: 'nope',
      );

      expect(result.failure, AccountDeletionFailure.wrongPassword);
    });

    test('a non-Firebase throw from reauth also stops everything', () async {
      final journal = _Journal();
      final result = await _service(journal).deleteAccount(
        account: _FakeAccount(journal, reauthError: StateError('offline')),
        password: 'correct-horse',
      );

      expect(result.failure, AccountDeletionFailure.reauthRequired);
      expect(result.dataWasDeleted, isFalse);
      expect(journal.events, ['reauth']);
    });
  });

  group('purge failure', () {
    test('leaves the Auth account intact so the user can retry', () async {
      final journal = _Journal();
      final result = await _service(
        journal,
        purgeError: FirebaseFunctionsException(
          code: 'internal',
          message: 'Account data was only partially deleted.',
        ),
      ).deleteAccount(
        account: _FakeAccount(journal),
        password: 'correct-horse',
      );

      expect(result.failure, AccountDeletionFailure.purgeFailed);
      expect(result.dataWasDeleted, isFalse);
      expect(journal.events, isNot(contains('authDelete')));
    });

    test('surfaces the server message rather than a generic one', () async {
      // The callable throws with a specific reason when its verify pass finds
      // residue; swallowing that would hide a half-purge.
      final journal = _Journal();
      final result = await _service(
        journal,
        purgeError: FirebaseFunctionsException(
          code: 'internal',
          message: 'Account data was only partially deleted.',
        ),
      ).deleteAccount(
        account: _FakeAccount(journal),
        password: 'correct-horse',
      );

      expect(result.message, 'Account data was only partially deleted.');
    });

    test('a non-Firebase throw is still a purge failure, not a success', () async {
      final journal = _Journal();
      final result = await _service(journal, purgeError: StateError('boom'))
          .deleteAccount(
        account: _FakeAccount(journal),
        password: 'correct-horse',
      );

      expect(result.success, isFalse);
      expect(result.failure, AccountDeletionFailure.purgeFailed);
      expect(journal.events, isNot(contains('authDelete')));
    });
  });

  group('auth delete failure', () {
    test('is the only failure mode that reports data as already gone', () async {
      final journal = _Journal();
      final result = await _service(journal).deleteAccount(
        account: _FakeAccount(
          journal,
          deleteError: fb.FirebaseAuthException(code: 'network-request-failed'),
        ),
        password: 'correct-horse',
      );

      expect(result.failure, AccountDeletionFailure.authDeleteFailed);
      expect(result.dataWasDeleted, isTrue);
      expect(journal.events, [
        'reauth',
        'photoDelete:uid_under_test',
        'purge',
        'authDelete',
      ]);
    });
  });

  group('preconditions', () {
    test('an account with no email is rejected before anything runs', () async {
      final journal = _Journal();
      final result = await _service(journal).deleteAccount(
        account: _FakeAccount(journal, email: null),
        password: 'correct-horse',
      );

      expect(result.failure, AccountDeletionFailure.notEligible);
      expect(journal.events, isEmpty);
    });

    test('an empty email is rejected the same way', () async {
      final journal = _Journal();
      final result = await _service(journal).deleteAccount(
        account: _FakeAccount(journal, email: ''),
        password: 'correct-horse',
      );

      expect(result.failure, AccountDeletionFailure.notEligible);
      expect(journal.events, isEmpty);
    });
  });
}
