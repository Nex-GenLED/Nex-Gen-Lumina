import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// What kind of time trigger starts or ends a lighting schedule.
enum TimeTrigger {
  sunset,
  sunrise,
  dusk,
  dawn,
  specificTime, // e.g., "at 8pm" — requires further parsing
  allDay,       // No time constraint specified
}

/// How often the lighting should repeat.
enum RecurrenceType {
  once,       // "tonight"
  daily,      // "every night this week"
  weekdays,   // "weeknights"
  weekends,   // "this weekend"
  custom,     // Specific days named
}

/// The parsed temporal portion of a compound command.
class TemporalIntent {
  final RecurrenceType recurrence;
  final TimeTrigger startTrigger;
  final TimeTrigger endTrigger;

  /// Total number of occurrences to schedule.
  final int dayCount;

  /// ISO weekday numbers for custom recurrence (1=Mon … 7=Sun). Empty = all.
  final List<int> weekdays;

  /// Parsed clock-time start hour (24h format), or null if not specified.
  /// e.g., "from 7pm" → 19, "from 7-10pm" → 19
  final int? startHour;

  /// Parsed clock-time end hour (24h format), or null if not specified.
  /// e.g., "to 10pm" → 22, "until midnight" → 0
  final int? endHour;

  /// Resolved start date for a date-range command, or null if not specified.
  /// e.g., "starting Monday" → next Monday, "starting April 5th" → April 5.
  final DateTime? startDate;

  /// Resolved end date for a date-range command, or null if not specified.
  /// e.g., "through Friday" → next Friday, "through April 12th" → April 12.
  final DateTime? endDate;

  const TemporalIntent({
    required this.recurrence,
    required this.startTrigger,
    required this.endTrigger,
    required this.dayCount,
    this.weekdays = const [],
    this.startHour,
    this.endHour,
    this.startDate,
    this.endDate,
  });

  bool get usesSunsetSunrise =>
      startTrigger == TimeTrigger.sunset || endTrigger == TimeTrigger.sunrise;

  bool get usesDuskDawn =>
      startTrigger == TimeTrigger.dusk || endTrigger == TimeTrigger.dawn;

  /// Whether specific clock hours were parsed from the user's request.
  bool get hasClockTime => startHour != null || endHour != null;

  /// Whether a specific date range was parsed from the user's request.
  bool get hasDateRange => startDate != null && endDate != null;

  /// Human-readable date range string for prompt injection.
  String get dateRangeLabel {
    if (startDate == null || endDate == null) return '';
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    String fmt(DateTime d) => '${months[d.month]} ${d.day}';
    return 'from ${fmt(startDate!)} through ${fmt(endDate!)}';
  }

  /// Human-readable time window string for prompt injection.
  String get timeWindowLabel {
    if (startHour != null && endHour != null) {
      return 'from ${_formatHour(startHour!)} to ${_formatHour(endHour!)}';
    } else if (startHour != null) {
      return 'starting at ${_formatHour(startHour!)}';
    } else if (endHour != null) {
      return 'until ${_formatHour(endHour!)}';
    }
    return '';
  }

  static String _formatHour(int h) {
    if (h == 0 || h == 24) return '12am';
    if (h == 12) return '12pm';
    return h > 12 ? '${h - 12}pm' : '${h}am';
  }

  @override
  String toString() =>
      'TemporalIntent(recurrence=${recurrence.name}, days=$dayCount, '
      'start=${startTrigger.name}, end=${endTrigger.name}'
      '${startHour != null ? ", startHour=$startHour" : ""}'
      '${endHour != null ? ", endHour=$endHour" : ""}'
      '${startDate != null ? ", startDate=$startDate" : ""}'
      '${endDate != null ? ", endDate=$endDate" : ""})';
}

/// The result of detecting a compound (lighting + scheduling) command.
///
/// Example input:  "Give me a Royals design every night this week from sunset to sunrise"
/// Example output: lightingIntent = "Royals design"
///                 temporal = TemporalIntent(daily, 7, sunset→sunrise)
class CompoundCommandResult {
  /// Pure lighting intent with temporal language stripped.
  /// e.g., "Royals design", "blue and gold", "Christmas theme"
  final String lightingIntent;

  /// Temporal component, or null if no scheduling intent was found.
  final TemporalIntent? temporal;

  /// True when both a lighting AND scheduling intent were detected.
  final bool isCompound;

