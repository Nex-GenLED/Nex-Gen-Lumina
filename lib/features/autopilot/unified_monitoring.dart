// Unified score-monitoring model.
//
// Game Day team selection + the Live Scoring toggle is now the SINGLE source of
// truth for score monitoring, alerts and celebrations. The separate Sports
// Alerts opt-in is retired as a user-facing concept: there is exactly one place
// to arm or disarm monitoring, and it is Game Day.
//
// WHY THIS FILE EXISTS AS PURE LOGIC
// Celebrations had never fired for anyone — zero `game_day`-sourced command
// docs fleet-wide out of 678 — behind three independent blockers, one of which
// was that score polling armed off the SPORTS-ALERT config list, a list the
// user configured in a different screen and which had nothing to do with the
// Game Day teams they'd selected. Arming is therefore the thing most worth
// making unit-testable, so a future change cannot quietly re-narrow it.
//
// THE FIELD SPLIT, and why it is not a collapse:
//   • `enabled`            → runs the scheduled show. The SERVER planner
//                            queries this exact field
//                            (planGameDayFires.ts:342).
//   • `liveScoringEnabled` → monitoring + celebrations. Client-only.
// A team migrated off the retired alerts list carries
// `enabled:false, liveScoringEnabled:true`, so it is monitored while remaining
// invisible to the planner. Merging the two into one flag would have handed the
// planner a set of teams the user never asked to have lit, and would have
// required a server change plus a deploy ordering this work is not allowed to
// take.

import '../sports_alerts/data/team_colors.dart';
import '../sports_alerts/models/score_alert_config.dart';
import '../sports_alerts/models/sport_type.dart';
import 'game_day_autopilot_config.dart';
import 'game_day_background_persistence.dart';

/// Result of resolving what should be monitored right now.
class MonitoringPlan {
  /// The teams to poll, expressed as [ScoreAlertConfig] because that is what
  /// `ScoreMonitorService.checkScores` consumes. These are DERIVED — nothing
  /// persists them as an independent opt-in any more.
  final List<ScoreAlertConfig> monitored;

  /// Legacy alert configs with no Game Day counterpart. Surfaced separately so
  /// the caller can migrate them; they are still included in [monitored] so a
  /// user never loses monitoring in the window before migration runs.
  final List<ScoreAlertConfig> orphanedLegacy;

  const MonitoringPlan({
    required this.monitored,
    this.orphanedLegacy = const [],
  });

  bool get isEmpty => monitored.isEmpty;
  bool get isNotEmpty => monitored.isNotEmpty;
}

/// Derive a [ScoreAlertConfig] from a Game Day team.
///
/// The id is the team slug: monitoring is per-team and there is exactly one
/// Game Day config per team, so a synthesized id keeps it stable across runs
/// (the old model minted random ids, which is why duplicates were possible).
ScoreAlertConfig monitoringConfigFor(BackgroundGameDayAutopilotConfig c) {
  return ScoreAlertConfig(
    id: c.teamSlug,
    teamSlug: c.teamSlug,
    sport: SportType.values.firstWhere(
      (s) => s.name == c.sport,
      orElse: () => SportType.nfl,
    ),
    isEnabled: true,
    sensitivity: AlertSensitivity.values.firstWhere(
      (s) => s.name == c.alertSensitivity,
      orElse: () => AlertSensitivity.majorOnly,
    ),
    // Carried for the same reason sensitivity is: the trigger service receives
    // ONLY this object, so a celebration choice that stops here would never
    // reach the animation. Null stays null — an unchosen effect must keep the
    // legacy hardcoded sequences.
    celebrationEffectId: c.celebrationEffectId,
    celebrationSpeed: c.celebrationSpeed,
    celebrationIntensity: c.celebrationIntensity,
  );
}

/// Is [slug]'s team still carried on the user's Firestore profile arrays?
///
/// [profileTeamKeys] holds `sports_teams` entries already normalised with
/// [_profileKey]. The prefs store keys teams by SLUG while the profile arrays
/// hold display NAMES, so the comparison goes through [kTeamColors].
///
/// A slug absent from [kTeamColors] returns false: both writers of the prefs
/// store (`zone_assignment_screen`, `live_scoring_prompt`) pick exclusively
/// from [kTeamColors], so an unknown slug is a genuinely dead entry, never a
/// custom team we would be wrong to disarm.
bool _isCarriedOnProfile(String slug, Set<String> profileTeamKeys) {
  final name = kTeamColors[slug]?.teamName;
  if (name == null) return false;
  return profileTeamKeys.contains(_profileKey(name));
}

/// Case/whitespace-insensitive profile-array key. Matches the normalisation
/// `TeamRegistrationService._stripTeamFromProfile` uses, so a team this
/// function considers "carried" is exactly one that a Game Day delete would
/// have stripped.
String _profileKey(String teamName) => teamName.trim().toLowerCase();

