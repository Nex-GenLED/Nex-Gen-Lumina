// lib/features/ai/ephemeral_session_dispatcher.dart
//
// Item #51 Prompt 3 — stateless dispatch helper that bridges the AI's
// emitted [EphemeralSessionIntent] to [EphemeralGameSessionService].
// Centralises the resolve-and-create logic so lumina_bottom_sheet and
// lumina_ai_screen don't duplicate it.
//
// Time-formatting discipline (Item #63 lesson): every game start/end time
// is converted via .toLocal() before extracting hour/minute/year/month/day.
// ESPN-sourced DateTime values are UTC-flagged; reading clock fields from
// them directly returns UTC values.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game_day/ephemeral_session/ephemeral_game_session_providers.dart';
import '../neighborhood/widgets/season_schedule_picker.dart'
    show gameScheduleServiceProvider;
import '../sports_alerts/data/team_colors.dart';
import '../sports_alerts/models/game_event.dart';
import 'ephemeral_session_intent.dart';

/// Result of an [EphemeralSessionDispatcher.dispatch] call.
///
/// Carries the structured outcome so handler sites can build chat
/// confirmation strings without duplicating game-time formatting or
/// no-game-found messaging logic.
class DispatchResult {
  /// Firestore document IDs of created sessions. One per resolved game
  /// (handles doubleheaders).
  final List<String> createdSessionIds;

  /// Pre-formatted display labels per session, e.g.
  /// 'Kansas City Royals — 7:00 PM'. Local-time formatted.
  final List<String> sessionLabels;

  /// Human-readable team name from kTeamColors[slug].teamName, or null
  /// when the slug was unknown.
  final String? teamDisplayName;

  /// Echoes the intent's revertLabel for handler convenience when
  /// building chat confirmation text.
  final String revertLabel;

  /// Populated when the resolution returned no games for the target date
  /// (or when 'next' anchor found no upcoming games). Carries a complete
  /// user-facing sentence; handlers append it to the AI's response text.
  final String? noGameFoundMessage;

  /// True when the dispatch completed without a hard error. False only
  /// for unexpected failures (network, service unavailable, unknown slug).
  /// noGameFoundMessage represents a *successful* dispatch with no games
  /// to track, so success=true in that case.
  final bool success;

  /// Populated only when [success] is false. Internal error string for
  /// debug logging — handlers do NOT surface this to users.
  final String? errorMessage;

  const DispatchResult({
    required this.createdSessionIds,
    required this.sessionLabels,
    required this.teamDisplayName,
    required this.revertLabel,
    required this.noGameFoundMessage,
    required this.success,
    required this.errorMessage,
  });
}

class EphemeralSessionDispatcher {
  EphemeralSessionDispatcher._();