  const CompoundCommandResult({
    required this.lightingIntent,
    this.temporal,
    required this.isCompound,
  });

  @override
  String toString() =>
      'CompoundCommand(isCompound=$isCompound, lighting="$lightingIntent", temporal=$temporal)';
}

// ---------------------------------------------------------------------------
// Detector
// ---------------------------------------------------------------------------

/// Detects and splits compound voice/text commands that combine a lighting
/// request with a scheduling/temporal request.
///
/// Handles patterns like:
///   "Royals design every night this week from sunset to sunrise"
///   "Blue and gold all week"
///   "Christmas lights this weekend at dusk"
///   "Patriots colors tonight"
///   "Give me a party theme for the next 5 days"
class CompoundCommandDetector {
  CompoundCommandDetector._();

  // -----------------------------------------------------------------------
  // Recurrence patterns
  // -----------------------------------------------------------------------

  static final _thisWeekPattern = RegExp(
    r'\b(every\s+night\s+this\s+week|all\s+week(\s+long)?|this\s+week|'
    r'for\s+the\s+(rest\s+of\s+the\s+)?week|'
    r'every\s+(night|evening|day)(\s+this\s+week)?)\b',
    caseSensitive: false,
  );

  static final _nextNDaysPattern = RegExp(
    r'\b(for\s+the\s+next|next)\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+days?\b',
    caseSensitive: false,
  );

  static final _weekendsPattern = RegExp(
    r'\b(this\s+weekend|all\s+weekend|saturday\s+and\s+sunday|'
    r'weekends?)\b',
    caseSensitive: false,
  );

  static final _weekdaysPattern = RegExp(
    r'\b(weeknights?|weekdays?|monday\s+through\s+friday|mon[\s-]+fri)\b',
    caseSensitive: false,
  );

  static final _tonightPattern = RegExp(
    r'\b(tonight|this\s+evening|this\s+night)\b',
    caseSensitive: false,
  );

  // -----------------------------------------------------------------------
  // Time trigger patterns
  // -----------------------------------------------------------------------

  static final _sunsetPattern =
      RegExp(r'\b(at\s+)?sunset\b', caseSensitive: false);
  static final _sunrisePattern =
      RegExp(r'\b(at\s+)?sunrise\b', caseSensitive: false);
  static final _duskPattern =
      RegExp(r'\b(at\s+)?dusk\b', caseSensitive: false);
  static final _dawnPattern =
      RegExp(r'\b(at\s+)?dawn\b', caseSensitive: false);

  /// Captures "from X to Y" pairs to detect start/end triggers together.
  static final _fromToPattern = RegExp(
    r'\bfrom\s+(\w+(?:\s+\w+)?)\s+to\s+(\w+(?:\s+\w+)?)\b',
    caseSensitive: false,
  );

  /// Clock time patterns — "from 7-10pm", "from 7pm to 10pm", "at 8pm",
  /// "until midnight", "7:30pm-10pm", etc.
  static final _clockTimeRangePattern = RegExp(
    r'\bfrom\s+(\d{1,2})(?::(\d{2}))?\s*([ap]m)?\s*[-–to]+\s*(\d{1,2})(?::(\d{2}))?\s*([ap]m)\b',
    caseSensitive: false,
  );
  static final _clockTimeAtPattern = RegExp(
    r'\bat\s+(\d{1,2})(?::(\d{2}))?\s*([ap]m)\b',
    caseSensitive: false,
  );
  static final _clockTimeUntilPattern = RegExp(
    r'\b(?:until|till|til)\s+(\d{1,2})(?::(\d{2}))?\s*([ap]m)\b',
    caseSensitive: false,
  );
  static final _midnightPattern = RegExp(
    r'\b(?:until|till|til)\s+midnight\b',
    caseSensitive: false,
  );

  // -----------------------------------------------------------------------
  // Date range patterns
  // -----------------------------------------------------------------------

  /// Captures "starting X through Y" date range expressions.
  /// X and Y can be day names, "today"/"tomorrow", or "Month Day" forms.
  static final _dateRangePattern = RegExp(
    r'\bstarting\s+(\w+(?:\s+\d{1,2}(?:st|nd|rd|th)?)?)\s+through\s+(\w+(?:\s+\d{1,2}(?:st|nd|rd|th)?)?)\b',
    caseSensitive: false,
  );

