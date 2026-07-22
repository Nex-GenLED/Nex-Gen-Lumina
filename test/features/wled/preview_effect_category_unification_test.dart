// Regression tests for #6 — the four preview surfaces must agree on what
// render-category each WLED effect id maps to, all driven by the single
// authoritative WledEffectsCatalog.
//
// The reported bug: "Chase 2" (id 37) previewed as flame on the roofline
// because the roofline read a divergent id space (effect_database, where
// id 37 = "Candle"). After the fix every surface derives its category from
// WledEffectsCatalog.
//
// Surfaces under test:
//   #1 effect_preview_widget.getPreviewType()        (tile preview)
//   #2 ar_preview_providers.categorizeEffect()       (roofline painter)
//   #4 light_effect_animator.effectTypeFromWledId()  (Lumina chat strip)
//   #3 pattern_theme_selection._EffectPainter._effectType is private; it now
//      switches on WledEffectsCatalog.getById(id).category, so we pin that
//      shared source directly (proves #3's input is correct).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart'
    show WledEffectsCatalog;
import 'package:nexgen_command/features/wled/effect_preview_widget.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/ai/light_effect_animator.dart';

void main() {
  group('#6 — catalog is the single source of effect-id → category', () {
    test('the reported bug ids carry their canonical WLED category', () {
      expect(WledEffectsCatalog.getById(37)!.category, 'Chase'); // Chase 2
      expect(WledEffectsCatalog.getById(38)!.category, 'Ambient'); // Aurora
      expect(WledEffectsCatalog.getById(54)!.category, 'Chase'); // Chase 3
      expect(WledEffectsCatalog.getById(45)!.category, 'Fire'); // Fire Flicker
      expect(WledEffectsCatalog.getById(66)!.category, 'Fire'); // Fire 2012
    });
  });

  group('#6 — id 37 "Chase 2" previews as a chase on every surface', () {
    test('tile preview (#1)', () {
      expect(getPreviewType(37), EffectPreviewType.chase);
    });
    test('roofline (#2)', () {
      expect(categorizeEffect(37), EffectCategory.chase);
    });
    test('chat strip (#4)', () {
      expect(effectTypeFromWledId(37), EffectType.chase);
    });
  });

  group('#6 — id 54 "Chase 3" previews as a chase, never fire', () {
    test('tile preview (#1)', () {
      expect(getPreviewType(54), EffectPreviewType.chase);
    });
    test('roofline (#2)', () {
      expect(categorizeEffect(54), EffectCategory.chase);
      expect(categorizeEffect(54), isNot(EffectCategory.fire));
    });
    test('chat strip (#4)', () {
      expect(effectTypeFromWledId(54), EffectType.chase);
    });
  });

  group('#6 — id 38 "Aurora" is not fire on any surface', () {
    test('tile preview (#1)', () {
      expect(getPreviewType(38), isNot(EffectPreviewType.fire));
    });
    test('roofline (#2)', () {
      expect(categorizeEffect(38), isNot(EffectCategory.fire));
    });
  });

  group('#6 — genuine fire effects STILL render fire (no over-correction)', () {
    test('id 66 "Fire 2012" — tile preview (#1)', () {
      expect(getPreviewType(66), EffectPreviewType.fire);
    });
    test('id 66 "Fire 2012" — roofline (#2)', () {
      expect(categorizeEffect(66), EffectCategory.fire);
    });
    test('id 45 "Fire Flicker" — consistent fire across #1 and #2', () {
      expect(getPreviewType(45), EffectPreviewType.fire);
      expect(categorizeEffect(45), EffectCategory.fire);
    });
  });

  group('#6 — sanity: a few non-bug ids stay sensible', () {
    test('id 0 "Solid" is solid', () {
      expect(getPreviewType(0), EffectPreviewType.solid);
      expect(categorizeEffect(0), EffectCategory.solid);
      expect(effectTypeFromWledId(0), EffectType.solid);
    });
    test('id 9 "Rainbow" is rainbow', () {
      expect(getPreviewType(9), EffectPreviewType.rainbow);
      expect(categorizeEffect(9), EffectCategory.rainbow);
      expect(effectTypeFromWledId(9), EffectType.rainbow);
    });
    test('id 17 "Twinkle" is twinkle/sparkle family', () {
      expect(getPreviewType(17), EffectPreviewType.sparkle);
      expect(categorizeEffect(17), EffectCategory.twinkle);
    });
  });
}
