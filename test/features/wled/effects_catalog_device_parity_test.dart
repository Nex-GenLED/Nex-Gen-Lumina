import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

/// Locks WledEffectsCatalog name lookups against the WLED 0.15.1 device
/// /json/effects array captured 2026-05-29 from the bench controller
/// (192.168.1.250). #82 — previous kEffectNames map was off-by-one from
/// ~id 37 onward, mislabeling 83 as "Halloween Eyes" when the device
/// actually renders "Solid Pattern" there.
void main() {
  group('WledEffectsCatalog.getName matches device /json/effects', () {
    // Spot indices the previous kEffectNames table got wrong.
    test('id 37 → "Chase 2"', () {
      expect(WledEffectsCatalog.getName(37), 'Chase 2');
    });

    test('id 40 → "Scanner"', () {
      expect(WledEffectsCatalog.getName(40), 'Scanner');
    });

    test('id 76 → "Meteor"', () {
      expect(WledEffectsCatalog.getName(76), 'Meteor');
    });

    test('id 80 → "Twinklefox"', () {
      expect(WledEffectsCatalog.getName(80), 'Twinklefox');
    });

    test('id 82 → "Halloween Eyes"', () {
      expect(WledEffectsCatalog.getName(82), 'Halloween Eyes');
    });

    test('id 83 → "Solid Pattern" (multi-color solid substitution target)', () {
      expect(WledEffectsCatalog.getName(83), 'Solid Pattern');
    });

    test('id 84 → "Solid Pattern Tri"', () {
      expect(WledEffectsCatalog.getName(84), 'Solid Pattern Tri');
    });

    // Slots the catalog comment had marked as retired but device exposes.
    test('id 48 → "Rolling Balls"', () {
      expect(WledEffectsCatalog.getName(48), 'Rolling Balls');
    });

    test('id 114 → "Rotozoomer"', () {
      expect(WledEffectsCatalog.getName(114), 'Rotozoomer');
    });

    // Baseline + tail anchors.
    test('id 0 → "Solid"', () {
      expect(WledEffectsCatalog.getName(0), 'Solid');
    });

    test('id 186 → "Akemi" (last device entry)', () {
      expect(WledEffectsCatalog.getName(186), 'Akemi');
    });

    test('unknown id falls back to "Effect #N"', () {
      expect(WledEffectsCatalog.getName(9999), 'Effect #9999');
    });
  });
}
