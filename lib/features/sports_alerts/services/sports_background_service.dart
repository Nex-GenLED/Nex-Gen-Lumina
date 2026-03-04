import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Listen for IP updates from the UI isolate.
  service.on('updateIps').listen((data) {
    if (data != null && data['ips'] is List) {
      controllerIps = List<String>.from(data['ips'] as List);
    }
  });

  // Listen for stop signal.
  service.on('stop').listen((_) async {
    monitor.dispose();
    espnApi.dispose();
    scheduleService.dispose();
    await service.stopSelf();
  });

  // Wire monitor → trigger.
  StreamSubscription<dynamic>? alertSub;

  // ---------- Main polling loop ----------
  Timer? pollTimer;

  Future<void> poll() async {
    final configs = await _loadConfigs();
    final active = configs.where((c) => c.isEnabled).toList();
    if (active.isEmpty) {
      _updateNotification(service, 'No active alerts');
      return;
    }

    // Rebuild trigger service with latest IPs each cycle.
    final trigger = AlertTriggerService(controllerIps: controllerIps);

    // Ensure we're subscribed to the monitor stream.
    alertSub ??= monitor.alertStream.listen((event) {
      final config = active.firstWhere(
        (c) => c.teamSlug == event.teamSlug,
        orElse: () => active.first,
      );
      trigger.handleAlertEvent(event, config);
    });

    // Run the score check.
    await monitor.checkScores(active);

    // Determine best polling interval and notification text.
    final intervalInfo = await _resolvePollingInterval(
      active,
      espnApi,
      scheduleService,
    );

    _updateNotification(service, intervalInfo.notificationBody);

    // If no games are active and none start soon, stop the service.
    if (intervalInfo.shouldStop) {
      monitor.dispose();
      espnApi.dispose();
      scheduleService.dispose();
      alertSub?.cancel();
      pollTimer?.cancel();
      await service.stopSelf();
      return;
    }

    // Re-schedule next poll.
    pollTimer?.cancel();
    pollTimer = Timer(
      Duration(seconds: intervalInfo.intervalSeconds),
      poll,
    );
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

  // iOS background fetch has ~15-20s max. Do a quick score check.
  final espnApi = EspnApiService();
  final monitor = ScoreMonitorService(espnApi: espnApi);
  final configs = await _loadConfigs();
  final active = configs.where((c) => c.isEnabled).toList();

  if (active.isEmpty) {
    espnApi.dispose();
    monitor.dispose();
    return true;
  }

  // Quick check — emit events via local notifications only.
  final trigger = AlertTriggerService(controllerIps: const []);
  monitor.alertStream.listen((event) {
    final config = active.firstWhere(
      (c) => c.teamSlug == event.teamSlug,
      orElse: () => active.first,
    );
    trigger.handleAlertEvent(event, config);
  });

  await monitor.checkScores(active);

  espnApi.dispose();
  monitor.dispose();
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
        if (game.isClutchTime) {
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
