import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';

/// Service for looking up customer accounts for media/installer access
class CustomerLookupService {
  final FirebaseFirestore _firestore;

  CustomerLookupService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Search for a user by their exact email address
  Future<UserModel?> findByEmail(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      final snapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('CustomerLookup: No user found for email $normalizedEmail');
        return null;
      }

      return UserModel.fromJson(snapshot.docs.first.data());
    } catch (e) {
      debugPrint('CustomerLookup: Error finding user by email: $e');
      return null;
    }
  }

  /// Search for users by address (partial match)
  /// Returns up to [limit] results matching the address query
  Future<List<UserModel>> findByAddress(String addressQuery, {int limit = 20}) async {
    try {
      final normalizedQuery = addressQuery.toLowerCase().trim();
      if (normalizedQuery.isEmpty) return [];

      // Firestore doesn't support full-text search, so we use a prefix query
      // For more advanced search, consider Algolia or similar
      final snapshot = await _firestore
          .collection('users')
          .orderBy('address')
          .startAt([normalizedQuery])
          .endAt(['$normalizedQuery\uf8ff'])
          .limit(limit)
          .get();

      final results = <UserModel>[];
      for (final doc in snapshot.docs) {
        try {
          results.add(UserModel.fromJson(doc.data()));
        } catch (e) {
          debugPrint('CustomerLookup: Error parsing user ${doc.id}: $e');
        }
      }

      debugPrint('CustomerLookup: Found ${results.length} users matching address "$addressQuery"');
      return results;
    } catch (e) {
      debugPrint('CustomerLookup: Error searching by address: $e');
      return [];
    }
  }

  /// Get all installation records for a specific dealer
  Future<List<InstallationRecord>> getInstallationsByDealer(String dealerCode) async {
    try {
      final snapshot = await _firestore
          .collection('installations')
          .where('dealerCode', isEqualTo: dealerCode)
          .orderBy('installedAt', descending: true)
          .limit(100)
          .get();

      return snapshot.docs
          .map((doc) => InstallationRecord.fromMap(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('CustomerLookup: Error fetching installations for dealer $dealerCode: $e');
      return [];
    }
  }

  /// Get all installation records for a specific installer
  Future<List<InstallationRecord>> getInstallationsByInstaller(
    String dealerCode,
    String installerCode,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('installations')
          .where('dealerCode', isEqualTo: dealerCode)
          .where('installerCode', isEqualTo: installerCode)
          .orderBy('installedAt', descending: true)
          .limit(100)
          .get();

      return snapshot.docs
          .map((doc) => InstallationRecord.fromMap(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('CustomerLookup: Error fetching installations for installer $dealerCode$installerCode: $e');
      return [];
    }
  }

  /// Get a user by their ID
  Future<UserModel?> getUserById(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('CustomerLookup: User $userId not found');
        return null;
      }
      return UserModel.fromJson(doc.data()!);
    } catch (e) {
      debugPrint('CustomerLookup: Error fetching user $userId: $e');
      return null;
    }
  }

  /// Search users by display name (partial match)
  Future<List<UserModel>> findByName(String nameQuery, {int limit = 20}) async {
    try {
      final normalizedQuery = nameQuery.toLowerCase().trim();
      if (normalizedQuery.isEmpty) return [];

      final snapshot = await _firestore
          .collection('users')
          .orderBy('display_name')
          .startAt([normalizedQuery])
          .endAt(['$normalizedQuery\uf8ff'])
          .limit(limit)
          .get();

      final results = <UserModel>[];
      for (final doc in snapshot.docs) {
        try {
          results.add(UserModel.fromJson(doc.data()));
        } catch (e) {
          debugPrint('CustomerLookup: Error parsing user ${doc.id}: $e');
        }
      }

      return results;
    } catch (e) {
      debugPrint('CustomerLookup: Error searching by name: $e');
      return [];
    }
  }

  /// Combined search across email, address, and name
  /// Useful for a unified search box in the UI
  Future<List<UserModel>> search(String query, {int limit = 20}) async {
    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty) return [];

    // Check if it looks like an email
    if (normalizedQuery.contains('@')) {
      final emailResult = await findByEmail(normalizedQuery);
      return emailResult != null ? [emailResult] : [];
    }

    // Otherwise search by address and name, merge results
    final results = <String, UserModel>{};

    final addressResults = await findByAddress(normalizedQuery, limit: limit);
    for (final user in addressResults) {
      results[user.id] = user;
    }

    final nameResults = await findByName(normalizedQuery, limit: limit);
    for (final user in nameResults) {
      results[user.id] = user;
    }

    return results.values.take(limit).toList();
  }
}
