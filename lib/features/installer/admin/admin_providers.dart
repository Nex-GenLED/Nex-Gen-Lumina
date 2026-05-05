import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';

/// Admin session timeout duration (30 minutes).
///
/// Idle timer kicks the user back to the PIN screen after this window.
/// Distinct from the per-IP rate limit on `mintStaffToken` (Prompt 6,
/// commit 97b6157) which is the actual abuse defense — this timeout
/// is a UX freshness check.
const Duration kAdminSessionTimeout = Duration(minutes: 30);

/// Warning threshold before session timeout (5 minutes).
const Duration kAdminSessionWarningThreshold = Duration(minutes: 5);

/// Tracks an active admin session.
///
/// Pre-2026-05-05 this carried only `authenticatedAt`; the new pattern
/// uses a [StateNotifier] for the lifecycle (matching SalesModeNotifier
/// and InstallerModeNotifier) but keeps this immutable struct as the
/// state value so existing consumers can still watch the
/// [adminSessionProvider] and read `.isValid`.
class AdminSession {
  final DateTime authenticatedAt;

  const AdminSession({required this.authenticatedAt});

  /// Whether the session is still within the timeout window.
  bool get isValid =>
      DateTime.now().difference(authenticatedAt) < kAdminSessionTimeout;
}

/// Notifier that handles admin PIN authentication and session lifecycle.
///
/// Migrated to server-side validation via the `mintStaffToken` Cloud
/// Function with `mode: 'admin'` (commit 1b45670). Mirrors the
/// SalesModeNotifier / InstallerModeNotifier pattern from b1b871b:
/// - PIN goes to mintStaffToken; the function validates against
///   `app_config/master_admin` (or per-installer fallback with role
///   enforcement) server-side and returns a custom token with
///   `role: 'admin'` and a `dealerCode` claim.
/// - On success we call `signInWithCustomToken`, store an
///   [AdminSession] in [adminSessionProvider], and start the 30-minute
///   idle timer.
/// - On exit we sign out and re-establish the anonymous baseline so
///   subsequent staff-pin entries work.
///
/// The previous client-side path (`validateAdminPin` + 15-minute
/// `_AdminPinRateLimiter`) is gone. Rate limiting is now enforced by
/// the Cloud Function's per-IP 10-attempts-per-60s window.
class AdminModeNotifier extends StateNotifier<AdminSession?> {
  AdminModeNotifier() : super(null);

  // Unlike SalesModeNotifier / InstallerModeNotifier, this notifier
  // doesn't need a Ref — its session state lives directly on the
  // notifier (via super(null)/state = ...) rather than being mirrored
  // into a separate StateProvider, so there's no need to mutate other
  // providers from inside the methods.

  Timer? _sessionTimer;
  Timer? _warningTimer;

  // Per-notifier failed-attempt counter. Same caveat as the corporate
  // notifier: this duplicates the server-side IP-based rate limit on
  // mintStaffToken (commit 97b6157). The local counter exists only for
  // the existing UX behavior (5-strike lockout per app session). Both
  // fire independently. Open Item #5 tracks consolidation.
  static const int _maxAttempts = 5;
  int _failedAttempts = 0;

  /// Optional callback fired when the warning threshold is reached.
  VoidCallback? onSessionWarning;

  bool get isActive => state != null && state!.isValid;

