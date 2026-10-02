// lib/features/game_day/served_game_day.dart
//
// +114 (plan §3.2) — which calendar entries belong to a Game Day the SERVER
// runs, so the phone's lease path can stand down for exactly those.
//
// HOW AN ENTRY IS TIED TO A TEAM. The plan assumed Game Day rows carry
// `entryId: gd_<slug>` (CalendarEntryId.gameDay). They do not: the autopilot
// writer (`GameDayAutopilotService._buildCalendarEntry`) never sets entryId, so
// every Game Day row in production is stored as the legacy `primary` id. What
// every row DOES carry is `sourceTag: game_day` and the note
// "<team name> vs|@ <opponent> — Game Day autopilot", where <team name> is the
// config's own `teamName`. So the team is recovered from the note through the
// account's enabled configs (name → slug). A `gd_<slug>` id is honoured first
// if a later build starts writing one.
//
// Crew rows (`game_day_group`) are never served: the server runs personal
// autopilot configs only. An entry whose team cannot be recovered reads as NOT
// served — the phone path runs, as today.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart'
    show enabledAutopilotConfigsProvider, gameDayAutopilotConfigsProvider;
import 'package:nexgen_command/features/game_day/game_day_run_mode.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status_provider.dart';
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';

/// PURE. The team slug a personal Game Day calendar entry belongs to, or null.
String? gameDayEntryTeamSlug(
  CalendarEntry e,
  Map<String, String> teamNameToSlug,
) {
  if (e.sourceTag != CalendarEntrySourceTag.gameDay) return null;
  if (e.entryId.startsWith('gd_') && e.entryId.length > 3) {
    return e.entryId.substring(3);
  }
  final name = e.gameDayTeamName;
  if (name == null) return null;
  return teamNameToSlug[name];
}

/// PURE. Does the server run this entry's Game Day at [now]?
bool isServedGameDayEntry(
  CalendarEntry e,
  GameDayServerStatus status,
  Map<String, String> teamNameToSlug,
  DateTime now,
) {
  final slug = gameDayEntryTeamSlug(e, teamNameToSlug);
  return slug != null && status.servesTeamAt(slug, now);
}

/// The lease path's answer for one entry. UNKNOWN is its own value on purpose:
/// in the first seconds after launch neither the user document nor the team
/// list has arrived, and reading that as "not served" would let the lease
/// psave a served night — which APPLIES the solid team colour to the house at
/// once — only for the next sweep to retract it. On every app open.
enum ServedVerdict { served, notServed, unknown }

/// `(entry, now) → verdict`, bound to the live server status and the
/// account's configs. Indirected so the lease manager can be tested without
/// Firestore.
typedef ServedGameDayEntryTest = ServedVerdict Function(
    CalendarEntry entry, DateTime now);

final servedGameDayEntryTestProvider = Provider<ServedGameDayEntryTest>((ref) {
  final statusAsync = ref.watch(gameDayServerStatusProvider);
  final configsAsync = ref.watch(gameDayAutopilotConfigsProvider);
  final status = statusAsync.valueOrNull ?? GameDayServerStatus.notServed;
  final configs = configsAsync.valueOrNull ?? const [];
  // Loading = no value yet. An error is an answer (not served): the stream
  // maps its own errors to not-served data, and a configs error leaves no team
  // to map — waiting on either would only delay the 112 behaviour.
  final statusKnown = statusAsync.hasValue || statusAsync.hasError;
  final configsKnown = configsAsync.hasValue || configsAsync.hasError;
  final nameToSlug = <String, String>{
    for (final c in configs)
      if (c.enabled && c.teamName.isNotEmpty) c.teamName: c.teamSlug,
  };
  return (entry, now) {
    // Only a personal Game Day row can be served; everything else is decided
    // without waiting on anything.
    if (entry.sourceTag != CalendarEntrySourceTag.gameDay) {
      return ServedVerdict.notServed;
    }
    if (!statusKnown) return ServedVerdict.unknown;
    if (!status.servedAt(now)) return ServedVerdict.notServed;
    // Served account: the team must be mapped to say which.
    if (!configsKnown) return ServedVerdict.unknown;
    return isServedGameDayEntry(entry, status, nameToSlug, now)
        ? ServedVerdict.served
        : ServedVerdict.notServed;
  };
});

/// +114 — the day-timeline tag for a Game Day row: `server`, `phone` or
/// `setup needed`; null for a row that is not Game Day. A crew row, or a row
/// whose team cannot be recovered, is `phone` — the phone runs it.
final gameDayRunTagProvider =
    Provider<String? Function(CalendarEntry entry)>((ref) {
  final status = ref.watch(gameDayServerStatusSyncProvider);
  final gate =
      ref.watch(gateStatusProvider).valueOrNull ?? GateStatus.unknown;
  final clock = ref.watch(gameDayNowProvider);
  final configs = ref.watch(enabledAutopilotConfigsProvider);
  final nameToSlug = <String, String>{
    for (final c in configs)
      if (c.teamName.isNotEmpty) c.teamName: c.teamSlug,
  };
  return (entry) {
    if (!entry.holdsGameDay) return null;
    final slug = gameDayEntryTeamSlug(entry, nameToSlug);
    if (slug == null) return runModeTag(GameDayRunMode.phone);
    return runModeTag(gameDayRunModeFor(
        status: status, gate: gate, now: clock(), teamSlug: slug));
  };
});
