// Build 120 (owner decision 2026-10-22): Lightning (57) flashes several
// times a second inside every strike whatever the speed, and the Halloween
// palettes suggested it at speed 128 in the Neighborhood Sync picker. The
// suggestions are gone; every palette still suggests something.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/data/holiday_palettes.dart';
import 'package:nexgen_command/features/wled/pattern_flash_safety.dart';

void main() {
  test('no Halloween palette suggests Lightning, and each still suggests '
      'at least one effect', () {
    final halloween = HolidayPalettes.halloween;
    expect(halloween.length, greaterThanOrEqualTo(9));
    for (final p in halloween) {
      expect(p.suggestedEffects, isNot(contains(kLightningEffectId)),
          reason: p.id);
      expect(p.suggestedEffects, isNotEmpty, reason: p.id);
    }
  });

  test('the three that used to lead with Lightning now lead with a slow '
      'effect: Twinkle or Blink', () {
    final byId = {for (final p in HolidayPalettes.halloween) p.id: p};
    expect(byId['halloween_classic']!.suggestedEffects, [43, 0]);
    expect(byId['halloween_hauntedhouse']!.suggestedEffects, [43, 0]);
    expect(byId['halloween_franken']!.suggestedEffects, [1, 0]);
  });
}
