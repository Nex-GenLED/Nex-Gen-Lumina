// test/features/wled/celebration_revert_capture_replay_test.dart
//
// COVERAGE OWED BY a356b5f — §2 of audit/ORIENTATION_ON_THE_WIRE.md.
//
// `rev` was cleared on the bench's seg 1 TWICE in one evening, on +80, with the
// geometry wire pin LIVE. The pin was working; nothing drove the path that
// leaked. The suite went 2441/4/0 with ZERO geometry assertions, because no
// test exercised `WledCelebrationDelivery.revert` at all.
//
// This file drives it. `capture()` is `repo.getState()` — the full
// `/json/state`, every seg carrying `start`/`stop`/`rev`/`len`/`mi` — and
// `revert()` replays that array VERBATIM through `applyJson`. That is the
// CAPTURE-REPLAY class: a stored state snapshot trusted at use-time, third
// sibling of stored-intent and stored-addresses.
//
// TWO ASSERTIONS PER SITE, AND BOTH ARE LOad-BEARING:
//
//   A. THE TAP POINT (pre-strip). The raw payload the site hands `applyJson`
//      still carries geometry. This is what makes B non-vacuous — without it,
//      "the wire is geometry-free" would pass just as happily against a
//      payload that never had geometry in it. It is also the mechanism by
//      which this test is PROVABLY ABLE TO FAIL: it is the pre-strip tap.
//
//   B. THE WIRE (post-strip). `stripGeometry` is the production function the
//      release wire applies, so what it emits IS what reaches the controller.
//      id/on/col/fx/pal survive; start/stop/rev/mi are gone.
//
//   C. THE REAL EXIT. Driven against an un-stubbed `WledService.applyJson`,
//      the payload reaches `pinNoGeometryOnWire` at the actual wire exit and
//      trips the debug assert naming `rev`. B is therefore not hypothetical:
//      the strip really is what stands between this site and the hardware.
//
// PROVEN ABLE TO FAIL — verified by temporarily reverting the fix:
//   `kGeometryKeys = ['start', 'stop']`  (i.e. the pre-a356b5f fence)
//     → B fails: seg[1] still carries `rev: false` at the wire.
//     → C fails: no assert is thrown; the leak walks through, exactly as it
//       did on the bench.
// Both were re-greened by restoring `['start', 'stop', 'rev', 'mi']`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/services/foreground_celebration_providers.dart';
import 'package:nexgen_command/features/wled/geometry_wire_pin.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// TONIGHT'S EXACT BENCH SHAPE (.150, 2026-08-18).
///
/// A real `/json/state` readback: two channels, seg 0 spanning 0–290 (the
/// post-reboot collapse boundary), Chiefs red/gold in `col` from the
/// celebration that had just run, `ps: -1` so the revert takes the seg-restore
/// branch (not the preset branch), and — the whole point — `rev: false` on
/// seg 1, which is the value the revert re-stamped over a manual restore twice
/// in one evening.
///
/// `len` is present deliberately: it is the key the fence deliberately does
/// NOT cover, and it must still be here afterwards or the fence has
/// over-reached.
Map<String, dynamic> benchState({bool seg1Reversed = false}) => {
      'on': true,
      'bri': 128,
      'ps': -1,
      'transition': 7,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': 291,
          'len': 291,
          'grp': 1,
          'spc': 0,
          'of': 0,
          'on': true,
          'frz': false,
          'bri': 255,
          'cct': 127,
          'col': [
            [227, 24, 55, 0], // 0xFFE31837 — Chiefs red
            [255, 184, 28, 0], // 0xFFFFB81C — Chiefs gold
            [0, 0, 0, 0],
          ],
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'pal': 5,
          'sel': true,
          'rev': false,
          'mi': false,
        },
        {
          'id': 1,
          'start': 291,
          'stop': 441,
          'len': 150,
          'grp': 1,
          'spc': 0,
          'of': 0,
          'on': true,
          'frz': false,
          'bri': 255,
          'cct': 127,
          'col': [
            [255, 184, 28, 0],
            [227, 24, 55, 0],
            [0, 0, 0, 0],
          ],
          'fx': 63,
          'sx': 200,
          'ix': 96,
          'pal': 0,
          'sel': false,
          // THE INCIDENT VALUE. `false` is what the coordinator captured and
          // what every celebration cycle then re-asserted — including over the
          // user's manual restore.
          'rev': seg1Reversed,
          'mi': false,
        },
      ],
    };

