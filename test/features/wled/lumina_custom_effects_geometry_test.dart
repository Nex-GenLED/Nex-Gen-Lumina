// +80 REPRO PIN — the Lumina custom-effects catalog vs the geometry contract.
//
// WHAT THIS PINS. Three of the four bounds-animated builders in
// `lumina_custom_effects.dart` carry their entire animation in `start`/`stop`:
// the "motion" IS a segment boundary sweeping across the strip. Under the +80
// wire pin those bounds are stripped, so the builders cannot destroy geometry —
// this test is the executable statement of both halves: the raw frame really
// does state the destroying shape, AND the pin really does neutralise it.
//
// ── THE BUILDERS ARE CURRENTLY DEAD. TWO INDEPENDENT GATES. ─────────────────
//
//   1. `LuminaCustomEffectsCatalog.isCustomEffect(int id) => false`
//      (lumina_custom_effects.dart:325) — hardcoded. Every dispatch site
//      (`pattern_repository.dart:255`, `pattern_explore_screen.dart:33`) asks
//      this first, so no id ever routes to a custom effect.
//   2. `LuminaEffectController._isRunning` is initialised false and assigned
//      false; there is NO `_isRunning = true` anywhere in the file.
//
// So the +79 field destruction was NOT these builders — the catalog is
// unreachable on +79 and there is no field exposure. They are pinned anyway,
// because dead code that states geometry is a loaded gun pointed at the next
// person who re-enables it.
//
// **STANDING CONSTRAINT: do not re-enable the custom-effects catalog without
// the wire pin in place.** Flipping `isCustomEffect` to a real lookup without
// the pin re-arms the exact class that destroyed the bench layout. The pin is
// the PRECONDITION for re-enabling, not a nice-to-have alongside it. See #103.
//
// The expectations below reference the SAME SegmentShape the healer suite uses
// for the +79 collapsed state (`geometry_connect_heal_test.dart`), so the two
// tests describe one incident in one vocabulary.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/wled/geometry_wire_pin.dart';
import 'package:nexgen_command/features/wled/lumina_custom_effects.dart';

/// The bench strip: bus0 128 + bus1 162.
const int kTotal = 290;

/// The bench's TRUE layout, from its own buses — what must survive.
const benchShape = <SegmentShape>[
  SegmentShape(0, 0, 128),
  SegmentShape(1, 128, 290),
];

/// The +79 collapsed state: seg 1 gone, seg 0 re-bound across the whole strip.
/// Identical to the constant the healer suite drifts against.
const collapsedShape = <SegmentShape>[SegmentShape(0, 0, 290)];

/// Read a payload's seg array as SegmentShapes — only entries that STATE bounds.
List<SegmentShape> shapeOf(Map<String, dynamic> payload) {
  final seg = payload['seg'];
  if (seg is! List) return const [];
  return [
    for (final s in seg)
      if (s is Map && s['start'] is int && s['stop'] is int)
        SegmentShape(s['id'] as int, s['start'] as int, s['stop'] as int),
  ];
}

