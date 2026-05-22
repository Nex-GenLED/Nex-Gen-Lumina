// Tests for the Stop-Sync teardown wiring in NeighborhoodSyncEngine
// (Phase 2). Covers:
//   • capture-once: executePattern called twice in the same listening
//     session captures only on the FIRST call
//   • teardown gating: stopListening fires teardown only when at least
//     one apply succeeded this session (hasApplied flag is the gate)
//   • teardown skipped: stopListening on a session that never applied
//     anything does NOT touch device state
//   • idempotent stopListening: a second stopListening on an already-
//     stopped engine does not re-fire teardown
//
// Drive the engine via its @visibleForTesting accessors to avoid
// standing up the full Riverpod listen wire-up. The orchestrator itself
// is covered in executeMemberTeardown_test.dart — these tests focus on
// the engine's lifecycle integration.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';
import 'package:nexgen_command/features/neighborhood/services/pre_sync_scene_snapshot.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_persistence.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetParticipationCacheForTest();
  });

  group('capture-once-per-listening-session', () {
    test(
        'executePattern called twice in the same session: getState() called '
        'EXACTLY ONCE; preSyncSceneProvider populated on the first call',
        () async {
      final repo = _CapturingRepo(
        stateToReturn: {'on': true, 'bri': 200},
      );
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0, 1]),
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      // Drive two consecutive _executePattern calls — same listening session.
      await engine.executePatternForTest(_baseCommand(id: 'cmd1'));
      await engine.executePatternForTest(_baseCommand(id: 'cmd2'));

      expect(repo.getStateCallCount, 1,
          reason: 'capture must run only on the first command per session');
      expect(engine.hasCapturedForTest, isTrue);
      final scene = container.read(preSyncSceneProvider);
      expect(scene, isNotNull);
      expect(scene!.groupId, 'g1');
      expect(scene.wledPayload['bri'], 200);
    });

    test(
        'opted-out member (empty participating channels): NO capture, NO '
        'apply, NO scene written (skip-apply preserves state)', () async {
      final repo = _CapturingRepo(stateToReturn: {'on': true});
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const []),
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      await engine.executePatternForTest(_baseCommand());

      expect(repo.getStateCallCount, 0,
          reason: 'capture sits below the participation gate');
      expect(repo.applyCallCount, 0);
      expect(engine.hasCapturedForTest, isFalse);
      expect(engine.hasAppliedForTest, isFalse);
      expect(container.read(preSyncSceneProvider), isNull);
    });
  });

  group('teardown gating via hasApplied flag', () {
    test(
        'stopListening with hasApplied=false (no apply this session): '
        'does NOT call applyJson — device state untouched', () async {
      final repo = _CapturingRepo();
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0, 1]),
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      // Simulate "was listening, never applied".
      engine.setListeningForTest(listening: true);
      engine.setHasAppliedForTest(hasApplied: false);

      engine.stopListening();
      // Yield so the (would-be) async teardown can run if it had been
      // dispatched.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repo.applyCallCount, 0,
          reason: 'no apply happened → no teardown → device left alone');
      expect(engine.isListeningForTest, isFalse);
    });

    test(
        'stopListening with hasApplied=true: teardown fires → applyJson is '
        'called (off-fallback when no schedule/autopilot/scene)', () async {
      final repo = _CapturingRepo();
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0, 1]),
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      engine.setListeningForTest(listening: true);
      engine.setHasAppliedForTest(hasApplied: true);

      engine.stopListening();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repo.applyCallCount, 1,
          reason: 'teardown fires its off-fallback applyJson');
      expect(repo.applyCalls.single, {'on': false});
    });

    test(
        'second stopListening on already-stopped engine: NO additional '
        'teardown (idempotent — only fires on true transition)', () async {
      final repo = _CapturingRepo();
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0, 1]),
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      engine.setListeningForTest(listening: true);
      engine.setHasAppliedForTest(hasApplied: true);
      engine.stopListening(); // first stop fires teardown
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final callsAfterFirst = repo.applyCallCount;

      engine.stopListening(); // second stop on already-stopped engine
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(repo.applyCallCount, callsAfterFirst,
          reason: 'second stop must not re-fire teardown');
    });
  });

  group('executeTeardownForTest (direct teardown probe)', () {
    test('off-fallback: no schedule, no autopilot, no scene → '
        'applyJson({"on": false}) + scene cleared', () async {
      final repo = _CapturingRepo();
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0, 1]),
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      final action = await engine.executeTeardownForTest();

      // We can't import the sealed types into a separate file easily —
      // assert by payload shape instead.
      expect(action, isNotNull);
      expect(repo.applyCalls.single, {'on': false});
      expect(container.read(preSyncSceneProvider), isNull,
          reason: 'clearPreSyncScene runs after every teardown');
    });

    test('scene tier: pre-sync scene set + matching groupId + recent → '
        'applyJson called with scene payload', () async {
      final repo = _CapturingRepo();
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0, 1]),
        deviceChannels: const [_ch0, _ch1],
        activeGroupId: 'g1',
        preSyncScene: PreSyncScene(
          groupId: 'g1',
          wledPayload: const {'on': true, 'bri': 128, 'tag': 'pre-sync'},
          activeLabel: 'Manual',
          capturedAt: DateTime.now(),
        ),
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      await engine.executeTeardownForTest();

      expect(repo.applyCalls.single, {
        'on': true,
        'bri': 128,
        'tag': 'pre-sync',
      });
      expect(container.read(preSyncSceneProvider), isNull,
          reason: 'scene cleared after consumption');
    });

    test('staleness: scene.groupId != activeGroupId → falls through to off',
        () async {
      final repo = _CapturingRepo();
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0, 1]),
        deviceChannels: const [_ch0, _ch1],
        activeGroupId: 'group_NEW',
        preSyncScene: PreSyncScene(
          groupId: 'group_OLD', // user switched groups
          wledPayload: const {'on': true, 'bri': 128},
          activeLabel: null,
          capturedAt: DateTime.now(),
        ),
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      await engine.executeTeardownForTest();

      expect(repo.applyCalls.single, {'on': false},
          reason: 'group-switched scene is stale → off-fallback');
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

