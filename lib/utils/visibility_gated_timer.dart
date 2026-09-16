import 'dart:async';

import 'package:flutter/widgets.dart';

/// #112 — a periodic callback that runs ONLY while its screen is really on
/// screen.
///
/// Three conditions, all required:
///  - the app is resumed (not backgrounded or hidden);
///  - the widget's tab is active — `StatefulShellRoute` (go_router) wraps every
///    inactive branch in `TickerMode(enabled: false)`, and the Navigator does
///    the same for routes hidden under an opaque route;
///  - the widget's route is the top route.
///
/// WHY: a `Timer.periodic` started in `initState` and cancelled only in
/// `dispose` keeps firing while the screen sits behind another tab, because
/// the shell keeps inactive branches mounted. Over the relay every tick is a
/// real bridge command (2026-09-15 live test: the Remote Access screen kept
/// writing a `getInfo` every 30 s from behind the Home tab).
///
/// What [onTick] does is not this class's concern — only whether and how often
/// it is called.
///
/// Usage from a `State`:
///  - `didChangeDependencies` → [updateFromContext] (both `TickerMode.of` and
///    `ModalRoute.of` register dependencies, so a tab switch or a pushed route
///    re-runs it);
///  - `didChangeAppLifecycleState` → [setAppLifecycleState];
///  - [setWanted] when the feature is switched on or off;
///  - `dispose` → [dispose].
class VisibilityGatedTimer {
  VisibilityGatedTimer({required this.period, required this.onTick});

  final Duration period;
  final VoidCallback onTick;

  Timer? _timer;
  bool _wanted = false;
  bool _appResumed = true;
  bool _tickerEnabled = true;
  bool _routeIsCurrent = true;
  bool _disposed = false;

  /// Pure decision, exposed for tests.
  static bool shouldRun({
    required bool wanted,
    required bool appResumed,
    required bool tickerEnabled,
    required bool routeIsCurrent,
  }) =>
      wanted && appResumed && tickerEnabled && routeIsCurrent;

  bool get isRunning => _timer != null;

  /// True when the screen is on screen right now, regardless of [setWanted].
  /// Callers use it to decide whether a one-shot action (e.g. a check on app
  /// resume) should run at all.
  bool get isVisible => _appResumed && _tickerEnabled && _routeIsCurrent;

  void setWanted(bool wanted) {
    _wanted = wanted;
    _sync();
  }

  void setAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _sync();
  }

  void updateFromContext(BuildContext context) {
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    _sync();
  }

  void _sync() {
    if (_disposed) return;
    final run = shouldRun(
      wanted: _wanted,
      appResumed: _appResumed,
      tickerEnabled: _tickerEnabled,
      routeIsCurrent: _routeIsCurrent,
    );
    if (run && _timer == null) {
      _timer = Timer.periodic(period, (_) => onTick());
    } else if (!run && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
