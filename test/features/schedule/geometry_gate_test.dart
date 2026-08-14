// The geometry gate — nothing psaves the ladder over wrong geometry.
//
// psave captures LIVE segment geometry into the preset regardless of the inline
// state (bench-proven: a save sending only {id,on} stored rev/mi/of/grp/spc
// anyway). So a save taken while geometry is wrong bakes the error into the
// base layer, where it loads every night — #76's transient clobber made
// durable. This gate is the fourth layer of that severity cap.
//
// The bench shape throughout: seg0 [0,128), seg1 [128,290).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';

const bench = <SegmentShape>[
  SegmentShape(0, 0, 128),
  SegmentShape(1, 128, 290),
];

/// A device whose shape can be set, and which records what it was told.
class FakeDevice {
  List<SegmentShape>? shape;
  final List<List<SegmentShape>> writes = [];
  bool writeSucceeds = true;
  bool writeActuallyApplies = true;
  bool readThrows = false;
  int reads = 0;

  FakeDevice(this.shape);

  Future<List<SegmentShape>?> read() async {
    reads++;
    if (readThrows) throw StateError('unreachable');
    return shape;
  }

  Future<bool> provision(List<SegmentShape> want) async {
    writes.add(want);
    if (!writeSucceeds) return false;
    if (writeActuallyApplies) shape = List.of(want);
    return true;
  }
}

Future<GateResult> run(FakeDevice d, {List<SegmentShape> expected = bench}) =>
    evaluateGeometryGate(
        expected: expected, read: d.read, reprovision: d.provision);

