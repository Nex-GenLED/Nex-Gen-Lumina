import 'package:cloud_firestore/cloud_firestore.dart';

import '../../sports_alerts/models/sport_type.dart';

/// Configuration for a group-level Game Day Autopilot.
///
/// Stored at: `/neighborhoods/{groupId}/game_day_autopilot/config`
///
/// The host's team selection and design push to all opted-in group members.
/// Each member has an individual opt-in toggle (`groupAutopilotOptIn` on
/// their member doc) — members who opt out receive no game day activations
/// from the group but their own individual autopilot still runs normally.
class GroupGameDayAutopilot {
  final String teamId;
  final String teamName;
  final SportType sport;
  final bool enabled;
  final String hostDesignId;
  final String hostUserId;

  /// UIDs of members who are opted in to group autopilot.
  /// Dynamically filtered — always re-fetch before broadcasting.
  final List<String> activeMemberIds;

  final DateTime updatedAt;

  const GroupGameDayAutopilot({
    required this.teamId,
    required this.teamName,
    required this.sport,
    this.enabled = true,
    required this.hostDesignId,
    required this.hostUserId,
    this.activeMemberIds = const [],
    required this.updatedAt,
  });

  factory GroupGameDayAutopilot.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return GroupGameDayAutopilot(
      teamId: data['teamId'] ?? '',
      teamName: data['teamName'] ?? '',
      sport: SportType.fromJson(data['sport'] ?? 'nfl'),
      enabled: data['enabled'] ?? true,
      hostDesignId: data['hostDesignId'] ?? '',
      hostUserId: data['hostUserId'] ?? '',
      activeMemberIds: List<String>.from(data['activeMemberIds'] ?? []),
      updatedAt:
          (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'teamId': teamId,
      'teamName': teamName,
      'sport': sport.toJson(),
      'enabled': enabled,
      'hostDesignId': hostDesignId,
      'hostUserId': hostUserId,
      'activeMemberIds': activeMemberIds,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  GroupGameDayAutopilot copyWith({
    String? teamId,
    String? teamName,
    SportType? sport,
    bool? enabled,
    String? hostDesignId,
    String? hostUserId,
    List<String>? activeMemberIds,
    DateTime? updatedAt,
  }) {
    return GroupGameDayAutopilot(
      teamId: teamId ?? this.teamId,
      teamName: teamName ?? this.teamName,
      sport: sport ?? this.sport,
      enabled: enabled ?? this.enabled,
      hostDesignId: hostDesignId ?? this.hostDesignId,
      hostUserId: hostUserId ?? this.hostUserId,
      activeMemberIds: activeMemberIds ?? this.activeMemberIds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Sport emoji for display.
  String get sportEmoji => switch (sport) {
        SportType.nfl || SportType.ncaaFB => '\u{1F3C8}',
        SportType.nba || SportType.wnba || SportType.ncaaMB => '\u{1F3C0}',
        SportType.mlb => '\u{26BE}',
        SportType.nhl => '\u{1F3D2}',
        SportType.mls ||
        SportType.nwsl ||
        SportType.fifa ||
        SportType.championsLeague =>
          '\u{26BD}',
      };

  int get optedInCount => activeMemberIds.length;
}
