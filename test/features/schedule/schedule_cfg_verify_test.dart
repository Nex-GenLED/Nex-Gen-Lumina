// Unit tests for verifyCfgAfterStall — the patient verification state machine
// that replaces the old retry loop. Models the bench-proven controller stall:
// the cfg write commits, the web server freezes for minutes, then recovers.
// We poll liveness, then readback-verify; we do NOT hammer re-POSTs into the
// blackout. Injected liveness/readback/rePost/delay → instant, deterministic.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

/// Returns a function that yields the given values in sequence, repeating the
/// last one once exhausted.
T Function() _sequence<T>(List<T> values) {
  var i = 0;
  return () {
    final v = values[i < values.length ? i : values.length - 1];
    i++;
    return v;
  };
}

void main() {
  group('verifyCfgAfterStall', () {
    test('stall-then-match: recovers after 2 dead polls, readback confirms → '
        'true (no re-POST)', () async {
      final live = _sequence<bool>([false, false, true]);
      var readbackCalls = 0;
      var rePostCalls = 0;
      var pollCount = 0;

      final ok = await verifyCfgAfterStall(
        liveness: () async => live(),
        readbackMatch: () async {
          readbackCalls++;
          return true; // recovered → timers present
        },
        rePost: () async {
          rePostCalls++;
          return true;
        },
        delay: (_) async {},
        onPoll: (_) => pollCount++,
      );

      expect(ok, isTrue);
      expect(rePostCalls, 0, reason: 'must NOT re-POST when readback confirms');
      expect(readbackCalls, 1);
      expect(pollCount, 3, reason: 'two dead polls then the live one');
    });

    test('stall-then-mismatch-then-repost-success: recovered but timers absent, '
        'one re-POST + settle + re-verify → true', () async {
      final readback = _sequence<bool?>([false, true]); // miss, then hit after repost
      var rePostCalls = 0;

      final ok = await verifyCfgAfterStall(
        liveness: () async => true, // alive immediately
        readbackMatch: () async => readback(),
        rePost: () async {
          rePostCalls++;
          return true;
        },
        delay: (_) async {},
      );

      expect(ok, isTrue);
      expect(rePostCalls, 1, reason: 'exactly one corrective re-POST');
    });

    test('recovered-mismatch-then-repost-STILL-mismatch → false', () async {
      var rePostCalls = 0;
      final ok = await verifyCfgAfterStall(
        liveness: () async => true,
        readbackMatch: () async => false, // never matches
        rePost: () async {
          rePostCalls++;
          return false;
        },
        delay: (_) async {},
      );
      expect(ok, isFalse);
      expect(rePostCalls, 1, reason: 'one re-POST attempt, then give up');
    });

    test('never-recovers: liveness always dead → false after the full window, '
        'no re-POST', () async {
      var livenessCalls = 0;
      var rePostCalls = 0;
      final ok = await verifyCfgAfterStall(
        liveness: () async {
          livenessCalls++;
          return false;
        },
        readbackMatch: () async => true, // never reached
        rePost: () async {
          rePostCalls++;
          return true;
        },
        delay: (_) async {},
      );
      expect(ok, isFalse);
      expect(rePostCalls, 0, reason: 'never re-POST while stalled');
      // 5min / 20s poll = 15 polls.
      expect(livenessCalls, 15);
    });

    test('half-recovered: alive but cfg readback inconclusive (null) a few '
        'times, then matches → true, no re-POST', () async {
      final readback = _sequence<bool?>([null, null, true]);
      var rePostCalls = 0;
      final ok = await verifyCfgAfterStall(
        liveness: () async => true,
        readbackMatch: () async => readback(),
        rePost: () async {
          rePostCalls++;
          return true;
        },
        delay: (_) async {},
      );
      expect(ok, isTrue);
      expect(rePostCalls, 0,
          reason: 'null readback keeps polling; it is not a mismatch');
    });
  });
}
