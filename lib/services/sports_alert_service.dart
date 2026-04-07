import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';

/// Top-10 team primary colors as 4-channel `[R, G, B, W]` arrays.
///
/// W is explicitly 0 — without it, WLED auto-extracts W = min(R,G,B) from any
/// 3-channel input, which lights the dedicated white LED and washes dark
/// branded reds (e.g. Chiefs `[227, 24, 55]`) into pink on RGBW strips.
const kTeamPrimaryColors = <String, List<int>>{
  'Chiefs':   [227,  24,  55, 0],
  'Royals':   [  0,  70, 135, 0],
  'Eagles':   [  0,  76,  84, 0],
  'Cowboys':  [  0,  34,  68, 0],
  'Packers':  [ 24,  72,  23, 0],
  'Lakers':   [ 85,  37, 130, 0],
  'Yankees':  [  0,  48, 135, 0],
  'Dodgers':  [  0,  90, 156, 0],
  'Warriors': [ 29,  66, 138, 0],
  '49ers':    [170,   0,   0, 0],
};

/// Manages game-day WLED automations: pre-game lighting, game-time palette,
/// score celebrations, and post-game revert.
///
/// Uses [AutopilotScheduleItem] entries as the source of truth for game times.
/// Live score API integration is a follow-up task — this service gets timing
/// and WLED automation working first.
class SportsAlertService {
  final Ref _ref;

  /// Active timers keyed by team name.
  final Map<String, List<Timer>> _activeTimers = {};

  /// Stored base payload to revert to after game ends.
  Map<String, dynamic>? _basePayload;

  SportsAlertService({required Ref ref}) : _ref = ref;

  // ---------------------------------------------------------------------------
  // Game-day monitoring
  // ---------------------------------------------------------------------------

  /// Schedule pre-game and game-time lighting for a team.
  ///
  /// - At [kickoffUtc] minus 2 hours: activates pre-game team colorloop.
  /// - At [kickoffUtc]: switches to game-time breathe effect.
  Future<void> startGameDayMonitoring({
    required String teamName,
    required DateTime kickoffUtc,
  }) async {
    try {
      // Cancel any existing timers for this team
      stopGameDayMonitoring(teamName: teamName);

      final now = DateTime.now().toUtc();
      final timers = <Timer>[];

      // Capture current state as baseline for revert
      await _captureBasePayload();

      // Pre-game: 2 hours before kickoff
      final preGameTime = kickoffUtc.subtract(const Duration(hours: 2));
      final preGameDelay = preGameTime.difference(now);
      if (preGameDelay.isNegative && kickoffUtc.isAfter(now)) {
        // We're already within the pre-game window — fire immediately
        await _applyPreGameLighting(teamName);
      } else if (!preGameDelay.isNegative) {
        timers.add(Timer(preGameDelay, () => _applyPreGameLighting(teamName)));
      }

      // Game-time: at kickoff
      final gameDelay = kickoffUtc.difference(now);
      if (!gameDelay.isNegative) {
        timers.add(Timer(gameDelay, () => _applyGameTimeLighting(teamName)));
      } else {
        // Kickoff already passed — apply game-time immediately
        await _applyGameTimeLighting(teamName);
      }

      _activeTimers[teamName] = timers;

      debugPrint(
        'SportsAlertService: Monitoring started for $teamName '
        '(kickoff: $kickoffUtc)',
      );
    } catch (e) {
      debugPrint('SportsAlertService: startGameDayMonitoring failed: $e');
    }
  }

