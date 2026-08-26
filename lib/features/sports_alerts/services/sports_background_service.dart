import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../autopilot/game_day_autopilot_background_worker.dart';
import '../../autopilot/game_day_background_persistence.dart';
import '../../autopilot/unified_monitoring.dart';
import '../../neighborhood/services/sync_event_background_persistence.dart';
import '../../neighborhood/services/sync_event_background_worker.dart';
import '../data/team_colors.dart';
import '../models/game_state.dart';
import '../models/score_alert_config.dart';
import '../models/sport_type.dart';
import 'alert_trigger_service.dart';
import 'espn_api_service.dart';
import 'game_schedule_service.dart';
import 'score_monitor_service.dart';

// ---------------------------------------------------------------------------
// Kill-switch: the Android foreground service (dataSync FGS) is DISABLED for
// the current Play release so the app declares no typed foreground-service
// permission (no Play FGS declaration / demo-video requirement). The
// background sports/sync watch was already inert in practice (updateControllerIps
// never wired up), so this removes no working user behavior. Foreground
// controls (test-fire, in-app sports UI) are unaffected. Flip back to true —
// and restore FOREGROUND_SERVICE_DATA_SYNC + the BackgroundService <service> in
// AndroidManifest.xml, then complete the Play FGS declaration — to re-enable.
const bool kSportsBackgroundServiceEnabled = false;

// ---------------------------------------------------------------------------
// SharedPreferences key for persisted alert configs
// ---------------------------------------------------------------------------
const _kConfigsKey = 'sports_alert_configs';

// ---------------------------------------------------------------------------
// Android notification channel / foreground service IDs
// ---------------------------------------------------------------------------
const _kNotificationChannelId = 'lumina_sports_alerts';
const _kForegroundNotificationId = 887733;

/// Configure and initialise the background service.
///
/// Call this once from `main()` or from the sports-alerts setup flow.
/// The service will auto-start only when explicitly told via
/// [startSportsService].
Future<void> initialiseSportsBackgroundService() async {
  if (!kSportsBackgroundServiceEnabled) return;
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      initialNotificationTitle: 'Lumina Sports Watch',
      initialNotificationContent: 'Starting up...',
      notificationChannelId: _kNotificationChannelId,
      foregroundServiceNotificationId: _kForegroundNotificationId,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: _onStart,
      onBackground: _onIosBackground,
    ),
  );
}

/// Start the background polling service.
Future<void> startSportsService() async {
  if (!kSportsBackgroundServiceEnabled) return;
  final service = FlutterBackgroundService();
  final running = await service.isRunning();
  if (!running) {
    await service.startService();
  }
}

/// Stop the background polling service.
Future<void> stopSportsService() async {
  final service = FlutterBackgroundService();
  service.invoke('stop');
}

/// Send updated controller IPs to the running service.
void updateControllerIps(List<String> ips) {
  FlutterBackgroundService().invoke('updateIps', {'ips': ips});
}

/// Notify the running background service that sync event configs changed.
/// The service will reload from SharedPreferences on its next poll cycle.
void notifySyncEventsChanged() {
  FlutterBackgroundService().invoke('syncEventsChanged');
}

/// Start the background service specifically for sync event monitoring.
/// Reuses the same service — just ensures it's running.
Future<void> startSyncEventService() async {
  await startSportsService();
}

