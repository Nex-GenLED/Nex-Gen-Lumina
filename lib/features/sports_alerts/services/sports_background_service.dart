import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Listen for IP updates from the UI isolate.
  final updateIpsSub = service.on('updateIps').listen((data) {
    if (data != null && data['ips'] is List) {
      controllerIps = List<String>.from(data['ips'] as List);
      syncWorker.updateControllerIps(controllerIps);
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
    alertSub?.cancel();
    pollTimer?.cancel();
    updateIpsSub.cancel();
    syncChangedSub.cancel();
    stopSub.cancel();
    await service.stopSelf();
  });

  Future<void> poll() async {
    final configs = await _loadConfigs();
    final active = configs.where((c) => c.isEnabled).toList();

    // Check if sync events are active (even if no sports alerts)
    final syncEvents = await loadSyncEventsForBackground();
    final hasSyncEvents = syncEvents.any((e) => e.isEnabled && !e.isManual);
    final hasActiveSession = await loadActiveSession() != null;

    if (active.isEmpty && !hasSyncEvents && !hasActiveSession) {
      _updateNotification(service, 'No active alerts');
      return;
    }

    // ── Sports alerts polling ──────────────────────────────────────
    if (active.isNotEmpty) {
      // Rebuild trigger service with latest IPs each cycle.
      final trigger = AlertTriggerService(controllerIps: controllerIps);

      // Ensure we're subscribed to the monitor stream.
      alertSub ??= monitor.alertStream.listen((event) {
        final config = active.firstWhere(
          (c) => c.teamSlug == event.teamSlug,
          orElse: () => active.first,
        );
        trigger.handleAlertEvent(event, config);

        // Also notify the sync worker so Neighborhood Sync Game Day
        // sessions can broadcast the celebration to all participants.
        syncWorker.onScoreAlertEvent(event);
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

      // Only auto-stop if no sync events are being monitored either
      if (intervalInfo.shouldStop && !hasSyncEvents && !hasActiveSession) {
        monitor.dispose();
        espnApi.dispose();
        scheduleService.dispose();
        syncWorker.dispose();
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

/// Save configs to SharedPreferences (called from UI layer).
Future<void> saveAlertConfigs(List<ScoreAlertConfig> configs) async {
  final prefs = await SharedPreferences.getInstance();
  final encoded = configs.map((c) => jsonEncode(c.toJson())).toList();
  await prefs.setStringList(_kConfigsKey, encoded);
}

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
        // Game over — no interval needed for this one.
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
