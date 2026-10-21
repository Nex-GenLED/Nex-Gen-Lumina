// Build 120 — the celebration cap table (owner decision 2026-10-21).
// Celebrations fire unattended in many houses, so they respect the same
// ceiling as the effect walk: no more than about 3 flashes or bursts per
// second on the strip.
//   • Strobe family: kStrobeSpeedCap (230, interim until the probed ceiling).
//   • Lightning: withdrawn from the picker; a saved one maps to 40 / 60.
//   • Everything else: the speed profile's recommended maximum.
//   • The picker's missing-value default is the capped value, not 240.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/services/celebration_contrast.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/wled/pattern_flash_safety.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

void main() {
  group('capCelebration', () {
    test('the strobe family never exceeds the interim cap of 230', () {
      expect(kStrobeSpeedCap, 230);
      for (final fx in [23, 24]) {
        expect(capCelebration(fx, 255, 255), (sx: 230, ix: 255));
        expect(capCelebration(fx, 100, 255), (sx: 100, ix: 255));
      }
      // A retired Strobe Mega plays as Strobe, capped the same way.
      expect(capCelebration(25, 255, 128).sx, 230);
    });

    test('Lightning maps to speed 40 / intensity 60 whatever was saved', () {
      expect(capCelebration(57, 240, 240), (sx: 40, ix: 60));
      expect(capCelebration(57, 10, 10), (sx: 40, ix: 60));
      expect(kLightningCelebrationSpeed, 40);
      expect(kLightningCelebrationIntensity, 60);
    });

    test('every other picker effect is capped at its profile maximum', () {
      for (final fx in WledEffectsCatalog.celebrationPickIds) {
        if (kSpeedCappedFlashEffectIds.contains(fx)) continue;
        final max = getSpeedProfile(fx).rawRecommendedMax;
        expect(capCelebration(fx, 255, 200), (sx: max, ix: 200),
            reason: 'fx $fx');
        expect(capCelebration(fx, max - 1, 200).sx, max - 1, reason: 'fx $fx');
      }
      // Spot values from the profile table, so a table edit is noticed.
      expect(capCelebration(28, 255, 0).sx, 190); // Chase
      expect(capCelebration(76, 255, 0).sx, 120); // Meteor
      expect(capCelebration(42, 255, 0).sx, 140); // Fireworks
    });

    test('an effect without a profile falls to the general maximum', () {
      expect(capCelebration(999, 255, 0).sx,
          getSpeedProfile(999).rawRecommendedMax);
    });

    test('the picker default is the capped value, never 240', () {
      expect(celebrationDefaultSpeedFor(23), 230);
      expect(celebrationDefaultSpeedFor(57), 40);
      expect(celebrationDefaultIntensityFor(57), 60);
      expect(celebrationDefaultSpeedFor(28), 190);
      expect(celebrationDefaultIntensityFor(28), 240);
    });
  });

  group('resolveCelebration applies the table', () {
    test('a chosen Chase at 255 resolves at the profile maximum', () {
      final r = resolveCelebration(
        chosenEffectId: 28,
        chosenSpeed: 255,
        chosenIntensity: 200,
        capturedState: null,
      );
      expect(r!.effectId, 28);
      expect(r.speed, 190);
      expect(r.intensity, 200);
    });

    test('a chosen Strobe at 255 resolves at 230', () {
      final r = resolveCelebration(
        chosenEffectId: 23,
        chosenSpeed: 255,
        chosenIntensity: 255,
        capturedState: null,
      );
      expect(r!.speed, 230);
    });

    test('the fallback itself runs at the strobe cap', () {
      expect(kFallbackCelebrationSpeed, kStrobeSpeedCap);
    });

    test('Lightning is not in the picker but a saved one resolves mapped', () {
      expect(WledEffectsCatalog.celebrationPickIds, isNot(contains(57)));
      final r = resolveCelebration(
        chosenEffectId: 57,
        chosenSpeed: 240,
        chosenIntensity: 240,
        capturedState: null,
      );
      expect(r!.effectId, 57);
      expect(r.speed, 40);
      expect(r.intensity, 60);
    });
  });
}
