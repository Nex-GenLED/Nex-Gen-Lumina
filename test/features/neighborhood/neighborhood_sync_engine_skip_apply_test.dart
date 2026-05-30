// SYMPTOM 1 REGRESSION GUARD — the b4a6f46 empty-participation skip-apply
// gate has been DROPPED. This file's original purpose (assert the gate)
// has been INVERTED: it now asserts the gate is gone and stays gone.
//
// Why: b4a6f46 added `if (participating.isEmpty) return;` to
// _executePattern. Any member whose roofline had no isPrimary-flagged
// segment silently no-op'd every sync command, and only the presser's
// home ever ran — Symptom 1 of the multi-home regression. Per
// CHANNEL_MAPPING_AUDIT_2026-05.md:459, participatingChannelIndices is
// dead schema (no UI writes it, no picker exists). The gate was
// defending semantics no UI could produce.
//
// Tests now cover:
//   1. member.participatingChannelIndices == [] → applyJson IS called
//      (regression guard — if this test fails because applyJson is no
//      longer being called on empty participation, the gate has been
//      re-introduced and Symptom 1 is back).
//   2. member.participatingChannelIndices == [0, 1] → applyJson IS
//      called with single-seg, no id, has fx (chokepoint-expandable
//      shape — Bundle 3b.3c assertion preserved).
//
// Driven via @visibleForTesting `executePatternForTest` on the engine.

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
  // Engine constructor calls WidgetsBinding.instance.addObserver (Prompt 5
  // app-lifecycle observer); test binding must be initialized.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetParticipationCacheForTest();
  });

  group('Symptom 1 regression guard — empty participation MUST NOT skip-apply', () {
    test(
        'member.participatingChannelIndices == [] → wledRepo.applyJson '
        'IS called (b4a6f46 gate dropped — every joined home applies)',
        () async {
      final repo = _RecordingWledRepository();
      final member = _baseMember(participatingChannelIndices: const []);

      final container = _makeContainer(
        repo: repo,
        currentMember: member,
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);

      final engine = container.read(neighborhoodSyncEngineProvider);
      await engine.executePatternForTest(_baseCommand());

      expect(repo.applyJsonCalls, hasLength(1),
          reason: 'Symptom 1 regression guard: if applyJson is NOT called '
              'on empty participation, the b4a6f46 skip-apply gate has been '
              're-introduced and only the presser will see lights run');
    });

    test(
        'member.participatingChannelIndices == [0, 1] → applyJson IS '
        'called with single-seg, no id, has fx (chokepoint-expandable '
        'shape, NOT multi-seg-with-ids)', () async {
      final repo = _RecordingWledRepository();
      final member = _baseMember(participatingChannelIndices: const [0, 1]);

      final container = _makeContainer(
        repo: repo,
        currentMember: member,
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);

      final engine = container.read(neighborhoodSyncEngineProvider);
      await engine.executePatternForTest(_baseCommand());

      expect(repo.applyJsonCalls, hasLength(1));
      final payload = repo.applyJsonCalls.first;
      final seg = payload['seg'] as List;
      expect(seg, hasLength(1),
          reason: 'Bundle 3b.3c removed inline per-channel seg-building; '
              'expansion to 2 segs happens at the chokepoint, not here');
      final entry = seg.first as Map;
      expect(entry.containsKey('id'), isFalse,
          reason: 'no id → chokepoint rule 7 will expand');
      expect(entry.containsKey('fx'), isTrue,
          reason: 'has fx → broadcast intent');
    });
  });
}

// ── Helpers ──────────────────────────────────────────────────────────

const _ch0 = DeviceChannel(
    id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2);
const _ch1 = DeviceChannel(
    id: 1, name: 'Channel 2', start: 128, stop: 188, gpioPin: 1);

NeighborhoodMember _baseMember({List<int>? participatingChannelIndices}) {
  return NeighborhoodMember(
    oderId: 'u1',
    displayName: 'House A',
    positionIndex: 0,
    lastSeen: DateTime.utc(2026, 5, 21),
    participatingChannelIndices: participatingChannelIndices,
  );
}

SyncCommand _baseCommand() {
  return SyncCommand(
    id: 'cmd1',
    groupId: 'g1',
    effectId: 0,
    colors: const [0xFFFFFFFF],
    speed: 128,
    intensity: 128,
    brightness: 200,
    startTimestamp: DateTime.utc(2026, 5, 21),
    memberDelays: const {'u1': 0},
    timingConfig: const SyncTimingConfig(),
    patternName: 'Test Pattern',
  );
}

ProviderContainer _makeContainer({
  required WledRepository repo,
  required NeighborhoodMember currentMember,
  required List<DeviceChannel> deviceChannels,
}) {
  return ProviderContainer(
    overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      currentUserMemberProvider.overrideWith((ref) => currentMember),
      currentRooflineConfigProvider
          .overrideWith((ref) => Stream<RooflineConfiguration?>.value(null)),
      deviceChannelsProvider.overrideWith((ref) => deviceChannels),
    ],
  );
}

/// Minimal WledRepository that records applyJson calls and returns false
/// (false return skips the wledStateProvider.notifier path in
/// _executePattern, avoiding the need to wire that notifier in tests).
class _RecordingWledRepository implements WledRepository {
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

  // Rest inherit no-op defaults from the abstract base.
  @override
  Future<WledHardwareConfig?> getConfig() async => null;
  @override
  Future<bool> supportsRgbw() async => false;
  @override
  Future<List<WledSegment>> fetchSegments() async => const <WledSegment>[];
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
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
  @override
  List<WledPreset> getPresets() => const [];
  @override
  void reset() {}
}
