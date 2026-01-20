import 'dart:ui';

/// US Federal Holidays with suggested lighting colors and effects.
///
/// Provides both fixed-date holidays and calculated dates for
/// holidays that fall on specific weekdays (e.g., Thanksgiving).
class USFederalHolidays {
  USFederalHolidays._();

  /// Get all federal holidays for a given year.
  static List<Holiday> getHolidaysForYear(int year) {
    return [
      // New Year's Day - January 1
      Holiday(
        name: "New Year's Day",
        date: DateTime(year, 1, 1),
        suggestedColors: [
          const Color(0xFFFFD700), // Gold
          const Color(0xFFC0C0C0), // Silver
          const Color(0xFFFFFFFF), // White
        ],
        suggestedEffectId: 74, // Fireworks
        isColorful: true,
      ),

      // Martin Luther King Jr. Day - 3rd Monday of January
      Holiday(
        name: 'Martin Luther King Jr. Day',
        date: _nthWeekdayOfMonth(year, 1, DateTime.monday, 3),
        suggestedColors: [
          const Color(0xFFFFFFFF), // White
          const Color(0xFF000080), // Navy blue
          const Color(0xFFFF0000), // Red
        ],
        suggestedEffectId: 0, // Solid
        isColorful: false, // Respectful, subtle
      ),

      // Presidents' Day - 3rd Monday of February
      Holiday(
        name: "Presidents' Day",
        date: _nthWeekdayOfMonth(year, 2, DateTime.monday, 3),
        suggestedColors: [
          const Color(0xFFFF0000), // Red
          const Color(0xFFFFFFFF), // White
          const Color(0xFF0000FF), // Blue
        ],
        suggestedEffectId: 0, // Solid
        isColorful: true,
      ),

      // Memorial Day - Last Monday of May
      Holiday(
        name: 'Memorial Day',
        date: _lastWeekdayOfMonth(year, 5, DateTime.monday),
        suggestedColors: [
          const Color(0xFFFF0000), // Red
          const Color(0xFFFFFFFF), // White
          const Color(0xFF0000FF), // Blue
        ],
        suggestedEffectId: 0, // Solid - respectful
        isColorful: false, // Subtle, respectful display
      ),

      // Juneteenth - June 19
      Holiday(
        name: 'Juneteenth',
        date: DateTime(year, 6, 19),
        suggestedColors: [
          const Color(0xFFFF0000), // Red
          const Color(0xFF00FF00), // Green
          const Color(0xFF000000), // Black (use warm white instead)
        ],
        suggestedEffectId: 0,
        isColorful: true,
      ),

      // Independence Day - July 4
      Holiday(
        name: 'Independence Day',
        date: DateTime(year, 7, 4),
        suggestedColors: [
          const Color(0xFFFF0000), // Red
          const Color(0xFFFFFFFF), // White
          const Color(0xFF0000FF), // Blue
        ],
        suggestedEffectId: 74, // Fireworks
        isColorful: true,
      ),

      // Labor Day - 1st Monday of September
      Holiday(
        name: 'Labor Day',
        date: _nthWeekdayOfMonth(year, 9, DateTime.monday, 1),
        suggestedColors: [
          const Color(0xFFFF0000), // Red
          const Color(0xFFFFFFFF), // White
          const Color(0xFF0000FF), // Blue
        ],
        suggestedEffectId: 0, // Solid
        isColorful: false, // Subtle
      ),

      // Columbus Day / Indigenous Peoples' Day - 2nd Monday of October
      Holiday(
        name: 'Columbus Day',
        date: _nthWeekdayOfMonth(year, 10, DateTime.monday, 2),
        suggestedColors: [
          const Color(0xFFFF6600), // Orange
          const Color(0xFF8B4513), // Brown
          const Color(0xFFFFD700), // Gold
        ],
        suggestedEffectId: 0,
        isColorful: true,
      ),

      // Veterans Day - November 11
      Holiday(
        name: 'Veterans Day',
        date: DateTime(year, 11, 11),
        suggestedColors: [
          const Color(0xFFFF0000), // Red
          const Color(0xFFFFFFFF), // White
          const Color(0xFF0000FF), // Blue
        ],
        suggestedEffectId: 0, // Solid - respectful
        isColorful: false, // Respectful
      ),

      // Thanksgiving - 4th Thursday of November
      Holiday(
        name: 'Thanksgiving',
        date: _nthWeekdayOfMonth(year, 11, DateTime.thursday, 4),
        suggestedColors: [
          const Color(0xFFFF6600), // Orange
          const Color(0xFFFFD700), // Gold
          const Color(0xFF8B4513), // Brown
        ],
        suggestedEffectId: 63, // Candle flicker
        isColorful: true,
      ),

      // Christmas Day - December 25
      Holiday(
        name: 'Christmas',
        date: DateTime(year, 12, 25),
        suggestedColors: [
          const Color(0xFFFF0000), // Red
          const Color(0xFF00FF00), // Green
          const Color(0xFFFFFFFF), // White
        ],
        suggestedEffectId: 12, // Chase
        isColorful: true,
      ),
    ];
  }

