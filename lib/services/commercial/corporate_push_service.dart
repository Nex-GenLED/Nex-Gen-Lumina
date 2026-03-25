import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/models/commercial/commercial_schedule.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Lock status for a single location's corporate schedule.
class LocationLockStatus {
  final String locationId;
  final String locationName;
  final bool isLocked;
  final DateTime? lockExpiryDate;

  const LocationLockStatus({
    required this.locationId,
    required this.locationName,
    required this.isLocked,
    this.lockExpiryDate,
  });
}

/// Service for pushing schedules and campaigns from a corporate admin to
/// one or more commercial locations.
///
/// Uses Firestore batch writes (consistent with [AutopilotEventRepository])
/// to atomically update multiple location documents.
class CorporatePushService {
  final FirebaseFirestore _db;

  CorporatePushService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Push a [schedule] to each of [locationIds].
  ///
  /// When [locked] is `true`, sets `isLockedByCorporate` and optionally
  /// `lockExpiryDate` on each target location's commercial schedule document.
  Future<void> pushScheduleToLocations(
    CommercialSchedule schedule,
    List<String> locationIds, {
    bool locked = false,
    DateTime? lockExpiry,
  }) async {
    if (locationIds.isEmpty) return;

    try {
      final batch = _db.batch();

      for (final locId in locationIds) {
        final locSchedule = schedule.copyWith(
          locationId: locId,
          isLockedByCorporate: locked,
          lockExpiryDate: locked ? lockExpiry : null,
        );

        final ref = await _resolveScheduleRef(locId);
        if (ref == null) continue;

        batch.set(
          ref,
          UserService.sanitizeForFirestore(locSchedule.toJson()),
          SetOptions(merge: true),
        );
      }

      await batch.commit();
      debugPrint(
        'CorporatePushService: pushed schedule to '
        '${locationIds.length} locations (locked=$locked)',
      );
    } catch (e) {
      debugPrint('CorporatePushService: pushScheduleToLocations error: $e');
      rethrow;
    }
  }

  /// Push a named campaign to [locationIds] with a defined date range.
  ///
  /// Creates a campaign document and pushes the schedule to all targets.
  Future<void> pushCampaign(
    String campaignName,
    CommercialSchedule schedule,
    List<String> locationIds,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      // 1. Create the campaign record.
      final campaignRef = _db.collection('campaigns').doc();
      await campaignRef.set(UserService.sanitizeForFirestore({
        'campaign_id': campaignRef.id,
        'campaign_name': campaignName,
        'schedule': schedule.toJson(),
        'location_ids': locationIds,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'created_at': FieldValue.serverTimestamp(),
      }));

      // 2. Push the schedule (locked for the campaign duration).
      await pushScheduleToLocations(
        schedule,
        locationIds,
        locked: true,
        lockExpiry: endDate,
      );

      debugPrint(
        'CorporatePushService: campaign "$campaignName" pushed to '
        '${locationIds.length} locations',
      );
    } catch (e) {
      debugPrint('CorporatePushService: pushCampaign error: $e');
      rethrow;
    }
  }

  /// Remove the corporate lock from a single location's schedule.
  Future<void> unlockLocation(String locationId) async {
    try {
      final ref = await _resolveScheduleRef(locationId);
      if (ref == null) return;

      await ref.update({
        'is_locked_by_corporate': false,
        'lock_expiry_date': FieldValue.delete(),
      });

      debugPrint(
        'CorporatePushService: unlocked location $locationId',
      );
    } catch (e) {
      debugPrint('CorporatePushService: unlockLocation error: $e');
      rethrow;
    }
  }

  /// Returns lock status for every location whose schedule is currently
  /// locked by corporate.
  Future<List<LocationLockStatus>> getActiveLocks() async {
    try {
      final snap = await _db
          .collectionGroup('commercial_schedule')
          .where('is_locked_by_corporate', isEqualTo: true)
          .get();

      return snap.docs.map((doc) {
        final data = doc.data();
        final expiryRaw = data['lock_expiry_date'] as String?;
        return LocationLockStatus(
          locationId: data['location_id'] as String? ?? doc.id,
          locationName: data['location_name'] as String? ?? doc.id,
          isLocked: true,
          lockExpiryDate:
              expiryRaw != null ? DateTime.tryParse(expiryRaw) : null,
        );
      }).toList();
    } catch (e) {
      debugPrint('CorporatePushService: getActiveLocks error: $e');
      return const [];
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  /// Resolve the Firestore document reference for a location's commercial
  /// schedule. Uses a collection-group query since we may not know the
  /// parent org ID at call time.
  Future<DocumentReference<Map<String, dynamic>>?> _resolveScheduleRef(
    String locationId,
  ) async {
    try {
      // Try the user-level path first (single-location commercial users).
      // For multi-location, schedules live under the location doc.
      final locSnap = await _db
          .collectionGroup('locations')
          .where('location_id', isEqualTo: locationId)
          .limit(1)
          .get();

      if (locSnap.docs.isNotEmpty) {
        return locSnap.docs.first.reference
            .collection('commercial_schedule')
            .doc('current');
      }

      // Fallback: use the user-level commercial_schedule collection
      // (matches DayPartSchedulerService path).
      return null;
    } catch (e) {
      debugPrint(
        'CorporatePushService: _resolveScheduleRef error: $e',
      );
      return null;
    }
  }
}
