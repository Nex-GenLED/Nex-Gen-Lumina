// ---------------------------------------------------------------------------
// StandardHoliday enum — major US holidays with date computation
// ---------------------------------------------------------------------------

/// Major US holidays. Each entry can compute its actual date for a given year.
enum StandardHoliday {
  newYearsDay,
  mlkDay,
  presidentsDay,
  memorialDay,
  independenceDay,
  laborDay,
  thanksgiving,
  christmasEve,
  christmasDay,
  newYearsEve,
}

extension StandardHolidayX on StandardHoliday {
  String get displayName {
    switch (this) {
      case StandardHoliday.newYearsDay:
        return "New Year's Day";
      case StandardHoliday.mlkDay:
        return 'Martin Luther King Jr. Day';
      case StandardHoliday.presidentsDay:
        return "Presidents' Day";
      case StandardHoliday.memorialDay:
        return 'Memorial Day';
      case StandardHoliday.independenceDay:
        return 'Independence Day';
      case StandardHoliday.laborDay:
        return 'Labor Day';
      case StandardHoliday.thanksgiving:
        return 'Thanksgiving';
      case StandardHoliday.christmasEve:
        return 'Christmas Eve';
      case StandardHoliday.christmasDay:
        return 'Christmas Day';
      case StandardHoliday.newYearsEve:
        return "New Year's Eve";
    }
  }

  /// Returns the exact [DateTime] this holiday falls on in [year].
  DateTime dateForYear(int year) {
    switch (this) {
      case StandardHoliday.newYearsDay:
        return DateTime(year, 1, 1);
      case StandardHoliday.mlkDay:
        // Third Monday of January.
        return _nthWeekday(year, 1, DateTime.monday, 3);
      case StandardHoliday.presidentsDay:
        // Third Monday of February.
        return _nthWeekday(year, 2, DateTime.monday, 3);
      case StandardHoliday.memorialDay:
        // Last Monday of May.
        return _lastWeekday(year, 5, DateTime.monday);
      case StandardHoliday.independenceDay:
        return DateTime(year, 7, 4);
      case StandardHoliday.laborDay:
        // First Monday of September.
        return _nthWeekday(year, 9, DateTime.monday, 1);
      case StandardHoliday.thanksgiving:
        // Fourth Thursday of November.
        return _nthWeekday(year, 11, DateTime.thursday, 4);
      case StandardHoliday.christmasEve:
        return DateTime(year, 12, 24);
      case StandardHoliday.christmasDay:
        return DateTime(year, 12, 25);
      case StandardHoliday.newYearsEve:
        return DateTime(year, 12, 31);
    }
  }

  /// The Nth occurrence of [weekday] in [month] of [year].
  static DateTime _nthWeekday(int year, int month, int weekday, int n) {
    var date = DateTime(year, month, 1);
    // Advance to the first occurrence of the target weekday.
    while (date.weekday != weekday) {
      date = date.add(const Duration(days: 1));
    }
    // Then advance (n - 1) more weeks.
    return date.add(Duration(days: 7 * (n - 1)));
  }

  /// Last occurrence of [weekday] in [month] of [year].
  static DateTime _lastWeekday(int year, int month, int weekday) {
    // Start from the last day of the month.
    var date = DateTime(year, month + 1, 0);
    while (date.weekday != weekday) {
      date = date.subtract(const Duration(days: 1));
    }
    return date;
  }
}

StandardHoliday? _parseStandardHoliday(String? key) {
  if (key == null) return null;
  for (final h in StandardHoliday.values) {
    if (h.name == key) return h;
  }
  return null;
}

// ---------------------------------------------------------------------------
// CustomClosure — ad-hoc closure date with internal reason
// ---------------------------------------------------------------------------

/// A single custom closure date (e.g. private event, renovations).
class CustomClosure {
  final DateTime date;
  final String reason;

  const CustomClosure({required this.date, required this.reason});

