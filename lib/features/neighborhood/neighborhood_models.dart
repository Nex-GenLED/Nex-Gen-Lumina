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

  /// Each home displays a different color from a coordinated theme.
  /// e.g., July 4th: House 1=Red, House 2=White, House 3=Blue
  complement,
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
      case SyncType.complement:
        return 'Complement Mode';
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
      case SyncType.complement:
        return 'Each home shows a different color from a theme';
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
      case SyncType.complement:
        return Icons.palette_outlined;
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

  /// Member-specific color overrides for Complement Mode.
  /// Key: member userId, Value: list of colors (as int values) for that member.
  /// If a member is not in this map, they use the default [colors] field.
  final Map<String, List<int>>? memberColorOverrides;

  /// The complement theme being used (e.g., "july4th", "christmas").
  /// Helps UI display the correct theme name.
  final String? complementTheme;

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
    this.memberColorOverrides,
    this.complementTheme,
  });

  factory SyncCommand.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse memberColorOverrides from Firestore
    Map<String, List<int>>? colorOverrides;
    if (data['memberColorOverrides'] != null) {
      final raw = data['memberColorOverrides'] as Map<String, dynamic>;
      colorOverrides = raw.map((k, v) => MapEntry(k, List<int>.from(v)));
    }

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
      memberColorOverrides: colorOverrides,
      complementTheme: data['complementTheme'],
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
      if (memberColorOverrides != null) 'memberColorOverrides': memberColorOverrides,
      if (complementTheme != null) 'complementTheme': complementTheme,
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

  /// Get the colors for a specific member.
  /// In Complement Mode, returns member-specific colors if assigned.
  /// Otherwise returns the default colors.
  List<int> getColorsForMember(String memberId) {
    if (syncType == SyncType.complement && memberColorOverrides != null) {
      return memberColorOverrides![memberId] ?? colors;
    }
    return colors;
  }

  /// Get the colors for a specific member as Flutter Color objects.
  List<Color> getColorObjectsForMember(String memberId) {
    return getColorsForMember(memberId).map((c) => Color(c | 0xFF000000)).toList();
  }

  /// Check if this command uses Complement Mode.
  bool get isComplementMode => syncType == SyncType.complement;
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

// ─────────────────────────────────────────────────────────────────────────────
// Complement Mode Theme Presets
// ─────────────────────────────────────────────────────────────────────────────

/// A predefined color theme for Complement Mode.
/// Each home in the neighborhood displays a different color from the palette.
class ComplementTheme {
  final String id;
  final String name;
  final String description;
  final IconData icon;

  /// The colors to distribute across homes (as RGB int values).
  /// Colors are assigned in order: Home 1 gets colors[0], Home 2 gets colors[1], etc.
  /// If there are more homes than colors, colors wrap around.
  final List<int> themeColors;

  /// Optional effect ID that works best with this theme (0 = solid color).
  final int recommendedEffectId;

  const ComplementTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.themeColors,
    this.recommendedEffectId = 0,
  });

  /// Get the color for a specific home index (0-based).
  /// Wraps around if there are more homes than colors.
  int getColorForIndex(int homeIndex) {
    return themeColors[homeIndex % themeColors.length];
  }

  /// Get all colors as Flutter Color objects.
  List<Color> get colorObjects {
    return themeColors.map((c) => Color(c | 0xFF000000)).toList();
  }

  /// Builds the member color overrides map for a list of members.
  Map<String, List<int>> buildMemberColorOverrides(List<NeighborhoodMember> members) {
    final sorted = List<NeighborhoodMember>.from(members)
      ..sort((a, b) => a.positionIndex.compareTo(b.positionIndex));

    final overrides = <String, List<int>>{};
    for (int i = 0; i < sorted.length; i++) {
      // Each member gets a single solid color from the theme
      final color = getColorForIndex(i);
      overrides[sorted[i].oderId] = [color];
    }
    return overrides;
  }
}

/// Pre-built complement themes for common holidays and events.
class ComplementThemes {
  ComplementThemes._();

