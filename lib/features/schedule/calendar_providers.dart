// lib/features/schedule/calendar_providers.dart
//
// State management for date-specific calendar schedule entries.
// Provides the CalendarScheduleNotifier, pending-changes state,
// and the LuminaCalendarService that calls the Anthropic API.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';

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
  CalendarScheduleNotifier() : super(_buildHolidayDefaults());

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

  /// Apply a list of date-specific entries, overwriting any existing
  /// entries for those dates.
  void applyEntries(List<CalendarEntry> entries) {
    final next = Map<String, CalendarEntry>.from(state);
    for (final e in entries) {
      next[e.dateKey] = e;
    }
    state = next;
  }

  /// Remove a specific date override, reverting it to the autopilot/recurring
  /// fallback.
  void removeEntry(String dateKey) {
    final next = Map<String, CalendarEntry>.from(state)..remove(dateKey);
    state = next;
  }

  CalendarEntry? entryFor(String dateKey) => state[dateKey];
}

final calendarScheduleProvider =
    StateNotifierProvider<CalendarScheduleNotifier, Map<String, CalendarEntry>>(
  (ref) => CalendarScheduleNotifier(),
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

  // Inline system instructions sent as part of the user message so that
  // LuminaBrain's own system prompt doesn't conflict.
  static const _prefix = '''
SCHEDULE_CALENDAR_MODE — You MUST respond with ONLY a raw JSON object. No markdown fences, no explanation, no text before or after the JSON.

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
• For ranges (e.g. "every Friday in April"), include one entry per matching day.
• For "off" / "turn off": set color to null and brightness to 0.
• onTime / offTime use 24-hour format ("18:00", "23:30"). null is valid.
• "brightness" is 0–100.
• Available patterns and their hex colors:
    Warm White #FFE8C0 | Ocean Pulse #00C2FF | Ember Glow #FF6B35
    Aurora #9B6DFF | KC Chiefs Red #E31837 | Spring Bloom #FF9ECD
    Independence Blue #0033A0 | Harvest Moon #FF8C00
    Winter Frost #B0E0FF | FIFA Green #00A86B | Off null

''';

  /// Calls Lumina AI and returns structured pending calendar changes.
  /// Returns null if the response cannot be parsed into valid date entries.
  static Future<PendingCalendarChanges?> parseRequest(
    WidgetRef ref,
    String userRequest,
  ) async {
    final today = DateTime.now();
    final todayStr = calendarDateKey(today);
    final dayStr = _dayName(today.weekday);
    final monthStr = _monthName(today.month);

    final systemContext =
        '${_prefix}Today is $todayStr ($dayStr, $monthStr ${today.day}, ${today.year}).';

    final raw = await LuminaBrain.chatCalendar(
      ref,
      systemContext,
      'User schedule request: $userRequest',
    );

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
    } catch (_) {
      return null;
    }

    final message =
        parsed['message'] as String? ?? 'Schedule updated.';
    final rawChanges = parsed['changes'] as List<dynamic>? ?? [];

    final changes = rawChanges
        .whereType<Map<String, dynamic>>()
        .map(CalendarEntry.fromAiJson)
        .whereType<CalendarEntry>()
        .toList();

    if (changes.isEmpty) return null;
    return PendingCalendarChanges(message: message, changes: changes);
  }
}
