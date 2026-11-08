// Roofline slice 3 — the colour summary of a saved design
// (`designColorSummaryOf`, the first reader of the stored `composed_pattern`
// layer beyond the motion fields) and the "Variations of …" base
// (`variationBaseFor`: stamped designs only).
//
// New behaviour. Pure: no device, no provider container.
//
// Fixture: three buses of 100 LEDs (ids 0, 1, 2), stamped for ctl-a.

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_color_summary.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';

final _now = DateTime(2026, 11, 5);
const kStamp = DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]);

/// Painted on three buses: red / blue halves on bus 1, ten white on bus 2
/// over the editor's near-black base, bus 3 all base.
CustomDesign _painted({DesignLayoutStamp? stamp = kStamp}) => CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'customer-uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      layoutStamp: stamp,
      channels: const [
        ChannelDesign(channelId: 0, channelName: 'Channel 1', ledCount: 100, colorGroups: [
          LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
          LedColorGroup(startLed: 50, endLed: 99, color: [0, 0, 255, 0]),
        ]),
        ChannelDesign(channelId: 1, channelName: 'Channel 2', ledCount: 100, colorGroups: [
          LedColorGroup(startLed: 0, endLed: 9, color: [255, 255, 255, 0]),
          LedColorGroup(startLed: 10, endLed: 99, color: [10, 10, 12, 0]),
        ]),
        ChannelDesign(channelId: 2, channelName: 'Channel 3', ledCount: 100, colorGroups: [
          LedColorGroup(startLed: 0, endLed: 99, color: [10, 10, 12, 0]),
        ]),
      ],
    );