/// Fake controller for the celebration delivery.
///
/// Extends [WledService] on the `mock` host (simulation mode) rather than
/// implementing the bare interface, so that with [routeToWire] set the
/// un-stubbed `applyJson` → `normalizeWledPayload` → `expandForParticipation`
/// → `_postJson` → `pinNoGeometryOnWire` chain is the REAL one. Nothing about
/// the fence is re-implemented here.
class _BenchService extends WledService {
  _BenchService(this.snapshot, {this.routeToWire = false}) : super('http://mock');

  final Map<String, dynamic> snapshot;

  /// false → record the payload and stop (the pre-strip TAP POINT).
  /// true  → record it and hand it to the real wire (the real EXIT).
  final bool routeToWire;

  final List<Map<String, dynamic>> applied = [];

  @override
  Future<Map<String, dynamic>?> getState() async => snapshot;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applied.add(payload);
    if (routeToWire) return super.applyJson(payload);
    return true;
  }
}

/// Exposes the container's Ref so [WledCelebrationDelivery] can be built.
final _refProvider = Provider<Ref>((ref) => ref);

({ProviderContainer container, WledCelebrationDelivery delivery})
    _harness(_BenchService repo) {
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  return (
    container: container,
    delivery: WledCelebrationDelivery(container.read(_refProvider)),
  );
}