/// THE unified arming resolution.
///
/// A team is monitored when its Game Day config has Live Scoring on. Legacy
/// alert configs are honoured only while they have no Game Day counterpart —
/// that is the pre-migration safety net, not a second authority: once a Game
/// Day config exists for the team, Game Day wins outright, so turning Live
/// Scoring off genuinely stops monitoring even if a stale legacy config is
/// still sitting in SharedPreferences.
///
/// ORPHAN SAFETY GATE (audit/SPORTS_ALERTS_SYNC_AUDIT.md §4.4). The safety net
/// used to arm on the prefs list ALONE. Because Game Day's delete path only
/// ever touches Firestore — `team_registration_service.dart:118-122` deletes
/// the subcollection doc, `:214-235` strips the profile arrays — and never the
/// prefs store, deleting a team left a prefs config behind that still armed
/// monitoring. Deleting the Game Day doc removed the very record that would
/// have suppressed the orphan, so the user kept getting celebrations for teams
/// they had removed.
///
/// A legacy config is therefore honoured only when Firestore still corroborates
/// it: the team has a Game Day doc (in which case Game Day wins above and this
/// path is not reached) OR its name is still on the profile arrays passed as
/// [profileTeamNames]. Lacking BOTH, the entry is reported in
/// [MonitoringPlan.orphanedLegacy] — so migration can still see and adopt it —
/// but is kept OUT of [MonitoringPlan.monitored].
///
/// [profileTeamNames] is the Firestore-derived `sports_teams` /
/// `sports_team_priority` list. The background isolate has no Firestore access,
/// so it receives the mirror the UI layer persists via `saveUserTeamPriority`
/// (`game_day_autopilot_providers.dart:297`). An empty list means "no teams on
/// the profile", which correctly disarms every orphan; accounts that are fine
/// are untouched, because their teams are either Game Day docs or present on
/// the profile arrays.
MonitoringPlan resolveMonitoring({
  required List<BackgroundGameDayAutopilotConfig> gameDayConfigs,
  required List<ScoreAlertConfig> legacyAlertConfigs,
  required List<String> profileTeamNames,
}) {
  final monitored = <ScoreAlertConfig>[];
  final gameDaySlugs = <String>{};

  for (final c in gameDayConfigs) {
    gameDaySlugs.add(c.teamSlug);
    if (c.isMonitored) monitored.add(monitoringConfigFor(c));
  }

  final profileTeamKeys = profileTeamNames.map(_profileKey).toSet();

  final orphaned = <ScoreAlertConfig>[];
  for (final legacy in legacyAlertConfigs) {
    if (gameDaySlugs.contains(legacy.teamSlug)) continue; // Game Day wins.
    orphaned.add(legacy);
    if (!legacy.isEnabled) continue;
    // No Game Day doc (we are past the `continue` above) AND no profile entry
    // ⇒ the team was deleted, or never really existed. Do not arm it.
    if (!_isCarriedOnProfile(legacy.teamSlug, profileTeamKeys)) continue;
    monitored.add(legacy);
  }

  return MonitoringPlan(monitored: monitored, orphanedLegacy: orphaned);
}

/// Should the poll loop run scoring checks at all?
///
/// This replaces the old `if (active.isNotEmpty)` gate, where `active` meant
/// enabled SPORTS-ALERT configs. An active Game Day session counts on its own,
/// which is what makes a mid-game "Light It Up Now" tap start monitoring from
/// that second — previously the tap lit the house and armed nothing.
bool shouldPollScores({
  required MonitoringPlan plan,
  required bool hasActiveGameDaySession,
}) =>
    plan.isNotEmpty || hasActiveGameDaySession;

/// Poll cadence. An active Game Day session is "active" for cadence purposes,
/// not merely for arming — a mid-game join needs 30s scoring, not 5-minute.
Duration monitoringPollInterval({
  required bool hasActiveGameDaySession,
}) =>
    hasActiveGameDaySession
        ? const Duration(seconds: 30)
        : const Duration(minutes: 5);

// ─────────────────────────────────────────────────────────────────────────
// Migration
// ─────────────────────────────────────────────────────────────────────────

/// Build the Game Day configs that adopt orphaned alert-only teams.
///
/// MONITORING-ONLY BY CONSTRUCTION: `enabled: false` (so the server planner's
/// `.where("enabled","==",true)` never returns them and they cannot produce a
/// first-pitch fire) + `liveScoringEnabled: true` (so monitoring and
/// celebrations continue exactly as they did). The user keeps what worked, is
/// never asked to re-opt-in, and gets no lighting they did not ask for. They
/// can turn the show on later from the one surface that now owns it.
///
/// Pure: the caller persists the result. Teams already having a Game Day config
/// are not touched — [orphaned] should come from [MonitoringPlan.orphanedLegacy].
List<GameDayAutopilotConfig> migrationConfigsFor(
  List<ScoreAlertConfig> orphaned, {
  required DateTime now,
  Map<String, ({String teamName, String espnTeamId, int primary, int secondary})>?
      teamMetadata,
}) {
  final out = <GameDayAutopilotConfig>[];
  for (final a in orphaned) {
    final meta = teamMetadata?[a.teamSlug];
    out.add(GameDayAutopilotConfig(
      teamSlug: a.teamSlug,
      teamName: meta?.teamName ?? a.teamSlug,
      espnTeamId: meta?.espnTeamId ?? '',
      sport: a.sport,
      primaryColorValue: meta?.primary ?? 0xFF000000,
      secondaryColorValue: meta?.secondary ?? 0xFFFFFFFF,
      // The whole point — monitored, not shown.
      enabled: false,
      liveScoringEnabled: true,
      // Carry the user's tuning across rather than resetting it.
      alertSensitivity: a.sensitivity,
      scoreCelebrationEnabled: true,
      createdAt: now,
      updatedAt: now,
    ));
  }
  return out;
}
