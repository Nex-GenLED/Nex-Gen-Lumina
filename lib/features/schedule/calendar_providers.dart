// lib/features/schedule/calendar_providers.dart
//
// State management for date-specific calendar schedule entries.
// Provides the CalendarScheduleNotifier, pending-changes state,
// and the LuminaCalendarService that calls the Anthropic API.

import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/eviction_request.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_detector.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_dialog.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/autopilot/autopilot_conflict_dialog.dart';
import 'package:nexgen_command/utils/sun_utils.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:uuid/uuid.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

String calendarDateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _monthName(int m) => const [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ][m];

String _dayName(int wd) => const [
      '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ][wd];

// ─── Calendar Schedule State ──────────────────────────────────────────────────

class CalendarScheduleNotifier
    extends StateNotifier<Map<String, CalendarEntry>> {
  final Ref _ref;
  final String? _userId;

  CalendarScheduleNotifier(this._ref, this._userId)
      : super(_buildHolidayDefaults()) {
    _loadFromFirestore();
  }

  // Seed with well-known holiday presets so the calendar is never empty.
  static Map<String, CalendarEntry> _buildHolidayDefaults() {
    final m = <String, CalendarEntry>{};
    void add(
      String dateKey,
      String pattern,
      Color color, {
      String? note,
      String onTime = '17:30',
      String offTime = '23:30',
    }) {
      m[dateKey] = CalendarEntry(
        dateKey: dateKey,
        patternName: pattern,
        color: color,
        onTime: onTime,
        offTime: offTime,
        brightness: 100,
        type: CalendarEntryType.holiday,
        autopilot: false,
        note: note ?? 'Holiday preset',
      );
    }

    // 2026 holidays — extend as needed
    add('2026-03-17', "St. Patrick's Day",   const Color(0xFF00A86B));
    add('2026-04-05', 'Easter Pastels',       const Color(0xFFFFB3DE));
    add('2026-05-25', 'Memorial Day',         const Color(0xFFB22222));
    add('2026-06-14', 'Flag Day',             const Color(0xFFB22222));
    add('2026-07-04', 'Independence Day',     const Color(0xFF0033A0));
    add('2026-09-07', 'Labor Day',            const Color(0xFFFF6B35));
    add('2026-10-31', 'Halloween',            const Color(0xFFFF6B00), offTime: '00:00');
    add('2026-11-26', 'Thanksgiving',         const Color(0xFFFF8C00));
    add('2026-12-24', 'Christmas Eve',        const Color(0xFFCC0000), onTime: '17:00', offTime: '01:00');
    add('2026-12-25', 'Christmas Day',        const Color(0xFFCC0000), onTime: '17:00', offTime: '01:00');
    add('2026-12-31', "New Year's Eve",       const Color(0xFF9B6DFF), onTime: '18:00', offTime: '02:00');
    add('2027-01-01', "New Year's Day",       const Color(0xFF9B6DFF));

    return m;
  }

  /// Load user-saved entries from Firestore and merge on top of holiday
  /// defaults. Firestore entries win on date-key conflicts.
  Future<void> _loadFromFirestore() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      final userService = _ref.read(userServiceProvider);
      final saved = await userService.loadCalendarEntries(uid);
      if (saved.isNotEmpty) {
        final merged = Map<String, CalendarEntry>.from(state);
        merged.addAll(saved);
        state = merged;
      }
    } catch (e) {
      debugPrint('❌ Failed to load calendar entries: $e');
    }
  }

  // ─── Conflict detection ─────────────────────────────────────────

  /// Check incoming entries against recurring schedules.
  /// Returns info the caller can pass to [showScheduleConflictDialog].
  ScheduleConflictInfo checkConflictsForEntries(List<CalendarEntry> entries) {
    final recurringSchedules = _ref.read(schedulesProvider);
    final seen = <String, ScheduleItem>{};
    for (final entry in entries) {
      final entryDate = DateTime.parse(entry.dateKey);
      for (final item in ScheduleConflictDetector.findItemConflictsForEntry(
        entry: entry,
        entryDate: entryDate,
        recurringItems: recurringSchedules,
      )) {
        seen[item.id] = item;
      }
    }
    return ScheduleConflictInfo(conflictingItems: seen.values.toList());
  }

  // ─── Autopilot conflict detection ───────────────────────────────

  /// Returns date keys from [entries] that would overwrite an existing
  /// [CalendarEntryType.user] record.  Used by autopilot to decide
  /// whether to show a conflict card.
  List<String> findUserConflictKeys(List<CalendarEntry> entries) {
    final conflicting = <String>[];
    for (final entry in entries) {
      final existing = state[entry.dateKey];
      if (existing != null && existing.type == CalendarEntryType.user) {
        conflicting.add(entry.dateKey);
      }
    }
    return conflicting;
  }

  /// Filter [entries] according to [choice], returning only the entries
  /// that should actually be written.
  ///
  /// - [keepMine]: drop any entry whose date has an existing user record.
  /// - [useAutopilot]: keep all entries (overwrites user records).
  /// - [merge]: keep autopilot's pattern/color but preserve user's times
  ///   and brightness where set.
  List<CalendarEntry> resolveAutopilotConflicts(
    List<CalendarEntry> entries,
    AutopilotConflictChoice choice,
  ) {
    if (choice == AutopilotConflictChoice.cancel ||
        choice == AutopilotConflictChoice.keepMine) {
      // Drop entries that conflict with user records
      return entries
          .where((e) {
            final existing = state[e.dateKey];
            return existing == null || existing.type != CalendarEntryType.user;
          })
          .toList();
    }

    if (choice == AutopilotConflictChoice.merge) {
      return entries.map((e) {
        final existing = state[e.dateKey];
        if (existing != null && existing.type == CalendarEntryType.user) {
          // Keep user's times and brightness; take autopilot's pattern/color
          return e.copyWith(
            onTime: existing.onTime ?? e.onTime,
            offTime: existing.offTime ?? e.offTime,
            brightness: existing.brightness > 0 ? existing.brightness : e.brightness,
          );
        }
        return e;
      }).toList();
    }

    // useAutopilot — pass through as-is
    return entries;
  }

  // ─── Mutations ─────────────────────────────────────────────────

  /// Apply a list of date-specific entries, overwriting any existing
  /// entries for those dates.  Persists non-holiday entries to Firestore.
  /// Pass [resolution] after showing the conflict dialog to handle overlaps.
  ///
  /// When [recurringIntent] is non-null, the per-day [entries] are discarded
  /// and a single recurring [ScheduleItem] is written instead. This is the
  /// collapse path for Lumina chat requests like "warm white every night
  /// this week" — the detector classifies the intent at parse time
  /// (see [LuminaCalendarService._detectRecurringIntent]) and this method
  /// routes the write. Other callers (autopilot, manual entry editor) leave
  /// [recurringIntent] null and get the original per-day write behavior.
  ///
  /// Returns true if the Firestore write succeeded.
  Future<bool> applyEntries(List<CalendarEntry> entries,
      {ConflictResolution? resolution, RecurringIntent? recurringIntent}) async {
    // ── Conflict resolution (before optimistic update) ───────────
    if (resolution == ConflictResolution.cancel) return false;

    // Recurring-intent fast path: skip CalendarEntry storage entirely and
    // write a single ScheduleItem instead. The schedules-provider addAll
    // path has its own content-fingerprint dedup against existing entries
    // (e.g. an autopilot-created sibling), so a no-op result is normal
    // when a matching ScheduleItem already exists.
    if (recurringIntent != null) {
      return _writeAsScheduleItem(recurringIntent);
    }

    if (resolution == ConflictResolution.removeExisting) {
      final conflicts = checkConflictsForEntries(entries);
      final schedNotifier = _ref.read(schedulesProvider.notifier);
      for (final item in conflicts.conflictingItems) {
        await schedNotifier.remove(item.id);
      }
    }

    // Optimistic local update
    final next = Map<String, CalendarEntry>.from(state);
    for (final e in entries) {
      next[e.dateKey] = e;
    }
    state = next;

    // Persist user entries to Firestore
    final uid = _userId;
    if (uid == null) return false;
    try {
      final userService = _ref.read(userServiceProvider);
      final toSave = Map<String, CalendarEntry>.fromEntries(
        next.entries.where((e) => e.value.type != CalendarEntryType.holiday),
      );
      final ok = await userService.saveCalendarEntries(uid, toSave);
      if (!ok) {
        debugPrint('❌ applyEntries: Firestore write failed');
      }

      // Item #61 Workstream B — surface each saved entry to the lease
      // manager so date-specific overrides within the 48 h window reach
      // the WLED timer slots. Holidays are bundled defaults and never lease.
      // A lease failure must NOT roll back the Firestore write: the
      // calendar display is the source of truth; the lease is just the
      // firing mechanism. A visible entry without a lease is recoverable
      // (next sweep or eviction UX), a missing entry is not.
      if (ok) {
        final leaseManager =
            _ref.read(calendarEntryLeaseManagerProvider);
        for (final entry in entries) {
          if (entry.type == CalendarEntryType.holiday) continue;
          try {
            final result = await leaseManager.handleEntryCreated(entry);
            if (result.outcome == LeaseOutcome.noFreeSlots) {
              // Prompt 4 — Option-C user-driven eviction. Surface a
              // request to the UI listener; await the user's pick.
              await _handleNoFreeSlotsForEntry(
                entry: entry,
                leaseManager: leaseManager,
              );
            }
          } catch (e) {
            debugPrint('CalendarLease: handleEntryCreated failed: $e');
          }
        }
      }
      return ok;
    } catch (e) {
      debugPrint('❌ applyEntries: $e');
      return false;
    }
  }

  /// Write a single recurring [ScheduleItem] from the detected [intent]
  /// onto the user's schedules array. Used by [applyEntries] when the
  /// Lumina chat path classified the request as a routine rather than
  /// one-off date overrides.
  ///
  /// Bypasses [CalendarEntry] storage entirely — the schedules array is
  /// the long-lived recurring form, and [ScheduleItem.timeLabel] preserves
  /// symbolic "Sunset"/"Sunrise" labels that [ScheduleSyncService] honors
  /// via WLED's astronomical timer flags (hour: 24/25). Cross-path dedup
  /// against an existing autopilot-created sibling is handled by
  /// [SchedulesNotifier.mergeWithDedup]'s content-fingerprint check.
  Future<bool> _writeAsScheduleItem(RecurringIntent intent) async {
    final uid = _userId;
    if (uid == null) {
      debugPrint('❌ _writeAsScheduleItem: no userId');
      return false;
    }

    // Inline WLED payload construction. CalendarEntry has no effect field,
    // so fx: 0 (Solid) is the safest reading — the color + brightness
    // already encode the intent for the most common case (e.g. "warm
    // white every night"). Pattern-with-motion requests routinely flow
    // through the SmartScheduler path which has full effect metadata; if
    // they reach here it's a Solid-fallback degradation, not data loss.
    final color = intent.color ?? const Color(0xFFFFFFFF);
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final colRgbw = rgbToRgbw(r, g, b, forceZeroWhite: true);
    final briWled = (intent.brightness * 255 / 100).round().clamp(0, 255);
    final wledPayload = <String, dynamic>{
      'on': true,
      'bri': briWled,
      'seg': [
        {
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'col': [colRgbw],
        }
      ],
    };

    // Order repeatDays Mon-Sun for stable dedup against autopilot-written
    // siblings (SchedulesNotifier.mergeWithDedup fingerprints on repeatDays.join).
    const dayOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final repeatDaysList =
        dayOrder.where(intent.repeatDays.contains).toList();

    final timeLabel = _toScheduleTimeLabel(intent.onTime);
    final offTimeLabelRaw = _toScheduleTimeLabel(intent.offTime);
    final item = ScheduleItem(
      id: 'lumina-chat-${const Uuid().v4()}',
      timeLabel: timeLabel,
      offTimeLabel: offTimeLabelRaw.isEmpty ? null : offTimeLabelRaw,
      repeatDays: repeatDaysList,
      actionLabel: intent.patternName,
      enabled: true,
      wledPayload: wledPayload,
    );

    try {
      final beforeLen = _ref.read(schedulesProvider).length;
      await _ref.read(schedulesProvider.notifier).mergeWithDedup([item]);
      final afterLen = _ref.read(schedulesProvider).length;
      final matched = afterLen == beforeLen;
      debugPrint('[LuminaCalendar] Recurring intent → ScheduleItem. '
          '${matched ? "Existing match — skipped write" : "Wrote new ScheduleItem"} '
          '(pattern="${intent.patternName}" '
          'days=${repeatDaysList.join(",")} '
          'time="${item.timeLabel}→${item.offTimeLabel ?? "(none)"}")');
      return true;
    } catch (e) {
      debugPrint('❌ _writeAsScheduleItem: $e');
      return false;
    }
  }

  /// Prompt 4 — Option-C eviction handler. Surfaces an
  /// [EvictionRequest] to the UI listener and awaits the user's pick;
  /// on a non-null pick, runs [CalendarEntryLeaseManager.applyEvictionAndLease].
  ///
  /// Cancellation (user dismissed the picker) leaves the entry in
  /// Firestore but without a lease — debug-logged for diagnostics.
  /// The entry remains visible on the calendar; a subsequent sweep
  /// or eviction-cancellation banner (out of scope) can re-attempt.
  Future<void> _handleNoFreeSlotsForEntry({
    required CalendarEntry entry,
    required CalendarEntryLeaseManager leaseManager,
  }) async {
    final leaseUntil = leaseManager.computeLeaseExpiry(entry);
    if (leaseUntil == null) {
      debugPrint(
          'CalendarLease: noFreeSlots for ${entry.dateKey} but '
          'lease-expiry uncomputable — skipping eviction prompt');
      return;
    }
    final completer = Completer<ScheduleItem?>();
    final request = EvictionRequest(
      entry: entry,
      leaseUntil: leaseUntil,
      completer: completer,
    );
    _ref.read(pendingEvictionRequestProvider.notifier).state = request;
    ScheduleItem? choice;
    try {
      choice = await completer.future;
    } catch (e) {
      debugPrint('CalendarLease: eviction completer threw — $e');
      return;
    }
    if (choice == null) {
      debugPrint(
          'CalendarLease: User cancelled eviction for ${entry.dateKey} '
          '— entry will not fire');
      return;
    }
    try {
      final result = await leaseManager.applyEvictionAndLease(
        entry: entry,
        itemToEvict: choice,
        evictUntil: leaseUntil,
      );
      if (result.outcome == LeaseOutcome.leased ||
          result.outcome == LeaseOutcome.updated) {
        debugPrint(
            'CalendarLease: Lease created after eviction for ${entry.dateKey}');
      } else {
        debugPrint(
            'CalendarLease: applyEvictionAndLease returned ${result.outcome} '
            'for ${entry.dateKey} — eviction landed but lease failed');
      }
    } catch (e) {
      debugPrint('CalendarLease: applyEvictionAndLease threw — $e');
    }
  }

  /// Map a CalendarEntry time string ("18:00" 24-hr, or symbolic
  /// "sunset"/"sunrise") to the form [ScheduleItem.timeLabel] expects:
  /// either "h:mm AM/PM" 12-hr clock, or the capitalized symbolic strings
  /// "Sunset"/"Sunrise" that [ScheduleSyncService._buildTimerEntry]
  /// translates to WLED's hour:25 / hour:24 astronomical timer flags.
  static String _toScheduleTimeLabel(String? input) {
    if (input == null || input.isEmpty) return '';
    final lower = input.trim().toLowerCase();
    if (lower == 'sunset') return 'Sunset';
    if (lower == 'sunrise') return 'Sunrise';
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(input.trim());
    if (match != null) {
      final h24 = int.parse(match.group(1)!);
      final mm = int.parse(match.group(2)!);
      if (h24 < 0 || h24 > 23 || mm < 0 || mm > 59) return input;
      final period = h24 >= 12 ? 'PM' : 'AM';
      final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
      return '$h12:${mm.toString().padLeft(2, '0')} $period';
    }
    return input;
  }

  /// Remove a specific date override, reverting it to the autopilot/recurring
  /// fallback.  Persists to Firestore.
  Future<bool> removeEntry(String dateKey) async {
    final next = Map<String, CalendarEntry>.from(state)..remove(dateKey);
    state = next;

    // Item #61 Workstream B — release any active lease for this date.
    // Fire-and-forget; release failure is logged but never blocks the
    // Firestore delete. Runs before the uid guard so a delete made
    // while signed-out still clears the controller-side timer.
    try {
      await _ref
          .read(calendarEntryLeaseManagerProvider)
          .handleEntryDeleted(dateKey);
    } catch (e) {
      debugPrint('CalendarLease: handleEntryDeleted failed: $e');
    }

    final uid = _userId;
    if (uid == null) return false;
    try {
      final userService = _ref.read(userServiceProvider);
      final toSave = Map<String, CalendarEntry>.fromEntries(
        next.entries.where((e) => e.value.type != CalendarEntryType.holiday),
      );
      final ok = await userService.saveCalendarEntries(uid, toSave);
      if (!ok) {
        debugPrint('❌ removeEntry: Firestore write failed');
      }
      return ok;
    } catch (e) {
      debugPrint('❌ removeEntry: $e');
      return false;
    }
  }

  CalendarEntry? entryFor(String dateKey) => state[dateKey];
}

