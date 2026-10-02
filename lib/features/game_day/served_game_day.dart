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
    show enabledAutopilotConfigsProvider;
import 'package:nexgen_command/features/game_day/game_day_server_status.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status_provider.dart';
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

/// `(entry, now) → served?`, bound to the live server status and the account's
/// enabled configs. Indirected so the lease manager and the timeline can be
/// tested without Firestore.
typedef ServedGameDayEntryTest = bool Function(CalendarEntry entry, DateTime now);

final servedGameDayEntryTestProvider = Provider<ServedGameDayEntryTest>((ref) {
  final status = ref.watch(gameDayServerStatusSyncProvider);
  final configs = ref.watch(enabledAutopilotConfigsProvider);
  final nameToSlug = <String, String>{
    for (final c in configs)
      if (c.teamName.isNotEmpty) c.teamName: c.teamSlug,
  };
  return (entry, now) => isServedGameDayEntry(entry, status, nameToSlug, now);
});