  /// Get popular non-federal holidays that many users celebrate.
  static List<Holiday> getPopularHolidaysForYear(int year) {
    return [
      // Valentine's Day - February 14
      Holiday(
        name: "Valentine's Day",
        date: DateTime(year, 2, 14),
        suggestedColors: [
          const Color(0xFFFF0000), // Red
          const Color(0xFFFF69B4), // Hot pink
          const Color(0xFFFFFFFF), // White
        ],
        suggestedEffectId: 82, // Heartbeat
        isColorful: true,
      ),

      // St. Patrick's Day - March 17
      Holiday(
        name: "St. Patrick's Day",
        date: DateTime(year, 3, 17),
        suggestedColors: [
          const Color(0xFF00FF00), // Green
          const Color(0xFF00AA00), // Dark green
          const Color(0xFFFFD700), // Gold
        ],
        suggestedEffectId: 12, // Chase
        isColorful: true,
      ),

      // Easter - Calculated (Sunday after first full moon after spring equinox)
      Holiday(
        name: 'Easter',
        date: _calculateEaster(year),
        suggestedColors: [
          const Color(0xFFFFB6C1), // Light pink
          const Color(0xFF87CEEB), // Sky blue
          const Color(0xFFFFFF00), // Yellow
          const Color(0xFF90EE90), // Light green
        ],
        suggestedEffectId: 52, // Rainbow
        isColorful: true,
      ),

      // Cinco de Mayo - May 5
      Holiday(
        name: 'Cinco de Mayo',
        date: DateTime(year, 5, 5),
        suggestedColors: [
          const Color(0xFF00FF00), // Green
          const Color(0xFFFFFFFF), // White
          const Color(0xFFFF0000), // Red
        ],
        suggestedEffectId: 12, // Chase
        isColorful: true,
      ),

      // Halloween - October 31
      Holiday(
        name: 'Halloween',
        date: DateTime(year, 10, 31),
        suggestedColors: [
          const Color(0xFFFF6600), // Orange
          const Color(0xFF800080), // Purple
          const Color(0xFF00FF00), // Neon green
        ],
        suggestedEffectId: 108, // Halloween eyes
        isColorful: true,
      ),

      // Hanukkah - Calculated (25th of Kislev in Hebrew calendar)
      // Approximation: usually falls in November/December
      Holiday(
        name: 'Hanukkah',
        date: _approximateHanukkah(year),
        suggestedColors: [
          const Color(0xFF0000FF), // Blue
          const Color(0xFFFFFFFF), // White
          const Color(0xFFFFD700), // Gold
        ],
        suggestedEffectId: 63, // Candle
        isColorful: true,
      ),

      // Diwali - Calculated (new moon in October/November)
      // Approximation
      Holiday(
        name: 'Diwali',
        date: _approximateDiwali(year),
        suggestedColors: [
          const Color(0xFFFFD700), // Gold
          const Color(0xFFFF6600), // Orange
          const Color(0xFFFF0000), // Red
        ],
        suggestedEffectId: 63, // Candle/diya effect
        isColorful: true,
      ),

      // New Year's Eve - December 31
      Holiday(
        name: "New Year's Eve",
        date: DateTime(year, 12, 31),
        suggestedColors: [
          const Color(0xFFFFD700), // Gold
          const Color(0xFFC0C0C0), // Silver
          const Color(0xFFFFFFFF), // White
        ],
        suggestedEffectId: 74, // Fireworks
        isColorful: true,
      ),
    ];
  }

