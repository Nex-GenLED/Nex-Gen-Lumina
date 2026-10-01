// lib/features/ai/recurring_request_phrases.dart
//
// +112 (#121) — ONE answer to "did the customer ask for something that
// repeats?" for every Lumina entry point (the chat's compound plan, the chat's
// cloud `schedulingIntents`, and the Schedule tab's calendar box).
//
// A multi-night request ("chiefs for the next three nights", "warm white all
// week") is a run of DATED nights and must never become a recurring
// ScheduleItem: that item repeats every week until the customer deletes it,
// and it carried only the first colour as a solid. A recurring item is written
// ONLY when the words say so — "every night", "every Friday", "nightly",
// "weekly", "every weekday", "each evening". The cloud model's own
// `recurringIntent` hint is a tie-breaker at most, never the decision.

/// True when [request] explicitly asks for a repeating schedule.
bool explicitRecurringRequested(String request) =>
    _recurringPattern.hasMatch(request.toLowerCase());

/// The weekday names the request repeats on, when it names any. Empty for
/// "every night" / "nightly" (the caller treats that as every day).
Set<String> explicitRecurringWeekdays(String request) {
  final lower = request.toLowerCase();
  final out = <String>{};
  for (final m in _everyDayNamePattern.allMatches(lower)) {
    final day = m.group(1)!;
    for (final e in _dayLabels.entries) {
      if (day.startsWith(e.key)) out.add(e.value);
    }
  }
  if (_everyWeekdayPattern.hasMatch(lower)) {
    out.addAll(const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']);
  }
  if (_everyWeekendPattern.hasMatch(lower)) {
    out.addAll(const ['Sat', 'Sun']);
  }
  return out;
}

const Map<String, String> _dayLabels = {
  'mon': 'Mon',
  'tue': 'Tue',
  'wed': 'Wed',
  'thu': 'Thu',
  'fri': 'Fri',
  'sat': 'Sat',
  'sun': 'Sun',
};

// "every night", "every day", "every evening", "each night", "nightly",
// "daily", "weekly", "every weekday / weeknight / weekend", "every Friday",
// "every Mon and Wed", "on Fridays" (plural day = habitual). NOT "every night
// this week" — that phrase is bounded, and the compound detector owns it as a
// seven-night run; the negative lookahead keeps it dated.
final RegExp _recurringPattern = RegExp(
  r'\b(?:'
  r'(?:every|each)\s+(?:night|day|evening)(?!\s+(?:this|next)\s+week)\b|'
  r'nightly|daily|weekly|'
  r'(?:every|each)\s+(?:weekday|weeknight|weekend)s?\b|'
  r'(?:every|each)\s+(?:mon|tues?|wed(?:nes)?|thu(?:rs)?|fri|sat(?:ur)?|sun)(?:day)?s?\b|'
  r'\bon\s+(?:mon|tues|wednes|thurs|fri|satur|sun)days\b'
  r')',
  caseSensitive: false,
);

final RegExp _everyDayNamePattern = RegExp(
  r'\b(?:every|each|on)\s+((?:mon|tues?|wed(?:nes)?|thu(?:rs)?|fri|sat(?:ur)?|sun)(?:day)?s?)\b',
  caseSensitive: false,
);

final RegExp _everyWeekdayPattern = RegExp(
  r'\b(?:every|each)\s+(?:weekday|weeknight)s?\b',
  caseSensitive: false,
);

final RegExp _everyWeekendPattern = RegExp(
  r'\b(?:every|each)\s+weekends?\b',
  caseSensitive: false,
);
