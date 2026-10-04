// #167 — the schedule card names an effect the way the controller does.
// fx 12 read "Theater Chase" while WLED 0.15.1 plays Fade; 17, 41, 43, 46,
// 51, 52 and 63 named other effects too.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/utils/effect_display_meta.dart';

void main() {
  test('every curated name is the catalog name for its id', () {
    for (var id = 0; id <= 200; id++) {
      final meta = EffectDisplayMeta.fromId(id);
      final known = WledEffectsCatalog.getById(id);
      if (known == null) continue;
      expect(meta.name, known.name, reason: 'fx $id');
    }
  });

  test('the ids from the report read as the controller plays them', () {
    expect(EffectDisplayMeta.fromId(12).name, 'Fade');
    expect(EffectDisplayMeta.fromId(41).name, 'Lighthouse');
    expect(EffectDisplayMeta.fromId(43).name, 'Rain');
    expect(EffectDisplayMeta.fromId(52).name, 'Running Dual');
    expect(EffectDisplayMeta.fromId(63).name, 'Pride 2015');
  });

  test('an id the card has no entry for still gets the controller name', () {
    expect(EffectDisplayMeta.fromId(87).name, 'Glitter');
    expect(EffectDisplayMeta.fromId(13).name, 'Theater');
    expect(EffectDisplayMeta.fromId(0).isMotion, isFalse);
  });

  test('an id the catalog does not know falls back honestly', () {
    expect(EffectDisplayMeta.fromId(999).name, 'Custom Effect');
  });
}
