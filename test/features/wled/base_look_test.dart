// +114 — the base look. The NGL ON ladder names its colour and effect instead
// of capturing whatever the house happened to be showing when it was saved.
//
// Two halves, and both matter:
//   WRITE — every lit ladder segment carries Lumina Blue / Solid / black slots
//           2-3, whatever live state says.
//   NEVER ASSERT — the satisfaction predicate ignores the look, so a fleet
//           ladder saved before +114 is NOT re-saved by the next schedule sync.
//           A dark ladder is the guarded on-connect repair's job.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/base_look.dart';

/// A live state showing something loud on every segment — the ambient-capture
/// trap: red, rainbow effect, a busy palette.
Map<String, dynamic> loudLive(List<int> ids) => {
      'on': true,
      'bri': 90,
      'seg': [
        for (final id in ids)
          {
            'id': id,
            'on': true,
            'fx': 9,
            'pal': 11,
            'col': [
              [255, 0, 0, 0],
              [0, 255, 0, 0],
              [0, 0, 255, 0],
            ],
          },
      ],
    };

void main() {
  group('the constant', () {
    test('is Lumina Blue, white 0, Solid, slots 2 and 3 black', () {
      expect(kBaseLookRed, 0);
      expect(kBaseLookGreen, 212);
      expect(kBaseLookBlue, 255);
      expect(kBaseLookWhite, 0);
      expect(kBaseLookEffectId, 0);
      expect(baseLookColSlots(), [
        [0, 212, 255, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]);
    });

    test('matches the app\'s Lumina cyan, so the house and the app agree', () {
      const c = NexGenPalette.cyan;
      expect((c.r * 255).round(), kBaseLookRed);
      expect((c.g * 255).round(), kBaseLookGreen);
      expect((c.b * 255).round(), kBaseLookBlue);
    });

    test('kBaseLookSegmentKeys is exactly what the look writes', () {
      expect(baseLookSegmentFields().keys.toSet(), kBaseLookSegmentKeys);
    });

    test('hands out fresh lists — one caller cannot mutate the next', () {
      final a = baseLookSegmentFields();
      ((a['col'] as List)[0] as List)[1] = 0;
      expect(baseLookColSlots()[0], [0, 212, 255, 0]);
    });
  });

  group('WRITE — the builder never captures the live look', () {
    for (final bri in const [200, 51, 102, 153]) {
      test('bri $bri: every lit segment is the base look, not the live one',
          () {
        final s = ScheduleSyncService.buildNglOnPresetState(
            bri, loudLive([0, 1, 2]));
        for (final seg in (s['seg'] as List).cast<Map>()) {
          expect(seg['on'], isTrue);
          expect(seg['fx'], kBaseLookEffectId);
          expect(seg['col'], baseLookColSlots());
          expect(seg.containsKey('pal'), isFalse,
              reason: 'Solid ignores the palette; the look names only what '
                  'it needs');
        }
      });
    }

    test('every ladder slot spec builds the same look', () {
      for (final spec in ScheduleSyncService.kOnPresetSpecs.values) {
        final s =
            ScheduleSyncService.buildNglOnPresetState(spec.bri, loudLive([0]));
        expect((s['seg'] as List).single['col'], baseLookColSlots());
      }
    });

    test('the healer\'s heal state is the same builder (one definition)', () {
      final live = loudLive([0, 1]);
      expect(ScheduleSyncService.onPresetHealState(200, live),
          ScheduleSyncService.buildNglOnPresetState(200, live));
    });

    test('the OFF preset is untouched — no look on a dark preset', () {
      final off = ScheduleSyncService.buildNglOffPresetState(loudLive([0, 1]));
      for (final seg in (off['seg'] as List).cast<Map>()) {
        expect(seg.keys.toSet(), {'id', 'on'});
      }
    });
  });

  group('NEVER ASSERT — no fleet-wide re-save', () {
    test('a pre-114 ladder holding a captured colour is still SATISFIED', () {
      // The installed-fleet shape: on, ib-persisted root, every segment on,
      // and whatever colour/effect the original save captured.
      final stored = <String, dynamic>{
        'n': 'NGL On',
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'on': true, 'fx': 9, 'col': [[255, 0, 0, 0]]},
          {'id': 1, 'on': true, 'fx': 9, 'col': [[255, 0, 0, 0]]},
        ],
      };
      expect(
        ScheduleSyncService.presetSatisfies(
          stored,
          ScheduleSyncService.buildNglOnPresetState(200, loudLive([0, 1])),
          expectedName: 'NGL On',
        ),
        isTrue,
        reason: 'asserting the look would re-psave every controller\'s ladder '
            'at its next sync — a visible flash per house',
      );
    });

    test('a freshly built preset satisfies itself (converges in one save)', () {
      final built =
          ScheduleSyncService.buildNglOnPresetState(200, loudLive([0, 1]));
      expect(
        ScheduleSyncService.presetSatisfies(
          {...built, 'n': 'NGL On'},
          ScheduleSyncService.buildNglOnPresetState(200, loudLive([0, 1])),
          expectedName: 'NGL On',
        ),
        isTrue,
        reason: '`col` is a List: compared with != it would never match, and '
            'the ladder would be re-saved on every sync',
      );
    });

    test('the segment-on bar is still enforced (BASE_LADDER.md)', () {
      final damaged = <String, dynamic>{
        'n': 'NGL On',
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'on': false, 'fx': 0, 'col': baseLookColSlots()},
          {'id': 1, 'on': true, 'fx': 0, 'col': baseLookColSlots()},
        ],
      };
      expect(ScheduleSyncService.isNglOnPresetSatisfied(damaged, 'NGL On'),
          isFalse);
    });
  });
}
