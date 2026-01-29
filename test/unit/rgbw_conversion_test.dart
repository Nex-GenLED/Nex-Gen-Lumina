import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

void main() {
  group('rgbToRgbw', () {
    test('pure red produces [255, 0, 0, 0]', () {
      final result = rgbToRgbw(255, 0, 0);
      expect(result, [255, 0, 0, 0]);
    });

    test('pure green produces [0, 255, 0, 0]', () {
      final result = rgbToRgbw(0, 255, 0);
      expect(result, [0, 255, 0, 0]);
    });

    test('pure blue produces [0, 0, 255, 0]', () {
      final result = rgbToRgbw(0, 0, 255);
      expect(result, [0, 0, 255, 0]);
    });

    test('pure white extracts to white channel', () {
      final result = rgbToRgbw(255, 255, 255);
      // White component (min) = 255, so RGB becomes 0,0,0 and W = 255
      expect(result, [0, 0, 0, 255]);
    });

    test('gray extracts white component correctly', () {
      final result = rgbToRgbw(128, 128, 128);
      // min(128,128,128) = 128, so all RGB reduced by 128
      expect(result, [0, 0, 0, 128]);
    });

    test('warm white extracts partial white', () {
      // RGB warm white: (255, 200, 150)
      // min = 150, so W = 150
      // R = 255-150 = 105, G = 200-150 = 50, B = 150-150 = 0
      final result = rgbToRgbw(255, 200, 150);
      expect(result, [105, 50, 0, 150]);
    });

    test('explicit white value overrides auto-calculation', () {
      final result = rgbToRgbw(255, 128, 64, explicitWhite: 200);
      // With explicit white, RGB stays unchanged
      expect(result, [255, 128, 64, 200]);
    });

    test('explicit white clamps to 255', () {
      final result = rgbToRgbw(100, 100, 100, explicitWhite: 300);
      expect(result[3], 255);
    });

    test('explicit white clamps to 0', () {
      final result = rgbToRgbw(100, 100, 100, explicitWhite: -50);
      expect(result[3], 0);
    });

    test('forceZeroWhite sets W to 0', () {
      final result = rgbToRgbw(255, 255, 255, forceZeroWhite: true);
      // Even though this is white, force W=0
      expect(result, [255, 255, 255, 0]);
    });

    test('black produces [0, 0, 0, 0]', () {
      final result = rgbToRgbw(0, 0, 0);
      expect(result, [0, 0, 0, 0]);
    });

    test('cyan (no red) extracts white from min', () {
      // Cyan: (0, 255, 255)
      // min = 0, so no white extraction
      final result = rgbToRgbw(0, 255, 255);
      expect(result, [0, 255, 255, 0]);
    });

    test('pastel color extracts white correctly', () {
      // Pastel pink: (255, 200, 200)
      // min = 200, W = 200
      // R = 55, G = 0, B = 0
      final result = rgbToRgbw(255, 200, 200);
      expect(result, [55, 0, 0, 200]);
    });
  });
}