void main() {
  group('shares from the picture (every design has one)', () {
    test('a painted design: lit colours by share, largest first, unlit counted', () {
      final s = designColorSummaryOf(_painted());
      expect(s.swatches.map((w) => w.rgbw), [
        [255, 0, 0, 0],
        [0, 0, 255, 0],
        [255, 255, 255, 0],
      ]);
      expect(s.swatches.map((w) => (w.share * 300).round()), [50, 50, 10]);
      // 90 near-black on bus 2 + 100 on bus 3, out of 300.
      expect((s.unlitShare * 300).round(), 190);
      expect(s.primary, const Color(0xFFFF0000));
      expect(s.secondary, const Color(0xFF0000FF));
      expect(s.accent, const Color(0xFFFFFFFF));
    });

    test('a gap the groups leave is unlit (full coverage, as the apply spine sees it)', () {
      final d = CustomDesign(
        id: 'd', name: 'Gap', ownerId: 'u', createdAt: _now, updatedAt: _now,
        perPixel: true,
        channels: const [
          ChannelDesign(channelId: 0, channelName: 'Ch1', ledCount: 100, colorGroups: [
            LedColorGroup(startLed: 40, endLed: 59, color: [0, 255, 0, 0]),
          ]),
        ],
      );
      final s = designColorSummaryOf(d);
      expect(s.swatches.single.rgbw, [0, 255, 0, 0]);
      expect((s.swatches.single.share * 100).round(), 20);
      expect((s.unlitShare * 100).round(), 80);
    });

    test('an effect design: its palette entries, weighted equally, no unlit', () {
      final d = CustomDesign(
        id: 'd', name: 'Look', ownerId: 'u', createdAt: _now, updatedAt: _now,
        channels: const [
          ChannelDesign(channelId: 0, channelName: 'Ch1', ledCount: 100, effectId: 28,
              colorGroups: [
                LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0]),
                LedColorGroup(startLed: 1, endLed: 1, color: [255, 215, 0]),
              ]),
        ],
      );
      final s = designColorSummaryOf(d);
      expect(s.swatches.map((w) => w.rgbw), [
        [255, 0, 0, 0],
        [255, 215, 0, 0],
      ]);
      expect(s.swatches.map((w) => (w.share * 100).round()), [50, 50]);
      expect(s.unlitShare, 0);
    });

    test('a design that paints nothing is empty', () {
      final d = CustomDesign(
        id: 'd', name: 'Blank', ownerId: 'u', createdAt: _now, updatedAt: _now,
        perPixel: true,
        channels: const [
          ChannelDesign(channelId: 0, channelName: 'Ch1', ledCount: 100, colorGroups: [
            LedColorGroup(startLed: 0, endLed: 99, color: [0, 0, 0, 0]),
          ]),
        ],
      );
      final s = designColorSummaryOf(d);
      expect(s.isEmpty, isTrue);
      expect(s.primary, isNull);
      expect(s.contextLines(), ['Colours: none lit']);
    });

    test('an excluded channel is not counted', () {
      final d = _painted().copyWith(channels: [
        for (final ch in _painted().channels)
          ch.channelId == 0 ? ch : ch.copyWith(included: false),
      ]);
      final s = designColorSummaryOf(d);
      expect(s.swatches.map((w) => w.rgbw), [
        [255, 0, 0, 0],
        [0, 0, 255, 0],
      ]);
      expect(s.unlitShare, 0);
    });
  });

  group('roles from the stored AI layer (the first composed_pattern reader)', () {
    test('the first layer\'s primary and the first stated secondary / accent win '
        'over the shares', () {
      final d = _painted().copyWith(composedPattern: {
        'source_intent': {
          'layers': [
            {
              'colors': {
                'primary_color': [255, 102, 0, 255],
                'secondary_color': null,
                'accent_color': null,
              },
            },
            {
              'colors': {
                'primary_color': [0, 0, 0, 255],
                'secondary_color': [128, 0, 128, 255],
                'accent_color': [255, 255, 255, 255],
              },
            },
          ],
        },
      });
      final s = designColorSummaryOf(d);
      expect(s.statedPrimary, const Color(0xFFFF6600));
      expect(s.statedSecondary, const Color(0xFF800080));
      expect(s.statedAccent, const Color(0xFFFFFFFF));
      expect(s.primary, const Color(0xFFFF6600));
      expect(s.secondary, const Color(0xFF800080));
      // The shares are still the picture's.
      expect(s.swatches.first.rgbw, [255, 0, 0, 0]);
    });

    test('a malformed layer states no roles and throws nothing', () {
      for (final cp in <Map<String, dynamic>>[
        {'source_intent': 'not a map'},
        {'source_intent': {'layers': 'nope'}},
        {'source_intent': {'layers': [1, 'x', null]}},
        {'source_intent': {'layers': [{'colors': {'primary_color': 'red'}}]}},
        {'source_intent': {'layers': [{'colors': {'primary_color': [1, 2]}}]}},
        {'effect_id': 28, 'has_motion': true},
      ]) {
        final s = designColorSummaryOf(_painted().copyWith(composedPattern: cp));
        expect(s.statedPrimary, isNull, reason: '$cp');
        expect(s.primary, const Color(0xFFFF0000), reason: 'falls back to the share');
      }
    });
  });

  group('the context lines carry numbers only', () {
    test('shares as whole percentages, no name, no id', () {
      final lines = designColorSummaryOf(_painted()).contextLines();
      expect(lines, [
        'Colours by share of lights: [255,0,0,0] 17%, [0,0,255,0] 17%, [255,255,255,0] 3%',
        'Unlit: 63%',
      ]);
      final text = lines.join('\n');
      expect(text, isNot(contains('Porch')));
      expect(text, isNot(contains('ctl-a')));
      expect(text, isNot(contains('customer-uid')));
    });
  });

  group('variationBaseFor — stamped designs only (owner decision 3)', () {
    test('a stamped design becomes a base carrying its stamp and colours', () {
      final base = variationBaseFor(_painted());
      expect(base, isNotNull);
      expect(base!.stamp, kStamp);
      expect(base.busLengthsByChannel, {0: 100, 1: 100, 2: 100});
      expect(base.colors.primary, const Color(0xFFFF0000));
      expect(base.design.id, 'd1');
    });

    test('an unstamped design gets no base', () {
      expect(variationBaseFor(_painted(stamp: null)), isNull);
    });
  });

  group('colorFromRgbw', () {
    test('plain RGB passes through; W folds in as warmth', () {
      expect(colorFromRgbw(const [255, 0, 0, 0]), const Color(0xFFFF0000));
      final warm = colorFromRgbw(const [0, 0, 0, 255]);
      expect(warm, isNot(const Color(0xFF000000)));
      expect(isUnlitRgbw(const [10, 10, 12, 0]), isTrue);
      expect(isUnlitRgbw(const [0, 0, 0, 40]), isFalse);
    });
  });
}
