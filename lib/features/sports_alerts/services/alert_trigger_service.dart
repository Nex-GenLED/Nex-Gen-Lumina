import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../models/autopilot_override.dart';
import '../../../services/autopilot_scheduler.dart';
import '../../wled/wled_payload_utils.dart' show applyChannelFilter;
import '../../wled/wled_service.dart';
import '../../wled/zone_providers.dart'
    show DeviceChannel, deviceChannelsFromConfig;
import '../data/team_colors.dart';
import '../models/score_alert_config.dart';
import '../models/score_alert_event.dart';
import 'celebration_contrast.dart';
import '../models/sport_type.dart';

/// One step of a score-celebration animation: a WLED payload whose `seg` is a
/// single NO-ID template (the caller channel-filters it across all configured
/// channels), held for [hold] before the next step.
class AlertAnimationStep {
  final Map<String, dynamic> payload;
  final Duration hold;
  const AlertAnimationStep(this.payload, this.hold);
}

/// Notification channel for sports score alerts.
const _kAndroidChannel = AndroidNotificationDetails(
  'sports_alerts',
  'Sports Alerts',
  channelDescription: 'Score alerts for your favorite teams',
  importance: Importance.high,
  priority: Priority.high,
  styleInformation: BigTextStyleInformation(''),
);
const _kNotificationDetails = NotificationDetails(
  android: _kAndroidChannel,
  iOS: DarwinNotificationDetails(),
);

/// Translates [ScoreAlertEvent]s into WLED LED animations and local
/// notifications.
///
/// Uses the existing [WledService] HTTP integration to send JSON payloads
/// to the Dig-Octa / WLED controller. Captures the current zone state before
/// each animation and restores it afterwards.
///
/// **Two-level targeting (channel-2 fix):**
///   - [_controllerIps] is the OUTER loop — one entry per *physical
///     controller* (separate IP), sourced from `activeAreaControllerIpsProvider`
///     (linked-residential set or all discovered controllers). This is genuine
///     multi-CONTROLLER fan-out, NOT dead plumbing.
///   - For EACH controller, channels are resolved from that controller's own
///     hardware buses ([_resolveChannels] → [deviceChannelsFromConfig]) and the
///     animation payloads are routed through [applyChannelFilter] so every
///     configured channel (bus) is addressed — not just seg 0 / channel 1.
///
/// Resolving channels per-controller (rather than receiving them from a
/// provider, as the Game Day fix does) is required because this service also
/// runs inside the sports background isolate, which has no Riverpod container —
/// and because channels differ per controller.
///
/// When an [AutopilotScheduler] is provided (i.e. autopilot is active), state
/// capture and restoration are delegated to the scheduler via the override
/// protocol. This prevents double-restore conflicts where both services try
/// to reset the lights simultaneously.
class AlertTriggerService {
  AlertTriggerService({
    required List<String> controllerIps,
    FlutterLocalNotificationsPlugin? notifications,
    this.autopilotScheduler,
  })  : _controllerIps = controllerIps,
        _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  final List<String> _controllerIps;
  final FlutterLocalNotificationsPlugin _notifications;

  /// Optional reference to the autopilot scheduler for override coordination.
  /// When non-null, state capture/restore is delegated to the scheduler.
  final AutopilotScheduler? autopilotScheduler;

