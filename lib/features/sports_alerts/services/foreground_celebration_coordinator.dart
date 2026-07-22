// lib/features/sports_alerts/services/foreground_celebration_coordinator.dart
//
// FOREGROUND score celebrations (next release; NOT 2.5.1). App-open by design.
//
// Per-score celebrations have never worked in a shipped build: the only
// ScoreMonitorService + celebration wiring lived in the (now-disabled) sports
// background service, and its light-targeting (updateControllerIps) was never
// called. This coordinator rebuilds celebrations on TOP of what's alive — the
// foreground Game Day phase machine — with NO background service, NO FGS, NO
// manifest change (kSportsBackgroundServiceEnabled stays false).
//
// What it reuses vs replaces (Phase A):
//   • REUSE the diff engine: [ScoreMonitorService] baselines silently on first
//     poll (previous==null → cache only, no emit), diffs deltas per sport,
//     dedups, and emits [ScoreAlertEvent]s on alertStream. Untouched.
//   • REUSE the celebration DESIGN: AlertTriggerService.buildAnimationSteps +
//     animationDuration — the team-color flash sequences and their timing.
//   • REPLACE the delivery: the old direct-IP WledService('http://$ip') loop
//     (LAN-only, inert) is gone. Delivery now goes through the modern apply
//     chokepoint (wledRepositoryProvider) via [CelebrationDelivery] — LAN AND
//     relay, multi-bus correct. See WledCelebrationDelivery.
//
// Lifecycle: polling runs ONLY while ≥1 tracked team is in the liveGame phase
// AND the app is foregrounded. No polling pre/post game, or in the background.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/team_colors.dart';
import '../models/score_alert_config.dart';
import '../models/score_alert_event.dart';
import '../models/sport_type.dart';
import 'alert_trigger_service.dart' show AlertAnimationStep, AlertTriggerService;
import 'score_monitor_service.dart';

// ── Tunable constants ──────────────────────────────────────────────────────

/// ESPN poll cadence during a live game. 30s (not the phase machine's 60s):
/// a score flash that lands ~a minute late feels broken, whereas 30s keeps the
/// flash within roughly a possession of the real score. Cost is bounded — it
/// only runs while a game is live AND the app is open, one scoreboard fetch per
/// sport per cycle (ScoreMonitorService groups by sport), so a single live NFL
/// game is ~2 requests/min. No polling otherwise.
const Duration kCelebrationPollInterval = Duration(seconds: 30);

/// Minimum quiet gap between consecutive celebrations so a burst of scores (or
/// two tracked games scoring together) can't stack/strobe the lights.
const Duration kCelebrationMinGap = Duration(seconds: 2);

/// A team currently in the liveGame phase with score celebrations enabled.
/// Built from the Game Day phase machine ∩ GameDayAutopilotConfig — see
/// liveCelebrationTeamsProvider.
@immutable
class CelebrationTeam {
  final String teamSlug;
  final SportType sport;
  final AlertSensitivity sensitivity;

  const CelebrationTeam({
    required this.teamSlug,
    required this.sport,
    this.sensitivity = AlertSensitivity.majorOnly,
  });

  /// Adapt to the diff engine's config shape (reuses ScoreMonitorService as-is).
  ScoreAlertConfig toAlertConfig() => ScoreAlertConfig(
        id: 'gameday-$teamSlug',
        teamSlug: teamSlug,
        sport: sport,
        isEnabled: true,
        sensitivity: sensitivity,
      );

  @override
  bool operator ==(Object other) =>
      other is CelebrationTeam &&
      teamSlug == other.teamSlug &&
      sport == other.sport &&
      sensitivity == other.sensitivity;

  @override
  int get hashCode => Object.hash(teamSlug, sport, sensitivity);
}

/// The delivery seam — capture current lights, play the flash, revert. Injected
/// so the coordinator is testable without a device, and so the real impl can
/// route through wledRepositoryProvider (LAN + relay). NEVER the direct-IP
/// AlertTriggerService path.
abstract class CelebrationDelivery {
  /// Snapshot the current controller state to restore after the flash. Null =
  /// couldn't read (skip the revert rather than guess).
  Future<Map<String, dynamic>?> capture();

  /// Play the ordered animation steps on the lights (channel-filtered).
  Future<void> play(List<AlertAnimationStep> steps);

  /// Restore the captured state. If the phase machine had a team design active,
  /// this lands back on it seamlessly (it's whatever was captured).
  Future<void> revert(Map<String, dynamic> captured);
}

