// Tests for WledNotifier.applyToDevice — the Class-1 multi-channel chokepoint
// (Week-1 consolidated fix). Every aesthetic-command site that builds a RAW
// broadcast payload (Current Colors, Lumina AI, Audio, Geofence, Voice,
// library Scenes) routes through this so the command targets EVERY effective
// channel, not just bus 0.
//
// The headline guarantee: on a 2-channel install with a COLD/null
// participation cache, a raw single-seg payload fans out to seg ids 0 AND 1.
// applyToDevice derives its target set from effectiveChannelIdsProvider
// (selector ∩ participation ∩ device buses), so a null participation cache
// resolves to "all device channels" — the fix is cache-independent, which is
// what dissolves the Class-3 cold-cache dependency for these paths.

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
  bool applyJsonShouldSucceed = true;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return applyJsonShouldSucceed;
  }

  @override
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
  @override
  Future<Map<String, dynamic>?> getState() async => null;
  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      false;
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
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 138, gpioPin: 14),
];

const _oneChannel = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
];

/// Builds overrides: a fake repo, local connectivity, a device-channel list,
/// and a COLD participation cache (participatingChannelIdsProvider → null).
/// effectiveChannelIdsProvider is left to compute from these so the test
/// exercises the real selector ∩ participation ∩ device chain.
List<Override> _overrides(
  _FakeWledRepository repo, {
  required List<DeviceChannel> channels,
}) =>
    [
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
      ),
      deviceChannelsProvider.overrideWithValue(channels),
      // COLD cache: no participation preference set.
      participatingChannelIdsProvider.overrideWithValue(null),
    ];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  ProviderContainer _container(
    _FakeWledRepository repo, {
    required List<DeviceChannel> channels,
  }) {
    final c = ProviderContainer(overrides: _overrides(repo, channels: channels));
    addTearDown(c.dispose); // cancels WledNotifier's poll Timer
    return c;
  }

  test(
      '2-channel + COLD cache: raw single-seg fans out to seg ids 0 AND 1, '
      'each on:true (the Game-Day channel-2 class, fixed cache-independently)',
      () async {
    final repo = _FakeWledRepository();
    final container = _container(repo, channels: _twoChannels);

    // Sanity: cold cache → effective = all device channels.
    expect(container.read(effectiveChannelIdsProvider), const [0, 1]);

    final ok = await container.read(wledStateProvider.notifier).applyToDevice(
      {
        'on': true,
        'bri': 200,
        'seg': [
          // RAW broadcast intent: single template seg, NO per-seg id.
          {'fx': 28, 'sx': 160, 'col': [[255, 0, 0, 0]]},
        ],
      },
      labelHint: null,
    );

    expect(ok, isTrue);
    expect(repo.applyJsonCalls, hasLength(1));
    final segs = repo.applyJsonCalls.first['seg'] as List;
    expect(segs, hasLength(2), reason: 'one seg per effective channel');
    expect(segs[0]['id'], 0);
    expect(segs[1]['id'], 1);
    expect(segs[0]['on'], isTrue);
    expect(segs[1]['on'], isTrue);
    // Bus ranges carried from DeviceChannel config.
    expect(segs[0]['start'], 0);
    expect(segs[0]['stop'], 128);
    expect(segs[1]['start'], 128);
    expect(segs[1]['stop'], 138);
    // Template fields preserved on each.
    expect(segs[0]['fx'], 28);
    expect(segs[1]['fx'], 28);
  });

  test('single-channel install still works: raw payload → one seg id 0',
      () async {
    final repo = _FakeWledRepository();
    final container = _container(repo, channels: _oneChannel);

    final ok = await container.read(wledStateProvider.notifier).applyToDevice(
      {
        'on': true,
        'seg': [
          {'fx': 0, 'col': [[0, 0, 255, 0]]},
        ],
      },
      labelHint: null,
    );

    expect(ok, isTrue);
    final segs = repo.applyJsonCalls.first['seg'] as List;
    expect(segs, hasLength(1));
    expect(segs.first['id'], 0);
    expect(segs.first['on'], isTrue);
  });

  test('U1 gate: no device channels → returns false, no device write',
      () async {
    final repo = _FakeWledRepository();
    final container = _container(repo, channels: const <DeviceChannel>[]);

    expect(container.read(effectiveChannelIdsProvider), isEmpty);

    final ok = await container.read(wledStateProvider.notifier).applyToDevice(
      {
        'on': true,
        'seg': [
          {'fx': 0, 'col': [[255, 0, 0, 0]]},
        ],
      },
      labelHint: null,
    );

    expect(ok, isFalse, reason: 'U1 gate short-circuits before any write');
    expect(repo.applyJsonCalls, isEmpty);
  });

  test(
      'double-filter guard: id-bearing multi-seg (custom-scene shape) passes '
      'through UNCHANGED — per-channel colors NOT flattened to bus 0',
      () async {
    final repo = _FakeWledRepository();
    final container = _container(repo, channels: _twoChannels);

    // Shape produced by CustomDesign.toWledPayload() / a custom scene that
    // reaches applyToDevice via the Lumina AI command router. Each channel
    // has a DISTINCT colour. Re-filtering would template off seg.first and
    // make both channels red.
    final ok = await container.read(wledStateProvider.notifier).applyToDevice(
      {
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'fx': 0, 'col': [[255, 0, 0, 0]]}, // ch0 red
          {'id': 1, 'fx': 0, 'col': [[0, 0, 255, 0]]}, // ch1 blue
        ],
      },
      labelHint: null,
    );

    expect(ok, isTrue);
    final segs = repo.applyJsonCalls.first['seg'] as List;
    expect(segs, hasLength(2));
    expect(segs[0]['col'], equals([[255, 0, 0, 0]]),
        reason: 'ch0 stays red');
    expect(segs[1]['col'], equals([[0, 0, 255, 0]]),
        reason: 'ch1 stays blue — NOT flattened to seg.first');
  });

  test(
      'discriminator: single-seg WITH explicit id passes through (targeted '
      'apply, not broadcast — documents the helper contract)', () async {
    final repo = _FakeWledRepository();
    final container = _container(repo, channels: _twoChannels);

    final ok = await container.read(wledStateProvider.notifier).applyToDevice(
      {
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0, 'col': [[255, 255, 255, 0]]},
        ],
      },
      labelHint: null,
    );

    expect(ok, isTrue);
    final segs = repo.applyJsonCalls.first['seg'] as List;
    expect(segs, hasLength(1),
        reason: 'explicit id:0 means "seg 0 specifically" — not expanded');
    expect(segs.first['id'], 0);
  });
}
