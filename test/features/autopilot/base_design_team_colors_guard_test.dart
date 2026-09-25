// Guard: the Game Day BASE design plays the team's OWN colours.
//
// History (2026-09-21): both base-design builders — TeamDesignCatalog's
// design 5 and GameDayAutopilotService's "dynamic" style — shipped fx 63
// captioned "Twinkle". On WLED 0.15.1 fx 63 is Pride 2015, a hue-rotating
// rainbow that reads neither `col[]` nor the palette; the bench put 55 % of
// its lit pixels in hues the team does not have, 162 colours per frame. The
// celebration path had the same class of bug (fx 9 "Wipe" = Rainbow, fx 63
// "Running" = Pride 2015) and got a guard; this is the base design's.
//
// What is pinned, for every design the two builders can produce:
//   • the effect is in the catalog and does not generate its own colours;
//   • it is never fx 63;
//   • a palette-reading effect must be in the bench-verified exemption set
//     (else the shared normalizer rewrites its pal 5 → 4 on the wire);
//   • `pal` is exactly WledEffectsCatalog.setColorsPaletteFor(fx), and it
//     SURVIVES normalizeWledPayload — the layer a fake delivery never crosses;
//   • the team's colours are on the wire;
//   • a design whose caption names an effect carries THAT effect's id
//     (label/ID drift is the real failure mode);
//   • the Fade is slow by the speed catalog's own definition.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/data/team_led_colors.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart';
import 'package:nexgen_command/features/autopilot/team_design_catalog.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/game_schedule_service.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart'
    show normalizeWledPayload;

// Bills: blue + red, 120° apart — the design used on the bench.
const Color _primary = Color(0xFF00338D);
const Color _secondary = Color(0xFFC60C30);
// On the wire the team's colours are their LED colours, not the brand hex
// (#00338D → [0, 92, 255], #C60C30 → [255, 0, 34]; lib/data/team_led_colors.dart).
final List<int> _primaryRgbw = teamLedRgb(0x00338D).toRgbw();
final List<int> _secondaryRgbw = teamLedRgb(0xC60C30).toRgbw();

List<Map<String, dynamic>> _segs(Map<String, dynamic> payload) =>
    (payload['seg'] as List)
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();

/// The one assertion both builders must satisfy for every design.
void _assertPlaysTeamColours(
  Map<String, dynamic> payload,
  int fx,
  String where,
) {
  final e = WledEffectsCatalog.getById(fx);
  expect(e, isNotNull, reason: '$where: fx $fx is not in the catalog');
  expect(fx, isNot(63), reason: '$where: fx 63 is Pride 2015, a rainbow');
  expect(e!.colorBehavior, isNot(ColorBehavior.generatesOwnColors),
      reason: '$where: ${e.name} ($fx) colours itself, not from the team');
  if (!e.usesUserColors) {
    expect(WledEffectsCatalog.kColorsOnlyVerifiedEffects, contains(fx),
        reason: '$where: ${e.name} ($fx) reads the palette but is not '
            'bench-verified under "Colors Only" — measure it before using it');
  }
  final expectedPal = WledEffectsCatalog.setColorsPaletteFor(fx);

  final segs = _segs(payload);
  expect(segs, isNotEmpty, reason: where);
  for (final seg in segs) {
    expect(seg['fx'], fx, reason: where);
    expect(seg['pal'], expectedPal, reason: '$where: pal');
    // Both team colours, in either order — design 2 ("Alt") leads with the
    // secondary on purpose.
    final col = (seg['col'] as List).cast<List>();
    expect(col.length, greaterThanOrEqualTo(2), reason: '$where: col');
    final onWire = {
      col[0].take(3).join(','),
      col[1].take(3).join(','),
    };
    expect(onWire, {
      _primaryRgbw.take(3).join(','),
      _secondaryRgbw.take(3).join(','),
    }, reason: '$where: the two team colours must be col[0] and col[1]');
  }
  // The layer that bit the celebration fix: the shared normalizer's palette
  // guard. What the builder set must be what reaches the controller.
  for (final seg in _segs(normalizeWledPayload(payload))) {
    expect(seg['pal'], expectedPal,
        reason: '$where: pal must survive normalizeWledPayload');
  }
}

