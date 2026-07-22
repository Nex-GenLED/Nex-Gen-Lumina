// lib/features/autopilot/game_day_priority_resolver.dart
//
// Priority coordination between personal Game Day Autopilot sessions and
// Neighborhood Sync sessions. Used by both foreground and background
// evaluators to answer the question: "Which event should drive the lights
// right now?"
//
// Rules (established in v2.1 product design):
//
//   1. Neighborhood Sync wins over personal Game Day for the SAME game.
//      If a neighborhood group is running a sync for the Chiefs vs.
//      Patriots game, the user's personal Chiefs Game Day Autopilot
//      defers to the group. The "bigger moment" wins.
//
//   2. For DIFFERENT games on the same night, team priority wins.
//      User's profile `sportsTeamPriority` list determines order.
//      First-match wins. If team A ranks above team B, team A's event
//      holds the evening regardless of which activated first.
//
//   3. If two events are at the same priority (same team, both personal
//      Game Day, etc.), first-come-first-served.
//
//   4. Longform sync events (Holiday, >24hr duration) yield to any
//      shortform event (Game Day, <8hr). This rule is already enforced
//      by SyncHandoffManager — we preserve it here for completeness but
//      don't duplicate logic.
//
// This resolver is a pure function. Callers are responsible for actually
// pausing, activating, or deferring based on the decision returned.

/// Source of a game day lighting event.
enum GameDayEventSource {
  /// A personal Game Day Autopilot session (individual user's config).
  personalAutopilot,

  /// A neighborhood sync session with category == gameDay.
  neighborhoodSync,
}

/// An event competing for lighting control during a game day window.
///
/// Both personal autopilot sessions and sync sessions convert into this
/// shape for priority comparison. The resolver does not care about the
/// underlying WLED payload — only the metadata needed to pick a winner.
class GameDayEventCandidate {
  /// Unique identifier. For personal events, the team slug (e.g., "chiefs").
  /// For sync events, the sync event id.
  final String id;

  /// Source of this event.
  final GameDayEventSource source;

  /// Team slug (lower-cased). Used to detect same-game matches and to
  /// consult the user's sports team priority list.
  final String teamSlug;

  /// ESPN team ID. Same team slug may map to different ESPN IDs across
  /// leagues (college vs pro) so include both for disambiguation.
  final String espnTeamId;

  /// When this event activated (pre-game start). Used as tiebreaker when
  /// two events share identical priority.
  final DateTime activatedAt;

  /// ESPN game id, when known. Two events with the same gameId are
  /// referring to the same game — neighborhood sync should win by rule 1.
  final String? gameId;

  const GameDayEventCandidate({
    required this.id,
    required this.source,
    required this.teamSlug,
    required this.espnTeamId,
    required this.activatedAt,
    this.gameId,
  });

  @override
  String toString() =>
      'GameDayEventCandidate($source, team=$teamSlug, gameId=$gameId, '
      'activated=$activatedAt)';
}

/// The decision returned by the resolver.
enum GameDayPriorityDecision {
  /// This event should activate or continue. The lights are its to drive.
  activate,

  /// This event should defer — another higher-priority event is active.
  /// Do not apply payloads; do not create a session if starting fresh.
  defer,

  /// This event should preempt a lower-priority event that's currently
  /// active. Caller is responsible for canceling/pausing the incumbent.
  preempt,
}

/// Result of a priority resolution call.
class GameDayPriorityResult {
  /// The decision for the candidate under evaluation.
  final GameDayPriorityDecision decision;

  /// If decision == defer, the event the candidate is deferring to.
  /// If decision == preempt, the event being preempted.
  /// If decision == activate, null.
  final GameDayEventCandidate? affectedBy;

  /// Human-readable reason, useful for debug logging and UI display
  /// ("Chiefs neighborhood sync has priority").
  final String reason;

  const GameDayPriorityResult({
    required this.decision,
    this.affectedBy,
    required this.reason,
  });

  bool get shouldActivate => decision == GameDayPriorityDecision.activate;
  bool get shouldDefer => decision == GameDayPriorityDecision.defer;
  bool get shouldPreempt => decision == GameDayPriorityDecision.preempt;

  @override
  String toString() =>
      'GameDayPriorityResult($decision, reason=$reason, '
      'affectedBy=${affectedBy?.id})';
}

