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

  const TemporalIntent({
    required this.recurrence,
    required this.startTrigger,
    required this.endTrigger,
    required this.dayCount,
    this.weekdays = const [],
  });

  bool get usesSunsetSunrise =>
      startTrigger == TimeTrigger.sunset || endTrigger == TimeTrigger.sunrise;

  bool get usesDuskDawn =>
      startTrigger == TimeTrigger.dusk || endTrigger == TimeTrigger.dawn;

  @override
  String toString() =>
      'TemporalIntent(recurrence=${recurrence.name}, days=$dayCount, '
      'start=${startTrigger.name}, end=${endTrigger.name})';
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
    r'weeknights?|weekdays?|weekends?'
    r')\b',
    caseSensitive: false,
  );

  // Connector / filler words to clean up after stripping
  static final _fillerPattern = RegExp(
    r'\b(for\s+me|give\s+me\s+(a\s+)?|set\s+up\s+(a\s+)?|schedule\s+(a\s+)?|'
    r'can\s+you\s+|please\s+|i\s+want\s+(a\s+)?|i\'d\s+like\s+(a\s+)?)\b',
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

    final hasTemporalSignal = _thisWeekPattern.hasMatch(lower) ||
        _nextNDaysPattern.hasMatch(lower) ||
        _weekendsPattern.hasMatch(lower) ||
        _weekdaysPattern.hasMatch(lower) ||
        _tonightPattern.hasMatch(lower) ||
        _sunsetPattern.hasMatch(lower) ||
        _duskPattern.hasMatch(lower);

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

    if (_weekendsPattern.hasMatch(lower)) {
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

    return TemporalIntent(
      recurrence: recurrence,
      startTrigger: startTrigger,
      endTrigger: endTrigger,
      dayCount: dayCount,
      weekdays: weekdays,
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

  static int _wordToInt(String word) {
    const map = {
      'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
      'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    };
    return map[word.toLowerCase()] ?? int.tryParse(word) ?? 7;
  }
}