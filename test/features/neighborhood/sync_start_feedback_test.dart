// SYNC START WINDOW (2026-11-02), items 3 and 4: what the Start button does
// with each outcome. The panel's build reads FirebaseAuth.instance, so the
// mapping is pure (sync_start_feedback.dart) and tested here; the panel calls
// exactly these two functions after `await broadcastSync(...)`.
//
//   * the engine is marked active ONLY when the command write was acknowledged;
//   * every outcome that is not a clean success has a plain-text line, with
//     the server's reason code / text when it returned one.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';
import 'package:nexgen_command/features/neighborhood/sync_start_feedback.dart';

void main() {
  group('shouldMarkEngineActive — only an acknowledged command write', () {
    test('written (flag off, no fan-out) → active', () {
      expect(shouldMarkEngineActive(const SyncStartResult(commandWritten: true)), isTrue);
    });
    test('written + fan-out ok → active', () {
      expect(
        shouldMarkEngineActive(const SyncStartResult(
          commandWritten: true,
          fanout: FanoutResult(ok: true, memberCount: 2, commandCount: 2, skipped: 0),
        )),
        isTrue,
      );
    });
    test('written + fan-out failed (broadcast still ran) → active', () {
      expect(
        shouldMarkEngineActive(const SyncStartResult(
          commandWritten: true,
          fanout: FanoutResult.failed(reason: 'network'),
        )),
        isTrue,
      );
    });
    test('rate-limited (nothing fired) → NOT active', () {
      expect(
        shouldMarkEngineActive(const SyncStartResult(
          commandWritten: false,
          fanout: FanoutResult(rateLimited: true, retryAfterMs: 17000),
        )),
        isFalse,
      );
    });
    for (final reason in ['flag_unavailable', 'write_timeout', 'client_error']) {
      test('failure $reason (nothing fired) → NOT active', () {
        expect(
          shouldMarkEngineActive(SyncStartResult.failed(SyncStartFailure(reason))),
          isFalse,
        );
      });
    }
  });

  group('syncStartFeedbackFor — a plain line for every non-clean outcome', () {
    test('clean success (fan-out reached everyone) → no line', () {
      expect(
        syncStartFeedbackFor(const SyncStartResult(
          commandWritten: true,
          fanout: FanoutResult(ok: true, memberCount: 2, commandCount: 2, skipped: 0),
        )),
        isNull,
      );
    });

    test('flag off (app-open broadcast only, as before) → no line', () {
      expect(syncStartFeedbackFor(const SyncStartResult(commandWritten: true)), isNull);
    });

    test('flag unreadable → error line says nothing was started', () {
      final f = syncStartFeedbackFor(
        const SyncStartResult.failed(SyncStartFailure('flag_unavailable')),
      );
      expect(f, isNotNull);
      expect(f!.isError, isTrue);
      expect(f.text, contains('Nothing was started'));
      expect(f.text, contains('sync settings'));
    });

    test('command write timed out → error line says nothing was started', () {
      final f = syncStartFeedbackFor(
        const SyncStartResult.failed(SyncStartFailure('write_timeout')),
      );
      expect(f!.isError, isTrue);
      expect(f.text, contains("didn't go through in time"));
      expect(f.text, contains('Nothing was started'));
    });

    test('client error → error line says nothing was sent', () {
      final f = syncStartFeedbackFor(
        const SyncStartResult.failed(SyncStartFailure('client_error')),
      );
      expect(f!.isError, isTrue);
      expect(f.text, contains('Nothing was sent'));
    });

    test('rate-limited → "try again in Ns" (ceil, min 1)', () {
      final f = syncStartFeedbackFor(const SyncStartResult(
        commandWritten: false,
        fanout: FanoutResult(rateLimited: true, retryAfterMs: 17001),
      ));
      expect(f!.isError, isFalse);
      expect(f.text, 'Hang on — try again in 18s.');
      final g = syncStartFeedbackFor(const SyncStartResult(
        commandWritten: false,
        fanout: FanoutResult(rateLimited: true, retryAfterMs: 0),
      ));
      expect(g!.text, 'Hang on — try again in 1s.');
    });

    test('fan-out failed with the server\'s reason + text → warning names both', () {
      final f = syncStartFeedbackFor(const SyncStartResult(
        commandWritten: true,
        fanout: FanoutResult(
          ok: false,
          reason: 'http_403',
          detail: 'Initiator is not a member of the named sync group.',
        ),
      ));
      expect(f!.isError, isFalse);
      expect(f.text, contains("weren't reached"));
      expect(f.text, contains('http_403: Initiator is not a member of the named sync group.'));
    });

    test('fan-out failed with a client reason only → warning names the reason', () {
      final f = syncStartFeedbackFor(const SyncStartResult(
        commandWritten: true,
        fanout: FanoutResult.failed(reason: 'timeout'),
      ));
      expect(f!.text, contains('(timeout)'));
    });

    test('fan-out ok but host-only (no memberCount: group not in scope) → warning says so', () {
      final f = syncStartFeedbackFor(const SyncStartResult(
        commandWritten: true,
        fanout: FanoutResult(ok: true, commandCount: 1),
      ));
      expect(f!.isError, isFalse);
      expect(f.text, contains("isn't enabled for closed-app delivery"));
    });

    test('fan-out ok but reached nobody → warning', () {
      final f = syncStartFeedbackFor(const SyncStartResult(
        commandWritten: true,
        fanout: FanoutResult(ok: true, memberCount: 2, commandCount: 0, skipped: 0),
      ));
      expect(f!.text, contains('no closed-app homes were reached'));
    });

    test('fan-out ok with skipped members → warning with the count', () {
      final f = syncStartFeedbackFor(const SyncStartResult(
        commandWritten: true,
        fanout: FanoutResult(ok: true, memberCount: 3, commandCount: 2, skipped: 1),
      ));
      expect(f!.text, contains('1 neighbor with the app closed was skipped'));
      final g = syncStartFeedbackFor(const SyncStartResult(
        commandWritten: true,
        fanout: FanoutResult(ok: true, memberCount: 4, commandCount: 2, skipped: 2),
      ));
      expect(g!.text, contains('2 neighbors with the app closed were skipped'));
    });
  });
}
