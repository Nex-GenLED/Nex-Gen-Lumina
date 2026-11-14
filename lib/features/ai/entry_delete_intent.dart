// lib/features/ai/entry_delete_intent.dart
//
// Build 128 — the `deleteCalendarEntries` field of the Smart-tier reply: the
// model's DESCRIPTION of which dated calendar entries the customer asked to
// remove. The model proposes, the app confirms: the app resolves this
// description against the calendar it holds (entry_delete_resolver.dart),
// shows a confirmation card with the count, dates and names, and removes
// nothing until the customer taps Delete. The model never sees the calendar
// and never claims a deletion happened.
//
// Before 128 the schema had no delete action at all, so a request to delete
// the entries Lumina itself had written fell to the model's scope rule and it
// answered that it could not do that. The seven entries written on 2026-11-11
// (sourceTag lumina_ai, entryIds lumina_…) could only be removed one at a
// time through the Schedule tab.
//
// Sibling of scheduling_intent.dart / recurring_sports_autopilot_intent.dart:
// a typed model with a tolerant `fromJson` that never throws, plus the prompt
// fragment the Smart prompt embeds verbatim so the producer and this parser
// derive from one source.
//
// [isEntryDeleteRequest] is the phone-side gate that keeps such a request out
// of the local tiers (team, holiday and theme resolution would otherwise
// compose a design for "delete the Chiefs entries") and routes it to the Smart
// model, whose prompt carries this schema.

import 'package:flutter/foundation.dart';

/// What kind of schedule the customer asked to delete.
enum EntryDeleteTarget {
  /// One-off calendar entries on specific dates. The only kind this feature
  /// removes.
  dated,

  /// A repeating (weekly / nightly) schedule. Never removed here; the app says
  /// where to do it.
  recurring,
}

/// Which entries the customer described.
enum EntryDeleteScope {
  /// One day — [EntryDeleteIntent.date].
  date,

  /// A span of days — [EntryDeleteIntent.startDate] to
  /// [EntryDeleteIntent.endDate], inclusive.
  range,

  /// Everything Lumina itself created, from today on.
  luminaAll,

  /// The model could not tell which day(s). The app asks; it never guesses.
  unclear,
}

/// Parsed `deleteCalendarEntries` field. Schema is defined by
/// [schemaPromptFragment], which lumina_ai_service.dart's Smart-tier system
/// prompt embeds verbatim.
class EntryDeleteIntent {
  final EntryDeleteTarget target;
  final EntryDeleteScope scope;

  /// Strict `YYYY-MM-DD`; set for [EntryDeleteScope.date].
  final String? date;

  /// Strict `YYYY-MM-DD`, inclusive; set for [EntryDeleteScope.range].
  final String? startDate;
  final String? endDate;

  /// A name the customer mentioned ("the Chiefs one"), or null. Matched
  /// case-insensitively as a substring of the entry's pattern name.
  final String? nameFilter;

  const EntryDeleteIntent({
    required this.target,
    required this.scope,
    this.date,
    this.startDate,
    this.endDate,
    this.nameFilter,
  });

  /// Always true on a non-null instance: [fromJson] degrades anything it
  /// cannot read to [EntryDeleteScope.unclear] rather than returning null, so
  /// the app can still answer the customer. Mirrors the sibling intents'
  /// dispatch sites.
  bool get isValid => true;

  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Parse a raw `deleteCalendarEntries` map. Returns null only when the field
  /// is absent (null input). Never throws:
  ///   • `target` anything but "recurring" → dated;
  ///   • `scope` "date" needs a valid `date`, "range" needs valid
  ///     `startDate` AND `endDate` (swapped if reversed), "lumina_all" takes
  ///     nothing; a scope whose dates are missing or malformed, or an unknown
  ///     scope, becomes [EntryDeleteScope.unclear] — a date is never invented;
  ///   • `nameFilter` kept when a non-empty String.
  static EntryDeleteIntent? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final target = json['target'] == 'recurring'
        ? EntryDeleteTarget.recurring
        : EntryDeleteTarget.dated;