  /// Validate [enteredPin] by calling `mintStaffToken({mode: 'admin'})`.
  /// On success, signs in with the returned custom token, creates an
  /// [AdminSession], and starts the inactivity timer.
  Future<bool> authenticate(String enteredPin) async {
    if (_failedAttempts >= _maxAttempts) {
      debugPrint(
          'AdminMode: locked out after $_maxAttempts failed attempts');
      return false;
    }
    if (enteredPin.length != 4) return false;

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('mintStaffToken');
      final result = await callable.call<Map<String, dynamic>>({
        'pin': enteredPin,
        'mode': 'admin',
      });

      final data = result.data;
      final token = data['token'] as String;

      await FirebaseAuth.instance.signInWithCustomToken(token);

      _failedAttempts = 0;
      state = AdminSession(authenticatedAt: DateTime.now());
      _startSessionTimer();
      debugPrint('AdminMode: activated');
      return true;
    } on FirebaseFunctionsException catch (e) {
      // permission-denied is the generic "no PIN match" response from
      // mintStaffToken. Count it for the local lockout. Other Functions
      // errors return false but don't count.
      if (e.code == 'permission-denied') {
        _failedAttempts++;
        debugPrint(
            'AdminMode: failed attempt $_failedAttempts/$_maxAttempts');
      } else {
        debugPrint('AdminMode: callable error ${e.code}: ${e.message}');
      }
      return false;
    } catch (e) {
      debugPrint('AdminMode: unexpected error: $e');
      return false;
    }
  }

  /// End the admin session (logout or expiry). Mirrors the
  /// exitSalesMode / exitInstallerMode pattern: signs out and
  /// re-establishes anonymous auth.
  void signOut() {
    _sessionTimer?.cancel();
    _warningTimer?.cancel();
    state = null;
    debugPrint('AdminMode: signed out');

    () async {
      try {
        await FirebaseAuth.instance.signOut();
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        debugPrint('AdminMode: auth restore failed on signOut: $e');
      }
    }();
  }

  /// Reset the inactivity timer (called from UI on user activity).
  void recordActivity() {
    if (state != null) _startSessionTimer();
  }

  /// Extend the session by resetting timers.
  void extendSession() {
    _startSessionTimer();
    debugPrint('AdminMode: session extended');
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _warningTimer?.cancel();

    final warningDelay =
        kAdminSessionTimeout - kAdminSessionWarningThreshold;
    _warningTimer = Timer(warningDelay, () {
      onSessionWarning?.call();
    });

    _sessionTimer = Timer(kAdminSessionTimeout, () {
      debugPrint('AdminMode: session timed out');
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

/// Primary provider for the admin mode notifier. State is the active
/// [AdminSession] or null when not authenticated.
final adminModeProvider =
    StateNotifierProvider<AdminModeNotifier, AdminSession?>((ref) {
  return AdminModeNotifier();
});

/// Backward-compat provider — existing widgets that `ref.watch` the
/// session value go through this. Reads only; mutations happen through
/// `adminModeProvider.notifier`.
final adminSessionProvider = Provider<AdminSession?>((ref) {
  return ref.watch(adminModeProvider);
});

/// Provider that returns true only if admin is authenticated AND
/// session has not expired.
final adminSessionActiveProvider = Provider<bool>((ref) {
  final session = ref.watch(adminModeProvider);
  if (session == null) return false;
  return session.isValid;
});

/// Legacy provider kept for backward compatibility. Reads from the
/// session-based provider so existing widgets that watch
/// `adminAuthenticatedProvider` continue to work.
final adminAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(adminSessionActiveProvider);
});

/// Provider for managing dealers
final dealerListProvider = StreamProvider<List<DealerInfo>>((ref) {
  return FirebaseFirestore.instance
      .collection('dealers')
      .orderBy('dealerCode')
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => DealerInfo.fromMap(doc.data()))
          .toList());
});

/// Provider for managing installers (optionally filtered by dealer)
final installerListProvider = StreamProvider.family<List<InstallerInfo>, String?>((ref, dealerCode) {
  Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('installers');

  if (dealerCode != null && dealerCode.isNotEmpty) {
    query = query.where('dealerCode', isEqualTo: dealerCode);
  }

  return query
      .orderBy('fullPin')
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => InstallerInfo.fromMap(doc.data()))
          .toList());
});

