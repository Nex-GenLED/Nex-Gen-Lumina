import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../sports_alerts/models/game_event.dart';
import '../../sports_alerts/models/sport_type.dart';
import '../../sports_alerts/services/game_schedule_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SEASON SCHEDULE RECONCILIATION
// ═════════════════════════════════════════════════════════════════════════════
//
// Runs daily (from the background service or foreground) to detect changes
// in the ESPN season schedule for any active "season schedule" sync events.
//
// Flow:
//  1. Load the last-known schedule from SharedPreferences
//  2. Fetch the latest schedule from ESPN (via GameScheduleService)
//  3. Diff the two and detect added, removed, or rescheduled games
//  4. If changes are found, persist them and return a ScheduleReconciliationResult
//  5. The caller (background worker or UI provider) handles notifications
// ═════════════════════════════════════════════════════════════════════════════

const _kLastReconciliationPrefix = 'season_reconcile_ts_';
const _kCachedSchedulePrefix = 'season_reconcile_schedule_';

/// Result of a schedule reconciliation check.
class ScheduleReconciliationResult {
  final String syncEventId;
  final String teamName;
  final SportType sport;
  final ScheduleDiff diff;
  final List<GameEvent> updatedSchedule;

  const ScheduleReconciliationResult({
    required this.syncEventId,
    required this.teamName,
    required this.sport,
    required this.diff,
    required this.updatedSchedule,
  });

  bool get hasChanges => diff.hasChanges;

  String get changesSummary {
    final parts = <String>[];
    if (diff.added.isNotEmpty) {
      parts.add('${diff.added.length} new game(s)');
    }
    if (diff.removed.isNotEmpty) {
      parts.add('${diff.removed.length} cancelled game(s)');
    }
    if (diff.rescheduled.isNotEmpty) {
      parts.add('${diff.rescheduled.length} rescheduled game(s)');
    }
    return parts.join(', ');
  }
}

/// Performs daily reconciliation for a season schedule sync event.
///
/// Returns null if no check was needed (already checked today) or if
/// there were no changes.
Future<ScheduleReconciliationResult?> reconcileSeasonSchedule({
  required String syncEventId,
  required String espnTeamId,
  required String teamName,
  required SportType sport,
  required int season,
  required GameScheduleService scheduleService,
  bool forceCheck = false,
}) async {
  final cacheKey = '${syncEventId}_${sport.name}_$espnTeamId';

  // 1. Check if we already reconciled today (unless forced)
  if (!forceCheck) {
    final shouldCheck = await _shouldReconcile(cacheKey);
    if (!shouldCheck) {
      debugPrint('[Reconciliation] Already checked today for $cacheKey');
      return null;
    }
  }

  debugPrint('[Reconciliation] Running schedule check for $teamName ($cacheKey)');

  // 2. Load the last-known schedule
  final previousGames = await _loadCachedSchedule(cacheKey);

  // 3. Fetch latest from ESPN (this forces a cache refresh in GameScheduleService)
  await scheduleService.invalidateCache(
    espnTeamId: espnTeamId,
    sport: sport,
    season: season,
  );

  final latestGames = await scheduleService.fetchSeasonSchedule(
    espnTeamId: espnTeamId,
    sport: sport,
    season: season,
    homeGamesOnly: true,
  );

  if (latestGames.isEmpty) {
    debugPrint('[Reconciliation] No games returned from ESPN for $cacheKey');
    await _markReconciled(cacheKey);
    return null;
  }

  // 4. If no previous schedule exists (first reconciliation), just save and return
  if (previousGames.isEmpty) {
    debugPrint('[Reconciliation] First reconciliation for $cacheKey, saving baseline');
    await _saveCachedSchedule(cacheKey, latestGames);
    await _markReconciled(cacheKey);
    return null;
  }

  // 5. Diff the schedules
  final diff = _diffSchedules(previousGames, latestGames);

  // 6. Save the updated schedule regardless
  await _saveCachedSchedule(cacheKey, latestGames);
  await _markReconciled(cacheKey);

  if (!diff.hasChanges) {
    debugPrint('[Reconciliation] No changes detected for $cacheKey');
    return null;
  }

  debugPrint('[Reconciliation] Changes detected for $cacheKey: '
      '${diff.added.length} added, ${diff.removed.length} removed, '
      '${diff.rescheduled.length} rescheduled');

  return ScheduleReconciliationResult(
    syncEventId: syncEventId,
    teamName: teamName,
    sport: sport,
    diff: diff,
    updatedSchedule: latestGames,
  );
}


// ═════════════════════════════════════════════════════════════════════════════
// Internal helpers
// ═════════════════════════════════════════════════════════════════════════════

/// Check if we should reconcile (haven't checked in the last 20 hours).
/// Using 20 hours instead of 24 to allow slight drift in background timing.
Future<bool> _shouldReconcile(String cacheKey) async {
  final prefs = await SharedPreferences.getInstance();
  final tsStr = prefs.getString('$_kLastReconciliationPrefix$cacheKey');
  if (tsStr == null) return true;

  final lastCheck = DateTime.tryParse(tsStr);
  if (lastCheck == null) return true;

  return DateTime.now().difference(lastCheck).inHours >= 20;
}

Future<void> _markReconciled(String cacheKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    '$_kLastReconciliationPrefix$cacheKey',
    DateTime.now().toIso8601String(),
  );
}

Future<List<GameEvent>> _loadCachedSchedule(String cacheKey) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = prefs.getString('$_kCachedSchedulePrefix$cacheKey');
    if (dataStr == null) return const [];

    final list = jsonDecode(dataStr) as List<dynamic>;
    return list
        .map((e) => GameEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (e) {
    debugPrint('[Reconciliation] Error loading cached schedule: $e');
    return const [];
  }
}

Future<void> _saveCachedSchedule(
  String cacheKey,
  List<GameEvent> games,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = jsonEncode(games.map((g) => g.toJson()).toList());
    await prefs.setString('$_kCachedSchedulePrefix$cacheKey', dataStr);
  } catch (e) {
    debugPrint('[Reconciliation] Error saving cached schedule: $e');
  }
}

ScheduleDiff _diffSchedules(
  List<GameEvent> previous,
  List<GameEvent> latest,
) {
  final previousIds = {for (final g in previous) g.gameId};
  final latestIds = {for (final g in latest) g.gameId};
  final latestById = {for (final g in latest) g.gameId: g};
  final previousById = {for (final g in previous) g.gameId: g};

  final added = latest.where((g) => !previousIds.contains(g.gameId)).toList();
  final removed =
      previous.where((g) => !latestIds.contains(g.gameId)).toList();

  final rescheduled = <RescheduledGame>[];
  for (final gameId in previousIds.intersection(latestIds)) {
    final prev = previousById[gameId]!;
    final curr = latestById[gameId]!;
    final timeDiff = curr.scheduledDate.difference(prev.scheduledDate).abs();
    if (timeDiff.inMinutes > 5) {
      rescheduled.add(RescheduledGame(
        gameId: gameId,
        oldDate: prev.scheduledDate,
        newDate: curr.scheduledDate,
        opponent: curr.isHome ? curr.awayTeam : curr.homeTeam,
      ));
    }
  }

  return ScheduleDiff(
    added: added,
    removed: removed,
    rescheduled: rescheduled,
    hasChanges:
        added.isNotEmpty || removed.isNotEmpty || rescheduled.isNotEmpty,
  );
}

