// lib/features/autopilot/game_day_autopilot_config.dart
//
// Persistent configuration for a user's Game Day Autopilot subscription
// for a single team. Stored in Firestore at /users/{uid}/game_day_autopilot/{teamSlug}.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../patterns/utils/pattern_display_name.dart';
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
      SportType.nba || SportType.wnba || SportType.ncaaMB =>
        const Duration(hours: 2, minutes: 30),
      SportType.nhl => const Duration(hours: 2, minutes: 30),
      SportType.mls ||
      SportType.nwsl ||
      SportType.fifa ||
      SportType.championsLeague =>
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
// Design variety mode
// ---------------------------------------------------------------------------

/// How pre-game designs are selected across multiple games.
enum AutopilotVarietyMode {
  /// Same design every game (saved or fallback).
  fixed,

  /// Cycle through the team's design catalog in order.
  /// Default for new autopilot configs.
  rotating,
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

  /// Whether to skip games where the entire game is in daylight at the
  /// user's location. When true (default), a game is skipped if its end
  /// time is more than 30 minutes before local sunset on the game's date.
  /// Night / evening games are unaffected — autopilot activates as normal.
  final bool skipDayGames;

  /// How pre-game designs rotate across games.
  /// - fixed: use the same design (saved or fallback) for every game
  /// - rotating: cycle through the team design catalog in order
  final AutopilotVarietyMode designVariety;

  /// User preference for design dynamism: 0.0 = static, 1.0 =
  /// fast motion. Currently persisted and surfaced in UI but
  /// not yet consumed by autopilot's design selection.
  /// TODO(v1.0.1): wire into game_day_autopilot_service.dart
  /// _selectDesign to weight effect choices by motion preference.
  final double motionStyle;

  /// Lead-time-before-game override in minutes. When null, defaults to 30.
  /// Applies to all future games for this team unless overridden by a
  /// per-date user CalendarEntry.
  final int? leadTimeMinutesOverride;

  /// Fixed on-time override in "HH:MM" 24-hour format. When non-null,
  /// ignores leadTimeMinutesOverride and uses this absolute time for all
  /// future games. Useful for users who want "always 5:00 PM regardless
  /// of kickoff."
  final String? onTimeOverride;

  /// Fixed off-time override in "HH:MM" 24-hour format. When non-null,
  /// ignores "game end + 60min" default. Same semantics as onTimeOverride.
  final String? offTimeOverride;

  /// Optional end bound for materialization. When non-null, the rolling
  /// 7-day calendar populate ([populateCalendarForTeam]) skips any game
  /// whose date falls after this day (inclusive of the day itself), so the
  /// autopilot stops writing future entries once the bound passes. Null
  /// means open-ended — the sport's natural season end governs. Set from a
  /// Lumina recurring-sports rule ("...through Oct 2026"); additive, so
  /// existing configs deserialize to null with no migration.
  final DateTime? untilDate;

  /// When this config was created.
  final DateTime createdAt;

  /// When this config was last modified.
  final DateTime updatedAt;

  /// Channel indices that participate in this team's Game Day show for
  /// the user's controller. `null` means "no explicit choice" — the
  /// default-participation policy in [resolveParticipatingChannels]
  /// applies. An empty list `[]` means the user explicitly opted out
  /// of all channels for this team. Read by the apply path, not stored
  /// verbatim.
  final List<int>? participatingChannelIndices;

  const GameDayAutopilotConfig({
    required this.teamSlug,
    required this.teamName,
    required this.espnTeamId,
    required this.sport,
    required this.primaryColorValue,
    required this.secondaryColorValue,
    this.enabled = false,
    this.designMode = AutopilotDesignMode.fallback,
    this.savedDesignName,
    this.savedDesignPayload,
    this.effectId = 52,
    this.speed = 160,
    this.intensity = 128,
    this.brightness = 200,
    this.scoreCelebrationEnabled = true,
    this.skipDayGames = true,
    this.designVariety = AutopilotVarietyMode.rotating,
    this.motionStyle = 0.5,
    this.leadTimeMinutesOverride,
    this.onTimeOverride,
    this.offTimeOverride,
    this.untilDate,
    required this.createdAt,
    required this.updatedAt,
    this.participatingChannelIndices,
  });

