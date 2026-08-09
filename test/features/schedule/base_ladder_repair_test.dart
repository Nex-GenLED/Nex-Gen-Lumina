// Base-ladder segment repair — audit/BASE_LADDER.md §6.
//
// The defect: ON ladder presets (1/3/4/5) were psaved with no `seg` key, so the
// save captured ambient segment state and stored a permanently-dark base layer.
// The fix is TWO changes that must ship together — an explicit `seg` in the
// payload AND a predicate that can see the damage. Either alone is inert.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

/// A stored preset def as `/presets.json` returns it.
Map<String, dynamic> def({
  required String name,
  bool? on,
  int? bri,
  List<Map<String, dynamic>>? seg,
}) =>
    <String, dynamic>{
      'n': name,
      if (on != null) 'on': on,
      if (bri != null) 'bri': bri,
      if (seg != null) 'seg': seg,
    };

Map<String, dynamic> liveState(List<int> segIds, {bool on = true}) =>
    <String, dynamic>{
      'on': on,
      'seg': [for (final id in segIds) {'id': id, 'on': on}],
    };

void main() {
  group('buildNglOnPresetState — the payload half', () {
    test('writes an explicit seg entry for every live segment', () {
      final s = ScheduleSyncService.buildNglOnPresetState(200, liveState([0, 1]));
      expect(s['on'], isTrue);
      expect(s['bri'], 200);
      expect(s['ib'], isTrue, reason: 'ib persists root on/bri into the preset');
      expect(s['seg'], [
        {'id': 0, 'on': true},
        {'id': 1, 'on': true},
      ]);
    });

    test('THE DEFECT: seg is never omitted, so psave cannot capture ambient '
        'state', () {
      for (final live in [
        liveState([0, 1], on: false), // house dark at save time
        liveState([0, 1, 2]),
        null,
      ]) {
        final s = ScheduleSyncService.buildNglOnPresetState(51, live);
        expect(s.containsKey('seg'), isTrue);
        final seg = s['seg'] as List;
        expect(seg, isNotEmpty);
        expect(seg.every((e) => (e as Map)['on'] == true), isTrue,
            reason: 'a dark house at save time must NOT produce a dark preset');
      }
    });

    test('writes no bounds — a resized channel is never re-bounded (P1-42)', () {
      final s = ScheduleSyncService.buildNglOnPresetState(102, liveState([0, 1]));
      for (final e in s['seg'] as List) {
        expect((e as Map).containsKey('start'), isFalse);
        expect(e.containsKey('stop'), isFalse);
      }
    });

    test('degrades to a single on-segment when live state is unavailable', () {
      final s = ScheduleSyncService.buildNglOnPresetState(153, null);
      expect(s['seg'], [
        {'on': true}
      ]);
    });
  });

  group('isNglOnPresetSatisfied — the predicate half', () {
    test('DAMAGED ladder (all segments off) is UNSATISFIED → gets repaired', () {
      final damaged = def(name: 'NGL On', on: true, bri: 200, seg: [
        {'id': 0, 'on': false},
        {'id': 1, 'on': false},
      ]);
      expect(ScheduleSyncService.isNglOnPresetSatisfied(damaged, 'NGL On'),
          isFalse);
    });

    test('CORRECT ladder is SATISFIED → left alone, no needless psave', () {
      final healthy = def(name: 'NGL On', on: true, bri: 200, seg: [
        {'id': 0, 'on': true},
        {'id': 1, 'on': true},
      ]);
      expect(
          ScheduleSyncService.isNglOnPresetSatisfied(healthy, 'NGL On'), isTrue);
    });

    test('PARTIAL damage (one segment dark) is UNSATISFIED', () {
      final partial = def(name: 'NGL Dim', on: true, bri: 51, seg: [
        {'id': 0, 'on': true},
        {'id': 1, 'on': false},
      ]);
      expect(ScheduleSyncService.isNglOnPresetSatisfied(partial, 'NGL Dim'),
          isFalse);
    });

    test('legacy segments-absent preset is UNSATISFIED', () {
      expect(
        ScheduleSyncService.isNglOnPresetSatisfied(
            def(name: 'NGL Low', on: true, bri: 102), 'NGL Low'),
        isFalse,
      );
    });

    test('still enforces the ib:true master bar (9158c00 must not regress)', () {
      final noRoot = def(name: 'NGL On', bri: 200, seg: [
        {'id': 0, 'on': true},
      ]);
      expect(
          ScheduleSyncService.isNglOnPresetSatisfied(noRoot, 'NGL On'), isFalse);
    });

    test('wrong name is UNSATISFIED regardless of segments', () {
      final wrong = def(name: 'Warm White', on: true, bri: 200, seg: [
        {'id': 0, 'on': true},
      ]);
      expect(
          ScheduleSyncService.isNglOnPresetSatisfied(wrong, 'NGL On'), isFalse);
    });
  });

  group('the kill switch', () {
    final damaged = def(name: 'NGL On', on: true, bri: 200, seg: [
      {'id': 0, 'on': false},
      {'id': 1, 'on': false},
    ]);

    test('repairSegments:false restores the PRE-REPAIR behaviour exactly', () {
      expect(
        ScheduleSyncService.isNglOnPresetSatisfied(damaged, 'NGL On',
            repairSegments: false),
        isTrue,
        reason: 'switched off, a damaged preset is skipped as it was before',
      );
    });

    test('repairSegments:false still enforces root on — the switch disables '
        'ONLY the segment assertion', () {
      final noRoot = def(name: 'NGL On', bri: 200, seg: [
        {'id': 0, 'on': false},
      ]);
      expect(
        ScheduleSyncService.isNglOnPresetSatisfied(noRoot, 'NGL On',
            repairSegments: false),
        isFalse,
      );
    });

    test('defaults to ON when the argument is omitted', () {
      expect(ScheduleSyncService.isNglOnPresetSatisfied(damaged, 'NGL On'),
          isFalse);
    });
  });

  group('idempotency — two syncs produce identical presets', () {
    test('the built state satisfies its own predicate', () {
      for (final e in ScheduleSyncService.kOnPresetSpecs.entries) {
        final built = ScheduleSyncService
            .buildNglOnPresetState(e.value.bri, liveState([0, 1]));
        // What WLED stores back: the payload minus `ib` (a request flag that is
        // never written back) — the stored def must then read as satisfied, or
        // every sync would re-save and flash the strip.
        final stored = def(
          name: e.value.name,
          on: built['on'] as bool,
          bri: built['bri'] as int,
          seg: (built['seg'] as List).cast<Map<String, dynamic>>(),
        );
        expect(
          ScheduleSyncService.isNglOnPresetSatisfied(stored, e.value.name),
          isTrue,
          reason: 'slot ${e.key} would re-psave on every sync',
        );
      }
    });
  });

  group('preset 2 is excluded from the ON repair', () {
    test('a correct OFF preset stays satisfied under its OWN predicate', () {
      final off = def(name: 'NGL Off', on: false, bri: 200, seg: [
        {'id': 0, 'on': false},
        {'id': 1, 'on': false},
      ]);
      expect(ScheduleSyncService.isNglOffPresetSatisfied(off), isTrue);
    });

    test('the ON bar would WRONGLY reject it — proving the two must not '
        'share a predicate', () {
      final off = def(name: 'NGL Off', on: false, bri: 200, seg: [
        {'id': 0, 'on': false},
      ]);
      expect(ScheduleSyncService.isNglOnPresetSatisfied(off, 'NGL Off'), isFalse,
          reason: 'applying the ON repair to preset 2 would relight the house '
              'at every OFF boundary');
    });
  });

  group('onPresetHealState — the healer path shares one definition', () {
    test('is the same payload as the sync path', () {
      final live = liveState([0, 1]);
      expect(ScheduleSyncService.onPresetHealState(200, live),
          ScheduleSyncService.buildNglOnPresetState(200, live));
    });

    test('carries explicit segments so the healer cannot re-damage what the '
        'sync repaired', () {
      final s = ScheduleSyncService.onPresetHealState(200, liveState([0, 1]));
      expect((s['seg'] as List).every((e) => (e as Map)['on'] == true), isTrue);
    });
  });
}
