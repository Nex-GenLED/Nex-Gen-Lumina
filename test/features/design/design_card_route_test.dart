// Build 132, fix 2 — the "same look" rule behind which screen a saved design
// opens on (lib/features/design/design_card_route.dart). The routing itself is
// driven through the real screen in
// test/features/wled/saved_design_card_route_132_test.dart; this pins the
// edges of the comparison.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_card_route.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';

ChannelDesign _ch(
  int id, {
  List<LedColorGroup> groups = const [
    LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 34, 0]),
  ],
  int fx = 28,
  int ledCount = 100,
  String? name,
  bool included = true,
  SolidLayout layout = SolidLayout.blocks,
}) =>
    ChannelDesign(
      channelId: id,
      channelName: name ?? 'Channel ${id + 1}',
      included: included,
      colorGroups: groups,
      effectId: fx,
      ledCount: ledCount,
      solidLayout: layout,
    );

CustomDesign _d(List<ChannelDesign> channels, {List<String> tags = const []}) =>
    CustomDesign(
      id: 'd',
      name: 'D',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      ownerId: 'u',
      channels: channels,
      tags: tags,
    );

void main() {
  group('channelsShareOneLook', () {
    test('channel names and LED counts are not part of the look', () {
      expect(
          channelsShareOneLook(_d([
            _ch(0, name: 'Front', ledCount: 128),
            _ch(1, name: 'Garage', ledCount: 162),
          ])),
          isTrue);
    });

    test('where a colour group sits is not part of the look', () {
      expect(
          channelsShareOneLook(_d([
            _ch(0, groups: const [
              LedColorGroup(startLed: 0, endLed: 127, color: [255, 0, 34, 0]),
            ]),
            _ch(1, groups: const [
              LedColorGroup(startLed: 0, endLed: 161, color: [255, 0, 34, 0]),
            ]),
          ])),
          isTrue);
    });

    test('a different white value is a different colour', () {
      expect(
          channelsShareOneLook(_d([
            _ch(0, groups: const [
              LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 34, 0]),
            ]),
            _ch(1, groups: const [
              LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 34, 10]),
            ]),
          ])),
          isFalse);
    });

    test('a group dimmed on one channel only is a different look', () {
      expect(
          channelsShareOneLook(_d([
            _ch(0),
            _ch(1, groups: const [
              LedColorGroup(
                  startLed: 0, endLed: 0, color: [255, 0, 34, 0], bri: 100),
            ]),
          ])),
          isFalse);
    });

    test('the same colours in another order are a different look', () {
      const a = LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0, 0]);
      const b = LedColorGroup(startLed: 1, endLed: 1, color: [0, 0, 255, 0]);
      expect(
          channelsShareOneLook(_d([
            _ch(0, groups: const [a, b]),
            _ch(1, groups: const [b, a]),
          ])),
          isFalse);
    });

    test('the Solid layout counts only for Solid', () {
      expect(
          channelsShareOneLook(_d([
            _ch(0, fx: 0, layout: SolidLayout.blocks),
            _ch(1, fx: 0, layout: SolidLayout.alternating),
          ])),
          isFalse);
      expect(
          channelsShareOneLook(_d([
            _ch(0, layout: SolidLayout.blocks),
            _ch(1, layout: SolidLayout.alternating),
          ])),
          isTrue);
    });

    test('a left-out channel is not compared; none left in is no look', () {
      expect(
          channelsShareOneLook(_d([_ch(0), _ch(1, fx: 9, included: false)])),
          isTrue);
      expect(channelsShareOneLook(_d([_ch(0, included: false)])), isFalse);
      expect(channelsShareOneLook(_d(const [])), isFalse);
    });
  });

  group('designOpensOnCardPage', () {
    test('an effect design with one look', () {
      expect(designOpensOnCardPage(_d([_ch(0), _ch(1)])), isTrue);
    });

    test('a Solid colour does not; a Pattern Editor Static design does', () {
      expect(designOpensOnCardPage(_d([_ch(0, fx: 0)])), isFalse);
      expect(
          designOpensOnCardPage(
              _d([_ch(0, fx: 0)], tags: const [kPatternEditorDesignTag])),
          isTrue);
    });

    test('channels that differ do not, Pattern Editor or not', () {
      expect(designOpensOnCardPage(_d([_ch(0), _ch(1, fx: 9)])), isFalse);
      expect(
          designOpensOnCardPage(_d([_ch(0), _ch(1, fx: 9)],
              tags: const [kPatternEditorDesignTag])),
          isFalse);
    });

    test('painted and AI designs do not', () {
      expect(
          designOpensOnCardPage(
              _d([_ch(0)]).copyWith(perPixel: true)),
          isFalse);
      expect(
          designOpensOnCardPage(_d([_ch(0)])
              .copyWith(composedPattern: const {'effect_id': 28})),
          isFalse);
    });

    test('the effect is read from the first INCLUDED channel', () {
      expect(
          designOpensOnCardPage(
              _d([_ch(0, fx: 0, included: false), _ch(1)])),
          isTrue);
    });
  });
}
