// Per-light brightness (`LedColorGroup.bri`, build 129) must reach the lights
// on every LIVE apply, not only on a schedule.
//
// Every live apply paints through `ledColorGroupsToSpans`: the editor's
// Apply and Live Preview, My Designs, the AI studio, Home favourites, scenes
// and the edit-pattern screen. In builds 129 and 130 it sent each group's
// PURE colour. A light dimmed to 5 % went out at full, and the per-pixel
// merge then joined it to its neighbour (bench, build 130: pixel 0 at 100 %
// and pixel 1 at 5 % went out as `"i":[0,2,[...]]`). Schedules were right all
// along: `ChannelDesign.positionalSpans` has always applied `bri`.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/wled/brightness_tile.dart';
import 'package:nexgen_command/features/wled/brightness_tile_apply.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/per_pixel_wire.dart';

const _base = [10, 10, 12, 0]; // the paint editor's base
const _cyan = [0, 229, 255, 0]; // the paint editor's default paint
const _warm = [255, 147, 41, 200];
const _red = [255, 0, 0, 0];
const _white = [255, 255, 255, 0];
const _lengths = {0: 60, 1: 40};
final _now = DateTime(2026, 11, 17);

/// The level the editor's "Dim to N %" stores.
int _pct(int p) => (p / 100 * kLedGroupFullBrightness).round();

/// A painted document using every brightness tool the editor has: a single
/// light at 5 %, a dimmed BASE pixel, Dim to 0 %, and two Ramps (one
/// mirrored).
PixelDesignDocument _dimmedDoc() {
  var doc = PixelDesignDocument.blank(baseColor: _base, channelLengths: _lengths)
      .paint(0, [for (var i = 0; i < 10; i++) i], _cyan)
      .paint(0, [for (var i = 10; i < 30; i++) i], _warm)
      .paint(1, [for (var i = 0; i < 40; i++) i], _red)
      .setBrightness(0, [1], _pct(5))
      .setBrightness(0, [30, 31], _pct(40))
      .setBrightness(1, [39], 0);
  final warmRamp = brightnessRamp([for (var i = 10; i < 30; i++) i],
      startPct: 100, endPct: 20, mirror: true);
  for (final r in warmRamp.entries) {
    doc = doc.setBrightness(0, [r.key], r.value);
  }
  final redRamp =
      brightnessRamp([for (var i = 0; i < 39; i++) i], startPct: 100, endPct: 5);
  for (final r in redRamp.entries) {
    doc = doc.setBrightness(1, [r.key], r.value);
  }
  return doc;
}

/// A design saved the way the paint editor's `_save()` builds it.
CustomDesign _design(PixelDesignDocument doc) => CustomDesign(
      id: 'd1',
      name: 'Dimmed',
      ownerId: 'u',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      channels: [
        for (final e in doc.toLedColorGroups().entries)
          ChannelDesign(
            channelId: e.key,
            channelName: 'Channel ${e.key + 1}',
            colorGroups: e.value,
            ledCount: doc.channelLength(e.key),
          ),
      ],
    );

/// [d] written to Firestore and read back: the channels come back as plain
/// JSON lists and maps.
CustomDesign _throughFirestore(CustomDesign d) {
  final data = d.toFirestore();
  data['channels'] = jsonDecode(jsonEncode(data['channels']));
  return CustomDesign.fromFirestoreData('saved-1', data);
}

class _Idle extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

/// A provider reader over two channels whose controller is [rec].
Future<ProviderReader> _pumpReader(
    WidgetTester tester, PerPixelWireRecorder rec) async {
  SharedPreferences.setMockInitialValues({});
  late WidgetRef ref;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      wledRepositoryProvider.overrideWith((ref) => rec),
      deviceChannelsProvider.overrideWithValue(const [
        DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 60, gpioPin: 2),
        DeviceChannel(id: 1, name: 'Ch2', start: 60, stop: 100, gpioPin: 4),
      ]),
      effectiveChannelIdsProvider.overrideWithValue(const [0, 1]),
      wledStateProvider.overrideWith(() => _Idle()),
    ],
    child: Consumer(builder: (c, r, _) {
      ref = r;
      return const SizedBox();
    }),
  ));
  return ref.read;
}

