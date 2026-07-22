// lib/utils/async_lock.dart
//
// Minimal hand-rolled async mutex. Pulled in deliberately instead of
// the `synchronized` package per Item #61 Workstream B Prompt 5
// dep-surface decision.
//
// API mirrors `synchronized`'s synchronized() signature so a future
// migration is a one-line import swap if features beyond plain
// mutual exclusion are ever needed (timeouts, multi-key locking,
// fairness).

import 'dart:async';

/// Minimal async mutex. Calls to [synchronized] execute in FIFO
/// order; each call waits for the previous one to complete before
/// its body runs.
///
/// Hand-rolled to avoid the `synchronized` package dependency. If
/// features beyond plain mutual exclusion are ever needed (timeouts,
/// multi-key locking, fairness), migrate to that package then.
///
/// Usage:
/// ```dart
/// final lock = AsyncLock();
/// await lock.synchronized(() async {
///   // critical section
/// });
/// ```
///
/// Exceptions thrown inside the body propagate to the caller. The
/// lock is always released even on exception so a failing critical
/// section does not deadlock subsequent waiters.
class AsyncLock {
  /// Tail of the FIFO chain. Each [synchronized] call appends a new
  /// completer's future here and awaits the previous tail before
  /// running its body.
  Future<void> _last = Future<void>.value();

  /// Run [action] exclusively. Returns the action's return value.
  /// Subsequent callers wait until this one completes (success or
  /// exception).
  Future<T> synchronized<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _last;
    _last = completer.future;

    return previous.then<T>((_) async {
      try {
        return await action();
      } finally {
        // Always release — exception in [action] must not deadlock
        // subsequent waiters. Exception still propagates to this
        // caller via the surrounding async function.
        completer.complete();
      }
    });
  }
}
