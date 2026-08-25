// lib/features/autopilot/game_day_autopilot_config.dart
//
// Persistent configuration for a user's Game Day Autopilot subscription
// for a single team. Stored in Firestore at /users/{uid}/game_day_autopilot/{teamSlug}.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../patterns/utils/pattern_display_name.dart';
import '../sports_alerts/models/score_alert_config.dart' show AlertSensitivity;
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

  /// UNIFIED MONITORING — the "Live Scoring" toggle, and the single source of
  /// truth for whether this team is score-monitored. There is no separate
  /// Sports Alerts opt-in any more: selecting a team here with Live Scoring on
  /// arms monitoring, alerts and celebrations for it, full stop.
  ///
  /// Deliberately SEPARATE from [enabled]:
  ///   • [enabled]           → runs the scheduled show. The SERVER planner
  ///                           queries exactly this field
  ///                           (planGameDayFires.ts:342
  ///                           `.where("enabled","==",true)`).
  ///   • [liveScoringEnabled] → monitoring + celebrations. Client-only.
  ///
  /// That split is what lets a team migrated from the retired sports-alerts
  /// list be monitored WITHOUT the planner ever seeing it — it carries
  /// `enabled:false, liveScoringEnabled:true`, so it cannot produce a
  /// first-pitch fire the user never asked for. Collapsing the two would have
  /// required a planner change and a deploy-ordering constraint.
  ///
  /// Absent means TRUE, so every team that already had Game Day keeps its
  /// monitoring across the upgrade.
  final bool liveScoringEnabled;

  /// Which scoring events celebrate. Moved here from the retired
  /// `ScoreAlertConfig` because it is real, consumed behavior
  /// (`score_monitor_service._filterBySensitivity`), and leaving it on a second
  /// model would have kept a second place to configure monitoring.
  final AlertSensitivity alertSensitivity;

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

  // ── Celebration effect (the score/win flash) ──────────────────────────
  //
  // ONE effect per team, chosen once, used for EVERY event type. The
  // per-event-type timing table in AlertTriggerService.buildAnimationSteps
  // still supplies duration and staging — only the hardcoded `fx` in each
  // stage is replaced by this choice
  // (audit/GAME_DAY_SPEC_AUDIT.md §6, gap row 3).
  //
  // These are DELIBERATELY distinct from the base-design fields above
  // ([effectId] / [speed] / [intensity] / [savedDesignPayload]): the base
  // design is what the house runs during the game, this is what interrupts it.
  // Before this existed there was only one design slot, so there was nothing
  // to collide with (audit §4).

  /// WLED effect id for this team's celebration. `null` means the user has
  /// not chosen one — the legacy hardcoded per-event sequences are used
  /// verbatim, so every existing config keeps its current behavior.
  final int? celebrationEffectId;

  /// Celebration speed (`sx`, 0-255). Only meaningful when
  /// [celebrationEffectId] is set.
  final int celebrationSpeed;

  /// Celebration intensity (`ix`, 0-255). Only meaningful when
  /// [celebrationEffectId] is set.
  final int celebrationIntensity;

  /// True when the user has picked a celebration effect for this team.
  bool get hasCelebrationEffect => celebrationEffectId != null;

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
    this.liveScoringEnabled = true,
    this.alertSensitivity = AlertSensitivity.majorOnly,
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
    this.celebrationEffectId,
    this.celebrationSpeed = 240,
    this.celebrationIntensity = 240,
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
        'live_scoring_enabled': liveScoringEnabled,
        'alert_sensitivity': alertSensitivity.toJson(),
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
        // Written only when chosen, so an untouched config stays byte-identical
        // and keeps the legacy hardcoded celebration.
        if (celebrationEffectId != null) ...{
          'celebration_effect_id': celebrationEffectId,
          'celebration_speed': celebrationSpeed,
          'celebration_intensity': celebrationIntensity,
        },
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
          _parseSavedDesignPayload(data['saved_design_payload']),
      effectId: (data['effect_id'] as num?)?.toInt() ?? 52,
      speed: (data['speed'] as num?)?.toInt() ?? 160,
      intensity: (data['intensity'] as num?)?.toInt() ?? 128,
      brightness: (data['brightness'] as num?)?.toInt() ?? 200,
      scoreCelebrationEnabled:
          data['score_celebration_enabled'] as bool? ?? true,
      // ABSENT MEANS "WHATEVER THE USER'S OWN TOGGLE SAYS", not bare true.
      //
      // This branch was written believing `score_celebration_enabled` was
      // absent fleet-wide and the feature unreachable. Measurement inverted
      // that: 49 of 50 live configs carry `score_celebration_enabled: true`,
      // and the switch that writes it is LABELLED "Live Scoring"
      // (game_day_screen.dart `_toggleLiveScoring` -> setLiveScoring).
      //
      // So `live_scoring_enabled` is a NEW field with no history, while a
      // field meaning the same thing to the user already exists and is set.
      // A bare `?? true` would have made monitoring unconditional and, worse,
      // would have overridden the intent of anyone who had deliberately turned
      // that switch OFF — the one user-visible control for this feature.
      // Falling back to it keeps the toggle authoritative until an explicit
      // new value is written, so OFF genuinely means off.
      liveScoringEnabled: data['live_scoring_enabled'] as bool? ??
          data['score_celebration_enabled'] as bool? ??
          true,
      alertSensitivity: _parseSensitivity(data['alert_sensitivity'] as String?),
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
      // Absent means "no celebration effect chosen" — the legacy hardcoded
      // per-event sequences apply. Never defaulted to a real effect id, or
      // every pre-existing config would silently acquire one.
      celebrationEffectId: (data['celebration_effect_id'] as num?)?.toInt(),
      celebrationSpeed: (data['celebration_speed'] as num?)?.toInt() ?? 240,
      celebrationIntensity:
          (data['celebration_intensity'] as num?)?.toInt() ?? 240,
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
    bool? liveScoringEnabled,
    AlertSensitivity? alertSensitivity,
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
    int? celebrationEffectId,
    bool clearCelebrationEffect = false,
    int? celebrationSpeed,
    int? celebrationIntensity,
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
      liveScoringEnabled: liveScoringEnabled ?? this.liveScoringEnabled,
      alertSensitivity: alertSensitivity ?? this.alertSensitivity,
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
      celebrationEffectId: clearCelebrationEffect
          ? null
          : (celebrationEffectId ?? this.celebrationEffectId),
      celebrationSpeed: celebrationSpeed ?? this.celebrationSpeed,
      celebrationIntensity: celebrationIntensity ?? this.celebrationIntensity,
    );
  }

  /// Tolerant read of `saved_design_payload`.
  ///
  /// Post-BUG-GD-PICKER-1 the field is a jsonEncoded String — the raw WLED
  /// payload carries `seg[].col = [[r,g,b,w],…]` nested arrays that Firestore
  /// cannot store as a live Map (native iOS SIGABRT / Android reject), so the
  /// picker's write never actually landed a doc before the fix. Accepts:
  ///   - String → jsonDecode to Map (current shape).
  ///   - Map    → verbatim (defensive; no real legacy docs should exist since
  ///              the raw-Map write always failed, but tolerate anyway).
  ///   - null / empty / malformed → null, so the apply path falls back to the
  ///     auto-built team-color payload rather than throwing.
  static Map<String, dynamic>? _parseSavedDesignPayload(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      if (raw.isEmpty) return null;
      try {
        final decoded = jsonDecode(raw);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (_) {
        return null;
      }
    }
    return null;
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

  /// Tolerant sensitivity parse. `AlertSensitivity.fromJson` throws on an
  /// unknown name (bare `firstWhere`, no orElse), and this reads migrated and
  /// hand-edited documents — so an unrecognised value must degrade to the
  /// default rather than take down the whole config load.
  static AlertSensitivity _parseSensitivity(String? value) {
    if (value == null) return AlertSensitivity.majorOnly;
    return AlertSensitivity.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AlertSensitivity.majorOnly,
    );
  }

  @override
  String toString() =>
      'GameDayAutopilotConfig($teamSlug, enabled=$enabled, design=$designLabel)';
}
