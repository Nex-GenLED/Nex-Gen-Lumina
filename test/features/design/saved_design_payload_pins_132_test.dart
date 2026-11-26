// Build 132 — wire payloads for saved designs and cards, PINNED byte for byte.
//
// Build 132 changes which screen a saved design opens on, how the Pattern
// Editor saves a design it was opened from, a hint under Home's Color
// Sequence and the Favorites picker's refusal sentence. None of that may
// change a single byte any saved design or card sends. Each payload
// expectation below was captured at build 131 (3191e4b0) and is compared as
// the exact `jsonEncode` string, so key ORDER is pinned as well as values.
// The ONE deliberate change is the card page's palette group, moved to the
// first included channel's colours in build 132 (see that group).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';

final _t = DateTime(2026, 11, 1);

/// The shape Now Playing / "Save As Custom Pattern" writes: one colour group
/// spanning each channel, the running effect on every channel.
CustomDesign nowPlayingShape() => CustomDesign(
      id: 'np1',
      name: 'Captured',
      createdAt: _t,
      updatedAt: _t,
      ownerId: 'u',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 127, color: [255, 0, 34, 0]),
          ],
          effectId: 28,
          speed: 44,
          intensity: 90,
          ledCount: 128,
          grouping: 2,
          spacing: 3,
        ),
        ChannelDesign(
          channelId: 1,
          channelName: 'Garage',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 161, color: [255, 0, 34, 0]),
          ],
          effectId: 28,
          speed: 44,
          intensity: 90,
          ledCount: 162,
          grouping: 2,
          spacing: 3,
        ),
      ],
      brightness: 150,
      brightnessStated: true,
    );

/// The shape the Pattern Editor writes for an animated pattern with one action
/// colour and a background: two colour slots, the same on every channel.
CustomDesign editorAnimatedShape() => CustomDesign(
      id: 'pe1',
      name: 'Blue Chase',
      createdAt: _t,
      updatedAt: _t,
      ownerId: 'u',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Channel 1',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 0, color: [0, 0, 255, 0]),
            LedColorGroup(startLed: 1, endLed: 1, color: [0, 0, 0, 0]),
          ],
          effectId: 28,
          speed: 44,
          intensity: 90,
          ledCount: 128,
        ),
        ChannelDesign(
          channelId: 1,
          channelName: 'Channel 2',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 0, color: [0, 0, 255, 0]),
            LedColorGroup(startLed: 1, endLed: 1, color: [0, 0, 0, 0]),
          ],
          effectId: 28,
          speed: 44,
          intensity: 90,
          ledCount: 162,
        ),
      ],
      brightness: 200,
      brightnessStated: true,
      tags: const [kPatternEditorDesignTag],
    );

/// The Pattern Editor's Static pattern with three colours: fx 0, Alternating.
CustomDesign editorStaticShape() => CustomDesign(
      id: 'pe2',
      name: 'Tricolour',
      createdAt: _t,
      updatedAt: _t,
      ownerId: 'u',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Channel 1',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0, 0]),
            LedColorGroup(startLed: 1, endLed: 1, color: [0, 255, 0, 0]),
            LedColorGroup(startLed: 2, endLed: 2, color: [0, 0, 255, 0]),
          ],
          effectId: 0,
          grouping: 2,
          solidLayout: SolidLayout.alternating,
          ledCount: 128,
        ),
      ],
      brightness: 180,
      brightnessStated: true,
      tags: const [kPatternEditorDesignTag],
    );

/// A painted design: positional runs, stated per-pixel.
CustomDesign paintedShape() => CustomDesign(
      id: 'p1',
      name: 'Painted',
      createdAt: _t,
      updatedAt: _t,
      ownerId: 'u',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          ledCount: 6,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 2, color: [255, 0, 0, 0]),
            LedColorGroup(startLed: 3, endLed: 5, color: [0, 0, 255, 0]),
          ],
        ),
      ],
      brightness: 120,
      perPixel: true,
    );

/// A one-colour Solid captured from Home.
CustomDesign solidShape() => CustomDesign(
      id: 's1',
      name: 'Warm',
      createdAt: _t,
      updatedAt: _t,
      ownerId: 'u',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 127, color: [255, 180, 100, 0]),
          ],
          ledCount: 128,
        ),
        ChannelDesign(
          channelId: 1,
          channelName: 'Garage',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 161, color: [255, 180, 100, 0]),
          ],
          ledCount: 162,
        ),
      ],
      brightness: 160,
      brightnessStated: true,
    );

List<int> _argb(ColorwayEffectSelectorPage page) => [
      for (final c in page.paletteNode.themeColors ?? const <Color>[])
        c.toARGB32(),
    ];

