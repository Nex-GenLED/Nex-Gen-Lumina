// +123 — the library's "… Shadows" collection cards keep their build-122
// speeds.
//
// Collection cards scale a base speed by their collection's pace
// (scaledEffectDefaultSpeed). When the Dancing Shadows TILE default went from
// 20 to 10 (+123 item B), the cards — which scaled the same table value —
// moved with it: a calm collection (pace 30 / 40 / 50) went from 5 / 6 / 8 to
// 2 / 3 / 4, below the slider's floor of 5. A comparison of every generated
// card (32,382 cards, 1,325 library nodes and every theme subcategory) between
// build-122 and the candidate found 1,033 differing cards, every one an fx 112
// "… Shadows" card, and nothing else.
//
// The cards now scale from 20 again; only the direct tile paths (library
// tuner, Home Tune effect menu, edit screen, Game Day picker) start at 10
// (dancing_shadows_speed_test.dart).

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';

const int kDancingShadows = 112;

/// Build-122's card speed for Dancing Shadows at collection pace [pace]:
/// its table value 20, scaled exactly as build-122 scaled it.
int build122CardSpeed(int pace) =>
    pace <= 0 ? 0 : (20 * pace / 128).round().clamp(1, 255);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the card speed at each collection pace is build-122\'s', () {
    // The calm collections that had dropped below the floor of 5.
    expect(scaledEffectDefaultSpeed(kDancingShadows, 30), 5);
    expect(scaledEffectDefaultSpeed(kDancingShadows, 40), 6);
    expect(scaledEffectDefaultSpeed(kDancingShadows, 50), 8);
    // Every pace the library uses, and a static collection.
    for (final pace in [0, 30, 40, 50, 60, 70, 80, 85, 90, 100, 110, 120, 128,
        130, 150, 180, 200, 255]) {
      expect(scaledEffectDefaultSpeed(kDancingShadows, pace),
          build122CardSpeed(pace),
          reason: 'pace $pace');
    }
  });

  test('every "… Shadows" card in the library sends build-122\'s speed', () async {
    final repo = PatternRepository(moviesVisible: true);
    var shadows = 0;
    final seen = <String>{};
    Future<void> walk(String? parent, int depth) async {
      if (depth > 8) return;
      for (final n in await repo.getChildNodes(parent)) {
        if (!seen.add(n.id)) continue;
        if (n.isPalette) {
          for (final item in await repo.generatePatternsForNode(n)) {
            final seg = (item.wledPayload['seg'] as List).first as Map;
            if (seg['fx'] != kDancingShadows) continue;
            shadows++;
            expect(seg['sx'], build122CardSpeed(n.defaultSpeed),
                reason: '${item.name} in ${n.name} (pace ${n.defaultSpeed})');
          }
        }
        await walk(n.id, depth + 1);
      }
    }

    await walk(null, 0);
    expect(shadows, greaterThan(1000), reason: 'the walk reached the library');
  });

  test('the theme grid\'s "… Shadows" card sends build-122\'s 20', () async {
    final repo = PatternRepository();
    const sub = SubCategory(
      id: 'sub_test',
      name: 'Test',
      parentCategoryId: 'cat_holiday',
      themeColors: [Color(0xFFFF0000), Color(0xFF00FF00)],
    );
    final items = await repo.generatePatternsForTheme(sub);
    final seg = items
        .map((i) => (i.wledPayload['seg'] as List).first as Map)
        .singleWhere((s) => s['fx'] == kDancingShadows);
    expect(seg['sx'], 20);
  });

  test('the tile still starts at 10 — cards and tile differ on purpose', () {
    expect(effectDefaultSpeed(kDancingShadows), 10);
    expect(scaledEffectDefaultSpeed(kDancingShadows, 128), 20);
  });
}