/// Coordinates foreground score monitoring + serialized celebration playback.
/// Owns NO device/Riverpod knowledge — the driver provider feeds it live teams
/// and the foreground signal; the delivery seam does the device work.
class ForegroundCelebrationCoordinator {
  ForegroundCelebrationCoordinator({
    required ScoreMonitor monitor,
    required CelebrationDelivery delivery,
    Duration pollInterval = kCelebrationPollInterval,
    Duration minGap = kCelebrationMinGap,
  })  : _monitor = monitor,
        _delivery = delivery,
        _pollInterval = pollInterval,
        _minGap = minGap;

  final ScoreMonitor _monitor;
  final CelebrationDelivery _delivery;
  final Duration _pollInterval;
  final Duration _minGap;

  List<CelebrationTeam> _liveTeams = const [];
  bool _foreground = true;
  bool _disposed = false;

  Timer? _pollTimer;
  StreamSubscription<ScoreAlertEvent>? _alertSub;

  bool _celebrating = false;
  ScoreAlertEvent? _queued; // coalesce buffer — at most ONE pending

  @visibleForTesting
  bool get isCelebrating => _celebrating;

  @visibleForTesting
  bool get isPolling => _pollTimer != null;

  // ── Inputs from the driver ───────────────────────────────────────────────

  /// The set of teams currently in liveGame with celebrations enabled. Empty
  /// (no live game, or toggle off for every team) → polling stops.
  void syncLiveTeams(List<CelebrationTeam> teams) {
    if (_disposed) return;
    _liveTeams = List.unmodifiable(teams);
    _reconcile();
  }

  /// App foreground/background. Celebrations are app-open-only by design — the
  /// dealer statement stays honest. Background pauses polling; no work off-screen.
  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    _reconcile();
  }

  void _reconcile() {
    final shouldRun = _foreground && _liveTeams.isNotEmpty;
    if (shouldRun) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  // ── Polling ──────────────────────────────────────────────────────────────

  void _startPolling() {
    if (_pollTimer != null) return;
    _alertSub ??= _monitor.alertStream.listen(handleAlert);
    // First poll baselines silently (ScoreMonitorService caches with no emit on
    // previous==null) — no celebration on app-open mid-game, no missed-score
    // replay. Only subsequent NEW deltas celebrate.
    unawaited(_pollOnce());
    _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(_pollOnce()));
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    // Keep the alert subscription and the ScoreMonitorService cache intact so a
    // brief background→foreground bounce re-baselines cleanly on the next start
    // rather than replaying. The cache is cleared on dispose / logout.
  }

  Future<void> _pollOnce() async {
    if (_disposed || _liveTeams.isEmpty) return;
    try {
      await _monitor.checkScores(
        _liveTeams.map((t) => t.toAlertConfig()).toList(),
      );
    } catch (e) {
      debugPrint('[Celebration] poll failed: $e');
    }
  }

  // ── Celebration playback (serialized + coalesced) ────────────────────────

  /// Handle one detected score. Serializes: if a celebration is already
  /// playing, the incoming score is COALESCED into a single pending slot
  /// (never stacked) so a burst can't strobe. Public for tests.
  @visibleForTesting
  void handleAlert(ScoreAlertEvent event) {
    if (_disposed) return;
    if (_celebrating) {
      // Extend/queue once — the newest score wins the single pending slot.
      _queued = event;
      return;
    }
    unawaited(_runCelebration(event));
  }

  Future<void> _runCelebration(ScoreAlertEvent event) async {
    _celebrating = true;
    try {
      final team = kTeamColors[event.teamSlug];
      if (team == null) return;
      final steps = AlertTriggerService.buildAnimationSteps(event.eventType, team);
      if (steps.isEmpty) return;

      // Slice-2/5 prior-state discipline: capture → flash → revert.
      final captured = await _delivery.capture();
      await _delivery.play(steps);
      if (captured != null && captured.isNotEmpty) {
        await _delivery.revert(captured);
      }
    } catch (e) {
      debugPrint('[Celebration] playback failed: $e');
    } finally {
      _celebrating = false;
      final next = _queued;
      _queued = null;
      if (next != null && !_disposed) {
        // Minimum quiet gap, then play the single coalesced follow-up.
        if (_minGap > Duration.zero) await Future<void>.delayed(_minGap);
        unawaited(_runCelebration(next));
      }
    }
  }

  // ── Teardown ─────────────────────────────────────────────────────────────

  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _alertSub?.cancel();
    _alertSub = null;
    _queued = null;
    _monitor.reset();
  }
}