// ---------------------------------------------------------------------------
// Android foreground / iOS foreground entry point
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  final espnApi = EspnApiService();
  final monitor = ScoreMonitorService(espnApi: espnApi);
  final scheduleService = GameScheduleService();
  List<String> controllerIps = [];

  // ── Sync Event Background Worker ───────────────────────────────────
  final syncEspnApi = EspnApiService();
  final syncWorker = SyncEventBackgroundWorker(service, syncEspnApi);
  syncWorker.startMonitoring();

  // ── Game Day Autopilot Background Worker ──────────────────────────
  final gameDayEspnApi = EspnApiService();
  final gameDayScheduleService = GameScheduleService();
  final gameDayWorker = GameDayAutopilotBackgroundWorker(
    espnApi: gameDayEspnApi,
    scheduleService: gameDayScheduleService,
  );
  await gameDayWorker.startMonitoring();

  // Listen for IP updates from the UI isolate. The local controllerIps
  // list feeds AlertTriggerService below (direct-IP sports alerts).
  final updateIpsSub = service.on('updateIps').listen((data) {
    if (data != null && data['ips'] is List) {
      controllerIps = List<String>.from(data['ips'] as List);
    }
  });

  // Listen for sync events config change signal.
  final syncChangedSub = service.on('syncEventsChanged').listen((_) {
    debugPrint('[Background] Sync events changed — worker will reload on next poll');
  });

  // Wire monitor → trigger.
  StreamSubscription<dynamic>? alertSub;
  Timer? pollTimer;

  // Listen for stop signal.
  late final StreamSubscription stopSub;
  stopSub = service.on('stop').listen((_) async {
    monitor.dispose();
    espnApi.dispose();
    scheduleService.dispose();
    syncWorker.dispose();
    gameDayWorker.dispose();
    gameDayEspnApi.dispose();
    gameDayScheduleService.dispose();
    alertSub?.cancel();
    pollTimer?.cancel();
    updateIpsSub.cancel();
    syncChangedSub.cancel();
    stopSub.cancel();
    await service.stopSelf();
  });

  Future<void> poll() async {
    // UNIFIED ARMING. `active` used to be "enabled SPORTS-ALERT configs" — a
    // list the user maintained in a different screen, unrelated to the Game Day
    // teams they had selected. That was celebration blocker (1): both
    // checkScores AND the alertStream subscription sat behind
    // `if (active.isNotEmpty)`, so a user with Game Day teams but no
    // sports-alert opt-in polled nothing and could never celebrate. Monitoring
    // now derives from Game Day + Live Scoring, with legacy configs honoured
    // only until migration adopts them.
    //
    // ORPHAN SAFETY GATE. A legacy prefs config no longer arms monitoring on
    // its own: Game Day's delete path writes only to Firestore, so a deleted
    // team left a prefs entry behind that kept celebrating
    // (audit/SPORTS_ALERTS_SYNC_AUDIT.md §4.4). The profile-array mirror is
    // the Firestore corroboration this isolate can reach — it has no Firestore
    // access of its own, so it reads what the UI layer persisted via
    // `saveUserTeamPriority` (game_day_autopilot_providers.dart:297).
    final legacyConfigs = await _loadConfigs();
    final gameDayConfigs = await loadGameDayConfigsForBackground();
    final profileTeamNames = await loadUserTeamPriority();
    final plan = resolveMonitoring(
      gameDayConfigs: gameDayConfigs,
      legacyAlertConfigs: legacyConfigs,
      profileTeamNames: profileTeamNames,
    );
    final active = plan.monitored;

    // Check all workload sources before deciding what to do
    final syncEvents = await loadSyncEventsForBackground();
    final hasSyncEvents = syncEvents.any((e) => e.isEnabled && !e.isManual);
    final hasActiveSession = await loadActiveSession() != null;
    final hasGameDayWork = await gameDayWorker.hasActiveWorkload();
    // An active Game Day session arms scoring on its own — this is what makes a
    // mid-game "Light It Up Now" tap start monitoring from that second.
    final hasActiveGameDaySession = gameDayWorker.hasActiveSession;

    if (active.isEmpty && !hasSyncEvents && !hasActiveSession && !hasGameDayWork) {
      _updateNotification(service, 'No active alerts');
      return;
    }

    // ── Game Day Autopilot evaluation ─────────────────────────────
    try {
      await gameDayWorker.evaluate();
    } catch (e) {
      debugPrint('[SportsBackground] Game Day evaluate failed: $e');
    }

    // ── Score polling ──────────────────────────────────────────────
    // Gate is the unified predicate: anything monitored, OR any active Game Day
    // session. The session limb is the mid-game-join case — there may be no
    // enabled config at all for an ephemeral "Light It Up Now" team.
    if (shouldPollScores(
      plan: plan,
      hasActiveGameDaySession: hasActiveGameDaySession,
    )) {
      // Rebuild trigger service with latest IPs each cycle.
      final trigger = AlertTriggerService(controllerIps: controllerIps);

      // Ensure we're subscribed to the monitor stream.
      alertSub ??= monitor.alertStream.listen((event) {
        // orElse must not fabricate a mismatched config: with an ephemeral
        // session there can be an event for a team with no entry in `active`,
        // and the old `active.first` fallback would have applied ANOTHER
        // team's sensitivity and zones to it.
        final config = active.where((c) => c.teamSlug == event.teamSlug).firstOrNull;
        if (config != null) {
          trigger.handleAlertEvent(event, config);
        }

        // The workers are notified REGARDLESS of whether a monitoring config
        // matched: an ephemeral session's team legitimately has no config, and
        // its celebration is exactly the case this whole change exists to fix.

        // Notify sync worker for group-level celebration broadcasts.
        syncWorker.onScoreAlertEvent(event);

        // Notify game day worker for personal celebration flashes.
        gameDayWorker.onScoreAlertEvent(event);
      });

      // Run the score check.
      await monitor.checkScores(active);
    }

    // ── Determine polling interval ─────────────────────────────────
    if (active.isNotEmpty) {
      final intervalInfo = await _resolvePollingInterval(
        active,
        espnApi,
        scheduleService,
      );

      _updateNotification(service, intervalInfo.notificationBody);

      // Only auto-stop if no sync events, no active session, and no Game Day
      if (intervalInfo.shouldStop &&
          !hasSyncEvents &&
          !hasActiveSession &&
          !hasGameDayWork) {
        monitor.dispose();
        espnApi.dispose();
        scheduleService.dispose();
        syncWorker.dispose();
        gameDayWorker.dispose();
        gameDayEspnApi.dispose();
        gameDayScheduleService.dispose();
        alertSub?.cancel();
        pollTimer?.cancel();
        await service.stopSelf();
        return;
      }

      // Re-schedule next poll at the sports alert interval
      // (sync worker manages its own internal timers)
      pollTimer?.cancel();
      pollTimer = Timer(
        Duration(seconds: intervalInfo.intervalSeconds),
        poll,
      );
    } else {
      // No sports alerts — poll at sync event cadence
      final activeSession = await loadActiveSession();
      final interval = activeSession != null
          ? const Duration(seconds: 30) // Active session — frequent polls
          : const Duration(minutes: 5); // Waiting for trigger

      if (hasActiveSession) {
        _updateNotification(service, 'Neighborhood Sync Active');
      } else if (hasSyncEvents) {
        _updateNotification(service, 'Monitoring sync events');
      }

      pollTimer?.cancel();
      pollTimer = Timer(interval, poll);
    }
  }

  // Kick off the first poll immediately.
  await poll();
}

