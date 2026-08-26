import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/services/image_upload_service.dart';

/// Ordered stages of account deletion.
///
/// The order IS the fix. `audit/OVERNIGHT_DATA_LIFECYCLE_AUDIT.md` F-2 (P0):
/// the shipped flow deleted the Firestore profile FIRST and called
/// `user.delete()` second. `user.delete()` throws `requires-recent-login`
/// whenever the session is older than ~5 minutes — the common case, since
/// nobody signs in immediately before visiting Security settings. By the time
/// that error surfaced, `users/{uid}` was already gone, and nothing recreates
/// it: `FirebaseAuthManager` only calls `createUser()` inside
/// `createUserWithEmailAndPassword`, never on sign-in. The user was left
/// signed in against a profile that does not exist, permanently, with no
/// recovery UI.
///
/// So re-authentication now happens BEFORE anything is touched. If it fails,
/// zero data has been deleted and the user simply retries from the top.
enum AccountDeletionStage {
  /// Proving the session is fresh. Nothing has been deleted yet.
  reauthenticating,

  /// Removing the Cloud Storage house photo.
  deletingPhoto,

  /// Server-side recursive purge of `users/{uid}` and every subcollection.
  purgingData,

  /// Removing the Firebase Auth account. Last, on purpose.
  deletingAuthAccount,
}

/// Why a deletion attempt stopped.
enum AccountDeletionFailure {
  /// Password did not match. NOTHING was deleted — safe to retry.
  wrongPassword,

  /// Session too old and re-auth did not refresh it. NOTHING was deleted.
  reauthRequired,

  /// The purge callable failed or reported an incomplete sweep. The Auth
  /// account is intact, so the user can still sign in and retry.
  purgeFailed,

  /// Data is gone but the Auth account could not be removed. The one
  /// genuinely awkward state — see [AccountDeletionResult.dataWasDeleted].
  authDeleteFailed,

  /// No signed-in user, missing email, or another precondition.
  notEligible,
}

/// Outcome of [AccountDeletionService.deleteAccount].
@immutable
class AccountDeletionResult {
  const AccountDeletionResult._({
    required this.success,
    this.failure,
    this.stage,
    this.message,
    this.dataWasDeleted = false,
  });

  const AccountDeletionResult.success()
      : success = true,
        failure = null,
        stage = null,
        message = null,
        dataWasDeleted = true;

  const AccountDeletionResult.failed({
    required AccountDeletionFailure failure,
    required AccountDeletionStage stage,
    required String message,
    bool dataWasDeleted = false,
  }) : this._(
          success: false,
          failure: failure,
          stage: stage,
          message: message,
          dataWasDeleted: dataWasDeleted,
        );

  final bool success;
  final AccountDeletionFailure? failure;
  final AccountDeletionStage? stage;
  final String? message;

  /// True when Firestore/Storage data was already purged before the failure.
  ///
  /// The whole point of the reordering is that this is `false` for every
  /// failure mode except [AccountDeletionFailure.authDeleteFailed].
  final bool dataWasDeleted;
}

/// The two Firebase Auth operations deletion needs, behind an interface.
///
/// `fb.User` cannot be constructed in a test, and F-2 is *an ordering bug* —
/// the only way to prove it is fixed is to make a re-auth failure happen and
/// assert nothing downstream ran. That test has to be able to fail on demand,
/// so the boundary is a two-method interface rather than the SDK type.
abstract class DeletableAccount {
  String get uid;
  String? get email;

  /// Refreshes the session. Throws `fb.FirebaseAuthException` on failure.
  Future<void> reauthenticate(String password);

  /// Deletes the Firebase Auth account.
  Future<void> deleteAuthAccount();
}

/// [DeletableAccount] backed by a real signed-in `fb.User`.
class FirebaseDeletableAccount implements DeletableAccount {
  const FirebaseDeletableAccount(this._user);

  final fb.User _user;

  @override
  String get uid => _user.uid;

  @override
  String? get email => _user.email;

  @override
  Future<void> reauthenticate(String password) async {
    final cred = fb.EmailAuthProvider.credential(
      email: _user.email ?? '',
      password: password,
    );
    await _user.reauthenticateWithCredential(cred);
  }

  @override
  Future<void> deleteAuthAccount() => _user.delete();
}

/// Deletes every Firestore document under `users/{uid}` server-side.
/// Throws on any failure, including a purge the server reports as incomplete.
typedef AccountDataPurger = Future<void> Function();

/// Deletes the user's house photo. Returns false rather than throwing.
typedef HousePhotoDeleter = Future<bool> Function(String uid);

/// Runs account deletion in the only order that is safe to interrupt.
///
///   1. re-authenticate  — nothing deleted yet; a failure here costs nothing
///   2. delete house photo (best effort; the server sweeps the prefix anyway)
///   3. purge all Firestore data server-side, and CONFIRM it succeeded
///   4. delete the Auth account
///
/// Step 3 is a callable rather than a `beforeUserDeleted` blocking function
/// because this Firebase project is `subtype: FIREBASE_AUTH`, not
/// `IDENTITY_PLATFORM` (probed live 2026-08-26) — blocking functions require
/// Identity Platform. `audit/OVERNIGHT_DATA_LIFECYCLE_AUDIT.md` §4 item 1
/// names the callable as the acceptable alternative shape.
class AccountDeletionService {
  AccountDeletionService({
    required HousePhotoDeleter deleteHousePhoto,
    required AccountDataPurger purgeAccountData,
  })  : _deleteHousePhoto = deleteHousePhoto,
        _purgeAccountData = purgeAccountData;

