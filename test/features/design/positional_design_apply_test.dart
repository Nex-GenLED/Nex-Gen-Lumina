// M1 (audit F3) — a saved per-pixel design applies the way it looked when it
// was saved, from EVERY door: My Designs, scenes, the payload consumers.
// Item 13 — DesignKind follows the stored marker, not a guess from shape.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/screens/design_detail_screen.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = [10, 10, 12, 0];
const _lengths = {0: 128, 1: 162};
final _now = DateTime(2026, 9, 19);

/// A design saved by the paint editor — built the way `_save()` builds it.
CustomDesign _painted(PixelDesignDocument doc, {bool marker = true}) => CustomDesign(
      id: 'p1', name: 'My pattern', ownerId: 'u', createdAt: _now, updatedAt: _now,
      perPixel: marker,
      channels: [
        for (final e in doc.toLedColorGroups().entries)
          ChannelDesign(channelId: e.key, channelName: 'Channel ${e.key + 1}',
              colorGroups: e.value, ledCount: doc.channelLength(e.key)),
      ],
    );

PixelDesignDocument _doc() =>
    PixelDesignDocument.blank(baseColor: _base, channelLengths: _lengths)
        .paint(0, [10], const [255, 0, 0, 0])
        .paint(0, [20], const [0, 255, 0, 0])
        .paint(0, [40, 44, 48, 52], const [0, 60, 255, 0])
        .paint(1, [0, 1, 2, 3], const [255, 40, 150, 0]);

/// Expands a payload's per-channel `i` arrays back into LED colours.
Map<int, List<List<int>>> _render(Map<String, dynamic> payload) {
  final out = <int, List<List<int>>>{};
  for (final s in (payload['seg'] as List).cast<Map>()) {
    final id = s['id'] as int;
    final leds = List<List<int>>.generate(_lengths[id]!, (_) => const [-1, -1, -1, -1]);
    final i = s['i'] as List;
    int k = 0;
    while (k < i.length) {
      final start = i[k] as int;
      if (i[k + 1] is int) {
        for (int x = start; x < (i[k + 1] as int); x++) {
          leds[x] = (i[k + 2] as List).cast<int>();
        }
        k += 3;
      } else {
        leds[start] = (i[k + 1] as List).cast<int>();
        k += 2;
      }
    }
    out[id] = leds;
  }
  return out;
}

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

