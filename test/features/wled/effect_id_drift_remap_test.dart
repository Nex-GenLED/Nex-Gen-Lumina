// test/features/wled/effect_id_drift_remap_test.dart
//
// Verifies the fw 0.15.1 effect-ID drift fix across the four legacy maps.
// All four are now routed through WledEffectsCatalog (the only 0.15.1-correct
// source), so these assertions are the regression guard against re-drift.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/effect_database.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

void main() {
  // Helper: a catalog name MUST resolve to exactly this 0.15.1 ID.
  int id(String name) {
    final v = WledEffectsCatalog.idForName(name);
    expect(v, isNotNull, reason: '"$name" is not a valid 0.15.1 catalog effect');
    return v!;
  }

  group('catalog name lookup', () {
    test('resolves canonical names to known 0.15.1 IDs', () {
      expect(id('Solid'), 0);
      expect(id('Theater'), 13);
      expect(id('Twinkle'), 17);
      expect(id('Sparkle'), 20);
      expect(id('Chase'), 28);
      expect(id('Aurora'), 38);
      expect(id('Fireworks'), 42);
      expect(id('Lightning'), 57);
      expect(id('Colorwaves'), 67);
      expect(id('Lake'), 75);
      expect(id('Ripple'), 79);
      expect(id('Twinklefox'), 80);
      expect(id('Candle'), 88);
      expect(id('Fireworks Starburst'), 89);
      expect(id('Plasma'), 97);
      expect(id('Pacifica'), 101);
      expect(id('Candle Multi'), 102);
      expect(id('Flow'), 110);
      expect(id('Fire 2012'), 66);
    });

    test('legacy/fake names have no 0.15.1 equivalent (must be dropped)', () {
      for (final fake in [
        'Tricolor Chase',
        'Tricolor Wipe',
        'Tricolor Fade',
        'Running Tri',
        'Halloween', // distinct from "Halloween Eyes"
        'Chase Rainbow White',
        'Rainbow Cycle',
        'Fire', // merges into "Fire 2012"
      ]) {
        expect(WledEffectsCatalog.idForName(fake), isNull,
            reason: '"$fake" should not resolve on 0.15.1');
      }
    });

    test('idsForNames silently drops unknown names', () {
      expect(
        WledEffectsCatalog.idsForNames(['Solid', 'Tricolor Chase', 'Chase']),
        [0, 28],
      );
    });
  });

  group('Source 1 — kDesignEffects / kCuratedEffectIds', () {
    test('design effects key on correct 0.15.1 IDs', () {
      // The 8 that were wrong pre-fix:
      expect(kDesignEffects[13], 'Theater Chase'); // was sent as 12 (Fade)
      expect(kDesignEffects[88], 'Candle'); // was 37 (Chase 2)
      expect(kDesignEffects[17], 'Twinkle'); // was 44 (Tetrix)
      expect(kDesignEffects[74], 'Colortwinkles'); // was 63 (Pride 2015)
      expect(kDesignEffects[65], 'Palette'); // was 74 (Colortwinkles)
      expect(kDesignEffects[79], 'Ripple'); // was 80 (Twinklefox)
      expect(kDesignEffects[101], 'Pacifica'); // was 97 (Plasma)
      expect(kDesignEffects[66], 'Fire'); // "Fire" -> Fire 2012 (66)
      // The 3 that were already correct:
      expect(kDesignEffects[0], 'Solid');
      expect(kDesignEffects[9], 'Rainbow');
      expect(kDesignEffects[42], 'Fireworks');
      // No stale numeric keys remain:
      expect(kDesignEffects.containsKey(12), isFalse);
      expect(kDesignEffects.containsKey(37), isFalse);
      expect(kDesignEffects.containsKey(44), isFalse);
    });

    test('curated list is a subset (no Blink/Fire/Fireworks) with valid IDs', () {
      expect(kCuratedEffectIds, [0, 2, 9, 13, 28, 88, 17, 74, 65, 79, 101]);
      // Every curated id is a real 0.15.1 effect:
      for (final fx in kCuratedEffectIds) {
        expect(WledEffectsCatalog.getById(fx), isNotNull);
      }
    });
  });

  group('Source 4 — EffectDatabase re-key + drops + audio exclusion', () {
    test('entries are keyed by real 0.15.1 ID matching the name', () {
      expect(EffectDatabase.effects[88]?.name, 'Candle'); // was key 37
      expect(EffectDatabase.effects[42]?.name, 'Fireworks'); // was key 39
      expect(EffectDatabase.effects[52]?.name, 'Running Dual'); // was key 41
      expect(EffectDatabase.effects[57]?.name, 'Lightning'); // was key 46
      expect(EffectDatabase.effects[90]?.name, 'Fireworks 1D'); // was key 53 (RSVD)
      expect(EffectDatabase.effects[110]?.name, 'Flow'); // was key 95
      expect(EffectDatabase.effects[128]?.name, 'Pixels'); // was key 102
      expect(EffectDatabase.effects[10]?.name, 'Scan'); // was key 11
      expect(EffectDatabase.effects[33]?.name, 'Rainbow Cycle'); // remap -> Rainbow Runner id
    });

    test('inner metadata.id matches its catalog key', () {
      EffectDatabase.effects.forEach((key, meta) {
        expect(meta.id, key, reason: 'metadata.id must equal its key');
        expect(WledEffectsCatalog.getById(key), isNotNull,
            reason: 'every key must be a real 0.15.1 effect');
      });
    });

    test('fake/merged effects are dropped (omitted, not substituted)', () {
      final names = EffectDatabase.effects.values.map((e) => e.name).toSet();
      for (final fake in [
        'Tricolor Chase',
        'Tricolor Wipe',
        'Tricolor Fade',
        'Running Tri',
        'Halloween',
        'Chase Rainbow White',
        'Fire',
      ]) {
        expect(names.contains(fake), isFalse, reason: '$fake must be dropped');
      }
      // Fire 2012 survives the merge:
      expect(EffectDatabase.effects[66]?.name, 'Fire 2012');
    });

    test('no audio-reactive effect leaks into the DB (no menu gate exists)', () {
      for (final key in EffectDatabase.effects.keys) {
        expect(WledEffectsCatalog.getById(key)!.requiresAudio, isFalse,
            reason: 'audio fx $key must be excluded from EffectDatabase');
      }
      // The 8 drifted audio targets specifically:
      for (final audioId in [129, 130, 131, 132, 133, 134, 135, 136]) {
        expect(EffectDatabase.effects.containsKey(audioId), isFalse);
      }
    });

    test('getRecommendedEffectIds returns only valid, non-fake IDs', () {
      for (final scenario in [
        'christmas',
        'halloween',
        'party',
        '4th-of-july',
        'romantic',
        'relaxation',
        'sports',
        'wedding',
        'rainbow',
        'default',
      ]) {
        final ids = EffectDatabase.getRecommendedEffectIds(scenario: scenario);
        expect(ids, isNotEmpty, reason: '$scenario produced no effects');
        for (final fx in ids) {
          expect(WledEffectsCatalog.getById(fx), isNotNull,
              reason: '$scenario produced invalid fx $fx');
        }
      }
      // Spot-check a couple resolved scenarios:
      expect(EffectDatabase.getRecommendedEffectIds(scenario: 'sports'),
          containsAll([28, 15, 52, 42, 20]));
      expect(EffectDatabase.getRecommendedEffectIds(scenario: 'rainbow'),
          [9, 33, 63, 30, 14]);
    });
  });

  group('Source 3 — kColorwayEffectIds exotic half', () {
    test('exotic IDs are the corrected 0.15.1 values', () {
      // Classic half stays correct; exotic half re-numbered.
      expect(PatternRepository.kColorwayEffectIds, containsAll([80, 79, 67, 38, 75, 101, 97, 110]));
      // The old drifted exotic IDs are gone:
      for (final old in [46, 52, 65, 69, 70, 73, 82, 107]) {
        expect(PatternRepository.kColorwayEffectIds.contains(old), isFalse,
            reason: 'old exotic id $old must be remapped');
      }
      for (final fx in PatternRepository.kColorwayEffectIds) {
        expect(WledEffectsCatalog.getById(fx), isNotNull);
      }
    });
  });
}
