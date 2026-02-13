import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/schedule/schedule_signal_words.dart';

// ---------------------------------------------------------------------------
// Extracted entities model
// ---------------------------------------------------------------------------

/// Structured entities pulled from a natural-language schedule request.
///
/// Used by [ScheduleComplexityClassifier] to inform routing and by the
/// Cloud AI to ground its response with pre-parsed data.
class ScheduleEntities {
  /// Explicit time references found (e.g., "10pm", "sunset").
  final List<String> timeReferences;

  /// Date or day-of-week references (e.g., "tomorrow", "Monday").
  final List<String> dateReferences;

  /// Duration span if specified (e.g., "next_week", "all_month").
  final String? duration;

  /// Recurrence pattern detected (e.g., "every_night", "daily", "weekdays").
  final String? recurrence;

  /// Sports team reference if found.
  final TeamReference? teamReference;

  /// Holiday reference if found.
  final String? holidayReference;

  /// Zone references for multi-zone requests.
  final List<String> zoneReferences;

  /// Action keywords found (e.g., "turn off", "warm white").
  final List<String> actionReferences;

  /// Variation indicator (e.g., "different_each_night", "mix_it_up").
  final String? variation;

  /// Rough time-of-day hint (e.g., "night", "morning", "evening").
  final String? timeHint;

  const ScheduleEntities({
    this.timeReferences = const [],
    this.dateReferences = const [],
    this.duration,
    this.recurrence,
    this.teamReference,
    this.holidayReference,
    this.zoneReferences = const [],
    this.actionReferences = const [],
    this.variation,
    this.timeHint,
  });

  /// True when at least one meaningful entity was extracted.
  bool get hasEntities =>
      timeReferences.isNotEmpty ||
      dateReferences.isNotEmpty ||
      duration != null ||
      recurrence != null ||
      teamReference != null ||
      holidayReference != null ||
      zoneReferences.isNotEmpty ||
      actionReferences.isNotEmpty ||
      variation != null;

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (timeReferences.isNotEmpty) map['timeReferences'] = timeReferences;
    if (dateReferences.isNotEmpty) map['dateReferences'] = dateReferences;
    if (duration != null) map['duration'] = duration;
    if (recurrence != null) map['recurrence'] = recurrence;
    if (teamReference != null) map['teamReference'] = teamReference!.shortName;
    if (holidayReference != null) map['holidayReference'] = holidayReference;
    if (zoneReferences.isNotEmpty) map['zoneReferences'] = zoneReferences;
    if (actionReferences.isNotEmpty) map['actionReferences'] = actionReferences;
    if (variation != null) map['variation'] = variation;
    if (timeHint != null) map['timeHint'] = timeHint;
    return map;
  }

  @override
  String toString() => 'ScheduleEntities(${toJson()})';
}

// ---------------------------------------------------------------------------
// Entity extractor
// ---------------------------------------------------------------------------

/// Extracts structured entities from natural-language scheduling text.
///
/// Runs entirely on-device using regex and keyword matching — no network
/// calls required. Designed to be called before the complexity classifier
/// and before routing to Cloud AI.
class ScheduleEntityExtractor {
  ScheduleEntityExtractor._();

  /// Extract all recognizable entities from [text].
  static ScheduleEntities extract(String text) {
    final lower = text.toLowerCase().trim();

    final times = _extractTimes(lower);
    final dates = _extractDates(lower);
    final duration = _extractDuration(lower);
    final recurrence = _extractRecurrence(lower);
    final team = _extractTeam(lower);
    final holiday = _extractHoliday(lower);
    final zones = _extractZones(lower);
    final actions = _extractActions(lower);
    final variation = _extractVariation(lower);
    final timeHint = _extractTimeHint(lower);

    final entities = ScheduleEntities(
      timeReferences: times,
      dateReferences: dates,
      duration: duration,
      recurrence: recurrence,
      teamReference: team,
      holidayReference: holiday,
      zoneReferences: zones,
      actionReferences: actions,
      variation: variation,
      timeHint: timeHint,
    );

    debugPrint('ScheduleEntityExtractor: ${entities.toJson()}');
    return entities;
  }

  // -----------------------------------------------------------------------
  // Time extraction
  // -----------------------------------------------------------------------

  /// Regex patterns for clock times.
  static final _clockTimeRegex = RegExp(
    r'\b(\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.|p\.m\.))\b',
    caseSensitive: false,
  );

  /// Solar event keywords.
  static const _solarKeywords = [
    'sunset', 'sunrise', 'dusk', 'dawn', 'sundown', 'sunup',
  ];

  /// Named time keywords.
  static const _namedTimes = ['noon', 'midnight'];

