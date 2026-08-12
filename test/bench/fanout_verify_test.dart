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

/// A's real resting state on the bench: master OFF at base preset 2, seg0
/// fx=0 — and pal=5, which is ALSO the broadcast's palette. Used as the
/// default baseline so the tests exercise the coincidence the live run hit.
ControllerSnapshot _resting() => const ControllerSnapshot(
      on: false,
      effectId: 0,
      paletteId: 5,
      colors: [
        [0, 200, 255, 0],
      ],
    );

/// A fanout#1 response that served both members and skipped nobody.
FanoutResponse _served({int members = 2, int commands = 2, int skipped = 0}) =>
    FanoutResponse.fromBody(200, {
      'ok': true,
      'memberCount': members,
      'commandCount': commands,
      'skipped': skipped,
    });

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
          {
            'fx': 88,
            'pal': 5,
            'col': [
              [255, 0, 0],
              [0, 0, 255]
            ]
          }
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
          '0': {
            'fx': 88,
            'pal': 5,
            'col': [
              [255, 0, 0]
            ]
          }
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

    // THE 2026-08-12 DELIVERY DEFECT. resolveMemberTargets returns ip:"" for
    // every member whose doc carries a denormalized controllerId array, so the
    // CF wrote commands naming no destination. The real bridge answered
    // "ERROR: HTTP -1" and marked them failed; the stub, which never reads
    // controllerIp, reported the byte-identical command as delivered. The
    // simulator must not be more capable than the bridge.
    test('skips a command with an EMPTY controllerIp', () {
      final c = QueuedCommand(
        id: 'c5',
        type: 'applyJson',
        payload: _pattern.toSegPayload(),
        controllerIp: '',
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

    test('a SUCCESS carries no reason — the body fallback is failure-only', () {
      final r = FanoutResponse.fromBody(
          200, {'ok': true, 'memberCount': 2, 'commandCount': 2, 'skipped': 0});
      expect(r.reason, isNull);
    });

    test('a failure with neither reason nor error still reports the body', () {
      final r = FanoutResponse.fromBody(400, {'ok': false, 'detail': 'x'});
      expect(r.reason, contains('detail'));
    });

    test('200 with a different reason is NOT a rate-limit refusal', () {
      final r =
          FanoutResponse.fromBody(200, {'ok': false, 'reason': 'no_members'});
      expect(r.isRateLimited, isFalse);
    });
  });

  group('evaluateFanoutRun', () {
    FanoutRunObservation good() => FanoutRunObservation(
          bQueueAfterFanout: [_applyCmd()],
          initiatorUid: 'uid_A',
          nodeBUid: 'uid_B',
          nodeABefore: _resting(),
          nodeAAfter: _matching(),
          nodeBAfter: _matching(),
          broadcast: _pattern,
          firstFanout: _served(),
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
        nodeABefore: _resting(),
        nodeAAfter: _matching(),
        nodeBAfter: _matching(),
        broadcast: _pattern,
        firstFanout: _served(),
        secondFanout: FanoutResponse.fromBody(
            200, {'ok': false, 'reason': 'rate_limited'}),
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
        nodeABefore: _resting(),
        nodeAAfter: _matching(),
        nodeBAfter: _matching(),
        broadcast: _pattern,
        firstFanout: _served(),
        secondFanout: FanoutResponse.fromBody(
            200, {'ok': false, 'reason': 'rate_limited'}),
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
        nodeABefore: _resting(),
        nodeAAfter: _matching(),
        nodeBAfter:
            const ControllerSnapshot(on: true, effectId: 0, paletteId: 0),
        broadcast: _pattern,
        firstFanout: _served(),
        secondFanout: FanoutResponse.fromBody(
            200, {'ok': false, 'reason': 'rate_limited'}),
      );
      final checks = evaluateFanoutRun(o);
      expect(checks[1].pass, isFalse); // delivery
      expect(checks[2].pass, isFalse); // convergence
    });

    // THE 2026-08-12 RUN, as a regression. A's member doc was
    // participationStatus:"paused", so fanoutToCrew skipped it silently and
    // wrote no command for A. A stayed at base — fx=0, pal=5 — and because the
    // broadcast's palette is ALSO 5, the evidence line read "A fx=0 pal=5" and
    // looked like a half-applied pattern. Nothing had been applied at all.
    test('a skipped initiator fails convergence and NAMES the skip', () {
      final o = FanoutRunObservation(
        bQueueAfterFanout: [_applyCmd()],
        initiatorUid: 'uid_A',
        nodeBUid: 'uid_B',
        nodeABefore: _resting(),
        nodeAAfter: _resting(), // never written to — unchanged
        nodeBAfter: _matching(),
        broadcast: _pattern,
        firstFanout: _served(members: 1, commands: 1, skipped: 1),
        secondFanout: FanoutResponse.fromBody(
            200, {'ok': false, 'reason': 'rate_limited'}),
      );
      final checks = evaluateFanoutRun(o);
      expect(checks[0].pass, isTrue); // server wrote to B
      expect(checks[1].pass, isTrue); // B converged
      expect(checks[2].pass, isFalse); // A did not
      expect(checks[2].evidence, contains('skipped=1'));
      expect(checks[2].evidence, contains('participationStatus'));
      // The baseline is what makes "pal=5 was already there" legible.
      expect(checks[2].evidence, contains('before fx=0 pal=5'));
    });

    // The other direction, and the more dangerous one: if A were already
    // resting ON the broadcast pattern, a "converged" pass would be worthless.
    test('a baseline that already matches is INCONCLUSIVE, never a pass', () {
      final o = FanoutRunObservation(
        bQueueAfterFanout: [_applyCmd()],
        initiatorUid: 'uid_A',
        nodeBUid: 'uid_B',
        nodeABefore: _matching(), // already carrying the pattern
        nodeAAfter: _matching(),
        nodeBAfter: _matching(),
        broadcast: _pattern,
        firstFanout: _served(),
        secondFanout: FanoutResponse.fromBody(
            200, {'ok': false, 'reason': 'rate_limited'}),
      );
      final conv = evaluateFanoutRun(o)[2];
      expect(conv.pass, isFalse);
      expect(conv.evidence, contains('INCONCLUSIVE'));
    });

    test('server accounting is parsed off the fanout response', () {
      final r = FanoutResponse.fromBody(
          200, {'ok': true, 'memberCount': 1, 'commandCount': 1, 'skipped': 1});
      expect(r.memberCount, 1);
      expect(r.commandCount, 1);
      expect(r.skipped, 1);
    });

    test('an absent accounting block stays null, not zero', () {
      // null means "the server did not say"; 0 means "it said none". Collapsing
      // them would invent a skip=0 claim the server never made.
      final r = FanoutResponse.fromBody(200, {'ok': true});
      expect(r.memberCount, isNull);
      expect(r.skipped, isNull);
    });

    test('an unlimited second fanout fails the rate-limit assertion', () {
      final o = FanoutRunObservation(
        bQueueAfterFanout: [_applyCmd()],
        initiatorUid: 'uid_A',
        nodeBUid: 'uid_B',
        nodeABefore: _resting(),
        nodeAAfter: _matching(),
        nodeBAfter: _matching(),
        broadcast: _pattern,
        firstFanout: _served(),
        secondFanout: FanoutResponse.fromBody(200, {'ok': true}),
      );
      expect(evaluateFanoutRun(o).last.pass, isFalse);
    });
  });
}
