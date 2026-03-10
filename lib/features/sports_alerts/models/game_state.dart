/// Current status of a game.
enum GameStatus {
  scheduled,
  inProgress,
  halftime,
  final_;

  factory GameStatus.fromJson(String json) {
    if (json == 'final_' || json == 'final') return GameStatus.final_;
    return GameStatus.values.firstWhere((e) => e.name == json);
  }

  String toJson() => name;
}

/// Live snapshot of a game's state from the ESPN API.
class GameState {
  final String gameId;
  final String homeTeam;
  final String awayTeam;
  final String homeTeamId;
  final String awayTeamId;
  final int homeScore;
  final int awayScore;
  final GameStatus status;
  final String? period;
  final String? clock;
  final DateTime lastUpdated;

  const GameState({
    required this.gameId,
    required this.homeTeam,
    required this.awayTeam,
    this.homeTeamId = '',
    this.awayTeamId = '',
    this.homeScore = 0,
    this.awayScore = 0,
    this.status = GameStatus.scheduled,
    this.period,
    this.clock,
    required this.lastUpdated,
  });

  /// NBA clutch time: last 2 minutes of 4th quarter or overtime,
  /// with a margin of 5 points or fewer.
  bool get isClutchTime {
    if (status != GameStatus.inProgress) return false;

    final p = period;
    if (p == null) return false;

    final periodNum = int.tryParse(p);
    // 4th quarter = 4, overtime periods = 5+
    final isLateGame = (periodNum != null && periodNum >= 4);
    if (!isLateGame) return false;

    final margin = (homeScore - awayScore).abs();
    if (margin > 5) return false;

    // Parse clock string like "1:42" or "0:30.5"
    final c = clock;
    if (c == null) return true; // no clock data, assume clutch if period >= 4

    final parts = c.split(':');
    if (parts.length != 2) return true;

    final minutes = int.tryParse(parts[0]) ?? 0;
    return minutes < 2;
  }

  /// NCAA MBB clutch time: last 5 minutes of 2nd half or overtime,
  /// with a margin of 8 points or fewer.
  bool get isCollegeBasketballClutchTime {
    if (status != GameStatus.inProgress) return false;

    final p = period;
    if (p == null) return false;

    final periodNum = int.tryParse(p);
    // 2nd half = 2, overtime periods = 3+
    final isLateGame = (periodNum != null && periodNum >= 2);
    if (!isLateGame) return false;

    final margin = (homeScore - awayScore).abs();
    if (margin > 8) return false;

    final c = clock;
    if (c == null) return true;

    final parts = c.split(':');
    if (parts.length != 2) return true;

    final minutes = int.tryParse(parts[0]) ?? 0;
    return minutes < 5;
  }

  GameState copyWith({
    String? gameId,
    String? homeTeam,
    String? awayTeam,
    String? homeTeamId,
    String? awayTeamId,
    int? homeScore,
    int? awayScore,
    GameStatus? status,
    String? period,
    String? clock,
    DateTime? lastUpdated,
  }) {
    return GameState(
      gameId: gameId ?? this.gameId,
      homeTeam: homeTeam ?? this.homeTeam,
      awayTeam: awayTeam ?? this.awayTeam,
      homeTeamId: homeTeamId ?? this.homeTeamId,
      awayTeamId: awayTeamId ?? this.awayTeamId,
      homeScore: homeScore ?? this.homeScore,
      awayScore: awayScore ?? this.awayScore,
      status: status ?? this.status,
      period: period ?? this.period,
      clock: clock ?? this.clock,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      gameId: json['gameId'] as String,
      homeTeam: json['homeTeam'] as String,
      awayTeam: json['awayTeam'] as String,
      homeTeamId: json['homeTeamId'] as String? ?? '',
      awayTeamId: json['awayTeamId'] as String? ?? '',
      homeScore: json['homeScore'] as int? ?? 0,
      awayScore: json['awayScore'] as int? ?? 0,
      status: GameStatus.fromJson(json['status'] as String),
      period: json['period'] as String?,
      clock: json['clock'] as String?,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'gameId': gameId,
        'homeTeam': homeTeam,
        'awayTeam': awayTeam,
        'homeTeamId': homeTeamId,
        'awayTeamId': awayTeamId,
        'homeScore': homeScore,
        'awayScore': awayScore,
        'status': status.toJson(),
        'period': period,
        'clock': clock,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GameState &&
          runtimeType == other.runtimeType &&
          gameId == other.gameId &&
          homeScore == other.homeScore &&
          awayScore == other.awayScore &&
          status == other.status &&
          period == other.period &&
          clock == other.clock;

  @override
  int get hashCode =>
      Object.hash(gameId, homeScore, awayScore, status, period, clock);

  @override
  String toString() =>
      'GameState(gameId: $gameId, $awayTeam $awayScore @ $homeTeam $homeScore, '
      'status: $status, period: $period, clock: $clock)';
}
