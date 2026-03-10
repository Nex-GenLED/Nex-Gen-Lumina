import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_event.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SYNC EVENT BACKGROUND PERSISTENCE
// ═════════════════════════════════════════════════════════════════════════════
//
// SharedPreferences-based persistence layer for sync event configs.
// Used by the background service isolate which has no access to Riverpod
// or Firestore listeners.
//
// The UI layer writes sync event state here whenever it changes, and the
// background service reads it on each polling cycle.
// ═════════════════════════════════════════════════════════════════════════════

const _kSyncEventsKey = 'bg_sync_events';
const _kSyncGroupIdKey = 'bg_sync_group_id';
const _kSyncHostUidKey = 'bg_sync_host_uid';
const _kSyncBackupHostUidKey = 'bg_sync_backup_host_uid';
const _kSyncUserUidKey = 'bg_sync_user_uid';
const _kSyncControllerIpsKey = 'bg_sync_controller_ips';
const _kSyncActiveSessionKey = 'bg_sync_active_session';
const _kSyncHostFailoverTsKey = 'bg_sync_host_failover_ts';

/// Serializable subset of SyncEvent for background service consumption.
/// Avoids pulling in Firestore dependencies in the background isolate.
class BackgroundSyncEventConfig {
  final String id;
  final String name;
  final String groupId;
  final String triggerType; // 'scheduledTime', 'gameStart', 'manual'
  final String? sportLeague;
  final String? espnTeamId;
  final String? teamId;
  final DateTime? scheduledTime;
  final List<int> repeatDays;
  final bool isEnabled;
  final String category;
  // Pattern data needed for WLED commands in background
  final int baseEffectId;
  final List<int> baseColors;
  final int baseSpeed;
  final int baseIntensity;
  final int baseBrightness;
  final int celebrationEffectId;
  final List<int> celebrationColors;
  final int celebrationDurationSeconds;
  final String postEventBehavior;
  // Season schedule fields
  final bool isSeasonSchedule;
  final int? seasonYear;
  final List<String> excludedGameIds;

  const BackgroundSyncEventConfig({
    required this.id,
    required this.name,
    required this.groupId,
    required this.triggerType,
    this.sportLeague,
    this.espnTeamId,
    this.teamId,
    this.scheduledTime,
    this.repeatDays = const [],
    this.isEnabled = true,
    this.category = 'gameDay',
    this.baseEffectId = 0,
    this.baseColors = const [0xFFFFFF],
    this.baseSpeed = 128,
    this.baseIntensity = 128,
    this.baseBrightness = 200,
    this.celebrationEffectId = 88,
    this.celebrationColors = const [0xFFFFFF],
    this.celebrationDurationSeconds = 15,
    this.postEventBehavior = 'returnToAutopilot',
    this.isSeasonSchedule = false,
    this.seasonYear,
    this.excludedGameIds = const [],
  });

  bool get isGameStart => triggerType == 'gameStart';
  bool get isScheduledTime => triggerType == 'scheduledTime';
  bool get isManual => triggerType == 'manual';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'groupId': groupId,
        'triggerType': triggerType,
        'sportLeague': sportLeague,
        'espnTeamId': espnTeamId,
        'teamId': teamId,
        'scheduledTime': scheduledTime?.toIso8601String(),
        'repeatDays': repeatDays,
        'isEnabled': isEnabled,
        'category': category,
        'baseEffectId': baseEffectId,
        'baseColors': baseColors,
        'baseSpeed': baseSpeed,
        'baseIntensity': baseIntensity,
        'baseBrightness': baseBrightness,
        'celebrationEffectId': celebrationEffectId,
        'celebrationColors': celebrationColors,
        'celebrationDurationSeconds': celebrationDurationSeconds,
        'postEventBehavior': postEventBehavior,
        'isSeasonSchedule': isSeasonSchedule,
        'seasonYear': seasonYear,
        'excludedGameIds': excludedGameIds,
      };

  factory BackgroundSyncEventConfig.fromJson(Map<String, dynamic> json) {
    return BackgroundSyncEventConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      groupId: json['groupId'] ?? '',
      triggerType: json['triggerType'] ?? 'scheduledTime',
      sportLeague: json['sportLeague'],
      espnTeamId: json['espnTeamId'],
      teamId: json['teamId'],
      scheduledTime: json['scheduledTime'] != null
          ? DateTime.tryParse(json['scheduledTime'])
          : null,
      repeatDays: List<int>.from(json['repeatDays'] ?? []),
      isEnabled: json['isEnabled'] ?? true,
      category: json['category'] ?? 'gameDay',
      baseEffectId: json['baseEffectId'] ?? 0,
      baseColors: List<int>.from(json['baseColors'] ?? [0xFFFFFF]),
      baseSpeed: json['baseSpeed'] ?? 128,
      baseIntensity: json['baseIntensity'] ?? 128,
      baseBrightness: json['baseBrightness'] ?? 200,
      celebrationEffectId: json['celebrationEffectId'] ?? 88,
      celebrationColors:
          List<int>.from(json['celebrationColors'] ?? [0xFFFFFF]),
      celebrationDurationSeconds: json['celebrationDurationSeconds'] ?? 15,
      postEventBehavior: json['postEventBehavior'] ?? 'returnToAutopilot',
      isSeasonSchedule: json['isSeasonSchedule'] ?? false,
      seasonYear: json['seasonYear'],
      excludedGameIds: List<String>.from(json['excludedGameIds'] ?? []),
    );
  }

  /// Create from a full SyncEvent model (called from UI layer).
  factory BackgroundSyncEventConfig.fromSyncEvent(SyncEvent event) {
    return BackgroundSyncEventConfig(
      id: event.id,
      name: event.name,
      groupId: event.syncGroupId,
      triggerType: event.triggerType.name,
      sportLeague: event.sportLeague,
      espnTeamId: event.espnTeamId,
      teamId: event.teamId,
      scheduledTime: event.scheduledTime,
      repeatDays: event.repeatDays,
      isEnabled: event.isEnabled,
      category: event.category.name,
      baseEffectId: event.basePattern.effectId,
      baseColors: event.basePattern.colors,
      baseSpeed: event.basePattern.speed,
      baseIntensity: event.basePattern.intensity,
      baseBrightness: event.basePattern.brightness,
      celebrationEffectId: event.celebrationPattern.effectId,
      celebrationColors: event.celebrationPattern.colors,
      celebrationDurationSeconds: event.celebrationDurationSeconds,
      postEventBehavior: event.postEventBehavior.name,
      isSeasonSchedule: event.isSeasonSchedule,
      seasonYear: event.seasonYear,
      excludedGameIds: event.excludedGameIds,
    );
  }
}

