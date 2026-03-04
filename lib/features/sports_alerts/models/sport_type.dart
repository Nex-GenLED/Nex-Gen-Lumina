/// Sport types supported by the Lumina Sports Alerts feature.
enum SportType {
  nfl,
  nba,
  mlb,
  nhl,
  mls;

  factory SportType.fromJson(String json) =>
      SportType.values.firstWhere((e) => e.name == json);

  String toJson() => name;
}

extension SportTypeExtension on SportType {
  /// ESPN API sport/league path segment.
  String get espnSportPath => switch (this) {
        SportType.nfl => 'football/nfl',
        SportType.nba => 'basketball/nba',
        SportType.mlb => 'baseball/mlb',
        SportType.nhl => 'hockey/nhl',
        SportType.mls => 'soccer/usa.1',
      };

  String get displayName => switch (this) {
        SportType.nfl => 'NFL',
        SportType.nba => 'NBA',
        SportType.mlb => 'MLB',
        SportType.nhl => 'NHL',
        SportType.mls => 'MLS',
      };

  /// The primary scoring unit name for display purposes.
  String get scoringUnit => switch (this) {
        SportType.nfl => 'Touchdown',
        SportType.nba => 'Basket',
        SportType.mlb => 'Run',
        SportType.nhl => 'Goal',
        SportType.mls => 'Goal',
      };

  /// Polling interval in seconds during live games.
  /// NBA uses 20s in clutch time, 60s otherwise — callers should check
  /// [GameState.isClutchTime] and use 20 when true.
  int get pollingIntervalSeconds => switch (this) {
        SportType.nfl => 45,
        SportType.nba => 60,
        SportType.mlb => 45,
        SportType.nhl => 45,
        SportType.mls => 45,
      };

  /// Faster polling interval used during clutch/critical moments.
  int get clutchPollingIntervalSeconds => switch (this) {
        SportType.nba => 20,
        _ => pollingIntervalSeconds,
      };
}
