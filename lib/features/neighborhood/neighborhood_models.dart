import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Direction of LED animation along the roofline.
enum RooflineDirection {
  leftToRight,
  rightToLeft,
  centerOut,
}

extension RooflineDirectionExtension on RooflineDirection {
  String get displayName {
    switch (this) {
      case RooflineDirection.leftToRight:
        return 'Left to Right';
      case RooflineDirection.rightToLeft:
        return 'Right to Left';
      case RooflineDirection.centerOut:
        return 'Center Out';
    }
  }

  String get shortName {
    switch (this) {
      case RooflineDirection.leftToRight:
        return 'L→R';
      case RooflineDirection.rightToLeft:
        return 'R→L';
      case RooflineDirection.centerOut:
        return '←C→';
    }
  }

  IconData get icon {
    switch (this) {
      case RooflineDirection.leftToRight:
        return Icons.arrow_forward;
      case RooflineDirection.rightToLeft:
        return Icons.arrow_back;
      case RooflineDirection.centerOut:
        return Icons.unfold_more;
    }
  }

  String toJson() => name;

  static RooflineDirection fromJson(String? value) {
    if (value == null) return RooflineDirection.leftToRight;
    return RooflineDirection.values.firstWhere(
      (e) => e.name == value,
      orElse: () => RooflineDirection.leftToRight,
    );
  }
}

/// Type of synchronization between homes.
enum SyncType {
  /// All homes run the same pattern independently (not time-synced).
  patternMatch,

  /// Animation flows from home to home in sequence.
  sequentialFlow,

  /// All homes animate in perfect unison (same frame at same moment).
  simultaneous,
}

extension SyncTypeExtension on SyncType {
  String get displayName {
    switch (this) {
      case SyncType.patternMatch:
        return 'Pattern Match';
      case SyncType.sequentialFlow:
        return 'Sequential Flow';
      case SyncType.simultaneous:
        return 'Simultaneous';
    }
  }

  String get description {
    switch (this) {
      case SyncType.patternMatch:
        return 'All homes run the same pattern independently';
      case SyncType.sequentialFlow:
        return 'Animation flows from home to home in sequence';
      case SyncType.simultaneous:
        return 'All homes animate in perfect unison';
    }
  }

  IconData get icon {
    switch (this) {
      case SyncType.patternMatch:
        return Icons.grid_view;
      case SyncType.sequentialFlow:
        return Icons.trending_flat;
      case SyncType.simultaneous:
        return Icons.sync;
    }
  }

  String toJson() => name;

  static SyncType fromJson(String? value) {
    if (value == null) return SyncType.sequentialFlow;
    return SyncType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SyncType.sequentialFlow,
    );
  }
}

/// A neighborhood sync group where multiple homes coordinate lighting patterns.
class NeighborhoodGroup {
  final String id;
  final String name;
  final String? description;
  final String? streetName;
  final String? city;
  final bool isPublic;
  final String inviteCode;
  final String creatorUid;
  final DateTime createdAt;
  final List<String> memberUids;
  final bool isActive;
  final String? activePatternId;
  final String? activePatternName;
  final SyncType activeSyncType;
  final double? latitude;
  final double? longitude;

  const NeighborhoodGroup({
    required this.id,
    required this.name,
    this.description,
    this.streetName,
    this.city,
    this.isPublic = false,
    required this.inviteCode,
    required this.creatorUid,
    required this.createdAt,
    required this.memberUids,
    this.isActive = false,
    this.activePatternId,
    this.activePatternName,
    this.activeSyncType = SyncType.sequentialFlow,
    this.latitude,
    this.longitude,
  });

