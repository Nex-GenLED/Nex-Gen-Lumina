// PART B — the poller must be PAUSED while a Game Day apply is in flight.
//
// audit/GAMEDAY_DIRECT_APPLY_WEDGE_AUDIT.md §4 and audit/GAMEDAY_WEDGE_U1_U6.md
// §2. The direct-apply path was unpaced and poller-concurrent: a single POST
// and roughly ten concurrent `getState` GETs landed on the controller inside
// the same 15-second window, on a device this project has already documented as
// fragile under concurrent load. The calendar-populate path was taught to pause
// the poller by fix/sync-pacing; these two apply paths were not.
//
// These tests exercise the pause/resume CONTRACT on WledNotifier directly —
// the depth counter, the finally-safety, and the nesting that makes an inner
// resume unable to restart polling while an outer hold is still open. That is
// the mechanism both call sites now rely on.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

void main() {
  late ProviderContainer container;
  late WledNotifier poller;

  setUp(() {
    container = ProviderContainer();
    poller = container.read(wledStateProvider.notifier);
  });

  tearDown(() => container.dispose());

  group('Part B — pause/resume contract used by both apply paths', () {
    test('pausePolling suppresses polling; resumePolling restores it', () {
      expect(poller.isPollingPaused, isFalse,
          reason: 'baseline: not paused');

      poller.pausePolling();
      expect(poller.isPollingPaused, isTrue,
          reason: 'an apply in flight must hold the poller');

      poller.resumePolling();
      expect(poller.isPollingPaused, isFalse,
          reason: 'polling must resume once the apply completes');
    });

    test('nesting is depth-counted — an inner resume cannot release an outer '
        'hold', () {
      // This is what makes the apply-path pause safe to add even though an
      // inner helper (e.g. syncAll) may pause and resume for itself.
      poller.pausePolling();
      poller.pausePolling();
      poller.resumePolling();
      expect(poller.isPollingPaused, isTrue,
          reason: 'still held by the outer pause');

      poller.resumePolling();
      expect(poller.isPollingPaused, isFalse);
    });

    test('a THROWING apply still resumes polling — the finally is the point',
        () async {
      // Models the apply-site shape: pause, throw, finally resume. Without the
      // finally a failed apply would leave the dashboard permanently un-polled,
      // which is a worse outcome than the unpaced write it replaces.
      Future<void> applyThatFails() async {
        poller.pausePolling();
        try {
          throw StateError('device write failed');
        } finally {
          poller.resumePolling();
        }
      }

      await expectLater(applyThatFails(), throwsA(isA<StateError>()));
      expect(poller.isPollingPaused, isFalse,
          reason: 'a failed apply must NOT strand the poller');
    });

    test('a successful apply resumes polling too', () async {
      Future<void> applyThatSucceeds() async {
        poller.pausePolling();
        try {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        } finally {
          poller.resumePolling();
        }
      }

      await applyThatSucceeds();
      expect(poller.isPollingPaused, isFalse);
    });

    test('the poller is held for the WHOLE await, not just the sync prefix',
        () async {
      // The regression this guards: pausing and resuming around a non-awaited
      // call would release the hold while the write is still on the wire.
      var pausedDuringApply = false;

      Future<void> apply() async {
        poller.pausePolling();
        try {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          pausedDuringApply = poller.isPollingPaused;
        } finally {
          poller.resumePolling();
        }
      }

      await apply();
      expect(pausedDuringApply, isTrue,
          reason: 'still paused at the far side of the await');
      expect(poller.isPollingPaused, isFalse);
    });
  });
}
