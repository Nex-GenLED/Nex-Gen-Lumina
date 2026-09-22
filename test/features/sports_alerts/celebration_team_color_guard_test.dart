// GUARD — a score celebration must render in TEAM COLOURS.
//
// WHY THIS EXISTS. From the first commit (2026-03-04) until 2026-09-21 the
// celebration table sent fx 9 labelled "Wipe", fx 63 labelled "Running" and
// fx 5 labelled "Theater Chase". On WLED 0.15.1 those ids are Rainbow, Pride
// 2015 and Random Colors. None of them draws from `col`, so a touchdown spent
// 13 of its 15 seconds as a rainbow while the team colours sat unread in the
// payload. Pride 2015 reads no palette either — no `pal` could have saved it.
//
// Nothing caught it, for six months, because the existing tests pinned the ids
// the table HAD ([2, 9, 63]) rather than checking what those ids MEAN. They
// passed because they matched the bug.
//
// The app's own WledEffectsCatalog had fx 9 and fx 63 right the whole time
// (`generatesOwnColors`). This test makes that catalog the enforcement: add a
// celebration stage whose effect does not read the team colours, or that
// forgets the palette, and it fails here instead of on a customer's house.
// (audit: gameday-rainbow-celebration-audit-2026-09-21.md)

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/celebration_contrast.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

final _team = kTeamColors['nfl_chiefs']!;

const _twoChannels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];

/// The catalog NAME each stage is meant to be, in order. This is the half that
/// actually broke: the label and the id disagreed and nothing compared them.
/// Change a stage's effect and this table must change with it — deliberately.
const _expectedEffectNames = <AlertEventType, List<String>>{
  AlertEventType.touchdown: ['Breathe', 'Wipe', 'Running'],
  AlertEventType.goal: ['Breathe', 'Wipe', 'Running'],
  AlertEventType.win: ['Breathe', 'Wipe', 'Running'],
  AlertEventType.fieldGoal: ['Breathe'],
  AlertEventType.safety: ['Strobe'],
  AlertEventType.run: ['Theater'],
  AlertEventType.quarterEndWinning: ['Breathe'],
  AlertEventType.clutchBasket: ['Strobe'],
  AlertEventType.soccerGoal: ['Chase', 'Strobe', 'Running', 'Breathe'],
  AlertEventType.turnover: [],
};

List<Map> _segsOf(AlertAnimationStep step) =>
    (step.payload['seg'] as List).cast<Map>();