  /// Cancel monitoring for a specific team and revert to base lighting.
  void stopGameDayMonitoring({required String teamName}) {
    try {
      final timers = _activeTimers.remove(teamName);
      if (timers != null) {
        for (final t in timers) {
          t.cancel();
        }
      }

      // Revert to base if no other games are being monitored
      if (_activeTimers.isEmpty) {
        _revertToBase();
      }

      debugPrint('SportsAlertService: Monitoring stopped for $teamName');
    } catch (e) {
      debugPrint('SportsAlertService: stopGameDayMonitoring failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Score celebrations
  // ---------------------------------------------------------------------------

  /// Fire a 15-second celebration burst, then revert to game-time palette.
  ///
  /// [eventType]: 'touchdown' | 'goal' | 'homeRun' | 'basket'
  Future<void> triggerScoreCelebration({
    required String teamName,
    required String eventType,
  }) async {
    try {
      // Guard: only fire if user has celebrations enabled
      final celebrationsEnabled = _ref.read(scoreCelebrationsProvider);
      if (!celebrationsEnabled) {
        debugPrint(
          'SportsAlertService: Score celebrations disabled, skipping',
        );
        return;
      }

      debugPrint('🎆 Score celebration: $teamName - $eventType');

      final colors = _teamColorsForPayload(teamName);

      // Fireworks burst (fx:88) at full brightness
      final celebrationPayload = <String, dynamic>{
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': 88, // Fireworks
            'sx': 200, // Fast speed
            'ix': 230, // High intensity
            'pal': 0,
            'col': colors,
          }
        ],
      };

      final repo = _ref.read(wledRepositoryProvider);
      if (repo == null) return;

      await repo.applyJson(celebrationPayload);

      // After 15 seconds, revert to game-time palette
      Timer(const Duration(seconds: 15), () {
        _applyGameTimeLighting(teamName);
      });
    } catch (e) {
      debugPrint('SportsAlertService: triggerScoreCelebration failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Startup integration
  // ---------------------------------------------------------------------------

  /// Check today's schedule for game-day items and auto-start monitoring.
  ///
  /// Called from [BackgroundLearningService.onAppStartup].
  Future<void> checkAndStartTodayGames(
    List<AutopilotScheduleItem> schedule,
  ) async {
    try {
      final now = DateTime.now();
      final todayGames = schedule.where((item) {
        if (item.trigger != AutopilotTrigger.gameDay) return false;
        final t = item.scheduledTime;
        return t.year == now.year &&
            t.month == now.month &&
            t.day == now.day;
      }).toList();

      if (todayGames.isEmpty) return;

      debugPrint(
        'SportsAlertService: Found ${todayGames.length} game(s) today',
      );

      for (final item in todayGames) {
        // Extract team name from eventName or reason field
        final teamName = item.eventName ??
            _extractTeamFromReason(item.reason) ??
            item.patternName;

        await startGameDayMonitoring(
          teamName: teamName,
          kickoffUtc: item.scheduledTime.toUtc(),
        );
      }
    } catch (e) {
      debugPrint('SportsAlertService: checkAndStartTodayGames failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _captureBasePayload() async {
    try {
      final repo = _ref.read(wledRepositoryProvider);
      if (repo == null) return;
      _basePayload = await repo.getState();
    } catch (e) {
      debugPrint('SportsAlertService: Failed to capture base state: $e');
    }
  }

  Future<void> _revertToBase() async {
    try {
      if (_basePayload == null || _basePayload!.isEmpty) return;
      final repo = _ref.read(wledRepositoryProvider);
      if (repo == null) return;
      await repo.applyJson(_basePayload!);
      debugPrint('SportsAlertService: Reverted to base lighting');
    } catch (e) {
      debugPrint('SportsAlertService: Failed to revert to base: $e');
    }
  }

  /// Apply pre-game team colorloop (fx:65) at bri:200.
  Future<void> _applyPreGameLighting(String teamName) async {
    try {
      debugPrint('SportsAlertService: Applying pre-game lighting for $teamName');

      final colors = _teamColorsForPayload(teamName);
      final payload = <String, dynamic>{
        'on': true,
        'bri': 200,
        'seg': [
          {
            'fx': 65, // Colorloop
            'sx': 128,
            'ix': 128,
            'pal': 0,
            'col': colors,
          }
        ],
      };

      final repo = _ref.read(wledRepositoryProvider);
      if (repo == null) return;
      await repo.applyJson(payload);
    } catch (e) {
      debugPrint('SportsAlertService: Pre-game lighting failed: $e');
    }
  }

  /// Apply game-time breathe effect (fx:11) at bri:255.
  Future<void> _applyGameTimeLighting(String teamName) async {
    try {
      debugPrint('SportsAlertService: Game time! Switching to breathe for $teamName');

      final colors = _teamColorsForPayload(teamName);
      final payload = <String, dynamic>{
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': 11, // Breathe
            'sx': 128,
            'ix': 200,
            'pal': 0,
            'col': colors,
          }
        ],
      };

      final repo = _ref.read(wledRepositoryProvider);
      if (repo == null) return;
      await repo.applyJson(payload);
    } catch (e) {
      debugPrint('SportsAlertService: Game-time lighting failed: $e');
    }
  }

  /// Build WLED-compatible color array from team name.
  /// Returns `[[r,g,b,0]]` with team primary color funneled through
  /// [safeRGBW] so the W channel is always explicit (W=0) and never
  /// auto-extracted by WLED — preventing the dark-red → pink bug.
  List<List<int>> _teamColorsForPayload(String teamName) {
    final rgb =
        kTeamPrimaryColors[teamName] ?? const [0, 200, 255, 0]; // Cyan fallback
    return [safeRGBW(rgb)];
  }

  /// Try to extract a team name from a reason string like "Chiefs game day".
  String? _extractTeamFromReason(String reason) {
    for (final team in kTeamPrimaryColors.keys) {
      if (reason.contains(team)) return team;
    }
    return null;
  }
}

/// Riverpod provider for the sports alert service.
final sportsAlertServiceProvider = Provider<SportsAlertService>((ref) {
  return SportsAlertService(ref: ref);
});