  Color get primaryColor => Color(primaryColorValue);
  Color get secondaryColor => Color(secondaryColorValue);

  /// Human-readable design label for the UI.
  ///
  /// Resolution order:
  ///   1. If [savedDesignName] is set, use it (user-named design wins).
  ///   2. If the effect has been customized away from the default Solid
  ///      (effectId != 0), reflect the live effect: "<team> <Effect>".
  ///      Without this branch a Theater-Chase-customized team would still
  ///      show "Team Colors" on the card despite playing fx 12.
  ///   3. Fall back to a mode-derived label. The fallback no longer
  ///      includes "(Solid)" — that suffix was misleading once any non-
  ///      Solid effect was in use, and adds noise even when accurate.
  String get designLabel {
    if (savedDesignName != null && savedDesignName!.isNotEmpty) {
      return savedDesignName!;
    }
    if (effectId != 0) {
      return '$teamName ${_effectShortName(effectId)}';
    }
    return switch (designMode) {
      AutopilotDesignMode.saved => 'Custom Design',
      AutopilotDesignMode.autoSelected => 'Auto-selected',
      AutopilotDesignMode.fallback => '$teamName Colors',
    };
  }

  /// Compact team name for Now Playing labels.
  ///
  /// Pre-2026-05-23 this split [teamSlug] on hyphen only, but actual
  /// slugs in [kTeamColors] are underscore-separated with a league
  /// prefix (e.g. `nfl_bills`, `cl_ac_milan`). The split was a no-op
  /// for the real data, and the result leaked both the league prefix
  /// and the underscore character into Game Day labels — visible to
  /// the user as "Nfl_bills Game Day" in Now Playing.
  ///
  /// Resolution order (Fix 3 Part 2):
  ///   1. Prefer [teamShortName] against [teamName]. This hits the
  ///      curated short-name overrides for multi-word nicknames
  ///      ("Boston Red Sox" → "Red Sox"), city-shared clubs
  ///      ("AC Milan" → "AC Milan"), league-suffix clubs
  ///      ("Inter Miami CF" → "Inter Miami"), and falls back to
  ///      `.split(' ').last` for the ~354 standard "City Mascot" teams
  ///      ("Kansas City Royals" → "Royals", "Chicago Bears" → "Bears").
  ///   2. Fallback (only when [teamName] is empty): split [teamSlug]
  ///      on either `-` or `_`, capitalize the last non-empty chunk.
  ///      Handles legacy hyphen-style slugs and any future
  ///      underscore-style slug whose [teamName] field wasn't
  ///      populated.
  ///
  /// Guarantee: the returned string NEVER contains `_` for any
  /// non-empty input. Asserted by the regression test that iterates
  /// every entry in [kTeamColors].
  String get shortTeamName {
    if (teamName.isNotEmpty) {
      return teamShortName(teamName);
    }
    if (teamSlug.isEmpty) return teamName;
    final parts = teamSlug
        .split(RegExp(r'[-_]'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return teamName;
    final last = parts.last;
    return last[0].toUpperCase() + last.substring(1);
  }

  /// Map a WLED effectId to a short display name for [designLabel].
  /// Curated to game-day-relevant effects; unknown ids fall back to
  /// "Custom" to avoid leaking raw effect numbers into the UI.
  static String _effectShortName(int effectId) {
    const names = {
      0: 'Solid', 2: 'Breathe', 12: 'Fade',
      28: 'Chase', 38: 'Fire', 39: 'Fireworks',
      17: 'Twinkle', 20: 'Sparkle', 41: 'Lighthouse',
      43: 'Chase', 46: 'Lightning', 52: 'Running',
      80: 'Twinklefox', 83: 'Pattern', 87: 'Glitter',
    };
    return names[effectId] ?? 'Custom';
  }

  /// Estimated game duration for this sport.
  Duration get estimatedDuration => estimatedGameDuration(sport);

  /// Effective lead time in minutes. Falls back to 30 if no override set.
  int get effectiveLeadTimeMinutes => leadTimeMinutesOverride ?? 30;

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
        'skip_day_games': skipDayGames,
        'design_variety': designVariety.name,
        'motion_style': motionStyle,
        if (leadTimeMinutesOverride != null)
          'lead_time_minutes_override': leadTimeMinutesOverride,
        if (onTimeOverride != null) 'on_time_override': onTimeOverride,
        if (offTimeOverride != null) 'off_time_override': offTimeOverride,
        if (untilDate != null) 'until_date': Timestamp.fromDate(untilDate!),
        'created_at': Timestamp.fromDate(createdAt),
        'updated_at': Timestamp.fromDate(updatedAt),
        if (participatingChannelIndices != null)
          'participating_channel_indices': participatingChannelIndices,
      };

  factory GameDayAutopilotConfig.fromFirestore(Map<String, dynamic> data) {
    final rawParticipating = data['participating_channel_indices'];
    return GameDayAutopilotConfig(
      teamSlug: data['team_slug'] as String? ?? '',
      teamName: data['team_name'] as String? ?? '',
      espnTeamId: data['espn_team_id'] as String? ?? '',
      sport: SportType.fromJson(data['sport'] as String? ?? 'nfl'),
      primaryColorValue: (data['primary_color'] as num?)?.toInt() ?? 0xFF000000,
      secondaryColorValue:
          (data['secondary_color'] as num?)?.toInt() ?? 0xFFFFFFFF,
      enabled: data['enabled'] as bool? ?? false,
      designMode: _parseDesignMode(data['design_mode'] as String?),
      savedDesignName: data['saved_design_name'] as String?,
      savedDesignPayload:
          data['saved_design_payload'] as Map<String, dynamic>?,
      effectId: (data['effect_id'] as num?)?.toInt() ?? 52,
      speed: (data['speed'] as num?)?.toInt() ?? 160,
      intensity: (data['intensity'] as num?)?.toInt() ?? 128,
      brightness: (data['brightness'] as num?)?.toInt() ?? 200,
      scoreCelebrationEnabled:
          data['score_celebration_enabled'] as bool? ?? true,
      skipDayGames: data['skip_day_games'] as bool? ?? true,
      designVariety: _parseVarietyMode(data['design_variety'] as String?),
      motionStyle: (data['motion_style'] as num?)?.toDouble() ?? 0.5,
      leadTimeMinutesOverride:
          (data['lead_time_minutes_override'] as num?)?.toInt(),
      onTimeOverride: data['on_time_override'] as String?,
      offTimeOverride: data['off_time_override'] as String?,
      untilDate: (data['until_date'] as Timestamp?)?.toDate(),
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      participatingChannelIndices: rawParticipating is List
          ? rawParticipating.map((e) => (e as num).toInt()).toList()
          : null,
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
    bool? skipDayGames,
    AutopilotVarietyMode? designVariety,
    double? motionStyle,
    int? leadTimeMinutesOverride,
    String? onTimeOverride,
    String? offTimeOverride,
    DateTime? untilDate,
    bool clearUntilDate = false,
    DateTime? updatedAt,
    List<int>? participatingChannelIndices,
    bool clearParticipatingChannelIndices = false,
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
      skipDayGames: skipDayGames ?? this.skipDayGames,
      designVariety: designVariety ?? this.designVariety,
      motionStyle: motionStyle ?? this.motionStyle,
      leadTimeMinutesOverride:
          leadTimeMinutesOverride ?? this.leadTimeMinutesOverride,
      onTimeOverride: onTimeOverride ?? this.onTimeOverride,
      offTimeOverride: offTimeOverride ?? this.offTimeOverride,
      untilDate: clearUntilDate ? null : (untilDate ?? this.untilDate),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      participatingChannelIndices: clearParticipatingChannelIndices
          ? null
          : (participatingChannelIndices ?? this.participatingChannelIndices),
    );
  }

  static AutopilotDesignMode _parseDesignMode(String? value) {
    if (value == null) return AutopilotDesignMode.fallback;
    return AutopilotDesignMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AutopilotDesignMode.fallback,
    );
  }

  static AutopilotVarietyMode _parseVarietyMode(String? value) {
    if (value == null) return AutopilotVarietyMode.rotating;
    return AutopilotVarietyMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AutopilotVarietyMode.rotating,
    );
  }

  @override
  String toString() =>
      'GameDayAutopilotConfig($teamSlug, enabled=$enabled, design=$designLabel)';
}
