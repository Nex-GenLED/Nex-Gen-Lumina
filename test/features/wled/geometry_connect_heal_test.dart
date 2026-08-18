// +80 — the CONNECT-TIME geometry check.
//
// The gap this closes, stated once: before +80 every geometry-repair call site
// sat inside a PRESET-SAVE path. `_healOnPresetMasterPower` reached the gate
// only after `if (broken.isEmpty) return;`; ScheduleSync reached it only when a
// preset actually needed writing. So the repair machinery existed with NO
// TRIGGER of its own — a controller that booted collapsed but had healthy
// presets stayed collapsed indefinitely, and did, for ~30 minutes on the bench
// with the app connected the whole time.
//
// The gate was a GUARD ON PSAVE. This is the HEALER.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';

void main() {
  // The bench's true layout, from its own buses (hw.led.ins):
  //   bus0 start=0 len=128   → seg 0 [0,128)
  //   bus1 start=128 len=162 → seg 1 [128,290)
  const bench = <SegmentShape>[
    SegmentShape(0, 0, 128),
    SegmentShape(1, 128, 290),
  ];

  group('decideGeometryHeal', () {
    test('THE +79 FIELD STATE — collapsed to one full-strip seg → DRIFTED', () {
      // Exactly what /json/state showed after the destroying apply: seg 1 gone,
      // seg 0 re-bound across the whole strip.
      const collapsed = <SegmentShape>[SegmentShape(0, 0, 290)];

      expect(
        decideGeometryHeal(expected: bench, live: collapsed),
        GeometryHealVerdict.drifted,
      );
    });

    test('THE BOOT STATE — reboot collapses 2 segments into 1 → DRIFTED', () {
      // The documented reboot behaviour: seg0 spans the strip, no seg1 until a
      // preset reloads. This is the case that sat unrepaired for 30 minutes.
      expect(
        decideGeometryHeal(
          expected: bench,
          live: const [SegmentShape(0, 0, 290)],
        ),
        GeometryHealVerdict.drifted,
      );
    });

    test('matching layout → HEALTHY, so a healthy controller gets zero writes',
        () {
      expect(
        decideGeometryHeal(expected: bench, live: bench),
        GeometryHealVerdict.healthy,
      );
    });

    test('a single moved boundary is drift, not noise', () {
      expect(
        decideGeometryHeal(
          expected: bench,
          live: const [SegmentShape(0, 0, 130), SegmentShape(1, 130, 290)],
        ),
        GeometryHealVerdict.drifted,
      );
    });

    test('an EXTRA segment is drift too', () {
      expect(
        decideGeometryHeal(
          expected: bench,
          live: const [
            SegmentShape(0, 0, 128),
            SegmentShape(1, 128, 290),
            SegmentShape(2, 290, 400),
          ],
        ),
        GeometryHealVerdict.drifted,
      );
    });

    group('stands aside on IGNORANCE — never repairs a suspicion', () {
      test('unreadable buses (empty expectation) → STAND ASIDE', () {
        expect(
          decideGeometryHeal(expected: const [], live: bench),
          GeometryHealVerdict.standAside,
          reason: 'a controller we cannot describe must not be re-provisioned',
        );
      });

      test('unreadable live state (null) → STAND ASIDE', () {
        expect(
          decideGeometryHeal(expected: bench, live: null),
          GeometryHealVerdict.standAside,
          reason: 'one flaky /json/state read must not trigger a repair',
        );
      });

      test('live read returned no segments (empty) → STAND ASIDE', () {
        expect(
          decideGeometryHeal(expected: bench, live: const []),
          GeometryHealVerdict.standAside,
        );
      });

      test('both unavailable → STAND ASIDE', () {
        expect(
          decideGeometryHeal(expected: const [], live: null),
          GeometryHealVerdict.standAside,
        );
      });
    });

    test('single-channel installs are healthy when they match', () {
      const single = <SegmentShape>[SegmentShape(0, 0, 300)];
      expect(
        decideGeometryHeal(expected: single, live: single),
        GeometryHealVerdict.healthy,
        reason: 'a 1-bus device whose one segment spans the strip is CORRECT — '
            'the +79 bug was a 2-bus device collapsing, not a wide segment',
      );
    });
  });

  group('ControllerHealReport surfaces the repair', () {
    test('geometryReprovisioned counts as a heal and names itself', () {
      final r = ControllerHealReport()..geometryReprovisioned = true;
      expect(r.anyHealed, isTrue);
      expect(r.toString(), contains('geometry'));
    });

    test('a no-op report still reads as no-op', () {
      expect(ControllerHealReport().toString(), 'no-op');
      expect(ControllerHealReport().anyHealed, isFalse);
    });
  });
}
