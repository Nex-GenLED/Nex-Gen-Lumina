// FIX A REGRESSION GUARD — Neighborhood Sync must carry pal:5 ("Colors Only")
// through to the applied WLED seg. Without it, WLED falls back to its default
// rainbow palette which OVERRIDES the selected `col` colors → chaotic flashing
// on hardware (the bright-white / random-color strobe).
//
// Before this fix, SyncPatternAssignment reduced a design to
// {effectId, colors, speed, intensity, brightness} and the engine rebuilt a
// pal-less seg — affecting ALL sync designs (Popular AND Browse-All), because
// even a catalog PatternItem that HAD pal:5 lost it in the conversion.
//
// These tests assert:
//   1. The applied seg (what reaches wledRepo.applyJson) carries pal/grp/spc.
//   2. The default is pal:5 (Colors Only) — colors in `col` are NOT replaced.
//   3. A catalog PatternItem's pal survives the full round-trip
//      (payload → SyncPatternAssignment → toJson/fromJson → engine seg).
//   4. A non-default palette (e.g. pal:6) is preserved, not forced to 5.
//   5. Complement-mode (per-member color) designs still carry pal:5.
//
// Engine assertions are driven via @visibleForTesting `executePatternForTest`
// and a recording WledRepository (same harness as the skip-apply guard).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_persistence.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetParticipationCacheForTest();
  });

  // ── Pure-model round-trip (no engine) ─────────────────────────────────────

  group('SyncPatternAssignment carries pal/grp/spc', () {
    test('default assignment uses the catalog invariant pal:5, grp:1, spc:0', () {
      const a = SyncPatternAssignment(
        name: 'X', effectId: 28, colors: [0x00BCD4, 0xFFFFFF],
      );
      expect(a.pal, 5);
      expect(a.grp, 1);
      expect(a.spc, 0);
    });

    test('fromWledPayload extracts pal/grp/spc from a catalog PatternItem', () {
      // Shape produced by PatternRepository.generatePatternsForNode (pal:5).
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'fx': 28,
            'sx': 128,
            'ix': 128,
            'pal': 5,
            'grp': 1,
            'spc': 0,
            'col': [
              [0, 188, 212, 0],
              [255, 255, 255, 0],
            ],
          },
        ],
      };
      final a = SyncPatternAssignment.fromWledPayload(
          name: 'Cyan Chase', payload: payload);
      expect(a.pal, 5, reason: "catalog pal:5 must survive the conversion");
      expect(a.effectId, 28);
      expect(a.colors, [0x00BCD4, 0xFFFFFF]);
    });

    test('fromWledPayload preserves a NON-default palette (e.g. pal:6)', () {
      // Some catalog nodes use special palettes (e.g. Red/White/Blue = pal:6).
      final payload = {
        'seg': [
          {'fx': 0, 'pal': 6, 'col': [[255, 0, 0, 0]]},
        ],
      };
      final a = SyncPatternAssignment.fromWledPayload(name: 'Patriot', payload: payload);
      expect(a.pal, 6, reason: 'fidelity: do not force every design to pal:5');
    });

    test('fromWledPayload defaults to pal:5 when the seg omits pal', () {
      final payload = {
        'seg': [
          {'fx': 15, 'col': [[0, 229, 255, 0]]},
        ],
      };
      final a = SyncPatternAssignment.fromWledPayload(name: 'Running', payload: payload);
      expect(a.pal, 5);
    });

    test('fromLibraryNode (Browse-All path) defaults to pal:5', () {
      final a = SyncPatternAssignment.fromLibraryNode(
        name: 'Ocean - Chase',
        themeColors: const [Color(0xFF2196F3), Color(0xFF00BCD4)],
        effectId: 28,
      );
      expect(a.pal, 5,
          reason: 'Browse-All picks must apply Colors Only, not rainbow');
    });

    test('toJson/fromJson round-trips pal/grp/spc (Firestore per-house path)', () {
      const a = SyncPatternAssignment(
        name: 'Special', effectId: 76, colors: [0xFF9800, 0xFFEB3B],
        pal: 6, grp: 2, spc: 1,
      );
      final round = SyncPatternAssignment.fromJson(a.toJson());
      expect(round.pal, 6);
      expect(round.grp, 2);
      expect(round.spc, 1);
    });

    test('fromJson on a LEGACY command (no pal keys) defaults to pal:5', () {
      final legacy = {
        'name': 'Old', 'effectId': 28, 'colors': [0x00BCD4],
        'speed': 128, 'intensity': 128, 'brightness': 200,
      };
      final a = SyncPatternAssignment.fromJson(legacy);
      expect(a.pal, 5, reason: 'old commands must stop rainbow-flashing');
      expect(a.grp, 1);
      expect(a.spc, 0);
    });
  });

  group('SyncCommand.getPatternForMember carries pal/grp/spc', () {
    test('global path (no per-house override) inherits the command pal', () {
      final cmd = SyncCommand(
        id: 'c', groupId: 'g', effectId: 28, colors: const [0x00BCD4],
        speed: 128, intensity: 128, brightness: 200,
        startTimestamp: DateTime.utc(2026, 5, 21), memberDelays: const {'u1': 0},
        timingConfig: const SyncTimingConfig(), pal: 6, grp: 2, spc: 1,
      );
      final p = cmd.getPatternForMember('u1');
      expect(p.pal, 6);
      expect(p.grp, 2);
      expect(p.spc, 1);
    });
  });

  // ── Engine-level: the APPLIED payload (what reaches the device) ────────────

  group('Applied sync seg carries pal:5 — colors not overridden by rainbow', () {
    test('default global command → applied seg has pal:5, grp:1, spc:0', () async {
      final repo = _RecordingWledRepository();
      final container = _makeContainer(repo: repo);
      addTearDown(container.dispose);

      final engine = container.read(neighborhoodSyncEngineProvider);
      await engine.executePatternForTest(_command(colors: const [0x00BCD4, 0xFFFFFF]));

      final seg = (repo.applyJsonCalls.single['seg'] as List).single as Map;
      expect(seg['pal'], 5,
          reason: 'CHAOS FIX: applied seg must carry pal:5 (Colors Only)');
      expect(seg['grp'], 1);
      expect(seg['spc'], 0);
      // The selected colors reached `col` and were not replaced by a palette.
      final col = seg['col'] as List;
      expect(col.first, [0, 188, 212, 0]);
      expect(col[1], [255, 255, 255, 0]);
    });

    test('catalog PatternItem (pal:5) → per-house override → applied seg keeps pal:5',
        () async {
      // Full round-trip: catalog payload → fromWledPayload → toJson/fromJson
      // (the Firestore hop for memberPatternOverrides) → engine seg.
      final catalogPayload = {
        'bri': 200,
        'seg': [
          {'fx': 28, 'sx': 128, 'ix': 128, 'pal': 5, 'grp': 1, 'spc': 0,
           'col': [[0, 188, 212, 0]]},
        ],
      };
      final assignment = SyncPatternAssignment.fromJson(
        SyncPatternAssignment.fromWledPayload(
                name: 'Cyan Chase', payload: catalogPayload)
            .toJson(),
      );
      expect(assignment.pal, 5);

      final repo = _RecordingWledRepository();
      final container = _makeContainer(repo: repo);
      addTearDown(container.dispose);

      final engine = container.read(neighborhoodSyncEngineProvider);
      await engine.executePatternForTest(
        _command(colors: const [0x00BCD4], overrides: {'u1': assignment}),
      );

      final seg = (repo.applyJsonCalls.single['seg'] as List).single as Map;
      expect(seg['pal'], 5,
          reason: 'Browse-All catalog pick must retain pal:5 end-to-end');
    });

    test('non-default palette (pal:6) is preserved through to the applied seg',
        () async {
      final repo = _RecordingWledRepository();
      final container = _makeContainer(repo: repo);
      addTearDown(container.dispose);

      final engine = container.read(neighborhoodSyncEngineProvider);
      await engine.executePatternForTest(_command(colors: const [0xFF0000], pal: 6));

      final seg = (repo.applyJsonCalls.single['seg'] as List).single as Map;
      expect(seg['pal'], 6);
    });

    test('complement-mode design still carries pal:5 (colors not rainbow)', () async {
      final repo = _RecordingWledRepository();
      final container = _makeContainer(repo: repo);
      addTearDown(container.dispose);

      final cmd = SyncCommand(
        id: 'c', groupId: 'g', effectId: 0, colors: const [0xFFFFFF],
        speed: 128, intensity: 128, brightness: 200,
        startTimestamp: DateTime.utc(2026, 5, 21), memberDelays: const {'u1': 0},
        timingConfig: const SyncTimingConfig(),
        syncType: SyncType.complement,
        memberColorOverrides: const {'u1': [0xFF0000]},
      );

      final engine = container.read(neighborhoodSyncEngineProvider);
      await engine.executePatternForTest(cmd);

      final seg = (repo.applyJsonCalls.single['seg'] as List).single as Map;
      expect(seg['pal'], 5);
      expect((seg['col'] as List).first, [255, 0, 0, 0],
          reason: 'complement member color reaches col, not overridden');
    });
  });
}

