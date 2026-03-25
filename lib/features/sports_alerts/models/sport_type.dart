/// Sport types supported by the Lumina Sports Alerts feature.
enum SportType {
  nfl,
  nba,
  mlb,
  nhl,
  mls,
  fifa,
  championsLeague,
  ncaaFB, // NCAA Division I FBS Football
  ncaaMB; // NCAA Division I Men's Basketball

  factory SportType.fromJson(String json) =>
      SportType.values.firstWhere((e) => e.name == json);

  String toJson() => name;

  /// Whether this sport type uses soccer scoring rules.
  bool get isSoccer =>
      this == SportType.mls ||
      this == SportType.fifa ||
      this == SportType.championsLeague;

  /// Whether this sport type uses football scoring rules (TD/FG/Safety).
  bool get isFootball => this == SportType.nfl || this == SportType.ncaaFB;

  /// Whether this sport type uses basketball scoring rules.
  bool get isBasketball => this == SportType.nba || this == SportType.ncaaMB;
}

extension SportTypeExtension on SportType {
  /// ESPN API sport/league path segment.
  String get espnSportPath => switch (this) {
        SportType.nfl => 'football/nfl',
        SportType.nba => 'basketball/nba',
        SportType.mlb => 'baseball/mlb',
        SportType.nhl => 'hockey/nhl',
        SportType.mls => 'soccer/usa.1',
        SportType.fifa => 'soccer/fifa.world',
        SportType.championsLeague => 'soccer/uefa.champions',
        SportType.ncaaFB => 'football/college-football',
        SportType.ncaaMB => 'basketball/mens-college-basketball',
      };

  String get displayName => switch (this) {
        SportType.nfl => 'NFL',
        SportType.nba => 'NBA',
        SportType.mlb => 'MLB',
        SportType.nhl => 'NHL',
        SportType.mls => 'MLS',
        SportType.fifa => 'FIFA World Cup',
        SportType.championsLeague => 'Champions League',
        SportType.ncaaFB => 'NCAA Football',
        SportType.ncaaMB => 'NCAA Basketball',
      };

  /// The primary scoring unit name for display purposes.
  String get scoringUnit => switch (this) {
        SportType.nfl || SportType.ncaaFB => 'Touchdown',
        SportType.nba || SportType.ncaaMB => 'Basket',
        SportType.mlb => 'Run',
        SportType.nhl => 'Goal',
        SportType.mls || SportType.fifa || SportType.championsLeague => 'Goal',
      };

  /// Polling interval in seconds during live games.
  /// Soccer uses 60s (goals are rare). NCAA FB uses 90s (longer plays).
  /// NCAA MBB uses 45s. NBA uses 20s in clutch time, 60s otherwise —
  /// callers should check [GameState.isClutchTime].
  int get pollingIntervalSeconds => switch (this) {
        SportType.nfl => 45,
        SportType.nba => 60,
        SportType.mlb => 45,
        SportType.nhl => 45,
        SportType.mls || SportType.fifa || SportType.championsLeague => 60,
        SportType.ncaaFB => 90,
        SportType.ncaaMB => 45,
      };

  /// Faster polling interval used during clutch/critical moments.
  /// NBA: 20s. NCAA MBB: 60s (last 5 min, margin ≤8).
  int get clutchPollingIntervalSeconds => switch (this) {
        SportType.nba => 20,
        SportType.ncaaMB => 60,
        _ => pollingIntervalSeconds,
      };

  /// ESPN groups query parameter to filter large scoreboards.
  /// College football uses &groups=80 to restrict to FBS conferences only.
  /// Returns null when no filter is needed.
  String? get espnGroupsParam => switch (this) {
        SportType.ncaaFB => '80',
        _ => null,
      };

  /// Sport emoji for schedule badges and display.
  String get sportEmoji => switch (this) {
        SportType.nfl || SportType.ncaaFB => '\u{1F3C8}',
        SportType.nba || SportType.ncaaMB => '\u{1F3C0}',
        SportType.mlb => '\u{26BE}',
        SportType.nhl => '\u{1F3D2}',
        SportType.mls ||
        SportType.fifa ||
        SportType.championsLeague =>
          '\u{26BD}',
      };
}