// ---------------------------------------------------------------------------
// iOS background fetch entry point
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
FutureOr<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  // iOS background fetch has ~15-20s max. Do quick checks for both
  // sports alerts AND sync events.

  // ── Sports alerts quick check ────────────────────────────────────
  final espnApi = EspnApiService();
  final monitor = ScoreMonitorService(espnApi: espnApi);
  final configs = await _loadConfigs();
  final active = configs.where((c) => c.isEnabled).toList();

  if (active.isNotEmpty) {
    final trigger = AlertTriggerService(controllerIps: const []);
    final alertSub = monitor.alertStream.listen((event) {
      final config = active.firstWhere(
        (c) => c.teamSlug == event.teamSlug,
        orElse: () => active.first,
      );
      trigger.handleAlertEvent(event, config);
    });

    await monitor.checkScores(active);
    await alertSub.cancel();
  }

  espnApi.dispose();
  monitor.dispose();

  // ── Sync events quick check ──────────────────────────────────────
  // Must complete within the remaining iOS background execution window.
  await performQuickSyncCheck();

  return true;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Load persisted [ScoreAlertConfig] list from SharedPreferences.
///
/// PUBLIC FOR MIGRATION ONLY. The retired Sports Alerts store is read exactly
/// once more, by [SportsAlertsLazyMigrator], to adopt its contents into Game
/// Day; nothing else should read it (audit/SPORTS_ALERTS_SYNC_AUDIT.md §4.2).
Future<List<ScoreAlertConfig>> loadAlertConfigs() => _loadConfigs();

