// lib/features/wled/pattern_adjustment_pacer.dart
//
// WHEN a live control's value goes to the lights (+110 E1 follow-up 4).
//
// WHY. Away from home every write is a relay command: the app writes it to
// Firestore, the bridge on the home network picks it up and replays it — about
// 1.5 s a command at best, 5–7 s when the bridge is mid-heartbeat. The sliders
// sent one write after every 200 ms pause in a drag, so a two-second drag
// queued several commands that landed one after another long after the
// finger lifted, and a refused one snapped the slider back just as late.
//
// THE RULE.
//   • At home: a short trailing debounce ([localDelay]), so the lights follow
//     a drag.
//   • Away: nothing is sent while a drag is in progress. ONE write goes when
//     it settles — the finger lifts ([settled], from `Slider.onChangeEnd`), or,
//     for a control that cannot say so (a colour wheel), after [remoteIdle]
//     with no change.
//   • Either way at most ONE write is in flight. A change that arrives while
//     one is outstanding is folded into the next write, never queued behind
//     it.
//   • A discrete tap (a chip, a menu choice) is not a drag: it goes after
//     [localDelay], at home or away.
//
// The pacer only decides WHEN. The caller keeps what is pending and sends it
// from [flush] — reading its latest values, so whatever was folded in goes.
//
// Pure Dart (dart:async only).

import 'dart:async';

class AdjustmentPacer {
  AdjustmentPacer({
    required this.flush,
    required this.isRemote,
    this.localDelay = const Duration(milliseconds: 200),
    this.remoteIdle = const Duration(milliseconds: 1500),
  });

  /// Sends whatever the caller has pending. Never called while a previous
  /// call is still running.
  final Future<void> Function() flush;

  /// True away from home (the relay path).
  final bool Function() isRemote;

  final Duration localDelay;
  final Duration remoteIdle;

  Timer? _timer;
  bool _pending = false;
  bool _inFlight = false;
  bool _disposed = false;

  /// True while a write is out.
  bool get inFlight => _inFlight;

  /// True while a change is waiting to be sent.
  bool get hasPending => _pending;

  /// The value changed. [dragging]: a step of a drag (false for a discrete
  /// tap).
  void changed({bool dragging = true}) {
    if (_disposed) return;
    _pending = true;
    _timer?.cancel();
    final wait = dragging && isRemote() ? remoteIdle : localDelay;
    _timer = Timer(wait, _go);
  }

  /// The drag ended: send what is pending now.
  void settled() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _go();
  }

  Future<void> _go() async {
    if (_disposed || !_pending) return;
    // A write is out: this change rides on the next one (see below).
    if (_inFlight) return;
    _pending = false;
    _inFlight = true;
    try {
      await flush();
    } finally {
      _inFlight = false;
    }
    // More arrived while that write was out. If its own wait (debounce, or
    // the away-from-home settle) is still running, that timer sends it;
    // otherwise the wait already passed during the write — send it now.
    if (!_disposed && _pending && !(_timer?.isActive ?? false)) {
      unawaited(_go());
    }
  }

  /// Stops the timer. A write already out is left to finish; nothing pending
  /// is sent.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
