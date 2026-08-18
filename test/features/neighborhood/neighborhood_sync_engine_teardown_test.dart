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
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/neighborhood/services/pre_sync_scene_snapshot.dart';
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
    resetActivePresetLabelCacheForTest();
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
        'paused member (participationStatus=paused): NO capture, NO apply, '
        'NO scene written — _shouldParticipateInSync short-circuits before '
        'the capture/apply path', () async {
      // NOTE: this test originally used participatingChannelIndices=[] to
      // trigger the b4a6f46 empty-participation skip-apply gate. That gate
      // was dropped (Symptom 1 fix); empty participation now applies. The
      // remaining no-apply paths in _scheduleLocalExecution are: paused
      // member, opted-out member, offline member, and member-not-in-
      // memberDelays. We exercise paused here.
      final repo = _CapturingRepo(stateToReturn: {'on': true});
      final pausedMember = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        isOnline: true, // explicit so the gate fires on paused, not isOnline
        lastSeen: DateTime.utc(2026, 5, 22),
        participationStatus: MemberParticipationStatus.paused,
        participatingChannelIndices: const [0, 1],
      );
      final container = _makeContainer(
        repo: repo,
        currentMember: pausedMember,
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      // executePatternForTest bypasses _scheduleLocalExecution's
      // participation check (it goes straight to _executePattern), so we
      // drive via the scheduler entry point to exercise the gate.
      engine.scheduleLocalExecutionForTest(_baseCommand());

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

  group('Fix 2 — Now Playing label fans out across sync lifecycle', () {
    test(
        '_executePattern success: activePresetLabelProvider is set to the '
        'sync design name (matching the start-side write the audit named)',
        () async {
      final repo = _CapturingRepo(applyJsonReturns: true);
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0, 1]),
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      // Pre-condition: label empty.
      expect(container.read(activePresetLabelProvider), isNull);

      await engine.executePatternForTest(_baseCommand());

      expect(container.read(activePresetLabelProvider), 'Test Pattern',
          reason:
              'sync start must fan the design name into the Now Playing label '
              '— without this, non-scene teardown tiers had no source label to '
              'restore from (Bug 3 in the cache-refresh audit)');
    });

    test(
        'teardown off-tier clears the label so Now Playing empties when '
        'lights go off (no schedule/autopilot/scene to fall back on)',
        () async {
      final repo = _CapturingRepo();
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0, 1]),
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      // Seed a label so we can observe the clear.
      container
          .read(activePresetLabelProvider.notifier)
          // ignore: deprecated_member_use_from_same_package
          .state = 'Sync-In-Progress Label';
      expect(container.read(activePresetLabelProvider), isNotNull);

      await engine.executeTeardownForTest();

      expect(container.read(activePresetLabelProvider), isNull,
          reason:
              'off-tier passes literal null → engine wiring clears the label');
    });

    test(
        'teardown scene-tier restores the label from scene.activeLabel '
        '(regression guard — this tier already restored pre-Fix-2)',
        () async {
      final repo = _CapturingRepo();
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0, 1]),
        deviceChannels: const [_ch0, _ch1],
        activeGroupId: 'g1',
        preSyncScene: PreSyncScene(
          groupId: 'g1',
          wledPayload: const {'on': true, 'bri': 128, 'tag': 'pre-sync'},
          activeLabel: 'Manual Warm White',
          capturedAt: DateTime.now(),
        ),
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      // Seed a different label to ensure the restore actually changed it
      // (not just absence of clobber).
      container
          .read(activePresetLabelProvider.notifier)
          // ignore: deprecated_member_use_from_same_package
          .state = 'Sync-In-Progress Label';

      await engine.executeTeardownForTest();

      expect(container.read(activePresetLabelProvider), 'Manual Warm White');
    });
  });

  group('Fix 3 — participation cache restored on teardown', () {
    test(
        'teardown clears the participation cache so dashboard chips '
        'un-strike without needing an app relaunch', () async {
      // Pre-condition: simulate the sync engine having previously written
      // a narrowed participation list (e.g. only channel 0 participates).
      // The dashboard's channel-selector strike-through reads this cache,
      // so the stale value is what causes the bug.
      await saveLocalParticipatingChannels(const [0]);
      expect(peekCachedParticipatingChannels(), equals(const [0]),
          reason: 'pre-condition: cache populated by prior sync apply');

      final repo = _CapturingRepo();
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0]),
        deviceChannels: const [_ch0, _ch1],
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      await engine.executeTeardownForTest();

      // The engine wires restoreParticipation → saveLocalParticipatingChannels(null).
      // That setter updates the in-memory cache SYNCHRONOUSLY before its
      // SharedPreferences await — so peek must return null immediately.
      expect(peekCachedParticipatingChannels(), isNull,
          reason: 'teardown must clear the participation cache. Stale cache '
              'is what keeps the dashboard chip strike-through after sync '
              'stops (Bug 2 in the cache-refresh audit).');
    });
  });

  group('sync-START capture (every member gets a restore point)', () {
    test(
        'startListening captures WITHOUT any command being applied — the '
        'no-apply member used to leave with no snapshot and get blanket-off',
        () async {
      final repo = _CapturingRepo(
        stateToReturn: {'on': false, 'bri': 128, 'seg': [
          {'id': 0, 'on': true, 'fx': 12},
        ]},
      );
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0]),
        deviceChannels: const [_ch0, _ch1],
        activeGroupId: 'g1',
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      engine.startListening();
      // Let the fire-and-forget sync-start capture settle. NO executePattern
      // call here — that is the whole point of the test.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(repo.getStateCallCount, 1,
          reason: 'capture must run at sync START, not on first applied command');
      final scene = container.read(preSyncSceneProvider);
      expect(scene, isNotNull,
          reason: 'a member who never applies a command still needs a restore '
              'point — without one the teardown falls to TurnOff and kills '
              'the master');
      expect(scene!.groupId, 'g1');
      // Captures the true pre-sync state verbatim, master-off included.
      expect(scene.wledPayload['on'], isFalse);

      // And it is mirrored to disk, so a restart can still recover it.
      final persisted = await loadPersistedPreSyncScene();
      expect(persisted, isNotNull);
      expect(persisted!.groupId, 'g1');

      engine.stopListening();
    });

    // ── REGRESSION LOCK, NOT A BUG FIX ──────────────────────────────────
    // Green from the first run. The "sync commands carry on:false" report was
    // a misattribution: the on:false docs in users/{uid}/commands are TEARDOWN
    // restores (a verbatim getState() of a master-off device, which is
    // legitimately {on:false, seg:[{on:true}]}), not broadcasts. Every
    // broadcast builder already hardcodes root on:true. This locks that so a
    // future edit can't quietly introduce the bug that was suspected here.
    test('LOCK: a broadcast apply carries root on:true (already correct)',
        () async {
      final repo = _CapturingRepo(applyJsonReturns: true);
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0]),
        deviceChannels: const [_ch0, _ch1],
        activeGroupId: 'g1',
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      await engine.executePatternForTest(_baseCommand(id: 'lock1'));

      expect(repo.applyCalls, isNotEmpty);
      expect(repo.applyCalls.first['on'], isTrue,
          reason: 'a sync broadcast must never darken the master; segments '
              'being lit is not enough if root on is false');
    });

    test('sync-start capture does not double-capture on a later apply',
        () async {
      final repo = _CapturingRepo(stateToReturn: {'on': true, 'bri': 200});
      final container = _makeContainer(
        repo: repo,
        currentMember: _baseMember(participatingChannelIndices: const [0]),
        deviceChannels: const [_ch0, _ch1],
        activeGroupId: 'g1',
      );
      addTearDown(container.dispose);
      final engine = container.read(neighborhoodSyncEngineProvider);

      engine.startListening();
      await Future<void>.delayed(Duration.zero);
      await engine.executePatternForTest(_baseCommand(id: 'cmd1'));

      expect(repo.getStateCallCount, 1,
          reason: 'the apply path must await the sync-start capture, not '
              'run a second one');

      engine.stopListening();
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
  /// Geometry (`start`/`stop`/`rev`/`mi`) is the PROVISIONING door — a separate
  /// method so `applyJson` can strip geometry unconditionally. This fake does
  /// not exercise it; `false` matches the interface default ("this transport
  /// cannot provision").
  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => false;

  _CapturingRepo({this.stateToReturn, this.applyJsonReturns = false});

  final Map<String, dynamic>? stateToReturn;

  /// Configurable applyJson result. Default false matches existing teardown
  /// tests (which only care about the call payload, not what runs in the
  /// engine's `if (success)` branch). The Fix-2 sync-start tests need true
  /// so the post-apply setLabelWithFingerprint path actually fires.
  final bool applyJsonReturns;

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
    return applyJsonReturns;
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
