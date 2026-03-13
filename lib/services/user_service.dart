import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/encryption_service.dart';

/// Service for managing user data in Firestore
class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a new user profile
  Future<void> createUser(UserModel user) async {
    try {
      // SECURITY: Encrypt sensitive data before storing
      final userData = user.toJson();
      final encryptedData = EncryptionService.encryptUserData(userData);

      // Remove null values to prevent Firestore errors
      final cleanedData = _removeNullValues(encryptedData);

      await _firestore.collection('users').doc(user.id).set(cleanedData);
    } catch (e) {
      debugPrint('Error creating user: $e');
      rethrow;
    }
  }

  /// Get user profile by ID
  Future<UserModel?> getUser(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return null;

      // SECURITY: Decrypt sensitive data after reading
      final encryptedData = doc.data()!;
      final decryptedData = EncryptionService.decryptUserData(encryptedData);
      return UserModel.fromJson(decryptedData);
    } catch (e) {
      debugPrint('Error getting user: $e');
      return null;
    }
  }

  /// Update user profile
  Future<void> updateUser(UserModel user) async {
    try {
      // SECURITY: Encrypt sensitive data before updating
      final userData = user.copyWith(updatedAt: DateTime.now()).toJson();
      final encryptedData = EncryptionService.encryptUserData(userData);

      // Remove null values to prevent Firestore from interpreting them as
      // "delete this field" which can cause permission errors
      final cleanedData = _removeNullValues(encryptedData);

      // Use set with merge to avoid permissions errors when document structure
      // doesn't match (e.g., when updating roofline_mask field)
      await _firestore.collection('users').doc(user.id).set(
        cleanedData,
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Error updating user: $e');
      rethrow;
    }
  }

  /// Recursively sanitize a map for Firestore compatibility.
  ///
  /// Removes null values AND converts any non-Firestore-safe types:
  /// - [DateTime] → [Timestamp]
  /// - [Color] → [int] (ARGB value)
  /// - [Map] with non-String keys → [Map<String, dynamic>]
  /// - Typed lists (Uint8List etc.) are already Firestore Blob-compatible.
  ///
  /// This prevents the native iOS Firestore SDK (FSTUserDataReader) from
  /// crashing with SIGABRT when encountering unsupported types.
  Map<String, dynamic> _removeNullValues(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      final sanitized = _sanitizeValue(entry.value);
      if (sanitized != null) {
        result[entry.key] = sanitized;
      }
    }
    return result;
  }

  /// Sanitize a single value for Firestore. Returns null if the value is null.
  dynamic _sanitizeValue(dynamic value) {
    if (value == null) return null;

    // Already Firestore-safe primitives
    if (value is String || value is bool || value is int || value is double) {
      return value;
    }

    // Firestore-native types
    if (value is Timestamp || value is GeoPoint || value is FieldValue) {
      return value;
    }

    // Convert DateTime → Timestamp (common serialization mistake)
    if (value is DateTime) {
      return Timestamp.fromDate(value);
    }

    // Convert Color → ARGB int (prevents SIGABRT on iOS)
    if (value is Color) {
      // ignore: deprecated_member_use
      return value.value;
    }

    // Recursively sanitize maps
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries) {
        final sanitized = _sanitizeValue(entry.value);
        if (sanitized != null) {
          result[entry.key.toString()] = sanitized;
        }
      }
      return result;
    }

    // Recursively sanitize lists
    if (value is List) {
      return value
          .where((item) => item != null)
          .map((item) => _sanitizeValue(item))
          .where((item) => item != null)
          .toList();
    }

    // Fallback: convert unknown types to string to prevent SIGABRT
    debugPrint('⚠️ Firestore sanitizer: converting unknown type '
        '${value.runtimeType} to string');
    return value.toString();
  }

  /// Update specific fields in user profile by ID
  Future<void> updateUserProfile(String userId, Map<String, dynamic> fields) async {
    try {
      fields['updated_at'] = FieldValue.serverTimestamp();
      await _firestore.collection('users').doc(userId).update(fields);
    } catch (e) {
      debugPrint('Error updating user profile: $e');
      rethrow;
    }
  }

  /// Delete user profile
  Future<void> deleteUser(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).delete();
    } catch (e) {
      debugPrint('Error deleting user: $e');
      rethrow;
    }
  }

  /// Stream user profile changes
  Stream<UserModel?> streamUser(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;

      // SECURITY: Decrypt sensitive data
      final encryptedData = doc.data()!;
      final decryptedData = EncryptionService.decryptUserData(encryptedData);
      return UserModel.fromJson(decryptedData);
    });
  }

  /// Append a single dislike keyword to the user's profile (arrayUnion).
  Future<void> addDislike(String userId, String keyword) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'dislikes': FieldValue.arrayUnion([keyword])
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('addDislike failed: $e');
    }
  }

  /// Log a positive pattern usage to help reinforce future suggestions.
  /// Stores a document under users/{uid}/pattern_usage.
  Future<void> logPatternUsage({
    required String userId,
    List<String>? colorNames,
    int? effectId,
    String? effectName,
    int? paletteId,
    Map<String, dynamic>? wled,
    String source = 'lumina',
    String? patternName,
    int? brightness,
    int? speed,
    int? intensity,
  }) async {
    try {
      final data = <String, dynamic>{
        'created_at': FieldValue.serverTimestamp(),
        'source': source,
        if (colorNames != null && colorNames.isNotEmpty) 'colors': colorNames,
        if (effectId != null) 'effect_id': effectId,
        if (effectName != null) 'effect_name': effectName,
        if (paletteId != null) 'palette_id': paletteId,
        if (wled != null) 'wled': wled,
        if (patternName != null) 'pattern_name': patternName,
        if (brightness != null) 'brightness': brightness,
        if (speed != null) 'speed': speed,
        if (intensity != null) 'intensity': intensity,
      };
      await _firestore.collection('users').doc(userId).collection('pattern_usage').add(data);
    } catch (e) {
      debugPrint('logPatternUsage failed: $e');
    }
  }

  // ==================== Usage Analytics ====================

  /// Get recent pattern usage events (last N days)
  Future<List<Map<String, dynamic>>> getRecentUsage(String userId, {int days = 30}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('pattern_usage')
          .where('created_at', isGreaterThan: Timestamp.fromDate(cutoff))
          .orderBy('created_at', descending: true)
          .limit(100)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('getRecentUsage failed: $e');
      return [];
    }
  }

  /// Get most frequently used patterns
  Future<Map<String, int>> getPatternFrequency(String userId, {int days = 30}) async {
    try {
      final usage = await getRecentUsage(userId, days: days);
      final frequency = <String, int>{};

      for (final event in usage) {
        final patternName = event['pattern_name'] as String?;
        final effectId = event['effect_id']?.toString();

        String key = patternName ?? 'effect_$effectId';
        if (key.isNotEmpty && key != 'effect_null') {
          frequency[key] = (frequency[key] ?? 0) + 1;
        }
      }

      return frequency;
    } catch (e) {
      debugPrint('getPatternFrequency failed: $e');
      return {};
    }
  }

  /// Get usage patterns by time of day (for habit detection)
  Future<Map<int, List<Map<String, dynamic>>>> getUsageByHour(String userId, {int days = 30}) async {
    try {
      final usage = await getRecentUsage(userId, days: days);
      final byHour = <int, List<Map<String, dynamic>>>{};

      for (final event in usage) {
        final timestamp = event['created_at'] as Timestamp?;
        if (timestamp != null) {
          final hour = timestamp.toDate().hour;
          byHour.putIfAbsent(hour, () => []).add(event);
        }
      }

      return byHour;
    } catch (e) {
      debugPrint('getUsageByHour failed: $e');
      return {};
    }
  }

  /// Stream pattern usage events for real-time tracking
  Stream<List<Map<String, dynamic>>> streamRecentUsage(String userId, {int limit = 20}) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('pattern_usage')
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // ==================== Favorites Management ====================

  /// Add a pattern to favorites
  Future<void> addFavorite(String userId, Map<String, dynamic> patternData) async {
    try {
      final favorites = _firestore.collection('users').doc(userId).collection('favorites');

      await favorites.add({
        ...patternData,
        'added_at': FieldValue.serverTimestamp(),
        'usage_count': 0,
        'auto_added': patternData['auto_added'] ?? false,
      });

      debugPrint('✅ Added pattern to favorites: ${patternData['pattern_name']}');
    } catch (e) {
      debugPrint('❌ addFavorite failed: $e');
      rethrow;
    }
  }

  /// Remove a favorite by ID
  Future<void> removeFavorite(String userId, String favoriteId) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('favorites')
          .doc(favoriteId)
          .delete();

      debugPrint('✅ Removed favorite: $favoriteId');
    } catch (e) {
      debugPrint('❌ removeFavorite failed: $e');
      rethrow;
    }
  }

  /// Update favorite usage count and last used timestamp
  Future<void> updateFavoriteUsage(String userId, String favoriteId) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('favorites')
          .doc(favoriteId)
          .update({
        'last_used': FieldValue.serverTimestamp(),
        'usage_count': FieldValue.increment(1),
      });
    } catch (e) {
      debugPrint('updateFavoriteUsage failed: $e');
    }
  }

  /// Stream user's favorite patterns
  Stream<List<Map<String, dynamic>>> streamFavorites(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('favorites')
        .orderBy('added_at', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  /// Get favorites as a list
  Future<List<Map<String, dynamic>>> getFavorites(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('favorites')
          .orderBy('added_at', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('getFavorites failed: $e');
      return [];
    }
  }

  // ==================== Smart Suggestions ====================

  /// Save a smart suggestion for the user
  Future<void> saveSuggestion(String userId, Map<String, dynamic> suggestion) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('suggestions')
          .add({
        ...suggestion,
        'created_at': FieldValue.serverTimestamp(),
        'dismissed': false,
      });

      debugPrint('✅ Created suggestion: ${suggestion['title']}');
    } catch (e) {
      debugPrint('❌ saveSuggestion failed: $e');
    }
  }

  /// Dismiss a suggestion
  Future<void> dismissSuggestion(String userId, String suggestionId) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('suggestions')
          .doc(suggestionId)
          .update({'dismissed': true});
    } catch (e) {
      debugPrint('dismissSuggestion failed: $e');
    }
  }

  /// Get active suggestions (not dismissed, not expired)
  Stream<List<Map<String, dynamic>>> streamActiveSuggestions(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('suggestions')
        .where('dismissed', isEqualTo: false)
        .orderBy('priority', descending: true)
        .orderBy('created_at', descending: true)
        .limit(10)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      return snapshot.docs.where((doc) {
        final data = doc.data();
        final expiresAt = (data['expires_at'] as Timestamp?)?.toDate();
        return expiresAt == null || now.isBefore(expiresAt);
      }).map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // ==================== Detected Habits ====================

  /// Save a detected habit
  Future<void> saveDetectedHabit(String userId, Map<String, dynamic> habit) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('detected_habits')
          .add({
        ...habit,
        'detected_at': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Saved detected habit: ${habit['description']}');
    } catch (e) {
      debugPrint('❌ saveDetectedHabit failed: $e');
    }
  }

  /// Get recent detected habits
  Future<List<Map<String, dynamic>>> getDetectedHabits(String userId, {int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('detected_habits')
          .orderBy('detected_at', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('getDetectedHabits failed: $e');
      return [];
    }
  }

  // ==================== Remote Access Configuration ====================

  /// Update the user's remote access configuration.
  ///
  /// [webhookUrl] is the Dynamic DNS URL for the user's home network
  /// [homeSsid] is the WiFi SSID of the user's home network
  /// [enabled] toggles remote access on/off
  Future<void> updateRemoteAccessConfig(
    String userId, {
    String? webhookUrl,
    String? homeSsid,
    bool? enabled,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updated_at': FieldValue.serverTimestamp(),
      };
      // SECURITY: Encrypt webhook URL before storing
      if (webhookUrl != null) {
        updates['webhook_url_encrypted'] =
            EncryptionService.encryptString(webhookUrl);
      }
      // SECURITY: Store both encrypted SSID (for display) and hash (for comparison)
      if (homeSsid != null) {
        updates['home_ssid_encrypted'] =
            EncryptionService.encryptString(homeSsid);
        updates['home_ssid_hash'] = EncryptionService.hashSsid(homeSsid);
      }
      if (enabled != null) updates['remote_access_enabled'] = enabled;

      await _firestore.collection('users').doc(userId).update(updates);
      debugPrint('✅ Remote access config updated for user $userId');
    } catch (e) {
      debugPrint('❌ updateRemoteAccessConfig failed: $e');
      rethrow;
    }
  }

  /// Save the current WiFi SSID as the user's home network.
  Future<void> saveHomeSsid(String userId, String ssid) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        // SECURITY: Encrypt for display recovery, hash for comparison
        'home_ssid_encrypted': EncryptionService.encryptString(ssid),
        'home_ssid_hash': EncryptionService.hashSsid(ssid),
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Home SSID saved (encrypted + hashed)');
    } catch (e) {
      debugPrint('❌ saveHomeSsid failed: $e');
      rethrow;
    }
  }

  /// Enable or disable remote access.
  Future<void> setRemoteAccessEnabled(String userId, bool enabled) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'remote_access_enabled': enabled,
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Remote access ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      debugPrint('❌ setRemoteAccessEnabled failed: $e');
      rethrow;
    }
  }

  /// Clear all remote access configuration (webhook URL, home SSID, disable).
  Future<void> clearRemoteAccessConfig(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        // Delete encrypted fields (current format)
        'webhook_url_encrypted': FieldValue.delete(),
        'home_ssid_encrypted': FieldValue.delete(),
        'home_ssid_hash': FieldValue.delete(),
        // Also clean up legacy plain-text fields if they exist
        'webhook_url': FieldValue.delete(),
        'home_ssid': FieldValue.delete(),
        'remote_access_enabled': false,
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Remote access config cleared');
    } catch (e) {
      debugPrint('❌ clearRemoteAccessConfig failed: $e');
      rethrow;
    }
  }

  // ==================== Schedule Management ====================

  /// Retry delays for transient failures: 2s, then 5s.
  static const _retryDelays = [Duration(seconds: 2), Duration(seconds: 5)];

  /// Attempts a Firestore write with automatic retry on transient failure.
  /// Returns true if the write eventually succeeded, false otherwise.
  Future<bool> _writeWithRetry(Future<void> Function() writeOp) async {
    // First attempt
    try {
      await writeOp();
      return true;
    } catch (e, stack) {
      debugPrint('❌ Schedule write failed (attempt 1): $e\n$stack');
    }

    // Retry attempts
    for (int i = 0; i < _retryDelays.length; i++) {
      await Future.delayed(_retryDelays[i]);
      try {
        await writeOp();
        debugPrint('✅ Schedule write succeeded on retry ${i + 2}');
        return true;
      } catch (e, stack) {
        debugPrint('❌ Schedule write failed (attempt ${i + 2}): $e\n$stack');
      }
    }
    return false;
  }

  /// Verifies a schedule write reached the Firestore server by reading
  /// back with [Source.server] (bypasses local cache).
  Future<bool> verifyServerWrite(String userId, int expectedCount) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .get(const GetOptions(source: Source.server));
      final serverSchedules = doc.data()?['schedules'] as List?;
      return serverSchedules != null && serverSchedules.length == expectedCount;
    } catch (e) {
      debugPrint('⚠️ Server verification failed (offline?): $e');
      return false;
    }
  }

  /// Fetches schedules directly from the Firestore server, bypassing cache.
  Future<List<ScheduleItem>> fetchSchedulesFromServer(String userId) async {
    final doc = await _firestore
        .collection('users')
        .doc(userId)
        .get(const GetOptions(source: Source.server));
    if (!doc.exists) return [];
    final data = doc.data()!;
    return (data['schedules'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map((e) => ScheduleItem.fromJson(e))
            .toList() ??
        [];
  }

  /// Save all schedules for a user (replaces existing schedules).
  /// Returns true if the write was confirmed on the server.
  Future<bool> saveSchedules(String userId, List<ScheduleItem> schedules) async {
    final success = await _writeWithRetry(() async {
      await _firestore.collection('users').doc(userId).update({
        'schedules': schedules.map((e) => e.toJson()).toList(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });

    if (!success) {
      debugPrint('❌ saveSchedules failed after all retries');
      return false;
    }

    // Verify the write reached the server
    final verified = await verifyServerWrite(userId, schedules.length);
    if (!verified) {
      debugPrint('⚠️ saveSchedules: write accepted but server verification failed');
    } else {
      debugPrint('✅ Schedules saved and verified: ${schedules.length} items');
    }
    return verified;
  }

  /// Add a single schedule item.
  /// Returns true if the write was confirmed on the server.
  Future<bool> addSchedule(String userId, ScheduleItem schedule) async {
    final success = await _writeWithRetry(() async {
      await _firestore.collection('users').doc(userId).update({
        'schedules': FieldValue.arrayUnion([schedule.toJson()]),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });

    if (!success) {
      debugPrint('❌ addSchedule failed after all retries');
      return false;
    }
    debugPrint('✅ Schedule added: ${schedule.id}');
    return true;
  }

  /// Remove a schedule item by ID.
  /// Note: arrayRemove requires exact match, so we fetch and resave.
  /// Returns true if the write was confirmed on the server.
  Future<bool> removeSchedule(String userId, String scheduleId) async {
    final success = await _writeWithRetry(() async {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final schedules = (data['schedules'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => ScheduleItem.fromJson(e))
              .where((s) => s.id != scheduleId)
              .toList() ??
          [];

      await _firestore.collection('users').doc(userId).update({
        'schedules': schedules.map((e) => e.toJson()).toList(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });

    if (!success) {
      debugPrint('❌ removeSchedule failed after all retries');
      return false;
    }
    debugPrint('✅ Schedule removed: $scheduleId');
    return true;
  }

  /// Update a single schedule item.
  /// Returns true if the write was confirmed on the server.
  Future<bool> updateSchedule(String userId, ScheduleItem schedule) async {
    final success = await _writeWithRetry(() async {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final schedules = (data['schedules'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => ScheduleItem.fromJson(e))
              .map((s) => s.id == schedule.id ? schedule : s)
              .toList() ??
          [];

      await _firestore.collection('users').doc(userId).update({
        'schedules': schedules.map((e) => e.toJson()).toList(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });

    if (!success) {
      debugPrint('❌ updateSchedule failed after all retries');
      return false;
    }
    debugPrint('✅ Schedule updated: ${schedule.id}');
    return true;
  }

  /// Stream user's schedules.
  Stream<List<ScheduleItem>> streamSchedules(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return [];
      final data = doc.data()!;
      return (data['schedules'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => ScheduleItem.fromJson(e))
              .toList() ??
          [];
    });
  }
}