  // -----------------------------------------------------------------------
  // Strip patterns — temporal language removed to isolate lighting intent
  // -----------------------------------------------------------------------

  static final _temporalStripPattern = RegExp(
    r'\b('
    r'every\s+night(\s+this\s+week)?|every\s+day(\s+this\s+week)?|'
    r'every\s+evening|all\s+week(\s+long)?|this\s+week|'
    r'for\s+the\s+(rest\s+of\s+the\s+)?week|this\s+weekend|'
    r'all\s+weekend|for\s+the\s+next\s+\d+\s+days?|'
    r'next\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d+)\s+days?|'
    r'tonight|this\s+evening|this\s+night|'
    r'from\s+sunset(\s+to\s+sunrise)?|from\s+dusk(\s+to\s+dawn)?|'
    r'sunset\s+to\s+sunrise|dusk\s+to\s+dawn|'
    r'at\s+sunset|at\s+sunrise|at\s+dusk|at\s+dawn|'
    r'sunrise|sunset|dusk|dawn|'
    r'weeknights?|weekdays?|weekends?|'
    r'from\s+\d{1,2}(?::\d{2})?\s*[ap]m?\s*[-–to]+\s*\d{1,2}(?::\d{2})?\s*[ap]m|'
    r'at\s+\d{1,2}(?::\d{2})?\s*[ap]m|'
    r'(?:until|till|til)\s+\d{1,2}(?::\d{2})?\s*[ap]m|'
    r'(?:until|till|til)\s+midnight|'
    r'starting\s+\w+(?:\s+\d{1,2}(?:st|nd|rd|th)?)?\s+through\s+\w+(?:\s+\d{1,2}(?:st|nd|rd|th)?)?'
    r')\b',
    caseSensitive: false,
  );

  // Connector / filler words to clean up after stripping
  static final _fillerPattern = RegExp(
    r'\b(for\s+me|give\s+me\s+(a\s+)?|set\s+up\s+(a\s+)?|schedule\s+(a\s+)?|'
    r"can\s+you\s+|please\s+|i\s+want\s+(a\s+)?|i'd\s+like\s+(a\s+)?)\b",
    caseSensitive: false,
  );

  // -----------------------------------------------------------------------
  // Main entry point
  // -----------------------------------------------------------------------

  /// Detect if [input] is a compound lighting+scheduling command.
  ///
  /// Returns a [CompoundCommandResult] regardless — check [isCompound]
  /// to determine whether a schedule was detected.
  static CompoundCommandResult detect(String input) {
    final lower = input.toLowerCase();

    final hasTemporalSignal = _dateRangePattern.hasMatch(lower) ||
        _thisWeekPattern.hasMatch(lower) ||
        _nextNDaysPattern.hasMatch(lower) ||
        _weekendsPattern.hasMatch(lower) ||
        _weekdaysPattern.hasMatch(lower) ||
        _tonightPattern.hasMatch(lower) ||
        _sunsetPattern.hasMatch(lower) ||
        _duskPattern.hasMatch(lower) ||
        _clockTimeRangePattern.hasMatch(lower) ||
        _clockTimeAtPattern.hasMatch(lower) ||
        _clockTimeUntilPattern.hasMatch(lower) ||
        _midnightPattern.hasMatch(lower);

    if (!hasTemporalSignal) {
      return CompoundCommandResult(
        lightingIntent: input.trim(),
        isCompound: false,
      );
    }

    final temporal = _parseTemporalIntent(lower);
    final lightingIntent = _extractLightingIntent(input);

    // If nothing meaningful remains after stripping, keep original
    final effectiveLighting =
        lightingIntent.trim().isEmpty ? input.trim() : lightingIntent.trim();

    debugPrint(
        '🗓️ CompoundCommand: lighting="$effectiveLighting" | temporal=$temporal');

    return CompoundCommandResult(
      lightingIntent: effectiveLighting,
      temporal: temporal,
      isCompound: effectiveLighting != input.trim(),
    );
  }

  // -----------------------------------------------------------------------
  // Internal parsers
  // -----------------------------------------------------------------------

