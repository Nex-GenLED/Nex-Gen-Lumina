// Tests for colorRgbToName — the promoted color-naming utility used by
// Now Playing label composition (Bug A / Fix 3) and (eventually) the
// scene_providers.dart caller that still owns the private duplicate.
//
// The function inspects RGB only (W channel ignored — WLED appends W
// automatically on RGBW bus types and the named palette is the RGB
// branding) and returns one of 9 named colors or "custom" / "unknown".

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/utils/color_naming.dart';

void main() {
  group('colorRgbToName — named-color buckets', () {
    test('vivid red → "red"', () {
      expect(colorRgbToName(const [255, 0, 0]), equals('red'));
      expect(colorRgbToName(const [220, 30, 30]), equals('red'));
    });

    test('vivid green → "green"', () {
      expect(colorRgbToName(const [0, 255, 0]), equals('green'));
      expect(colorRgbToName(const [40, 220, 50]), equals('green'));
    });

    test('vivid blue → "blue"', () {
      expect(colorRgbToName(const [0, 0, 255]), equals('blue'));
      expect(colorRgbToName(const [50, 60, 230]), equals('blue'));
    });

    test('white → "white"', () {
      expect(colorRgbToName(const [255, 255, 255]), equals('white'));
      expect(colorRgbToName(const [220, 220, 220]), equals('white'));
    });

    test('yellow → "yellow"', () {
      expect(colorRgbToName(const [255, 255, 0]), equals('yellow'));
      expect(colorRgbToName(const [220, 220, 30]), equals('yellow'));
    });

    test('orange → "orange"', () {
      expect(colorRgbToName(const [255, 165, 0]), equals('orange'));
    });

    test('purple → "purple"', () {
      expect(colorRgbToName(const [180, 0, 255]), equals('purple'));
    });

    test('cyan → "cyan"', () {
      expect(colorRgbToName(const [0, 255, 255]), equals('cyan'));
      expect(colorRgbToName(const [50, 220, 220]), equals('cyan'));
    });

    test('pink → "pink"', () {
      expect(colorRgbToName(const [255, 100, 200]), equals('pink'));
    });
  });

  group('colorRgbToName — fallbacks', () {
    test('pad slot [0,0,0] (post-Fix-2 zero pad) → "custom"', () {
      // After Fix 2, every apply payload pads col to 3 slots with
      // [0,0,0,0]. Label composition must recognize these as
      // unnameable and drop them from the assembled list.
      expect(colorRgbToName(const [0, 0, 0]), equals('custom'));
      expect(colorRgbToName(const [0, 0, 0, 0]), equals('custom'));
    });

    test('short array (<3 channels) → "unknown"', () {
      expect(colorRgbToName(const []), equals('unknown'));
      expect(colorRgbToName(const [255]), equals('unknown'));
      expect(colorRgbToName(const [255, 0]), equals('unknown'));
    });

    test('mid-saturation values that match no named bucket → "custom"', () {
      // Muted teal-ish, no clean named bucket.
      expect(colorRgbToName(const [120, 140, 150]), equals('custom'));
    });

    test('RGBW (4-channel) input — W is ignored, RGB drives the name', () {
      expect(colorRgbToName(const [255, 0, 0, 0]), equals('red'));
      expect(colorRgbToName(const [255, 0, 0, 200]), equals('red'));
      expect(colorRgbToName(const [0, 0, 255, 50]), equals('blue'));
    });
  });
}