void main() {
  group('classifyGeometry — count and bounds only', () {
    test('identical -> match', () {
      expect(classifyGeometry(bench, bench), GateBranch.match);
    });

    test('same count, moved bounds -> drift', () {
      expect(
        classifyGeometry(bench, const [
          SegmentShape(0, 0, 130),
          SegmentShape(1, 130, 290),
        ]),
        GateBranch.drift,
      );
    });

    // The reboot collapse, 2026-08-14: two segments became one spanning the
    // whole strip, and a preset load could NOT undo it.
    test('collapsed to one segment -> totalLoss', () {
      expect(
        classifyGeometry(bench, const [SegmentShape(0, 0, 290)]),
        GateBranch.totalLoss,
      );
    });

    // "We do not know the shape" must never authorise a save.
    test('empty EXPECTED is totalLoss, not a vacuous match', () {
      expect(classifyGeometry(const [], const []), GateBranch.totalLoss);
    });
  });

  // THE #76-SIGN-FLIPPED RULE. The pixel map does not own rev/mi/of/grp/spc —
  // provisioning and the installer do. A gate that compared them would refuse
  // on a correctly-installed reversed channel the app has no record of, which
  // is the same error as clobbering it, just in the other direction.
  test('geometry FIELDS are not compared — only count and bounds', () {
    // Ellie's case: the device is legitimately reversed. The gate sees shape,
    // not orientation, so it must read as a clean match.
    expect(classifyGeometry(bench, bench), GateBranch.match);
    // And the shape type carries no orientation to compare in the first place.
    const s = SegmentShape(1, 128, 290);
    expect(s.toString(), '1[128,290)');
  });

  group('MATCH branch', () {
    test('proceeds without writing anything', () async {
      final d = FakeDevice(List.of(bench));
      final r = await run(d);
      expect(r.proceed, isTrue);
      expect(r.branch, GateBranch.match);
      expect(r.repaired, isFalse);
      expect(d.writes, isEmpty, reason: 'a matching device must not be written');
      expect(r.refusal, isNull);
    });
  });

  group('DRIFT branch', () {
    test('re-provisions, re-reads, then proceeds', () async {
      final d = FakeDevice([const SegmentShape(0, 0, 130), const SegmentShape(1, 130, 290)]);
      final r = await run(d);
      expect(r.branch, GateBranch.drift);
      expect(r.proceed, isTrue);
      expect(r.repaired, isTrue);
      expect(d.writes.single, bench);
      expect(r.actual, bench);
    });

    // A write that reports success is NOT evidence. The whole lesson of the
    // 2026-08-14 incident is that the device's actual shape is the authority.
    test('a write that reports success but does NOT take is refused', () async {
      final d = FakeDevice([const SegmentShape(0, 0, 130), const SegmentShape(1, 130, 290)])
        ..writeActuallyApplies = false;
      final r = await run(d);
      expect(r.proceed, isFalse);
      expect(r.repaired, isFalse);
      expect(d.reads, greaterThanOrEqualTo(2), reason: 'must re-read to verify');
      expect(r.refusal, contains('did not take'));
    });

    test('a failed write is refused and says so differently', () async {
      final d = FakeDevice([const SegmentShape(0, 0, 130), const SegmentShape(1, 130, 290)])
        ..writeSucceeds = false;
      final r = await run(d);
      expect(r.proceed, isFalse);
      expect(r.refusal, contains('failed'));
    });
  });

  group('TOTAL LOSS branch', () {
    test('collapsed layout is re-provisioned from the map and verified', () async {
      final d = FakeDevice([const SegmentShape(0, 0, 290)]);
      final r = await run(d);
      expect(r.branch, GateBranch.totalLoss);
      expect(r.proceed, isTrue);
      expect(r.repaired, isTrue);
      expect(d.writes.single, bench);
    });

    test('unrecoverable collapse refuses, naming both shapes', () async {
      final d = FakeDevice([const SegmentShape(0, 0, 290)])
        ..writeActuallyApplies = false;
      final r = await run(d);
      expect(r.proceed, isFalse);
      expect(r.refusal, contains('0[0,128) 1[128,290)')); // expected
      expect(r.refusal, contains('0[0,290)')); // actual
    });
  });

  group('unreadable device', () {
    test('refuses rather than guessing', () async {
      final d = FakeDevice(List.of(bench))..readThrows = true;
      final r = await run(d);
      expect(r.proceed, isFalse);
      expect(r.refusal, contains('unreadable'));
      expect(d.writes, isEmpty, reason: 'never write on top of an unknown shape');
    });

    test('a null read is also a refusal', () async {
      final r = await run(FakeDevice(null));
      expect(r.proceed, isFalse);
    });
  });

  test('summary is legible in both directions', () async {
    final ok = await run(FakeDevice(List.of(bench)));
    expect(ok.summary, contains('match'));
    final bad = await run(FakeDevice([const SegmentShape(0, 0, 290)])
      ..writeSucceeds = false);
    expect(bad.summary, contains('gated_geometry_mismatch'));
    expect(bad.summary, contains('expected'));
  });

  // THE INTERACTION, pinned. The two guards ask different questions:
  // the gate asks "is the device in a state worth saving?", the convergence
  // guard asks "has saving stopped helping?". A gate refusal means NO SAVE
  // HAPPENED, so counting it would burn the convergence budget on a condition
  // a save was never going to fix — and would eventually silence the gate's
  // own legible refusal behind a non-convergence refusal.
  group('gate refusal is NOT a repair attempt', () {
    test('a refused gate leaves the convergence counter untouched', () async {
      final store = InMemoryRepairAttemptStore();
      final d = FakeDevice([const SegmentShape(0, 0, 290)])
        ..writeActuallyApplies = false;

      for (var sync = 0; sync < 10; sync++) {
        final g = await run(d);
        expect(g.proceed, isFalse);
        // The caller must NOT record an attempt when the gate refuses.
        if (g.proceed) await store.recordAttempt(2);
      }

      expect(await store.attempts(2), 0);
      final decision =
          await decideRepair(presetId: 2, presetName: 'NGL Off', store: store);
      expect(decision.allowed, isTrue,
          reason: 'ten gate refusals must not exhaust the repair budget');
    });

    test('a gate that PROCEEDS does feed the convergence guard', () async {
      final store = InMemoryRepairAttemptStore();
      final d = FakeDevice(List.of(bench));
      var saves = 0;
      for (var sync = 0; sync < 10; sync++) {
        final g = await run(d);
        if (!g.proceed) continue;
        final decision = await decideRepair(
            presetId: 2, presetName: 'NGL Off', store: store);
        if (!decision.allowed) continue;
        saves++;
        await store.recordAttempt(2);
      }
      expect(saves, kMaxRepairAttempts,
          reason: 'geometry fine, predicate never satisfied -> the OTHER guard '
              'stops it');
    });
  });

  group('segmentShapeFromState', () {
    test('parses the bench shape', () {
      final s = segmentShapeFromState({
        'seg': [
          {'id': 0, 'start': 0, 'stop': 128},
          {'id': 1, 'start': 128, 'stop': 290},
        ]
      });
      expect(s, bench);
    });

    // WLED reports unused slots as zero-length; counting them would fake a
    // segment count and turn a match into a totalLoss.
    test('zero-length segments are not part of the shape', () {
      final s = segmentShapeFromState({
        'seg': [
          {'id': 0, 'start': 0, 'stop': 128},
          {'id': 1, 'start': 128, 'stop': 290},
          {'id': 2, 'start': 0, 'stop': 0},
        ]
      });
      expect(s, bench);
    });

    test('a malformed body is null, not an empty shape', () {
      expect(segmentShapeFromState(null), isNull);
      expect(segmentShapeFromState({'on': true}), isNull);
    });
  });
}