Map<String, dynamic> _seg(Map<String, dynamic> payload, int index) =>
    Map<String, dynamic>.from((payload['seg'] as List)[index] as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // `applyJson` warms the participation cache from SharedPreferences. Empty
    // → null → `expandForParticipation` passes the payload through unchanged,
    // which is what we want: the seg array must reach the pin untouched.
    SharedPreferences.setMockInitialValues({});
  });

  group('WledCelebrationDelivery capture→revert: the payload that reaches the '
      'wire is geometry-free (a356b5f §2)', () {
    test('A+B — tonight\'s exact bench shape: revert replays geometry, the '
        'wire strips it, and the LOOK survives intact', () async {
      final repo = _BenchService(benchState());
      final h = _harness(repo);

      // Drive the real site, both halves.
      final captured = await h.delivery.capture();
      expect(captured, isNotNull,
          reason: 'capture() is repo.getState() — the full /json/state');
      await h.delivery.revert(captured!);

      expect(repo.applied, hasLength(1),
          reason: 'ps:-1 → the seg-restore branch, one applyJson');
      final raw = repo.applied.single;

      // ── A. THE TAP POINT (pre-strip) ─────────────────────────────────────
      // This is the assertion that makes B mean something. The site hands the
      // repository a payload that DOES state geometry; the fence is the only
      // thing between it and the hardware.
      //
      // Asserted with raw `containsKey`, NOT `findGeometryViolations` — the
      // tap point must be independent of the fence it is testing, or a
      // narrowed `kGeometryKeys` would fail here and mask the wire regression
      // in B, which is where it belongs.
      //
      // If this ever fails because the revert was changed to field-select
      // (the shape refine_roofline_screen.dart:118 already uses), that is a
      // WIN — but collapse this test to B deliberately rather than deleting
      // the assertion, or B goes vacuous without anyone noticing.
      for (final i in [0, 1]) {
        final s = _seg(raw, i);
        expect(
          ['start', 'stop', 'rev', 'mi'].where(s.containsKey).toList(),
          ['start', 'stop', 'rev', 'mi'],
          reason: 'seg[$i]: the captured array is replayed VERBATIM — every '
              'geometry key the controller echoed is handed to applyJson',
        );
      }
      expect(_seg(raw, 1)['rev'], false,
          reason: 'THE incident value, re-stamped over a manual restore twice '
              'on the bench');

      // ── B. THE WIRE (post-strip) ─────────────────────────────────────────
      // stripGeometry is the production release-path function; what it emits
      // is what the controller receives.
      final wire = stripGeometry(raw);
      expect(findGeometryViolations(wire), isEmpty,
          reason: 'nothing stating segment geometry reaches the controller');

      for (final i in [0, 1]) {
        final s = _seg(wire, i);
        // Geometry: gone. Bounds AND orientation.
        expect(s.containsKey('start'), isFalse, reason: 'seg[$i] start');
        expect(s.containsKey('stop'), isFalse, reason: 'seg[$i] stop');
        expect(s.containsKey('rev'), isFalse,
            reason: 'seg[$i] rev — a restore must not re-assert DIRECTION');
        expect(s.containsKey('mi'), isFalse, reason: 'seg[$i] mi');
        // Look: intact. The revert still restores what the user was looking at.
        expect(s['id'], i);
        expect(s['on'], isTrue);
        expect(s['col'], _seg(benchState(), i)['col']);
        expect(s['fx'], _seg(benchState(), i)['fx']);
        expect(s['pal'], _seg(benchState(), i)['pal']);
        expect(s['sx'], _seg(benchState(), i)['sx']);
        expect(s['ix'], _seg(benchState(), i)['ix']);
        expect(s['bri'], 255);
        // NOT over-fenced: len is deliberately exempt (WLED echoes it in every
        // readback and it cannot move a boundary on its own).
        expect(s['len'], _seg(benchState(), i)['len'],
            reason: 'len stays — the fence covers geometry, not every echo');
      }

      // Root fields the revert restores are untouched by the fence.
      expect(wire['on'], isTrue);
      expect(wire['bri'], 128);
    });

    test('A+B — the MIRRORED case: a genuinely reversed channel is not '
        're-asserted either', () async {
      // The damaging direction. Where seg 1 IS reversed (an installer-set
      // orientation), replaying rev:true re-provisions direction from a stale
      // snapshot just as surely as replaying rev:false cleared it.
      final repo = _BenchService(benchState(seg1Reversed: true));
      final h = _harness(repo);

      await h.delivery.revert((await h.delivery.capture())!);

      final raw = repo.applied.single;
      expect(_seg(raw, 1)['rev'], true,
          reason: 'pre-strip tap point — fence-independent');

      final wire = stripGeometry(raw);
      expect(_seg(wire, 1).containsKey('rev'), isFalse,
          reason: 'orientation is provisioning\'s in EITHER direction (#76)');
      expect(_seg(wire, 1)['fx'], 63, reason: 'the LOOK still survives');
    });

    test('C — driven against the REAL wire exit, the pin fires and names rev',
        () async {
      // No applyJson stub: normalizeWledPayload → expandForParticipation →
      // _postJson → pinNoGeometryOnWire, the real chain. In debug/test the pin
      // asserts; in release it strips (which is what B measures). This is the
      // proof that B is the behaviour on the actual path, not a bench-side
      // simulation of it.
      final repo = _BenchService(benchState(), routeToWire: true);
      final h = _harness(repo);
      final captured = await h.delivery.capture();

      await expectLater(
        h.delivery.revert(captured!),
        throwsA(isA<AssertionError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(
            contains('GEOMETRY ON THE WIRE (local)'),
            // The ENUMERATED keys, not the report's static prose — the
            // boilerplate says "start/stop/rev/mi" regardless of what the
            // fence actually caught, so `contains('rev')` alone would pass
            // against a fence that had never looked at rev.
            contains('seg[0](id=0):start+stop+rev+mi'),
            contains('seg[1](id=1):start+stop+rev+mi'),
          ),
        )),
        reason: 'the celebration revert reaches the real wire pin carrying '
            'orientation — this is the leak that ran nightly under a live pin',
      );
    });

    test('the preset branch was never exposed — ps>=0 replays no seg at all',
        () async {
      // Guard against a "fix" that routes everything through the seg branch.
      final repo = _BenchService({...benchState(), 'ps': 3});
      final h = _harness(repo);

      await h.delivery.revert((await h.delivery.capture())!);

      expect(repo.applied.single, {'ps': 3});
      expect(findGeometryViolations(repo.applied.single), isEmpty);
    });
  });
}