void main() {
  group('TeamDesignCatalog — every design plays the team colours', () {
    final catalog = TeamDesignCatalog.build(
      teamName: 'Bills',
      primary: _primary,
      secondary: _secondary,
    );

    test('six designs, each colour-reading, none fx 63, pal from the rule',
        () {
      expect(catalog, hasLength(6));
      for (final d in catalog) {
        _assertPlaysTeamColours(d.wledPayload, d.effectId, d.name);
      }
    });

    // Label/ID drift: a design captioned with an effect's name must carry
    // that effect's id on the pinned firmware. "Twinkle" over fx 63 is how
    // the rainbow shipped.
    test('captions name the effect that is actually sent', () {
      const captioned = <int, String>{2: 'Chase', 3: 'Breathe', 4: 'Fade'};
      captioned.forEach((index, label) {
        final d = catalog[index];
        expect(d.name, endsWith(label), reason: 'design ${index + 1}');
        expect(WledEffectsCatalog.getById(d.effectId)!.name, label,
            reason: 'design ${index + 1}: fx ${d.effectId} is not $label');
      });
    });

    test('design 5 is Fade (12): a crossfade of the two team colours', () {
      final d = catalog[4];
      expect(d.effectId, kBaseDesignFadeEffectId);
      expect(kBaseDesignFadeEffectId, 12);
      expect(WledEffectsCatalog.getById(12)!.name, 'Fade');
      expect(WledEffectsCatalog.getById(12)!.colorBehavior,
          ColorBehavior.blendsSelectedColors);
      // Fade reads col[] directly: pal 0, and the guard has nothing to exempt.
      expect(WledEffectsCatalog.setColorsPaletteFor(12), 0);
      expect(_segs(d.wledPayload).single['pal'], 0);
    });

    test('the Fade is slow by the speed catalog\'s own definition', () {
      final d = catalog[4];
      final profile = getSpeedProfile(kBaseDesignFadeEffectId);
      expect(d.speed, kBaseDesignFadeSpeed);
      expect(d.speed, profile.rawDefault,
          reason: 'the base design uses the catalog\'s "Fade pace" default, '
              'not a raw literal');
      final label =
          profile.speedLabel(profile.mapRawToSlider(d.speed).position);
      expect(label, anyOf('Very Slow', 'Slow'),
          reason: 'sx ${d.speed} reads as $label on the Fade profile');
      expect(_segs(d.wledPayload).single['sx'], d.speed);
    });
  });

  group('GameDayAutopilotService.selectDesign — every style plays the team '
      'colours', () {
    late GameDayAutopilotService svc;
    setUp(() {
      svc = GameDayAutopilotService(
        espnApi: EspnApiService(),
        scheduleService: GameScheduleService(),
      );
    });
    tearDown(() => svc.dispose());

    // Each list lands in exactly one _StyleCategory (see _categorizeStyles):
    // static / motion / dynamic, plus the no-preference fallback.
    const styles = <String, List<String>>{
      'static': ['static'],
      'motion': ['animated'],
      'dynamic': ['twinkle'],
      'fallback': [],
    };

    test('static, motion, dynamic and fallback all pass the guard', () {
      styles.forEach((name, prefs) {
        final design = svc.selectDesign(_config(), preferredStyles: prefs);
        _assertPlaysTeamColours(
            design.wledPayload, design.effectId, 'style $name');
      });
    });

    test('dynamic is Fade (12) at the catalog\'s slow pace — never 63', () {
      final design =
          svc.selectDesign(_config(), preferredStyles: const ['twinkle']);
      expect(design.effectId, kBaseDesignFadeEffectId);
      expect(design.effectId, isNot(63));
      expect(design.designName, contains('Fade'));
      expect(design.designName, isNot(contains('Twinkle')));
      expect(design.speed, kBaseDesignFadeSpeed);
      final seg = _segs(design.wledPayload).single;
      expect(seg['fx'], 12);
      expect(seg['sx'], kBaseDesignFadeSpeed);
      expect(seg['pal'], 0);
    });

    test('a saved design is passed through untouched (not this guard\'s '
        'business)', () {
      final saved = _config(
        designMode: AutopilotDesignMode.saved,
        savedDesignPayload: {
          'on': true,
          'bri': 200,
          'seg': [
            {'fx': 83, 'pal': 5, 'col': [_primaryRgbw, _secondaryRgbw]},
          ],
        },
      );
      final design = svc.selectDesign(saved, preferredStyles: const ['twinkle']);
      expect(design.mode, AutopilotDesignMode.saved);
      expect(_segs(design.wledPayload).single['fx'], 83);
    });
  });
}

GameDayAutopilotConfig _config({
  AutopilotDesignMode designMode = AutopilotDesignMode.autoSelected,
  Map<String, dynamic>? savedDesignPayload,
}) {
  final now = DateTime.utc(2026, 9, 21);
  return GameDayAutopilotConfig(
    teamSlug: 'nfl_bills',
    teamName: 'Buffalo Bills',
    espnTeamId: '2',
    sport: SportType.nfl,
    primaryColorValue: 0xFF00338D,
    secondaryColorValue: 0xFFC60C30,
    brightness: 200,
    designMode: designMode,
    savedDesignPayload: savedDesignPayload,
    createdAt: now,
    updatedAt: now,
  );
}
