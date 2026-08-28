// Remote channel display (#91) — the fallback chain that lets an off-LAN
// session SEE its channels.
//
// The defect: `deviceChannelsProvider` derives from `/json/cfg hw.led.ins[]`,
// and `CloudRelayRepository.getConfig()` returns null unconditionally because
// the bridge firmware has no cfg dispatch branch. Off-LAN the bus list was
// therefore always `[]`, the dashboard drew no channels, and per-channel
// commands — which relay perfectly — had no UI to fire them.
//
// These tests lock three things:
//   • the PRECEDENCE of displayChannelsProvider, with each source absent in
//     turn, including the source TAG (a caller that draws an LED range must be
//     able to tell a measurement from a reconstruction);
//   • the reboot-collapse case: a controller showing one seg0 spanning the
//     whole strip yields ONE channel, not zero and not an invented two;
//   • setChannelPower case 3 (master off + channel on) off-LAN against a stub
//     relay — the case that lights the WHOLE HOUSE if the census is empty.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/pixel_map_channel.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _liveChannels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 288, gpioPin: 1),
];

PixelMapChannel _pmChannel(int index, int count) => PixelMapChannel(
      controllerId: 'ctrl-1',
      channelIndex: index,
      segments: const [],
      sourcePixelCount: count,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
    );