void main() {
  final c = LuminaEffectController();
  const colors = [
    [0, 128, 255, 0]
  ];

  group('1001 Rising Tide — the final frame IS the +79 collapsed state', () {
    late Map<String, dynamic> finalFrame;

    setUp(() {
      final frames = c.generateRisingTideFrames(
          colors: colors, totalPixels: kTotal, steps: 20);
      finalFrame = frames.last;
    });

    test('RAW: states {id:0, start:0, stop:290} and OMITS seg 1', () {
      final seg = finalFrame['seg'] as List;

      // Seg 1's guard (`clampedPixels < totalPixels`) goes false on the last
      // frame, so it is dropped entirely — and seg 0 spans the whole strip.
      expect(seg, hasLength(1),
          reason: 'seg 1 is omitted on the final frame — this is what leaves '
              'half the strip holding frame 19\'s black');
      expect((seg.single as Map)['id'], 0);
      expect((seg.single as Map)['start'], 0);
      expect((seg.single as Map)['stop'], kTotal);

      // The shape this frame states is EXACTLY the +79 collapsed state.
      expect(shapeOf(finalFrame), collapsedShape,
          reason: 'the raw builder output re-bounds seg 0 across the strip, '
              'which is what swallowed seg 1 and its rev:true on the bench');
      expect(shapeOf(finalFrame), isNot(benchShape));
    });

    test('PINNED: the pin neutralises it — no bounds survive', () {
      expect(findGeometryViolations(finalFrame), isNotEmpty,
          reason: 'precondition: the raw frame must actually violate, or this '
              'test proves nothing');

      final pinned = stripGeometry(finalFrame);

      expect(findGeometryViolations(pinned), isEmpty);
      expect(shapeOf(pinned), isEmpty,
          reason: 'a pinned frame states NO geometry at all');
      // The LOOK survives — only the SHAPE is removed.
      final seg = (pinned['seg'] as List).single as Map;
      expect(seg['id'], 0);
      expect(seg['fx'], 0);
      expect(seg['col'], colors);
      expect(seg['on'], true);
    });

    test('every frame violates raw, and none violate pinned', () {
      final frames = c.generateRisingTideFrames(
          colors: colors, totalPixels: kTotal, steps: 20);
      expect(frames, hasLength(20));
      for (var i = 0; i < frames.length; i++) {
        expect(findGeometryViolations(frames[i]), isNotEmpty,
            reason: 'raw frame ${i + 1} must state bounds');
        expect(findGeometryViolations(stripGeometry(frames[i])), isEmpty,
            reason: 'pinned frame ${i + 1} must not');
      }
    });
  });

  group('1002 Falling Tide — the reverse path (reverse: true)', () {
    test('RAW states bounds; PINNED does not', () {
      final frames = c.generateRisingTideFrames(
        colors: colors,
        totalPixels: kTotal,
        steps: 20,
        reverse: true,
      );

      for (final f in frames) {
        expect(findGeometryViolations(f), isNotEmpty);
        expect(findGeometryViolations(stripGeometry(f)), isEmpty);
      }

      // The reverse path sweeps seg 0's START rather than its stop, so its
      // frames re-bound seg 0 from the far end — a different motion, the same
      // violation class.
      final first = frames.first['seg'] as List;
      expect((first.first as Map)['stop'], kTotal);
    });
  });

  group('1005 Grand Reveal — SWEEP FINDING: zero-length final segments', () {
    test('the last frame emits [0,0) and [290,290) — segments as "nonexistent"',
        () {
      final frames = c.generateGrandRevealFrames(
          colors: colors, totalPixels: kTotal, steps: 20);
      final seg = frames.last['seg'] as List;
      final byId = {
        for (final s in seg) (s as Map)['id'] as int: s,
      };

      // spread == center on the final frame ⇒ leftEnd 0, rightStart 290.
      expect(byId[0]!['start'], 0);
      expect(byId[0]!['stop'], 0, reason: 'seg 0 is ZERO-LENGTH');
      expect(byId[2]!['start'], kTotal);
      expect(byId[2]!['stop'], kTotal, reason: 'seg 2 is ZERO-LENGTH');

      // A zero-length bound is precisely what applyChannelFilter's Rule 1
      // forbids: "Channel unused" is {id, on:false} and NOTHING else — never a
      // zero-length [0,0) bound, which reads as "this channel does not exist".
      expect(findGeometryViolations(frames.last), isNotEmpty);
      expect(findGeometryViolations(stripGeometry(frames.last)), isEmpty);
    });
  });

  group('1006 Curtain Call — SWEEP FINDING: a split that matches no bus', () {
    test('terminal state re-bounds to 0-145/145-290, not the real 0-128/128-290',
        () {
      final frames = c.generateGrandRevealFrames(
        colors: colors,
        totalPixels: kTotal,
        steps: 20,
        closing: true,
      );
      final seg = frames.last['seg'] as List;
      final byId = {
        for (final s in seg) (s as Map)['id'] as int: s,
      };

      // center = totalPixels ~/ 2 = 145. Derived from PIXEL COUNT, not from bus
      // boundaries — so a device whose real split is 128 gets re-bound to 145.
      expect(byId[0]!['stop'], 145);
      expect(byId[2]!['start'], 145);
      expect(byId[0]!['stop'], isNot(128),
          reason: 'the bench\'s real boundary is 128; this states 145');

      expect(findGeometryViolations(frames.last), isNotEmpty);
      expect(findGeometryViolations(stripGeometry(frames.last)), isEmpty);
    });
  });

  group('1007 Ocean Swell — the one builder that is already contract-clean', () {
    test('states no bounds raw, so the pin is a no-op for it', () {
      final frames =
          c.generateOceanSwellFrames(colors: colors, totalPixels: kTotal);
      expect(frames, isNotEmpty);
      for (final f in frames) {
        expect(findGeometryViolations(f), isEmpty,
            reason: 'Ocean Swell animates colour/phase, not boundaries — it '
                'needs no redesign and is excluded from #103');
      }
      expect(identical(stripGeometry(frames.first), frames.first), isTrue);
    });
  });

  group('the dead gates — pinned so a re-enable is a DELIBERATE act', () {
    test('isCustomEffect is hardcoded false: the catalog is unreachable', () {
      for (final id in [1001, 1002, 1003, 1004, 1005, 1006, 1007]) {
        expect(LuminaCustomEffectsCatalog.isCustomEffect(id), isFalse,
            reason: 'if this fails the catalog has been RE-ENABLED — confirm '
                'the wire pin is in place before shipping (#103)');
      }
    });

    test('a fresh controller is not running', () {
      expect(LuminaEffectController().isRunning, isFalse);
    });
  });
}