  /// Check if a date is a federal holiday.
  static Holiday? getHolidayForDate(DateTime date) {
    final holidays = [
      ...getHolidaysForYear(date.year),
      ...getPopularHolidaysForYear(date.year),
    ];

    for (final holiday in holidays) {
      if (holiday.date.year == date.year &&
          holiday.date.month == date.month &&
          holiday.date.day == date.day) {
        return holiday;
      }
    }
    return null;
  }

  /// Get holidays in a date range.
  static List<Holiday> getHolidaysInRange(DateTime start, DateTime end) {
    final holidays = <Holiday>[];

    // Get holidays for all years in range
    for (int year = start.year; year <= end.year; year++) {
      holidays.addAll(getHolidaysForYear(year));
      holidays.addAll(getPopularHolidaysForYear(year));
    }

    // Filter to range
    return holidays.where((h) =>
        !h.date.isBefore(start) && !h.date.isAfter(end)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  /// Calculate the nth weekday of a month.
  /// e.g., 3rd Monday of January
  static DateTime _nthWeekdayOfMonth(int year, int month, int weekday, int n) {
    var date = DateTime(year, month, 1);

    // Find the first occurrence of the weekday
    while (date.weekday != weekday) {
      date = date.add(const Duration(days: 1));
    }

    // Add (n-1) weeks
    date = date.add(Duration(days: (n - 1) * 7));

    return date;
  }

  /// Calculate the last weekday of a month.
  /// e.g., Last Monday of May
  static DateTime _lastWeekdayOfMonth(int year, int month, int weekday) {
    // Start from the last day of the month
    var date = DateTime(year, month + 1, 0);

    // Go backward until we find the weekday
    while (date.weekday != weekday) {
      date = date.subtract(const Duration(days: 1));
    }

    return date;
  }

  /// Calculate Easter Sunday using the Anonymous Gregorian algorithm.
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

  /// Approximate Hanukkah start date.
  /// This is an approximation - real calculation requires Hebrew calendar.
  static DateTime _approximateHanukkah(int year) {
    // Hanukkah typically falls between late November and late December
    // This is a rough approximation based on the year
    final base = DateTime(year, 12, 1);
    final offset = (year * 11 + 14) % 30 - 15;
    return base.add(Duration(days: offset.clamp(-10, 15)));
  }

  /// Approximate Diwali date.
  /// This is an approximation - real calculation requires Hindu calendar.
  static DateTime _approximateDiwali(int year) {
    // Diwali typically falls between mid-October and mid-November
    final base = DateTime(year, 10, 28);
    final offset = (year * 11) % 30 - 15;
    return base.add(Duration(days: offset.clamp(-14, 20)));
  }
}

/// Represents a holiday with lighting suggestions.
class Holiday {
  /// Name of the holiday.
  final String name;

  /// Date of the holiday.
  final DateTime date;

  /// Suggested colors for lighting.
  final List<Color> suggestedColors;

  /// Suggested WLED effect ID.
  final int suggestedEffectId;

  /// Whether this holiday traditionally uses colorful lights.
  /// False for solemn/respectful holidays like Memorial Day, Veterans Day.
  final bool isColorful;

  const Holiday({
    required this.name,
    required this.date,
    required this.suggestedColors,
    required this.suggestedEffectId,
    required this.isColorful,
  });

  @override
  String toString() => 'Holiday($name, ${date.month}/${date.day}/${date.year})';
}
