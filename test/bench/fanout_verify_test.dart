// Unit tests for the two-node fanout harness's pure logic
// (bench/src/fanout_verify.dart). The hardware run is runbook step 5 and is
// gated on the F-3 deploy + a scoped fanout flag; this locks the logic that
// decides pass/fail so that when it finally runs, a green result means
// something.
//
// The assertion that matters most here is the rate-limit one: the CF signals a
// refusal as HTTP 200 with {ok:false, reason:"rate_limited"}, so a naive
// "non-200 means refused" check would let a 500 read as working anti-strobe
// protection. That false-green is tested for explicitly.

import 'package:flutter_test/flutter_test.dart';

import '../../bench/src/fanout_verify.dart';

const _pattern = PatternSpec(
  effectId: 88,
  paletteId: 5,
  colors: [
    [255, 0, 0],
    [0, 0, 255],
  ],
);

ControllerSnapshot _matching() => const ControllerSnapshot(
      on: true,
      effectId: 88,
      paletteId: 5,
      colors: [
        [255, 0, 0],
        [0, 0, 255],
      ],
    );

QueuedCommand _applyCmd({String id = 'c1', String status = 'pending'}) =>
    QueuedCommand(
      id: id,
      type: 'applyJson',
      status: status,
      payload: _pattern.toSegPayload(),
    );

