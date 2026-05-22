// Tests for [executeMemberTeardown] — the side-effecting orchestrator
// that composes freshness gate + pure resolver + per-tier apply +
// clear-on-consumption. Wired into NeighborhoodSyncEngine.stopListening
// on the listening→not-listening transition.
//
// Convergence-Phase-2: this orchestrator is the live teardown executor.
// These tests lock the per-tier apply contract (what payload reaches
// the controller for each priority outcome) and the staleness gate.
//
// All applies route through WledRepository.applyJson — restoration
// passes through the chokepoint, so participation is respected on
// restore (verified at the engine layer / hardware probe, not here).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/services/pre_sync_scene_snapshot.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_teardown_resolver.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';

void main() {
  group('executeMemberTeardown — per-tier apply', () {
    final now = DateTime.utc(2026, 5, 22, 21, 0);

    test('tier 1 (schedule with payload): applies schedule.wledPayload', () async {
      final repo = _RecordingRepo();
      final clearCalls = _Counter();
      final labelCalls = <String?>[];

      final action = await executeMemberTeardown(
        activeSchedule: _scheduleItem(payload: {'on': true, 'bri': 200}),
        activeAutopilot: null,
        preSyncScene: null,
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: labelCalls.add,
        clearPreSyncScene: clearCalls.inc,
      );

      expect(action, isA<ApplySchedule>());
      expect(repo.applyCalls, hasLength(1));
      expect(repo.applyCalls.single, {'on': true, 'bri': 200});
      expect(labelCalls, isEmpty,
          reason: 'label restoration is scene-tier only');
      expect(clearCalls.value, 1,
          reason: 'clearPreSyncScene runs after every successful teardown');
    });

    test(
        'tier 1 falls through when schedule has no wledPayload (preset-only) '
        '→ next-tier autopilot wins', () async {
      final repo = _RecordingRepo();
      final autopilot = _autopilotItem();

      final action = await executeMemberTeardown(
        activeSchedule: _scheduleItem(payload: null),
        activeAutopilot: autopilot,
        preSyncScene: null,
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
      );

      expect(action, isA<ApplyAutopilot>());
      expect(repo.applyCalls.single, autopilot.wledPayload);
    });

    test('tier 2 (autopilot): applies autopilot.wledPayload', () async {
      final repo = _RecordingRepo();
      final autopilot = _autopilotItem();

      final action = await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: autopilot,
        preSyncScene: null,
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
      );

      expect(action, isA<ApplyAutopilot>());
      expect(repo.applyCalls.single, autopilot.wledPayload);
    });

    test('tier 3 (scene): applies scene.wledPayload AND restores label',
        () async {
      final repo = _RecordingRepo();
      final scene = _scene(label: 'Manual Warm White');
      final labelCalls = <String?>[];

      final action = await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: scene,
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: labelCalls.add,
        clearPreSyncScene: () {},
      );

      expect(action, isA<ApplyPreSyncScene>());
      expect(repo.applyCalls.single, scene.wledPayload);
      expect(labelCalls, ['Manual Warm White'],
          reason: 'scene tier restores the Now Playing label');
    });

    test('tier 3 with null activeLabel: applyJson still fires, callback runs '
        'with null (engine decides null vs no-op)', () async {
      final repo = _RecordingRepo();
      final scene = _scene(label: null);
      final labelCalls = <String?>[];

      await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: scene,
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: labelCalls.add,
        clearPreSyncScene: () {},
      );

      expect(repo.applyCalls.single, scene.wledPayload);
      expect(labelCalls, [null]);
    });

    test('tier 4 (off-fallback): all null → applyJson({"on": false})',
        () async {
      final repo = _RecordingRepo();
      final clearCalls = _Counter();

      final action = await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: null,
        activeGroupId: null,
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: clearCalls.inc,
      );

      expect(action, isA<TurnOff>());
      expect(repo.applyCalls.single, {'on': false});
      expect(clearCalls.value, 1);
    });
  });

  group('executeMemberTeardown — priority dominance', () {
    final now = DateTime.utc(2026, 5, 22, 21, 0);

    test('schedule wins over autopilot + scene', () async {
      final repo = _RecordingRepo();
      final action = await executeMemberTeardown(
        activeSchedule: _scheduleItem(payload: {'on': true, 'bri': 99}),
        activeAutopilot: _autopilotItem(),
        preSyncScene: _scene(),
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
      );
      expect(action, isA<ApplySchedule>());
      expect(repo.applyCalls.single['bri'], 99);
    });

    test('autopilot wins over scene', () async {
      final repo = _RecordingRepo();
      final autopilot = _autopilotItem();
      final action = await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: autopilot,
        preSyncScene: _scene(),
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
      );
      expect(action, isA<ApplyAutopilot>());
      expect(repo.applyCalls.single, autopilot.wledPayload);
    });
  });

  group('executeMemberTeardown — staleness gate', () {
    final now = DateTime.utc(2026, 5, 22, 21, 0);

    test('stale scene (groupId mismatch) → treated as null → falls to off',
        () async {
      final repo = _RecordingRepo();
      final clearCalls = _Counter();

      final action = await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: _scene(groupId: 'group_A'),
        activeGroupId: 'group_B', // user switched groups mid-session
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: clearCalls.inc,
      );

      expect(action, isA<TurnOff>(),
          reason: 'group mismatch must NOT restore the wrong-group scene');
      expect(repo.applyCalls.single, {'on': false});
      expect(clearCalls.value, 1,
          reason: 'clearPreSyncScene still runs (stale snapshot is consumed/discarded)');
    });

    test('stale scene (capturedAt past maxStaleness) → falls through to off',
        () async {
      final repo = _RecordingRepo();
      final ancientScene = _scene(
        groupId: 'g1',
        capturedAt: now.subtract(const Duration(hours: 24)), // way past 12h
      );

      final action = await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: ancientScene,
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
      );

      expect(action, isA<TurnOff>());
      expect(repo.applyCalls.single, {'on': false});
    });

    test('stale scene + active autopilot → autopilot wins (scene drops out, '
        'autopilot tier is reached)', () async {
      final repo = _RecordingRepo();
      final autopilot = _autopilotItem();
      final ancientScene =
          _scene(groupId: 'g1', capturedAt: now.subtract(const Duration(days: 2)));

      final action = await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: autopilot,
        preSyncScene: ancientScene,
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
      );

      expect(action, isA<ApplyAutopilot>());
      expect(repo.applyCalls.single, autopilot.wledPayload);
    });

    test('custom maxStaleness override: scene 1h old + maxStaleness 30min → '
        'stale → off', () async {
      final repo = _RecordingRepo();
      final scene = _scene(
        groupId: 'g1',
        capturedAt: now.subtract(const Duration(hours: 1)),
      );

      final action = await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: scene,
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
        maxStaleness: const Duration(minutes: 30),
      );

      expect(action, isA<TurnOff>());
    });
  });

  group('executeMemberTeardown — restore respects participation via chokepoint', () {
    final now = DateTime.utc(2026, 5, 22, 21, 0);

    test(
        'scene-tier restore with participation=[0]: WledRepository.applyJson '
        'IS called AND the post-chokepoint payload OMITS the non-participating '
        'seg (id:1) so the excluded channel cannot be touched by the restore '
        '(unit/integration equivalent of hardware T5)', () async {
      final repo = _RecordingRepo()..participatingForChokepoint = [0];

      // Scene's wledPayload mirrors what WledRepository.getState() returns:
      // multi-seg WITH ids (full device state from the controller). Seg 1
      // is staged "blue" — if the restore touches it, the post-chokepoint
      // payload will still carry the blue seg 1 entry. The participation
      // filter must drop it for the restore to be safe.
      final sceneFromGetState = <String, dynamic>{
        'on': true,
        'bri': 217,
        'seg': [
          {
            'id': 0,
            'start': 0,
            'stop': 128,
            'fx': 0,
            'col': [
              [255, 232, 192, 0]
            ],
          },
          {
            'id': 1,
            'start': 128,
            'stop': 138,
            'fx': 0,
            'col': [
              [0, 0, 255, 0] // ch1 staged solid blue (the "must not be touched" channel)
            ],
          },
        ],
      };

      await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: PreSyncScene(
          groupId: 'g1',
          wledPayload: sceneFromGetState,
          activeLabel: 'Manual',
          capturedAt: now,
        ),
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
        participating: [0],
      );

      // First half of the assertion: the restore went THROUGH applyJson
      // (i.e. the executor did not build/send a payload that bypassed the
      // repository). This is the routing proof.
      expect(repo.applyCalls, hasLength(1),
          reason: 'restore must route through WledRepository.applyJson — '
              'a bypass would skip the chokepoint participation filter');

      // Second half: the payload, AFTER the chokepoint runs, must not
      // carry the excluded seg. This is the participation-respect proof.
      final postChokepoint = repo.postChokepointCalls.single;
      final segs = postChokepoint['seg'] as List;
      final segIds = segs
          .map((s) => (s as Map)['id'])
          .where((id) => id != null)
          .toList();

      expect(segIds, isNot(contains(1)),
          reason: 'restore must respect participation on the post-chokepoint '
              'payload — a non-participating channel (id:1) must not receive '
              'the restore apply. If this fails, the scene-tier restore is '
              'bypassing the chokepoint participation filter (likely via '
              'expandForParticipation Rule 4 short-circuiting multi-seg-with-'
              'ids payloads), and a non-participating channel would be '
              'force-lit on Stop Sync.');
    });

    test(
        'guard: full participation [0,1] does NOT over-filter — both segs '
        'retained in the post-chokepoint payload (regression guard against '
        'over-eager filtering that would break T1/T3-like full-participation '
        'restore paths)', () async {
      final repo = _RecordingRepo()..participatingForChokepoint = [0, 1];
      final sceneFromGetState = <String, dynamic>{
        'on': true,
        'bri': 217,
        'seg': [
          {
            'id': 0,
            'fx': 0,
            'col': [
              [255, 232, 192, 0]
            ],
          },
          {
            'id': 1,
            'fx': 0,
            'col': [
              [255, 232, 192, 0]
            ],
          },
        ],
      };

      await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: PreSyncScene(
          groupId: 'g1',
          wledPayload: sceneFromGetState,
          activeLabel: 'Warm White',
          capturedAt: now,
        ),
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
        participating: [0, 1],
      );

      final postChokepoint = repo.postChokepointCalls.single;
      final segIds = (postChokepoint['seg'] as List)
          .map((s) => (s as Map)['id'])
          .toList();
      expect(segIds, containsAll(<int>[0, 1]),
          reason: 'full participation must retain ALL captured segs — '
              'over-filtering would regress the T1/T3 hardware passes');
    });

    test(
        'guard: empty participation passes through unchanged '
        '(matches chokepoint Rule 2 — explicit-none is upstream skip)',
        () async {
      final repo = _RecordingRepo()..participatingForChokepoint = const [];
      final sceneFromGetState = <String, dynamic>{
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'fx': 0, 'col': [[255, 0, 0, 0]]},
          {'id': 1, 'fx': 0, 'col': [[0, 0, 255, 0]]},
        ],
      };

      await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: PreSyncScene(
          groupId: 'g1',
          wledPayload: sceneFromGetState,
          activeLabel: null,
          capturedAt: now,
        ),
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
        participating: const [],
      );

      // Filter passes through; chokepoint Rule 2 also passes through.
      // Both segs reach the controller untouched (empty participation
      // means "no filter applied" — actual skip-apply happens upstream).
      final postChokepoint = repo.postChokepointCalls.single;
      final segIds = (postChokepoint['seg'] as List)
          .map((s) => (s as Map)['id'])
          .toList();
      expect(segIds, containsAll(<int>[0, 1]),
          reason: 'empty participating must not be treated as "filter all" — '
              'matches chokepoint Rule 2 semantics');
    });

    test(
        'guard: null participation passes through unchanged '
        '(matches chokepoint Rule 1 — no preference set)', () async {
      final repo = _RecordingRepo()..participatingForChokepoint = null;
      final sceneFromGetState = <String, dynamic>{
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0},
          {'id': 1, 'fx': 0},
        ],
      };

      await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: PreSyncScene(
          groupId: 'g1',
          wledPayload: sceneFromGetState,
          activeLabel: null,
          capturedAt: now,
        ),
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
        participating: null,
      );

      // No participating set → no filter, no expand. Payload reaches
      // the controller verbatim (both segs intact).
      final input = repo.applyCalls.single;
      final segIds = (input['seg'] as List)
          .map((s) => (s as Map)['id'])
          .toList();
      expect(segIds, containsAll(<int>[0, 1]));
    });

    test(
        'defense-in-depth: SCHEDULE tier with a multi-seg-with-ids payload '
        '(hypothetical "save current device state as schedule" flow) is '
        'ALSO filtered correctly — the audit confirmed schedule stores are '
        'single-seg today, but the pre-filter covers the future regression', () async {
      final repo = _RecordingRepo()..participatingForChokepoint = [0];

      // Hypothetical multi-seg-with-ids schedule payload (NOT currently
      // produced by any code path; this test exists as defense-in-depth
      // against a future "save current device state as schedule" flow).
      final scheduleWithMultiSeg = ScheduleItem(
        id: 'sch_multiseg',
        timeLabel: '7:00 PM',
        offTimeLabel: '11:00 PM',
        repeatDays: const ['Mon'],
        actionLabel: 'Captured state',
        enabled: true,
        wledPayload: const <String, dynamic>{
          'on': true,
          'bri': 200,
          'seg': [
            {'id': 0, 'fx': 0, 'col': [[100, 200, 50, 0]]},
            {'id': 1, 'fx': 0, 'col': [[0, 0, 255, 0]]},
          ],
        },
      );

      await executeMemberTeardown(
        activeSchedule: scheduleWithMultiSeg,
        activeAutopilot: null,
        preSyncScene: null,
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
        participating: [0],
      );

      final postChokepoint = repo.postChokepointCalls.single;
      final segIds = (postChokepoint['seg'] as List)
          .map((s) => (s as Map)['id'])
          .toList();
      expect(segIds, isNot(contains(1)),
          reason: 'pre-applyJson filter applies to ALL tiers — defense in '
              'depth against a multi-seg-with-ids schedule payload that '
              'could leak in via a future save-current-state flow');
    });

    test(
        'restore degrades to off-fallback when filter strips ALL segs '
        '(no participating ids match the captured scene)', () async {
      final repo = _RecordingRepo()..participatingForChokepoint = [2];
      final sceneFromGetState = <String, dynamic>{
        'on': true,
        'bri': 217,
        'seg': [
          {'id': 0, 'fx': 0, 'col': [[255, 232, 192, 0]]},
          {'id': 1, 'fx': 0, 'col': [[0, 0, 255, 0]]},
        ],
      };

      await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: PreSyncScene(
          groupId: 'g1',
          wledPayload: sceneFromGetState,
          activeLabel: 'Manual',
          capturedAt: now,
        ),
        activeGroupId: 'g1',
        now: now,
        repo: repo,
        restorePresetLabel: (_) {},
        clearPreSyncScene: () {},
        participating: [2], // participation id not present in scene
      );

      // Filter degrades to {'on': false} — the safe alternative to
      // POSTing a seg-less payload that would leave the controller
      // frozen on the sync state.
      expect(repo.applyCalls.single, {'on': false},
          reason: 'when no participating segs match the captured scene, '
              'fall back to off rather than leak the sync state through');
    });
  });

  group('executeMemberTeardown — clear-on-consumption', () {
    final now = DateTime.utc(2026, 5, 22, 21, 0);

    test('clearPreSyncScene fires after a schedule-tier apply', () async {
      final clearCalls = _Counter();
      await executeMemberTeardown(
        activeSchedule: _scheduleItem(payload: {'on': true}),
        activeAutopilot: null,
        preSyncScene: null,
        activeGroupId: 'g1',
        now: now,
        repo: _RecordingRepo(),
        restorePresetLabel: (_) {},
        clearPreSyncScene: clearCalls.inc,
      );
      expect(clearCalls.value, 1);
    });

    test('clearPreSyncScene fires after an autopilot-tier apply', () async {
      final clearCalls = _Counter();
      await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: _autopilotItem(),
        preSyncScene: null,
        activeGroupId: 'g1',
        now: now,
        repo: _RecordingRepo(),
        restorePresetLabel: (_) {},
        clearPreSyncScene: clearCalls.inc,
      );
      expect(clearCalls.value, 1);
    });

    test('clearPreSyncScene fires after a scene-tier apply', () async {
      final clearCalls = _Counter();
      await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: _scene(),
        activeGroupId: 'g1',
        now: now,
        repo: _RecordingRepo(),
        restorePresetLabel: (_) {},
        clearPreSyncScene: clearCalls.inc,
      );
      expect(clearCalls.value, 1);
    });

    test('clearPreSyncScene fires after an off-tier apply', () async {
      final clearCalls = _Counter();
      await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: null,
        activeGroupId: null,
        now: now,
        repo: _RecordingRepo(),
        restorePresetLabel: (_) {},
        clearPreSyncScene: clearCalls.inc,
      );
      expect(clearCalls.value, 1);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixtures + fakes
// ─────────────────────────────────────────────────────────────────────────────

ScheduleItem _scheduleItem({Map<String, dynamic>? payload}) {
  return ScheduleItem(
    id: 'sch_1',
    timeLabel: '7:00 PM',
    offTimeLabel: '11:00 PM',
    repeatDays: const ['Mon'],
    actionLabel: 'Warm White',
    enabled: true,
    wledPayload: payload,
  );
}

AutopilotScheduleItem _autopilotItem() {
  final t = DateTime.utc(2026, 5, 22, 19, 0);
  return AutopilotScheduleItem(
    id: 'ap_1',
    scheduledTime: t,
    repeatDays: const [],
    patternName: 'Royals Heritage',
    reason: 'Royals home game',
    trigger: AutopilotTrigger.gameDay,
    confidenceScore: 0.9,
    wledPayload: const {
      'on': true,
      'bri': 200,
      'seg': [
        {'fx': 52}
      ],
    },
    createdAt: t,
  );
}

PreSyncScene _scene({
  String groupId = 'g1',
  String? label,
  DateTime? capturedAt,
}) {
  return PreSyncScene(
    groupId: groupId,
    wledPayload: const {'on': true, 'bri': 128},
    activeLabel: label,
    capturedAt: capturedAt ?? DateTime.utc(2026, 5, 22, 20, 0),
  );
}

class _Counter {
  int value = 0;
  void inc() => value++;
}

class _RecordingRepo extends WledRepository {
  final List<Map<String, dynamic>> applyCalls = [];

  /// When set, applyJson mirrors WledService's pipeline:
  ///   normalizeWledPayload → expandForParticipation → recorded as
  ///   [postChokepointCalls]. Lets a test reason about the post-
  ///   chokepoint shape (i.e. what would actually be POSTed to the
  ///   controller) without standing up a real WledService + HTTP layer.
  List<int>? participatingForChokepoint;
  final List<Map<String, dynamic>> postChokepointCalls = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyCalls.add(Map<String, dynamic>.from(payload));
    if (participatingForChokepoint != null) {
      final normalized = normalizeWledPayload(payload);
      final expanded = expandForParticipation(
        normalized,
        participatingForChokepoint,
      );
      postChokepointCalls.add(expanded);
    }
    return true;
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
}