void main() {
  group('a saved design sends exactly what it sent at build 131', () {
    test('Now Playing shape', () {
      expect(jsonEncode(nowPlayingShape().toWledPayload()), '{"on":true,"bri":150,"seg":[{"grp":2,"spc":3,"id":0,"col":[[255,0,34,0]],"pal":5,"fx":28,"sx":44,"ix":90},'
          '{"grp":2,"spc":3,"id":1,"col":[[255,0,34,0]],"pal":5,"fx":28,"sx":44,"ix":90}]}');
    });

    test('Pattern Editor, animated', () {
      expect(jsonEncode(editorAnimatedShape().toWledPayload()), '{"on":true,"bri":200,"seg":[{"grp":1,"spc":0,"id":0,"col":[[0,0,255,0],[0,0,0,0]],"pal":5,"fx":28,"sx":44,"ix":90},'
          '{"grp":1,"spc":0,"id":1,"col":[[0,0,255,0],[0,0,0,0]],"pal":5,"fx":28,"sx":44,"ix":90}]}');
    });

    test('Pattern Editor, Static three colours (Alternating)', () {
      expect(jsonEncode(editorStaticShape().toWledPayload()), '{"on":true,"bri":180,"seg":[{"grp":2,"spc":0,"id":0,"col":[[255,0,0,0],[0,255,0,0],[0,0,255,0]],'
          '"pal":5,"fx":84,"sx":0,"ix":0}]}');
    });

    test('painted', () {
      expect(jsonEncode(paintedShape().toWledPayload()), '{"on":true,"seg":[{"grp":1,"spc":0,"id":0,"on":true,"fx":0,"i":[0,3,[255,0,0,0],3,6,[0,0,255,0]],'
          '"pal":0,"col":[[0,0,0,0]]}]}');
    });

    test('one-colour Solid', () {
      expect(jsonEncode(solidShape().toWledPayload()), '{"on":true,"bri":160,"seg":[{"grp":1,"spc":0,"id":0,"col":[[255,180,100,0]],"pal":5,"fx":0,"sx":128,"ix":128},'
          '{"grp":1,"spc":0,"id":1,"col":[[255,180,100,0]],"pal":5,"fx":0,"sx":128,"ix":128}]}');
    });
  });

  group('the card page a design opens on builds its palette from ONE channel',
      () {
    // The palette `forDesign` synthesises is what the card page previews,
    // applies and hands to the Pattern Editor. At build 131 it gathered up to
    // three colours ACROSS channels, so a multi-channel design with fewer
    // than three colours repeated them: [c, c] and [a, bg, a] below. Changed
    // DELIBERATELY in build 132 (item 1 of the follow-up): the palette is the
    // first included channel's own colours, up to three.
    test('Now Playing shape: one colour on two channels is [c]', () {
      expect(_argb(ColorwayEffectSelectorPage.forDesign(design: nowPlayingShape())),
          const [0xFFFF0022]);
    });

    test('Pattern Editor, animated: colour plus background is [a, bg]', () {
      expect(
          _argb(ColorwayEffectSelectorPage.forDesign(
              design: editorAnimatedShape())),
          const [0xFF0000FF, 0xFF000000]);
    });

    test('one colour on three channels is still [c]', () {
      final d = nowPlayingShape();
      final three = d.copyWith(channels: [
        ...d.channels,
        d.channels.first.copyWith(channelId: 2, channelName: 'Porch'),
      ]);
      expect(_argb(ColorwayEffectSelectorPage.forDesign(design: three)),
          const [0xFFFF0022]);
    });

    test('a left-out first channel is skipped; more than three colours stop '
        'at three', () {
      final d = editorAnimatedShape();
      final withFour = d.copyWith(channels: [
        d.channels.first.copyWith(included: false),
        d.channels[1].copyWith(colorGroups: const [
          LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0, 0]),
          LedColorGroup(startLed: 1, endLed: 1, color: [0, 255, 0, 0]),
          LedColorGroup(startLed: 2, endLed: 2, color: [0, 0, 255, 0]),
          LedColorGroup(startLed: 3, endLed: 3, color: [255, 255, 0, 0]),
        ]),
      ]);
      expect(_argb(ColorwayEffectSelectorPage.forDesign(design: withFour)),
          const [0xFFFF0000, 0xFF00FF00, 0xFF0000FF]);
    });
  });

  test('a catalog card sends exactly what it sent at build 131', () {
    expect(
        jsonEncode(buildSelectorPayload(const SelectorState(
          effectId: 28,
          speed: 44,
          intensity: 90,
          grouping: 1,
          spacing: 0,
          colors: [
            [255, 0, 0, 0],
            [0, 0, 255, 0],
          ],
        ))),
        '{"on":true,"seg":[{"fx":28,"sx":44,"ix":90,"pal":5,"grp":1,"spc":0,"col":[[255,0,0,0],[0,0,255,0]]}]}');
  });
}