  static TemporalIntent _parseTemporalIntent(String lower) {
    RecurrenceType recurrence;
    int dayCount;
    List<int> weekdays = [];
    DateTime? startDate;
    DateTime? endDate;

    // Check "starting X through Y" date range first — it takes priority
    // over general recurrence patterns since it carries explicit bounds.
    final dateRangeMatch = _dateRangePattern.firstMatch(lower);
    if (dateRangeMatch != null) {
      final rawStart = dateRangeMatch.group(1) ?? '';
      final rawEnd = dateRangeMatch.group(2) ?? '';
      startDate = resolveDate(rawStart);
      endDate = (startDate != null)
          ? resolveDate(rawEnd, onOrAfter: startDate)
          : resolveDate(rawEnd);
      if (startDate != null && endDate != null) {
        dayCount = endDate.difference(startDate).inDays + 1;
        recurrence = dayCount == 1 ? RecurrenceType.once : RecurrenceType.daily;
      } else {
        // Fallback if date resolution fails
        recurrence = RecurrenceType.once;
        dayCount = 1;
      }
    } else if (_weekendsPattern.hasMatch(lower)) {
      recurrence = RecurrenceType.weekends;
      dayCount = 2;
      weekdays = [6, 7];
    } else if (_weekdaysPattern.hasMatch(lower)) {
      recurrence = RecurrenceType.weekdays;
      dayCount = 5;
      weekdays = [1, 2, 3, 4, 5];
    } else if (_tonightPattern.hasMatch(lower)) {
      recurrence = RecurrenceType.once;
      dayCount = 1;
    } else if (_thisWeekPattern.hasMatch(lower)) {
      recurrence = RecurrenceType.daily;
      dayCount = 7;
    } else {
      final ndMatch = _nextNDaysPattern.firstMatch(lower);
      if (ndMatch != null) {
        final numWord = ndMatch.group(2) ?? '7';
        dayCount = _wordToInt(numWord);
        recurrence = RecurrenceType.daily;
      } else {
        recurrence = RecurrenceType.once;
        dayCount = 1;
      }
    }

    // Parse time triggers
    TimeTrigger startTrigger = TimeTrigger.allDay;
    TimeTrigger endTrigger = TimeTrigger.allDay;

    final fromToMatch = _fromToPattern.firstMatch(lower);
    if (fromToMatch != null) {
      startTrigger = _parseTrigger(fromToMatch.group(1) ?? '');
      endTrigger = _parseTrigger(fromToMatch.group(2) ?? '');
    } else {
      if (_sunsetPattern.hasMatch(lower)) startTrigger = TimeTrigger.sunset;
      if (_duskPattern.hasMatch(lower)) startTrigger = TimeTrigger.dusk;
      if (_sunrisePattern.hasMatch(lower)) endTrigger = TimeTrigger.sunrise;
      if (_dawnPattern.hasMatch(lower)) endTrigger = TimeTrigger.dawn;
    }

    // Parse specific clock times ("from 7-10pm", "at 8pm", "until midnight")
    int? startHour;
    int? endHour;

    final clockRange = _clockTimeRangePattern.firstMatch(lower);
    if (clockRange != null) {
      final sh = int.tryParse(clockRange.group(1) ?? '');
      final sAmPm = clockRange.group(3)?.toLowerCase() ?? clockRange.group(6)?.toLowerCase();
      final eh = int.tryParse(clockRange.group(4) ?? '');
      final eAmPm = clockRange.group(6)?.toLowerCase();

      if (sh != null) startHour = _to24Hour(sh, sAmPm ?? eAmPm ?? 'pm');
      if (eh != null) endHour = _to24Hour(eh, eAmPm ?? 'pm');

      startTrigger = TimeTrigger.specificTime;
      endTrigger = TimeTrigger.specificTime;
    } else if (_midnightPattern.hasMatch(lower)) {
      endHour = 0;
      endTrigger = TimeTrigger.specificTime;
    } else {
      final atMatch = _clockTimeAtPattern.firstMatch(lower);
      if (atMatch != null) {
        final h = int.tryParse(atMatch.group(1) ?? '');
        final ampm = atMatch.group(3)?.toLowerCase() ?? 'pm';
        if (h != null) {
          startHour = _to24Hour(h, ampm);
          startTrigger = TimeTrigger.specificTime;
        }
      }
      final untilMatch = _clockTimeUntilPattern.firstMatch(lower);
      if (untilMatch != null) {
        final h = int.tryParse(untilMatch.group(1) ?? '');
        final ampm = untilMatch.group(3)?.toLowerCase() ?? 'pm';
        if (h != null) {
          endHour = _to24Hour(h, ampm);
          endTrigger = TimeTrigger.specificTime;
        }
      }
    }

    return TemporalIntent(
      recurrence: recurrence,
      startTrigger: startTrigger,
      endTrigger: endTrigger,
      dayCount: dayCount,
      weekdays: weekdays,
      startHour: startHour,
      endHour: endHour,
      startDate: startDate,
      endDate: endDate,
    );
  }