/// Pure priority resolver. No state, no I/O. Safe to call from any
/// isolate including the background service.
class GameDayPriorityResolver {
  /// Resolve whether [candidate] should activate, defer to, or preempt
  /// any event in [activeEvents].
  ///
  /// [teamPriority] is the user's ordered sports team slug list (first =
  /// highest priority). An empty list means no preferred ordering —
  /// falls through to first-come-first-served.
  ///
  /// [activeEvents] are events currently active or recently activated.
  /// Should NOT include [candidate] itself.
  static GameDayPriorityResult resolve({
    required GameDayEventCandidate candidate,
    required List<GameDayEventCandidate> activeEvents,
    required List<String> teamPriority,
  }) {
    if (activeEvents.isEmpty) {
      return const GameDayPriorityResult(
        decision: GameDayPriorityDecision.activate,
        reason: 'No competing events',
      );
    }

    // Rule 1: Same-game match — neighborhood sync wins over personal.
    for (final active in activeEvents) {
      if (_isSameGame(candidate, active)) {
        if (candidate.source == GameDayEventSource.personalAutopilot &&
            active.source == GameDayEventSource.neighborhoodSync) {
          return GameDayPriorityResult(
            decision: GameDayPriorityDecision.defer,
            affectedBy: active,
            reason: 'Neighborhood sync is active for the same game '
                '(${candidate.teamSlug})',
          );
        }
        if (candidate.source == GameDayEventSource.neighborhoodSync &&
            active.source == GameDayEventSource.personalAutopilot) {
          return GameDayPriorityResult(
            decision: GameDayPriorityDecision.preempt,
            affectedBy: active,
            reason: 'Neighborhood sync preempting personal autopilot '
                'for same game (${candidate.teamSlug})',
          );
        }
        // Same source + same game shouldn't happen in practice.
        // Defer to the already-active one.
        return GameDayPriorityResult(
          decision: GameDayPriorityDecision.defer,
          affectedBy: active,
          reason: 'Duplicate event already active for ${candidate.teamSlug}',
        );
      }
    }

    // Rule 2 & 3: Different games — team priority, then first-come-first-served.
    final candidateRank = _priorityRank(candidate.teamSlug, teamPriority);

    for (final active in activeEvents) {
      final activeRank = _priorityRank(active.teamSlug, teamPriority);

      if (candidateRank < activeRank) {
        // Lower rank number = higher priority.
        return GameDayPriorityResult(
          decision: GameDayPriorityDecision.preempt,
          affectedBy: active,
          reason: 'Higher team priority: ${candidate.teamSlug} '
              '(#${candidateRank + 1}) beats ${active.teamSlug} '
              '(#${activeRank + 1})',
        );
      }

      if (candidateRank > activeRank) {
        return GameDayPriorityResult(
          decision: GameDayPriorityDecision.defer,
          affectedBy: active,
          reason: 'Lower team priority: ${candidate.teamSlug} '
              '(#${candidateRank + 1}) yields to ${active.teamSlug} '
              '(#${activeRank + 1})',
        );
      }

      // Equal rank — first-come-first-served.
      if (candidate.activatedAt.isAfter(active.activatedAt)) {
        return GameDayPriorityResult(
          decision: GameDayPriorityDecision.defer,
          affectedBy: active,
          reason: 'Equal priority — ${active.teamSlug} activated first',
        );
      }
    }

    // Candidate has higher or equal priority than all actives and didn't
    // activate after any of them. Good to go.
    return const GameDayPriorityResult(
      decision: GameDayPriorityDecision.activate,
      reason: 'Highest priority among active events',
    );
  }

  /// Two events are "the same game" if:
  ///   - Both have gameIds and they match, OR
  ///   - Both share team slug + ESPN team ID + activated within 6h of
  ///     each other (fallback when gameId isn't available on one side)
  static bool _isSameGame(
    GameDayEventCandidate a,
    GameDayEventCandidate b,
  ) {
    if (a.gameId != null && b.gameId != null && a.gameId == b.gameId) {
      return true;
    }
    if (a.teamSlug == b.teamSlug && a.espnTeamId == b.espnTeamId) {
      final diff = a.activatedAt.difference(b.activatedAt).abs();
      return diff < const Duration(hours: 6);
    }
    return false;
  }

  /// Rank of a team in the priority list. Lower index = higher priority.
  /// Returns teamPriority.length (i.e., last place) for unlisted teams.
  static int _priorityRank(String teamSlug, List<String> teamPriority) {
    final idx = teamPriority.indexOf(teamSlug);
    return idx == -1 ? teamPriority.length : idx;
  }
}
