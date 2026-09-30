// +110 package E2 — Design Studio audit rows 40, 41, 42 and 118, at the
// shared apply spine.
//
//  40  a design goes to every channel it carries content for, never the
//      Home channel bar's selection, and says nothing about other channels;
//  41  a composed design with motion runs its effect in its colours;
//  42  a failure comes back with its own sentence;
//  118 a positional design is described as static (and a motion design as
//      animated).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 9, 29);

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

class _Repo implements WledRepository, PerPixelWriter {
  _Repo({this.baseOk = true, this.pixelsOk = true});
  bool baseOk;
  bool pixelsOk;
  final json = <Map<String, dynamic>>[];
  final pixels = <int, List<PixelSpan>>{};
  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    json.add(payload);
    return baseOk;
  }

  @override
  Future<bool> applyPerPixel(
      {int segmentId = 0,
      required List<PixelSpan> spans,
      int chunkSize = kDefaultPixelChunkSize}) async {
    pixels[segmentId] = spans;
    return pixelsOk;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _channels = [
  DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Ch2', start: 100, stop: 200, gpioPin: 3),
  DeviceChannel(id: 2, name: 'Ch3', start: 200, stop: 300, gpioPin: 4),
];

ProviderContainer _container(_Repo? repo, {Set<int>? selected}) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    deviceChannelsProvider.overrideWithValue(_channels),
    participatingChannelIdsProvider.overrideWithValue(null),
    selectedChannelIdsProvider.overrideWith((ref) => selected),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// A design painted on channels 0 and 1 only.
CustomDesign _painted() => CustomDesign(
      id: 'd', name: 'Two channels', ownerId: 'u',
      createdAt: _now, updatedAt: _now, perPixel: true,
      channels: const [
        ChannelDesign(channelId: 0, channelName: 'Ch1', ledCount: 100, colorGroups: [
          LedColorGroup(startLed: 0, endLed: 9, color: [255, 0, 0, 0]),
          LedColorGroup(startLed: 10, endLed: 99, color: [0, 0, 0, 0]),
        ]),
        ChannelDesign(channelId: 1, channelName: 'Ch2', ledCount: 100, colorGroups: [
          LedColorGroup(startLed: 0, endLed: 99, color: [0, 0, 255, 0]),
        ]),
      ],
    );

/// An AI-composed design that asked for a chase.
CustomDesign _composedWithMotion() => CustomDesign(
      id: 'c', name: 'Blue chase', ownerId: 'u',
      createdAt: _now, updatedAt: _now,
      channels: const [
        ChannelDesign(channelId: 0, channelName: 'Ch1', ledCount: 100, effectId: 28,
            colorGroups: [
              LedColorGroup(startLed: 0, endLed: 99, color: [0, 0, 255, 0]),
            ]),
        ChannelDesign(channelId: 1, channelName: 'Ch2', ledCount: 100, effectId: 28,
            colorGroups: [
              LedColorGroup(startLed: 0, endLed: 99, color: [0, 0, 255, 0]),
            ]),
      ],
      composedPattern: const {
        'name': 'Blue chase',
        'effect_id': 28,
        'speed': 140,
        'intensity': 128,
        'has_motion': true,
        'color_groups': [],
      },
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('row 40 — which channels a design goes to', () {
    test('every channel the design paints, nothing about the rest', () async {
      final repo = _Repo();
      final c = _container(repo);
      final report = await applyPositionalDesignDetailed(c.read, _painted());

      expect(report.ok, isTrue);
      final base = repo.json.single;
      final ids = [for (final s in base['seg'] as List) (s as Map)['id']];
      expect(ids, [0, 1], reason: 'the design paints channels 0 and 1');
      // Channel 2 is not mentioned at all: no `{id:2, on:false}` marker.
      expect(ids, isNot(contains(2)));
      for (final s in base['seg'] as List) {
        expect((s as Map)['on'], isTrue);
      }
      expect(repo.pixels.keys, containsAll([0, 1]));
    });

    test('the Home channel-bar selection is ignored', () async {
      final repo = _Repo();
      // Only channel 2 ticked on Home — which the design does not paint.
      final c = _container(repo, selected: {2});
      final report = await applyPositionalDesignDetailed(c.read, _painted());

      expect(report.ok, isTrue);
      final ids = [for (final s in repo.json.single['seg'] as List) (s as Map)['id']];
      expect(ids, [0, 1]);
      expect(repo.pixels.keys, containsAll([0, 1]));
    });

    test('a painted channel the controller lacks is left out', () async {
      final repo = _Repo();
      final c = ProviderContainer(overrides: [
        wledRepositoryProvider.overrideWithValue(repo),
        wledStateProvider.overrideWith(() => _FakeWledNotifier()),
        deviceChannelsProvider.overrideWithValue(const [
          DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 100, gpioPin: 2),
        ]),
        participatingChannelIdsProvider.overrideWithValue(null),
      ]);
      addTearDown(c.dispose);
      await applyPositionalDesignDetailed(c.read, _painted());
      final ids = [for (final s in repo.json.single['seg'] as List) (s as Map)['id']];
      expect(ids, [0]);
    });

    test('a channel set aside ("leave out of shows") stays out', () async {
      final repo = _Repo();
      final c = ProviderContainer(overrides: [
        wledRepositoryProvider.overrideWithValue(repo),
        wledStateProvider.overrideWith(() => _FakeWledNotifier()),
        deviceChannelsProvider.overrideWithValue(_channels),
        participatingChannelIdsProvider.overrideWithValue(const [0, 2]),
      ]);
      addTearDown(c.dispose);
      await applyPositionalDesignDetailed(c.read, _painted());
      final ids = [for (final s in repo.json.single['seg'] as List) (s as Map)['id']];
      expect(ids, [0]);
    });
  });

  group('row 41 — motion', () {
    test('a composed design with motion runs its effect in its colours',
        () async {
      final repo = _Repo();
      final c = _container(repo);
      final report =
          await applyPositionalDesignDetailed(c.read, _composedWithMotion());

      expect(report.ok, isTrue);
      expect(repo.pixels, isEmpty, reason: 'not a still frame');
      final segs = (repo.json.single['seg'] as List).cast<Map>();
      expect(segs.map((s) => s['id']), [0, 1]);
      for (final s in segs) {
        expect(s['fx'], 28);
        expect(s['sx'], 140);
        expect(s['col'], [
          [0, 0, 255, 0]
        ]);
      }
    });

    test('a painted design has no motion', () {
      expect(motionEffectOf(_painted()), isNull);
      expect(motionEffectOf(_composedWithMotion())!.effectId, 28);
    });
  });

  group('row 42 — the failure has its own sentence', () {
    test('the background landed but the pixels did not', () async {
      final repo = _Repo(pixelsOk: false);
      final c = _container(repo);
      final report = await applyPositionalDesignDetailed(c.read, _painted());

      expect(report.ok, isFalse);
      expect(report.wire, SpineWriteResult.pixelsFailed);
      expect(report.message, contains('background'));
      expect(report.message, isNot(contains("Couldn't reach your lights")));
    });

    test('nothing landed', () async {
      final repo = _Repo(baseOk: false);
      final c = _container(repo);
      final report = await applyPositionalDesignDetailed(c.read, _painted());

      expect(report.wire, SpineWriteResult.baseFailed);
      expect(report.message, contains('nothing was changed'));
    });

    test('no controller → the shared reason, not "couldn\'t reach"', () async {
      final c = _container(null);
      final report = await applyPositionalDesignDetailed(c.read, _painted());

      expect(report.ok, isFalse);
      expect(report.wire, SpineWriteResult.noDevice);
      expect(report.message, isNotNull);
      expect(report.message, isNot(contains('Check the connection')));
    });
  });
}