  static List<String> _extractTimes(String text) {
    final results = <String>[];

    // Clock times: "10pm", "7:30 AM", "10:00pm"
    for (final match in _clockTimeRegex.allMatches(text)) {
      results.add(match.group(0)!.trim());
    }

    // Solar events
    for (final keyword in _solarKeywords) {
      if (RegExp('\\b$keyword\\b').hasMatch(text)) {
        results.add(keyword);
      }
    }

    // Named times
    for (final keyword in _namedTimes) {
      if (RegExp('\\b$keyword\\b').hasMatch(text)) {
        results.add(keyword);
      }
    }

    return results;
  }

  // -----------------------------------------------------------------------
  // Date / day-of-week extraction
  // -----------------------------------------------------------------------

  static const _dayNames = [
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday',
    'saturday', 'sunday',
  ];
  static const _dayAbbrs = [
    'mon', 'tue', 'tues', 'wed', 'thu', 'thur', 'thurs',
    'fri', 'sat', 'sun',
  ];
  static const _relativeDate = [
    'today', 'tonight', 'tomorrow', 'tomorrow night',
    'this evening', 'this morning', 'this weekend',
    'next week', 'next weekend', 'next month',
  ];

  static final _specificDateRegex = RegExp(
    r'\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}(?:st|nd|rd|th)?\b',
    caseSensitive: false,
  );

  static List<String> _extractDates(String text) {
    final results = <String>[];

    // Relative dates (check longer phrases first)
    final sortedRelative = List.of(_relativeDate)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final keyword in sortedRelative) {
      if (text.contains(keyword)) {
        results.add(keyword);
      }
    }

    // Full day names
    for (final day in _dayNames) {
      if (RegExp('\\b$day\\b').hasMatch(text)) {
        results.add(day);
      }
    }

    // Abbreviated day names (only if full name not already matched)
    if (results.isEmpty) {
      for (final abbr in _dayAbbrs) {
        if (RegExp('\\b$abbr\\b').hasMatch(text)) {
          results.add(abbr);
        }
      }
    }

    // Specific dates: "December 25th", "January 1"
    for (final match in _specificDateRegex.allMatches(text)) {
      results.add(match.group(0)!.trim());
    }

