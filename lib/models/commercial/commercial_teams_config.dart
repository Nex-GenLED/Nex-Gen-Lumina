import 'package:nexgen_command/models/commercial/commercial_team_profile.dart';

/// Per-location commercial teams configuration.
///
/// Teams are stored in priority order (rank 1 first). The
/// [useBrandColorsForAlerts] flag substitutes the business's brand palette
/// for team colors on scoring alert animations.
class CommercialTeamsConfig {
  final String locationId;
  final List<CommercialTeamProfile> teams;
  final bool useBrandColorsForAlerts;

  const CommercialTeamsConfig({
    required this.locationId,
    this.teams = const [],
    this.useBrandColorsForAlerts = false,
  });

  factory CommercialTeamsConfig.fromJson(Map<String, dynamic> json) {
    final raw = (json['teams'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map((e) => CommercialTeamProfile.fromJson(e))
            .toList() ??
        const [];
    // Ensure sorted by priority rank.
    raw.sort((a, b) => a.priorityRank.compareTo(b.priorityRank));
    return CommercialTeamsConfig(
      locationId: json['location_id'] as String,
      teams: raw,
      useBrandColorsForAlerts:
          (json['use_brand_colors_for_alerts'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'location_id': locationId,
        'teams': teams.map((e) => e.toJson()).toList(),
        'use_brand_colors_for_alerts': useBrandColorsForAlerts,
      };

  CommercialTeamsConfig copyWith({
    String? locationId,
    List<CommercialTeamProfile>? teams,
    bool? useBrandColorsForAlerts,
  }) {
    return CommercialTeamsConfig(
      locationId: locationId ?? this.locationId,
      teams: teams ?? this.teams,
      useBrandColorsForAlerts:
          useBrandColorsForAlerts ?? this.useBrandColorsForAlerts,
    );
  }

  /// The primary (rank 1) team, or `null` if no teams are configured.
  CommercialTeamProfile? get primaryTeam =>
      teams.isNotEmpty ? teams.first : null;
}
