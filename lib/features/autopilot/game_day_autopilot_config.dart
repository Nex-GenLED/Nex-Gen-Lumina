// lib/features/autopilot/game_day_autopilot_config.dart
//
// Persistent configuration for a user's Game Day Autopilot subscription
// for a single team. Stored in Firestore at /users/{uid}/game_day_autopilot/{teamSlug}.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../sports_alerts/models/sport_type.dart';

// ---------------------------------------------------------------------------
// Estimated game durations by sport (used as post-game fallback)
// ---------------------------------------------------------------------------

/// Estimated game duration per sport for the post-game fallback timer.
/// If live end-of-game detection via ESPN fails, the system uses
/// estimatedDuration + 60 min buffer before triggering the 30-min countdown.
Duration estimatedGameDuration(SportType sport) => switch (sport) {
      SportType.mlb => const Duration(hours: 3),
      SportType.nfl || SportType.ncaaFB => const Duration(hours: 3, minutes: 30),
      SportType.nba || SportType.ncaaMB => const Duration(hours: 2, minutes: 30),
      SportType.nhl => const Duration(hours: 2, minutes: 30),
      SportType.mls || SportType.fifa || SportType.championsLeague =>
        const Duration(hours: 2),
    };

// ---------------------------------------------------------------------------
// Design selection mode
// ---------------------------------------------------------------------------

/// How the pre-game design is chosen.
enum AutopilotDesignMode {
  /// User explicitly saved a design for this team.
  saved,

  /// Auto-selected based on UserVarietyProfile / style history.
  autoSelected,

  /// Fallback: solid in team primary color (profile unavailable).
  fallback,
}

// ---------------------------------------------------------------------------
// GameDayAutopilotConfig
// ---------------------------------------------------------------------------

/// Persistent per-team autopilot configuration.
///
/// One document per team slug under `/users/{uid}/game_day_autopilot/{teamSlug}`.
class GameDayAutopilotConfig {
  /// Team slug key from kTeamColors (e.g. 'mlb_royals').
  final String teamSlug;

  /// Display name (e.g. 'Kansas City Royals').
  final String teamName;

  /// ESPN numeric team ID for schedule/score polling.
  final String espnTeamId;

  /// Sport type.
  final SportType sport;

  /// Team primary color (ARGB int).
  final int primaryColorValue;

  /// Team secondary color (ARGB int).
  final int secondaryColorValue;

  /// Whether autopilot is enabled for this team.
  final bool enabled;

  /// How the design was selected.
  final AutopilotDesignMode designMode;

  /// User-saved design name (null if auto-selected or fallback).
  final String? savedDesignName;

  /// WLED payload for the saved or auto-selected design.
  /// Null means the service should compute it at activation time.
  final Map<String, dynamic>? savedDesignPayload;

  /// Effect ID for the design (0 = Solid, 65 = Breathe, etc.).
  final int effectId;

  /// Speed parameter (0-255).
  final int speed;

  /// Intensity parameter (0-255).
  final int intensity;

  /// Brightness parameter (0-255).
  final int brightness;

  /// Whether score celebrations should fire during the game.
  final bool scoreCelebrationEnabled;

  /// When this config was created.
  final DateTime createdAt;

  /// When this config was last modified.
  final DateTime updatedAt;

