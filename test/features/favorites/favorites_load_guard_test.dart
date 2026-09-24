// firstEventWithin — the deadline + abort behind My Favorites (2.5.10+108).
//
// On build-107 a brand-new customer's first login could leave the favorites
// listen waiting forever behind a flooded Firestore client, and the section
// spun for good. The load now has a deadline, and on the deadline the listen
// is CANCELLED (a Firestore listen is aborted by cancelling its
// subscription), not merely abandoned.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/favorites/favorites_load_guard.dart';

class _Source {
  late final StreamController<int> controller;
  var listens = 0;
  var cancels = 0;

  _Source() {
    controller = StreamController<int>(
      onListen: () => listens++,
      onCancel: () => cancels++,
    );
  }
}

void main() {
  const deadline = Duration(milliseconds: 60);

  test('no first event: TimeoutException, stream closes, source cancelled',
      () async {
    final src = _Source();
    final events = <Object>[];
    final done = Completer<void>();
    firstEventWithin(src.controller.stream, deadline).listen(
      events.add,
      onError: events.add,
      onDone: done.complete,
    );

    await done.future.timeout(const Duration(seconds: 2));
    expect(events.single, isA<TimeoutException>());
    expect(src.listens, 1);
    expect(src.cancels, 1, reason: 'the listen must be aborted, not abandoned');
  });

  test('a first event before the deadline disarms it for good', () async {
    final src = _Source();
    final events = <Object>[];
    final sub = firstEventWithin(src.controller.stream, deadline)
        .listen(events.add, onError: events.add);

    src.controller.add(1);
    // Well past the deadline: a live snapshot stream is silent between
    // changes, and that silence is not a failure.
    await Future<void>.delayed(deadline * 3);
    src.controller.add(2);
    await Future<void>.delayed(Duration.zero);

    expect(events, [1, 2]);
    expect(src.cancels, 0);
    await sub.cancel();
    expect(src.cancels, 1);
  });

  test('an error as the first event is forwarded and disarms the deadline',
      () async {
    final src = _Source();
    final events = <Object>[];
    final sub = firstEventWithin(src.controller.stream, deadline)
        .listen(events.add, onError: events.add);

    src.controller.addError(StateError('permission-denied'));
    await Future<void>.delayed(deadline * 3);

    expect(events.single, isA<StateError>());
    await sub.cancel();
  });

  test('cancelling before the deadline (provider disposed) cancels the source '
      'and never reports a timeout', () async {
    final src = _Source();
    final events = <Object>[];
    final sub = firstEventWithin(src.controller.stream, deadline)
        .listen(events.add, onError: events.add);

    await sub.cancel();
    await Future<void>.delayed(deadline * 3);

    expect(src.cancels, 1);
    expect(events, isEmpty);
  });
}