    final rawName = json['nameFilter'];
    final nameFilter =
        rawName is String && rawName.trim().isNotEmpty ? rawName.trim() : null;

    final rawScope = json['scope'];
    switch (rawScope) {
      case 'date':
        final d = _strictDate(json['date']);
        if (d == null) {
          debugPrint('[EntryDeleteIntent] scope date without a usable date');
          return EntryDeleteIntent(
              target: target,
              scope: EntryDeleteScope.unclear,
              nameFilter: nameFilter);
        }
        return EntryDeleteIntent(
          target: target,
          scope: EntryDeleteScope.date,
          date: d,
          nameFilter: nameFilter,
        );
      case 'range':
        var a = _strictDate(json['startDate']);
        var b = _strictDate(json['endDate']);
        if (a == null || b == null) {
          debugPrint('[EntryDeleteIntent] scope range without both dates');
          return EntryDeleteIntent(
              target: target,
              scope: EntryDeleteScope.unclear,
              nameFilter: nameFilter);
        }
        if (a.compareTo(b) > 0) {
          final t = a;
          a = b;
          b = t;
        }
        return EntryDeleteIntent(
          target: target,
          scope: EntryDeleteScope.range,
          startDate: a,
          endDate: b,
          nameFilter: nameFilter,
        );
      case 'lumina_all':
        return EntryDeleteIntent(
          target: target,
          scope: EntryDeleteScope.luminaAll,
          nameFilter: nameFilter,
        );
      default:
        if (rawScope != 'unclear') {
          debugPrint('[EntryDeleteIntent] unknown scope "$rawScope" → unclear');
        }
        return EntryDeleteIntent(
            target: target,
            scope: EntryDeleteScope.unclear,
            nameFilter: nameFilter);
    }
  }

  /// Strict `YYYY-MM-DD` with a round-trip guard, so a rollover date
  /// ('2026-02-30' → Mar 2) is rejected rather than shifted.
  static String? _strictDate(dynamic raw) {
    if (raw is! String || !_datePattern.hasMatch(raw)) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final roundTrip = '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
    return roundTrip == raw ? raw : null;
  }

  Map<String, dynamic> toJson() => {
        'target': target == EntryDeleteTarget.recurring ? 'recurring' : 'dated',
        'scope': switch (scope) {
          EntryDeleteScope.date => 'date',
          EntryDeleteScope.range => 'range',
          EntryDeleteScope.luminaAll => 'lumina_all',
          EntryDeleteScope.unclear => 'unclear',
        },
        'date': date,
        'startDate': startDate,
        'endDate': endDate,
        'nameFilter': nameFilter,
      };

  @override
  String toString() =>
      'EntryDeleteIntent(${target.name}, ${scope.name}, date=$date, '
      'range=$startDate..$endDate, name=$nameFilter)';

  /// The schema description the model is held to — the single source of
  /// truth embedded verbatim in the Smart prompt. Pure static text; today's
  /// date reaches the model through the context block, not this fragment.
  static const String schemaPromptFragment =
      '═══ DELETING DATED CALENDAR ENTRIES ═══\n'
      'When the user asks to delete, remove, cancel or clear entries from their '
      'calendar or schedule ("delete the entries you created", "remove '
      'Friday\'s lights", "cancel what you set up for Nov 20 to Nov 27", "clear '
      'everything you made for me"), emit a `deleteCalendarEntries` field. YOU '
      'DO NOT DELETE ANYTHING: the app resolves your description to the actual '
      'entries and shows the user a confirmation with the count, dates and '
      'names; nothing is removed until the user taps Delete.\n'
      '`deleteCalendarEntries` schema:\n'
      '  {\n'
      '    "target": "dated" | "recurring",\n'
      '    "scope": "date" | "range" | "lumina_all" | "unclear",\n'
      '    "date": "YYYY-MM-DD" | null,\n'
      '    "startDate": "YYYY-MM-DD" | null,\n'
      '    "endDate": "YYYY-MM-DD" | null,\n'
      '    "nameFilter": string | null\n'
      '  }\n'
      'Rules:\n'
      '• "target": "dated" for one-off calendar entries on specific dates. '
      '"recurring" when the user asks to delete a repeating / weekly / nightly '
      'schedule — still emit the field; the app explains that repeating '
      'schedules are deleted from My Schedule.\n'
      '• "scope": "date" with "date" for one day ("tonight", "Friday", '
      '"November 20"); "range" with "startDate" and "endDate" for a span '
      '("this week", "Nov 20 through Nov 27"); "lumina_all" for everything '
      'Lumina itself created ("everything you created / set up / added for '
      'me", "all your entries", "the ones you made"); "unclear" when you '
      'cannot tell which day(s) — then ASK in `message` ("Which day\'s entries '
      'should I remove?") and leave every date null. NEVER guess a date.\n'
      '• Resolve relative days ("tonight", "Friday", "this week") against '
      'today\'s date given in the context. Dates are strict YYYY-MM-DD.\n'
      '• "nameFilter": the entry name the user mentioned, if any ("the Chiefs '
      'one" → "Chiefs"); otherwise null.\n'
      '• When emitting this field: set `wled` to null (no lighting change), '
      'set schedulingIntent, schedulingIntents, ephemeralSession and '
      'recurringSportsAutopilot to null, give no `colors` or `effect`, and '
      'keep `message` to one short sentence such as "Here\'s what I found — '
      'confirm below." NEVER say anything was deleted, and never list entries '
      'yourself; the app shows the real list.\n'
      '• Game Day and other automatic entries cannot be deleted this way; the '
      'app says so. Do not refuse the request yourself — emit the field and '
      'let the app answer.\n'
      'Example — user: "delete the seven entries you created for me" →\n'
      '  {"message":"Here\'s what I found — confirm below.","wled":null,'
      '"deleteCalendarEntries":{"target":"dated","scope":"lumina_all",'
      '"date":null,"startDate":null,"endDate":null,"nameFilter":null}}\n'
      'Example — user: "remove Friday\'s entry" (today is Wednesday '
      '2026-11-18) →\n'
      '  {"message":"Here\'s what I found — confirm below.","wled":null,'
      '"deleteCalendarEntries":{"target":"dated","scope":"date",'
      '"date":"2026-11-20","startDate":null,"endDate":null,'
      '"nameFilter":null}}\n'
      'Example — user: "delete my nightly warm white schedule" →\n'
      '  {"message":"Repeating schedules are deleted from My Schedule.",'
      '"wled":null,"deleteCalendarEntries":{"target":"recurring",'
      '"scope":"unclear","date":null,"startDate":null,"endDate":null,'
      '"nameFilter":"warm white"}}\n\n';
}

final RegExp _kDeleteVerb = RegExp(
    r'\b(delete|remove|cancel|clear|erase|undo|get rid of|take off|wipe)\b');

final RegExp _kDeleteObject = RegExp(
    r"\b(entry|entries|night|nights|schedule|schedules|scheduled|calendar|"
    r'plan|plans|day|days|evening|evenings|everything|all of (them|those|that|it)|'
    r'the ones|what you (made|created|set up|added|scheduled|put)|'
    r'you (made|created|set up|added|scheduled|put))\b');

/// True when [prompt] asks to delete, remove, cancel or clear something on
/// the calendar or schedule — a delete verb AND a schedule noun. Pure.
///
/// Used by LuminaBrain.chat to skip the local tiers (which would otherwise
/// compose a design for "delete the Chiefs entries") and by the tier
/// classifier to route the request to the Smart prompt, which carries the
/// schema. A plain lighting command ("remove the red", "clear blue") has no
/// schedule noun and is not matched.
bool isEntryDeleteRequest(String prompt) {
  final t = prompt.toLowerCase().trim();
  return _kDeleteVerb.hasMatch(t) && _kDeleteObject.hasMatch(t);
}
