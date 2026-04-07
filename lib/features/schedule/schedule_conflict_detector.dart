// lib/features/schedule/schedule_conflict_detector.dart
//
// Detects time-range overlaps between ScheduleItem (recurring) entries
// and CalendarEntry (date-specific) entries.
//
// Conflict rules:
//   1. Two ScheduleItems conflict iff their time windows overlap on a
//      shared day-of-week.
//   2. A CalendarEntry conflicts with a ScheduleItem iff the entry's
//      specific date falls on a day-of-week the ScheduleItem runs AND
//      their time windows overlap on that date.
//   3. Two CalendarEntries on different dates NEVER conflict — different
//      days, by definition no overlap.

import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

/// Result of a full-system conflict scan: which ScheduleItems and
/// CalendarEntries are participants in at least one genuine conflict.
class ScheduleConflicts {
  final Set<String> itemIds;
  final Set<String> entryKeys;
  const ScheduleConflicts({
    required this.itemIds,
    required this.entryKeys,
  });

  bool get isEmpty => itemIds.isEmpty && entryKeys.isEmpty;
  bool get isNotEmpty => !isEmpty;
  int get totalCount => itemIds.length + entryKeys.length;
}

class ScheduleConflictDetector {
  ScheduleConflictDetector._();

  // ── Day abbreviation mapping ────────────────────────────────────────────────
  // Dart DateTime.weekday: 1=Mon … 7=Sun
  // ScheduleItem.repeatDays uses: "Sun","Mon","Tue","Wed","Thu","Fri","Sat"

  static const _weekdayAbbrs = {
    1: 'mon',
    2: 'tue',
    3: 'wed',
    4: 'thu',
    5: 'fri',
    6: 'sat',
    7: 'sun',
  };

  // ── Recurring vs Recurring ──────────────────────────────────────────────────

  /// Find [ScheduleItem]s in [existing] whose time window and repeat days
  /// overlap with [incoming].  Pass [excludeId] when editing an existing
  /// schedule so it doesn't conflict with itself.
  static List<ScheduleItem> findItemConflicts({
    required ScheduleItem incoming,
    required List<ScheduleItem> existing,
    String? excludeId,
  }) {
    final inOn = _parseToMinutes(incoming.timeLabel);
    // If no parseable on-time (Sunset/Sunrise), we can't do static overlap.
    if (inOn == null) return [];

    final inOff = incoming.offTimeLabel != null
        ? _parseToMinutes(incoming.offTimeLabel!)
        : null;

    final conflicts = <ScheduleItem>[];

    for (final other in existing) {
      if (!other.enabled) continue;
      if (other.id == excludeId) continue;

      // Days must overlap
      if (!_daysOverlap(incoming.repeatDays, other.repeatDays)) continue;

      final otherOn = _parseToMinutes(other.timeLabel);
      if (otherOn == null) continue; // Sunset/Sunrise — skip

      final otherOff = other.offTimeLabel != null
          ? _parseToMinutes(other.offTimeLabel!)
          : null;

      if (_windowsOverlap(inOn, inOff, otherOn, otherOff)) {
        conflicts.add(other);
      }
    }
    return conflicts;
  }

  // ── Date-specific vs Recurring ──────────────────────────────────────────────

  /// Returns [ScheduleItem]s from [recurringItems] that overlap with [entry]
  /// on the given [entryDate].
  static List<ScheduleItem> findItemConflictsForEntry({
    required CalendarEntry entry,
    required DateTime entryDate,
    required List<ScheduleItem> recurringItems,
  }) {
    final entryOn = entry.onTime != null
        ? _parse24hrToMinutes(entry.onTime!)
        : null;
    final entryOff = entry.offTime != null
        ? _parse24hrToMinutes(entry.offTime!)
        : null;

    // If the calendar entry has no parseable on-time we can't check overlap.
    if (entryOn == null) return [];

    final weekday = entryDate.weekday; // 1=Mon…7=Sun

    final conflicts = <ScheduleItem>[];

    for (final item in recurringItems) {
      if (!item.enabled) continue;
      if (!_itemCoversWeekday(item, weekday)) continue;

      final itemOn = _parseToMinutes(item.timeLabel);
      if (itemOn == null) continue; // Sunset/Sunrise — skip

      final itemOff = item.offTimeLabel != null
          ? _parseToMinutes(item.offTimeLabel!)
          : null;

      if (_windowsOverlap(entryOn, entryOff, itemOn, itemOff)) {
        conflicts.add(item);
      }
    }
    return conflicts;
  }

