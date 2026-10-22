// Lumina AI consent: Apple guideline 5.1.2(i).
//
// Lumina AI sends the user's requests to a third-party AI provider
// (Anthropic) through the `claudeProxy` callable. Apple requires clear
// disclosure AND explicit permission before that happens. This file holds:
//
//   * the stored decision ([AiConsent]), per ACCOUNT on users/{uid}.ai_consent,
//     so it follows the user to a new phone and is deleted with the account;
//   * the store that reads and writes it ([AiConsentStore]);
//   * the gate every cloud AI request passes ([AiConsentGate]).
//
// FAIL CLOSED, everywhere. No stored decision, a stream still loading, a
// read error, a write that did not land, an older consent version, or no
// prompter on screen all mean "not granted", and nothing is sent. Only a
// grant whose write SUCCEEDED opens the gate.
//
// The server-side check in claudeProxy is deliberately not built yet. It
// needs the aligned functions tree and a separate approval.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';

/// Bump when the provider or what is sent changes. Every account is asked
/// again, because a grant for an older version does not open the gate.
const int kAiConsentVersion = 1;

/// The provider named in the consent sheet.
const String kAiConsentProvider = 'anthropic';

enum AiConsentStatus { granted, declined, revoked }

/// One account's stored decision (users/{uid}.ai_consent).
class AiConsent {
  final AiConsentStatus status;
  final int version;
  final String provider;
  final DateTime? decidedAt;

  const AiConsent({
    required this.status,
    this.version = kAiConsentVersion,
    this.provider = kAiConsentProvider,
    this.decidedAt,
  });

  /// True only for a grant of the CURRENT version for the current provider.
  bool get allowsRequests =>
      status == AiConsentStatus.granted &&
      version >= kAiConsentVersion &&
      provider == kAiConsentProvider;

  /// `decided_at` is written as a server timestamp by [AiConsentStore].
  Map<String, dynamic> toJson() => {
        'status': status.name,
        'version': version,
        'provider': provider,
        if (decidedAt != null) 'decided_at': Timestamp.fromDate(decidedAt!),
      };

  /// Anything unreadable comes back as null, which the gate treats as "not
  /// asked".
  static AiConsent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final status = AiConsentStatus.values
        .where((s) => s.name == raw['status'])
        .firstOrNull;
    if (status == null) return null;
    final version = raw['version'];
    final decided = raw['decided_at'];
    return AiConsent(
      status: status,
      version: version is int ? version : 0,
      provider: raw['provider'] is String ? raw['provider'] as String : '',
      decidedAt: decided is Timestamp ? decided.toDate() : null,
    );
  }
}

/// Reads and writes users/{uid}.ai_consent.
abstract class AiConsentStore {
  Stream<AiConsent?> watch(String uid);

  /// Throws if the write does not land. A missing user doc throws too: this
  /// is a field UPDATE, never a create.
  Future<void> write(String uid, AiConsentStatus status);
}

class FirestoreAiConsentStore implements AiConsentStore {
  FirestoreAiConsentStore([FirebaseFirestore? firestore])
      : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  @override
  Stream<AiConsent?> watch(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) => AiConsent.fromJson(snap.data()?['ai_consent']));

  @override
  Future<void> write(String uid, AiConsentStatus status) =>
      _firestore.collection('users').doc(uid).update({
        'ai_consent': {
          'status': status.name,
          'version': kAiConsentVersion,
          'provider': kAiConsentProvider,
          'decided_at': FieldValue.serverTimestamp(),
        },
      });
}

final aiConsentStoreProvider =
    Provider<AiConsentStore>((ref) => FirestoreAiConsentStore());

/// The signed-in account's stored decision. Null when signed out or not
/// asked.
final aiConsentProvider = StreamProvider<AiConsent?>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(null);
  return ref.read(aiConsentStoreProvider).watch(uid);
});

/// Fail-closed view for widgets: loading, error and "not asked" are all
/// false.
final aiConsentGrantedProvider = Provider<bool>((ref) {
  final stored = ref.watch(aiConsentProvider).valueOrNull;
  return stored?.allowsRequests ?? false;
});

/// Thrown by every cloud AI chokepoint when the gate stays closed. Callers
/// show [userMessage]; it is never a connection error.
class AiConsentRequiredException implements Exception {
  const AiConsentRequiredException({this.signedOut = false});