/// Builds a container with every tier explicitly stated, so a test that means
/// "this source is ABSENT" cannot accidentally fall through to a live Firebase
/// read instead.
ProviderContainer _container({
  List<DeviceChannel> live = const [],
  List<PixelMapChannel> pixelMap = const [],
  List<int> cachedIds = const [],
  List<DeviceChannel> segments = const [],
}) {
  final c = ProviderContainer(overrides: [
    deviceChannelsProvider.overrideWithValue(live),
    currentPixelMapChannelsProvider.overrideWith((ref) => Stream.value(pixelMap)),
    cachedChannelIdsProvider.overrideWith((ref) async => cachedIds),
    segmentDerivedChannelsProvider.overrideWith((ref) async => segments),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// Drains the async tiers so `valueOrNull` is populated, mirroring a dashboard
/// that has been on screen for a frame.
Future<void> _settle(ProviderContainer c) async {
  await c.read(currentPixelMapChannelsProvider.future);
  await c.read(cachedChannelIdsProvider.future);
  await c.read(segmentDerivedChannelsProvider.future);
}

void main() {
  group('deviceChannelsFromPixelCounts (pure)', () {
    test('cumulative offsets, ascending index order', () {
      final out = deviceChannelsFromPixelCounts({1: 160, 0: 128});
      expect(out.map((c) => c.id), [0, 1]);
      expect(out[0].start, 0);
      expect(out[0].stop, 128);
      expect(out[1].start, 128);
      expect(out[1].stop, 288);
      // A pixel map does not record wiring — never invent a pin.
      expect(out.every((c) => c.gpioPin == -1), isTrue);
    });

    test('empty map yields no channels', () {
      expect(deviceChannelsFromPixelCounts(const {}), isEmpty);
    });
  });

  group('deviceChannelsFromIds (pure)', () {
    test('sorts, dedups, and zeroes the bounds it does not know', () {
      final out = deviceChannelsFromIds([2, 0, 2]);
      expect(out.map((c) => c.id), [0, 2]);
      expect(out.every((c) => c.start == 0 && c.stop == 0), isTrue,
          reason: 'ids-only source must not invent a range');
      expect(out[1].name, 'Channel 3');
    });
  });

  group('deviceChannelsFromSegments (pure)', () {
    test('builds one channel per active segment', () {
      final out = deviceChannelsFromSegments([
        {'id': 0, 'start': 0, 'stop': 128, 'on': true},
        {'id': 1, 'start': 128, 'stop': 288, 'on': false},
      ]);
      expect(out.map((c) => c.id), [0, 1]);
      expect(out[1].stop, 288);
    });

    // The reboot-collapse case (WLED folds two buses into one seg0 spanning the
    // whole strip until a preset reloads). One channel is the honest answer for
    // a live-state view; it is also why pixelMap outranks this tier.
    test('collapsed single seg0 still renders exactly ONE channel', () {
      final out = deviceChannelsFromSegments([
        {'id': 0, 'start': 0, 'stop': 290, 'on': true},
      ]);
      expect(out, hasLength(1));
      expect(out.single.id, 0);
      expect(out.single.start, 0);
      expect(out.single.stop, 290);
    });

    test('inactive padding slots (stop <= start) are not channels', () {
      final out = deviceChannelsFromSegments([
        {'id': 0, 'start': 0, 'stop': 290},
        {'id': 1, 'start': 0, 'stop': 0},
        {'id': 2, 'start': 0, 'stop': 0},
      ]);
      expect(out, hasLength(1),
          reason: 'WLED pads state with empty slots; rendering them would '
              'invent hardware the customer does not have');
    });

    test('a non-list / malformed seg yields nothing rather than throwing', () {
      expect(deviceChannelsFromSegments(null), isEmpty);
      expect(deviceChannelsFromSegments(<dynamic>[]), isEmpty);
      expect(deviceChannelsFromSegments([
        {'id': 'not-an-int', 'start': 0, 'stop': 10},
        {'no-id': true},
      ]), isEmpty);
    });
  });

  group('displayChannelsProvider precedence', () {
    test('1. live cfg wins over every cache', () async {
      final c = _container(
        live: _liveChannels,
        pixelMap: [_pmChannel(0, 999)],
        cachedIds: const [0, 1, 2, 3],
        segments: const [
          DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 290, gpioPin: -1),
        ],
      );
      final d = c.read(displayChannelsProvider);
      expect(d.source, DisplayChannelSource.live);
      expect(d.channels, _liveChannels);
      expect(d.isLive, isTrue);
      expect(d.hasLengths, isTrue);
    });

    // #92: the map must COVER the census to be tagged pixelMap. Complete case
    // — identical behaviour to #91.
    test('2. live absent → pixelMap when it covers every id (unchanged from 91)',
        () async {
      final c = _container(
        pixelMap: [_pmChannel(0, 128), _pmChannel(1, 160)],
        cachedIds: const [0, 1],
        segments: const [
          DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 290, gpioPin: -1),
        ],
      );
      await _settle(c);
      final d = c.read(displayChannelsProvider);
      expect(d.source, DisplayChannelSource.pixelMap);
      expect(d.length, 2);
      expect(d.channels[0].start, 0);
      expect(d.channels[0].stop, 128);
      expect(d.channels[1].start, 128);
      expect(d.channels[1].stop, 288);
      expect(d.isLive, isFalse);
      expect(d.hasLengths, isTrue);
    });

    test('3. live + pixelMap absent → denormalized participation ids', () async {
      final c = _container(
        cachedIds: const [0, 1],
        segments: const [
          DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 290, gpioPin: -1),
        ],
      );
      await _settle(c);
      final d = c.read(displayChannelsProvider);
      expect(d.source, DisplayChannelSource.participation);
      expect(d.channels.map((x) => x.id), [0, 1]);
      // This tier knows ids and nothing else — say so, so no caller draws a
      // fabricated LED count from it.
      expect(d.hasLengths, isFalse);
    });

    test('4. only live seg[] available → segments tier', () async {
      final c = _container(segments: const [
        DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: -1),
        DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 288, gpioPin: -1),
      ]);
      await _settle(c);
      final d = c.read(displayChannelsProvider);
      expect(d.source, DisplayChannelSource.segments);
      expect(d.length, 2);
      expect(d.hasLengths, isTrue);
    });

    test('every source absent → empty, tagged none (never a false channel)',
        () async {
      final c = _container();
      await _settle(c);
      final d = c.read(displayChannelsProvider);
      expect(d.source, DisplayChannelSource.none);
      expect(d.isEmpty, isTrue);
    });

    // The laziness guarantee: on LAN the lower tiers must not even be built, or
    // every healthy local session pays a Firestore read and an extra getState.
    test('LAN path does not instantiate the fallback tiers', () {
      var cachedBuilt = false;
      var segmentsBuilt = false;
      final c = ProviderContainer(overrides: [
        deviceChannelsProvider.overrideWithValue(_liveChannels),
        currentPixelMapChannelsProvider
            .overrideWith((ref) => Stream.value(const <PixelMapChannel>[])),
        cachedChannelIdsProvider.overrideWith((ref) async {
          cachedBuilt = true;
          return const <int>[];
        }),
        segmentDerivedChannelsProvider.overrideWith((ref) async {
          segmentsBuilt = true;
          return const <DeviceChannel>[];
        }),
      ]);
      addTearDown(c.dispose);

      expect(c.read(displayChannelsProvider).source, DisplayChannelSource.live);
      expect(cachedBuilt, isFalse,
          reason: 'a healthy LAN session must not pay for a Firestore read');
      expect(segmentsBuilt, isFalse,
          reason: 'a healthy LAN session must not pay for an extra getState');
    });

    test('an empty pixelMap doc set falls through rather than winning empty',
        () async {
      final c = _container(pixelMap: const [], cachedIds: const [0, 1]);
      await _settle(c);
      expect(c.read(displayChannelsProvider).source,
          DisplayChannelSource.participation);
    });
  });

  // ── #92 COMPLETENESS ────────────────────────────────────────────────────
  //
  // #91 took the pixelMap tier on PRESENCE, so a partially-mapped controller
  // reported however many channels happened to be mapped. On the real venue
  // account (participation [0,1,2], only pixelMap/0 written) that was ONE
  // channel — and ChannelSelectorBar hides itself at `length <= 1`, so the
  // account #91 was written for still saw nothing. The id census decides HOW
  // MANY; the map only contributes lengths.
  group('displayChannelsProvider completeness (#92)', () {
    test('THE VENUE SHAPE: ids [0,1,2] + pixelMap/0 only → 3 channels',
        () async {
      final c = _container(
        pixelMap: [_pmChannel(0, 177)],
        cachedIds: const [0, 1, 2],
      );
      await _settle(c);
      final d = c.read(displayChannelsProvider);

      expect(d.length, 3,
          reason: 'the id census knows there are three channels; #91 reported '
              'one and the selector bar hid itself');
      expect(d.channels.map((x) => x.id), [0, 1, 2]);

      // ch0 keeps its real mapped length…
      expect(d.channels[0].start, 0);
      expect(d.channels[0].stop, 177);
      // …and the unmapped ones contribute no invented span.
      expect(d.channels[1].stop - d.channels[1].start, 0);
      expect(d.channels[2].stop - d.channels[2].start, 0);

      // Partial coverage must NOT claim to be a pixel map.
      expect(d.source, DisplayChannelSource.participation);
      expect(d.hasLengths, isFalse,
          reason: 'a partial map may not present per-channel lengths as '
              'measured for channels it never saw');
    });

    test('unmapped channels do not shift each other by a guessed amount',
        () async {
      // Only the MIDDLE channel is mapped.
      final c = _container(
        pixelMap: [_pmChannel(1, 240)],
        cachedIds: const [0, 1, 2],
      );
      await _settle(c);
      final d = c.read(displayChannelsProvider);
      expect(d.length, 3);
      expect(d.channels[0].stop - d.channels[0].start, 0);
      expect(d.channels[1].stop - d.channels[1].start, 240);
      expect(d.channels[2].stop - d.channels[2].start, 0);
    });

    test('census wins even when the map covers ids the census omits', () async {
      // A stale pixelMap doc for a channel the device no longer reports.
      final c = _container(
        pixelMap: [_pmChannel(0, 100), _pmChannel(7, 50)],
        cachedIds: const [0, 1],
      );
      await _settle(c);
      final d = c.read(displayChannelsProvider);
      expect(d.channels.map((x) => x.id), [0, 1],
          reason: 'a stale map doc must not resurrect a channel the device '
              'no longer lists');
      expect(d.source, DisplayChannelSource.participation);
    });

    test('no id census → pixelMap alone is still the census (91 fallback)',
        () async {
      final c = _container(pixelMap: [_pmChannel(0, 128), _pmChannel(1, 160)]);
      await _settle(c);
      final d = c.read(displayChannelsProvider);
      expect(d.source, DisplayChannelSource.pixelMap);
      expect(d.length, 2);
    });
  });

  group('pure merge builders (#92)', () {
    test('mergeChannelIdsWithPixelCounts enriches by id, cumulative start', () {
      final out = mergeChannelIdsWithPixelCounts(
        ids: [2, 0, 1],
        lengthByChannelIndex: {0: 100, 2: 50},
      );
      expect(out.map((c) => c.id), [0, 1, 2]);
      expect([out[0].start, out[0].stop], [0, 100]);
      expect([out[1].start, out[1].stop], [100, 100]); // unknown → zero-width
      expect([out[2].start, out[2].stop], [100, 150]);
      expect(out.every((c) => c.gpioPin == -1), isTrue);
    });

    test('empty census yields nothing regardless of map contents', () {
      expect(
        mergeChannelIdsWithPixelCounts(
            ids: const [], lengthByChannelIndex: {0: 10}),
        isEmpty,
      );
    });

    test('pixelMapCoversAll is the tag rule', () {
      expect(
        pixelMapCoversAll(ids: [0, 1], lengthByChannelIndex: {0: 1, 1: 2}),
        isTrue,
      );
      expect(
        pixelMapCoversAll(ids: [0, 1, 2], lengthByChannelIndex: {0: 1}),
        isFalse,
      );
      expect(
        pixelMapCoversAll(ids: const [], lengthByChannelIndex: {0: 1}),
        isFalse,
        reason: 'an empty census is not "covered" — there is nothing to cover',
      );
    });
  });

  group('setChannelPower case 3 off-LAN (stub relay)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    // THE REGRESSION THIS EXISTS FOR. Case 3 enumerates every channel so that
    // master-on does not relight the whole house. Off-LAN both the cfg refresh
    // AND the old cached list were empty (same root cause), so the enumeration
    // collapsed to the target alone — one tap, whole house lit. The census now
    // comes from displayChannelsProvider.
    test('master OFF + channel ON emits EVERY channel explicitly from cache',
        () async {
      final repo = _StubRelayRepo()
        ..stateResult = {
          'on': false,
          'seg': [
            {'id': 0, 'on': false},
            {'id': 1, 'on': false},
          ],
        };

      final c = ProviderContainer(overrides: [
        wledRepositoryProvider.overrideWith((ref) => repo),
        wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.remote),
        ),
        participatingChannelIdsProvider.overrideWithValue(null),
        // No live cfg — exactly what the relay gives you.
        currentPixelMapChannelsProvider
            .overrideWith((ref) => Stream.value([_pmChannel(0, 128), _pmChannel(1, 160)])),
        cachedChannelIdsProvider.overrideWith((ref) async => const <int>[]),
        segmentDerivedChannelsProvider
            .overrideWith((ref) async => const <DeviceChannel>[]),
      ]);
      addTearDown(c.dispose);
      await c.read(currentPixelMapChannelsProvider.future);

      // Precondition: the relay really cannot see the buses.
      expect(await repo.getConfig(), isNull);
      expect(c.read(deviceChannelsProvider), isEmpty);
      expect(c.read(displayChannelsProvider).source,
          DisplayChannelSource.pixelMap);

      await c
          .read(wledStateProvider.notifier)
          .setChannelPower(0, true, isManualChange: false);

      expect(repo.applyJsonCalls, hasLength(1));
      final p = repo.applyJsonCalls.single;
      expect(p['on'], isTrue);
      final segs = (p['seg'] as List).cast<Map>();
      expect(segs, hasLength(2),
          reason: 'an empty census here means master-on lights the whole house');
      expect(segs.firstWhere((s) => s['id'] == 0)['on'], isTrue);
      expect(segs.firstWhere((s) => s['id'] == 1)['on'], isFalse);
      // #95 still holds on the cached path: a power write states power only.
      // This matters MORE from a cache, whose bounds are a reconstruction.
      for (final s in segs) {
        expect(s.containsKey('start'), isFalse);
        expect(s.containsKey('stop'), isFalse);
        expect(s.keys.toSet(), {'id', 'on'});
      }
    });

    test('with no cache at all, the target is still represented', () async {
      final repo = _StubRelayRepo()
        ..stateResult = {'on': false, 'seg': const []};

      final c = ProviderContainer(overrides: [
        wledRepositoryProvider.overrideWith((ref) => repo),
        wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.remote),
        ),
        participatingChannelIdsProvider.overrideWithValue(null),
        currentPixelMapChannelsProvider
            .overrideWith((ref) => Stream.value(const <PixelMapChannel>[])),
        cachedChannelIdsProvider.overrideWith((ref) async => const <int>[]),
        segmentDerivedChannelsProvider
            .overrideWith((ref) async => const <DeviceChannel>[]),
      ]);
      addTearDown(c.dispose);

      await c
          .read(wledStateProvider.notifier)
          .setChannelPower(1, true, isManualChange: false);

      final segs = (repo.applyJsonCalls.single['seg'] as List).cast<Map>();
      expect(segs, hasLength(1));
      expect(segs.single['id'], 1);
      expect(segs.single['on'], isTrue);
    });
  });
}

