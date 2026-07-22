import 'game_state.dart';
import 'sport_type.dart';

/// A scheduled game from the ESPN season schedule API.
///
/// Unlike [GameState] which tracks live scores, a [GameEvent] represents
/// a future (or past) scheduled game in the season calendar. Used by the
/// "Every home game this season" feature to auto-create Sync Events.
class GameEvent {
  /// ESPN event ID (same as [GameState.gameId] once the game goes live).
  final String gameId;

  /// Home team display name.
  final String homeTeam;

  /// Away team display name (opponent).
  final String awayTeam;

  /// ESPN numeric ID for the home team.
  final String homeTeamId;

  /// ESPN numeric ID for the away team.
  final String awayTeamId;

  /// Scheduled start time in UTC.
  final DateTime scheduledDate;

  /// Whether this is a home game for the queried team.
  final bool isHome;

  /// Sport type for this game.
  final SportType sport;

  /// ESPN season year (e.g. 2025 for the 2025-26 NFL season).
  final int season;

  /// Short venue name if available (e.g., "Arrowhead Stadium").
  final String? venue;

  /// Current game status (scheduled, in progress, final).
  final GameStatus status;

  const GameEvent({
    required this.gameId,
    required this.homeTeam,
    required this.awayTeam,
    this.homeTeamId = '',
    this.awayTeamId = '',
    required this.scheduledDate,
    this.isHome = true,
    required this.sport,
    required this.season,
    this.venue,
    this.status = GameStatus.scheduled,
  });

  /// Whether this game is in the future.
  bool get isUpcoming => scheduledDate.isAfter(DateTime.now());

  /// Whether this game has already been played.
  bool get isCompleted => status == GameStatus.final_;

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'homeTeam': homeTeam,
        'awayTeam': awayTeam,
        'homeTeamId': homeTeamId,
        'awayTeamId': awayTeamId,
        'scheduledDate': scheduledDate.toIso8601String(),
        'isHome': isHome,
        'sport': sport.toJson(),
        'season': season,
        'venue': venue,
        'status': status.toJson(),
      };

  factory GameEvent.fromJson(Map<String, dynamic> json) {
    return GameEvent(
      gameId: json['gameId'] as String,
      homeTeam: json['homeTeam'] as String,
      awayTeam: json['awayTeam'] as String,
      homeTeamId: json['homeTeamId'] as String? ?? '',
      awayTeamId: json['awayTeamId'] as String? ?? '',
      scheduledDate: DateTime.parse(json['scheduledDate'] as String),
      isHome: json['isHome'] as bool? ?? true,
      sport: SportType.fromJson(json['sport'] as String),
      season: json['season'] as int,
      venue: json['venue'] as String?,
      status: GameStatus.fromJson(json['status'] as String? ?? 'scheduled'),
    );
  }

  GameEvent copyWith({
    String? gameId,
    String? homeTeam,
    String? awayTeam,
    String? homeTeamId,
    String? awayTeamId,
    DateTime? scheduledDate,
    bool? isHome,
    SportType? sport,
    int? season,
    String? venue,
    GameStatus? status,
  }) {
    return GameEvent(
      gameId: gameId ?? this.gameId,
      homeTeam: homeTeam ?? this.homeTeam,
      awayTeam: awayTeam ?? this.awayTeam,
      homeTeamId: homeTeamId ?? this.homeTeamId,
      awayTeamId: awayTeamId ?? this.awayTeamId,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      isHome: isHome ?? this.isHome,
      sport: sport ?? this.sport,
      season: season ?? this.season,
      venue: venue ?? this.venue,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameEvent &&
          runtimeType == other.runtimeType &&
          gameId == other.gameId;

  @override
  int get hashCode => gameId.hashCode;

  @override
  String toString() =>
      'GameEvent($gameId: $awayTeam @ $homeTeam, ${scheduledDate.toLocal()})';
}
