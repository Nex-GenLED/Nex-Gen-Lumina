import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';

/// Admin session timeout duration (30 minutes)
const Duration kAdminSessionTimeout = Duration(minutes: 30);

/// Maximum failed admin PIN attempts before lockout
const int kMaxAdminPinAttempts = 5;

/// Lockout duration after exceeding max failed attempts
const Duration kAdminLockoutDuration = Duration(minutes: 15);

/// Tracks failed admin PIN attempts and lockout state
class _AdminPinRateLimiter {
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  /// Returns true if the admin PIN entry is currently locked out
  bool get isLockedOut {
    if (_lockoutUntil == null) return false;
    if (DateTime.now().isAfter(_lockoutUntil!)) {
      // Lockout expired, reset
      _failedAttempts = 0;
      _lockoutUntil = null;
      return false;
    }
    return true;
  }

  /// Returns the remaining lockout duration, or Duration.zero if not locked out
  Duration get remainingLockout {
    if (_lockoutUntil == null) return Duration.zero;
    final remaining = _lockoutUntil!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Record a failed attempt. Returns true if now locked out.
  bool recordFailure() {
    _failedAttempts++;
    if (_failedAttempts >= kMaxAdminPinAttempts) {
      _lockoutUntil = DateTime.now().add(kAdminLockoutDuration);
      debugPrint('AdminPinRateLimiter: Locked out until $_lockoutUntil after $_failedAttempts failed attempts');
      return true;
    }
    return false;
  }

  /// Reset after successful authentication
  void reset() {
    _failedAttempts = 0;
    _lockoutUntil = null;
  }

  int get failedAttempts => _failedAttempts;
}

final _adminPinRateLimiter = _AdminPinRateLimiter();

/// Hash a PIN using SHA-256 for comparison with stored hash
String hashPin(String pin) => sha256.convert(utf8.encode(pin)).toString();

/// Validate the admin PIN against the hash stored in Firestore.
///
/// Returns a [AdminPinResult] indicating success, failure, lockout, or error.
Future<AdminPinResult> validateAdminPin(String enteredPin) async {
  // Check rate limit first
  if (_adminPinRateLimiter.isLockedOut) {
    final remaining = _adminPinRateLimiter.remainingLockout;
    debugPrint('AdminPin: Locked out for ${remaining.inMinutes} more minutes');
    return AdminPinResult.lockedOut(remaining);
  }

  try {
    final doc = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('admin')
        .get();

    if (!doc.exists || doc.data() == null) {
      debugPrint('AdminPin: No admin config found in Firestore');
      _adminPinRateLimiter.recordFailure();
      return AdminPinResult.failure('Admin PIN not configured');
    }

    final storedHash = doc.data()!['pin_hash'] as String?;
    if (storedHash == null || storedHash.isEmpty) {
      debugPrint('AdminPin: No pin_hash field in admin config');
      _adminPinRateLimiter.recordFailure();
      return AdminPinResult.failure('Admin PIN not configured');
    }

    final enteredHash = hashPin(enteredPin);
    if (enteredHash == storedHash) {
      _adminPinRateLimiter.reset();
      debugPrint('AdminPin: Authentication successful');
      return AdminPinResult.success();
    } else {
      final nowLocked = _adminPinRateLimiter.recordFailure();
      debugPrint('AdminPin: Incorrect PIN (attempt ${_adminPinRateLimiter.failedAttempts}/$kMaxAdminPinAttempts)');
      if (nowLocked) {
        return AdminPinResult.lockedOut(_adminPinRateLimiter.remainingLockout);
      }
      return AdminPinResult.failure('Incorrect PIN');
    }
  } catch (e) {
    debugPrint('AdminPin: Error validating PIN: $e');
    _adminPinRateLimiter.recordFailure();
    return AdminPinResult.failure('Unable to validate PIN. Check your connection.');
  }
}

/// Result of an admin PIN validation attempt
class AdminPinResult {
  final bool isSuccess;
  final bool isLockedOut;
  final String? errorMessage;
  final Duration? lockoutRemaining;

  const AdminPinResult._({
    required this.isSuccess,
    this.isLockedOut = false,
    this.errorMessage,
    this.lockoutRemaining,
  });

  factory AdminPinResult.success() => const AdminPinResult._(isSuccess: true);

  factory AdminPinResult.failure(String message) => AdminPinResult._(
        isSuccess: false,
        errorMessage: message,
      );

  factory AdminPinResult.lockedOut(Duration remaining) => AdminPinResult._(
        isSuccess: false,
        isLockedOut: true,
        lockoutRemaining: remaining,
        errorMessage: 'Too many attempts. Try again in ${remaining.inMinutes + 1} minutes.',
      );
}

/// Tracks admin session authentication timestamp
class AdminSession {
  final DateTime authenticatedAt;

  const AdminSession({required this.authenticatedAt});

  /// Whether the session is still within the timeout window
  bool get isValid =>
      DateTime.now().difference(authenticatedAt) < kAdminSessionTimeout;
}

/// Provider for the admin session (null if not authenticated)
final adminSessionProvider = StateProvider<AdminSession?>((ref) => null);

/// Provider that returns true only if admin is authenticated AND session
/// has not expired. This replaces the old `adminAuthenticatedProvider`.
final adminSessionActiveProvider = Provider<bool>((ref) {
  final session = ref.watch(adminSessionProvider);
  if (session == null) return false;
  return session.isValid;
});

/// Legacy provider kept for backward compatibility.
/// Reads from the session-based provider so existing widgets that watch
/// `adminAuthenticatedProvider` continue to work.
final adminAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(adminSessionActiveProvider);
});

/// Call this to start an admin session (on successful PIN entry).
void startAdminSession(WidgetRef ref) {
  ref.read(adminSessionProvider.notifier).state =
      AdminSession(authenticatedAt: DateTime.now());
}

/// Call this to end the admin session (logout or expiry).
void endAdminSession(WidgetRef ref) {
  ref.read(adminSessionProvider.notifier).state = null;
}

/// Checks whether the admin session is still valid.
/// Returns true if active, false if expired or not authenticated.
/// If expired, automatically clears the session.
bool checkAdminSession(WidgetRef ref) {
  final session = ref.read(adminSessionProvider);
  if (session == null) return false;
  if (!session.isValid) {
    endAdminSession(ref);
    return false;
  }
  return true;
}

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
