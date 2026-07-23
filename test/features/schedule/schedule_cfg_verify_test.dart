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

    // (a) Race case: recovered, first readback MISMATCH, but a delayed re-LOOK
    // matches → confirmed with ZERO writes (the first readback raced the commit).
    // This is the bench-proven false-red the re-look-before-re-POST change fixes.
    test('recovered-mismatch-then-reLOOK-match → confirmed, NO re-POST', () async {
      final readback = _sequence<bool?>([false, true]); // race miss, then settled hit
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
      expect(rePostCalls, 0,
          reason: 'a transient race is answered with a second LOOK, not a WRITE');
    });

    // (b) Genuine drop: recovered, mismatch, re-LOOK STILL mismatch → the
    // corrective re-POST fires and its re-verify matches → confirmed. Exactly one
    // re-POST from this fn (the initial cfg POST lived in _pushCfgWithVerify, so
    // end-to-end that is the "two POSTs" of the genuine-drop path).
    test('mismatch → reLOOK mismatch → re-POST → re-verify match → confirmed '
        '(exactly one re-POST)', () async {
      final readback = _sequence<bool?>([false, false, true]); // miss, miss, hit after repost
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
      expect(rePostCalls, 1,
          reason: 'genuine drop → exactly one corrective re-POST');
    });

    // (d) Recovered, mismatch, but the re-LOOK comes back NULL (controller dipped
    // again mid-settle) → keep polling; never a re-POST, never red. A later poll
    // reads the landed timers → confirmed.
    test('mismatch → reLOOK null → poll continues (not red), later match → true',
        () async {
      final readback = _sequence<bool?>([false, null, true]); // miss, dip, then hit
      var rePostCalls = 0;
      var pollCount = 0;

      final ok = await verifyCfgAfterStall(
        liveness: () async => true,
        readbackMatch: () async => readback(),
        rePost: () async {
          rePostCalls++;
          return true;
        },
        delay: (_) async {},
        onPoll: (_) => pollCount++,
      );

      expect(ok, isTrue);
      expect(rePostCalls, 0, reason: 'a null re-look keeps polling, never writes');
      expect(pollCount, greaterThanOrEqualTo(2),
          reason: 'the null re-look continued the patient poll');
    });

    // (c) Genuine mismatch that never resolves: mismatch → reLOOK mismatch →
    // re-POST → re-verify STILL mismatch → red (hard-fail reachable).
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

  // The 2xx-immediate readback path's race tolerance. The bench-proven false-red
  // (192.168.1.150, 2026-07-23): heaviest sync → controller answered 2xx and the
  // very next /json/cfg GET before its config state was consistent → transient
  // mismatch → red, even though curl seconds later showed the timers landed. ONE
  // delayed re-look absorbs the race; a genuine mismatch still hard-fails.
  //
  // (Test cases (a) stall→recovery→mismatch→match and (b) →mismatch are the
  // verifyCfgAfterStall group above — mismatch→re-POST+settle+re-verify.)
  group('verify2xxReadbackWithRetry (2xx readback race tolerance)', () {
    test('first readback matches → confirmed immediately, no wait, one look',
        () async {
      var readbackCalls = 0;
      var delayCalls = 0;
      final r = await verify2xxReadbackWithRetry(
        readbackMatch: () async {
          readbackCalls++;
          return true;
        },
        delay: (_) async => delayCalls++,
      );
      expect(r, isTrue);
      expect(readbackCalls, 1, reason: 'a matching first look needs no re-look');
      expect(delayCalls, 0, reason: 'no wait when the first readback matches');
    });

    // (c) 2xx → immediate mismatch → (delay) → match = confirmed, no red.
    test('mismatch then match on the delayed re-look → confirmed', () async {
      final readback = _sequence<bool?>([false, true]);
      var readbackCalls = 0;
      var delayCalls = 0;
      final r = await verify2xxReadbackWithRetry(
        readbackMatch: () async {
          readbackCalls++;
          return readback();
        },
        delay: (_) async => delayCalls++,
      );
      expect(r, isTrue, reason: 'the readback raced the commit; re-look matched');
      expect(readbackCalls, 2, reason: 'exactly one re-look');
      expect(delayCalls, 1, reason: 'exactly one settle before the re-look');
    });

    // (d) 2xx → immediate mismatch → mismatch = red (hard-fail preserved).
    test('mismatch then STILL mismatch on the re-look → false (hard-fail)',
        () async {
      var readbackCalls = 0;
      final r = await verify2xxReadbackWithRetry(
        readbackMatch: () async {
          readbackCalls++;
          return false; // genuine mismatch — never resolves
        },
        delay: (_) async {},
      );
      expect(r, isFalse, reason: 'a persistent mismatch must still hard-fail red');
      expect(readbackCalls, 2, reason: 'one retry, then give up — never a loop');
    });

    test('first readback null (unreadable) → null passthrough, no retry',
        () async {
      var readbackCalls = 0;
      var delayCalls = 0;
      final r = await verify2xxReadbackWithRetry(
        readbackMatch: () async {
          readbackCalls++;
          return null;
        },
        delay: (_) async => delayCalls++,
      );
      expect(r, isNull, reason: 'null is inconclusive, not a mismatch');
      expect(readbackCalls, 1, reason: 'null does not trigger the mismatch retry');
      expect(delayCalls, 0);
    });

    test('mismatch then null on the re-look → null (caller falls to patient poll)',
        () async {
      final readback = _sequence<bool?>([false, null]);
      final r = await verify2xxReadbackWithRetry(
        readbackMatch: () async => readback(),
        delay: (_) async {},
      );
      expect(r, isNull,
          reason: 'became unreadable on the re-look → inconclusive, not red');
    });
  });
}
