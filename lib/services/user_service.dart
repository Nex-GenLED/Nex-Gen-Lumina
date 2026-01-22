import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/models/user_model.dart';

/// Service for managing user data in Firestore
class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a new user profile
  Future<void> createUser(UserModel user) async {
    try {
      await _firestore.collection('users').doc(user.id).set(user.toJson());
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
      return UserModel.fromJson(doc.data()!);
    } catch (e) {
      debugPrint('Error getting user: $e');
      return null;
    }
  }

  /// Update user profile
  Future<void> updateUser(UserModel user) async {
    try {
      await _firestore.collection('users').doc(user.id).update(
        user.copyWith(updatedAt: DateTime.now()).toJson(),
      );
    } catch (e) {
      debugPrint('Error updating user: $e');
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
      return UserModel.fromJson(doc.data()!);
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
    int? paletteId,
    Map<String, dynamic>? wled,
    String source = 'lumina',
  }) async {
    try {
      final data = <String, dynamic>{
        'created_at': FieldValue.serverTimestamp(),
        'source': source,
        if (colorNames != null && colorNames.isNotEmpty) 'colors': colorNames,
        if (effectId != null) 'effect_id': effectId,
        if (paletteId != null) 'palette_id': paletteId,
        if (wled != null) 'wled': wled,
      };
      await _firestore.collection('users').doc(userId).collection('pattern_usage').add(data);
    } catch (e) {
      debugPrint('logPatternUsage failed: $e');
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
      if (webhookUrl != null) updates['webhook_url'] = webhookUrl;
      if (homeSsid != null) updates['home_ssid'] = homeSsid;
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
        'home_ssid': ssid,
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Home SSID saved: $ssid');
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

  /// Save all schedules for a user (replaces existing schedules).
  Future<void> saveSchedules(String userId, List<ScheduleItem> schedules) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'schedules': schedules.map((e) => e.toJson()).toList(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Schedules saved: ${schedules.length} items');
    } catch (e) {
      debugPrint('❌ saveSchedules failed: $e');
      rethrow;
    }
  }

  /// Add a single schedule item.
  Future<void> addSchedule(String userId, ScheduleItem schedule) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'schedules': FieldValue.arrayUnion([schedule.toJson()]),
        'updated_at': FieldValue.serverTimestamp(),
      });
      debugPrint('✅ Schedule added: ${schedule.id}');
    } catch (e) {
      debugPrint('❌ addSchedule failed: $e');
      rethrow;
    }
  }

  /// Remove a schedule item by ID.
  /// Note: arrayRemove requires exact match, so we fetch and resave.
  Future<void> removeSchedule(String userId, String scheduleId) async {
    try {
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
      debugPrint('✅ Schedule removed: $scheduleId');
    } catch (e) {
      debugPrint('❌ removeSchedule failed: $e');
      rethrow;
    }
  }

  /// Update a single schedule item.
  Future<void> updateSchedule(String userId, ScheduleItem schedule) async {
    try {
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
      debugPrint('✅ Schedule updated: ${schedule.id}');
    } catch (e) {
      debugPrint('❌ updateSchedule failed: $e');
      rethrow;
    }
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