/// Minimal active session state for background service tracking.
class BackgroundActiveSession {
  final String sessionId;
  final String syncEventId;
  final String groupId;
  final String? gameId;
  final DateTime startedAt;

  const BackgroundActiveSession({
    required this.sessionId,
    required this.syncEventId,
    required this.groupId,
    this.gameId,
    required this.startedAt,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'syncEventId': syncEventId,
        'groupId': groupId,
        'gameId': gameId,
        'startedAt': startedAt.toIso8601String(),
      };

  factory BackgroundActiveSession.fromJson(Map<String, dynamic> json) {
    return BackgroundActiveSession(
      sessionId: json['sessionId'] ?? '',
      syncEventId: json['syncEventId'] ?? '',
      groupId: json['groupId'] ?? '',
      gameId: json['gameId'],
      startedAt: DateTime.tryParse(json['startedAt'] ?? '') ?? DateTime.now(),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PERSISTENCE FUNCTIONS (called from UI layer)
// ═════════════════════════════════════════════════════════════════════════════

/// Save sync event configs for the background service to read.
/// Called whenever sync events change in the UI.
Future<void> saveSyncEventsForBackground(
  List<BackgroundSyncEventConfig> configs,
) async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = configs.map((c) => jsonEncode(c.toJson())).toList();
  await prefs.setStringList(_kSyncEventsKey, encoded);
  debugPrint(
    '[SyncBgPersistence] Saved ${configs.length} sync events for background',
  );
}

/// Save the active group ID for background service.
Future<void> saveSyncGroupId(String? groupId) async {
  final prefs = await SharedPreferences.getInstance();
  if (groupId == null) {
    await prefs.remove(_kSyncGroupIdKey);
  } else {
    await prefs.setString(_kSyncGroupIdKey, groupId);
  }
}

/// Save the current user's UID for background auth context.
Future<void> saveSyncUserUid(String? uid) async {
  final prefs = await SharedPreferences.getInstance();
  if (uid == null) {
    await prefs.remove(_kSyncUserUidKey);
  } else {
    await prefs.setString(_kSyncUserUidKey, uid);
  }
}

/// Save host and backup host UIDs for failover logic.
Future<void> saveSyncHostInfo({
  required String hostUid,
  String? backupHostUid,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSyncHostUidKey, hostUid);
  if (backupHostUid != null) {
    await prefs.setString(_kSyncBackupHostUidKey, backupHostUid);
  }
}

/// Save controller IPs for direct WLED commands from background.
Future<void> saveSyncControllerIps(List<String> ips) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_kSyncControllerIpsKey, ips);
}

/// Mark that an active session was started (background or foreground).
Future<void> saveActiveSession(BackgroundActiveSession session) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSyncActiveSessionKey, jsonEncode(session.toJson()));
}

/// Clear the active session marker.
Future<void> clearActiveSession() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kSyncActiveSessionKey);
}

/// Record the timestamp when a host failover grace window begins.
Future<void> saveHostFailoverTimestamp(DateTime ts) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSyncHostFailoverTsKey, ts.toIso8601String());
}

// ═════════════════════════════════════════════════════════════════════════════
// LOAD FUNCTIONS (called from background isolate)
// ═════════════════════════════════════════════════════════════════════════════

/// Load sync event configs in background isolate.
Future<List<BackgroundSyncEventConfig>> loadSyncEventsForBackground() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kSyncEventsKey);
    if (raw == null || raw.isEmpty) return const [];
    return raw.map((jsonStr) {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return BackgroundSyncEventConfig.fromJson(map);
    }).toList();
  } catch (e) {
    debugPrint('[SyncBgPersistence] Error loading sync events: $e');
    return const [];
  }
}

/// Load the active group ID.
Future<String?> loadSyncGroupId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kSyncGroupIdKey);
}

/// Load the current user UID.
Future<String?> loadSyncUserUid() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kSyncUserUidKey);
}

/// Load host UID.
Future<String?> loadSyncHostUid() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kSyncHostUidKey);
}

/// Load backup host UID.
Future<String?> loadSyncBackupHostUid() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kSyncBackupHostUidKey);
}

/// Load controller IPs.
Future<List<String>> loadSyncControllerIps() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_kSyncControllerIpsKey) ?? [];
}

/// Load active session info.
Future<BackgroundActiveSession?> loadActiveSession() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kSyncActiveSessionKey);
  if (raw == null) return null;
  try {
    return BackgroundActiveSession.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  } catch (e) {
    return null;
  }
}

/// Load the host failover timestamp.
Future<DateTime?> loadHostFailoverTimestamp() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kSyncHostFailoverTsKey);
  if (raw == null) return null;
  return DateTime.tryParse(raw);
}

/// Clear the failover timestamp.
Future<void> clearHostFailoverTimestamp() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kSyncHostFailoverTsKey);
}
