// lib/features/autopilot/game_day_background_persistence.dart
//
// SharedPreferences-based persistence layer for Game Day Autopilot state.
// Used by the background service isolate which has no access to Riverpod,
// Firestore listeners, or the Flutter widget tree.
//
// Mirrors the pattern in features/neighborhood/services/sync_event_background_persistence.dart.
//
// The UI layer writes state here whenever configs change or sessions
// update. The background worker reads on each polling cycle and writes
// back session state as sessions transition phases.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_day_autopilot_config.dart';
import 'game_day_autopilot_service.dart';

const _kConfigsKey = 'bg_gameday_configs';
const _kSessionsKey = 'bg_gameday_sessions';
const _kUserPriorityKey = 'bg_gameday_user_priority';
const _kUserLocationKey = 'bg_gameday_user_location';
const _kUserPreferredStylesKey = 'bg_gameday_preferred_styles';
const _kControllerIpsKey = 'bg_gameday_controller_ips';
const _kUserUidKey = 'bg_gameday_user_uid';

// ═════════════════════════════════════════════════════════════════════════
// BACKGROUND CONFIG — serializable subset of GameDayAutopilotConfig
// ═════════════════════════════════════════════════════════════════════════

/// Serializable mirror of GameDayAutopilotConfig for the background isolate.
/// Holds exactly what the background worker needs to evaluate games and
/// build WLED payloads. Excludes Firestore-specific types (Timestamp etc.)
/// in favor of ISO8601 strings.
class BackgroundGameDayAutopilotConfig {
  final String teamSlug;
  final String teamName;
  final String espnTeamId;
  final String sport; // SportType.name
  final int primaryColorValue;
  final int secondaryColorValue;
  final bool enabled;

  // Design selection
  final String designMode; // AutopilotDesignMode.name
  final int effectId;
  final int speed;
  final int intensity;
  final int brightness;
  final String? savedDesignName;
  final Map<String, dynamic>? savedDesignPayload;

  // Variety + overrides
  final bool skipDayGames;
  final String designVariety; // AutopilotVarietyMode.name
  final int? leadTimeMinutesOverride;
  final String? onTimeOverride;
  final String? offTimeOverride;

  // Score celebrations (future — background will handle these in D3+)
  final bool scoreCelebrationEnabled;

  const BackgroundGameDayAutopilotConfig({
    required this.teamSlug,
    required this.teamName,
    required this.espnTeamId,
    required this.sport,
    required this.primaryColorValue,
    required this.secondaryColorValue,
    required this.enabled,
    required this.designMode,
    required this.effectId,
    required this.speed,
    required this.intensity,
    required this.brightness,
    this.savedDesignName,
    this.savedDesignPayload,
    required this.skipDayGames,
    required this.designVariety,
    this.leadTimeMinutesOverride,
    this.onTimeOverride,
    this.offTimeOverride,
    required this.scoreCelebrationEnabled,
  });

  Map<String, dynamic> toJson() => {
        'teamSlug': teamSlug,
        'teamName': teamName,
        'espnTeamId': espnTeamId,
        'sport': sport,
        'primaryColorValue': primaryColorValue,
        'secondaryColorValue': secondaryColorValue,
        'enabled': enabled,
        'designMode': designMode,
        'effectId': effectId,
        'speed': speed,
        'intensity': intensity,
        'brightness': brightness,
        'savedDesignName': savedDesignName,
        'savedDesignPayload': savedDesignPayload,
        'skipDayGames': skipDayGames,
        'designVariety': designVariety,
        'leadTimeMinutesOverride': leadTimeMinutesOverride,
        'onTimeOverride': onTimeOverride,
        'offTimeOverride': offTimeOverride,
        'scoreCelebrationEnabled': scoreCelebrationEnabled,
      };

  factory BackgroundGameDayAutopilotConfig.fromJson(
    Map<String, dynamic> json,
  ) {
    return BackgroundGameDayAutopilotConfig(
      teamSlug: json['teamSlug'] ?? '',
      teamName: json['teamName'] ?? '',
      espnTeamId: json['espnTeamId'] ?? '',
      sport: json['sport'] ?? '',
      primaryColorValue: json['primaryColorValue'] ?? 0xFFFFFFFF,
      secondaryColorValue: json['secondaryColorValue'] ?? 0xFF000000,
      enabled: json['enabled'] ?? false,
      designMode: json['designMode'] ?? 'fallback',
      effectId: json['effectId'] ?? 0,
      speed: json['speed'] ?? 128,
      intensity: json['intensity'] ?? 128,
      brightness: json['brightness'] ?? 200,
      savedDesignName: json['savedDesignName'] as String?,
      savedDesignPayload: json['savedDesignPayload'] == null
          ? null
          : Map<String, dynamic>.from(json['savedDesignPayload'] as Map),
      skipDayGames: json['skipDayGames'] ?? true,
      designVariety: json['designVariety'] ?? 'rotating',
      leadTimeMinutesOverride:
          (json['leadTimeMinutesOverride'] as num?)?.toInt(),
      onTimeOverride: json['onTimeOverride'] as String?,
      offTimeOverride: json['offTimeOverride'] as String?,
      scoreCelebrationEnabled: json['scoreCelebrationEnabled'] ?? false,
    );
  }