void main() {
  group('ControllerSnapshot.fromState', () {
    test('parses a List-shaped seg', () {
      final s = ControllerSnapshot.fromState({
        'on': true,
        'seg': [
          {'fx': 88, 'pal': 5, 'col': [[255, 0, 0], [0, 0, 255]]}
        ],
      });
      expect(s.on, isTrue);
      expect(s.effectId, 88);
      expect(s.paletteId, 5);
      expect(s.colors.first, [255, 0, 0]);
    });

    // WLED returns `seg` as a Map on some firmware versions — a documented
    // variability this codebase has been bitten by before.
    test('parses a Map-shaped seg', () {
      final s = ControllerSnapshot.fromState({
        'on': true,
        'seg': {
          '0': {'fx': 88, 'pal': 5, 'col': [[255, 0, 0]]}
        },
      });
      expect(s.effectId, 88);
      expect(s.paletteId, 5);
    });

    test('tolerates a missing/empty seg', () {
      final s = ControllerSnapshot.fromState({'on': false});
      expect(s.on, isFalse);
      expect(s.effectId, isNull);
      expect(s.colors, isEmpty);
    });
  });

  group('ControllerSnapshot.reflects', () {
    test('matches an exact pattern', () {
      expect(_matching().reflects(_pattern), isTrue);
    });

    // An RGBW controller reports 4 channels for a 3-channel broadcast. A
    // trailing zero W is not a mismatch.
    test('RGBW readback matches an RGB broadcast', () {
      const s = ControllerSnapshot(
        on: true,
        effectId: 88,
        paletteId: 5,
        colors: [
          [255, 0, 0, 0],
          [0, 0, 255, 0],
        ],
      );
      expect(s.reflects(_pattern), isTrue);
    });

    test('wrong effect fails', () {
      const s = ControllerSnapshot(
        on: true,
        effectId: 0,
        paletteId: 5,
        colors: [
          [255, 0, 0],
          [0, 0, 255],
        ],
      );
      expect(s.reflects(_pattern), isFalse);
    });

    test('wrong palette fails', () {
      const s = ControllerSnapshot(
        on: true,
        effectId: 88,
        paletteId: 0,
        colors: [
          [255, 0, 0],
          [0, 0, 255],
        ],
      );
      expect(s.reflects(_pattern), isFalse);
    });

    test('wrong color fails', () {
      const s = ControllerSnapshot(
        on: true,
        effectId: 88,
        paletteId: 5,
        colors: [
          [0, 255, 0],
          [0, 0, 255],
        ],
      );
      expect(s.reflects(_pattern), isFalse);
    });

    test('too few colors fails', () {
      const s = ControllerSnapshot(
        on: true,
        effectId: 88,
        paletteId: 5,
        colors: [
          [255, 0, 0],
        ],
      );
      expect(s.reflects(_pattern), isFalse);
    });
  });

  group('executableCommands (bridge-sim drain)', () {
    test('executes a pending applyJson', () {
      expect(executableCommands([_applyCmd()]).length, 1);
    });

    test('skips already-completed commands', () {
      expect(executableCommands([_applyCmd(status: 'completed')]), isEmpty);
    });

    test('skips non-applyJson types', () {
      final c = QueuedCommand(
        id: 'c2',
        type: 'reboot',
        payload: const {'x': 1},
      );
      expect(executableCommands([c]), isEmpty);
    });

    // Posting an empty seg is the skip-apply hazard the sync engine already
    // guards against; the bridge-sim must not reintroduce it.
    test('skips an empty-seg payload', () {
      const c = QueuedCommand(
        id: 'c3',
        type: 'applyJson',
        payload: {'seg': []},
      );
      expect(executableCommands([c]), isEmpty);
    });

    test('skips an entirely empty payload', () {
      const c = QueuedCommand(id: 'c4', type: 'applyJson', payload: {});
      expect(executableCommands([c]), isEmpty);
    });

    test('preserves queue order', () {
      final out = executableCommands([
        _applyCmd(id: 'a'),
        _applyCmd(id: 'b'),
        _applyCmd(id: 'c'),
      ]);
      expect(out.map((c) => c.id), ['a', 'b', 'c']);
    });
  });

  group('applyPayload (stub controller)', () {
    test('applies fx/pal/col', () {
      const before = ControllerSnapshot(on: true, effectId: 0, paletteId: 0);
      final after = applyPayload(before, _pattern.toSegPayload());
      expect(after.reflects(_pattern), isTrue);
    });

    // A top-level-only payload like {'on': false} has no seg key and must not
    // wipe the segment fields.
    test('a top-level-only payload preserves segment state', () {
      final after = applyPayload(_matching(), {'on': false});
      expect(after.on, isFalse);
      expect(after.effectId, 88);
      expect(after.paletteId, 5);
      expect(after.colors.first, [255, 0, 0]);
    });
  });

  group('FanoutResponse.isRateLimited', () {
    test('200 + ok:false + rate_limited is a refusal', () {
      final r = FanoutResponse.fromBody(
          200, {'ok': false, 'reason': 'rate_limited', 'retryAfterMs': 12000});
      expect(r.isRateLimited, isTrue);
      expect(r.retryAfterMs, 12000);
    });

    test('200 + ok:true is NOT a refusal', () {
      final r = FanoutResponse.fromBody(200, {'ok': true});
      expect(r.isRateLimited, isFalse);
    });

    // THE FALSE-GREEN GUARD. A 500 must never read as "the limiter worked".
    test('a 500 is NOT a refusal', () {
      final r = FanoutResponse.fromBody(500, {'error': 'boom'});
      expect(r.isRateLimited, isFalse);
    });

    test('200 with a different reason is NOT a rate-limit refusal', () {
      final r = FanoutResponse.fromBody(200, {'ok': false, 'reason': 'no_members'});
      expect(r.isRateLimited, isFalse);
    });
  });

  group('evaluateFanoutRun', () {
    FanoutRunObservation good() => FanoutRunObservation(
          bQueueAfterFanout: [_applyCmd()],
          initiatorUid: 'uid_A',
          nodeBUid: 'uid_B',
          nodeAAfter: _matching(),
          nodeBAfter: _matching(),
          broadcast: _pattern,
          secondFanout: FanoutResponse.fromBody(
              200, {'ok': false, 'reason': 'rate_limited'}),
        );

    test('a clean run passes all four assertions', () {
      final checks = evaluateFanoutRun(good());
      expect(checks.length, 4);
      expect(checks.every((c) => c.pass), isTrue,
          reason: checks.map((c) => c.toString()).join('\n'));
    });

    test('empty queue fails the server assertion', () {
      final o = FanoutRunObservation(
        bQueueAfterFanout: const [],
        initiatorUid: 'uid_A',
        nodeBUid: 'uid_B',
        nodeAAfter: _matching(),
        nodeBAfter: _matching(),
        broadcast: _pattern,
        secondFanout:
            FanoutResponse.fromBody(200, {'ok': false, 'reason': 'rate_limited'}),
      );
      expect(evaluateFanoutRun(o).first.pass, isFalse);
    });

    // THE RUN-INVALIDATING CASE. If B is the initiator, delivery to B proves
    // only self-apply — nothing about fanout. It must fail loudly rather than
    // quietly pass and be cited as evidence.
    test('B == initiator fails the server assertion', () {
      final o = FanoutRunObservation(
        bQueueAfterFanout: [_applyCmd()],
        initiatorUid: 'uid_SAME',
        nodeBUid: 'uid_SAME',
        nodeAAfter: _matching(),
        nodeBAfter: _matching(),
        broadcast: _pattern,
        secondFanout:
            FanoutResponse.fromBody(200, {'ok': false, 'reason': 'rate_limited'}),
      );
      final server = evaluateFanoutRun(o).first;
      expect(server.pass, isFalse);
      expect(server.evidence, contains('equals the initiator'));
    });

    test('B not converged fails delivery and convergence', () {
      final o = FanoutRunObservation(
        bQueueAfterFanout: [_applyCmd()],
        initiatorUid: 'uid_A',
        nodeBUid: 'uid_B',
        nodeAAfter: _matching(),
        nodeBAfter: const ControllerSnapshot(on: true, effectId: 0, paletteId: 0),
        broadcast: _pattern,
        secondFanout:
            FanoutResponse.fromBody(200, {'ok': false, 'reason': 'rate_limited'}),
      );
      final checks = evaluateFanoutRun(o);
      expect(checks[1].pass, isFalse); // delivery
      expect(checks[2].pass, isFalse); // convergence
    });

    test('an unlimited second fanout fails the rate-limit assertion', () {
      final o = FanoutRunObservation(
        bQueueAfterFanout: [_applyCmd()],
        initiatorUid: 'uid_A',
        nodeBUid: 'uid_B',
        nodeAAfter: _matching(),
        nodeBAfter: _matching(),
        broadcast: _pattern,
        secondFanout: FanoutResponse.fromBody(200, {'ok': true}),
      );
      expect(evaluateFanoutRun(o).last.pass, isFalse);
    });
  });
}
