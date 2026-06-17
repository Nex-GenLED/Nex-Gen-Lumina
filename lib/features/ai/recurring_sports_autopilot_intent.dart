// lib/features/ai/recurring_sports_autopilot_intent.dart
//
// Typed model for the `recurringSportsAutopilot` field emitted by the cloud
// AI processor when the user asks for a team's lighting on EVERY game / every
// home game / all season ("Royals blue every home-game night through Oct
// 2026"). Instead of enumerating ~80 game dates (which overflows the response
// token cap and truncates the JSON), the AI emits this ONE compact rule. The
// app hands it to the existing Game Day Autopilot enable path
// ([GameDayAutopilotNotifier.toggleAutopilot]) which materializes only the
// next rolling 7-day window of CalendarEntry rows — the
// CalendarEntryLeaseManager then promotes those within 48h into ≤8 WLED RTC
// timers. No per-game enumeration is ever persisted.
//
// The rule carries only the team slug (+ an optional end bound). All other
// team metadata — name, ESPN id, sport, colors — is resolved from the
// `kTeamColors` catalog by the enable path, so the model never has to emit it.
// This keeps the response tiny and is what eliminates the truncation.

import 'package:flutter/foundation.dart';

/// Parsed `recurringSportsAutopilot` intent. Schema is defined in
/// lumina_ai_service.dart's Smart-tier system prompt.
class RecurringSportsAutopilotIntent {
  /// Team slug from `kTeamColors` (e.g. 'mlb_royals'). The AI is instructed
  /// to emit the slug in `<sport>_<team>` snake_case — same format and
  /// catalog as the `ephemeralSession.teamSlug` field.
  final String teamSlug;

  /// Optional explicit end bound. When non-null, the autopilot stops
  /// materializing games whose date falls after this day (inclusive of the
  /// day itself). Null means open-ended — the season's natural end governs
  /// (e.g. MLB ends in October regardless). Date-only; time-of-day is
  /// ignored by the materializer's inclusive end-of-day comparison.
  final DateTime? untilDate;

  const RecurringSportsAutopilotIntent({
    required this.teamSlug,
    this.untilDate,
  });

  static final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Parse and validate a raw `recurringSportsAutopilot` map from the AI
  /// response. Returns null when the input is null or has no usable
  /// `teamSlug`. A malformed `untilDate` is dropped (logged) rather than
  /// failing the whole intent — an open-ended rule is still useful.
  static RecurringSportsAutopilotIntent? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;

    final slug = json['teamSlug'] as String?;
    if (slug == null || slug.trim().isEmpty) {
      debugPrint('[RecurringSportsAutopilotIntent] missing or empty teamSlug');
      return null;
    }

    DateTime? until;
    final rawUntil = json['untilDate'];
    if (rawUntil is String && rawUntil.isNotEmpty) {
      until = _tryParseStrictDate(rawUntil);
      if (until == null) {
        debugPrint(
            '[RecurringSportsAutopilotIntent] ignoring malformed untilDate: $rawUntil');
      }
    }

    return RecurringSportsAutopilotIntent(
      teamSlug: slug.trim(),
      untilDate: until,
    );
  }

  /// Strict `YYYY-MM-DD` parse with a round-trip guard so rollover dates
  /// (e.g. '2026-02-30' → Mar 2) are rejected rather than silently shifted.
  static DateTime? _tryParseStrictDate(String raw) {
    if (!_datePattern.hasMatch(raw)) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final roundTrip = '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
    return roundTrip == raw ? parsed : null;
  }

  /// Always true on a non-null instance. [fromJson] returns null on any
  /// validation failure, so a constructed intent is by definition valid.
  /// Mirrors [EphemeralSessionIntent.isValid] for symmetric dispatch sites.
  bool get isValid => true;

  @override
  String toString() {
    final dateSuffix = untilDate != null
        ? '@until=${untilDate!.toIso8601String().substring(0, 10)}'
        : '';
    return 'RecurringSportsAutopilotIntent(slug=$teamSlug$dateSuffix)';
  }
}
