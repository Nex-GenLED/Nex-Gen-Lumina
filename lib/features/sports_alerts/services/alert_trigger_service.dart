import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../models/autopilot_override.dart';
import '../../../services/autopilot_scheduler.dart';
import '../../wled/wled_service.dart';
import '../data/team_colors.dart';
import '../models/score_alert_config.dart';
import '../models/score_alert_event.dart';
import '../models/sport_type.dart';

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
          // Only do our own capture/restore if autopilot is NOT managing it
          final previousState =
              (token == null) ? await _captureZoneState(svc) : <String, dynamic>{};

          await _applyAlertAnimation(event.eventType, teamColors, svc);

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
  // LED animation sequences
  // ---------------------------------------------------------------------------

  /// Dispatch the correct animation for the given [eventType].
  Future<void> _applyAlertAnimation(
    AlertEventType eventType,
    TeamColors team,
    WledService svc,
  ) async {
    switch (eventType) {
      case AlertEventType.touchdown:
      case AlertEventType.goal:
        await _animateTouchdownGoal(team, svc);

      case AlertEventType.fieldGoal:
        await _animateFieldGoal(team, svc);

      case AlertEventType.safety:
        await _animateSafety(team, svc);

      case AlertEventType.run:
        await _animateRun(team, svc);

      case AlertEventType.quarterEndWinning:
        await _animateQuarterEnd(team, svc);

      case AlertEventType.clutchBasket:
        await _animateClutchBasket(team, svc);

      case AlertEventType.soccerGoal:
        await _animateSoccerGoal(team, svc);

      case AlertEventType.turnover:
        // Phase 2 — no animation yet.
        break;
    }
  }

  /// Touchdown / Goal: 15s total.
  /// Strobe (2s) → Color Wipe (5s) → Running Lights (8s).
  Future<void> _animateTouchdownGoal(TeamColors team, WledService svc) async {
    final colors = _teamColorArray(team);

    // Phase 1: Strobe — effect ID 2
    await svc.applyJson({
      'on': true,
      'bri': 255,
      'seg': [
        {'id': 0, 'fx': 2, 'sx': 240, 'ix': 255, 'col': colors},
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 2));

    // Phase 2: Color Wipe — effect ID 9
    await svc.applyJson({
      'seg': [
        {'id': 0, 'fx': 9, 'sx': 180, 'ix': 200, 'col': colors},
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 5));

    // Phase 3: Running Lights — effect ID 63
    await svc.applyJson({
      'seg': [
        {'id': 0, 'fx': 63, 'sx': 128, 'ix': 200, 'col': colors},
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 8));
  }

  /// Field Goal: 8s — Pulse/breathing in team primary (3 pulses).
  /// Breathe effect = ID 2 (Breathe) at moderate speed.
  Future<void> _animateFieldGoal(TeamColors team, WledService svc) async {
    final primary = colorToRgbw(team.primary);

    // Breathe effect ID 2 → actually WLED "Breathe" is fx 2 when
    // using the standard effect list; for pulse we use Breath (ID 2)
    // with speed tuned for ~3 pulses in 8s.
    await svc.applyJson({
      'on': true,
      'bri': 255,
      'seg': [
        {
          'id': 0,
          'fx': 2,
          'sx': 110,
          'ix': 255,
          'col': [primary, [0, 0, 0, 0], [0, 0, 0, 0]],
        },
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 8));
  }

  /// Safety: 6s — fast flash in team primary.
  /// Strobe effect (ID 23 = Strobe Mega) at max speed.
  Future<void> _animateSafety(TeamColors team, WledService svc) async {
    final primary = colorToRgbw(team.primary);

    await svc.applyJson({
      'on': true,
      'bri': 255,
      'seg': [
        {
          'id': 0,
          'fx': 23,
          'sx': 255,
          'ix': 255,
          'col': [primary, [0, 0, 0, 0], [0, 0, 0, 0]],
        },
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 6));
  }

  /// Run scored: 6s (max 10s) — Theater Chase in team colors.
  /// Theater Chase = effect ID 5.
  Future<void> _animateRun(TeamColors team, WledService svc) async {
    final colors = _teamColorArray(team);

    await svc.applyJson({
      'on': true,
      'bri': 255,
      'seg': [
        {'id': 0, 'fx': 5, 'sx': 160, 'ix': 200, 'col': colors},
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 6));
  }

  /// Quarter end winning: 10s — slow breathe in team primary.
  Future<void> _animateQuarterEnd(TeamColors team, WledService svc) async {
    final primary = colorToRgbw(team.primary);

    await svc.applyJson({
      'on': true,
      'bri': 200,
      'seg': [
        {
          'id': 0,
          'fx': 2,
          'sx': 60,
          'ix': 255,
          'col': [primary, [0, 0, 0, 0], [0, 0, 0, 0]],
        },
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 10));
  }

  /// Clutch basket: 5s — rapid flash in team primary.
  Future<void> _animateClutchBasket(TeamColors team, WledService svc) async {
    final primary = colorToRgbw(team.primary);

    await svc.applyJson({
      'on': true,
      'bri': 255,
      'seg': [
        {
          'id': 0,
          'fx': 23,
          'sx': 240,
          'ix': 255,
          'col': [primary, [0, 0, 0, 0], [0, 0, 0, 0]],
        },
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 5));
  }

  /// Soccer Goal: 20s total.
  /// Slow Build Chase (6s) → Peak Flash (4s) → Celebration Running (6s) → Slow Fade (4s).
  /// Goals are rare in soccer — the celebration is deliberately longer and
  /// builds from a slow chase into a dramatic strobe peak before fading.
  Future<void> _animateSoccerGoal(TeamColors team, WledService svc) async {
    final colors = _teamColorArray(team);
    final primary = colorToRgbw(team.primary);

    // Phase 1: Slow Build Chase — Chase effect (fx:28) at moderate speed
    await svc.applyJson({
      'on': true,
      'bri': 180,
      'seg': [
        {'id': 0, 'fx': 28, 'sx': 100, 'ix': 200, 'col': colors},
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 6));

    // Phase 2: Peak Flash — Strobe Mega (fx:23) at max brightness
    await svc.applyJson({
      'bri': 255,
      'seg': [
        {'id': 0, 'fx': 23, 'sx': 200, 'ix': 255, 'col': colors},
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 4));

    // Phase 3: Celebration — Running Lights (fx:63) with both team colors
    await svc.applyJson({
      'seg': [
        {'id': 0, 'fx': 63, 'sx': 140, 'ix': 220, 'col': colors},
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 6));

    // Phase 4: Slow Fade — Breathe (fx:2) at low speed for fade-out
    await svc.applyJson({
      'bri': 120,
      'seg': [
        {
          'id': 0,
          'fx': 2,
          'sx': 40,
          'ix': 200,
          'col': [primary, [0, 0, 0, 0], [0, 0, 0, 0]],
        },
      ],
    });
    await Future<void>.delayed(const Duration(seconds: 4));
  }

  // ---------------------------------------------------------------------------
  // Color helpers
  // ---------------------------------------------------------------------------

  /// Build the WLED 3-slot color array: [primary, secondary, black].
  List<List<int>> _teamColorArray(TeamColors team) => [
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
    };
    return '${team.teamName} $action $emoji';
  }

  static String _sportEmoji(SportType sport) => switch (sport) {
        SportType.nfl || SportType.ncaaFB => '\u{1F3C8}',
        SportType.nba || SportType.ncaaMB => '\u{1F3C0}',
        SportType.mlb => '\u{26BE}',
        SportType.nhl => '\u{1F3D2}',
        SportType.mls || SportType.fifa || SportType.championsLeague =>
          '\u{26BD}',
      };
}
