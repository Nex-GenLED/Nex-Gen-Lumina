import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/corporate/models/corporate_session.dart';

/// Length of the corporate PIN. 4 digits, mirrors sales/installer.
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
/// Mirrors [InstallerModeNotifier] / [SalesModeNotifier]:
/// - PIN is validated against `app_config/master_corporate_pin`
/// - On success, writes a [CorporateSession] to [corporateSessionProvider]
/// - 60-minute idle timeout via [_startSessionTimer]
class CorporateModeNotifier extends StateNotifier<bool> {
  CorporateModeNotifier(this._ref) : super(false);

  final Ref _ref;
  Timer? _sessionTimer;
  Timer? _warningTimer;

  static const int _maxAttempts = 5;
  int _failedAttempts = 0;

  /// Optional callback fired when the warning threshold is reached.
  /// UI can wire this to show a "session about to expire" prompt.
  VoidCallback? onSessionWarning;

  bool get isActive => state;

  /// Validate [enteredPin] against `app_config/master_corporate_pin` in
  /// Firestore. On success, creates and stores a [CorporateSession] and
  /// starts the inactivity timer.
  Future<bool> authenticate(String enteredPin) async {
    if (_failedAttempts >= _maxAttempts) {
      debugPrint(
          'CorporateMode: locked out after $_maxAttempts failed attempts');
      return false;
    }
    if (enteredPin.length != kCorporatePinLength) return false;

    try {
      final enteredHash = sha256.convert(utf8.encode(enteredPin)).toString();

      final configDoc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('master_corporate_pin')
          .get();

      if (!configDoc.exists) {
        debugPrint(
            'CorporateMode: master_corporate_pin doc missing in app_config');
        _failedAttempts++;
        return false;
      }

      final data = configDoc.data() ?? {};
      final storedHash = data['pin_hash'] as String?;
      if (storedHash == null || storedHash != enteredHash) {
        _failedAttempts++;
        debugPrint(
            'CorporateMode: failed attempt $_failedAttempts/$_maxAttempts');
        return false;
      }

      _failedAttempts = 0;

      // Optional fields stored alongside the PIN — let admins customize the
      // session display without re-deploying. Falls back to sensible defaults.
      final displayName =
          (data['displayName'] as String?) ?? 'Nex-Gen Corporate';
      final role = CorporateRoleX.fromString(data['role'] as String?);

      _ref.read(corporateSessionProvider.notifier).state = CorporateSession(
        uid: data['uid'] as String? ?? '',
        displayName: displayName,
        role: role,
        authenticatedAt: DateTime.now(),
      );

      _startSessionTimer();
      state = true;
      debugPrint('CorporateMode: activated as $displayName (${role.name})');
      return true;
    } catch (e) {
      debugPrint('CorporateMode: validation error: $e');
      _failedAttempts++;
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