  static TimeTrigger _parseTrigger(String text) {
    final t = text.trim().toLowerCase();
    if (t.contains('sunset')) return TimeTrigger.sunset;
    if (t.contains('sunrise')) return TimeTrigger.sunrise;
    if (t.contains('dusk')) return TimeTrigger.dusk;
    if (t.contains('dawn')) return TimeTrigger.dawn;
    return TimeTrigger.specificTime;
  }

  static String _extractLightingIntent(String original) {
    var result = original;

    // Strip temporal language
    result = result.replaceAll(_temporalStripPattern, ' ');
    // Strip filler/connector phrases
    result = result.replaceAll(_fillerPattern, ' ');
    // Collapse whitespace
    result = result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    // Strip leading articles
    result = result.replaceAll(RegExp(r'^(a|an|the)\s+', caseSensitive: false), '');

    return result.trim();
  }

  /// Convert 12-hour time to 24-hour. e.g., (7, "pm") → 19, (12, "am") → 0
  static int _to24Hour(int hour, String amPm) {
    if (amPm == 'am') {
      return hour == 12 ? 0 : hour;
    } else {
      return hour == 12 ? 12 : hour + 12;
    }
  }

  static int _wordToInt(String word) {
    const map = {
      'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
      'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    };
    return map[word.toLowerCase()] ?? int.tryParse(word) ?? 7;
  }

  // -----------------------------------------------------------------------
  // Date resolution helpers
  // -----------------------------------------------------------------------

  /// Resolve a human date expression to a [DateTime] on or after [onOrAfter].
  ///
  /// Supports day names ("monday"), relative words ("today", "tomorrow"),
  /// and month+day forms ("April 5th", "Dec 25").
  /// Exposed as `@visibleForTesting` so unit tests can inject [now].
  @visibleForTesting
  static DateTime? resolveDate(
    String text, {
    DateTime? onOrAfter,
    DateTime? now,
  }) {
    final t = text.trim().toLowerCase();
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final earliest = onOrAfter ?? today;

    if (t == 'today') return today.isBefore(earliest) ? earliest : today;
    if (t == 'tomorrow') {
      final tom = today.add(const Duration(days: 1));
      return tom.isBefore(earliest) ? earliest : tom;
    }

    // Day of week
    const dayNames = {
      'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
      'friday': 5, 'saturday': 6, 'sunday': 7,
    };
    if (dayNames.containsKey(t)) {
      final target = dayNames[t]!;
      var candidate = earliest;
      // Walk forward until we land on the target day of week
      for (int i = 0; i < 7; i++) {
        if (candidate.weekday == target) return candidate;
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate; // unreachable, but safe
    }

    // Month + optional day: "april 5th", "december 25", "jan", "july 4"
    final monthDayRe = RegExp(
      r'^(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|'
      r'july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)'
      r'(?:\s+(\d{1,2})(?:st|nd|rd|th)?)?$',
    );
    final mMatch = monthDayRe.firstMatch(t);
    if (mMatch != null) {
      final month = _parseMonth(mMatch.group(1)!);
      final day = int.tryParse(mMatch.group(2) ?? '') ?? 1;
      var candidate = DateTime(clock.year, month, day);
      if (candidate.isBefore(earliest)) {
        candidate = DateTime(clock.year + 1, month, day);
      }
      return candidate;
    }

    return null;
  }

  static int _parseMonth(String m) {
    const months = {
      'jan': 1, 'january': 1,
      'feb': 2, 'february': 2,
      'mar': 3, 'march': 3,
      'apr': 4, 'april': 4,
      'may': 5,
      'jun': 6, 'june': 6,
      'jul': 7, 'july': 7,
      'aug': 8, 'august': 8,
      'sep': 9, 'sept': 9, 'september': 9,
      'oct': 10, 'october': 10,
      'nov': 11, 'november': 11,
      'dec': 12, 'december': 12,
    };
    return months[m.toLowerCase()] ?? 1;
  }
}