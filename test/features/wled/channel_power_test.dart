// Per-channel power (P1-43) — the additive seg-scoped path.
//
// Firmware segment independence is bench-proven; the app previously wrote power
// as top-level master {"on":bool} only, so a per-channel off was inexpressible.
// These tests lock the four decided policy shapes at BOTH layers:
//   • buildChannelPowerPayload — the pure payload builder (deterministic).
//   • WledNotifier.setChannelPower — the action, via a fake repo capturing POSTs
//     (asserts exactly ONE /json/state post, driven by live getState + fresh
//     getConfig bounds).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _twoChannels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 288, gpioPin: 1),
];

void main() {
  group('buildChannelPowerPayload (pure policy shapes)', () {
    // (a) Channel ON while master is OFF → ONE post: master on + EVERY channel
    // explicit (target on, all others off). Master-on alone would relight all.
    test('ON while master OFF → master on + all segs explicit (target on)', () {
      final p = buildChannelPowerPayload(
        channelId: 0,
        on: true,
        masterOn: false,
        litChannelIds: const {},
        channels: _twoChannels,
      );
      expect(p['on'], isTrue);
      final segs = p['seg'] as List;
      expect(segs, hasLength(2));
      expect(segs.firstWhere((s) => s['id'] == 0)['on'], isTrue);
      expect(segs.firstWhere((s) => s['id'] == 1)['on'], isFalse);
      // #95: bounds are NEVER emitted, not even on the enumerating case.
      expect(segs.firstWhere((s) => s['id'] == 1).containsKey('start'), isFalse);
      expect(segs.firstWhere((s) => s['id'] == 1).containsKey('stop'), isFalse);
    });

    // (b) Single-channel OFF while others stay lit → seg-scoped off, NO master.
    test('OFF while others lit → seg off, NO top-level on', () {
      final p = buildChannelPowerPayload(
        channelId: 0,
        on: false,
        masterOn: true,
        litChannelIds: const {0, 1},
        channels: _twoChannels,
      );
      expect(p.containsKey('on'), isFalse,
          reason: 'a single-channel off must never touch master');
      final segs = p['seg'] as List;
      expect(segs, hasLength(1));
      expect(segs.first['id'], 0);
      expect(segs.first['on'], isFalse);
    });

    // (c) OFF the LAST lit channel → master follows so state does not lie.
    test('OFF last lit channel → master off {"on":false}, no seg', () {
      final p = buildChannelPowerPayload(
        channelId: 0,
        on: false,
        masterOn: true,
        litChannelIds: const {0}, // only channel 0 lit
        channels: _twoChannels,
      );
      expect(p['on'], isFalse);
      expect(p.containsKey('seg'), isFalse);
    });

    // (d) Channel ON while master already ON → seg-scoped on only.
    test('ON while master already ON → seg on only, NO top-level on', () {
      final p = buildChannelPowerPayload(
        channelId: 1,
        on: true,
        masterOn: true,
        litChannelIds: const {0},
        channels: _twoChannels,
      );
      expect(p.containsKey('on'), isFalse);
      final segs = p['seg'] as List;
      expect(segs, hasLength(1));
      expect(segs.first['id'], 1);
      expect(segs.first['on'], isTrue);
      expect(segs.first.containsKey('start'), isFalse);
      expect(segs.first.containsKey('stop'), isFalse);
    });

    // ── #95 PIN: a power write states POWER and states nothing else ────────
    //
    // This builder used to stamp start/stop whenever a config refresh had
    // succeeded. That is geometry, and an apply never writes geometry (#76 for
    // the seven design builders, #89 for applyChannelFilter). This builder was
    // in neither census — the third time a geometry sweep under-counted its own
    // family — so the pin is written as a FIELD SWEEP over every policy case
    // rather than as spot checks on the two cases someone remembered.
    test('#95 — NO geometry field, in ANY case, ever', () {
      const geometry = {
        'start', 'stop', 'len', 'rev', 'mi', 'of', 'grp', 'spc',
      };

      final cases = <String, Map<String, dynamic>>{
        'ON while master OFF (enumerates every channel)':
            buildChannelPowerPayload(
          channelId: 0, on: true, masterOn: false,
          litChannelIds: const {}, channels: _twoChannels,
        ),
        'ON while master ON': buildChannelPowerPayload(
          channelId: 1, on: true, masterOn: true,
          litChannelIds: const {0}, channels: _twoChannels,
        ),
        'OFF while others lit': buildChannelPowerPayload(
          channelId: 0, on: false, masterOn: true,
          litChannelIds: const {0, 1}, channels: _twoChannels,
        ),
        'OFF last lit channel': buildChannelPowerPayload(
          channelId: 0, on: false, masterOn: true,
          litChannelIds: const {0}, channels: _twoChannels,
        ),
      };

      cases.forEach((name, payload) {
        final segs = payload['seg'];
        if (segs is! List) return; // master-only payload carries no seg at all
        for (final s in segs.cast<Map>()) {
          for (final field in geometry) {
            expect(s.containsKey(field), isFalse,
                reason: '$name: seg ${s['id']} emitted geometry "$field" — '
                    'a power change must state power and nothing else (#95)');
          }
          // And it must still say the two things it IS for.
          expect(s.containsKey('id'), isTrue, reason: name);
          expect(s.containsKey('on'), isTrue, reason: name);
        }
      });
    });

    test('case 3 includes the target even when channels is empty', () {
      final p = buildChannelPowerPayload(
        channelId: 2,
        on: true,
        masterOn: false,
        litChannelIds: const {},
        channels: const [],
      );
      expect(p['on'], isTrue);
      final segs = p['seg'] as List;
      expect(segs, hasLength(1));
      expect(segs.first['id'], 2);
      expect(segs.first['on'], isTrue);
    });
  });

  group('WledNotifier.setChannelPower (action — fake service captures POSTs)',
      () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    ProviderContainer container(_FakeRepo repo) {
      final c = ProviderContainer(overrides: [
        wledRepositoryProvider.overrideWith((ref) => repo),
        wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
        ),
        participatingChannelIdsProvider.overrideWithValue(null),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('master OFF + channel ON → exactly ONE post: master on + all segs', () async {
      final repo = _FakeRepo()
        ..stateResult = {
          'on': false,
          'seg': [
            {'id': 0, 'on': false},
            {'id': 1, 'on': false},
          ],
        }
        ..config = _twoBusConfig;
      final c = container(repo);

      await c
          .read(wledStateProvider.notifier)
          .setChannelPower(0, true, isManualChange: false);

      expect(repo.applyJsonCalls, hasLength(1),
          reason: 'master-off channel-on is ONE post, not master + seg races');
      final p = repo.applyJsonCalls.single;
      expect(p['on'], isTrue);
      final segs = p['seg'] as List;
      expect(segs, hasLength(2));
      expect(segs.firstWhere((s) => s['id'] == 0)['on'], isTrue);
      expect(segs.firstWhere((s) => s['id'] == 1)['on'], isFalse);

      // #95: the getConfig refresh still runs — but for the CENSUS, not for
      // bounds. It must produce both segs (below) and no geometry (above).
      // Dropping the refresh as "bounds-only" collapsed this to one seg, which
      // would let master-on relight the whole house.
      expect(segs.firstWhere((s) => s['id'] == 1).containsKey('start'), isFalse,
          reason: 'a power change states power and nothing else (#95)');
      expect(segs.firstWhere((s) => s['id'] == 1).containsKey('stop'), isFalse);
    });

    test('single-channel OFF (others lit) never writes a top-level on', () async {
      final repo = _FakeRepo()
        ..stateResult = {
          'on': true,
          'seg': [
            {'id': 0, 'on': true},
            {'id': 1, 'on': true},
          ],
        }
        ..config = _twoBusConfig;
      final c = container(repo);

      await c
          .read(wledStateProvider.notifier)
          .setChannelPower(0, false, isManualChange: false);

      final p = repo.applyJsonCalls.single;
      expect(p.containsKey('on'), isFalse);
      expect((p['seg'] as List).single['id'], 0);
      expect((p['seg'] as List).single['on'], isFalse);
    });

    test('OFF the last lit channel writes master off', () async {
      final repo = _FakeRepo()
        ..stateResult = {
          'on': true,
          'seg': [
            {'id': 0, 'on': true},
            {'id': 1, 'on': false},
          ],
        }
        ..config = _twoBusConfig;
      final c = container(repo);

      await c
          .read(wledStateProvider.notifier)
          .setChannelPower(0, false, isManualChange: false);

      final p = repo.applyJsonCalls.single;
      expect(p['on'], isFalse);
      expect(p.containsKey('seg'), isFalse);
    });

    test('ON while master already on → seg-scoped on only (no master write)',
        () async {
      final repo = _FakeRepo()
        ..stateResult = {
          'on': true,
          'seg': [
            {'id': 0, 'on': false},
            {'id': 1, 'on': true},
          ],
        }
        ..config = _twoBusConfig;
      final c = container(repo);

      await c
          .read(wledStateProvider.notifier)
          .setChannelPower(0, true, isManualChange: false);

      final p = repo.applyJsonCalls.single;
      expect(p.containsKey('on'), isFalse);
      expect((p['seg'] as List).single['id'], 0);
      expect((p['seg'] as List).single['on'], isTrue);
    });

    test('config unavailable → id-only seg entries (no stale bounds, P1-42)',
        () async {
      final repo = _FakeRepo()
        ..stateResult = {
          'on': false,
          'seg': [
            {'id': 0, 'on': false},
            {'id': 1, 'on': false},
          ],
        }
        ..config = null; // getConfig returns null → refresh yields no channels
      final c = container(repo);

      await c
          .read(wledStateProvider.notifier)
          .setChannelPower(0, true, isManualChange: false);

      final p = repo.applyJsonCalls.single;
      expect(p['on'], isTrue);
      for (final s in p['seg'] as List) {
        expect((s as Map).containsKey('start'), isFalse);
        expect(s.containsKey('stop'), isFalse);
      }
    });
  });
}

const _twoBusConfig = WledHardwareConfig(
  totalLeds: 288,
  buses: [
    WledLedBus(pin: [2], start: 0, len: 128),
    WledLedBus(pin: [1], start: 128, len: 160),
  ],
);

class _FakeRepo implements WledRepository {
  final List<Map<String, dynamic>> applyJsonCalls = [];
  Map<String, dynamic>? stateResult;
  WledHardwareConfig? config;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return true;
  }

  @override
  Future<Map<String, dynamic>?> getState() async => stateResult;

  @override
  Future<WledHardwareConfig?> getConfig() async => config;

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
