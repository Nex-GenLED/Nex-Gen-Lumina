/// A sports team configured for commercial game-day lighting automation.
class CommercialTeam {
  final String teamSlug;
  final String teamName;
  final String sport;
  final int priorityRank;
  final String alertIntensity;
  final bool enableGameDayMode;

  const CommercialTeam({
    required this.teamSlug,
    required this.teamName,
    required this.sport,
    this.priorityRank = 1,
    this.alertIntensity = 'full',
    this.enableGameDayMode = true,
  });

  factory CommercialTeam.fromJson(Map<String, dynamic> json) {
    return CommercialTeam(
      teamSlug: json['team_slug'] as String,
      teamName: json['team_name'] as String,
      sport: json['sport'] as String,
      priorityRank: (json['priority_rank'] as num?)?.toInt() ?? 1,
      alertIntensity:
          (json['alert_intensity'] as String?) ?? 'full',
      enableGameDayMode:
          (json['enable_game_day_mode'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'team_slug': teamSlug,
        'team_name': teamName,
        'sport': sport,
        'priority_rank': priorityRank,
        'alert_intensity': alertIntensity,
        'enable_game_day_mode': enableGameDayMode,
      };

  CommercialTeam copyWith({
    String? teamSlug,
    String? teamName,
    String? sport,
    int? priorityRank,
    String? alertIntensity,
    bool? enableGameDayMode,
  }) {
    return CommercialTeam(
      teamSlug: teamSlug ?? this.teamSlug,
      teamName: teamName ?? this.teamName,
      sport: sport ?? this.sport,
      priorityRank: priorityRank ?? this.priorityRank,
      alertIntensity: alertIntensity ?? this.alertIntensity,
      enableGameDayMode:
          enableGameDayMode ?? this.enableGameDayMode,
    );
  }
}