  final HousePhotoDeleter _deleteHousePhoto;
  final AccountDataPurger _purgeAccountData;

  /// Deletes [account]'s data and then the account itself.
  ///
  /// [password] is required: re-authenticating unconditionally is what
  /// guarantees the session is fresh *before* any data is touched. Guessing
  /// whether re-auth is "needed" is not possible from the client — there is no
  /// API for token age — and guessing wrong is exactly what produced F-2.
  ///
  /// [onStage] reports progress so the UI can say what is happening; a user
  /// watching an irreversible operation deserves to know which step failed.
  Future<AccountDeletionResult> deleteAccount({
    required DeletableAccount account,
    required String password,
    void Function(AccountDeletionStage stage)? onStage,
  }) async {
    final email = account.email;
    if (email == null || email.isEmpty) {
      return const AccountDeletionResult.failed(
        failure: AccountDeletionFailure.notEligible,
        stage: AccountDeletionStage.reauthenticating,
        message: 'This account has no email address and cannot be deleted '
            'from the app. Please contact support.',
      );
    }

    // ── 1. Re-authenticate FIRST. Nothing has been deleted at this point. ──
    onStage?.call(AccountDeletionStage.reauthenticating);
    try {
      await account.reauthenticate(password);
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('AccountDeletionService: reauth failed: ${e.code}');
      final wrongPassword = e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-login-credentials';
      return AccountDeletionResult.failed(
        failure: wrongPassword
            ? AccountDeletionFailure.wrongPassword
            : AccountDeletionFailure.reauthRequired,
        stage: AccountDeletionStage.reauthenticating,
        message: wrongPassword
            ? 'That password is incorrect. Nothing has been deleted.'
            : 'Could not verify your sign-in (${e.code}). '
                'Nothing has been deleted.',
      );
    } catch (e) {
      debugPrint('AccountDeletionService: reauth failed: $e');
      return const AccountDeletionResult.failed(
        failure: AccountDeletionFailure.reauthRequired,
        stage: AccountDeletionStage.reauthenticating,
        message: 'Could not verify your sign-in. Nothing has been deleted.',
      );
    }

    // ── 2. House photo (F-3). ──────────────────────────────────────────────
    // Best effort on purpose: `deleteHousePhoto()` returns false rather than
    // throwing, and until the `storage.rules` split ships to production it
    // returns false for *every* caller (on a delete `request.resource` is
    // null, so the old combined write clause's size check always failed). The
    // purge callable sweeps the whole `users/{uid}/` prefix with admin
    // credentials regardless, so this call is the belt and that is the braces.
    onStage?.call(AccountDeletionStage.deletingPhoto);
    final photoDeleted = await _deleteHousePhoto(account.uid);
    if (!photoDeleted) {
      debugPrint('AccountDeletionService: house photo not deleted client-side; '
          'the server purge will sweep the prefix.');
    }

    // ── 3. Purge Firestore data, and require confirmed success. ────────────
    onStage?.call(AccountDeletionStage.purgingData);
    try {
      await _purgeAccountData();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('AccountDeletionService: purge failed: ${e.code} ${e.message}');
      return AccountDeletionResult.failed(
        failure: AccountDeletionFailure.purgeFailed,
        stage: AccountDeletionStage.purgingData,
        message: e.message ??
            'Your data could not be deleted. Your account is unchanged — '
                'please try again.',
      );
    } catch (e) {
      debugPrint('AccountDeletionService: purge failed: $e');
      return const AccountDeletionResult.failed(
        failure: AccountDeletionFailure.purgeFailed,
        stage: AccountDeletionStage.purgingData,
        message: 'Your data could not be deleted. Your account is unchanged — '
            'please try again.',
      );
    }

    // ── 4. Auth account LAST. ──────────────────────────────────────────────
    onStage?.call(AccountDeletionStage.deletingAuthAccount);
    try {
      await account.deleteAuthAccount();
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('AccountDeletionService: auth delete failed: ${e.code}');
      // Data is gone, sign-in is not. Unlike F-2's inverse, this state is
      // recoverable: the user is still authenticated and can retry, and a
      // retry is cheap because the purge is idempotent.
      return AccountDeletionResult.failed(
        failure: AccountDeletionFailure.authDeleteFailed,
        stage: AccountDeletionStage.deletingAuthAccount,
        dataWasDeleted: true,
        message: 'Your data was deleted, but your sign-in could not be '
            'removed (${e.code}). Please try again.',
      );
    } catch (e) {
      debugPrint('AccountDeletionService: auth delete failed: $e');
      return const AccountDeletionResult.failed(
        failure: AccountDeletionFailure.authDeleteFailed,
        stage: AccountDeletionStage.deletingAuthAccount,
        dataWasDeleted: true,
        message: 'Your data was deleted, but your sign-in could not be '
            'removed. Please try again.',
      );
    }

    return const AccountDeletionResult.success();
  }
}

final accountDeletionServiceProvider = Provider<AccountDeletionService>((ref) {
  final imageUploadService = ref.read(imageUploadServiceProvider);
  return AccountDeletionService(
    deleteHousePhoto: imageUploadService.deleteHousePhoto,
    purgeAccountData: () async {
      // The callable takes no uid: it purges `request.auth.uid` and nothing
      // else, so there is no argument a caller could aim at someone else.
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('purgeUserAccount')
          .call<dynamic>(<String, dynamic>{});
    },
  );
});
