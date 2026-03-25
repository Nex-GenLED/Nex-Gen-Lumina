import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/models/commercial/business_hours.dart';
import 'package:nexgen_command/models/commercial/channel_role.dart';
import 'package:nexgen_command/models/commercial/commercial_schedule.dart';
import 'package:nexgen_command/models/commercial/day_part.dart';
import 'package:nexgen_command/models/commercial/day_part_template.dart';
import 'package:nexgen_command/models/commercial/holiday_calendar.dart';
import 'package:nexgen_command/services/commercial/business_hours_service.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Service that integrates day-part scheduling with the existing Autopilot
/// system for commercial locations.
///
/// The commercial schedule **coexists** with the standard autopilot document
/// structure — it writes to a sibling `commercial_schedule` sub-document under
/// the same location path so the two systems can be evaluated side-by-side.
class DayPartSchedulerService {
  final FirebaseFirestore _db;
  final BusinessHoursService hoursService;

  DayPartSchedulerService({
    FirebaseFirestore? db,
    this.hoursService = const BusinessHoursService(),
  }) : _db = db ?? FirebaseFirestore.instance;

  // ── Core resolution methods ──────────────────────────────────────────────

  /// Returns the [DayPart] active right now for [schedule], or `null` if no
  /// day-part covers the current time.
  DayPart? getActiveDayPart(
    CommercialSchedule schedule,
    BusinessHours hours,
  ) {
    final now = DateTime.now();
    for (final dp in schedule.dayParts) {
      if (dp.isActiveAt(now)) return dp;
    }
    return null;
  }

  /// Returns the [CommercialSchedule.defaultAmbientDesignId] when coverage
  /// policy is SMART_FILL and no day-part covers the current time.
  String? getSmartFillDesign(CommercialSchedule schedule) {
    final policy = schedule.coveragePolicy;
    if (policy != CoveragePolicy.smartFill) return null;

    // Check whether any day-part is currently active.
    final now = DateTime.now();
    for (final dp in schedule.dayParts) {
      if (dp.isActiveAt(now)) return null; // a day-part covers this slot
    }

    return schedule.defaultAmbientDesignId;
  }

  /// Resolves the design that should be active right now for [channel].
  ///
  /// Resolution order:
  /// 1. If business is closed → SCHEDULED_ONLY channels get `null`
  ///    (lights off); other channels get [defaultAmbientDesignId] or `null`.
  /// 2. Active day-part → its [assignedDesignId].
  /// 3. Smart Fill gap → [defaultAmbientDesignId].
  /// 4. Fallback → `null` (no design).
  ///
  /// For outdoor channels the caller should additionally apply the
  /// [DaylightBrightnessModifier] multiplier to the brightness value.
  String? resolveActiveDesign(
    CommercialSchedule schedule,
    BusinessHours hours,
    ChannelRoleConfig channel, {
    HolidayCalendar calendar = const HolidayCalendar(),
  }) {
    final open = hoursService.isBusinessOpen(hours, calendar);
    final effectivePolicy =
        channel.coveragePolicy; // channel-level policy takes precedence

    // Outside business hours.
    if (!open) {
      if (effectivePolicy == CoveragePolicy.scheduledOnly) return null;
      if (effectivePolicy == CoveragePolicy.alwaysOn) {
        return schedule.defaultAmbientDesignId;
      }
      // SMART_FILL outside hours → ambient if available
      return schedule.defaultAmbientDesignId;
    }

    // During business hours — try active day-part first.
    final activePart = getActiveDayPart(schedule, hours);
    if (activePart != null) {
      // Day-part may override coverage policy.
      final partPolicy = activePart.coveragePolicy ?? effectivePolicy;
      if (partPolicy == CoveragePolicy.scheduledOnly &&
          activePart.assignedDesignId == null) {
        return null;
      }
      return activePart.assignedDesignId ?? schedule.defaultAmbientDesignId;
    }

    // No day-part covers this time — Smart Fill.
    if (effectivePolicy == CoveragePolicy.smartFill) {
      return schedule.defaultAmbientDesignId;
    }
    if (effectivePolicy == CoveragePolicy.alwaysOn) {
      return schedule.defaultAmbientDesignId;
    }

    // SCHEDULED_ONLY with no active day-part → off.
    return null;
  }

  /// Generates a [CommercialSchedule] from a business-type template and hours.
  CommercialSchedule generateScheduleFromTemplate(
    String businessType,
    BusinessHours hours, {
    String locationId = '',
  }) {
    final parts = DayPartTemplate.forBusinessType(businessType, hours);
    return CommercialSchedule(
      locationId: locationId,
      dayParts: parts,
      coveragePolicy: CoveragePolicy.smartFill,
    );
  }

  // ── Firestore persistence (extends Autopilot document tree) ──────────────

  /// Writes a [CommercialSchedule] to Firestore alongside the existing
  /// autopilot document structure.
  ///
  /// Path: `/users/{uid}/commercial_schedule/{locationId}`
  ///
  /// This does **not** replace autopilot events — it coexists.  The
  /// Autopilot system checks `commercialModeEnabled` to decide whether
  /// to delegate to the commercial schedule.
  Future<bool> saveSchedule(String uid, CommercialSchedule schedule) async {
    try {
      final ref = _db
          .collection('users')
          .doc(uid)
          .collection('commercial_schedule')
          .doc(schedule.locationId);

      await ref.set(
        UserService.sanitizeForFirestore(schedule.toJson()),
        SetOptions(merge: true),
      );

      debugPrint(
        'DayPartSchedulerService: saved commercial schedule '
        'for location ${schedule.locationId}',
      );
      return true;
    } catch (e) {
      debugPrint('DayPartSchedulerService: saveSchedule error: $e');
      return false;
    }
  }

  /// Fetches the commercial schedule for [locationId].
  Future<CommercialSchedule?> fetchSchedule(
    String uid,
    String locationId,
  ) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('commercial_schedule')
          .doc(locationId)
          .get(const GetOptions(source: Source.server));

      if (!snap.exists || snap.data() == null) return null;
      return CommercialSchedule.fromJson(snap.data()!);
    } catch (e) {
      debugPrint('DayPartSchedulerService: fetchSchedule error: $e');
      return null;
    }
  }

  /// Deletes the commercial schedule for [locationId].
  Future<void> deleteSchedule(String uid, String locationId) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('commercial_schedule')
          .doc(locationId)
          .delete();
    } catch (e) {
      debugPrint('DayPartSchedulerService: deleteSchedule error: $e');
    }
  }
}
