// Phase C gate (audit/DESIGN_CARD_P4.md).
//   C1 — the colourway tuner's design-edit mode: payload round-trip through
//        the seven selector providers, snapshot/restore on cancel, and a
//        save that updates in place.
//   C2 — the Sync picker excludes saved designs (its wire format cannot
//        carry one).
//   C3 — composedPattern survives every edit writer, since nothing reads it
//        back and it cannot be re-derived.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_control_panel.dart';
import 'package:nexgen_command/features/wled/design_spacing_defaults.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

/// An effect-kind design: exactly one colour group per channel.
CustomDesign effectDesign({
  String id = 'fx1',
  int effectId = 12,
  int speed = 90,
  int intensity = 200,
  int brightness = 180,
  Map<String, dynamic>? composedPattern,
}) {
  return CustomDesign(
    id: id,
    name: 'Sunset Fade',
    description: 'kept',
    createdAt: DateTime(2026, 5, 29),
    updatedAt: DateTime(2026, 6, 1),
    ownerId: 'u',
    brightness: brightness,
    tags: const ['kept'],
    channels: [
      ChannelDesign(
        channelId: 0,
        channelName: 'Front',
        included: true,
        effectId: effectId,
        speed: speed,
        intensity: intensity,
        colorGroups: [
          LedColorGroup(startLed: 0, endLed: 9, color: const [255, 80, 0, 0]),
        ],
        ledCount: 10,
      ),
      // Excluded channels must be carried through a save untouched.
      const ChannelDesign(
          channelId: 1, channelName: 'Back', included: false, ledCount: 10),
    ],
    composedPattern: composedPattern,
  );
}

