// Build 124, fix d4 — Twinkle's background is lit RAW.
//
// WLED's Twinkle (fx 17) fades every pixel toward col[1] with
// Segment::fade_out, which does not apply the colour gamma that SEGCOLOR gets.
// The app's dim field (30 % of the sparkle colour) therefore lit at 30 %, not
// at the ~3 % the sparkle code assumes. Owner's bench, spare controller
// 2026-11-10, step 9 (gamma 2.8): field [77,53,33] glowed pale; field [9,3,1]
// — the same 30 % with the controller's gamma applied — "looks more correct
// against the darker background". This file pins that approved payload.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/sparkle_background.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

const _warm1 = [255, 177, 110, 0]; // 3000K slot 1 — the sparkle
const _warm2 = [255, 207, 160, 0]; // 3000K slot 2 — the near-identical field

void main() {
  test('the gamma is the one the app writes to every controller', () {
    expect(kNglLightGammaConfig['val'], 2.8);
    // WLED's table: (int)(pow(v/255, 2.8) * 255 + 0.5).
    expect(controllerGammaChannel(255), 255);
    expect(controllerGammaChannel(0), 0);
    expect(controllerGammaChannel(77), 9);
    expect(controllerGammaChannel(53), 3);
    expect(controllerGammaChannel(33), 1);
  });

  test('bench step 9, exactly: fx 17 sx 200 ix 128 pal 0, '
      'col [255,177,110] / [9,3,1] / black, on the wire', () {
    final built = buildSelectorPayload(const SelectorState(
      effectId: 17,
      speed: 200,
      intensity: 128,
      grouping: 1,
      spacing: 0,
      colors: [_warm1, _warm2],
    ));
    final seg = ((normalizeWledPayload(built)['seg'] as List).single as Map)
        .cast<String, dynamic>();
    expect(seg['fx'], 17);
    expect(seg['sx'], 200);
    expect(seg['ix'], 128);
    expect(seg['pal'], 0);
    expect(seg['col'], [_warm1, [9, 3, 1, 0], [0, 0, 0, 0]]);
  });

  test('only fx 17 is raw-field: the rest of the sparkle family keeps 30 %',
      () {
    for (final fx in kSparkleOverFieldEffectIds.difference({17})) {
      final r = readableSparkleColors(fx, const [_warm1, _warm2]);
      expect(r.colors[1], [77, 53, 33, 0], reason: 'fx $fx reads SEGCOLOR');
    }
  });

  test('white-chip sparkle (the rule extended; flagged for the bench): '
      'field W 77 → 9', () {
    final r = readableSparkleColors(17, const [
      [0, 0, 0, 255],
      [0, 0, 0, 230],
    ]);
    expect(r.colors[1], [0, 0, 0, 9]);
  });
}