  /// No account is signed in: the showroom demo (code REVIEW) runs signed
  /// out. There is nowhere to store consent and claudeProxy refuses a
  /// signed-out caller, so Lumina AI cannot run at all. That is a different
  /// message from "switched off".
  final bool signedOut;

  String get userMessage =>
      signedOut ? kAiSignInRequiredMessage : kAiConsentOffMessage;

  @override
  String toString() => 'AiConsentRequiredException(signedOut: $signedOut)';
}

/// What Lumina says when a request needed the cloud and consent is not given.
const String kAiConsentOffMessage =
    "Lumina AI is off, so I can only do quick commands like 'turn on' or "
    "'warm white'. You can turn Lumina AI on in Settings → Lumina AI.";

/// What Lumina says when a request needed the cloud and nobody is signed in
/// (the showroom demo).
const String kAiSignInRequiredMessage =
    'Lumina AI needs a Nex-Gen account. In the demo you can still use quick '
    "commands like 'turn on' or 'warm white'.";

/// The gate. It is static because the chokepoints (LuminaAI._callClaude and
/// EventLuminaService) are static or ref-less. The app shell keeps it in step
/// with the account ([syncFromStore]) and registers the prompter that shows
/// the sheet.
class AiConsentGate {
  AiConsentGate._();

  static String? _uid;
  static bool _storedGrant = false;
  static bool _revokedThisSession = false;
  static Future<bool> Function()? _prompter;
  static Future<bool>? _inFlight;

  /// True when the app shell reports a signed-in account. False in the
  /// signed-out showroom demo, and before the shell has bound the gate,
  /// which also fails closed.
  static bool get hasAccount => _uid != null;

  /// Throws unless a request may go to the cloud: [AiConsentRequiredException]
  /// with `signedOut: true` when no account is signed in (no sheet; nothing
  /// could store the answer), otherwise after [ensure] says no.
  static Future<void> requireConsent() async {
    if (!hasAccount) throw const AiConsentRequiredException(signedOut: true);
    if (!await ensure()) throw const AiConsentRequiredException();
  }

  /// True only while the account's stored decision is a current grant and
  /// it has not been switched off on this phone since.
  static bool get isGranted => _storedGrant && !_revokedThisSession;

  /// True after the user switched Lumina AI off on this phone and has not
  /// granted again. Widgets combine this with [aiConsentGrantedProvider]
  /// rather than reading [isGranted], whose sync order relative to a
  /// rebuild is not guaranteed.
  static bool get revokedOnThisPhone => _revokedThisSession;

  /// Mirror the signed-in account's stored decision. A different account
  /// starts clean.
  static void syncFromStore(String? uid, AiConsent? consent) {
    if (uid != _uid) {
      _uid = uid;
      _revokedThisSession = false;
    }
    _storedGrant = uid != null && (consent?.allowsRequests ?? false);
  }

  /// Called only after a grant's write has landed.
  static void markGranted() {
    _storedGrant = true;
    _revokedThisSession = false;
  }

  /// Takes effect at once, even if saving the revocation fails, so the
  /// phone stays closed until a new grant is saved.
  static void markRevoked() {
    _storedGrant = false;
    _revokedThisSession = true;
  }

  static void registerPrompter(Future<bool> Function() prompter) =>
      _prompter = prompter;

  static void unregisterPrompter(Future<bool> Function() prompter) {
    if (identical(_prompter, prompter)) _prompter = null;
  }

  /// Open: true. Closed: shows the sheet once (concurrent callers share it)
  /// and returns whether a grant was saved. No prompter means false.
  static Future<bool> ensure() async {
    if (isGranted) return true;
    final prompter = _prompter;
    if (prompter == null) return false;
    return _inFlight ??= _runPrompter(prompter);
  }

  /// A prompter that throws reads as "no".
  static Future<bool> _runPrompter(Future<bool> Function() prompter) async {
    try {
      return await prompter();
    } catch (e) {
      debugPrint('AI consent prompt failed, treated as not granted: $e');
      return false;
    } finally {
      _inFlight = null;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _uid = null;
    _storedGrant = false;
    _revokedThisSession = false;
    _prompter = null;
    _inFlight = null;
  }
}
