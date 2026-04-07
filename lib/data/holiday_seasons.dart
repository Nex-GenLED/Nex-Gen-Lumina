// lib/data/holiday_seasons.dart
//
// Multi-day holiday season ranges (distinct from single-day CalendarEntry).
//
// CalendarEntry represents a single calendar date.  HolidaySeason represents
// a date range with a start and end — used so users can run holiday designs
// across an extended stretch (e.g. all of December for Christmas) instead
// of only on the holiday date itself.
//
// Anchor logic: most seasons resolve to a fixed (month, day) pair every
// year.  Two seasons depend on calculated dates:
//   • thanksgiving_block — anchored to the 4th Thursday of November
//   • holiday_stretch    — Thanksgiving Day through Jan 1
//   • easter_block       — Good Friday through Easter Sunday (Anonymous
//                          Gregorian algorithm)
//
// Standard Easter calculation and Thanksgiving anchoring mirror the
// algorithms in [USFederalHolidays] (lib/data/us_federal_holidays.dart).
// They are duplicated here (rather than imported) so this module stays
// free of dart:ui — usable from pure-Dart business logic, tests, or
// background isolates.

/// A holiday season with a date range, name, and optional metadata.
///
/// `start` and `end` are inclusive — `contains(date)` returns true on both
/// the start and end day.  Seasons may cross a year boundary (e.g.
/// `holiday_stretch` runs from Thanksgiving in November through Jan 1 of
/// the following year), in which case `start.year < end.year`.
class HolidaySeason {
  /// Stable machine identifier (e.g. 'christmas_season').
  final String id;

  /// User-facing name (e.g. 'Christmas Season').
  final String name;

  /// Inclusive start date.
  final DateTime start;

  /// Inclusive end date.
  final DateTime end;

  const HolidaySeason({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
  });

  /// True if [date] (compared by year/month/day only) falls within this
  /// season, inclusive of both endpoints.
  bool contains(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  /// Number of days in the season (inclusive).
  int get dayCount => end.difference(start).inDays + 1;

  @override
  String toString() =>
      'HolidaySeason($id: ${start.toIso8601String().substring(0, 10)} → '
      '${end.toIso8601String().substring(0, 10)})';
}

/// Predefined named holiday seasons. The map is rebuilt per year to keep
/// moving dates (Easter, Thanksgiving) accurate.
///
/// Keys are stable identifiers — UI labels live on the [HolidaySeason.name]
/// field.  Add or remove seasons here; do not hardcode date ranges in
/// scheduling business logic.
class HolidaySeasons {
  HolidaySeasons._();

  /// Returns the full set of named holiday seasons anchored to [year].
  ///
  /// Some seasons span a year boundary (e.g. `holiday_stretch` ends on
  /// Jan 1 of `year + 1`); these are returned with [HolidaySeason.end]
  /// set to the following year.
  static Map<String, HolidaySeason> forYear(int year) {
    // Reuse the canonical Thanksgiving anchor (4th Thursday of November)
    // and Easter calculation from USFederalHolidays so all parts of the
    // app agree on the dates.
    final thanksgiving = _nthWeekdayOfMonth(year, 11, DateTime.thursday, 4);
    final easter = _calculateEaster(year);
    final goodFriday = easter.subtract(const Duration(days: 2));
    // Sunday after Thanksgiving = Thanksgiving + 3 days (Thu→Sun).
    final sundayAfterThanksgiving =
        thanksgiving.add(const Duration(days: 3));

    return {
      'christmas_season': HolidaySeason(
        id: 'christmas_season',
        name: 'Christmas Season',
        start: DateTime(year, 12, 1),
        end: DateTime(year, 12, 31),
      ),
      'holiday_stretch': HolidaySeason(
        id: 'holiday_stretch',
        name: 'Holiday Stretch',
        start: thanksgiving,
        end: DateTime(year + 1, 1, 1),
      ),
      'halloween_season': HolidaySeason(
        id: 'halloween_season',
        name: 'Halloween Season',
        start: DateTime(year, 10, 1),
        end: DateTime(year, 10, 31),
      ),
      'independence_week': HolidaySeason(
        id: 'independence_week',
        name: 'Independence Week',
        start: DateTime(year, 7, 1),
        end: DateTime(year, 7, 7),
      ),
      'thanksgiving_block': HolidaySeason(
        id: 'thanksgiving_block',
        name: 'Thanksgiving Block',
        start: thanksgiving,
        end: sundayAfterThanksgiving,
      ),
      'new_years_eve_block': HolidaySeason(
        id: 'new_years_eve_block',
        name: "New Year's Eve Block",
        start: DateTime(year, 12, 30),
        end: DateTime(year + 1, 1, 1),
      ),
      'st_patricks_block': HolidaySeason(
        id: 'st_patricks_block',
        name: "St. Patrick's Block",
        start: DateTime(year, 3, 14),
        end: DateTime(year, 3, 17),
      ),
      'valentines_block': HolidaySeason(
        id: 'valentines_block',
        name: "Valentine's Block",
        start: DateTime(year, 2, 12),
        end: DateTime(year, 2, 14),
      ),
      'easter_block': HolidaySeason(
        id: 'easter_block',
        name: 'Easter Block',
        start: goodFriday,
        end: easter,
      ),
    };
  }