class _Repo implements WledRepository, PerPixelWriter {
  final json = <Map<String, dynamic>>[];
  final pixels = <int, List<PixelSpan>>{};
  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    json.add(payload);
    return true;
  }

  @override
  Future<bool> applyPerPixel({int segmentId = 0, required List<PixelSpan> spans,
      int chunkSize = kDefaultPixelChunkSize}) async {
    pixels[segmentId] = spans;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('isPositional', () {
    test('the paint editor STATES it — even for a one-colour or blank design', () {
      final oneColour = PixelDesignDocument.blank(baseColor: _base, channelLengths: _lengths)
          .paint(0, [for (int i = 0; i < 128; i++) i], const [255, 0, 0, 0])
          .paint(1, [for (int i = 0; i < 162; i++) i], const [255, 0, 0, 0]);
      final blank = PixelDesignDocument.blank(baseColor: _base, channelLengths: _lengths);
      for (final d in [_painted(oneColour), _painted(blank)]) {
        expect(d.channels.every((c) => c.colorGroups.length == 1), isTrue,
            reason: 'single group per channel — indistinguishable by shape');
        expect(d.isPositional, isTrue);
        expect(designKindOf(d), DesignKind.perPixel,
            reason: 'was `effect` → Edit opened the colourway tuner');
      }
    });

    test('the marker survives Firestore', () {
      final back = CustomDesign.fromFirestoreData('p1', _painted(_doc()).toFirestore());
      expect(back.perPixel, isTrue);
      expect(back.copyWith(name: 'Renamed').perPixel, isTrue);
    });

    test('an unmarked legacy painted design is still recognised (it tiles its channel)', () {
      expect(_painted(_doc(), marker: false).isPositional, isTrue);
    });

    test("the colour editor's three-colour save is NOT positional", () {
      final palette = CustomDesign(
        id: 'e', name: 'Tri', ownerId: 'u', createdAt: _now, updatedAt: _now,
        channels: const [
          ChannelDesign(channelId: 0, channelName: 'Main', effectId: 17, colorGroups: [
            LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0, 0]),
            LedColorGroup(startLed: 1, endLed: 1, color: [0, 255, 0, 0]),
            LedColorGroup(startLed: 2, endLed: 2, color: [0, 0, 255, 0]),
          ]),
        ],
      );
      expect(palette.isPositional, isFalse);
      expect(designKindOf(palette), DesignKind.effect,
          reason: 'was `perPixel` → Edit opened the paint editor on 3 stray LEDs');
      final seg = (palette.toWledPayload()['seg'] as List).single as Map;
      expect(seg['fx'], 17);
      expect(seg.containsKey('i'), isFalse);
    });

    test('a captured solid stays an effect design', () {
      final solid = CustomDesign(
        id: 's', name: 'Warm', ownerId: 'u', createdAt: _now, updatedAt: _now,
        channels: const [
          ChannelDesign(channelId: 0, channelName: 'Ch1', ledCount: 128, colorGroups: [
            LedColorGroup(startLed: 0, endLed: 127, color: [255, 160, 0, 0]),
          ]),
        ],
      );
      expect(solid.isPositional, isFalse);
    });
  });

  group('toWledPayload is faithful for a positional design', () {
    test('every LED of every channel comes back exactly as painted', () {
      final doc = _doc();
      final payload = normalizeWledPayload(_painted(doc).toWledPayload());
      final rendered = _render(payload);
      int diffs = 0;
      for (final ch in _lengths.keys) {
        for (int i = 0; i < _lengths[ch]!; i++) {
          if (rendered[ch]![i].toString() != doc.colorAt(ch, i).toString()) diffs++;
        }
      }
      expect(diffs, 0, reason: 'was: 3 colours, no positions, fx 83');
      for (final s in (payload['seg'] as List).cast<Map>()) {
        expect(s['fx'], 0);
        expect(s.containsKey('frz'), isFalse,
            reason: 'a per-pixel write must not be un-frozen by the chokepoint');
      }
      expect(utf8.encode(jsonEncode(payload)).length, lessThan(kMaxApplyPayloadBytes));
    });

    test('an AI-composed design with uncovered LEDs is filled black (self-contained)', () {
      final ai = CustomDesign(
        id: 'a', name: 'AI', ownerId: 'u', createdAt: _now, updatedAt: _now,
        composedPattern: const {'name': 'x'},
        channels: const [
          ChannelDesign(channelId: 0, channelName: 'Ch1', ledCount: 128, colorGroups: [
            LedColorGroup(startLed: 50, endLed: 59, color: [255, 0, 0]),
          ]),
        ],
      );
      final leds = _render(ai.toWledPayload())[0]!;
      expect(leds[49], [0, 0, 0, 0]);
      expect(leds[50], [255, 0, 0, 0], reason: 'RGB-only colour gets W=0');
      expect(leds[60], [0, 0, 0, 0]);
      expect(leds.any((l) => l[0] == -1), isFalse, reason: 'no LED left unwritten');
    });

    test('a scene built from the design carries the same faithful payload', () {
      final scene = Scene.fromDesign(_painted(_doc()));
      final seg = (scene.toWledPayload()['seg'] as List).first as Map;
      expect(seg['fx'], 0);
      expect(seg['i'], isNotEmpty);
    });
  });

  testWidgets('scene apply routes a positional design through the per-pixel spine',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _Repo();
    late WidgetRef ref;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        wledRepositoryProvider.overrideWith((ref) => repo),
        deviceChannelsProvider.overrideWithValue(const [
          DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 128, gpioPin: 2),
          DeviceChannel(id: 1, name: 'Ch2', start: 128, stop: 290, gpioPin: 3),
        ]),
        effectiveChannelIdsProvider.overrideWithValue(const [0, 1]),
        wledStateProvider.overrideWith(() => _FakeWledNotifier()),
      ],
      child: Consumer(builder: (c, r, _) {
        ref = r;
        return const SizedBox();
      }),
    ));

    final design = _painted(_doc());
    final result = await applyPositionalDesignWith(ref.read, design);
    expect(result, DesignApplyResult.applied);
    // Base (one applyJson) + one paint per channel, with the stored runs.
    expect(repo.json.length, 1);
    expect(repo.pixels.keys.toSet(), {0, 1});
    expect(repo.pixels[1]!.first.start, 0);
    expect(repo.pixels[1]!.first.end, 3);
    expect(repo.pixels[1]!.first.color, [255, 40, 150, 0]);

    // And the provider the scene UI calls takes the same road.
    repo.json.clear();
    repo.pixels.clear();
    final ok = await ref.read(applySceneProvider)(Scene.fromDesign(design));
    expect(ok, isTrue);
    expect(repo.pixels.keys.toSet(), {0, 1},
        reason: 'was a single lossy applyJson (fx 83)');
    // applySceneProvider also nudges brightness through the notifier's 150 ms
    // debounce — let it fire before the tree is torn down.
    await tester.pump(const Duration(milliseconds: 300));
  });
}