  /// Guard against overlapping animations on the same controller.
  bool _animationInProgress = false;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Main entry point called by [ScoreMonitorService] when a score event fires.
  Future<void> handleAlertEvent(
    ScoreAlertEvent event,
    ScoreAlertConfig config,
  ) async {
    final teamColors = kTeamColors[event.teamSlug];
    if (teamColors == null) return;

    // Fire notification in parallel with the LED animation.
    unawaited(_showNotification(event, teamColors));

    if (_animationInProgress) {
      debugPrint('[AlertTrigger] Animation already running, skipping LED');
      return;
    }

    _animationInProgress = true;
    OverrideToken? token;

    try {
      // Request override from autopilot if available
      if (autopilotScheduler != null) {
        final animDuration = animationDuration(event.eventType);
        token = await autopilotScheduler!.requestOverride(
          source: OverrideSource.sportsScoreAlert,
          duration: animDuration,
        );
        // If override was denied (another override active), still proceed
        // with the animation — we just won't get clean autopilot restore
      }

      for (final ip in _controllerIps) {
        final svc = WledService('http://$ip');
        try {
          // Resolve THIS controller's channels from its own hardware buses so
          // the celebration fans out across every configured channel (the
          // channel-2 fix), independent of the participation cache.
          final channels = await _resolveChannels(svc);
          if (channels.isEmpty) {
            // U1 gate: can't read this controller's channel config — skip it
            // rather than fall back to a seg-0-only (channel-1-only) write.
            debugPrint(
                '[AlertTrigger] $ip: no channels resolved — skipping (U1 gate)');
            continue;
          }

          // Only do our own capture/restore if autopilot is NOT managing it
          final previousState =
              (token == null) ? await _captureZoneState(svc) : <String, dynamic>{};

          // AUTOMATIC CONTRAST CHECK (Phase B). The captured state used to go
          // only to _restoreZoneState; it now also decides whether the user's
          // chosen celebration would be invisible against what this controller
          // is showing RIGHT NOW. When autopilot manages capture/restore we
          // never capture ourselves, so the scheduler's own snapshot is the
          // source — otherwise the check would be dead in exactly the case
          // that matters most, a celebration during a scheduled show.
          final baseState = token?.capturedState ?? previousState;
          final resolution = resolveCelebration(
            chosenEffectId: config.celebrationEffectId,
            chosenSpeed: config.celebrationSpeed,
            chosenIntensity: config.celebrationIntensity,
            capturedState: baseState,
          );
          if (resolution?.usedFallback ?? false) {
            debugPrint('[AlertTrigger] $ip: chosen celebration clashes with '
                'the current look — using the safe fallback');
          }

          await _applyAlertAnimation(
              event.eventType, teamColors, svc, channels, resolution);

          if (token == null) {
            await _restoreZoneState(svc, previousState);
          }
        } catch (e) {
          debugPrint('[AlertTrigger] Error on $ip: $e');
        }
      }
    } finally {
      // Release override — autopilot restores state
      if (token != null) {
        await autopilotScheduler!.releaseOverride(token);
      }
      _animationInProgress = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Animation duration helper
  // ---------------------------------------------------------------------------

  /// Calculate expected animation duration for each event type.
  ///
  /// Used by the override protocol to set the override window, and
  /// available to the scheduler for pre-computing durations.
  static Duration animationDuration(AlertEventType eventType) {
    return switch (eventType) {
      AlertEventType.touchdown || AlertEventType.goal =>
        const Duration(seconds: 15),
      AlertEventType.soccerGoal => const Duration(seconds: 20),
      AlertEventType.fieldGoal => const Duration(seconds: 8),
      AlertEventType.safety => const Duration(seconds: 6),
      AlertEventType.run => const Duration(seconds: 6),
      AlertEventType.quarterEndWinning => const Duration(seconds: 10),
      AlertEventType.clutchBasket => const Duration(seconds: 5),
      // The longest in the table, deliberately: a win is the moment the whole
      // feature exists for.
      AlertEventType.win => const Duration(seconds: 30),
      AlertEventType.turnover => Duration.zero,
    };
  }

  // ---------------------------------------------------------------------------
  // State capture / restore
  // ---------------------------------------------------------------------------

  /// Save the current device state so we can restore it after the animation.
  Future<Map<String, dynamic>> _captureZoneState(WledService svc) async {
    final state = await svc.getState();
    return state ?? {};
  }

  /// Restore zones to their previous state after the animation completes.
  Future<void> _restoreZoneState(
    WledService svc,
    Map<String, dynamic> previousState,
  ) async {
    if (previousState.isEmpty) return;

    // Build a minimal restore payload from captured state.
    final restore = <String, dynamic>{};

    final on = previousState['on'];
    if (on != null) restore['on'] = on;

    final bri = previousState['bri'];
    if (bri != null) restore['bri'] = bri;

    // Restore full segment array to bring back previous colors/effects.
    final seg = previousState['seg'];
    if (seg != null) restore['seg'] = seg;

    // If a preset was active, reload it instead.
    final ps = previousState['ps'];
    if (ps is int && ps >= 0) {
      await svc.applyJson({'ps': ps});
      return;
    }

    if (restore.isNotEmpty) {
      await svc.applyJson(restore);
    }
  }

  // ---------------------------------------------------------------------------
  // Channel resolution
  // ---------------------------------------------------------------------------

  /// Resolve a controller's channels from its own hardware buses
  /// (`/json/cfg → hw.led.ins[]`). Returns an empty list when the config can't
  /// be read — the caller treats that as the U1 "skip this controller" gate.
  Future<List<DeviceChannel>> _resolveChannels(WledService svc) async {
    try {
      return deviceChannelsFromConfig(await svc.getConfig());
    } catch (e) {
      debugPrint('[AlertTrigger] resolveChannels failed: $e');
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // LED animation sequences
  // ---------------------------------------------------------------------------

  /// Play the celebration for [eventType] on a single controller, fanning each
  /// step out across [channels] via [applyChannelFilter] (multi-seg-with-ids →
  /// survives the participation chokepoint by Rule 4, lighting EVERY channel).
  ///
  /// Animation content (effects / speeds / colors / timing) is identical to the
  /// previous per-method sequences — see [buildAnimationSteps]. Only the channel
  /// targeting changes: hardcoded `id:0` → per-channel fan-out.
  Future<void> _applyAlertAnimation(
    AlertEventType eventType,
    TeamColors team,
    WledService svc,
    List<DeviceChannel> channels,
    CelebrationResolution? celebration,
  ) async {
    final ids = channels.map((c) => c.id).toList();
    for (final step in buildAnimationSteps(eventType, team, celebration)) {
      await svc.applyJson(applyChannelFilter(step.payload, ids, channels));
      await Future<void>.delayed(step.hold);
    }
  }

  /// Rewrite one legacy stage to use the user's (contrast-resolved) effect.
  ///
  /// The TIMING TABLE IS PRESERVED WHOLE: stage count, hold durations, and the
  /// first stage's `on`/`bri` assertion all come through untouched. Only the
  /// motion is replaced — which is exactly the split Tyler specified, the
  /// switch owning duration and staging while the user owns the effect.
  ///
  /// `sx`/`ix` are taken from the choice too. The user picked their effect in a
  /// live preview at a particular speed and intensity; that is the look they
  /// approved, so honouring it is what makes the picker truthful. The cost is
  /// that the legacy per-stage speed ramp is no longer expressed — a chosen
  /// celebration is one look held for the staged duration rather than three
  /// escalating ones.
  ///
  /// A fallback celebration also overrides `col` to white: it was substituted
  /// precisely because the motion clashed, and team colours are the one axis
  /// left to distinguish it (see [kFallbackCelebrationColor]).
  static Map<String, dynamic> _applyCelebrationToStage(
    Map<String, dynamic> payload,
    CelebrationResolution celebration,
  ) {
    final segs = payload['seg'];
    if (segs is! List) return payload;

    return {
      ...payload,
      'seg': [
        for (final seg in segs)
          if (seg is Map<String, dynamic>)
            {
              ...seg,
              'fx': celebration.effectId,
              'sx': celebration.speed,
              'ix': celebration.intensity,
              if (celebration.usedFallback)
                'col': [
                  List<int>.from(kFallbackCelebrationColor),
                  [0, 0, 0, 0],
                  [0, 0, 0, 0],
                ],
            }
          else
            seg,
      ],
    };
  }

  /// Pure builder for a celebration's ordered animation steps. Each step's `seg`
  /// is a single NO-ID template (the player channel-filters it). Exposed for
  /// unit tests that lock the animation content + prove the channel fan-out.
  ///
  /// Sequences (unchanged from the legacy per-event methods):
  ///   - touchdown / goal      15s: Strobe fx2 (2s) → Wipe fx9 (5s) → Running fx63 (8s)
  ///   - fieldGoal              8s: Breathe fx2
  ///   - safety                 6s: Strobe Mega fx23
  ///   - run                    6s: Theater Chase fx5
  ///   - quarterEndWinning     10s: slow Breathe fx2
  ///   - clutchBasket           5s: rapid Strobe fx23
  ///   - soccerGoal            20s: Chase fx28 (6s) → Strobe fx23 (4s) → Running fx63 (6s) → Breathe fx2 (4s)
  ///   - turnover                  : no animation (Phase 2)
  static List<AlertAnimationStep> buildAnimationSteps(
    AlertEventType eventType,
    TeamColors team, [
    CelebrationResolution? celebration,
  ]) {
    final steps = _legacyAnimationSteps(eventType, team);
    if (celebration == null) return steps; // no user choice → legacy verbatim
    return [
      for (final step in steps)
        AlertAnimationStep(
          _applyCelebrationToStage(step.payload, celebration),
          step.hold,
        ),
    ];
  }

  /// THE TIMING TABLE. Per-event-type duration and staging, unchanged — this is
  /// the part a user's celebration choice does NOT replace. Its literal `fx`
  /// ids are the DEFAULT motion, used verbatim when no celebration has been
  /// chosen, and substituted by [_applyCelebrationToStage] when one has.
  static List<AlertAnimationStep> _legacyAnimationSteps(
    AlertEventType eventType,
    TeamColors team,
  ) {
    final colors = _teamColorArray(team);
    final primary = colorToRgbw(team.primary);
    List<List<int>> primaryOnly() => [
          List<int>.from(primary),
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ];

    switch (eventType) {
      case AlertEventType.touchdown:
      case AlertEventType.goal:
        return [
          AlertAnimationStep({
            'on': true,
            'bri': 255,
            'seg': [
              {'fx': 2, 'sx': 240, 'ix': 255, 'col': colors},
            ],
          }, const Duration(seconds: 2)),
          AlertAnimationStep({
            'seg': [
              {'fx': 9, 'sx': 180, 'ix': 200, 'col': colors},
            ],
          }, const Duration(seconds: 5)),
          AlertAnimationStep({
            'seg': [
              {'fx': 63, 'sx': 128, 'ix': 200, 'col': colors},
            ],
          }, const Duration(seconds: 8)),
        ];

      case AlertEventType.fieldGoal:
        return [
          AlertAnimationStep({
            'on': true,
            'bri': 255,
            'seg': [
              {'fx': 2, 'sx': 110, 'ix': 255, 'col': primaryOnly()},
            ],
          }, const Duration(seconds: 8)),
        ];

      case AlertEventType.safety:
        return [
          AlertAnimationStep({
            'on': true,
            'bri': 255,
            'seg': [
              {'fx': 23, 'sx': 255, 'ix': 255, 'col': primaryOnly()},
            ],
          }, const Duration(seconds: 6)),
        ];

      case AlertEventType.run:
        return [
          AlertAnimationStep({
            'on': true,
            'bri': 255,
            'seg': [
              {'fx': 5, 'sx': 160, 'ix': 200, 'col': colors},
            ],
          }, const Duration(seconds: 6)),
        ];

      case AlertEventType.quarterEndWinning:
        return [
          AlertAnimationStep({
            'on': true,
            'bri': 200,
            'seg': [
              {'fx': 2, 'sx': 60, 'ix': 255, 'col': primaryOnly()},
            ],
          }, const Duration(seconds: 10)),
        ];

      case AlertEventType.clutchBasket:
        return [
          AlertAnimationStep({
            'on': true,
            'bri': 255,
            'seg': [
              {'fx': 23, 'sx': 240, 'ix': 255, 'col': primaryOnly()},
            ],
          }, const Duration(seconds: 5)),
        ];

      case AlertEventType.soccerGoal:
        return [
          AlertAnimationStep({
            'on': true,
            'bri': 180,
            'seg': [
              {'fx': 28, 'sx': 100, 'ix': 200, 'col': colors},
            ],
          }, const Duration(seconds: 6)),
          AlertAnimationStep({
            'bri': 255,
            'seg': [
              {'fx': 23, 'sx': 200, 'ix': 255, 'col': colors},
            ],
          }, const Duration(seconds: 4)),
          AlertAnimationStep({
            'seg': [
              {'fx': 63, 'sx': 140, 'ix': 220, 'col': colors},
            ],
          }, const Duration(seconds: 6)),
          AlertAnimationStep({
            'bri': 120,
            'seg': [
              {'fx': 2, 'sx': 40, 'ix': 200, 'col': primaryOnly()},
            ],
          }, const Duration(seconds: 4)),
        ];

      // WIN — the longest sequence in the table (30s), staged so it builds
      // rather than simply running one effect for half a minute. As with every
      // other entry, a chosen celebration replaces the `fx` at each stage and
      // leaves this staging intact.
      case AlertEventType.win:
        return [
          AlertAnimationStep({
            'on': true,
            'bri': 255,
            'seg': [
              {'fx': 2, 'sx': 255, 'ix': 255, 'col': colors},
            ],
          }, const Duration(seconds: 5)),
          AlertAnimationStep({
            'seg': [
              {'fx': 9, 'sx': 200, 'ix': 220, 'col': colors},
            ],
          }, const Duration(seconds: 10)),
          AlertAnimationStep({
            'seg': [
              {'fx': 63, 'sx': 150, 'ix': 200, 'col': colors},
            ],
          }, const Duration(seconds: 15)),
        ];

      case AlertEventType.turnover:
        // Phase 2 — no animation yet.
        return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Color helpers
  // ---------------------------------------------------------------------------

  /// Build the WLED 3-slot color array: [primary, secondary, black].
  static List<List<int>> _teamColorArray(TeamColors team) => [
        colorToRgbw(team.primary),
        colorToRgbw(team.secondary),
        [0, 0, 0, 0],
      ];

  /// Convert a Flutter [Color] to RGBW with forceZeroWhite for saturated
  /// team colors (per project convention).
  ///
  /// Public so the [AutopilotScheduler] can reuse for pre-game colorways.
  static List<int> colorToRgbw(Color c) => rgbToRgbw(
        (c.r * 255.0).round().clamp(0, 255),
        (c.g * 255.0).round().clamp(0, 255),
        (c.b * 255.0).round().clamp(0, 255),
        forceZeroWhite: true,
      );

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  Future<void> _showNotification(
    ScoreAlertEvent event,
    TeamColors team,
  ) async {
    try {
      final title = _notificationTitle(event, team);
      await _notifications.show(
        6001 + event.eventType.index,
        title,
        'Your lights are celebrating!',
        _kNotificationDetails,
      );
    } catch (e) {
      debugPrint('[AlertTrigger] Notification error: $e');
    }
  }

  static String _notificationTitle(ScoreAlertEvent event, TeamColors team) {
    final emoji = _sportEmoji(event.sport);
    final action = switch (event.eventType) {
      AlertEventType.touchdown => 'Touchdown!',
      AlertEventType.fieldGoal => 'Field Goal!',
      AlertEventType.safety => 'Safety!',
      AlertEventType.goal => 'Goal!',
      AlertEventType.run =>
        event.pointsScored > 1 ? '${event.pointsScored} Runs!' : 'Run!',
      AlertEventType.quarterEndWinning => 'Winning!',
      AlertEventType.clutchBasket => 'Clutch Basket!',
      AlertEventType.turnover => 'Turnover!',
      AlertEventType.soccerGoal => 'GOOOOOL!',
      AlertEventType.win => 'WINS!',
    };
    return '${team.teamName} $action $emoji';
  }

  static String _sportEmoji(SportType sport) => switch (sport) {
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
}