final calendarScheduleProvider =
    StateNotifierProvider<CalendarScheduleNotifier, Map<String, CalendarEntry>>(
  (ref) {
    final userId = ref.watch(authStateProvider).maybeWhen(
          data: (u) => u?.uid,
          orElse: () => null,
        );
    return CalendarScheduleNotifier(ref, userId);
  },
);

// ─── UI Navigation State ──────────────────────────────────────────────────────

/// Currently selected day in the schedule screen.
final selectedCalendarDateProvider = StateProvider<String>(
  (ref) => calendarDateKey(DateTime.now()),
);

/// Which zoom level is active: 'week' | 'month' | '3month' | '6month' | 'year'
final calendarViewModeProvider = StateProvider<String>((ref) => 'week');

// ─── Pending Changes from Lumina AI ──────────────────────────────────────────

class PendingCalendarChanges {
  final String message;
  final List<CalendarEntry> changes;
  /// When non-null, the changes array represents a single recurring intent
  /// (e.g. "warm white every night this week") and should be persisted as a
  /// ScheduleItem on the user's recurring schedules array, NOT as N
  /// CalendarEntry overrides. See [LuminaCalendarService._detectRecurringIntent]
  /// for the detection rules and [CalendarScheduleNotifier._writeAsScheduleItem]
  /// for the write path.
  final RecurringIntent? recurringIntent;
  const PendingCalendarChanges({
    required this.message,
    required this.changes,
    this.recurringIntent,
  });
}

