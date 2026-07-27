// Persistence + freshness contract for the pre-sync scene snapshot.
//
// Background: leaving a sync could turn the whole system off. The teardown
// tier order (schedule -> autopilot -> preSyncScene -> TurnOff) was correct,
// but the snapshot lived ONLY in an in-memory StateProvider. Kill the app
// mid-session and the snapshot vanished, so the resolver fell through to
// TurnOff() and wrote {'on': false} — master off.
//
// These lock the durable half of the fix: the snapshot round-trips through
// SharedPreferences, survives a "restart" (a fresh ProviderContainer reading
// from disk), is still subject to the 12h staleness gate, and is dropped once
// a teardown consumes it.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/features/neighborhood/services/pre_sync_scene_snapshot.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_teardown_resolver.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

/// Records applyJson payloads; everything else on the interface is unused
/// here and routed to noSuchMethod so an unexpected call fails loudly.
class _RecordingRepo implements WledRepository {
  _RecordingRepo(this.applied);

  final List<Map<String, dynamic>> applied;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applied.add(Map<String, dynamic>.from(payload));
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// A device whose MASTER is off but whose segments are individually enabled —
/// exactly what WLED's /json/state returns in that condition, and the shape
/// that was being misread as "sync commands carry on:false".
const _masterOffState = <String, dynamic>{
  'on': false,
  'bri': 128,
  'seg': [
    {'id': 0, 'on': true, 'fx': 12, 'col': [[255, 0, 0, 0]]},
  ],
};

const _litState = <String, dynamic>{
  'on': true,
  'bri': 200,
  'seg': [
    {'id': 0, 'on': true, 'fx': 3, 'col': [[0, 255, 0, 0]]},
  ],
};

PreSyncScene _scene({
  String groupId = 'g1',
  Map<String, dynamic> payload = _litState,
  String? label = 'Warm White',
  DateTime? capturedAt,
}) {
  return PreSyncScene(
    groupId: groupId,
    wledPayload: payload,
    activeLabel: label,
    capturedAt: capturedAt ?? DateTime.utc(2026, 7, 27, 18),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PreSyncScene JSON round-trip', () {
    test('survives toJson -> fromJson with payload and label intact', () {
      final original = _scene(payload: _masterOffState, label: 'Christmas');
      final restored = PreSyncScene.fromJson(original.toJson());

      expect(restored, isNotNull);
      expect(restored!.groupId, 'g1');
      expect(restored.activeLabel, 'Christmas');
      expect(restored.capturedAt, original.capturedAt);
      expect(restored.wledPayload['on'], isFalse);
      expect((restored.wledPayload['seg'] as List).first['fx'], 12);
    });

    test('null activeLabel round-trips as null', () {
      final restored = PreSyncScene.fromJson(_scene(label: null).toJson());
      expect(restored, isNotNull);
      expect(restored!.activeLabel, isNull);
    });

    test('malformed json reads as absent, never throws', () {
      expect(PreSyncScene.fromJson(const {}), isNull);
      expect(PreSyncScene.fromJson(const {'group_id': 'g1'}), isNull);
      expect(
        PreSyncScene.fromJson(const {
          'group_id': 'g1',
          'wled_payload': {'on': true},
          'captured_at': 'not-a-date',
        }),
        isNull,
      );
    });
  });

  group('persistence across a simulated app restart', () {
    test('snapshot written in one container is readable after a restart', () async {
      // "Session 1" — capture at sync start.
      final before = ProviderContainer();
      addTearDown(before.dispose);
      final captured = _scene(payload: _litState);
      before.read(preSyncSceneProvider.notifier).state = captured;
      await savePreSyncScene(captured);

      // "Restart" — brand-new container. The in-memory slot is empty; only
      // the persisted copy remains. This is the exact state that used to
      // force the TurnOff tier.
      final after = ProviderContainer();
      addTearDown(after.dispose);
      expect(after.read(preSyncSceneProvider), isNull,
          reason: 'in-memory slot must NOT survive a restart');

      final recovered = await loadPersistedPreSyncScene();
      expect(recovered, isNotNull);
      expect(recovered!.groupId, captured.groupId);
      expect(recovered.wledPayload['bri'], 200);
    });

    test('the recovered snapshot drives ApplyPreSyncScene, NOT TurnOff', () async {
      await savePreSyncScene(_scene());
      final recovered = await loadPersistedPreSyncScene();

      final action = resolveCurrentMemberState(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: recovered,
      );

      // THE regression guard: before persistence this resolved to TurnOff()
      // after any restart, which is what shut the master off on leave.
      expect(action, isA<ApplyPreSyncScene>());
      expect((action as ApplyPreSyncScene).scene.groupId, 'g1');
    });

    test('with NO persisted snapshot the resolver still falls to TurnOff', () async {
      final recovered = await loadPersistedPreSyncScene();
      expect(recovered, isNull);

      final action = resolveCurrentMemberState(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: recovered,
      );
      // TurnOff remains the genuine last resort — persistence makes it rare,
      // it does not remove it.
      expect(action, isA<TurnOff>());
    });
  });

  group('staleness gate still applies to a persisted snapshot', () {
    test('a snapshot older than 12h is rejected after recovery', () async {
      final now = DateTime.utc(2026, 7, 27, 18);
      await savePreSyncScene(
        _scene(capturedAt: now.subtract(const Duration(hours: 13))),
      );
      final recovered = await loadPersistedPreSyncScene();
      expect(recovered, isNotNull, reason: 'it persists; freshness is separate');

      expect(
        isPreSyncSceneFresh(
          scene: recovered,
          activeGroupId: 'g1',
          now: now,
        ),
        isFalse,
      );
    });

    test('a snapshot inside 12h survives the gate', () async {
      final now = DateTime.utc(2026, 7, 27, 18);
      await savePreSyncScene(
        _scene(capturedAt: now.subtract(const Duration(hours: 11))),
      );
      final recovered = await loadPersistedPreSyncScene();

      expect(
        isPreSyncSceneFresh(scene: recovered, activeGroupId: 'g1', now: now),
        isTrue,
      );
    });

    test('a persisted snapshot from another group is rejected', () async {
      final now = DateTime.utc(2026, 7, 27, 18);
      await savePreSyncScene(_scene(groupId: 'group-A', capturedAt: now));
      final recovered = await loadPersistedPreSyncScene();

      expect(
        isPreSyncSceneFresh(
          scene: recovered,
          activeGroupId: 'group-B',
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('clearing after a consumed teardown', () {
    test('clearPersistedPreSyncScene removes it from disk', () async {
      await savePreSyncScene(_scene());
      expect(await loadPersistedPreSyncScene(), isNotNull);

      await clearPersistedPreSyncScene();
      expect(await loadPersistedPreSyncScene(), isNull);
    });

    test('executeMemberTeardown clears the persisted copy after restoring', () async {
      await savePreSyncScene(_scene());
      final applied = <Map<String, dynamic>>[];

      await executeMemberTeardown(
        activeSchedule: null,
        activeAutopilot: null,
        preSyncScene: await loadPersistedPreSyncScene(),
        activeGroupId: 'g1',
        now: DateTime.utc(2026, 7, 27, 18),
        repo: _RecordingRepo(applied),
        restorePresetLabel: (_) {},
        clearPreSyncScene: () async {
          await clearPersistedPreSyncScene();
        },
        participating: null,
      );

      expect(applied, hasLength(1));
      expect(applied.first['bri'], 200, reason: 'restored the captured scene');
      // A later unrelated leave must not replay this consumed scene.
      expect(await loadPersistedPreSyncScene(), isNull);
    });
  });
}
