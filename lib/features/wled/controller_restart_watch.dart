// lib/features/wled/controller_restart_watch.dart
//
// +122 item 2 (TD-9, defect 1 — the trigger).
//
// The connect-time healer runs once per NEW endpoint (`shouldHealOnConnect`).
// A controller that restarts on the SAME address while the app is connected is
// not a new endpoint, so its collapsed post-boot layout stayed collapsed for
// as long as the app stayed connected — and did, on the bench and in the
// field. The dashboard polls `/json/state` every 1.5 s, which carries no
// uptime; `/json/info` does.
//
// This watch reads the controller's uptime on a slow cadence (LAN only) and
// names two events, each of which re-runs the geometry heal:
//   • uptime DROP  — the uptime read is lower than the last one on the same
//     endpoint: the controller rebooted between reads (an outage in between,
//     when reads failed, keeps the baseline so the reboot behind it is still
//     seen);
//   • COLD START   — the first readable uptime on an endpoint is small: the
//     controller booted moments ago (it was off when the app connected, so the
//     connect heal stood aside on an unreachable controller, or the app came
//     up right after the controller did).
// Pure decision, injectable reads, a timer like the gamma watchdog's.

import 'dart:async';

/// How often the watch reads `/json/info` on the LAN. One small GET; the
/// dashboard's state poll is 20× more frequent.
const Duration kRestartWatchInterval = Duration(seconds: 30);
const Duration kRestartWatchMinInterval = Duration(seconds: 10);

/// An endpoint whose FIRST readable uptime is below this booted moments ago.
const int kColdStartUptimeMaxSeconds = 120;

typedef UptimeReading = ({String endpoint, int uptimeSeconds});

enum RestartKind { none, uptimeDrop, coldStart }

/// Pure: what a new reading says against the last one.
RestartKind classifyUptime({
  required String? previousEndpoint,
  required int? previousUptime,
  required UptimeReading reading,
}) {
  if (previousEndpoint != reading.endpoint || previousUptime == null) {
    return reading.uptimeSeconds < kColdStartUptimeMaxSeconds
        ? RestartKind.coldStart
        : RestartKind.none;
  }
  return reading.uptimeSeconds < previousUptime
      ? RestartKind.uptimeDrop
      : RestartKind.none;
}

class ControllerRestartWatch {
  ControllerRestartWatch({
    required Future<UptimeReading?> Function() readUptime,
    required Future<void> Function(RestartKind kind) onRestart,
    Duration interval = kRestartWatchInterval,
  })  : _readUptime = readUptime,
        _onRestart = onRestart,
        _interval = interval < kRestartWatchMinInterval
            ? kRestartWatchMinInterval
            : interval;

  final Future<UptimeReading?> Function() _readUptime;
  final Future<void> Function(RestartKind kind) _onRestart;
  final Duration _interval;

  Timer? _timer;
  bool _inFlight = false;
  String? _lastEndpoint;
  int? _lastUptime;

  Duration get interval => _interval;
  String? get lastEndpoint => _lastEndpoint;
  int? get lastUptime => _lastUptime;
  int ticks = 0;
  int restartsSeen = 0;

  void start() {
    stop();
    _timer = Timer.periodic(_interval, (_) => unawaited(tickOnce()));
  }

  /// One read. A null reading (relay, mock, unreachable) changes nothing: the
  /// baseline survives an outage so the reboot behind it is still seen.
  Future<void> tickOnce() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      ticks++;
      final reading = await _readUptime();
      if (reading == null) return;
      final kind = classifyUptime(
        previousEndpoint: _lastEndpoint,
        previousUptime: _lastUptime,
        reading: reading,
      );
      _lastEndpoint = reading.endpoint;
      _lastUptime = reading.uptimeSeconds;
      if (kind == RestartKind.none) return;
      restartsSeen++;
      await _onRestart(kind);
    } catch (_) {
      // A failed read or heal is retried on the next tick; never fatal.
    } finally {
      _inFlight = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