    return results;
  }

  // -----------------------------------------------------------------------
  // Duration extraction
  // -----------------------------------------------------------------------

  static final _durationPatterns = <RegExp, String>{
    RegExp(r'\ball\s+month\b'): 'all_month',
    RegExp(r'\ball\s+season\b'): 'all_season',
    RegExp(r'\ball\s+week\b'): 'all_week',
    RegExp(r'\bfor\s+a\s+week\b'): 'one_week',
    RegExp(r'\bfor\s+the\s+week\b'): 'one_week',
    RegExp(r'\bfor\s+a\s+month\b'): 'one_month',
    RegExp(r'\bfor\s+the\s+month\b'): 'one_month',
    RegExp(r'\bnext\s+week\b'): 'next_week',
    RegExp(r'\bnext\s+month\b'): 'next_month',
    RegExp(r'\brest\s+of\s+the\s+season\b'): 'rest_of_season',
    RegExp(r'\brest\s+of\s+the\s+month\b'): 'rest_of_month',
    RegExp(r'\brest\s+of\s+the\s+week\b'): 'rest_of_week',
    RegExp(r'\b(\d+)\s+days?\b'): 'n_days',
    RegExp(r'\b(\d+)\s+nights?\b'): 'n_nights',
    RegExp(r'\b(\d+)\s+weeks?\b'): 'n_weeks',
    RegExp(r'\b(\d+)\s+months?\b'): 'n_months',
    RegExp(r'\bthrough\s+(january|february|march|april|may|june|july|august|september|october|november|december)\b'):
        'through_month',
    RegExp(r'\buntil\s+(january|february|march|april|may|june|july|august|september|october|november|december)\b'):
        'until_month',
  };

  static String? _extractDuration(String text) {
    for (final entry in _durationPatterns.entries) {
      final match = entry.key.firstMatch(text);
      if (match != null) {
        // For numeric durations, include the number
        if (entry.value.startsWith('n_')) {
          final n = match.group(1);
          if (n != null) return '${n}_${entry.value.substring(2)}';
        }
        // For "through/until month", include the month
        if (entry.value.contains('month') && match.groupCount >= 1) {
          final month = match.group(1);
          if (month != null && entry.value.startsWith('through')) {
            return 'through_$month';
          }
          if (month != null && entry.value.startsWith('until')) {
            return 'until_$month';
          }
        }
        return entry.value;
      }
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Recurrence extraction
  // -----------------------------------------------------------------------

  static final _recurrencePatterns = <RegExp, String>{
    RegExp(r'\bevery\s+night\b'): 'every_night',
    RegExp(r'\bevery\s+evening\b'): 'every_evening',
    RegExp(r'\bevery\s+morning\b'): 'every_morning',
    RegExp(r'\bevery\s+day\b'): 'every_day',
    RegExp(r'\bnightly\b'): 'nightly',
    RegExp(r'\bdaily\b'): 'daily',
    RegExp(r'\bweekly\b'): 'weekly',
    RegExp(r'\bon\s+weekdays\b'): 'weekdays',
    RegExp(r'\bon\s+weekends\b'): 'weekends',
    RegExp(r'\bweekdays\b'): 'weekdays',
    RegExp(r'\bweeknights\b'): 'weeknights',
    RegExp(r'\bweekends\b'): 'weekends',
    RegExp(r'\bevery\s+game\s*day\b'): 'every_game_day',
  };

  static String? _extractRecurrence(String text) {
    for (final entry in _recurrencePatterns.entries) {
      if (entry.key.hasMatch(text)) {
        return entry.value;
      }
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Team extraction
  // -----------------------------------------------------------------------

  static TeamReference? _extractTeam(String text) {
    // Check longer team names first to avoid partial matches
    final sortedKeys = knownTeams.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sortedKeys) {
      if (RegExp('\\b${RegExp.escape(key)}\\b').hasMatch(text)) {
        return knownTeams[key];
      }
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Holiday extraction
  // -----------------------------------------------------------------------

  static String? _extractHoliday(String text) {
    // Check longer holiday names first
    final sortedKeys = knownHolidays.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sortedKeys) {
      if (text.contains(key)) {
        return knownHolidays[key];
      }
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Zone extraction
  // -----------------------------------------------------------------------

  static List<String> _extractZones(String text) {
    final found = <String>{};

    // Check longer zone phrases first to avoid "front" matching
    // when "front of house" is present.
    final sortedKeys = knownZones.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sortedKeys) {
      if (text.contains(key)) {
        final canonical = knownZones[key]!;
        // Skip if a more specific phrase already captured this zone
        if (!found.contains(canonical)) {
          found.add(canonical);
        }
      }
    }

    return found.toList();
  }

  // -----------------------------------------------------------------------
  // Action extraction
  // -----------------------------------------------------------------------

  static const _actionKeywords = <String, String>{
    'turn off': 'power_off',
    'shut off': 'power_off',
    'lights off': 'power_off',
    'switch off': 'power_off',
    'power off': 'power_off',
    'turn on': 'power_on',
    'lights on': 'power_on',
    'switch on': 'power_on',
    'power on': 'power_on',
    'warm white': 'warm_white',
    'cool white': 'cool_white',
    'candlelight': 'candlelight',
    'cancel': 'cancel',
    'delete': 'delete',
    'remove': 'remove',
    'disable': 'disable',
    'pause': 'pause',
    'stop': 'stop',
  };

  static List<String> _extractActions(String text) {
    final results = <String>[];
    // Check longer phrases first
    final sortedKeys = _actionKeywords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sortedKeys) {
      if (text.contains(key)) {
        final action = _actionKeywords[key]!;
        if (!results.contains(action)) {
          results.add(action);
        }
      }
    }
    return results;
  }

  // -----------------------------------------------------------------------
  // Variation extraction
  // -----------------------------------------------------------------------

  static final _variationPatterns = <RegExp, String>{
    RegExp(r'\bdifferent\s+each\s+(night|day|evening)\b'): 'different_each',
    RegExp(r'\bdifferent\s+every\s+(night|day|evening)\b'): 'different_every',
    RegExp(r'\bnew\s+(design|pattern|look)\s+each\b'): 'new_each',
    RegExp(r'\bchange\s+(it\s+)?up\s+each\b'): 'change_each',
    RegExp(r'\brotate\b'): 'rotate',
    RegExp(r'\brotation\b'): 'rotation',
    RegExp(r'\balternate\b'): 'alternate',
    RegExp(r'\balternating\b'): 'alternating',
    RegExp(r'\bcycle\s+through\b'): 'cycle_through',
    RegExp(r'\bmix\s+it\s+up\b'): 'mix_it_up',
    RegExp(r'\bvariety\b'): 'variety',
    RegExp(r'\brandom(ize)?\b'): 'randomize',
    RegExp(r'\bsurprise\s+me\b'): 'surprise',
  };

  static String? _extractVariation(String text) {
    for (final entry in _variationPatterns.entries) {
      if (entry.key.hasMatch(text)) {
        return entry.value;
      }
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // Time-of-day hint
  // -----------------------------------------------------------------------

  static String? _extractTimeHint(String text) {
    if (RegExp(r'\b(night|tonight|evening|after\s+dark|late)\b').hasMatch(text)) {
      return 'night';
    }
    if (RegExp(r'\b(morning|dawn|sunrise|wake\s+up)\b').hasMatch(text)) {
      return 'morning';
    }
    if (RegExp(r'\b(afternoon)\b').hasMatch(text)) {
      return 'afternoon';
    }
    if (RegExp(r'\b(dusk|sunset|sundown)\b').hasMatch(text)) {
      return 'evening';
    }
    return null;
  }
}