/// Service for admin CRUD operations
class AdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ============ DEALER OPERATIONS ============

  /// Get next available dealer code
  Future<String> getNextDealerCode() async {
    final snapshot = await _firestore
        .collection('dealers')
        .orderBy('dealerCode', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return '01';
    }

    final lastCode = snapshot.docs.first.data()['dealerCode'] as String;
    final nextCode = (int.parse(lastCode) + 1).toString().padLeft(2, '0');

    if (int.parse(nextCode) > 99) {
      throw Exception('Maximum dealer limit (99) reached');
    }

    return nextCode;
  }

  /// Check if a dealer code is available
  Future<bool> isDealerCodeAvailable(String dealerCode) async {
    final snapshot = await _firestore
        .collection('dealers')
        .where('dealerCode', isEqualTo: dealerCode)
        .limit(1)
        .get();
    return snapshot.docs.isEmpty;
  }

  /// Add a new dealer
  Future<void> addDealer(DealerInfo dealer) async {
    // Check if code is available
    final available = await isDealerCodeAvailable(dealer.dealerCode);
    if (!available) {
      throw Exception('Dealer code ${dealer.dealerCode} is already in use');
    }

    await _firestore.collection('dealers').add(dealer.toMap());
    debugPrint('AdminService: Added dealer ${dealer.dealerCode} - ${dealer.companyName}');
  }

  /// Update an existing dealer
  Future<void> updateDealer(String dealerCode, Map<String, dynamic> updates) async {
    final snapshot = await _firestore
        .collection('dealers')
        .where('dealerCode', isEqualTo: dealerCode)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      throw Exception('Dealer not found');
    }

    await snapshot.docs.first.reference.update(updates);
    debugPrint('AdminService: Updated dealer $dealerCode');
  }

  /// Toggle dealer active status
  Future<void> toggleDealerActive(String dealerCode, bool isActive) async {
    await updateDealer(dealerCode, {'isActive': isActive});

    // Also deactivate all installers under this dealer if deactivating
    if (!isActive) {
      final installers = await _firestore
          .collection('installers')
          .where('dealerCode', isEqualTo: dealerCode)
          .get();

      for (final doc in installers.docs) {
        await doc.reference.update({'isActive': false});
      }
      debugPrint('AdminService: Deactivated ${installers.docs.length} installers under dealer $dealerCode');
    }
  }

  /// Delete a dealer (soft delete by deactivating)
  Future<void> deleteDealer(String dealerCode) async {
    await toggleDealerActive(dealerCode, false);
  }

  // ============ INSTALLER OPERATIONS ============

  /// Get next available installer code for a dealer
  Future<String> getNextInstallerCode(String dealerCode) async {
    final snapshot = await _firestore
        .collection('installers')
        .where('dealerCode', isEqualTo: dealerCode)
        .orderBy('installerCode', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return '01';
    }

    final lastCode = snapshot.docs.first.data()['installerCode'] as String;
    final nextCode = (int.parse(lastCode) + 1).toString().padLeft(2, '0');

    if (int.parse(nextCode) > 99) {
      throw Exception('Maximum installer limit (99) for this dealer reached');
    }

    return nextCode;
  }

  /// Check if an installer PIN is available
  Future<bool> isInstallerPinAvailable(String fullPin) async {
    final snapshot = await _firestore
        .collection('installers')
        .where('fullPin', isEqualTo: fullPin)
        .limit(1)
        .get();
    return snapshot.docs.isEmpty;
  }

  /// Add a new installer
  Future<void> addInstaller(InstallerInfo installer) async {
    // Check if PIN is available
    final available = await isInstallerPinAvailable(installer.fullPin);
    if (!available) {
      throw Exception('Installer PIN ${installer.fullPin} is already in use');
    }

    // Verify dealer exists and is active
    final dealerSnapshot = await _firestore
        .collection('dealers')
        .where('dealerCode', isEqualTo: installer.dealerCode)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (dealerSnapshot.docs.isEmpty) {
      throw Exception('No active dealer found with code ${installer.dealerCode}');
    }

    await _firestore.collection('installers').add(installer.toMap());
    debugPrint('AdminService: Added installer ${installer.fullPin} - ${installer.name}');
  }

  /// Update an existing installer
  Future<void> updateInstaller(String fullPin, Map<String, dynamic> updates) async {
    final snapshot = await _firestore
        .collection('installers')
        .where('fullPin', isEqualTo: fullPin)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      throw Exception('Installer not found');
    }

    await snapshot.docs.first.reference.update(updates);
    debugPrint('AdminService: Updated installer $fullPin');
  }

  /// Toggle installer active status
  Future<void> toggleInstallerActive(String fullPin, bool isActive) async {
    await updateInstaller(fullPin, {'isActive': isActive});
  }

  /// Delete an installer (soft delete by deactivating)
  Future<void> deleteInstaller(String fullPin) async {
    await toggleInstallerActive(fullPin, false);
  }

  /// Get installation count for an installer
  Future<int> getInstallationCount(String fullPin) async {
    final snapshot = await _firestore
        .collection('installations')
        .where('installerPin', isEqualTo: fullPin)
        .count()
        .get();
    return snapshot.count ?? 0;
  }
}

/// Provider for the admin service
final adminServiceProvider = Provider<AdminService>((ref) => AdminService());

/// Provider for installation statistics
final installationStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final firestore = FirebaseFirestore.instance;

  final dealerCount = await firestore.collection('dealers').where('isActive', isEqualTo: true).count().get();
  final installerCount = await firestore.collection('installers').where('isActive', isEqualTo: true).count().get();
  final installationCount = await firestore.collection('installations').count().get();

  return {
    'dealers': dealerCount.count ?? 0,
    'installers': installerCount.count ?? 0,
    'installations': installationCount.count ?? 0,
  };
});