  /// July 4th / Independence Day - Red, White, Blue
  static const july4th = ComplementTheme(
    id: 'july4th',
    name: 'July 4th',
    description: 'Red, White, Blue - American Independence Day',
    icon: Icons.flag,
    themeColors: [
      0xFF0000, // Red
      0xFFFFFF, // White
      0x0000FF, // Blue
    ],
    recommendedEffectId: 0, // Solid
  );

  /// Christmas - Red, Green, White
  static const christmas = ComplementTheme(
    id: 'christmas',
    name: 'Christmas',
    description: 'Red, Green, White - Classic holiday colors',
    icon: Icons.ac_unit,
    themeColors: [
      0xFF0000, // Red
      0x00FF00, // Green
      0xFFFFFF, // White
    ],
    recommendedEffectId: 0,
  );

  /// Halloween - Orange, Purple, Green
  static const halloween = ComplementTheme(
    id: 'halloween',
    name: 'Halloween',
    description: 'Orange, Purple, Green - Spooky season',
    icon: Icons.nightlight_round,
    themeColors: [
      0xFF6600, // Orange
      0x9900FF, // Purple
      0x00FF00, // Green
    ],
    recommendedEffectId: 0,
  );

  /// St. Patrick's Day - Green, Gold, White
  static const stPatricks = ComplementTheme(
    id: 'stpatricks',
    name: "St. Patrick's Day",
    description: 'Green, Gold, White - Irish celebration',
    icon: Icons.eco,
    themeColors: [
      0x00FF00, // Green
      0xFFD700, // Gold
      0xFFFFFF, // White
    ],
    recommendedEffectId: 0,
  );

  /// Valentine's Day - Red, Pink, White
  static const valentines = ComplementTheme(
    id: 'valentines',
    name: "Valentine's Day",
    description: 'Red, Pink, White - Colors of love',
    icon: Icons.favorite,
    themeColors: [
      0xFF0000, // Red
      0xFF69B4, // Hot Pink
      0xFFFFFF, // White
    ],
    recommendedEffectId: 0,
  );

  /// Easter - Pastel colors
  static const easter = ComplementTheme(
    id: 'easter',
    name: 'Easter',
    description: 'Pastel Pink, Yellow, Blue, Green',
    icon: Icons.egg,
    themeColors: [
      0xFFB6C1, // Light Pink
      0xFFFF99, // Light Yellow
      0x87CEEB, // Sky Blue
      0x98FB98, // Pale Green
    ],
    recommendedEffectId: 0,
  );

  /// Mardi Gras - Purple, Gold, Green
  static const mardiGras = ComplementTheme(
    id: 'mardigras',
    name: 'Mardi Gras',
    description: 'Purple, Gold, Green - New Orleans tradition',
    icon: Icons.masks,
    themeColors: [
      0x9400D3, // Purple
      0xFFD700, // Gold
      0x00FF00, // Green
    ],
    recommendedEffectId: 0,
  );

  /// Pride - Rainbow colors
  static const pride = ComplementTheme(
    id: 'pride',
    name: 'Pride',
    description: 'Rainbow - Celebration of diversity',
    icon: Icons.wb_sunny,
    themeColors: [
      0xFF0000, // Red
      0xFF7F00, // Orange
      0xFFFF00, // Yellow
      0x00FF00, // Green
      0x0000FF, // Blue
      0x8B00FF, // Violet
    ],
    recommendedEffectId: 0,
  );

  /// Sports Team - Generic team colors (user can customize)
  static const gameDay = ComplementTheme(
    id: 'gameday',
    name: 'Game Day',
    description: 'Show team spirit across the neighborhood',
    icon: Icons.sports_football,
    themeColors: [
      0xFF0000, // Team color 1 (placeholder)
      0xFFFFFF, // Team color 2 (placeholder)
    ],
    recommendedEffectId: 0,
  );

  /// All available themes
  static const List<ComplementTheme> all = [
    july4th,
    christmas,
    halloween,
    stPatricks,
    valentines,
    easter,
    mardiGras,
    pride,
    gameDay,
  ];

  /// Get a theme by ID
  static ComplementTheme? getById(String id) {
    try {
      return all.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }
}