void main() {
  group('every celebration stage reads the team colours', () {
    for (final type in AlertEventType.values) {
      test('${type.name}: each stage uses a colour-reading catalog effect', () {
        final steps = AlertTriggerService.buildAnimationSteps(type, _team);
        for (var i = 0; i < steps.length; i++) {
          for (final seg in _segsOf(steps[i])) {
            final fx = seg['fx'] as int;
            final effect = WledEffectsCatalog.getById(fx);
            expect(effect, isNotNull,
                reason: '${type.name} stage ${i + 1} sends fx $fx, which is '
                    'not in WledEffectsCatalog — an id nobody can name is how '
                    'this bug started');
            expect(effect!.usesUserColors, isTrue,
                reason: '${type.name} stage ${i + 1} sends fx $fx '
                    '("${effect.name}", ${effect.colorBehavior.name}). That '
                    'effect does not draw from `col`, so the celebration '
                    'would NOT render in team colours.');
          }
        }
      });
    }

    test('every event type is covered by the expected-name table', () {
      expect(_expectedEffectNames.keys.toSet(), AlertEventType.values.toSet(),
          reason: 'a new AlertEventType needs an entry here');
    });

    for (final type in AlertEventType.values) {
      test('${type.name}: each stage IS the effect its label says', () {
        final steps = AlertTriggerService.buildAnimationSteps(type, _team);
        final names = [
          for (final s in steps)
            WledEffectsCatalog.getById(_segsOf(s).first['fx'] as int)?.name,
        ];
        expect(names, _expectedEffectNames[type]);
      });
    }
  });

  group('every celebration stage asserts palette 0', () {
    // A segment KEEPS its palette when `pal` is omitted, so a stage without it
    // inherits the look underneath. Colour-reading effects go through
    // color_from_palette: over a non-zero palette they render THAT, not `col`.
    test('legacy table', () {
      for (final type in AlertEventType.values) {
        final steps = AlertTriggerService.buildAnimationSteps(type, _team);
        for (var i = 0; i < steps.length; i++) {
          for (final seg in _segsOf(steps[i])) {
            expect(seg, containsPair('pal', 0),
                reason: '${type.name} stage ${i + 1} does not assert pal:0');
          }
        }
      }
    });

    test('a chosen celebration and the white fallback inherit it', () {
      const chosen =
          CelebrationResolution(effectId: 28, speed: 200, intensity: 180);
      const fallback = CelebrationResolution(
        effectId: kFallbackCelebrationEffectId,
        speed: kFallbackCelebrationSpeed,
        intensity: kFallbackCelebrationIntensity,
        usedFallback: true,
      );
      for (final resolution in [chosen, fallback]) {
        for (final type in AlertEventType.values) {
          final steps =
              AlertTriggerService.buildAnimationSteps(type, _team, resolution);
          for (final step in steps) {
            for (final seg in _segsOf(step)) {
              expect(seg, containsPair('pal', 0));
            }
          }
        }
      }
    });

    // Bench-chosen 2026-09-21 on WLED 0.15.1 (see kSetColorsOnlyPalette's doc):
    // a palette-reading pick under pal 0 draws from the firmware's DEFAULT
    // palette, so it is sent "Colors Only" (5) — the segment's own col[] as the
    // palette. A colour-reading pick reads col[] directly under pal 0.
    test('a chosen palette-reading pick asserts "Colors Only" (5) on every '
        'stage; every colour-reading pick keeps pal 0', () {
      expect(WledEffectsCatalog.kSetColorsOnlyPalette, 5);
      for (final id in WledEffectsCatalog.celebrationPickIds) {
        final expectedPal = WledEffectsCatalog.usesUserColors(id) ? 0 : 5;
        expect(WledEffectsCatalog.celebrationPaletteFor(id), expectedPal);
        final chosen =
            CelebrationResolution(effectId: id, speed: 200, intensity: 180);
        for (final type in AlertEventType.values) {
          final steps =
              AlertTriggerService.buildAnimationSteps(type, _team, chosen);
          for (final step in steps) {
            for (final seg in _segsOf(step)) {
              expect(seg, containsPair('pal', expectedPal),
                  reason: 'fx $id, ${type.name}');
            }
          }
        }
      }
      // The four this was measured on.
      for (final id in [64, 42, 90, 89]) {
        expect(WledEffectsCatalog.celebrationPickIds, contains(id));
        expect(WledEffectsCatalog.celebrationPaletteFor(id), 5, reason: '$id');
      }
    });

    test('it survives applyChannelFilter onto every targeted channel', () {
      // What is asserted on the template is only useful if it reaches the wire.
      final steps = AlertTriggerService.buildAnimationSteps(
          AlertEventType.touchdown, _team);
      for (final step in steps) {
        final wire = applyChannelFilter(step.payload, const [0, 1], _twoChannels);
        final segs = (wire['seg'] as List).cast<Map>();
        expect(segs.map((s) => s['id']), [0, 1]);
        for (final seg in segs) {
          expect(seg, containsPair('pal', 0));
          expect(WledEffectsCatalog.getById(seg['fx'] as int)!.usesUserColors,
              isTrue);
        }
      }
    });
  });

  group('the team colours are actually on the wire', () {
    test('slot 0 of every stage is the team primary, white channel zeroed', () {
      final primary = AlertTriggerService.colorToRgbw(_team.primary);
      expect(primary, [227, 24, 55, 0]); // Chiefs red #E31837
      for (final type in AlertEventType.values) {
        for (final step in AlertTriggerService.buildAnimationSteps(type, _team)) {
          for (final seg in _segsOf(step)) {
            expect((seg['col'] as List).first, primary,
                reason: '${type.name} does not lead with the team primary');
          }
        }
      }
    });
  });

  group('the guard would have caught the original bug', () {
    // If someone makes the guard pass by editing the CATALOG instead of the
    // table, these fail. The three ids below are what shipped; the firmware
    // facts are from wled00/FX.cpp @ v0.15.1.
    test('fx 9 (Rainbow), fx 63 (Pride 2015), fx 5 (Random Colors) are '
        'catalogued as NOT reading the user colours', () {
      const shipped = {9: 'Rainbow', 63: 'Pride 2015', 5: 'Random Colors'};
      shipped.forEach((fx, name) {
        final effect = WledEffectsCatalog.getById(fx);
        expect(effect, isNotNull);
        expect(effect!.name, name);
        expect(effect.usesUserColors, isFalse,
            reason: 'fx $fx ($name) does not draw from `col` on WLED 0.15.1');
      });
    });

    test('no celebration stage uses a rainbow-family effect', () {
      for (final type in AlertEventType.values) {
        for (final step in AlertTriggerService.buildAnimationSteps(type, _team)) {
          for (final seg in _segsOf(step)) {
            expect(WledEffectsCatalog.rainbowEffectIds, isNot(contains(seg['fx'])),
                reason: '${type.name} sends rainbow-family fx ${seg['fx']}');
          }
        }
      }
    });

    test('the contrast fallback is itself a colour-reading effect', () {
      // It floods WHITE by overriding `col`; that only works if it reads `col`.
      expect(
        WledEffectsCatalog.getById(kFallbackCelebrationEffectId)!.usesUserColors,
        isTrue,
      );
    });
  });
}
