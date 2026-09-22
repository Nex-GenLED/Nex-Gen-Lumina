// A saved design keeps its Blocks | Alternating layout.
//
// `ChannelDesign` had no field for it: the tuner dropped the chip on save and
// `CustomDesign.toWledPayload` substituted fx 83 + pal 5 (Blocks) for every
// multi-colour Solid, so a design saved as Alternating fired as Blocks from
// My Designs, schedules, scenes and Game Day
// (audit/DESIGN_CARD_BLOCKS_LAYOUT_AUDIT_2026-09-22.md, Finding 2).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

final _now = DateTime(2026, 9, 22);

const _red = [255, 0, 0, 0];
const _white = [255, 255, 255, 0];
const _blue = [0, 0, 255, 0];

/// A palette-shaped Solid channel — one single-LED group per colour, no
/// led_count — exactly what the tuner's node and the colour editor's "save as
/// pattern" produce. (Groups that TILE a channel are a painted picture and go
/// per-pixel; see positional_design_apply_test.dart.)
ChannelDesign _solid(List<List<int>> colors,
        {SolidLayout layout = SolidLayout.blocks, int grouping = 1, int id = 0}) =>
    ChannelDesign(
      channelId: id,
      channelName: 'Ch$id',
      effectId: 0,
      speed: 77,
      intensity: 99,
      grouping: grouping,
      solidLayout: layout,
      colorGroups: [
        for (var i = 0; i < colors.length; i++)
          LedColorGroup(startLed: i, endLed: i, color: colors[i]),
      ],
    );

CustomDesign _design(List<ChannelDesign> channels) => CustomDesign(
      id: 'd', name: 'Layout', ownerId: 'u', createdAt: _now, updatedAt: _now,
      channels: channels,
    );

Map<String, dynamic> _seg(CustomDesign d) =>
    ((d.toWledPayload()['seg'] as List).single as Map).cast<String, dynamic>();

