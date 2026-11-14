// Build 129 — per-pixel brightness in Design Studio.
//
// A pixel's brightness is kept APART from its colour: `LedColorGroup.bri`
// (0–255, absent = full) and a second sparse layer in PixelDesignDocument.
// What reaches the lights is the LIT colour — the colour scaled so the light
// output is bri/255 of full, through the inverse of the controller's gamma
// 2.8 — and every design saved before build 129 reads back unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/design_frame.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';

import '../../helpers/wled_strip_simulator.dart';

PixelDesignDocument _doc({int len = 12}) => PixelDesignDocument.blank(
      baseColor: const [10, 10, 12, 0],
      channelLengths: {0: len},
    );

void main() {
  group('LedColorGroup.bri', () {
    test('absent in JSON reads as full; full is omitted on write; a dim level round-trips', () {
      final old = LedColorGroup.fromJson({'start_led': 0, 'end_led': 4, 'color': [255, 0, 0, 0]});
      expect(old.bri, kLedGroupFullBrightness);
      expect(old.isDimmed, isFalse);
      expect(old.toJson(), {'start_led': 0, 'end_led': 4, 'color': [255, 0, 0, 0]},
          reason: 'an unedited design re-saves byte-identical');

      final dim = LedColorGroup(startLed: 0, endLed: 0, color: const [255, 0, 0, 0], bri: 102);
      final back = LedColorGroup.fromJson(dim.toJson());
      expect(back.bri, 102);
      expect(dim.toJson()['bri'], 102);
    });

    test('litColor is the colour at the brightness, gamma-compensated, W included', () {
      // 40 % of the light (bri 102) needs value 184 on a 255 channel
      final g = LedColorGroup(startLed: 0, endLed: 0, color: const [255, 255, 255, 200], bri: 102);
      expect(g.litColor, [184, 184, 184, 144]);
      expect(gamma8(184) / 255, closeTo(0.40, 0.01), reason: 'what the controller then lights');
      expect(LedColorGroup(startLed: 0, endLed: 0, color: const [255, 0, 0], bri: 255).litColor, [255, 0, 0, 0]);
      expect(LedColorGroup(startLed: 0, endLed: 0, color: const [255, 0, 0, 0], bri: 0).litColor, [0, 0, 0, 0]);
    });

    test('positionalSpans send the lit colour, so every apply path and the API preset honour it', () {
      final ch = ChannelDesign(
        channelId: 0,
        channelName: 'Front',
        ledCount: 4,
        colorGroups: [
          LedColorGroup(startLed: 0, endLed: 1, color: const [255, 0, 0, 0]),
          LedColorGroup(startLed: 2, endLed: 3, color: const [255, 0, 0, 0], bri: 102),
        ],
      );
      final spans = ch.positionalSpans();
      expect(spans[0].color, [255, 0, 0, 0]);
      expect(spans[1].color, [184, 0, 0, 0]);
    });
  });

  group('PixelDesignDocument brightness layer', () {
    test('dimming never touches colour, painting never touches brightness', () {
      var d = _doc().paint(0, [2, 3], const [255, 0, 0, 0]);
      d = d.setBrightness(0, [3, 4], 102);
      expect(d.colorAt(0, 3), [255, 0, 0, 0]);
      expect(d.brightnessAt(0, 3), 102);
      expect(d.colorAt(0, 4), [10, 10, 12, 0], reason: 'base colour, dimmed');
      expect(d.brightnessAt(0, 4), 102);
      expect(d.brightnessAt(0, 2), kLedGroupFullBrightness);
      d = d.paint(0, [3], const [0, 255, 0, 0]);
      expect(d.brightnessAt(0, 3), 102, reason: 're-painting keeps the level');
      expect(d.litColorAt(0, 3), [0, 184, 0, 0]);
      expect(d.dimmedCount, 2);
    });

    test('Full removes the entry; Erase clears colour and brightness', () {
      var d = _doc().paint(0, [1], const [255, 0, 0, 0]).setBrightness(0, [1, 2], 51);
      d = d.setBrightness(0, [2], 255);
      expect(d.isDimmed(0, 2), isFalse);
      expect(d.dimmedCount, 1);
      d = d.clearToBase(0, [1]);
      expect(d.isPainted(0, 1), isFalse);
      expect(d.isDimmed(0, 1), isFalse);
    });

    test('runs split on brightness as well as colour and round-trip losslessly', () {
      final d = _doc(len: 8)
          .paint(0, [0, 1, 2, 3], const [255, 0, 0, 0])
          .setBrightness(0, [2, 3], 102)
          .setBrightness(0, [6, 7], 204);
      final groups = d.toLedColorGroups()[0]!;
      expect(groups.map((g) => [g.startLed, g.endLed, g.bri]).toList(), [
        [0, 1, 255],
        [2, 3, 102],
        [4, 5, 255],
        [6, 7, 204],
      ]);
      final back = PixelDesignDocument.fromLedColorGroups(
        baseColor: const [10, 10, 12, 0],
        channelLengths: {0: 8},
        groupsByChannel: {0: groups},
      );
      for (var i = 0; i < 8; i++) {
        expect(back.colorAt(0, i), d.colorAt(0, i), reason: 'colour px $i');
        expect(back.brightnessAt(0, i), d.brightnessAt(0, i), reason: 'bri px $i');
      }
    });

    test('onlyPainted treats a dimmed base pixel as painted (it must reach the lights)', () {
      final d = _doc(len: 6).setBrightness(0, [4], 128);
      final groups = d.toLedColorGroups(onlyPainted: true)[0]!;
      expect(groups, hasLength(1));
      expect(groups.single.startLed, 4);
      expect(groups.single.bri, 128);
      expect(_doc(len: 6).toLedColorGroups(onlyPainted: true), isEmpty);
    });

    test('a saved design without bri opens at full brightness, pixel for pixel', () {
      final groups = [
        LedColorGroup.fromJson({'start_led': 0, 'end_led': 11, 'color': [255, 170, 90, 0]}),
      ];
      final d = PixelDesignDocument.fromLedColorGroups(
          baseColor: const [0, 0, 0, 0], channelLengths: {0: 12}, groupsByChannel: {0: groups});
      expect(d.dimmedCount, 0);
      expect(d.litColorAt(0, 5), [255, 170, 90, 0]);
    });

    test('the preview frame shows the lit colour, so a dim pixel looks dim', () {
      final d = _doc(len: 2).paint(0, [0, 1], const [255, 0, 0, 0]).setBrightness(0, [1], 102);
      final frame = frameFromDocument(d);
      expect((frame[0]![0].r * 255).round(), 255);
      expect((frame[0]![1].r * 255).round(), 184);
    });

    test('what the controller renders from the saved groups matches the intended light', () {
      final d = _doc(len: 4).paint(0, [0, 1, 2, 3], const [255, 255, 255, 0]).setBrightness(0, [1], 204).setBrightness(0, [2], 102).setBrightness(0, [3], 26);
      final ch = ChannelDesign(channelId: 0, channelName: 'c', ledCount: 4, colorGroups: d.toLedColorGroups()[0]!);
      final spans = ch.fullCoverageSpans();
      final i = <dynamic>[];
      for (final s in spans) {
        i.addAll([s.start, s.end + 1, s.color]);
      }
      final lit = const WledStripSimulator().render({'fx': 0, 'i': i}, 4);
      final levels = lightLevels(lit);
      expect(levels[0], closeTo(100, 1));
      expect(levels[1], closeTo(80, 3));
      expect(levels[2], closeTo(40, 3));
      expect(levels[3], closeTo(10, 3));
    });
  });

  group('brightnessRamp', () {
    test('linear in light from start to end, in the order given', () {
      final r = brightnessRamp([10, 11, 12, 13, 14], startPct: 100, endPct: 40);
      expect(r, {10: 255, 11: 217, 12: 179, 13: 140, 14: 102});
    });
    test('mirror: bright at both ends, dim in the middle', () {
      final r = brightnessRamp([0, 1, 2, 3, 4], startPct: 100, endPct: 40, mirror: true);
      expect(r[0], 255);
      expect(r[2], 102);
      expect(r[4], 255);
      expect(r[1], r[3]);
    });
    test('one index gets the start level; none gives nothing', () {
      expect(brightnessRamp([7], startPct: 60, endPct: 0), {7: 153});
      expect(brightnessRamp([], startPct: 60, endPct: 0), isEmpty);
    });
  });
}
