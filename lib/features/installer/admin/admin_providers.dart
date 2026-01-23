import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';

/// Admin PIN for accessing dealer/installer management
/// In production, this should be stored securely or use Firebase Auth roles
const String kAdminPin = '9999';

/// Provider for admin authentication state
final adminAuthenticatedProvider = StateProvider<bool>((ref) => false);

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