  factory CustomClosure.fromJson(Map<String, dynamic> json) {
    return CustomClosure(
      date: DateTime.parse(json['date'] as String),
      reason: (json['reason'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String().split('T').first,
        'reason': reason,
      };

  CustomClosure copyWith({DateTime? date, String? reason}) {
    return CustomClosure(
      date: date ?? this.date,
      reason: reason ?? this.reason,
    );
  }
}

// ---------------------------------------------------------------------------
// SpecialEvent — date range with optional schedule/design overrides
// ---------------------------------------------------------------------------

/// A special event spanning one or more days (e.g. grand opening, seasonal
/// promotion). Can override the commercial schedule and/or design.
class SpecialEvent {
  final DateTime startDate;
  final DateTime endDate;
  final String name;
  final String? customScheduleId;
  final String? designOverrideId;

  const SpecialEvent({
    required this.startDate,
    required this.endDate,
    required this.name,
    this.customScheduleId,
    this.designOverrideId,
  });

  factory SpecialEvent.fromJson(Map<String, dynamic> json) {
    return SpecialEvent(
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      name: json['name'] as String,
      customScheduleId: json['custom_schedule_id'] as String?,
      designOverrideId: json['design_override_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'start_date': startDate.toIso8601String().split('T').first,
        'end_date': endDate.toIso8601String().split('T').first,
        'name': name,
        if (customScheduleId != null) 'custom_schedule_id': customScheduleId,
        if (designOverrideId != null) 'design_override_id': designOverrideId,
      };

  SpecialEvent copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? name,
    String? customScheduleId,
    String? designOverrideId,
  }) {
    return SpecialEvent(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      name: name ?? this.name,
      customScheduleId: customScheduleId ?? this.customScheduleId,
      designOverrideId: designOverrideId ?? this.designOverrideId,
    );
  }

  /// Whether [date] falls within this event's range (inclusive).
  bool containsDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }
}

// ---------------------------------------------------------------------------
// HolidayCalendar — observed holidays, closures, and special events
// ---------------------------------------------------------------------------

/// Combines standard US holidays, custom closures, and special events into
/// a single calendar that the [BusinessHoursService] checks against.
class HolidayCalendar {
  final bool standardHolidaysEnabled;
  final List<String> observedHolidays;
  final List<CustomClosure> customClosures;
  final List<SpecialEvent> specialEvents;

  const HolidayCalendar({
    this.standardHolidaysEnabled = true,
    this.observedHolidays = const [],
    this.customClosures = const [],
    this.specialEvents = const [],
  });

  factory HolidayCalendar.fromJson(Map<String, dynamic> json) {
    return HolidayCalendar(
      standardHolidaysEnabled:
          (json['standard_holidays_enabled'] as bool?) ?? true,
      observedHolidays: (json['observed_holidays'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      customClosures: (json['custom_closures'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => CustomClosure.fromJson(e))
              .toList() ??
          const [],
      specialEvents: (json['special_events'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => SpecialEvent.fromJson(e))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'standard_holidays_enabled': standardHolidaysEnabled,
        'observed_holidays': observedHolidays,
        'custom_closures': customClosures.map((e) => e.toJson()).toList(),
        'special_events': specialEvents.map((e) => e.toJson()).toList(),
      };

  HolidayCalendar copyWith({
    bool? standardHolidaysEnabled,
    List<String>? observedHolidays,
    List<CustomClosure>? customClosures,
    List<SpecialEvent>? specialEvents,
  }) {
    return HolidayCalendar(
      standardHolidaysEnabled:
          standardHolidaysEnabled ?? this.standardHolidaysEnabled,
      observedHolidays: observedHolidays ?? this.observedHolidays,
      customClosures: customClosures ?? this.customClosures,
      specialEvents: specialEvents ?? this.specialEvents,
    );
  }

  /// Whether [date] falls on an observed standard holiday.
  bool isStandardHoliday(DateTime date) {
    if (!standardHolidaysEnabled) return false;
    for (final key in observedHolidays) {
      final holiday = _parseStandardHoliday(key);
      if (holiday == null) continue;
      final holidayDate = holiday.dateForYear(date.year);
      if (holidayDate.year == date.year &&
          holidayDate.month == date.month &&
          holidayDate.day == date.day) {
        return true;
      }
    }
    return false;
  }

  /// Whether [date] falls on a custom closure date.
  bool isCustomClosure(DateTime date) {
    for (final c in customClosures) {
      if (c.date.year == date.year &&
          c.date.month == date.month &&
          c.date.day == date.day) {
        return true;
      }
    }
    return false;
  }

  /// Whether [date] falls within any special event range.
  SpecialEvent? activeSpecialEvent(DateTime date) {
    for (final e in specialEvents) {
      if (e.containsDate(date)) return e;
    }
    return null;
  }
}