  const GameDayAutopilotConfig({
    required this.teamSlug,
    required this.teamName,
    required this.espnTeamId,
    required this.sport,
    required this.primaryColorValue,
    required this.secondaryColorValue,
    this.enabled = true,
    this.designMode = AutopilotDesignMode.fallback,
    this.savedDesignName,
    this.savedDesignPayload,
    this.effectId = 0,
    this.speed = 128,
    this.intensity = 128,
    this.brightness = 200,
    this.scoreCelebrationEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Color get primaryColor => Color(primaryColorValue);
  Color get secondaryColor => Color(secondaryColorValue);

  /// Human-readable design label for the UI.
  String get designLabel {
    if (savedDesignName != null && savedDesignName!.isNotEmpty) {
      return savedDesignName!;
    }
    return switch (designMode) {
      AutopilotDesignMode.saved => 'Custom Design',
      AutopilotDesignMode.autoSelected => 'Auto-selected',
      AutopilotDesignMode.fallback => 'Team Colors (Solid)',
    };
  }

  /// Estimated game duration for this sport.
  Duration get estimatedDuration => estimatedGameDuration(sport);

  // ── Serialization ──────────────────────────────────────────────────────

  Map<String, dynamic> toFirestore() => {
        'team_slug': teamSlug,
        'team_name': teamName,
        'espn_team_id': espnTeamId,
        'sport': sport.toJson(),
        'primary_color': primaryColorValue,
        'secondary_color': secondaryColorValue,
        'enabled': enabled,
        'design_mode': designMode.name,
        'saved_design_name': savedDesignName,
        'saved_design_payload': savedDesignPayload,
        'effect_id': effectId,
        'speed': speed,
        'intensity': intensity,
        'brightness': brightness,
        'score_celebration_enabled': scoreCelebrationEnabled,
        'created_at': Timestamp.fromDate(createdAt),
        'updated_at': Timestamp.fromDate(updatedAt),
      };

  factory GameDayAutopilotConfig.fromFirestore(Map<String, dynamic> data) {
    return GameDayAutopilotConfig(
      teamSlug: data['team_slug'] as String? ?? '',
      teamName: data['team_name'] as String? ?? '',
      espnTeamId: data['espn_team_id'] as String? ?? '',
      sport: SportType.fromJson(data['sport'] as String? ?? 'nfl'),
      primaryColorValue: (data['primary_color'] as num?)?.toInt() ?? 0xFF000000,
      secondaryColorValue:
          (data['secondary_color'] as num?)?.toInt() ?? 0xFFFFFFFF,
      enabled: data['enabled'] as bool? ?? true,
      designMode: _parseDesignMode(data['design_mode'] as String?),
      savedDesignName: data['saved_design_name'] as String?,
      savedDesignPayload:
          data['saved_design_payload'] as Map<String, dynamic>?,
      effectId: (data['effect_id'] as num?)?.toInt() ?? 0,
      speed: (data['speed'] as num?)?.toInt() ?? 128,
      intensity: (data['intensity'] as num?)?.toInt() ?? 128,
      brightness: (data['brightness'] as num?)?.toInt() ?? 200,
      scoreCelebrationEnabled:
          data['score_celebration_enabled'] as bool? ?? true,
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  GameDayAutopilotConfig copyWith({
    bool? enabled,
    AutopilotDesignMode? designMode,
    String? savedDesignName,
    Map<String, dynamic>? savedDesignPayload,
    int? effectId,
    int? speed,
    int? intensity,
    int? brightness,
    bool? scoreCelebrationEnabled,
    DateTime? updatedAt,
  }) {
    return GameDayAutopilotConfig(
      teamSlug: teamSlug,
      teamName: teamName,
      espnTeamId: espnTeamId,
      sport: sport,
      primaryColorValue: primaryColorValue,
      secondaryColorValue: secondaryColorValue,
      enabled: enabled ?? this.enabled,
      designMode: designMode ?? this.designMode,
      savedDesignName: savedDesignName ?? this.savedDesignName,
      savedDesignPayload: savedDesignPayload ?? this.savedDesignPayload,
      effectId: effectId ?? this.effectId,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      brightness: brightness ?? this.brightness,
      scoreCelebrationEnabled:
          scoreCelebrationEnabled ?? this.scoreCelebrationEnabled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static AutopilotDesignMode _parseDesignMode(String? value) {
    if (value == null) return AutopilotDesignMode.fallback;
    return AutopilotDesignMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AutopilotDesignMode.fallback,
    );
  }

  @override
  String toString() =>
      'GameDayAutopilotConfig($teamSlug, enabled=$enabled, design=$designLabel)';
}