  /// Resolve the AI's [intent] into one or more EphemeralGameSession rows
  /// in Firestore and start phase-machine tracking for each.
  ///
  /// [ref] is the [WidgetRef] from the calling chat surface; the dispatcher
  /// reads (not watches) provider state to fetch the per-user session
  /// service and the schedule service.
  ///
  /// [userId] is accepted for log/audit context; the per-user service is
  /// resolved from the Riverpod provider (which itself watches auth state).
  static Future<DispatchResult> dispatch({
    required EphemeralSessionIntent intent,
    required WidgetRef ref,
    required String userId,
  }) async {
    debugPrint(
        '[EphemeralSessionDispatcher] Dispatching intent (uid=$userId): $intent');

    final teamInfo = kTeamColors[intent.teamSlug];
    if (teamInfo == null) {
      final result = DispatchResult(
        createdSessionIds: const [],
        sessionLabels: const [],
        teamDisplayName: null,
        revertLabel: intent.revertLabel,
        noGameFoundMessage: null,
        success: false,
        errorMessage: 'Unknown team slug: ${intent.teamSlug}',
      );
      debugPrint(
          '[EphemeralSessionDispatcher] Result: created=0, noGame=false, error=${result.errorMessage}');
      return result;
    }

    final sessionService = ref.read(ephemeralGameSessionServiceProvider);
    if (sessionService == null) {
      final result = DispatchResult(
        createdSessionIds: const [],
        sessionLabels: const [],
        teamDisplayName: teamInfo.teamName,
        revertLabel: intent.revertLabel,
        noGameFoundMessage: null,
        success: false,
        errorMessage: 'EphemeralGameSessionService unavailable (user not authenticated)',
      );
      debugPrint(
          '[EphemeralSessionDispatcher] Result: created=0, noGame=false, error=${result.errorMessage}');
      return result;
    }

    final scheduleService = ref.read(gameScheduleServiceProvider);

    // ── Resolve target date based on anchor ─────────────────────────────
    DateTime? targetDate;
    try {
      switch (intent.gameAnchorType) {
        case 'today':
        case 'tonight':
          // DateTime.now() is local-flagged; downstream resolveGames keys
          // on local y/m/d, which is what 'today' means to the user.
          targetDate = DateTime.now();
          break;
        case 'tomorrow':
          targetDate = DateTime.now().add(const Duration(days: 1));
          break;
        case 'specific_date':
          // YYYY-MM-DD parses as local-flagged midnight.
          targetDate = DateTime.parse(intent.gameAnchorSpecificDate!);
          break;
        case 'next':
          // No service-level helper returns the matching GameEvent for
          // 'next' directly; chain fetchNextGameDate → resolveGamesForTeamOnDate.
          // .toLocal() before passing the date so the local-day key matches
          // (Item #63 discipline).
          final next = await scheduleService.fetchNextGameDate(
            teamInfo.espnTeamId,
            teamInfo.sport,
          );
          if (next != null) {
            targetDate = next.toLocal();
          }
          break;
      }
    } catch (e) {
      final result = DispatchResult(
        createdSessionIds: const [],
        sessionLabels: const [],
        teamDisplayName: teamInfo.teamName,
        revertLabel: intent.revertLabel,
        noGameFoundMessage: null,
        success: false,
        errorMessage: 'Failed to resolve target date: $e',
      );
      debugPrint(
          '[EphemeralSessionDispatcher] Result: created=0, noGame=false, error=${result.errorMessage}');
      return result;
    }

    if (targetDate == null) {
      // 'next' anchor with no upcoming games in the lookahead window.
      final result = DispatchResult(
        createdSessionIds: const [],
        sessionLabels: const [],
        teamDisplayName: teamInfo.teamName,
        revertLabel: intent.revertLabel,
        noGameFoundMessage:
            "I couldn't find an upcoming ${teamInfo.teamName} game in the next two weeks, but I've applied the colors anyway.",
        success: true,
        errorMessage: null,
      );
      debugPrint(
          '[EphemeralSessionDispatcher] Result: created=0, noGame=true (next anchor empty)');
      return result;
    }

    // ── Resolve games on that date ──────────────────────────────────────
    List<GameEvent> games;
    try {
      games = await scheduleService.resolveGamesForTeamOnDate(
        intent.teamSlug,
        targetDate,
      );
    } catch (e) {
      final result = DispatchResult(
        createdSessionIds: const [],
        sessionLabels: const [],
        teamDisplayName: teamInfo.teamName,
        revertLabel: intent.revertLabel,
        noGameFoundMessage: null,
        success: false,
        errorMessage: 'Failed to fetch schedule: $e',
      );
      debugPrint(
          '[EphemeralSessionDispatcher] Result: created=0, noGame=false, error=${result.errorMessage}');
      return result;
    }

    if (games.isEmpty) {
      final dateLabel =
          _humanDateForAnchor(intent.gameAnchorType, targetDate);
      final result = DispatchResult(
        createdSessionIds: const [],
        sessionLabels: const [],
        teamDisplayName: teamInfo.teamName,
        revertLabel: intent.revertLabel,
        noGameFoundMessage:
            "There's no ${teamInfo.teamName} game $dateLabel, but I've applied the colors anyway. Want me to set this up for the next ${teamInfo.teamName} game instead?",
        success: true,
        errorMessage: null,
      );
      debugPrint(
          '[EphemeralSessionDispatcher] Result: created=0, noGame=true');
      return result;
    }

    // ── 'tonight' filter ────────────────────────────────────────────────
    // When multiple games are returned and the anchor is 'tonight', keep
    // only games starting at or after 5pm local time. If the filter empties
    // the list, fall back to the unfiltered set ('today' semantics).
    if (intent.gameAnchorType == 'tonight' && games.length > 1) {
      final filtered =
          games.where((g) => g.scheduledDate.toLocal().hour >= 17).toList();
      if (filtered.isNotEmpty) {
        games = filtered;
      }
    }

    // ── Create one session per resolved game ────────────────────────────
    final createdSessionIds = <String>[];
    final sessionLabels = <String>[];
    for (final game in games) {
      try {
        final session = await sessionService.createSession(
          teamSlug: intent.teamSlug,
          gameId: game.gameId,
          revertWledPayload: intent.revertWledPayload,
          revertLabel: intent.revertLabel,
        );
        await sessionService.startTracking(session.sessionId);
        createdSessionIds.add(session.sessionId);
        sessionLabels.add(
            '${teamInfo.teamName} — ${_formatGameTime(game.scheduledDate)}');
      } catch (e) {
        debugPrint(
            '[EphemeralSessionDispatcher] failed to create session for game ${game.gameId}: $e');
      }
    }

    final result = DispatchResult(
      createdSessionIds: createdSessionIds,
      sessionLabels: sessionLabels,
      teamDisplayName: teamInfo.teamName,
      revertLabel: intent.revertLabel,
      noGameFoundMessage: null,
      success: createdSessionIds.isNotEmpty,
      errorMessage: createdSessionIds.isEmpty
          ? 'Failed to create any sessions for ${games.length} resolved games'
          : null,
    );
    debugPrint(
        '[EphemeralSessionDispatcher] Result: created=${result.createdSessionIds.length}, noGame=${result.noGameFoundMessage != null}');
    return result;
  }

  // ── Time formatting helpers (.toLocal() discipline per Item #63) ──────

  /// Format a UTC-flagged DateTime as 'h:mm AM/PM' in the device's local
  /// timezone. Per Item #63 lesson, ESPN-sourced timestamps are UTC and
  /// must be converted before clock-field extraction.
  static String _formatGameTime(DateTime utcStart) {
    final local = utcStart.toLocal();
    final h24 = local.hour;
    final m = local.minute;
    final hour12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final period = h24 >= 12 ? 'PM' : 'AM';
    final mm = m.toString().padLeft(2, '0');
    return '$hour12:$mm $period';
  }

  static String _humanDateForAnchor(String anchorType, DateTime targetDate) {
    switch (anchorType) {
      case 'today':
      case 'tonight':
        return 'today';
      case 'tomorrow':
        return 'tomorrow';
      case 'specific_date':
        final local = targetDate.toLocal();
        return 'on ${_monthAbbrev(local.month)} ${local.day}';
      case 'next':
        return 'coming up';
    }
    return '';
  }

  static String _monthAbbrev(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }
}