void main() {
  group('C1 — payload round-trip through the selector state', () {
    test('payload → state → payload is an equal payload', () {
      final original = buildSelectorPayload(const SelectorState(
        effectId: 28,
        speed: 77,
        intensity: 201,
        grouping: 3,
        spacing: 2,
        brightness: 180,
        colors: [
          [255, 80, 0, 0],
          [0, 0, 255, 0],
        ],
      ));

      final state = selectorStateFromPayload(original);
      final rebuilt = buildSelectorPayload(state);

      expect(rebuilt, equals(original));
    });

    test('every field survives the trip, not just the map shape', () {
      const before = SelectorState(
        effectId: 28,
        speed: 77,
        intensity: 201,
        grouping: 3,
        spacing: 2,
        brightness: 180,
        colors: [
          [255, 80, 0, 0]
        ],
      );
      final after = selectorStateFromPayload(buildSelectorPayload(before));
      expect(after, equals(before));
    });

    test('pal is derived from the effect, never hardcoded', () {
      for (final fx in [0, 28, 63, 83]) {
        final payload = buildSelectorPayload(SelectorState(
          effectId: fx,
          speed: 128,
          intensity: 128,
          colors: const [
            [255, 255, 255, 0]
          ],
        ));
        final seg = (payload['seg'] as List).first as Map;
        expect(seg['pal'], WledEffectsCatalog.paletteForEffect(fx),
            reason: 'fx $fx must carry its own palette behaviour');
      }
    });

    test('a legacy seg with no grp/spc seeds the #88 design defaults, '
        'not whatever the controller shows', () {
      final state = selectorStateFromPayload({
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 5, 'sx': 120, 'ix': 90, 'col': <List<int>>[]}
        ],
      });
      expect(state.grouping, kDesignDefaultGrp);
      expect(state.spacing, kDesignDefaultSpc);
    });

    test('the #67 exclusion seg is skipped, not read as the design', () {
      // applyChannelFilter emits {id: 0, on: false} first when a design is
      // scoped away from channel 0; it carries no fx.
      final state = selectorStateFromPayload({
        'on': true,
        'bri': 255,
        'seg': [
          {'id': 0, 'on': false},
          {'id': 1, 'fx': 44, 'sx': 60, 'ix': 30},
        ],
      });
      expect(state.effectId, 44);
      expect(state.speed, 60);
    });

    test('empty colours fall back to white rather than emitting an empty col',
        () {
      final payload = buildSelectorPayload(const SelectorState(
          effectId: 0, speed: 128, intensity: 128, colors: []));
      final seg = (payload['seg'] as List).first as Map;
      expect(seg['col'], [
        [255, 255, 255, 0]
      ]);
    });
  });

  group('C1 — save-to-design updates in place', () {
    // The tuner's fourth exit builds this design and hands it to
    // updateDesignProvider, which refuses an empty id. What matters is that
    // the id is carried and the untouched fields are carried with it.
    test('the saved design keeps its id and its unrelated fields', () {
      final original = effectDesign(composedPattern: {'source_intent': 1});

      // Mirrors _saveToDesign's copyWith.
      final saved = original.copyWith(
        channels: [
          for (final ch in original.channels)
            ch.included
                ? ch.copyWith(effectId: 44, speed: 60, intensity: 30)
                : ch,
        ],
        updatedAt: DateTime(2026, 7, 1),
      );

      expect(saved.id, 'fx1');
      expect(saved.id, isNotEmpty,
          reason: 'non-empty id → updateDesign, never createDesign');
      expect(saved.name, original.name, reason: 'the tuner does not rename');
      expect(saved.description, original.description);
      expect(saved.tags, original.tags);
      expect(saved.brightness, original.brightness);

      final front = saved.channels.firstWhere((c) => c.channelId == 0);
      expect(front.effectId, 44);
      expect(front.speed, 60);
      expect(front.intensity, 30);
      // Colours are NOT written — the tuner has no colour editor.
      expect(front.colorGroups.single.color, const [255, 80, 0, 0]);

      // Excluded channels pass through untouched.
      final back = saved.channels.firstWhere((c) => c.channelId == 1);
      expect(back.included, isFalse);
      expect(back.effectId, original.channels[1].effectId);
    });

    test('seeding reads the CHANNEL, not toWledPayload, so a stored fx 0 '
        'is not rewritten to 83', () {
      // toWledPayload substitutes fx 83 for a multi-colour Solid
      // (design_models.dart). Seeding through it would show 83 in the picker
      // and then persist 83 over the stored 0.
      final multiColour = CustomDesign(
        id: 'm',
        name: 'Two Tone',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        ownerId: 'u',
        channels: [
          ChannelDesign(
            channelId: 0,
            channelName: 'A',
            included: true,
            effectId: 0,
            colorGroups: [
              LedColorGroup(startLed: 0, endLed: 4, color: const [255, 0, 0, 0]),
              LedColorGroup(startLed: 5, endLed: 9, color: const [0, 255, 0, 0]),
            ],
            ledCount: 10,
          ),
        ],
      );

      final viaPayload =
          selectorStateFromPayload(multiColour.toWledPayload()).effectId;
      final viaChannel = multiColour.channels.first.effectId;

      expect(viaPayload, 83, reason: 'the substitution is real');
      expect(viaChannel, 0, reason: 'the stored truth is 0');
      expect(viaChannel, isNot(viaPayload),
          reason: 'which is exactly why _seedFromDesign reads the channel');
    });
  });

  group('C2 — the Sync picker cannot carry a saved design', () {
    // The decisive evidence for the exclusion: the wire format has no field
    // for a payload, so nothing about the design could survive the trip.
    test('the REAL wire format has no payload field', () {
      // This is the evidence the exclusion rests on, so it asserts the actual
      // serialiser rather than a restatement of it. If a payload field is ever
      // added to the wire format, this fails and the exclusion should be
      // revisited.
      final assignment = SyncPatternAssignment.fromLibraryNode(
        name: 'Sunset Fade',
        themeColors: const [Color(0xFFFF5000)],
        effectId: 12,
      );
      final json = assignment.toJson();

      expect(json.keys.toSet(), {
        'name',
        'effectId',
        'colors',
        'speed',
        'intensity',
        'brightness',
        'pal',
        'grp',
        'spc',
      });
      expect(json.containsKey('wledPayload'), isFalse);
      expect(json.containsKey('payload'), isFalse);
    });

    test('fromLibraryNode reconstructs from themeColors — it never consults '
        'a payload, so a design arrives as swatches', () {
      final assignment = SyncPatternAssignment.fromLibraryNode(
        name: 'Sunset Fade',
        themeColors: const [Color(0xFFFF5000), Color(0xFF0000FF)],
        effectId: 12,
      );
      // Only the preview swatches survive; nothing design-specific does.
      expect(assignment.colors, hasLength(2));
      expect(assignment.wledPayload, isNull);
    });

    test('the picker filter drops my_designs and every design_* child', () {
      // The REAL filter the picker calls, not a copy of it.
      const nodes = [
        LibraryNode(
            id: 'cat_holiday',
            name: 'Holidays',
            nodeType: LibraryNodeType.category),
        LibraryNode(
            id: kMyDesignsCategoryId,
            name: 'My Designs',
            nodeType: LibraryNodeType.category),
      ];
      final roots = syncableLibraryNodes(nodes);
      expect(roots.map((n) => n.id), ['cat_holiday']);

      const children = [
        LibraryNode(
            id: 'design_abc',
            name: 'Sunset Fade',
            nodeType: LibraryNodeType.palette,
            metadata: {'isSavedDesign': true, 'sourceDesignId': 'abc'}),
        LibraryNode(
            id: 'holiday_xmas_classic',
            name: 'Classic',
            nodeType: LibraryNodeType.palette),
      ];
      expect(syncableLibraryNodes(children).map((n) => n.id),
          ['holiday_xmas_classic']);
    });

    test('a per-pixel design is excluded too — the filter is by node id, '
        'so design KIND never has to be inspected', () {
      const perPixelNode = LibraryNode(
          id: 'design_perpixel1',
          name: 'Painted',
          nodeType: LibraryNodeType.palette,
          metadata: {'isSavedDesign': true, 'sourceDesignId': 'perpixel1'});
      expect(syncableLibraryNodes(const [perPixelNode]), isEmpty);
    });
  });

  group('C3 — composedPattern survives every edit writer', () {
    test('the tuner save preserves it', () {
      const intent = {
        'source_intent': {'zones': 2},
        'wled_payload': {
          'seg': [
            {
              'col': [
                [255, 0, 0, 0]
              ]
            }
          ]
        },
      };
      final original = effectDesign(composedPattern: intent);
      final saved = original.copyWith(
        channels: [
          for (final ch in original.channels)
            ch.included ? ch.copyWith(effectId: 44) : ch,
        ],
        updatedAt: DateTime(2026, 7, 1),
      );

      expect(saved.composedPattern, isNotNull);
      expect(saved.composedPattern, equals(intent));
      // And through the write the update actually performs.
      final wire = saved.toFirestore();
      expect(wire.containsKey('composed_pattern'), isTrue);
    });

    test('the manual-editor edit-save preserves it', () {
      final original = effectDesign(composedPattern: {'a': 1});
      // Mirrors ManualDesignEditor._save's edit branch.
      final saved = original.copyWith(
        name: original.name,
        channels: const [
          ChannelDesign(channelId: 0, channelName: 'Channel 1', ledCount: 10),
        ],
        updatedAt: DateTime(2026, 7, 1),
      );
      expect(saved.composedPattern, equals({'a': 1}));
    });

    test('a FRESH CustomDesign would destroy it — the failure mode the doc '
        'comment warns about', () {
      final original = effectDesign(composedPattern: {'a': 1});
      final fresh = CustomDesign(
        id: original.id,
        name: original.name,
        createdAt: original.createdAt,
        updatedAt: DateTime(2026, 7, 1),
        ownerId: original.ownerId,
        channels: original.channels,
      );
      expect(fresh.composedPattern, isNull);
      expect(fresh.toFirestore().containsKey('composed_pattern'), isFalse,
          reason: 'the key is omitted, so .update() would LEAVE the stored '
              'value — the doc survives this particular mistake, but any '
              'writer using .set() would erase it');
    });
  });
}