void main() {
  group('ledColorGroupsToSpans, the converter behind every live apply', () {
    const groups = [
      LedColorGroup(startLed: 0, endLed: 0, color: _cyan),
      LedColorGroup(startLed: 1, endLed: 1, color: _cyan, bri: 13),
      LedColorGroup(startLed: 2, endLed: 4, color: _warm, bri: 102),
      LedColorGroup(startLed: 5, endLed: 5, color: [255, 0, 0], bri: 102),
      LedColorGroup(startLed: 6, endLed: 6, color: _white, bri: 0),
    ];

    test('a group below full goes out at its lit colour, not its pure colour', () {
      final dimmed = ledColorGroupsToSpans(groups);
      final atFull = ledColorGroupsToSpans(
          [for (final g in groups) g.copyWith(bri: kLedGroupFullBrightness)]);
      expect(dimmed.first.color, atFull.first.color,
          reason: 'a group at full is unchanged');
      for (var k = 1; k < groups.length; k++) {
        expect(dimmed[k].color, isNot(atFull[k].color),
            reason: 'group $k at bri ${groups[k].bri}');
        expect(dimmed[k].color, groups[k].litColor, reason: 'group $k');
      }
      expect(dimmed[1].color, [0, 79, 88, 0], reason: 'cyan at 5 % of its light');
      expect(dimmed[3].color, [184, 0, 0, 0], reason: 'RGB-only at 40 %, W stays 0');
      expect(dimmed[4].color, [0, 0, 0, 0], reason: 'Dim to 0 % is off');
    });

    test('the per-pixel merge no longer joins a 100 % light to its 5 % neighbour', () {
      final spans =
          normalizeAndMergePixelSpans(ledColorGroupsToSpans(groups.sublist(0, 2)));
      final seg = (buildPerPixelPayload(spans, 0)['seg'] as List).first as Map;
      expect(seg['i'], [
        0, [0, 229, 255, 0],
        1, [0, 79, 88, 0],
      ], reason: 'build 130 sent [0, 2, [0, 229, 255, 0]]: both lights at full');
    });

    test('customDesignToSpans (My Designs, favourites, scenes, AI studio, '
        'edit-pattern) carries every level', () {
      final design = _design(_dimmedDoc());
      final spans = customDesignToSpans(design);
      for (final ch in design.channels) {
        final sent = spanPixelBytes(spans[ch.channelId]!, ch.ledCount);
        for (final g in ch.colorGroups) {
          for (var p = g.startLed; p <= g.endLed; p++) {
            expect(sent[p], g.litColor, reason: 'channel ${ch.channelId} pixel $p');
          }
        }
      }
    });
  });

  group('parity: the schedule shape and the live apply send the same bytes', () {
    testWidgets('positionalSpans, toWledPayload and the apply spine agree pixel '
        'for pixel', (tester) async {
      final design = _design(_dimmedDoc());
      final rec = PerPixelWireRecorder();
      final read = await _pumpReader(tester, rec);
      expect(await applyPositionalDesignWith(read, design), DesignApplyResult.applied);

      final applied = sentPixelBytes(rec.pixelBodies, _lengths);
      final payload = sentPixelBytes([design.toWledPayload()], _lengths);
      for (final ch in design.channels) {
        final positional = spanPixelBytes(ch.positionalSpans(), ch.ledCount);
        expect(applied[ch.channelId], positional,
            reason: 'channel ${ch.channelId}: live apply vs positionalSpans');
        expect(payload[ch.channelId], positional,
            reason: 'channel ${ch.channelId}: toWledPayload vs positionalSpans');
      }
      // A dimmed design: the bytes are the lit colours, not the paint.
      expect(applied[0]![1], [0, 79, 88, 0]);
      expect(applied[0]![30], litRgbwForBrightness(_base, _pct(40)));
      expect(applied[1]![39], [0, 0, 0, 0]);
    });
  });

  group('round trip: save, reopen, apply', () {
    testWidgets('a dimmed design read back from Firestore applies at the levels '
        'it was painted at', (tester) async {
      final doc = _dimmedDoc();
      final reopened = _throughFirestore(_design(doc));
      expect(reopened.channels.first.colorGroups.any((g) => g.isDimmed), isTrue,
          reason: 'the level is stored as bri, apart from the colour');

      final rec = PerPixelWireRecorder();
      final read = await _pumpReader(tester, rec);
      expect(await applyPositionalDesignWith(read, reopened), DesignApplyResult.applied);

      final applied = sentPixelBytes(rec.pixelBodies, _lengths);
      for (final ch in _lengths.keys) {
        for (var p = 0; p < _lengths[ch]!; p++) {
          expect(applied[ch]![p], doc.litColorAt(ch, p),
              reason: 'channel $ch pixel $p: what the editor showed');
        }
      }
    });
  });

  group('non-regression: nothing at full brightness changes', () {
    // What the converter sent before it read the level: the pure colour, RGB
    // padded with W = 0. Every group at full must still give exactly this.
    List<int> pureRgbw(List<int> c) => c.length >= 4
        ? c.sublist(0, 4)
        : (c.length == 3 ? [...c, 0] : const [0, 0, 0, 0]);
    String bytes(List<PixelSpan> spans) =>
        jsonEncode(buildPerPixelPayload(normalizeAndMergePixelSpans(spans), 0));
    String pureBytes(List<LedColorGroup> groups) => bytes([
          for (final g in groups)
            PixelSpan(start: g.startLed, end: g.endLed, color: pureRgbw(g.color)),
        ]);

    test('a design with no bri sends the same bytes', () {
      final undimmed =
          PixelDesignDocument.blank(baseColor: _base, channelLengths: _lengths)
              .paint(0, [10], _red)
              .paint(0, [20, 21, 22], _warm)
              .paint(1, [0, 1, 2, 3], const [255, 40, 150, 0]);
      // Stored before build 129: no bri key, RGB and RGBW colours.
      final legacy = [
        LedColorGroup.fromJson(const {'start_led': 0, 'end_led': 9, 'color': [255, 0, 0]}),
        LedColorGroup.fromJson(const {'start_led': 10, 'end_led': 19, 'color': [0, 0, 0, 255]}),
        LedColorGroup.fromJson(const {'start_led': 20, 'end_led': 29, 'color': [12, 34, 56, 78]}),
      ];
      final cases = [
        ...undimmed.toLedColorGroups().values,
        ...undimmed.toLedColorGroups(onlyPainted: true).values,
        legacy,
      ];
      for (final groups in cases) {
        expect(groups.any((g) => g.isDimmed), isFalse);
        expect(bytes(ledColorGroupsToSpans(groups)), pureBytes(groups));
      }
    });

    test('every saved Brightness Patterns tile, Wave included, sends the same '
        'bytes, and they are the frame the tile paints live', () {
      for (final preset in kBrightnessPatternPresets) {
        for (final base in const [_white, _warm, _cyan]) {
          final channels =
              brightnessTileChannels(preset.tile, base, const {0: 100, 1: 162});
          for (final ch in channels) {
            final what = '${preset.id} on $base, channel ${ch.channelId}';
            // Saved pre-dimmed, with no level of its own: nothing to double.
            expect(ch.colorGroups.any((g) => g.isDimmed), isFalse, reason: what);
            expect(ch.colorGroups.any((g) => g.toJson().containsKey('bri')), isFalse,
                reason: what);
            final converted = ledColorGroupsToSpans(ch.colorGroups);
            expect(bytes(converted), pureBytes(ch.colorGroups), reason: what);
            expect(bytes(converted),
                bytes(brightnessTileSpans(preset.tile, base, ch.ledCount)),
                reason: what);
          }
        }
      }
    });

    testWidgets('a Wave tile sent live, and the same tile saved and re-applied '
        'from My Designs, send the same pixels', (tester) async {
      final wave = brightnessPatternPresetById('wave6')!.tile;
      final rec = PerPixelWireRecorder();
      final read = await _pumpReader(tester, rec);
      expect(await applyBrightnessTileWith(read, tile: wave, baseRgbw: _white),
          SpineWriteResult.ok);
      final live = sentPixelBytes(rec.pixelBodies, _lengths);

      rec.bodies.clear();
      final saved = _throughFirestore(brightnessTileDesign(read,
          name: 'Wave', ownerId: 'u', tile: wave, baseRgbw: _white));
      expect(await applyPositionalDesignWith(read, saved), DesignApplyResult.applied);
      expect(sentPixelBytes(rec.pixelBodies, _lengths), live);
      expect(live[0]!.take(6).toList(), [
        for (final level in const [100, 80, 60, 40, 60, 80]) rgbwAtLevel(_white, level),
      ]);
    });
  });
}
