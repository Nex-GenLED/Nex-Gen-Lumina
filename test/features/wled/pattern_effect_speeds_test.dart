// +110 E1, owner item D — curated per-effect default speeds for a roofline.
//
// The table (lib/features/wled/pattern_effect_speeds.dart) must:
//   • cover EVERY effect in the catalog, each in exactly one of the pace table
//     and the not-a-pace set;
//   • leave the speed slider free above AND below every default;
//   • start the owner's nine "too fast" effects slower than anything the app
//     sent for them before;
//   • be what the Explore catalogue actually sends.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

/// The owner's report, 2026-09-29.
const _ownerTooFast = <int, String>{
  64: 'Juggle',
  91: 'Bouncing Balls',
  111: 'Chunchun',
  23: 'Strobe',
  42: 'Fireworks',
  90: 'Fireworks 1D',
  89: 'Fireworks Starburst',
  112: 'Dancing Shadows',
  25: 'Strobe Mega',
};

/// What the app sent for an effect before the table: the Explore catalogue's
/// 128 × multiplier, or the tuner's profile default.
List<int> _before(int fx) => [
      WledEffectsCatalog.getAdjustedSpeed(fx, 128),
      getSpeedProfile(fx).rawDefault,
    ];

void main() {
  test('every catalog effect is covered — exactly once', () {
    for (final e in WledEffectsCatalog.allEffects) {
      final inPace = kEffectDefaultSpeed.containsKey(e.id);
      final notPace = kSpeedIsNotPace.contains(e.id);
      expect(inPace ^ notPace, isTrue,
          reason: 'fx ${e.id} ${e.name}: in pace table $inPace, '
              'not-a-pace $notPace — must be exactly one');
    }
  });

  test('no stray ids: every table entry is a catalog effect', () {
    final ids = {for (final e in WledEffectsCatalog.allEffects) e.id};
    expect(kEffectDefaultSpeed.keys.where((k) => !ids.contains(k)), isEmpty);
    expect(kSpeedIsNotPace.where((k) => !ids.contains(k)), isEmpty);
  });

  test('the slider stays free above AND below every default', () {
    for (final e in kEffectDefaultSpeed.entries) {
      final p = getSpeedProfile(e.key);
      expect(e.value, greaterThan(p.rawMin),
          reason: 'fx ${e.key}: no room below ${e.value} (min ${p.rawMin})');
      expect(e.value, lessThan(p.rawRecommendedMax),
          reason: 'fx ${e.key}: no room above ${e.value} '
              '(recommended max ${p.rawRecommendedMax})');
    }
  });

  group('the owner\'s nine start slower than before', () {
    for (final entry in _ownerTooFast.entries) {
      test('fx ${entry.key} ${entry.value}', () {
        final fx = entry.key;
        final speed = effectDefaultSpeed(fx);
        if (speed == null) {
          // Fireworks: the firmware ignores speed; its rate is intensity.
          expect(kSpeedIsNotPace, contains(fx));
          expect(effectDefaultIntensity(fx), lessThan(128),
              reason: 'the app sent ix 128; the firmware default is 192');
          return;
        }
        for (final old in _before(fx)) {
          expect(speed, lessThan(old),
              reason: '${entry.value}: $speed is not slower than $old');
        }
      });
    }
  });

  test('Strobe, Strobe Rainbow and Strobe Mega are flagged as flash', () {
    expect(kPhotosensitiveFlashEffectIds, {23, 24, 25});
  });

  group('scaledEffectDefaultSpeed', () {
    test('a neutral folder (128) gets the table value', () {
      expect(scaledEffectDefaultSpeed(64, 128), effectDefaultSpeed(64));
    });
    test('a calm folder slows it, a lively one quickens it', () {
      expect(scaledEffectDefaultSpeed(28, 64), (60 * 64 / 128).round());
      expect(scaledEffectDefaultSpeed(28, 150), (60 * 150 / 128).round());
    });
    test('a static folder stays static', () {
      expect(scaledEffectDefaultSpeed(28, 0), 0);
    });
    test('an effect with no pace keeps the folder speed', () {
      expect(scaledEffectDefaultSpeed(83, 100), 100);
    });
  });

  test('the Explore theme grid SENDS the table speed', () async {
    final repo = PatternRepository();
    const sub = SubCategory(
      id: 'sub_test',
      name: 'Test',
      parentCategoryId: 'cat_holiday',
      themeColors: [Color(0xFFFF0000), Color(0xFF00FF00)],
    );
    final items = await repo.generatePatternsForTheme(sub);
    expect(items, isNotEmpty);
    for (final item in items) {
      final seg = (item.wledPayload['seg'] as List).first as Map;
      final fx = seg['fx'] as int;
      expect(seg['sx'], scaledEffectDefaultSpeed(fx, 128),
          reason: 'fx $fx: theme grid speed');
    }
  });

  test('a library palette node SENDS the table speed, scaled by its folder',
      () async {
    final repo = PatternRepository();
    final roots = await repo.getChildNodes(null);
    LibraryNode? palette;
    Future<void> find(String? parent) async {
      if (palette != null) return;
      for (final n in await repo.getChildNodes(parent)) {
        if (palette != null) return;
        if (n.isPalette && n.metadata?['type'] != 'brightness_gradient') {
          palette = n;
          return;
        }
        await find(n.id);
      }
    }

    for (final r in roots) {
      await find(r.id);
      if (palette != null) break;
    }
    expect(palette, isNotNull);
    final items = await repo.generatePatternsForNode(palette!);
    for (final item in items) {
      final seg = (item.wledPayload['seg'] as List).first as Map;
      final fx = seg['fx'] as int;
      expect(seg['sx'], scaledEffectDefaultSpeed(fx, palette!.defaultSpeed),
          reason: 'fx $fx in ${palette!.name}');
    }
  });
}