  /// Returns dateKeys of [CalendarEntry] entries that overlap with [item]
  /// across the next [lookAheadDays] days starting from today.
  static List<String> findEntryConflictsForItem({
    required ScheduleItem item,
    required Map<String, CalendarEntry> calendarEntries,
    int lookAheadDays = 60,
  }) {
    if (!item.enabled) return [];

    final itemOn = _parseToMinutes(item.timeLabel);
    if (itemOn == null) return []; // Sunset/Sunrise — skip

    final itemOff = item.offTimeLabel != null
        ? _parseToMinutes(item.offTimeLabel!)
        : null;

    final today = DateTime.now();
    final conflicting = <String>[];

    for (int d = 0; d < lookAheadDays; d++) {
      final date = today.add(Duration(days: d));
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      if (!_itemCoversWeekday(item, date.weekday)) continue;

      final entry = calendarEntries[key];
      if (entry == null) continue;

      final entryOn = entry.onTime != null
          ? _parse24hrToMinutes(entry.onTime!)
          : null;
      if (entryOn == null) continue;

      final entryOff = entry.offTime != null
          ? _parse24hrToMinutes(entry.offTime!)
          : null;

      if (_windowsOverlap(itemOn, itemOff, entryOn, entryOff)) {
        conflicting.add(key);
      }
    }
    return conflicting;
  }

  // ── Full-system scan ────────────────────────────────────────────────────────