  /// Build from a full GameDayAutopilotConfig (called from UI layer).
  factory BackgroundGameDayAutopilotConfig.fromConfig(
    GameDayAutopilotConfig config,
  ) {
    return BackgroundGameDayAutopilotConfig(
      teamSlug: config.teamSlug,
      teamName: config.teamName,
      espnTeamId: config.espnTeamId,
      sport: config.sport.name,
      primaryColorValue: config.primaryColorValue,
      secondaryColorValue: config.secondaryColorValue,
      enabled: config.enabled,
      designMode: config.designMode.name,
      effectId: config.effectId,
      speed: config.speed,
      intensity: config.intensity,
      brightness: config.brightness,
      savedDesignName: config.savedDesignName,
      savedDesignPayload: config.savedDesignPayload,
      skipDayGames: config.skipDayGames,
      designVariety: config.designVariety.name,
      leadTimeMinutesOverride: config.leadTimeMinutesOverride,
      onTimeOverride: config.onTimeOverride,
      offTimeOverride: config.offTimeOverride,
      scoreCelebrationEnabled: config.scoreCelebrationEnabled,
    );
  }

  /// Effective lead time, mirroring GameDayAutopilotConfig.effectiveLeadTimeMinutes.
  int get effectiveLeadTimeMinutes => leadTimeMinutesOverride ?? 30;
}

// ═════════════════════════════════════════════════════════════════════════
// BACKGROUND SESSION — serializable mirror of AutopilotSession
// ═════════════════════════════════════════════════════════════════════════

class BackgroundAutopilotSession {
  final String teamSlug;
  final String phase; // AutopilotSessionPhase.name
  final DateTime? gameStart;
  final DateTime? gameEndDetected;
  final DateTime? countdownEnd;
  final String? activeGameId;
  final bool usedFallbackTimer;
  final DateTime activatedAt;

  const BackgroundAutopilotSession({
    required this.teamSlug,
    required this.phase,
    this.gameStart,
    this.gameEndDetected,
    this.countdownEnd,
    this.activeGameId,
    this.usedFallbackTimer = false,
    required this.activatedAt,
  });

  Map<String, dynamic> toJson() => {
        'teamSlug': teamSlug,
        'phase': phase,
        'gameStart': gameStart?.toIso8601String(),
        'gameEndDetected': gameEndDetected?.toIso8601String(),
        'countdownEnd': countdownEnd?.toIso8601String(),
        'activeGameId': activeGameId,
        'usedFallbackTimer': usedFallbackTimer,
        'activatedAt': activatedAt.toIso8601String(),
      };

  factory BackgroundAutopilotSession.fromJson(Map<String, dynamic> json) {
    return BackgroundAutopilotSession(
      teamSlug: json['teamSlug'] ?? '',
      phase: json['phase'] ?? 'idle',
      gameStart: json['gameStart'] == null
          ? null
          : DateTime.tryParse(json['gameStart']),
      gameEndDetected: json['gameEndDetected'] == null
          ? null
          : DateTime.tryParse(json['gameEndDetected']),
      countdownEnd: json['countdownEnd'] == null
          ? null
          : DateTime.tryParse(json['countdownEnd']),
      activeGameId: json['activeGameId'] as String?,
      usedFallbackTimer: json['usedFallbackTimer'] ?? false,
      activatedAt: DateTime.tryParse(json['activatedAt'] ?? '') ??
          DateTime.now(),
    );
  }

  factory BackgroundAutopilotSession.fromSession(AutopilotSession session) {
    return BackgroundAutopilotSession(
      teamSlug: session.teamSlug,
      phase: session.phase.name,
      gameStart: session.gameStart,
      gameEndDetected: session.gameEndDetected,
      countdownEnd: session.countdownEnd,
      activeGameId: session.activeGameId,
      usedFallbackTimer: session.usedFallbackTimer,
      activatedAt: session.gameStart ?? DateTime.now(),
    );
  }

  bool get isActive =>
      phase == 'preGame' || phase == 'liveGame' || phase == 'postGame';
}

// ═════════════════════════════════════════════════════════════════════════
// USER CONTEXT TYPES — user profile data the background needs
// ═════════════════════════════════════════════════════════════════════════

/// User's geographic location for daylight filter calculations.
class BackgroundUserLocation {
  final double latitude;
  final double longitude;

