// Build 120 (owner decision 2026-10-22): the two Nature & Outdoors palettes
// that suggested Lightning (57) — Stormy Seas and Thunderstorm — keep their
// other effects and lose Lightning, pinned like the Halloween trio.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/data/nature_outdoors_palettes.dart';
import 'package:nexgen_command/features/wled/pattern_flash_safety.dart';

void main() {
  final nodes = NatureOutdoorsPalettes.getAllNaturePaletteNodes();

  test('no Nature & Outdoors palette suggests Lightning, and each still '
      'suggests at least one effect', () {
    expect(nodes.length, greaterThan(20));
    for (final n in nodes) {
      expect(n.suggestedEffects, isNot(contains(kLightningEffectId)),
          reason: n.id);
      expect(n.suggestedEffects, isNotEmpty, reason: n.id);
    }
  });

  test('Stormy Seas keeps Ripple and Twinkle; Thunderstorm keeps Blink and '
      'Strobe; their speeds and intensities are unchanged', () {
    final byId = {for (final n in nodes) n.id: n};
    final stormy = byId['ocean_stormy']!;
    expect(stormy.suggestedEffects, [79, 43]);
    expect(stormy.defaultSpeed, 150);
    expect(stormy.defaultIntensity, 200);
    final thunder = byId['mountain_thunderstorm']!;
    expect(thunder.suggestedEffects, [1, 23]);
    expect(thunder.defaultSpeed, 200);
    expect(thunder.defaultIntensity, 220);
  });
}
