import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The sign-in, first-run and staff-PIN screens talk to Firebase Auth and to
// the account document through this file, so each one can be driven in a
// widget test without a Firebase app.

/// The signed-in account, as the setup and sign-in screens need it.
abstract class AccountSession {
  String? get uid;
  String? get email;
  String? get displayName;
  bool get isSignedIn;
  bool get isAnonymous;

  /// Starts an anonymous session and returns its uid.
  Future<String?> signInAnonymously();

  Future<void> reauthenticate(String email, String password);
  Future<void> updatePassword(String newPassword);
  Future<void> sendPasswordResetEmail(String email);
  Future<void> signOut();
}

class FirebaseAccountSession implements AccountSession {
  FirebaseAccountSession([FirebaseAuth? auth]) : _authOverride = auth;

  final FirebaseAuth? _authOverride;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  @override
  String? get uid => _auth.currentUser?.uid;
  @override
  String? get email => _auth.currentUser?.email;
  @override
  String? get displayName => _auth.currentUser?.displayName;
  @override
  bool get isSignedIn => _auth.currentUser != null;
  @override
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? false;

  @override
  Future<String?> signInAnonymously() async =>
      (await _auth.signInAnonymously()).user?.uid;

  @override
  Future<void> reauthenticate(String email, String password) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    await user.updatePassword(newPassword);
  }

  @override
  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  @override
  Future<void> signOut() => _auth.signOut();
}

final accountSessionProvider =
    Provider<AccountSession>((ref) => FirebaseAccountSession());

/// The Firestore the sign-in and join screens write the account through.
final accountFirestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

// ─────────────────────────────────────────────────────────────────────────────
// One-shot account flags (must_reset_password, welcome_completed)
// ─────────────────────────────────────────────────────────────────────────────

/// A flag on `users/{uid}` that a screen clears once, after which the router
/// must stop sending the customer back to that screen.
enum AccountFlag {
  /// `must_reset_password` → false. Cleared by the forced password reset.
  passwordResetDone,

  /// `welcome_completed` → true. Cleared by the first-run screen.
  welcomeCompleted,
}

/// Flags this app session has already cleared, per uid.
///
/// The screen that clears a flag records it here BEFORE its Firestore write,
/// and `appRedirect` honours it. So a write that is slow, offline or refused
/// no longer strands the customer on a screen they have already finished: the
/// write keeps retrying in the background (see [writeAccountFlag]) while the
/// router lets them through.
class SessionAccountFlags {
  SessionAccountFlags._();

  static final Map<String, Set<AccountFlag>> _cleared = {};

  static void markCleared(String uid, AccountFlag flag) {
    if (uid.isEmpty) return;
    (_cleared[uid] ??= <AccountFlag>{}).add(flag);
  }

  static bool isCleared(String? uid, AccountFlag flag) {
    if (uid == null || uid.isEmpty) return false;
    return _cleared[uid]?.contains(flag) ?? false;
  }

  @visibleForTesting
  static void resetForTest() {
    _cleared.clear();
    _retrying.clear();
  }

  static final Set<String> _retrying = {};
}

/// How long a screen waits for a one-shot flag write before moving on.
///
/// Matches `kRedirectFirestoreTimeout`: the same round trip the router already
/// refuses to wait longer for.
const Duration kAccountFlagWriteTimeout = Duration(seconds: 8);

/// Waits between background retries after a flag write did not land in time.
/// Each retry is itself bounded by [kAccountFlagWriteTimeout].
const List<Duration> kAccountFlagRetryDelays = <Duration>[
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 45),
  Duration(minutes: 2),
  Duration(minutes: 5),
  Duration(minutes: 10),
];

/// What happened to a flag write within the screen's wait.
enum AccountFlagWrite {
  /// The server acknowledged it.
  saved,

  /// It did not land in time (offline, slow, or refused). The flag is
  /// honoured for this session and the write is retrying in the background.
  retryingInBackground,
}

/// Clears [flag] for [uid]: records it for this session, then runs [write]
/// with a bounded wait. If the write fails or times out, it is retried in the
/// background on [retryDelays] until one attempt succeeds.
///
/// Never throws, and never waits longer than [timeout]. The caller moves the
/// customer on either way.
Future<AccountFlagWrite> writeAccountFlag({
  required String uid,
  required AccountFlag flag,
  required Future<void> Function() write,
  Duration timeout = kAccountFlagWriteTimeout,
  List<Duration> retryDelays = kAccountFlagRetryDelays,
}) async {
  SessionAccountFlags.markCleared(uid, flag);
  if (await _attemptFlagWrite(write, timeout, flag, attempt: 1)) {
    return AccountFlagWrite.saved;
  }
  _retryFlagWriteInBackground(uid, flag, write, timeout, retryDelays);
  return AccountFlagWrite.retryingInBackground;
}

Future<bool> _attemptFlagWrite(
  Future<void> Function() write,
  Duration timeout,
  AccountFlag flag, {
  required int attempt,
}) async {
  try {
    await write().timeout(timeout);
    return true;
  } catch (e) {
    debugPrint('Account flag ${flag.name}: attempt $attempt failed: $e');
    return false;
  }
}

void _retryFlagWriteInBackground(
  String uid,
  AccountFlag flag,
  Future<void> Function() write,
  Duration timeout,
  List<Duration> retryDelays,
) {
  final key = '$uid/${flag.name}';
  // One retry loop per flag per account; a second tap must not start another.
  if (!SessionAccountFlags._retrying.add(key)) return;
  unawaited(() async {
    try {
      var attempt = 1;
      for (final delay in retryDelays) {
        await Future<void>.delayed(delay);
        attempt++;
        if (await _attemptFlagWrite(write, timeout, flag, attempt: attempt)) {
          return;
        }
      }
      debugPrint('Account flag ${flag.name}: gave up after $attempt attempts; '
          'honoured for this session only.');
    } finally {
      SessionAccountFlags._retrying.remove(key);
    }
  }());
}

// ─────────────────────────────────────────────────────────────────────────────
// Leftover anonymous sessions
// ─────────────────────────────────────────────────────────────────────────────

/// Signs out an anonymous session. Anonymous sessions exist only so the staff
/// PIN screen can read its PIN documents; one left behind makes the router
/// send every customer route ("Create One", the demo) back to the login page.
///
/// Returns true when a session was signed out. Never throws.
Future<bool> discardAnonymousSession(AccountSession session) async {
  if (!session.isSignedIn || !session.isAnonymous) return false;
  try {
    await session.signOut();
    return true;
  } catch (e) {
    debugPrint('discardAnonymousSession: sign-out failed: $e');
    return false;
  }
}