/// A uniform recurring schedule intent inferred from a Lumina chat request.
///
/// Built by [LuminaCalendarService._detectRecurringIntent] when the parsed
/// CalendarEntry list represents a routine rather than a series of one-off
/// date overrides. Consumed by [CalendarScheduleNotifier._writeAsScheduleItem]
/// to produce a single [ScheduleItem] with the appropriate repeatDays and
/// time labels.
class RecurringIntent {
  final String patternName;
  final Color? color;
  /// Source time string from the CalendarEntry — may be a 24-hr clock string
  /// like "18:00", or the literal symbolic strings "sunset" / "sunrise".
  /// [CalendarScheduleNotifier._toScheduleTimeLabel] maps both forms to the
  /// 12-hr / capitalized form that [ScheduleItem.timeLabel] expects.
  final String? onTime;
  final String? offTime;
  /// 0–100 (matches CalendarEntry.brightness). The ScheduleItem write path
  /// scales this to the 0–255 range WLED expects.
  final int brightness;
  /// 3-letter title-case day names ('Mon', 'Tue', etc) matching the format
  /// [ScheduleItem.repeatDays] expects and the WLED timer day-of-week parser.
  final Set<String> repeatDays;
  /// Preserved for logging and any future "show what was collapsed" UI.
  final List<CalendarEntry> originalChanges;
  /// Human-readable summary of the detected pattern (e.g. "every night this
  /// week", "every weekday") for debug logs.
  final String intentSummary;