/// Empty the retired store. Called by the migrator once its contents are safely
/// in Firestore, so a later launch cannot resurrect an already-adopted team.
Future<void> clearAlertConfigs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kConfigsKey);
}

/// Load persisted [ScoreAlertConfig] list from SharedPreferences.
Future<List<ScoreAlertConfig>> _loadConfigs() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kConfigsKey);
    if (raw == null || raw.isEmpty) return const [];
    return raw.map((jsonStr) {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return ScoreAlertConfig.fromJson(map);
    }).toList();
  } catch (e) {
    debugPrint('[SportsBackground] Error loading configs: $e');
    return const [];
  }
}

// NOTE: there is deliberately no `saveAlertConfigs` any more. The retired
// prefs store is now READ-ONLY, and read by exactly two callers: the migrator,
// which drains it into Game Day, and the poll loop below, whose remaining
// legacy entries are gated by resolveMonitoring's orphan safety check. Nothing
// writes it — every add now goes to the `game_day_autopilot` doc, which is what
// keeps the two surfaces from drifting apart again.

/// Determine the optimal polling interval based on current game states.
Future<_PollingInterval> _resolvePollingInterval(
  List<ScoreAlertConfig> configs,
  EspnApiService espnApi,
  GameScheduleService scheduleService,
) async {
  var minInterval = 300; // Default 5 min.
  var anyInProgress = false;
  var anyClutch = false;
  String teamWatching = '';

  for (final config in configs) {
    final teamInfo = kTeamColors[config.teamSlug];
    if (teamInfo == null) continue;

    final game = await espnApi.fetchTeamGame(
      config.sport,
      teamInfo.espnTeamId,
    );

    if (game == null) continue;

    if (teamWatching.isEmpty) teamWatching = teamInfo.teamName;

    switch (game.status) {
      case GameStatus.inProgress:
      case GameStatus.halftime:
        anyInProgress = true;
        final sportInterval = config.sport.pollingIntervalSeconds;
        final isClutch = game.isClutchTime ||
            (config.sport == SportType.ncaaMB &&
                game.isCollegeBasketballClutchTime);
        if (isClutch) {
          anyClutch = true;
          final clutch = config.sport.clutchPollingIntervalSeconds;
          if (clutch < minInterval) minInterval = clutch;
        } else {
          if (sportInterval < minInterval) minInterval = sportInterval;
        }

      case GameStatus.scheduled:
        // Check if game starts within 30 min.
        final hasSoon = await scheduleService.hasGameSoon(
          teamInfo.espnTeamId,
          config.sport,
        );
        if (hasSoon && 300 < minInterval) minInterval = 300;

      case GameStatus.final_:
      case GameStatus.unknown:
        // Game over or transient unknown state (postponed/cancelled/etc.) —
        // no interval needed for this one.
        break;
    }
  }

  if (!anyInProgress) {
    // No in-progress games. Check if any scheduled soon.
    // If not, signal to stop.
    return _PollingInterval(
      intervalSeconds: 300,
      shouldStop: true,
      notificationBody: 'No live games',
    );
  }

  final body = anyClutch
      ? 'CLUTCH TIME — Watching $teamWatching'
      : 'Watching $teamWatching game...';

  return _PollingInterval(
    intervalSeconds: minInterval,
    shouldStop: false,
    notificationBody: body,
  );
}

class _PollingInterval {
  final int intervalSeconds;
  final bool shouldStop;
  final String notificationBody;

  const _PollingInterval({
    required this.intervalSeconds,
    required this.shouldStop,
    required this.notificationBody,
  });
}

void _updateNotification(ServiceInstance service, String content) {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'Lumina Sports Watch',
      content: content,
    );
  }
}