  const BackgroundUserLocation({
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory BackgroundUserLocation.fromJson(Map<String, dynamic> json) {
    return BackgroundUserLocation(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// PERSISTENCE FUNCTIONS (called from UI layer)
// ═════════════════════════════════════════════════════════════════════════

/// Save Game Day configs for the background isolate to read.
/// Called whenever configs change in the UI.
Future<void> saveGameDayConfigsForBackground(
  List<BackgroundGameDayAutopilotConfig> configs,
) async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = configs.map((c) => jsonEncode(c.toJson())).toList();
  await prefs.setStringList(_kConfigsKey, encoded);
  debugPrint(
    '[GameDayBgPersistence] Saved ${configs.length} configs for background',
  );
}

/// Save an active session snapshot. Called from foreground on transitions.
/// Background worker writes via saveGameDaySessionsFromBackground.
Future<void> saveGameDaySession(BackgroundAutopilotSession session) async {
  final sessions = await loadGameDaySessions();
  final updated = Map<String, BackgroundAutopilotSession>.from(sessions);
  updated[session.teamSlug] = session;
  await _persistSessions(updated.values.toList());
}

/// Remove a session (session ended or cancelled).
Future<void> clearGameDaySession(String teamSlug) async {
  final sessions = await loadGameDaySessions();
  final updated = Map<String, BackgroundAutopilotSession>.from(sessions)
    ..remove(teamSlug);
  await _persistSessions(updated.values.toList());
}

/// Persist the full session map atomically. Used by the background worker
/// to sync its in-memory state back to SharedPreferences each cycle.
Future<void> saveGameDaySessionsFromBackground(
  List<BackgroundAutopilotSession> sessions,
) => _persistSessions(sessions);

Future<void> _persistSessions(
  List<BackgroundAutopilotSession> sessions,
) async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = sessions.map((s) => jsonEncode(s.toJson())).toList();
  await prefs.setStringList(_kSessionsKey, encoded);
}

/// Save the user's team priority list.
Future<void> saveUserTeamPriority(List<String> priority) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_kUserPriorityKey, priority);
}

/// Save the user's location for daylight calculations.
Future<void> saveUserLocation(BackgroundUserLocation? location) async {
  final prefs = await SharedPreferences.getInstance();
  if (location == null) {
    await prefs.remove(_kUserLocationKey);
  } else {
    await prefs.setString(_kUserLocationKey, jsonEncode(location.toJson()));
  }
}

/// Save the user's preferred effect styles for auto-design selection.
Future<void> saveUserPreferredStyles(List<String> styles) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_kUserPreferredStylesKey, styles);
}

/// Save controller IPs for direct WLED commands from background.
Future<void> saveGameDayControllerIps(List<String> ips) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_kControllerIpsKey, ips);
}

/// Save current user UID.
Future<void> saveGameDayUserUid(String? uid) async {
  final prefs = await SharedPreferences.getInstance();
  if (uid == null) {
    await prefs.remove(_kUserUidKey);
  } else {
    await prefs.setString(_kUserUidKey, uid);
  }
}

// ═════════════════════════════════════════════════════════════════════════
// LOAD FUNCTIONS (called from background isolate)
// ═════════════════════════════════════════════════════════════════════════

/// Load Game Day configs in the background isolate.
Future<List<BackgroundGameDayAutopilotConfig>>
    loadGameDayConfigsForBackground() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kConfigsKey);
    if (raw == null || raw.isEmpty) return const [];
    return raw.map((jsonStr) {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return BackgroundGameDayAutopilotConfig.fromJson(map);
    }).toList();
  } catch (e) {
    debugPrint('[GameDayBgPersistence] Error loading configs: $e');
    return const [];
  }
}

/// Load all active sessions keyed by team slug.
Future<Map<String, BackgroundAutopilotSession>> loadGameDaySessions() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kSessionsKey);
    if (raw == null || raw.isEmpty) return const {};
    final out = <String, BackgroundAutopilotSession>{};
    for (final jsonStr in raw) {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final session = BackgroundAutopilotSession.fromJson(map);
      out[session.teamSlug] = session;
    }
    return out;
  } catch (e) {
    debugPrint('[GameDayBgPersistence] Error loading sessions: $e');
    return const {};
  }
}

/// Load user team priority.
Future<List<String>> loadUserTeamPriority() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_kUserPriorityKey) ?? const [];
}

/// Load user location.
Future<BackgroundUserLocation?> loadUserLocation() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kUserLocationKey);
  if (raw == null) return null;
  try {
    return BackgroundUserLocation.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  } catch (_) {
    return null;
  }
}

/// Load user preferred styles.
Future<List<String>> loadUserPreferredStyles() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_kUserPreferredStylesKey) ?? const [];
}

/// Load controller IPs.
Future<List<String>> loadGameDayControllerIps() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_kControllerIpsKey) ?? const [];
}

/// Load current user UID.
Future<String?> loadGameDayUserUid() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kUserUidKey);
}

/// Load the single currently-active Game Day session, if any. Returns
/// the first session in preGame/liveGame/postGame phase. Useful for
/// other background workers (e.g. sync worker) checking for Game Day
/// presence.
Future<BackgroundAutopilotSession?> loadActiveGameDaySession() async {
  final sessions = await loadGameDaySessions();
  for (final session in sessions.values) {
    if (session.isActive) return session;
  }
  return null;
}