  /// Compute the full set of conflicting [ScheduleItem] IDs and
  /// [CalendarEntry] dateKeys across the entire schedule system.
  ///
  /// Used by the overload banner and cleanup sheet to decide what (if
  /// anything) actually needs the user's attention.
  ///
  /// Honors the three rules at the top of this file: CalendarEntries are
  /// only flagged when they overlap a recurring ScheduleItem on their
  /// specific date.  CalendarEntries on different dates never conflict
  /// with each other regardless of how many exist.
  static ScheduleConflicts computeAllConflicts({
    required List<ScheduleItem> schedules,
    required Map<String, CalendarEntry> calendarEntries,
  }) {
    final enabled = schedules.where((s) => s.enabled).toList();
    final conflictingItemIds = <String>{};
    final conflictingEntryKeys = <String>{};

    // Recurring vs recurring
    for (final item in enabled) {
      final conflicts = findItemConflicts(
        incoming: item,
        existing: enabled,
        excludeId: item.id,
      );
      if (conflicts.isNotEmpty) {
        conflictingItemIds.add(item.id);
        for (final c in conflicts) {
          conflictingItemIds.add(c.id);
        }
      }
    }

    // Date-specific vs recurring (date-by-date — entries on different
    // dates can never conflict with each other)
    for (final entry in calendarEntries.entries) {
      final date = DateTime.tryParse(entry.key);
      if (date == null) continue;
      final conflicts = findItemConflictsForEntry(
        entry: entry.value,
        entryDate: date,
        recurringItems: enabled,
      );
      if (conflicts.isNotEmpty) {
        conflictingEntryKeys.add(entry.key);
        for (final c in conflicts) {
          conflictingItemIds.add(c.id);
        }
      }
    }

    return ScheduleConflicts(
      itemIds: conflictingItemIds,
      entryKeys: conflictingEntryKeys,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  /// Parse a ScheduleItem 12-hour time label ("7:00 PM") to minutes since
  /// midnight (0–1439).  Returns null for "Sunset", "Sunrise", or anything
  /// that doesn't match the `H:MM AM/PM` pattern.
  ///
  /// Mirrors the regex in [ScheduleFinder._parseTimeLabel] without needing
  /// a reference DateTime or lat/lon.
  static int? _parseToMinutes(String timeLabel) {
    final trimmed = timeLabel.trim().toLowerCase();

    // Solar events cannot be resolved to a fixed minute value.
    if (trimmed == 'sunset' || trimmed == 'sunrise') return null;

    final re =
        RegExp(r'^(\d{1,2}):(\d{2})\s*(am|pm)$', caseSensitive: false);
    final m = re.firstMatch(timeLabel.trim());
    if (m == null) return null;

    var hour = int.tryParse(m.group(1)!) ?? 0;
    final minute = int.tryParse(m.group(2)!) ?? 0;
    final ampm = m.group(3)!.toLowerCase();

    if (ampm == 'pm' && hour != 12) hour += 12;
    if (ampm == 'am' && hour == 12) hour = 0;

    return hour * 60 + minute;
  }

  /// Parse a CalendarEntry 24-hour time string ("19:00") to minutes since
  /// midnight.  Returns null if the format doesn't match `HH:MM`.
  static int? _parse24hrToMinutes(String time24) {
    final parts = time24.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  /// Returns true if two time windows overlap.
  ///
  /// Each window is defined by an on-time and an optional off-time (all in
  /// minutes since midnight, 0–1439).  When [off] is null the window is
  /// treated as a point (zero-length); when [off] < [on] the window wraps
  /// past midnight (overnight schedule).
  ///
  /// Adjacent windows (one ends exactly when the other starts) are NOT
  /// considered a conflict.
  static bool _windowsOverlap(int on1, int? off1, int on2, int? off2) {
    // Expand each window into a list of linear (non-wrapping) ranges.
    final ranges1 = _linearRanges(on1, off1);
    final ranges2 = _linearRanges(on2, off2);

    for (final r1 in ranges1) {
      for (final r2 in ranges2) {
        if (_minuteRangesOverlap(r1.$1, r1.$2, r2.$1, r2.$2)) return true;
      }
    }
    return false;
  }

  /// Convert an on/off pair into one or two non-wrapping (start, end) ranges.
  ///
  /// - No off time → [on, 1440) — runs until end of day (indefinite / "always on").
  /// - off > on → single range [on, off).
  /// - off <= on → overnight wrap → two ranges: [on, 1440) and [0, off).
  static List<(int, int)> _linearRanges(int on, int? off) {
    if (off == null) return [(on, 1440)];
    if (off > on) return [(on, off)];
    // Overnight: wraps past midnight.
    return [(on, 1440), (0, off)];
  }

  /// Returns true if the open ranges [s1,e1) and [s2,e2) overlap.
  /// Adjacent ranges (e1 == s2) do NOT overlap.
  static bool _minuteRangesOverlap(int s1, int e1, int s2, int e2) {
    return s1 < e2 && s2 < e1;
  }

  /// Returns true if [item]'s repeat days include the given [weekday]
  /// (Dart convention: 1=Monday … 7=Sunday).
  static bool _itemCoversWeekday(ScheduleItem item, int weekday) {
    final target = _weekdayAbbrs[weekday]!;
    final daysLower = item.repeatDays.map((d) => d.toLowerCase()).toList();
    if (daysLower.contains('daily')) return true;
    return daysLower.any((d) => d.startsWith(target));
  }

  /// Returns true if [days1] and [days2] share at least one common day.
  /// "Daily" matches all days.
  static bool _daysOverlap(List<String> days1, List<String> days2) {
    final a = days1.map((d) => d.toLowerCase()).toSet();
    final b = days2.map((d) => d.toLowerCase()).toSet();

    if (a.contains('daily') || b.contains('daily')) return true;

    // Normalize: each entry may be a full name or 3-letter abbreviation.
    // ScheduleItem uses 3-letter ("Mon", "Tue", …).  Use startsWith matching
    // consistent with ScheduleFinder.appliesToDay().
    for (final d1 in a) {
      for (final d2 in b) {
        if (d1.startsWith(d2) || d2.startsWith(d1)) return true;
      }
    }
    return false;
  }
}