// ── Helpers ──────────────────────────────────────────────────────────────

SyncCommand _command({
  required List<int> colors,
  int pal = 5,
  Map<String, SyncPatternAssignment>? overrides,
}) {
  return SyncCommand(
    id: 'cmd1',
    groupId: 'g1',
    effectId: 28,
    colors: colors,
    speed: 128,
    intensity: 128,
    brightness: 200,
    startTimestamp: DateTime.utc(2026, 5, 21),
    memberDelays: const {'u1': 0},
    timingConfig: const SyncTimingConfig(),
    patternName: 'Test',
    pal: pal,
    memberPatternOverrides: overrides,
  );
}

const _ch0 = DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2);
const _ch1 = DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 188, gpioPin: 1);

NeighborhoodMember _member() => NeighborhoodMember(
      oderId: 'u1',
      displayName: 'House A',
      positionIndex: 0,
      lastSeen: DateTime.utc(2026, 5, 21),
      participatingChannelIndices: const [0, 1],
    );

ProviderContainer _makeContainer({required WledRepository repo}) {
  return ProviderContainer(
    overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      currentUserMemberProvider.overrideWith((ref) => _member()),
      currentRooflineConfigProvider
          .overrideWith((ref) => Stream<RooflineConfiguration?>.value(null)),
      deviceChannelsProvider.overrideWith((ref) => const [_ch0, _ch1]),
    ],
  );
}

class _RecordingWledRepository implements WledRepository {
  /// Geometry (`start`/`stop`/`rev`/`mi`) is the PROVISIONING door — a separate
  /// method so `applyJson` can strip geometry unconditionally. This fake does
  /// not exercise it; `false` matches the interface default ("this transport
  /// cannot provision").
  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => false;

  final List<Map<String, dynamic>> applyJsonCalls = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return false; // false → skip wledStateProvider.notifier branch
  }

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
  Future<List<WledSegment>> fetchSegments() async => const <WledSegment>[];
  @override
  Future<bool> renameSegment({required int id, required String name}) async => false;
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
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
  @override
  List<WledPreset> getPresets() => const [];
  @override
  void reset() {}
}
