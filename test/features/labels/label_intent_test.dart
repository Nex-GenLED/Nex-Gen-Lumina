import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/labels/label_intent.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';

WledStateModel _state({
  int effectId = 0,
  int presetId = 0,
  Color color = const Color(0xFFFFFFFF),
  List<Color> colorSequence = const [],
}) {
  return WledStateModel(
    isOn: true,
    brightness: 200,
    speed: 128,
    intensity: 128,
    color: color,
    connected: true,
    warmWhite: 0,
    supportsRgbw: false,
    effectId: effectId,
    paletteId: 0,
    presetId: presetId,
    reverse: false,
    colorSequence: colorSequence,
    colorNames: const [],
    customEffectName: null,
    colorGroupSize: 1,
    spacing: 0,
  );
}

void main() {
  group('LabelIntent.fingerprintForState', () {
    test('single color from colorSequence → 6-char hex', () {
      final fp = LabelIntent.fingerprintForState(
        _state(colorSequence: const [Color(0xFFFF0000)]),
      );
      expect(fp, 'ff0000');
    });

    test('two colors → 12-char hex', () {
      final fp = LabelIntent.fingerprintForState(
        _state(colorSequence: const [Color(0xFFFF0000), Color(0xFF00FF00)]),
      );
      expect(fp, 'ff000000ff00');
    });

    test('three colors → 12-char hex (truncated from 18)', () {
      final fp = LabelIntent.fingerprintForState(
        _state(colorSequence: const [
          Color(0xFFFF0000),
          Color(0xFF00FF00),
          Color(0xFF0000FF),
        ]),
      );
      expect(fp, 'ff000000ff00');
      expect(fp.length, 12);
    });

    test('empty colorSequence falls back to color field', () {
      final fp = LabelIntent.fingerprintForState(
        _state(color: const Color(0xFFABCDEF)),
      );
      expect(fp, 'abcdef');
    });

    test('color order matters — same colors different order → different fp', () {
      final a = LabelIntent.fingerprintForState(
        _state(colorSequence: const [Color(0xFFFF0000), Color(0xFF00FF00)]),
      );
      final b = LabelIntent.fingerprintForState(
        _state(colorSequence: const [Color(0xFF00FF00), Color(0xFFFF0000)]),
      );
      expect(a, isNot(b));
    });
  });

  group('LabelIntent.matches', () {
    final base = LabelIntent(
      label: 'KC Royals Twinkle',
      effectId: 43,
      presetId: 0,
      colorFingerprint: 'ff0000ffd700',
      writtenAt: DateTime(2026, 5, 12),
    );

    test('exact device state → matches', () {
      final device = _state(
        effectId: 43,
        presetId: 0,
        colorSequence: const [Color(0xFFFF0000), Color(0xFFFFD700)],
      );
      expect(base.matches(device), isTrue);
    });

    test('effectId mismatch → no match', () {
      final device = _state(
        effectId: 12, // ← was 43
        presetId: 0,
        colorSequence: const [Color(0xFFFF0000), Color(0xFFFFD700)],
      );
      expect(base.matches(device), isFalse);
    });

    test('presetId mismatch → no match', () {
      final device = _state(
        effectId: 43,
        presetId: 7, // ← was 0
        colorSequence: const [Color(0xFFFF0000), Color(0xFFFFD700)],
      );
      expect(base.matches(device), isFalse);
    });

    test('color mismatch → no match', () {
      final device = _state(
        effectId: 43,
        presetId: 0,
        colorSequence: const [Color(0xFFFFFFFF)], // ← warm white instead
      );
      expect(base.matches(device), isFalse);
    });
  });

  group('LabelIntent JSON round-trip', () {
    test('toJson → fromJson → equal fields', () {
      final original = LabelIntent(
        label: 'Diamond Family Shimmer',
        effectId: 84,
        presetId: 3,
        colorFingerprint: '0080ffffd700',
        writtenAt: DateTime.utc(2026, 5, 12, 14, 30),
      );
      final json = original.toJson();
      final restored = LabelIntent.fromJson(json)!;
      expect(restored.label, original.label);
      expect(restored.effectId, original.effectId);
      expect(restored.presetId, original.presetId);
      expect(restored.colorFingerprint, original.colorFingerprint);
      expect(restored.writtenAt, original.writtenAt);
    });

    test('encode → decode round-trip', () {
      final original = LabelIntent(
        label: 'Blue Line Bar Mood',
        effectId: 0,
        presetId: 0,
        colorFingerprint: '0040ff',
        writtenAt: DateTime.utc(2026, 5, 12),
      );
      final encoded = original.encode();
      final restored = LabelIntent.decode(encoded)!;
      expect(restored.matches(_state(
        effectId: 0,
        colorSequence: const [Color(0xFF0040FF)],
      )), isTrue);
    });

    test('fromJson with missing label → null', () {
      expect(
        LabelIntent.fromJson({
          'effectId': 0,
          'presetId': 0,
          'colorFingerprint': '',
          'writtenAt': '2026-05-12T00:00:00.000Z',
        }),
        isNull,
      );
    });

    test('fromJson with non-int effectId → null', () {
      expect(
        LabelIntent.fromJson({
          'label': 'X',
          'effectId': 'forty-three',
          'presetId': 0,
          'colorFingerprint': '',
          'writtenAt': '2026-05-12T00:00:00.000Z',
        }),
        isNull,
      );
    });

    test('decode of garbage string → null', () {
      expect(LabelIntent.decode('not json'), isNull);
      expect(LabelIntent.decode(''), isNull);
      expect(LabelIntent.decode('[]'), isNull); // not an object
    });
  });
}