/// A relay-shaped repository: `getState` works (the bridge relays it verbatim),
/// `getConfig` is null (the bridge has no cfg dispatch branch), and geometry is
/// refused outright.
class _StubRelayRepo implements WledRepository {
  final List<Map<String, dynamic>> applyJsonCalls = [];
  Map<String, dynamic>? stateResult;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return true;
  }

  @override
  Future<Map<String, dynamic>?> getState() async => stateResult;

  /// The whole defect, in one line.
  @override
  Future<WledHardwareConfig?> getConfig() async => null;

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async =>
      throw UnsupportedError('geometry writes are LAN-only');

  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      true;

  @override
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => false;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => false;
  @override
  Future<bool> configureSyncReceiver() async => false;
  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      false;
  @override
  Future<bool> supportsRgbw() async => false;
  @override
  Future<List<WledSegment>> fetchSegments() async => const [];
  @override
  Future<bool> renameSegment({required int id, required String name}) async =>
      false;
  @override
  Future<bool> applyToSegments({
    required List<int> ids,
    Color? color,
    int? white,
    int? fx,
    int? speed,
    int? intensity,
  }) async =>
      false;
  @override
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async =>
      false;
  @override
  Future<int?> getTotalLedCount() async => null;
  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async =>
      false;
  @override
  Future<bool> loadPreset(int presetId) async => false;
  @override
  List<WledPreset> getPresets() => const [];
  @override
  void reset() {}
}