  /// Returns every season that contains [date], anchored to the appropriate
  /// year (also checks the previous year for seasons that span a year
  /// boundary, like `holiday_stretch` which ends Jan 1).
  ///
  /// Result is sorted by start date ascending — earliest-starting season
  /// first. Use [activeSeasonForDate] for the priority-resolved choice.
  static List<HolidaySeason> activeSeasonsForDate(DateTime date) {
    final out = <HolidaySeason>[];
    // Check both current and previous year so a date in early January can
    // still resolve into a season that started in November.
    final candidates = <HolidaySeason>[
      ...forYear(date.year).values,
      ...forYear(date.year - 1).values,
    ];
    for (final s in candidates) {
      if (s.contains(date)) out.add(s);
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  /// Resolution priority order when multiple seasons overlap on the same
  /// date — used by autopilot and the smart scheduler to pick a single
  /// dominant season.
  ///
  /// Tighter, more specific blocks rank higher than broad stretches so a
  /// date that falls inside both `christmas_season` and `new_years_eve_block`
  /// resolves to the New Year's block.
  static const List<String> _priorityOrder = [
    'new_years_eve_block',
    'thanksgiving_block',
    'easter_block',
    'st_patricks_block',
    'valentines_block',
    'independence_week',
    'halloween_season',
    'christmas_season',
    'holiday_stretch',
  ];

  /// Returns the single highest-priority season active on [date], or null
  /// if no season contains it.  Honors the documented priority order: tight
  /// blocks beat broad stretches when they overlap.
  static HolidaySeason? activeSeasonForDate(DateTime date) {
    final active = activeSeasonsForDate(date);
    if (active.isEmpty) return null;
    for (final id in _priorityOrder) {
      for (final season in active) {
        if (season.id == id) return season;
      }
    }
    return active.first;
  }

  /// Returns true if [date] falls inside any named holiday season.
  static bool isInAnySeason(DateTime date) =>
      activeSeasonsForDate(date).isNotEmpty;

  // ── Date-math helpers ─────────────────────────────────────────────────
  // Mirrors USFederalHolidays so this file has no Color dependency and
  // can be imported anywhere without pulling Flutter material in.

  /// Calculate the nth weekday of a month (e.g. 4th Thursday of November).
  static DateTime _nthWeekdayOfMonth(int year, int month, int weekday, int n) {
    var date = DateTime(year, month, 1);
    while (date.weekday != weekday) {
      date = date.add(const Duration(days: 1));
    }
    return date.add(Duration(days: (n - 1) * 7));
  }

  /// Calculate Easter Sunday using the Anonymous Gregorian algorithm.
  /// Works for any year in the Gregorian calendar.
  static DateTime _calculateEaster(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }
}

