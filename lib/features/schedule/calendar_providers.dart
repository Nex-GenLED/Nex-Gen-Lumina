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
import 'package:nexgen_command/features/schedule/schedule_conflict_detector.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_dialog.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/autopilot/autopilot_conflict_dialog.dart';
import 'package:nexgen_command/utils/sun_utils.dart';

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
  /// Returns true if the Firestore write succeeded.
  Future<bool> applyEntries(List<CalendarEntry> entries,
      {ConflictResolution? resolution}) async {
    // ── Conflict resolution (before optimistic update) ───────────
    if (resolution == ConflictResolution.cancel) return false;
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
      return ok;
    } catch (e) {
      debugPrint('❌ applyEntries: $e');
      return false;
    }
  }

  /// Remove a specific date override, reverting it to the autopilot/recurring
  /// fallback.  Persists to Firestore.
  Future<bool> removeEntry(String dateKey) async {
    final next = Map<String, CalendarEntry>.from(state)..remove(dateKey);
    state = next;

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
  const PendingCalendarChanges({required this.message, required this.changes});
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
• For "off" / "turn off": set color to null and brightness to 0.
• onTime / offTime use 24-hour format ("18:00", "23:30"). Use "sunset" or "$sunsetTime" for sunset, "sunrise" or "$sunriseTime" for sunrise. null is also valid.
• Today's sunset is $sunsetTime and sunrise is $sunriseTime in the user's timezone ($timezone). Use these exact times when the user says "sunset" or "sunrise".
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
      return PendingCalendarChanges(
        message: "Couldn't reach Lumina right now. Check your connection and try again.",
        changes: const [],
      );
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
    return PendingCalendarChanges(message: message, changes: changes);
  }
}