void main() {
  group('the stored field', () {
    test('defaults to Blocks — every existing design is unchanged', () {
      expect(const ChannelDesign(channelId: 0, channelName: 'x').solidLayout,
          SolidLayout.blocks);
    });

    test('survives Firestore and copyWith', () {
      final back = CustomDesign.fromFirestoreData(
          'd', _design([_solid([_red, _blue], layout: SolidLayout.alternating)]).toFirestore());
      expect(back.channels.single.solidLayout, SolidLayout.alternating);
      expect(back.channels.single.copyWith(speed: 1).solidLayout, SolidLayout.alternating);
      expect(back.channels.single.copyWith(solidLayout: SolidLayout.blocks).solidLayout,
          SolidLayout.blocks);
    });

    test('is written snake_case, as every other model field is', () {
      final json = _solid([_red, _blue], layout: SolidLayout.alternating).toJson();
      expect(json['solid_layout'], 'alternating');
      expect(_solid([_red, _blue]).toJson()['solid_layout'], 'blocks');
    });

    test('a design saved BEFORE the field existed reads as Blocks', () {
      final legacy = ChannelDesign.fromJson(const {
        'channel_id': 0, 'channel_name': 'Ch1', 'included': true,
        'color_groups': <dynamic>[], 'effect_id': 0, 'speed': 128, 'intensity': 128,
        'reverse': false, 'led_count': 0, 'grouping': 1, 'spacing': 0,
      });
      expect(legacy.solidLayout, SolidLayout.blocks);
      expect(solidLayoutFromJson(null), SolidLayout.blocks);
      expect(solidLayoutFromJson('garbage'), SolidLayout.blocks);
      expect(solidLayoutFromJson('alternating'), SolidLayout.alternating);
    });
  });

  group('toWledPayload fires the STORED layout', () {
    test('Blocks, three colours: fx 83 + pal 5, sx/ix from the channel — '
        'byte-for-byte what every design fired as before the field existed', () {
      final seg = _seg(_design([_solid([_red, _white, _blue])]));
      expect(seg['fx'], 83);
      expect(seg['pal'], 5);
      expect(seg['sx'], 77);
      expect(seg['ix'], 99);
      expect(seg['grp'], 1);
      expect(seg['spc'], 0);
      expect(seg['col'], [_red, _white, _blue]);
    });

    test('Alternating, three colours: fx 84 with ix:0, width in grp', () {
      final seg = _seg(_design([_solid([_red, _white, _blue],
          layout: SolidLayout.alternating, grouping: 2)]));
      expect(seg['fx'], 84);
      expect(seg['ix'], 0, reason: '1 virtual px per run; grp does the width');
      expect(seg['sx'], 0);
      expect(seg['grp'], 2);
      expect(seg['pal'], 5);
    });

    test('Alternating, two colours: fx 83 with pal:0 and sx=ix=0', () {
      final seg = _seg(_design([_solid([_red, _blue], layout: SolidLayout.alternating)]));
      expect(seg['fx'], 83);
      expect(seg['pal'], 0, reason: 'pal 5 would map the two colours positionally');
      expect(seg['sx'], 0);
      expect(seg['ix'], 0);
    });

    test('the layout is per channel', () {
      final d = _design([
        _solid([_red, _white, _blue], id: 0),
        _solid([_red, _white, _blue], id: 1, layout: SolidLayout.alternating),
      ]);
      final segs = (d.toWledPayload()['seg'] as List).cast<Map>();
      expect(segs.map((s) => s['fx']), [83, 84]);
    });

    test('one colour is plain Solid whatever the layout says', () {
      final seg = _seg(_design([_solid([_red], layout: SolidLayout.alternating)]));
      expect(seg['fx'], 0);
      expect(seg['pal'], 5);
      expect(seg['sx'], 77, reason: 'nothing pinned');
    });

    test('a non-Solid effect ignores the layout', () {
      final seg = _seg(_design([
        _solid([_red, _blue], layout: SolidLayout.alternating).copyWith(effectId: 17),
      ]));
      expect(seg['fx'], 17);
      expect(seg['pal'], 5);
      expect(seg['sx'], 77);
    });

    test('a positional (painted) design never consults it', () {
      final painted = _design([
        ChannelDesign(
          channelId: 0, channelName: 'A', effectId: 0, ledCount: 10,
          solidLayout: SolidLayout.alternating,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 4, color: _red),
            LedColorGroup(startLed: 5, endLed: 9, color: _blue),
          ],
        ),
      ]);
      expect(painted.isPositional, isTrue);
      final seg = (painted.toWledPayload()['seg'] as List).single as Map;
      expect(seg['fx'], 0);
      expect(seg.containsKey('i'), isTrue);
    });
  });

  group('the apply chokepoint leaves both layouts alone', () {
    // normalizeWledPayload rewrites pal 5 → 4 for palette-SWEEP effects only;
    // fx 83 / 84 read the user's colours, so the layout must reach the wire.
    test('fx 84 + pal 5 survives', () {
      final p = normalizeWledPayload(_design([
        _solid([_red, _white, _blue], layout: SolidLayout.alternating),
      ]).toWledPayload());
      final seg = (p['seg'] as List).single as Map;
      expect([seg['fx'], seg['pal'], seg['ix']], [84, 5, 0]);
    });

    test('fx 83 + pal 0 survives', () {
      final p = normalizeWledPayload(_design([
        _solid([_red, _blue], layout: SolidLayout.alternating),
      ]).toWledPayload());
      final seg = (p['seg'] as List).single as Map;
      expect([seg['fx'], seg['pal']], [83, 0]);
    });

    test('fx 83 + pal 5 survives', () {
      final p = normalizeWledPayload(_design([_solid([_red, _white, _blue])]).toWledPayload());
      final seg = (p['seg'] as List).single as Map;
      expect([seg['fx'], seg['pal']], [83, 5]);
    });
  });
}
