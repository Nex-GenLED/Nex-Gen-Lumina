import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/corporate/models/corporate_session.dart';

/// Length of the corporate PIN. 4 digits, mirrors sales/installer/admin.
const int kCorporatePinLength = 4;

/// Inactivity timeout for corporate mode (60 minutes — longer than
/// installer/sales because corporate users typically work in longer
/// uninterrupted sessions).
const Duration kCorporateSessionTimeout = Duration(minutes: 60);

/// Warning threshold before corporate session timeout (5 minutes).
const Duration kCorporateSessionWarningThreshold = Duration(minutes: 5);

/// Holds the active corporate session, or null if not authenticated.
final corporateSessionProvider =
    StateProvider<CorporateSession?>((ref) => null);

/// Convenience provider — returns true when a corporate session exists.
final corporateModeActiveProvider = Provider<bool>((ref) {
  return ref.watch(corporateSessionProvider) != null;
});

/// Notifier that handles corporate PIN authentication and session lifecycle.
///
/// Migrated to server-side validation via the `mintStaffToken` Cloud
/// Function with `mode: 'owner'` (commit 1b45670). Mirrors the
/// SalesModeNotifier / InstallerModeNotifier pattern from b1b871b:
/// - PIN goes to mintStaffToken; the function validates against
///   `app_config/master_corporate_pin` server-side and returns a custom
///   token with `role: 'owner'` and NO dealerCode claim (owner is
///   cross-dealer god mode).
/// - On success we call `signInWithCustomToken`, store a
///   [CorporateSession] in [corporateSessionProvider], and start the
///   60-minute idle timer.
/// - On exit we sign out and re-establish the anonymous baseline so
///   subsequent staff-pin entries work.
///
/// The previous client-side hash compare against `master_corporate_pin`
/// is gone — that doc is no longer client-readable post-rule-tightening.
class CorporateModeNotifier extends StateNotifier<bool> {
  CorporateModeNotifier(this._ref) : super(false);

  final Ref _ref;
  Timer? _sessionTimer;
  Timer? _warningTimer;

  // Per-notifier failed-attempt counter. Note: this duplicates the
  // server-side IP-based rate limit on mintStaffToken (commit 97b6157),
  // which is the actual abuse defense. The local counter exists only
  // for the existing UX behavior (5-strike lockout per app session).
  // Open Item #5 tracks consolidating these into a single screen-level
  // counter — until then, both fire independently.
  static const int _maxAttempts = 5;
  int _failedAttempts = 0;

  /// Optional callback fired when the warning threshold is reached.
  /// UI can wire this to show a "session about to expire" prompt.
  VoidCallback? onSessionWarning;

  bool get isActive => state;

  /// Validate [enteredPin] by calling `mintStaffToken({mode: 'owner'})`.
  /// On success, signs in with the returned custom token, creates a
  /// [CorporateSession], and starts the inactivity timer.
  Future<bool> authenticate(String enteredPin) async {
    if (_failedAttempts >= _maxAttempts) {
      debugPrint(
          'CorporateMode: locked out after $_maxAttempts failed attempts');
      return false;
    }
    if (enteredPin.length != kCorporatePinLength) return false;

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('mintStaffToken');
      final result = await callable.call<Map<String, dynamic>>({
        'pin': enteredPin,
        'mode': 'owner',
      });

      final data = result.data;
      final token = data['token'] as String;
      final displayName =
          (data['displayName'] as String?) ?? 'Nex-Gen Corporate';

      await FirebaseAuth.instance.signInWithCustomToken(token);
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

      _failedAttempts = 0;

      _ref.read(corporateSessionProvider.notifier).state = CorporateSession(
        uid: uid,
        displayName: displayName,
        // Owner is the highest corporate role — maps to CorporateRole.owner.
        // Other CorporateRole values (officer/warehouse/readonly) are
        // legacy from the doc-stored 'role' field; with server-minted
        // claims, owner is the only role this notifier produces.
        role: CorporateRole.owner,
        authenticatedAt: DateTime.now(),
      );

      _startSessionTimer();
      state = true;
      debugPrint('CorporateMode: activated as $displayName (owner)');
      return true;
    } on FirebaseFunctionsException catch (e) {
      // permission-denied is the generic "no PIN match" response from
      // mintStaffToken — count it as a failed attempt to preserve the
      // existing lockout UX. Other Functions errors collapse to the
      // same return-false path but log separately.
      if (e.code == 'permission-denied') {
        _failedAttempts++;
        debugPrint(
            'CorporateMode: failed attempt $_failedAttempts/$_maxAttempts');
      } else {
        debugPrint('CorporateMode: callable error ${e.code}: ${e.message}');
      }
      return false;
    } catch (e) {
      debugPrint('CorporateMode: unexpected error: $e');
      return false;
    }
  }

  /// Sign out and clear the corporate session.
  void signOut() {
    _sessionTimer?.cancel();
    _warningTimer?.cancel();
    _ref.read(corporateSessionProvider.notifier).state = null;
    state = false;
    debugPrint('CorporateMode: signed out');

    // Roll the Firebase Auth session back to anonymous so subsequent
    // staff-pin entries (or other anonymous-only flows) work. Mirrors
    // the exitSalesMode / exitInstallerMode pattern from b1b871b. We do
    // not attempt to restore a customer's prior session — staff and
    // customer auth states should not share, and signing out + re-anon
    // is the documented v2.2.0 trade-off.
    () async {
      try {
        await FirebaseAuth.instance.signOut();
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        debugPrint('CorporateMode: auth restore failed on signOut: $e');
      }
    }();
  }

  /// Reset the inactivity timer (called from UI on user activity).
  void recordActivity() {
    if (state) _startSessionTimer();
  }

  /// Extend the session by resetting timers (called from warning dialog).
  void extendSession() {
    _startSessionTimer();
    debugPrint('CorporateMode: session extended');
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _warningTimer?.cancel();

    final warningDelay =
        kCorporateSessionTimeout - kCorporateSessionWarningThreshold;
    _warningTimer = Timer(warningDelay, () {
      onSessionWarning?.call();
    });

    _sessionTimer = Timer(kCorporateSessionTimeout, () {
      debugPrint('CorporateMode: session timed out');
      signOut();
    });
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _warningTimer?.cancel();
    super.dispose();
  }
}

/// Provider for the corporate mode notifier.
final corporateModeProvider =
    StateNotifierProvider<CorporateModeNotifier, bool>((ref) {
  return CorporateModeNotifier(ref);
});
