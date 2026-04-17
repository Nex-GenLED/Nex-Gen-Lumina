import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../../../utils/time_format.dart';
import '../../sports_alerts/models/game_event.dart';
import '../../sports_alerts/models/game_state.dart';
import '../../sports_alerts/models/sport_type.dart';
import '../../sports_alerts/services/game_schedule_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SEASON SCHEDULE PICKER
// ═════════════════════════════════════════════════════════════════════════════
//
// Shows a team's full season schedule (home games by default) with checkboxes
// for per-game deselection. Used in the Sync Event creation flow when the
// user enables "Every home game this season".
// ═════════════════════════════════════════════════════════════════════════════

/// Provider for the GameScheduleService singleton.
final gameScheduleServiceProvider = Provider<GameScheduleService>((ref) {
  final service = GameScheduleService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Fetches the season schedule for a given team.
final seasonScheduleProvider = FutureProvider.family<List<GameEvent>,
    ({String espnTeamId, SportType sport, int season})>(
  (ref, params) {
    final service = ref.watch(gameScheduleServiceProvider);
    return service.fetchSeasonSchedule(
      espnTeamId: params.espnTeamId,
      sport: params.sport,
      season: params.season,
      homeGamesOnly: true,
    );
  },
);

/// Infers the current season year for a sport.
int currentSeasonYear(SportType sport) {
  final now = DateTime.now();
  // NFL/NHL/NBA seasons start in fall and span two calendar years.
  // MLB/MLS seasons are within a single calendar year.
  switch (sport) {
    case SportType.nfl:
    case SportType.nhl:
    case SportType.nba:
    case SportType.ncaaFB:
    case SportType.ncaaMB:
      // If we're in Jan-June, we're in the season that started last year
      return now.month <= 6 ? now.year - 1 : now.year;
    case SportType.mlb:
    case SportType.mls:
    case SportType.fifa:
    case SportType.championsLeague:
      return now.year;
  }
}

/// Widget that displays the season schedule with per-game toggle checkboxes.
class SeasonSchedulePicker extends ConsumerStatefulWidget {
  final String espnTeamId;
  final String teamName;
  final SportType sport;
  final Color teamColor;

  /// Game IDs that are currently excluded (unchecked).
  final Set<String> excludedGameIds;

  /// Called when the excluded set changes.
  final ValueChanged<Set<String>> onExcludedChanged;

  const SeasonSchedulePicker({
    super.key,
    required this.espnTeamId,
    required this.teamName,
    required this.sport,
    required this.teamColor,
    required this.excludedGameIds,
    required this.onExcludedChanged,
  });

  @override
  ConsumerState<SeasonSchedulePicker> createState() =>
      _SeasonSchedulePickerState();
}

class _SeasonSchedulePickerState extends ConsumerState<SeasonSchedulePicker> {
  late int _season;

  @override
  void initState() {
    super.initState();
    _season = currentSeasonYear(widget.sport);
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(seasonScheduleProvider((
      espnTeamId: widget.espnTeamId,
      sport: widget.sport,
      season: _season,
    )));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with season selector
        _buildHeader(),
        const SizedBox(height: 12),

        // Schedule list
        scheduleAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(color: NexGenPalette.cyan),
            ),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(Icons.cloud_off, color: Colors.white38, size: 40),
                const SizedBox(height: 8),
                Text(
                  'Unable to load schedule.\nCheck your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(seasonScheduleProvider((
                    espnTeamId: widget.espnTeamId,
                    sport: widget.sport,
                    season: _season,
                  ))),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (games) => _buildGameList(games),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final upcomingCount = ref
            .watch(seasonScheduleProvider((
              espnTeamId: widget.espnTeamId,
              sport: widget.sport,
              season: _season,
            )))
            .valueOrNull
            ?.where((g) => g.isUpcoming)
            .length ??
        0;

    final excludedCount = widget.excludedGameIds.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.teamColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.teamColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month,
                  color: widget.teamColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${widget.teamName} Home Games',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Season year chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _seasonLabel,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          if (upcomingCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '$upcomingCount upcoming${excludedCount > 0 ? ' ($excludedCount skipped)' : ''}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  String get _seasonLabel {
    switch (widget.sport) {
      case SportType.nfl:
      case SportType.nhl:
      case SportType.nba:
      case SportType.ncaaFB:
      case SportType.ncaaMB:
        return '$_season-${(_season + 1) % 100}';
      case SportType.mlb:
      case SportType.mls:
      case SportType.fifa:
      case SportType.championsLeague:
        return '$_season';
    }
  }

  Widget _buildGameList(List<GameEvent> games) {
    if (games.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No home games found for the $_seasonLabel season.',
            style: TextStyle(color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Split into upcoming and past
    final upcoming = games.where((g) => g.isUpcoming).toList();
    final past = games.where((g) => !g.isUpcoming).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Select all / deselect all
        if (upcoming.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                TextButton(
                  onPressed: () {
                    // Select all: remove all upcoming from excluded
                    final updated = Set<String>.from(widget.excludedGameIds);
                    for (final g in upcoming) {
                      updated.remove(g.gameId);
                    }
                    widget.onExcludedChanged(updated);
                  },
                  child: Text(
                    'Select All',
                    style: TextStyle(
                        color: widget.teamColor, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Deselect all: add all upcoming to excluded
                    final updated = Set<String>.from(widget.excludedGameIds);
                    for (final g in upcoming) {
                      updated.add(g.gameId);
                    }
                    widget.onExcludedChanged(updated);
                  },
                  child: const Text(
                    'Deselect All',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // Upcoming games
        if (upcoming.isNotEmpty) ...[
          ...upcoming.map((game) => _GameRow(
                game: game,
                isExcluded: widget.excludedGameIds.contains(game.gameId),
                teamColor: widget.teamColor,
                onToggle: () => _toggleGame(game.gameId),
              )),
        ],

        // Past games (greyed out, not toggleable)
        if (past.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              'Completed (${past.length})',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          ...past.map((game) => _GameRow(
                game: game,
                isExcluded: false,
                teamColor: widget.teamColor,
                isPast: true,
                onToggle: null,
              )),
        ],
      ],
    );
  }

  void _toggleGame(String gameId) {
    final updated = Set<String>.from(widget.excludedGameIds);
    if (updated.contains(gameId)) {
      updated.remove(gameId);
    } else {
      updated.add(gameId);
    }
    widget.onExcludedChanged(updated);
  }
}

class _GameRow extends ConsumerWidget {
  final GameEvent game;
  final bool isExcluded;
  final Color teamColor;
  final bool isPast;
  final VoidCallback? onToggle;

  const _GameRow({
    required this.game,
    required this.isExcluded,
    required this.teamColor,
    this.isPast = false,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localDate = game.scheduledDate.toLocal();
    final timeFormat = ref.watch(timeFormatPreferenceProvider);
    final isIncluded = !isExcluded && !isPast;

    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        child: Row(
          children: [
            // Checkbox (only for upcoming games)
            if (!isPast)
              Checkbox(
                value: isIncluded,
                onChanged: (_) => onToggle?.call(),
                activeColor: teamColor,
                checkColor: Colors.black,
                side: BorderSide(
                  color: isExcluded ? Colors.grey.shade700 : teamColor,
                ),
              ),
            if (isPast) const SizedBox(width: 48),

            // Date column
            SizedBox(
              width: 100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(localDate),
                    style: TextStyle(
                      color: isPast
                          ? Colors.grey.shade700
                          : isExcluded
                              ? Colors.grey.shade600
                              : Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      decoration:
                          isExcluded ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    formatTime(localDate, timeFormat: timeFormat),
                    style: TextStyle(
                      color: isPast ? Colors.grey.shade800 : Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Opponent
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'vs ${game.awayTeam}',
                    style: TextStyle(
                      color: isPast
                          ? Colors.grey.shade700
                          : isExcluded
                              ? Colors.grey.shade600
                              : Colors.white70,
                      fontSize: 13,
                      decoration:
                          isExcluded ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (game.venue != null)
                    Text(
                      game.venue!,
                      style: TextStyle(
                          color: Colors.grey.shade700, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Status badge
            if (game.status == GameStatus.final_)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Final',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 10),
                ),
              ),
            if (game.status == GameStatus.inProgress)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _formatDate(DateTime dt) {
    final wd = _weekdays[dt.weekday - 1];
    final mo = _months[dt.month - 1];
    return '$wd, $mo ${dt.day}';
  }

}
