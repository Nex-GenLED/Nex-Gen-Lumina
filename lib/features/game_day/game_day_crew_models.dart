import 'package:cloud_firestore/cloud_firestore.dart';

import '../sports_alerts/models/sport_type.dart';

/// A Game Day Crew is a single-team sync group where the host controls
/// the design, live scoring, and autopilot for all members.
///
/// Stored at: `/game_day_crews/{crewId}`
///
/// Rules:
/// - One team per crew.
/// - Host controls design, live scoring toggle, and autopilot toggle.
/// - Members receive the host's exact config — no overrides.
/// - The only member choice is join or leave.
class GameDayCrew {
  final String id;

  /// Team slug from kTeamColors (e.g. 'nfl_cowboys').
  final String teamSlug;

  /// Display name (e.g. 'Dallas Cowboys').
  final String teamName;

  final SportType sport;

  /// UID of the host (creator).
  final String hostUid;

  /// Host's display name for the crew card.
  final String hostDisplayName;

  /// 6-character invite code for joining.
  final String inviteCode;

  /// Whether live scoring celebrations fire for all members.
  final bool liveScoring;

  /// Whether autopilot (auto-activate at game time) is on for the crew.
  final bool autopilotEnabled;

  /// The WLED design payload that ALL members run.
  final Map<String, dynamic>? designPayload;

  /// Human-readable name of the design.
  final String designName;

  /// WLED effect parameters.
  final int effectId;
  final int speed;
  final int intensity;
  final int brightness;

  /// Team colors (ARGB int values).
  final int primaryColorValue;
  final int secondaryColorValue;

  /// ESPN team ID for score polling.
  final String espnTeamId;

  /// UIDs of all crew members (including host).
  final List<String> memberUids;

  final DateTime createdAt;
  final DateTime updatedAt;

  const GameDayCrew({
    required this.id,
    required this.teamSlug,
    required this.teamName,
    required this.sport,
    required this.hostUid,
    required this.hostDisplayName,
    required this.inviteCode,
    this.liveScoring = false,
    this.autopilotEnabled = true,
    this.designPayload,
    this.designName = 'Team Colors (Solid)',
    this.effectId = 0,
    this.speed = 128,
    this.intensity = 128,
    this.brightness = 200,
    required this.primaryColorValue,
    required this.secondaryColorValue,
    required this.espnTeamId,
    this.memberUids = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  int get memberCount => memberUids.length;
  bool isHost(String uid) => uid == hostUid;

  /// Sport emoji for display.
  String get sportEmoji => switch (sport) {
        SportType.nfl || SportType.ncaaFB => '\u{1F3C8}',
        SportType.nba || SportType.ncaaMB => '\u{1F3C0}',
        SportType.mlb => '\u{26BE}',
        SportType.nhl => '\u{1F3D2}',
        SportType.mls ||
        SportType.fifa ||
        SportType.championsLeague =>
          '\u{26BD}',
      };

  // ── Serialization ────────────────────────────────────────────────────────

  Map<String, dynamic> toFirestore() => {
        'team_slug': teamSlug,
        'team_name': teamName,
        'sport': sport.toJson(),
        'host_uid': hostUid,
        'host_display_name': hostDisplayName,
        'invite_code': inviteCode,
        'live_scoring': liveScoring,
        'autopilot_enabled': autopilotEnabled,
        'design_payload': designPayload,
        'design_name': designName,
        'effect_id': effectId,
        'speed': speed,
        'intensity': intensity,
        'brightness': brightness,
        'primary_color': primaryColorValue,
        'secondary_color': secondaryColorValue,
        'espn_team_id': espnTeamId,
        'member_uids': memberUids,
        'created_at': Timestamp.fromDate(createdAt),
        'updated_at': Timestamp.fromDate(updatedAt),
      };

  factory GameDayCrew.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GameDayCrew(
      id: doc.id,
      teamSlug: data['team_slug'] as String? ?? '',
      teamName: data['team_name'] as String? ?? '',
      sport: SportType.fromJson(data['sport'] as String? ?? 'nfl'),
      hostUid: data['host_uid'] as String? ?? '',
      hostDisplayName: data['host_display_name'] as String? ?? '',
      inviteCode: data['invite_code'] as String? ?? '',
      liveScoring: data['live_scoring'] as bool? ?? false,
      autopilotEnabled: data['autopilot_enabled'] as bool? ?? true,
      designPayload: data['design_payload'] as Map<String, dynamic>?,
      designName: data['design_name'] as String? ?? 'Team Colors (Solid)',
      effectId: (data['effect_id'] as num?)?.toInt() ?? 0,
      speed: (data['speed'] as num?)?.toInt() ?? 128,
      intensity: (data['intensity'] as num?)?.toInt() ?? 128,
      brightness: (data['brightness'] as num?)?.toInt() ?? 200,
      primaryColorValue: (data['primary_color'] as num?)?.toInt() ?? 0xFF000000,
      secondaryColorValue:
          (data['secondary_color'] as num?)?.toInt() ?? 0xFFFFFFFF,
      espnTeamId: data['espn_team_id'] as String? ?? '',
      memberUids: List<String>.from(data['member_uids'] ?? []),
      createdAt:
          (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt:
          (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  GameDayCrew copyWith({
    bool? liveScoring,
    bool? autopilotEnabled,
    Map<String, dynamic>? designPayload,
    String? designName,
    int? effectId,
    int? speed,
    int? intensity,
    int? brightness,
    List<String>? memberUids,
    String? hostDisplayName,
    DateTime? updatedAt,
  }) {
    return GameDayCrew(
      id: id,
      teamSlug: teamSlug,
      teamName: teamName,
      sport: sport,
      hostUid: hostUid,
      hostDisplayName: hostDisplayName ?? this.hostDisplayName,
      inviteCode: inviteCode,
      liveScoring: liveScoring ?? this.liveScoring,
      autopilotEnabled: autopilotEnabled ?? this.autopilotEnabled,
      designPayload: designPayload ?? this.designPayload,
      designName: designName ?? this.designName,
      effectId: effectId ?? this.effectId,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      brightness: brightness ?? this.brightness,
      primaryColorValue: primaryColorValue,
      secondaryColorValue: secondaryColorValue,
      espnTeamId: espnTeamId,
      memberUids: memberUids ?? this.memberUids,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