  const RecurringIntent({
    required this.patternName,
    required this.color,
    required this.onTime,
    required this.offTime,
    required this.brightness,
    required this.repeatDays,
    required this.originalChanges,
    required this.intentSummary,
  });
}

final pendingCalendarProvider =
    StateProvider<PendingCalendarChanges?>((ref) => null);

// ─── Lumina Calendar AI Service ───────────────────────────────────────────────

class LuminaCalendarService {
  LuminaCalendarService._();

  /// Format a 24-hour time string from a DateTime (e.g. "18:30").
  static String _hhmm(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Build the system instructions with dynamic sun times and timezone.
  static String _buildPrefix({
    required String sunsetTime,
    required String sunriseTime,
    required String timezone,
  }) => '''
SCHEDULE_CALENDAR_MODE — You MUST respond with ONLY a raw JSON object. No markdown fences, no explanation, no text before or after the JSON.

USER_TIMEZONE: $timezone

Required JSON format:
{
  "message": "Brief friendly confirmation (1-2 sentences max)",
  "changes": [
    {
      "date": "YYYY-MM-DD",
      "pattern": "Pattern Name",
      "color": "#RRGGBB",
      "onTime": "HH:MM",
      "offTime": "HH:MM",
      "brightness": 85
    }
  ]
}

Rules:
• YOU MUST ALWAYS include at least one entry in "changes" with a valid "date" in YYYY-MM-DD format.
• For relative dates like "next week", "this weekend", "tomorrow", etc., calculate the actual calendar dates from today's date (provided below) and list EACH date explicitly.
• "next week" means the 7 days of the following Monday–Sunday week. "nightly" or "every night" means every day in the range.
• For ranges (e.g. "every Friday in April 2026", "nightly next week"), include one entry PER matching day.
• If the request is a uniform recurring pattern (same pattern, color, and time across every matching day), you MAY additionally include a top-level field "recurringIntent": true to signal that the changes array represents a single recurring routine. This is OPTIONAL — the changes array must still be populated with one entry per matching day as above. Use "recurringIntent": true for prompts like "every night this week", "nightly through Sunday", "every weekday for the next two weeks". Do NOT use it for distinct one-offs like "blue on December 25" or "red and green on Christmas Eve".
• For "off" / "turn off": set color to null and brightness to 0.
• onTime / offTime use 24-hour format ("18:00", "23:30"). Use "sunset" or "$sunsetTime" for sunset, "sunrise" or "$sunriseTime" for sunrise. null is also valid.
• Today's sunset is $sunsetTime local clock time. Today's sunrise is $sunriseTime local clock time. Use exactly these clock-time values when the user says "sunset" or "sunrise" — DO NOT convert or adjust for timezone. The user's timezone is $timezone (informational only; the sunset and sunrise values above are already correct local clock time).
• "brightness" is 0–100.
• Common patterns and their hex colors:
    Warm White #FFE8C0 | Ocean Pulse #00C2FF | Ember Glow #FF6B35
    Aurora #9B6DFF | KC Chiefs Red #E31837 | Spring Bloom #FF9ECD
    Independence Blue #0033A0 | Harvest Moon #FF8C00
    Winter Frost #B0E0FF | FIFA Green #00A86B | Off null
• You are NOT limited to the patterns above. If the user requests a team, theme, or design not listed (e.g. "Royals", "Lakers", "patriotic"), create a descriptive pattern name and pick an appropriate hex color. For sports teams, use their official primary color.

''';

  /// Calls Lumina AI and returns structured pending calendar changes.
  /// Returns a [PendingCalendarChanges] with a user-facing error message
  /// if the request fails, or valid changes on success.
  static Future<PendingCalendarChanges?> parseRequest(
    WidgetRef ref,
    String userRequest,
  ) async {
    final today = DateTime.now();
    final todayStr = calendarDateKey(today);
    final dayStr = _dayName(today.weekday);
    final monthStr = _monthName(today.month);

    // Resolve user coordinates for sun time calculation
    final user = ref.read(currentUserProfileProvider).maybeWhen(
          data: (u) => u,
          orElse: () => null,
        );
    final lat = user?.latitude;
    final lon = user?.longitude;

    // Compute today's actual sunset/sunrise from device lat/lng
    String sunsetTime = '18:00';
    String sunriseTime = '06:30';
    if (lat != null && lon != null) {
      final sunset = SunUtils.sunsetLocal(lat, lon, today);
      final sunrise = SunUtils.sunriseLocal(lat, lon, today);
      if (sunset != null) sunsetTime = _hhmm(sunset);
      if (sunrise != null) sunriseTime = _hhmm(sunrise);
    }

    // Resolve device timezone name
    final tzOffset = today.timeZoneOffset;
    final tzName = today.timeZoneName;
    final sign = tzOffset.isNegative ? '-' : '+';
    final absHours = tzOffset.inHours.abs().toString().padLeft(2, '0');
    final absMinutes = (tzOffset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final timezone = '$tzName (UTC$sign$absHours:$absMinutes)';

    // Diagnostic trace for sunset/sunrise issues. Captures the exact values
    // substituted into the AI prompt + the device's timezone offset so
    // forensic analysis can pinpoint whether a wrong on-time came from
    // SunUtils, the prompt, or the model.
    debugPrint('📅 Astronomy: sunset=$sunsetTime sunrise=$sunriseTime tz=$timezone');
    debugPrint('📅 Device offset: ${today.timeZoneOffset} (${today.timeZoneOffset.inHours}h) zone=${today.timeZoneName}');

    final prefix = _buildPrefix(
      sunsetTime: sunsetTime,
      sunriseTime: sunriseTime,
      timezone: timezone,
    );

    final systemContext =
        '${prefix}Today is $todayStr ($dayStr, $monthStr ${today.day}, ${today.year}).';

    String raw;
    try {
      raw = await LuminaBrain.chatCalendar(
        ref,
        systemContext,
        'User schedule request: $userRequest',
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('📅 Calendar AI: Firebase error ${e.code} — ${e.message}');
      final message = switch (e.code) {
        'resource-exhausted' =>
            "You've reached the hourly AI limit. Try again in an hour.",
        'unauthenticated' =>
            'Please sign out and sign back in to use Lumina AI.',
        'internal' =>
            'Lumina is temporarily unavailable. Please try again shortly.',
        _ =>
            "Couldn't reach Lumina right now. Check your connection and try again.",
      };
      return PendingCalendarChanges(message: message, changes: const []);
    } on TimeoutException catch (e) {
      debugPrint('📅 Calendar AI: Timeout — $e');
      return PendingCalendarChanges(
        message: "Couldn't reach Lumina right now. Check your connection and try again.",
        changes: const [],
      );
    } catch (e) {
      debugPrint('📅 Calendar AI: Unexpected error — $e');
      return PendingCalendarChanges(
        message: "Couldn't reach Lumina right now. Check your connection and try again.",
        changes: const [],
      );
    }

    debugPrint('📅 Calendar AI raw response: $raw');
    return _parseAiResponse(raw);
  }

  static PendingCalendarChanges? _parseAiResponse(String raw) {
    // Strip any accidental markdown fences
    String cleaned = raw.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(cleaned);
    if (fence != null) {
      cleaned = fence.group(1)!.trim();
    } else {
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start >= 0 && end > start) {
        cleaned = cleaned.substring(start, end + 1);
      }
    }

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('📅 Calendar AI: JSON decode failed — $e\nRaw: $raw');
      return PendingCalendarChanges(
        message: 'Lumina had trouble reading that. Try rephrasing your request.',
        changes: const [],
      );
    }

    final message =
        parsed['message'] as String? ?? 'Schedule updated.';
    final rawChanges = parsed['changes'] as List<dynamic>? ?? [];

    final changes = rawChanges
        .whereType<Map<String, dynamic>>()
        .map(CalendarEntry.fromAiJson)
        .whereType<CalendarEntry>()
        .toList();

    if (changes.isEmpty) {
      return PendingCalendarChanges(
        message: 'No dates matched — did you mean this week or a specific date?',
        changes: const [],
      );
    }

    // Optional Claude hint: when the model judges the request to be a
    // uniform recurring pattern it may set top-level recurringIntent:true.
    // This lowers the detector's entry-count threshold so borderline
    // 2-entry cases collapse when the natural-language signal was strong.
    final claudeFlag = parsed['recurringIntent'] == true;
    final intent = _detectRecurringIntent(
      changes,
      claudeFlaggedRecurring: claudeFlag,
    );
    if (intent != null) {
      debugPrint('📅 LuminaCalendar: recurring intent detected '
          '(${intent.intentSummary}) — '
          'will route to ScheduleItem write on confirm');
    }
    return PendingCalendarChanges(
      message: message,
      changes: changes,
      recurringIntent: intent,
    );
  }

  /// Detects whether [changes] represents a single recurring intent
  /// (e.g. "warm white every night this week") rather than a series of
  /// distinct date overrides ("blue on December 25").
  ///
  /// Returns a [RecurringIntent] when the rules below match, or null when
  /// the entries should be written as per-day CalendarEntry overrides.
  ///
  /// Rules (evaluated in order):
  ///   1. UNIFORM CONSECUTIVE DAYS — ≥3 entries on consecutive calendar
  ///      days with identical pattern/color/time/brightness.
  ///   2. SAME-WEEKDAY REPETITION — ≥3 entries all on the same weekday
  ///      with identical fields.
  ///   3. WEEKDAY-ONLY or WEEKEND-ONLY — ≥5 entries entirely within
  ///      Mon-Fri (collapses to Mon-Fri repeat) or entirely within
  ///      Sat-Sun (collapses to Sat-Sun repeat) with identical fields.
  ///   4. FALLBACK — null.
  ///
  /// When [claudeFlaggedRecurring] is true, the minimum entry threshold
  /// for rules 1 and 2 drops to 2 — Claude's natural-language judgment
  /// lets a borderline 2-entry case collapse. Rule 3's 5-entry threshold
  /// stays put; that pattern is already strong enough not to need hints.
  static RecurringIntent? _detectRecurringIntent(
    List<CalendarEntry> entries, {
    bool claudeFlaggedRecurring = false,
  }) {
    final minEntries = claudeFlaggedRecurring ? 2 : 3;
    if (entries.length < minEntries) return null;

    // All entries must agree on the lighting payload for a collapse to
    // be safe — different colors/patterns per day means the user wanted
    // distinct one-offs, not a routine.
    final first = entries.first;
    final allIdentical = entries.every((e) =>
        e.patternName == first.patternName &&
        e.color == first.color &&
        e.onTime == first.onTime &&
        e.offTime == first.offTime &&
        e.brightness == first.brightness);
    if (!allIdentical) return null;

    // Parse dateKeys to DateTimes once and keep them sorted.
    final dated = <DateTime>[];
    for (final e in entries) {
      final d = DateTime.tryParse(e.dateKey);
      if (d == null) return null; // unparseable dateKey aborts detection
      dated.add(d);
    }
    dated.sort();

    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // RULE 0 — Trust Claude's explicit recurring flag.
    // The decomposition heuristics below require structural regularity
    // (consecutive days, same weekday, all weekdays, etc.) — but
    // "this week" or "next week" can legitimately span weekdays AND
    // weekends in any gap pattern Claude chose. When Claude explicitly
    // flagged the response as recurring AND all entries have identical
    // fields, collapse to whichever days actually appear instead of
    // insisting on structural regularity. The identical-fields invariant
    // has been enforced above before this point.
    if (claudeFlaggedRecurring) {
      final days = dated.map((d) => dayLabels[d.weekday - 1]).toSet();
      return RecurringIntent(
        patternName: first.patternName,
        color: first.color,
        onTime: first.onTime,
        offTime: first.offTime,
        brightness: first.brightness,
        repeatDays: days,
        originalChanges: entries,
        intentSummary: 'recurring on ${days.join('/')} (Claude-flagged)',
      );
    }

    // RULE 1 — consecutive days
    bool consecutive = true;
    for (int i = 1; i < dated.length; i++) {
      if (dated[i].difference(dated[i - 1]).inDays != 1) {
        consecutive = false;
        break;
      }
    }
    if (consecutive) {
      final days = dated.map((d) => dayLabels[d.weekday - 1]).toSet();
      return RecurringIntent(
        patternName: first.patternName,
        color: first.color,
        onTime: first.onTime,
        offTime: first.offTime,
        brightness: first.brightness,
        repeatDays: days,
        originalChanges: entries,
        intentSummary: '${entries.length} consecutive days',
      );
    }

    // RULE 2 — same weekday repetition
    final weekdays = dated.map((d) => d.weekday).toSet();
    if (weekdays.length == 1) {
      final dayLabel = dayLabels[weekdays.first - 1];
      return RecurringIntent(
        patternName: first.patternName,
        color: first.color,
        onTime: first.onTime,
        offTime: first.offTime,
        brightness: first.brightness,
        repeatDays: {dayLabel},
        originalChanges: entries,
        intentSummary: '${entries.length} ${dayLabel}s',
      );
    }

    // RULE 3 — weekday-only (Mon-Fri) or weekend-only (Sat-Sun), ≥5 entries
    if (entries.length >= 5) {
      const weekdayInts = {1, 2, 3, 4, 5};
      const weekendInts = {6, 7};
      final allWeekday = dated.every((d) => weekdayInts.contains(d.weekday));
      final allWeekend = dated.every((d) => weekendInts.contains(d.weekday));
      if (allWeekday) {
        return RecurringIntent(
          patternName: first.patternName,
          color: first.color,
          onTime: first.onTime,
          offTime: first.offTime,
          brightness: first.brightness,
          repeatDays: const {'Mon', 'Tue', 'Wed', 'Thu', 'Fri'},
          originalChanges: entries,
          intentSummary: 'every weekday (${entries.length} entries)',
        );
      }
      if (allWeekend) {
        return RecurringIntent(
          patternName: first.patternName,
          color: first.color,
          onTime: first.onTime,
          offTime: first.offTime,
          brightness: first.brightness,
          repeatDays: const {'Sat', 'Sun'},
          originalChanges: entries,
          intentSummary: 'every weekend (${entries.length} entries)',
        );
      }
    }

    return null;
  }
}
