// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// LED alert intensity for commercial scoring events.
enum AlertIntensity {
  full,
  moderate,
  subtle,
}

/// Which channels should react to scoring alerts.
enum AlertChannelScope {
  allChannels,
  indoorOnly,
  selectedChannels,
}

// ---------------------------------------------------------------------------
// Serialization helpers
// ---------------------------------------------------------------------------

AlertIntensity _parseAlertIntensity(String? v) {
  switch (v) {
    case 'full':
      return AlertIntensity.full;
    case 'moderate':
      return AlertIntensity.moderate;
    case 'subtle':
      return AlertIntensity.subtle;
    default:
      return AlertIntensity.full;
  }
}

AlertChannelScope _parseAlertChannelScope(String? v) {
  switch (v) {
    case 'all_channels':
      return AlertChannelScope.allChannels;
    case 'indoor_only':
      return AlertChannelScope.indoorOnly;
    case 'selected_channels':
      return AlertChannelScope.selectedChannels;
    default:
      return AlertChannelScope.allChannels;
  }
}

String _alertChannelScopeStr(AlertChannelScope s) {
  switch (s) {
    case AlertChannelScope.allChannels:
      return 'all_channels';
    case AlertChannelScope.indoorOnly:
      return 'indoor_only';
    case AlertChannelScope.selectedChannels:
      return 'selected_channels';
  }
}

// ---------------------------------------------------------------------------
// CommercialTeamProfile
// ---------------------------------------------------------------------------

/// A sports team configured for commercial game-day automation with full
/// channel scope and alert intensity controls.
class CommercialTeamProfile {
  final int priorityRank;
  final String teamId;
  final String teamName;
  final String sport;
  final String primaryColor;
  final String secondaryColor;
  final AlertIntensity alertIntensity;
  final AlertChannelScope alertChannelScope;
  final List<String> selectedChannelIds;
  final bool gameDayAutoModeEnabled;
  final int gameDayLeadTimeMinutes;

  const CommercialTeamProfile({
    required this.priorityRank,
    required this.teamId,
    required this.teamName,
    required this.sport,
    required this.primaryColor,
    required this.secondaryColor,
    this.alertIntensity = AlertIntensity.full,
    this.alertChannelScope = AlertChannelScope.allChannels,
    this.selectedChannelIds = const [],
    this.gameDayAutoModeEnabled = true,
    this.gameDayLeadTimeMinutes = 120,
  });

  factory CommercialTeamProfile.fromJson(Map<String, dynamic> json) {
    return CommercialTeamProfile(
      priorityRank: (json['priority_rank'] as num?)?.toInt() ?? 1,
      teamId: json['team_id'] as String,
      teamName: json['team_name'] as String,
      sport: json['sport'] as String,
      primaryColor: json['primary_color'] as String,
      secondaryColor: json['secondary_color'] as String,
      alertIntensity:
          _parseAlertIntensity(json['alert_intensity'] as String?),
      alertChannelScope:
          _parseAlertChannelScope(json['alert_channel_scope'] as String?),
      selectedChannelIds: (json['selected_channel_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      gameDayAutoModeEnabled:
          (json['game_day_auto_mode_enabled'] as bool?) ?? true,
      gameDayLeadTimeMinutes:
          (json['game_day_lead_time_minutes'] as num?)?.toInt() ?? 120,
    );
  }

  Map<String, dynamic> toJson() => {
        'priority_rank': priorityRank,
        'team_id': teamId,
        'team_name': teamName,
        'sport': sport,
        'primary_color': primaryColor,
        'secondary_color': secondaryColor,
        'alert_intensity': alertIntensity.name,
        'alert_channel_scope': _alertChannelScopeStr(alertChannelScope),
        'selected_channel_ids': selectedChannelIds,
        'game_day_auto_mode_enabled': gameDayAutoModeEnabled,
        'game_day_lead_time_minutes': gameDayLeadTimeMinutes,
      };

  CommercialTeamProfile copyWith({
    int? priorityRank,
    String? teamId,
    String? teamName,
    String? sport,
    String? primaryColor,
    String? secondaryColor,
    AlertIntensity? alertIntensity,
    AlertChannelScope? alertChannelScope,
    List<String>? selectedChannelIds,
    bool? gameDayAutoModeEnabled,
    int? gameDayLeadTimeMinutes,
  }) {
    return CommercialTeamProfile(
      priorityRank: priorityRank ?? this.priorityRank,
      teamId: teamId ?? this.teamId,
      teamName: teamName ?? this.teamName,
      sport: sport ?? this.sport,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      alertIntensity: alertIntensity ?? this.alertIntensity,
      alertChannelScope: alertChannelScope ?? this.alertChannelScope,
      selectedChannelIds: selectedChannelIds ?? this.selectedChannelIds,
      gameDayAutoModeEnabled:
          gameDayAutoModeEnabled ?? this.gameDayAutoModeEnabled,
      gameDayLeadTimeMinutes:
          gameDayLeadTimeMinutes ?? this.gameDayLeadTimeMinutes,
    );
  }

  /// Whether this is the primary team (rank 1).
  bool get isPrimary => priorityRank == 1;

  /// Whether this is a secondary team (rank 2).
  bool get isSecondary => priorityRank == 2;
}