  factory NeighborhoodGroup.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NeighborhoodGroup(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'],
      streetName: data['streetName'],
      city: data['city'],
      isPublic: data['isPublic'] ?? false,
      inviteCode: data['inviteCode'] ?? '',
      creatorUid: data['creatorUid'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      memberUids: List<String>.from(data['memberUids'] ?? []),
      isActive: data['isActive'] ?? false,
      activePatternId: data['activePatternId'],
      activePatternName: data['activePatternName'],
      activeSyncType: SyncTypeExtension.fromJson(data['activeSyncType']),
      latitude: data['latitude']?.toDouble(),
      longitude: data['longitude']?.toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'streetName': streetName,
      'city': city,
      'isPublic': isPublic,
      'inviteCode': inviteCode,
      'creatorUid': creatorUid,
      'createdAt': Timestamp.fromDate(createdAt),
      'memberUids': memberUids,
      'isActive': isActive,
      'activePatternId': activePatternId,
      'activePatternName': activePatternName,
      'activeSyncType': activeSyncType.toJson(),
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  NeighborhoodGroup copyWith({
    String? id,
    String? name,
    String? description,
    String? streetName,
    String? city,
    bool? isPublic,
    String? inviteCode,
    String? creatorUid,
    DateTime? createdAt,
    List<String>? memberUids,
    bool? isActive,
    String? activePatternId,
    String? activePatternName,
    SyncType? activeSyncType,
    double? latitude,
    double? longitude,
    bool clearActivePattern = false,
  }) {
    return NeighborhoodGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      streetName: streetName ?? this.streetName,
      city: city ?? this.city,
      isPublic: isPublic ?? this.isPublic,
      inviteCode: inviteCode ?? this.inviteCode,
      creatorUid: creatorUid ?? this.creatorUid,
      createdAt: createdAt ?? this.createdAt,
      memberUids: memberUids ?? this.memberUids,
      isActive: isActive ?? this.isActive,
      activePatternId: clearActivePattern ? null : (activePatternId ?? this.activePatternId),
      activePatternName: clearActivePattern ? null : (activePatternName ?? this.activePatternName),
      activeSyncType: activeSyncType ?? this.activeSyncType,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  bool get isCreator => creatorUid.isNotEmpty;
  int get memberCount => memberUids.length;
  bool get hasLocation => latitude != null && longitude != null;
}

/// Individual member's sync status.
enum MemberParticipationStatus {
  /// Actively participating in sync.
  active,

  /// Temporarily paused (running personal pattern).
  paused,

  /// Opted out of current schedule.
  optedOut,
}

extension MemberParticipationStatusExtension on MemberParticipationStatus {
  String get displayName {
    switch (this) {
      case MemberParticipationStatus.active:
        return 'Active';
      case MemberParticipationStatus.paused:
        return 'Paused';
      case MemberParticipationStatus.optedOut:
        return 'Opted Out';
    }
  }

  Color get color {
    switch (this) {
      case MemberParticipationStatus.active:
        return Colors.green;
      case MemberParticipationStatus.paused:
        return Colors.orange;
      case MemberParticipationStatus.optedOut:
        return Colors.grey;
    }
  }

  String toJson() => name;

  static MemberParticipationStatus fromJson(String? value) {
    if (value == null) return MemberParticipationStatus.active;
    return MemberParticipationStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MemberParticipationStatus.active,
    );
  }
}

/// A member's configuration within a neighborhood group.
class NeighborhoodMember {
  final String oderId;
  final String displayName;
  final int positionIndex;
  final int ledCount;
  final double rooflineMeters;
  final RooflineDirection rooflineDirection;
  final String? controllerIp;
  final bool isOnline;
  final DateTime lastSeen;
  final MemberParticipationStatus participationStatus;
  final List<String> optedOutScheduleIds;

  const NeighborhoodMember({
    required this.oderId,
    required this.displayName,
    required this.positionIndex,
    this.ledCount = 300,
    this.rooflineMeters = 15.0,
    this.rooflineDirection = RooflineDirection.leftToRight,
    this.controllerIp,
    this.isOnline = false,
    required this.lastSeen,
    this.participationStatus = MemberParticipationStatus.active,
    this.optedOutScheduleIds = const [],
  });

  factory NeighborhoodMember.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NeighborhoodMember(
      oderId: doc.id,
      displayName: data['displayName'] ?? 'Unknown Home',
      positionIndex: data['positionIndex'] ?? 0,
      ledCount: data['ledCount'] ?? 300,
      rooflineMeters: (data['rooflineMeters'] ?? 15.0).toDouble(),
      rooflineDirection: RooflineDirectionExtension.fromJson(data['rooflineDirection']),
      controllerIp: data['controllerIp'],
      isOnline: data['isOnline'] ?? false,
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
      participationStatus: MemberParticipationStatusExtension.fromJson(data['participationStatus']),
      optedOutScheduleIds: List<String>.from(data['optedOutScheduleIds'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'positionIndex': positionIndex,
      'ledCount': ledCount,
      'rooflineMeters': rooflineMeters,
      'rooflineDirection': rooflineDirection.toJson(),
      'controllerIp': controllerIp,
      'isOnline': isOnline,
      'lastSeen': Timestamp.fromDate(lastSeen),
      'participationStatus': participationStatus.toJson(),
      'optedOutScheduleIds': optedOutScheduleIds,
    };
  }

  NeighborhoodMember copyWith({
    String? oderId,
    String? displayName,
    int? positionIndex,
    int? ledCount,
    double? rooflineMeters,
    RooflineDirection? rooflineDirection,
    String? controllerIp,
    bool? isOnline,
    DateTime? lastSeen,
    MemberParticipationStatus? participationStatus,
    List<String>? optedOutScheduleIds,
  }) {
    return NeighborhoodMember(
      oderId: oderId ?? this.oderId,
      displayName: displayName ?? this.displayName,
      positionIndex: positionIndex ?? this.positionIndex,
      ledCount: ledCount ?? this.ledCount,
      rooflineMeters: rooflineMeters ?? this.rooflineMeters,
      rooflineDirection: rooflineDirection ?? this.rooflineDirection,
      controllerIp: controllerIp ?? this.controllerIp,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      participationStatus: participationStatus ?? this.participationStatus,
      optedOutScheduleIds: optedOutScheduleIds ?? this.optedOutScheduleIds,
    );
  }

  /// Estimated time (in ms) for animation to traverse this home's LEDs.
  int animationDurationMs(double pixelsPerSecond) {
    if (pixelsPerSecond <= 0) return 0;
    return ((ledCount / pixelsPerSecond) * 1000).round();
  }

  /// Check if this member has opted out of a specific schedule.
  bool isOptedOutOf(String scheduleId) => optedOutScheduleIds.contains(scheduleId);
}

/// Timing configuration for synchronized animations.
class SyncTimingConfig {
  final double pixelsPerSecond;
  final double gapDelayMs;
  final bool reverseDirection;

  const SyncTimingConfig({
    this.pixelsPerSecond = 50.0,
    this.gapDelayMs = 0,
    this.reverseDirection = false,
  });

  SyncTimingConfig copyWith({
    double? pixelsPerSecond,
    double? gapDelayMs,
    bool? reverseDirection,
  }) {
    return SyncTimingConfig(
      pixelsPerSecond: pixelsPerSecond ?? this.pixelsPerSecond,
      gapDelayMs: gapDelayMs ?? this.gapDelayMs,
      reverseDirection: reverseDirection ?? this.reverseDirection,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pixelsPerSecond': pixelsPerSecond,
      'gapDelayMs': gapDelayMs,
      'reverseDirection': reverseDirection,
    };
  }

  factory SyncTimingConfig.fromJson(Map<String, dynamic> json) {
    return SyncTimingConfig(
      pixelsPerSecond: (json['pixelsPerSecond'] ?? 50.0).toDouble(),
      gapDelayMs: (json['gapDelayMs'] ?? 0).toDouble(),
      reverseDirection: json['reverseDirection'] ?? false,
    );
  }
}

/// A scheduled sync pattern for a neighborhood group.
class SyncSchedule {
  final String id;
  final String groupId;
  final String patternName;
  final int effectId;
  final List<int> colors;
  final int speed;
  final int intensity;
  final int brightness;
  final SyncType syncType;
  final SyncTimingConfig timingConfig;
  final DateTime startDate;
  final DateTime endDate;
  final TimeOfDay dailyStartTime;
  final TimeOfDay dailyEndTime;
  final bool useSunset;
  final List<int> daysOfWeek; // 1=Mon, 7=Sun
  final String createdBy;
  final DateTime createdAt;
  final String? notificationMessage;
  final bool isActive;

  const SyncSchedule({
    required this.id,
    required this.groupId,
    required this.patternName,
    required this.effectId,
    required this.colors,
    required this.speed,
    required this.intensity,
    required this.brightness,
    required this.syncType,
    required this.timingConfig,
    required this.startDate,
    required this.endDate,
    required this.dailyStartTime,
    required this.dailyEndTime,
    this.useSunset = false,
    required this.daysOfWeek,
    required this.createdBy,
    required this.createdAt,
    this.notificationMessage,
    this.isActive = true,
  });

  factory SyncSchedule.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SyncSchedule(
      id: doc.id,
      groupId: data['groupId'] ?? '',
      patternName: data['patternName'] ?? '',
      effectId: data['effectId'] ?? 0,
      colors: List<int>.from(data['colors'] ?? [0xFFFFFF]),
      speed: data['speed'] ?? 128,
      intensity: data['intensity'] ?? 128,
      brightness: data['brightness'] ?? 200,
      syncType: SyncTypeExtension.fromJson(data['syncType']),
      timingConfig: data['timingConfig'] != null
          ? SyncTimingConfig.fromJson(Map<String, dynamic>.from(data['timingConfig']))
          : const SyncTimingConfig(),
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(days: 7)),
      dailyStartTime: _timeFromMinutes(data['dailyStartMinutes'] ?? 1020), // 5pm default
      dailyEndTime: _timeFromMinutes(data['dailyEndMinutes'] ?? 1380), // 11pm default
      useSunset: data['useSunset'] ?? false,
      daysOfWeek: List<int>.from(data['daysOfWeek'] ?? [1, 2, 3, 4, 5, 6, 7]),
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notificationMessage: data['notificationMessage'],
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'groupId': groupId,
      'patternName': patternName,
      'effectId': effectId,
      'colors': colors,
      'speed': speed,
      'intensity': intensity,
      'brightness': brightness,
      'syncType': syncType.toJson(),
      'timingConfig': timingConfig.toJson(),
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'dailyStartMinutes': dailyStartTime.hour * 60 + dailyStartTime.minute,
      'dailyEndMinutes': dailyEndTime.hour * 60 + dailyEndTime.minute,
      'useSunset': useSunset,
      'daysOfWeek': daysOfWeek,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'notificationMessage': notificationMessage,
      'isActive': isActive,
    };
  }

  SyncSchedule copyWith({
    String? id,
    String? groupId,
    String? patternName,
    int? effectId,
    List<int>? colors,
    int? speed,
    int? intensity,
    int? brightness,
    SyncType? syncType,
    SyncTimingConfig? timingConfig,
    DateTime? startDate,
    DateTime? endDate,
    TimeOfDay? dailyStartTime,
    TimeOfDay? dailyEndTime,
    bool? useSunset,
    List<int>? daysOfWeek,
    String? createdBy,
    DateTime? createdAt,
    String? notificationMessage,
    bool? isActive,
  }) {
    return SyncSchedule(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      patternName: patternName ?? this.patternName,
      effectId: effectId ?? this.effectId,
      colors: colors ?? this.colors,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      brightness: brightness ?? this.brightness,
      syncType: syncType ?? this.syncType,
      timingConfig: timingConfig ?? this.timingConfig,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      dailyStartTime: dailyStartTime ?? this.dailyStartTime,
      dailyEndTime: dailyEndTime ?? this.dailyEndTime,
      useSunset: useSunset ?? this.useSunset,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      notificationMessage: notificationMessage ?? this.notificationMessage,
      isActive: isActive ?? this.isActive,
    );
  }

  static TimeOfDay _timeFromMinutes(int minutes) {
    return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  /// Check if this schedule is active on a given day.
  bool isActiveOnDay(int weekday) => daysOfWeek.contains(weekday);

  /// Get formatted date range string.
  String get dateRangeString {
    final start = '${startDate.month}/${startDate.day}';
    final end = '${endDate.month}/${endDate.day}';
    return '$start - $end';
  }

  /// Get formatted time range string.
  String get timeRangeString {
    final start = _formatTime(dailyStartTime);
    final end = _formatTime(dailyEndTime);
    return useSunset ? 'Sunset - $end' : '$start - $end';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}

/// A sync command broadcast to all members in a neighborhood.
class SyncCommand {
  final String id;
  final String groupId;
  final int effectId;
  final List<int> colors;
  final int speed;
  final int intensity;
  final int brightness;
  final DateTime startTimestamp;
  final Map<String, int> memberDelays;
  final SyncTimingConfig timingConfig;
  final SyncType syncType;
  final String? patternName;
  final String? scheduleId;

  const SyncCommand({
    required this.id,
    required this.groupId,
    required this.effectId,
    required this.colors,
    required this.speed,
    required this.intensity,
    required this.brightness,
    required this.startTimestamp,
    required this.memberDelays,
    required this.timingConfig,
    this.syncType = SyncType.sequentialFlow,
    this.patternName,
    this.scheduleId,
  });

  factory SyncCommand.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SyncCommand(
      id: doc.id,
      groupId: data['groupId'] ?? '',
      effectId: data['effectId'] ?? 0,
      colors: List<int>.from(data['colors'] ?? [0xFFFFFF]),
      speed: data['speed'] ?? 128,
      intensity: data['intensity'] ?? 128,
      brightness: data['brightness'] ?? 200,
      startTimestamp: (data['startTimestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      memberDelays: Map<String, int>.from(data['memberDelays'] ?? {}),
      timingConfig: data['timingConfig'] != null
          ? SyncTimingConfig.fromJson(Map<String, dynamic>.from(data['timingConfig']))
          : const SyncTimingConfig(),
      syncType: SyncTypeExtension.fromJson(data['syncType']),
      patternName: data['patternName'],
      scheduleId: data['scheduleId'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'groupId': groupId,
      'effectId': effectId,
      'colors': colors,
      'speed': speed,
      'intensity': intensity,
      'brightness': brightness,
      'startTimestamp': Timestamp.fromDate(startTimestamp),
      'memberDelays': memberDelays,
      'timingConfig': timingConfig.toJson(),
      'syncType': syncType.toJson(),
      'patternName': patternName,
      'scheduleId': scheduleId,
    };
  }

  /// Get the delay for a specific member.
  /// Returns -1 if the member is not included in this sync command.
  int getDelayForMember(String oderId) {
    return memberDelays[oderId] ?? -1;
  }

  /// Check if a member is included in this sync command.
  bool includesMember(String oderId) => memberDelays.containsKey(oderId);

  /// Convert colors to Flutter Color objects.
  List<Color> get colorObjects {
    return colors.map((c) => Color(c | 0xFF000000)).toList();
  }
}

/// Status of a member in the neighborhood sync.
enum MemberSyncStatus {
  offline,
  online,
  syncing,
  error,
}

/// Extension to get display properties for sync status.
extension MemberSyncStatusExtension on MemberSyncStatus {
  String get displayName {
    switch (this) {
      case MemberSyncStatus.offline:
        return 'Offline';
      case MemberSyncStatus.online:
        return 'Online';
      case MemberSyncStatus.syncing:
        return 'Syncing';
      case MemberSyncStatus.error:
        return 'Error';
    }
  }

  Color get color {
    switch (this) {
      case MemberSyncStatus.offline:
        return Colors.grey;
      case MemberSyncStatus.online:
        return Colors.green;
      case MemberSyncStatus.syncing:
        return Colors.cyan;
      case MemberSyncStatus.error:
        return Colors.red;
    }
  }

  IconData get icon {
    switch (this) {
      case MemberSyncStatus.offline:
        return Icons.cloud_off;
      case MemberSyncStatus.online:
        return Icons.cloud_done;
      case MemberSyncStatus.syncing:
        return Icons.sync;
      case MemberSyncStatus.error:
        return Icons.error_outline;
    }
  }
}
