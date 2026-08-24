// Scheduling V3 D3 — the ONE satisfaction predicate.
//
// `presetSatisfies(stored, builderOutput)` replaces four hand-written
// predicates. The bar for a preset is now the builder's own output, so a
// predicate cannot describe "correct" differently from the code that writes it
// — the split that made the `ib:true` fix inert on the entire installed fleet.
//
// The existing 18 tests in base_ladder_repair_test.dart run against the same
// implementation through the retained adapters, and are the regression net for
// the all-channel path.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

Map<String, dynamic> live4() => {
      'seg': [for (var i = 0; i < 4; i++) {'id': i, 'on': true}],
    };

/// What a controller returns for a healthy all-channel ON ladder preset:
/// the name, root on, per-segment on — and NO `ib` (never stored).
Map<String, dynamic> storedHealthyOn(String name, {int segs = 4}) => {
      'n': name,
      'on': true,
      'bri': 200,
      'seg': [for (var i = 0; i < segs; i++) {'id': i, 'on': true}],
    };

void main() {
  group('all-channel behaviour is unchanged', () {
    test('a healthy ON ladder preset is satisfied', () {
      expect(
        ScheduleSyncService.presetSatisfies(
          storedHealthyOn('NGL On'),
          ScheduleSyncService.buildNglOnPresetState(200, live4()),
          expectedName: 'NGL On',
        ),
        isTrue,
      );
    });

    test('a preset missing root `on` is UNSATISFIED — the ib:true regression',
        () {
      final noRoot = storedHealthyOn('NGL On')..remove('on');
      expect(
        ScheduleSyncService.presetSatisfies(
          noRoot,
          ScheduleSyncService.buildNglOnPresetState(200, live4()),
          expectedName: 'NGL On',
        ),
        isFalse,
        reason: 'every controller commissioned before 9158c00 is in this state; '
            'the old name-only predicate skipped them forever',
      );
    });

    test('a wrong name is unsatisfied', () {
      expect(
        ScheduleSyncService.presetSatisfies(
          storedHealthyOn('Something Else'),
          ScheduleSyncService.buildNglOnPresetState(200, live4()),
          expectedName: 'NGL On',
        ),
        isFalse,
      );
    });

    test('a segment the controller LACKS is tolerated — silence is not '
        'contradiction', () {
      // The legacy segments-absent shape: live has 4, the preset stored 1.
      // This is preset 2/3/4/5/10/11 on the bench rig today (U-7), and on a
      // large share of the fleet.
      //
      // ⚠️ DELIBERATE, AND IT COST A REVERT TO GET RIGHT. The first version of
      // this predicate returned false here — strictly more correct, since such
      // a preset provably does not control the missing segment. But the old
      // `_presetAllSegmentsOn` never counted segments, so tightening it would
      // start a fleet-wide ladder repair on the next sync, with a visible flash
      // per controller (psave applies live). That is a real change to what
      // customers' houses do, and it is not this change's to make. Behaviour
      // preserved exactly; the strictness is opt-in via
      // requireAllExpectedSegments, which only scoped intents set.
      expect(
        ScheduleSyncService.presetSatisfies(
          storedHealthyOn('NGL On', segs: 1),
          ScheduleSyncService.buildNglOnPresetState(200, live4()),
          expectedName: 'NGL On',
        ),
        isTrue,
      );
    });

    test('…but a SCOPED intent requires every segment to be stated', () {
      // For a scope, a missing segment means the exclusion was never written,
      // and psave will have captured whatever the controller was showing (U-7).
      // So here silence IS contradiction.
      expect(
        ScheduleSyncService.presetSatisfies(
          storedHealthyOn('NGL On', segs: 1),
          ScheduleSyncService.buildNglOnPresetState(200, live4(),
              channels: const [1]),
          expectedName: 'NGL On',
          requireAllExpectedSegments: true,
        ),
        isFalse,
      );
    });

    test('an all-segments-off ON preset is damage — unchanged', () {
      final damaged = storedHealthyOn('NGL On');
      for (final s in damaged['seg'] as List) {
        (s as Map)['on'] = false;
      }
      expect(
        ScheduleSyncService.presetSatisfies(
          damaged,
          ScheduleSyncService.buildNglOnPresetState(200, live4()),
          expectedName: 'NGL On',
        ),
        isFalse,
      );
    });

    test('preset 2 keeps its OWN bar automatically', () {
      // The standing warning is that preset 2 must not be judged by the ON
      // ladder's all-segments-ON rule. Comparing against its own builder gives
      // it its own bar with no special case.
      final storedOff = {
        'n': 'NGL Off',
        'on': false,
        'seg': [for (var i = 0; i < 4; i++) {'id': i, 'on': false}],
      };
      expect(
        ScheduleSyncService.presetSatisfies(
          storedOff,
          ScheduleSyncService.buildNglOffPresetState(live4()),
          expectedName: 'NGL Off',
        ),
        isTrue,
      );
      // …and the same stored def fails the ON bar, as it must.
      expect(
        ScheduleSyncService.presetSatisfies(
          storedOff,
          ScheduleSyncService.buildNglOnPresetState(200, live4()),
          expectedName: 'NGL Off',
        ),
        isFalse,
      );
    });
  });

  group('the two deliberate exclusions', () {
    test('`ib` is never asserted — it is a request flag, never stored', () {
      final stored = storedHealthyOn('NGL On');
      expect(stored.containsKey('ib'), isFalse);
      final expectedState =
          ScheduleSyncService.buildNglOnPresetState(200, live4());
      expect(expectedState['ib'], true, reason: 'the builder does set it');
      expect(
        ScheduleSyncService.presetSatisfies(stored, expectedState,
            expectedName: 'NGL On'),
        isTrue,
        reason: 'asserting ib would mark every preset on every controller broken',
      );
    });

    test('`bri` drift does NOT trigger a re-save', () {
      final drifted = storedHealthyOn('NGL On')..['bri'] = 199;
      expect(
        ScheduleSyncService.presetSatisfies(
          drifted,
          ScheduleSyncService.buildNglOnPresetState(200, live4()),
          expectedName: 'NGL On',
        ),
        isTrue,
        reason: 'psave APPLIES live — a re-save is a visible flash on the '
            "customer's house, and brightness drift is cosmetic",
      );
    });

    test('compareSegments:false is the base-ladder-repair kill switch', () {
      final damaged = storedHealthyOn('NGL On');
      for (final s in damaged['seg'] as List) {
        (s as Map)['on'] = false;
      }
      expect(
        ScheduleSyncService.presetSatisfies(
          damaged,
          ScheduleSyncService.buildNglOnPresetState(200, live4()),
          expectedName: 'NGL On',
          compareSegments: false,
        ),
        isTrue,
        reason: 'flag OFF ⇒ segments are not judged, so no repair is triggered',
      );
    });
  });

  group('SCOPED presets — the healer leaves them alone', () {
    test('a scoped preset matching its intent needs NO repair', () {
      // Channel 1 only: seg 1 on, everything else off.
      final expectedState = ScheduleSyncService.buildNglOnPresetState(
          200, live4(),
          channels: const [1]);
      final storedScoped = {
        'n': 'NGL On',
        'on': true,
        'seg': [
          {'id': 0, 'on': false},
          {'id': 1, 'on': true},
          {'id': 2, 'on': false},
          {'id': 3, 'on': false},
        ],
      };
      expect(
        ScheduleSyncService.presetSatisfies(storedScoped, expectedState,
            expectedName: 'NGL On'),
        isTrue,
        reason: 'THE F2-3 FIX: this exact preset used to be called damage and '
            'overwritten back to all-on',
      );
    });

    test('an all-on controller preset does NOT satisfy a scoped intent — '
        'it repairs to the scoped shape', () {
      expect(
        ScheduleSyncService.presetSatisfies(
          storedHealthyOn('NGL On'), // all four on
          ScheduleSyncService.buildNglOnPresetState(200, live4(),
              channels: const [1]),
          expectedName: 'NGL On',
        ),
        isFalse,
      );
    });

    test('a scoped preset does NOT satisfy an all-channel intent', () {
      final storedScoped = {
        'n': 'NGL On',
        'on': true,
        'seg': [
          {'id': 0, 'on': false},
          {'id': 1, 'on': true},
          {'id': 2, 'on': false},
          {'id': 3, 'on': false},
        ],
      };
      expect(
        ScheduleSyncService.presetSatisfies(
          storedScoped,
          ScheduleSyncService.buildNglOnPresetState(200, live4()),
          expectedName: 'NGL On',
        ),
        isFalse,
        reason: 'removing a scope must repair the preset back to full strip',
      );
    });

    test('a scoped OFF only judges the segments it named', () {
      final expectedState = ScheduleSyncService.buildNglOffPresetState(live4(),
          channels: const [1]);
      // The controller holds seg 1 off and the others ON — which is exactly
      // what a scoped OFF should leave behind.
      final stored = {
        'n': 'NGL Off',
        'seg': [
          {'id': 0, 'on': true},
          {'id': 1, 'on': false},
          {'id': 2, 'on': true},
          {'id': 3, 'on': true},
        ],
      };
      expect(
        ScheduleSyncService.presetSatisfies(stored, expectedState,
            expectedName: 'NGL Off'),
        isTrue,
        reason: 'a scoped OFF must not care what the other channels are doing',
      );
    });
  });

  group('bounds are never asserted', () {
    test('a preset saved with sb:true still satisfies', () {
      final withBounds = {
        'n': 'NGL On',
        'on': true,
        'seg': [
          for (var i = 0; i < 4; i++)
            {'id': i, 'on': true, 'start': i * 10, 'stop': (i + 1) * 10}
        ],
      };
      expect(
        ScheduleSyncService.presetSatisfies(
          withBounds,
          ScheduleSyncService.buildNglOnPresetState(200, live4()),
          expectedName: 'NGL On',
        ),
        isTrue,
        reason: 'bounds are provisioning\'s — the Item-#82 wrong-range stomp',
      );
    });
  });
}