const _ch0 = DeviceChannel(
    id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2);
const _ch1 = DeviceChannel(
    id: 1, name: 'Channel 2', start: 128, stop: 138, gpioPin: 1);

NeighborhoodMember _baseMember({List<int>? participatingChannelIndices}) {
  return NeighborhoodMember(
    oderId: 'u1',
    displayName: 'House A',
    positionIndex: 0,
    lastSeen: DateTime.utc(2026, 5, 22),
    participatingChannelIndices: participatingChannelIndices,
  );
}

SyncCommand _baseCommand({String id = 'cmd1'}) {
  return SyncCommand(
    id: id,
    groupId: 'g1',
    effectId: 0,
    colors: const [0xFFFFFFFF],
    speed: 128,
    intensity: 128,
    brightness: 200,
    startTimestamp: DateTime.utc(2026, 5, 22),
    memberDelays: const {'u1': 0},
    timingConfig: const SyncTimingConfig(),
    patternName: 'Test Pattern',
  );
}

ProviderContainer _makeContainer({
  required WledRepository repo,
  required NeighborhoodMember currentMember,
  required List<DeviceChannel> deviceChannels,
  String? activeGroupId,
  PreSyncScene? preSyncScene,
}) {
  return ProviderContainer(
    overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      currentUserMemberProvider.overrideWith((ref) => currentMember),
      currentRooflineConfigProvider
          .overrideWith((ref) => Stream<RooflineConfiguration?>.value(null)),
      deviceChannelsProvider.overrideWith((ref) => deviceChannels),
      if (activeGroupId != null)
        activeNeighborhoodIdProvider.overrideWith((ref) => activeGroupId),
      if (preSyncScene != null)
        preSyncSceneProvider.overrideWith((ref) => preSyncScene),
    ],
  );
}

/// WledRepository fake that records both getState() and applyJson()
/// calls. getState() returns the configured fixture (or null) so the
/// capture path can be exercised without a real controller.
class _CapturingRepo implements WledRepository {
  _CapturingRepo({this.stateToReturn});

  final Map<String, dynamic>? stateToReturn;

  int getStateCallCount = 0;
  int get applyCallCount => applyCalls.length;
  final List<Map<String, dynamic>> applyCalls = [];

  @override
  Future<Map<String, dynamic>?> getState() async {
    getStateCallCount++;
    return stateToReturn == null
        ? null
        : Map<String, dynamic>.from(stateToReturn!);
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyCalls.add(Map<String, dynamic>.from(payload));
    return false; // false → skip the wledStateProvider notifier branch
  }

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
