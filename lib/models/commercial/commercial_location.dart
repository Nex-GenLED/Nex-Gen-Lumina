import 'package:nexgen_command/models/commercial/channel_role.dart';
import 'package:nexgen_command/models/commercial/commercial_role.dart';

/// A manager or staff assignment at a commercial location.
class LocationManagerAssignment {
  final String userId;
  final CommercialRole role;
  final DateTime assignedAt;

  const LocationManagerAssignment({
    required this.userId,
    required this.role,
    required this.assignedAt,
  });

  factory LocationManagerAssignment.fromJson(Map<String, dynamic> json) {
    return LocationManagerAssignment(
      userId: json['user_id'] as String,
      role: parseCommercialRole(json['role'] as String?),
      assignedAt: json['assigned_at'] != null
          ? DateTime.parse(json['assigned_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'role': role.name,
        'assigned_at': assignedAt.toIso8601String(),
      };

  LocationManagerAssignment copyWith({
    String? userId,
    CommercialRole? role,
    DateTime? assignedAt,
  }) {
    return LocationManagerAssignment(
      userId: userId ?? this.userId,
      role: role ?? this.role,
      assignedAt: assignedAt ?? this.assignedAt,
    );
  }
}

/// A single physical commercial location within an organization.
class CommercialLocation {
  final String locationId;
  final String orgId;
  final String locationName;
  final String address;
  final double lat;
  final double lng;
  final String controllerId;
  final String businessHoursId;
  final String scheduleId;
  final String teamsConfigId;
  final bool isUsingOrgTemplate;
  final List<ChannelRoleConfig> channelConfigs;
  final List<LocationManagerAssignment> managers;

  const CommercialLocation({
    required this.locationId,
    required this.orgId,
    required this.locationName,
    required this.address,
    required this.lat,
    required this.lng,
    required this.controllerId,
    this.businessHoursId = '',
    this.scheduleId = '',
    this.teamsConfigId = '',
    this.isUsingOrgTemplate = false,
    this.channelConfigs = const [],
    this.managers = const [],
  });

  factory CommercialLocation.fromJson(Map<String, dynamic> json) {
    return CommercialLocation(
      locationId: json['location_id'] as String,
      orgId: json['org_id'] as String,
      locationName: json['location_name'] as String,
      address: json['address'] as String,
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
      controllerId: json['controller_id'] as String,
      businessHoursId:
          (json['business_hours_id'] as String?) ?? '',
      scheduleId: (json['schedule_id'] as String?) ?? '',
      teamsConfigId: (json['teams_config_id'] as String?) ?? '',
      isUsingOrgTemplate:
          (json['is_using_org_template'] as bool?) ?? false,
      channelConfigs: (json['channel_configs'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => ChannelRoleConfig.fromJson(e))
              .toList() ??
          const [],
      managers: (json['managers'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => LocationManagerAssignment.fromJson(e))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'location_id': locationId,
        'org_id': orgId,
        'location_name': locationName,
        'address': address,
        'lat': lat,
        'lng': lng,
        'controller_id': controllerId,
        'business_hours_id': businessHoursId,
        'schedule_id': scheduleId,
        'teams_config_id': teamsConfigId,
        'is_using_org_template': isUsingOrgTemplate,
        'channel_configs':
            channelConfigs.map((e) => e.toJson()).toList(),
        'managers': managers.map((e) => e.toJson()).toList(),
      };

  CommercialLocation copyWith({
    String? locationId,
    String? orgId,
    String? locationName,
    String? address,
    double? lat,
    double? lng,
    String? controllerId,
    String? businessHoursId,
    String? scheduleId,
    String? teamsConfigId,
    bool? isUsingOrgTemplate,
    List<ChannelRoleConfig>? channelConfigs,
    List<LocationManagerAssignment>? managers,
  }) {
    return CommercialLocation(
      locationId: locationId ?? this.locationId,
      orgId: orgId ?? this.orgId,
      locationName: locationName ?? this.locationName,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      controllerId: controllerId ?? this.controllerId,
      businessHoursId: businessHoursId ?? this.businessHoursId,
      scheduleId: scheduleId ?? this.scheduleId,
      teamsConfigId: teamsConfigId ?? this.teamsConfigId,
      isUsingOrgTemplate:
          isUsingOrgTemplate ?? this.isUsingOrgTemplate,
      channelConfigs: channelConfigs ?? this.channelConfigs,
      managers: managers ?? this.managers,
    );
  }

  /// Find the role of [userId] at this location.
  CommercialRole? roleForUser(String userId) {
    for (final m in managers) {
      if (m.userId == userId) return m.role;
    }
    return null;
  }
}
