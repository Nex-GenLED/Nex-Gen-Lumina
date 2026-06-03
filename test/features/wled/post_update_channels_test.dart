// Tests for WledNotifier._postUpdate channel behavior (Week-1 Class-3 remainder).
//
// Three guarantees:
//   1. WARM path (device channels known): a colour/speed change builds one seg
//      per effective channel, each with 'on':true — so a targeted channel that
//      is currently OFF relights (the channel-2-dark class). Regression guard:
//      the warm per-channel multi-seg shape is unchanged otherwise.
//   2. POWER/BRIGHTNESS stay device-global (top-level, no seg) — never bus-0.
//   3. COLD start (hardware config still loading): _postUpdate lazy-resolves the
//      config once, then targets every channel instead of falling to a bus-0
//      single-seg setState.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWledRepository implements WledRepository {
  final List<Map<String, dynamic>> applyJsonCalls = [];
  final List<Map<String, dynamic>> setStateCalls = [];
  bool applyJsonShouldSucceed = true;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return applyJsonShouldSucceed;
  }

  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async {
    setStateCalls.add({
      'on': on,
      'brightness': brightness,
      'speed': speed,
      'color': color,
      'white': white,
    });
    return true;
  }

  @override
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
  @override
  Future<Map<String, dynamic>?> getState() async => null;
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
  Future<WledHardwareConfig?> getConfig() async => null;
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

const _twoChannels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 188, gpioPin: 1),
];

const _twoBusConfig = WledHardwareConfig(
  totalLeds: 188,
  buses: [
    WledLedBus(pin: [2], start: 0, len: 128),
    WledLedBus(pin: [1], start: 128, len: 60),
  ],
);

List<Override> _baseOverrides(_FakeWledRepository repo) => [
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
      ),
      participatingChannelIdsProvider.overrideWithValue(null), // cold cache
    ];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  ProviderContainer _container(List<Override> overrides) {
    final c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    return c;
  }

  test(
      'WARM: setColor on 2 channels → one seg per channel, each on:true + '
      'start/stop (Phase-2 relight + warm-path regression guard)', () async {
    final repo = _FakeWledRepository();
    final container = _container([
      ..._baseOverrides(repo),
      deviceChannelsProvider.overrideWithValue(_twoChannels),
    ]);

    await container
        .read(wledStateProvider.notifier)
        .setColor(const Color(0xFFFF0000), isManualChange: false);

    expect(repo.applyJsonCalls, hasLength(1),
        reason: 'warm path routes through applyJson, not setState');
    expect(repo.setStateCalls, isEmpty);
    final segs = repo.applyJsonCalls.first['seg'] as List;
    expect(segs, hasLength(2), reason: 'one seg per effective channel');
    expect(segs[0]['id'], 0);
    expect(segs[1]['id'], 1);
    expect(segs[0]['on'], isTrue, reason: 'Phase 2: relight targeted channel');
    expect(segs[1]['on'], isTrue);
    expect(segs[0]['start'], 0);
    expect(segs[0]['stop'], 128);
    expect(segs[1]['start'], 128);
    expect(segs[1]['stop'], 188);
    expect(segs[0]['col'], isA<List>());
  });

  test('WARM: setSpeed on 2 channels → both channels get sx + on:true',
      () async {
    final repo = _FakeWledRepository();
    final container = _container([
      ..._baseOverrides(repo),
      deviceChannelsProvider.overrideWithValue(_twoChannels),
    ]);

    await container
        .read(wledStateProvider.notifier)
        .setSpeed(200, isManualChange: false);

    final segs = repo.applyJsonCalls.first['seg'] as List;
    expect(segs, hasLength(2));
    expect(segs[0]['sx'], 200);
    expect(segs[1]['sx'], 200);
    expect(segs[0]['on'], isTrue);
    expect(segs[1]['on'], isTrue);
  });

  test('POWER stays device-global (top-level on, NO seg) — never bus-0',
      () async {
    final repo = _FakeWledRepository();
    final container = _container([
      ..._baseOverrides(repo),
      deviceChannelsProvider.overrideWithValue(_twoChannels),
    ]);

    await container
        .read(wledStateProvider.notifier)
        .togglePower(false, isManualChange: false);

    expect(repo.applyJsonCalls, hasLength(1));
    final payload = repo.applyJsonCalls.first;
    expect(payload['on'], isFalse);
    expect(payload.containsKey('seg'), isFalse,
        reason: 'power is a device-level write — no per-seg, no bus-0');
  });

  test(
      'COLD start: hardware config still loading → _postUpdate lazy-resolves '
      'and targets BOTH channels, NOT a bus-0 setState', () async {
    final repo = _FakeWledRepository();
    // Delayed config so the FIRST effectiveChannelIds read is empty (cold),
    // forcing _postUpdate down the lazy-resolve branch. deviceChannelsProvider
    // is NOT overridden — it derives from this config.
    final container = _container([
      ..._baseOverrides(repo),
      deviceHardwareConfigProvider.overrideWith((ref) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return _twoBusConfig;
      }),
    ]);

    // Cold at first read.
    expect(container.read(effectiveChannelIdsProvider), isEmpty);

    await container
        .read(wledStateProvider.notifier)
        .setColor(const Color(0xFF00FF00), isManualChange: false);

    // After lazy-resolve the colour change fanned out per channel via
    // applyJson — NOT a bus-0 setState.
    expect(repo.setStateCalls, isEmpty,
        reason: 'cold-resolve must avoid the bus-0 setState fallback');
    expect(repo.applyJsonCalls, hasLength(1));
    final segs = repo.applyJsonCalls.first['seg'] as List;
    expect(segs, hasLength(2));
    expect(segs[0]['id'], 0);
    expect(segs[1]['id'], 1);
    expect(segs[0]['on'], isTrue);
    expect(segs[1]['on'], isTrue);
  });
}
