import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How long the dashboard's My Favorites waits for its first Firestore
/// snapshot before it shows "Couldn't load favorites" with Retry.
///
/// A healthy listen answers from the local cache at once and from the server
/// within a few seconds even on cellular, so this only fires when the
/// Firestore client is stuck — which is exactly when a spinner used to sit
/// there forever (the 2.5.10+107 first-login hang).
const Duration kFavoritesLoadTimeout = Duration(seconds: 12);

/// The deadline in force. A provider so tests can shorten it.
final favoritesLoadTimeoutProvider =
    Provider<Duration>((ref) => kFavoritesLoadTimeout);

/// Forwards [source], but if its FIRST event (data or error) has not arrived
/// within [timeout] it emits a [TimeoutException], closes, and CANCELS the
/// subscription to [source].
///
/// Cancelling the subscription is how a Firestore listen is aborted: the
/// listener is removed from the client, so nothing keeps waiting on a query
/// nobody will read (the #111 abort discipline, applied to a stream rather
/// than an HttpClientRequest). After the first event there is no deadline —
/// a live snapshot stream is legitimately silent between changes. Cancelling
/// the returned stream (the provider being disposed) cancels [source] too.
Stream<T> firstEventWithin<T>(Stream<T> source, Duration timeout) {
  late final StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? deadline;

  // Synchronous on purpose: the deadline timer is cancelled and the source
  // cancellation is ISSUED in the same call, and the timeout is reported
  // without waiting for the native listener to finish detaching.
  Future<void> abortSource() {
    deadline?.cancel();
    deadline = null;
    final s = subscription;
    subscription = null;
    return s?.cancel() ?? Future<void>.value();
  }

  controller = StreamController<T>(
    onListen: () {
      deadline = Timer(timeout, () {
        deadline = null;
        if (controller.isClosed) return;
        controller.addError(TimeoutException(
          'No first snapshot within ${timeout.inMilliseconds} ms',
          timeout,
        ));
        unawaited(abortSource());
        unawaited(controller.close());
      });
      subscription = source.listen(
        (event) {
          deadline?.cancel();
          deadline = null;
          controller.add(event);
        },
        onError: (Object error, StackTrace stack) {
          deadline?.cancel();
          deadline = null;
          controller.addError(error, stack);
        },
        onDone: () {
          deadline?.cancel();
          deadline = null;
          controller.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: abortSource,
  );
  return controller.stream;
}
