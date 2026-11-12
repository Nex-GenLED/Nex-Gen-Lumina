// +126 (a) — the owed re-sync flag and the bounded automatic re-sync, on the
// real SchedulesNotifier with a fake sync service.
//
//   • the flag is set by a deferred / failed / unconverged outcome, persisted
//     per account, and survives a restart (a second container over the same
//     SharedPreferences);
//   • a launch or a LAN return with the flag set runs ONE automatic sync,
//     under the bounds (lights off, daytime, ten minutes apart, six a day);
//   • a verified converged sync clears it; the Firestore mirror is non-fatal.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/schedule_sync_status.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

/// A store whose owed-flag read parks until the test releases [gate]: the
/// launch trigger's first await, held open so the container can be torn
/// down underneath it.
class _HeldStore extends ScheduleSyncStatusStore {
  _HeldStore() : super();
  final gate = Completer<void>();

  @override
  Future<bool> readOwed(String uid) async {
    await gate.future;
    return true;
  }
}

/// Returns the scripted results in order; the last one repeats.
class _ScriptedSyncService extends ScheduleSyncService {
  _ScriptedSyncService(this.script) : super();
  final List<ScheduleSyncResult Function(List<ScheduleItem>)> script;
  final List<List<ScheduleItem>> calls = [];

  @override
  Future<ScheduleSyncResult> syncAll(
      Ref ref, List<ScheduleItem> schedules) async {
    calls.add(List.of(schedules));
    final i = (calls.length - 1).clamp(0, script.length - 1);
    return script[i](schedules);
  }
}

class _RecordingMirror implements ScheduleSyncMirror {
  final List<ScheduleSyncStatus> writes = [];
  @override
  Future<void> write(String uid, ScheduleSyncStatus status) async {
    writes.add(status);
  }
}

class _RejectingMirror implements ScheduleSyncMirror {
  int attempts = 0;
  @override
  Future<void> write(String uid, ScheduleSyncStatus status) async {
    attempts++;
    throw StateError('permission-denied');
  }
}

class _FakeUser implements User {
  @override
  String get uid => 'u1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserService implements UserService {
  @override
  Future<void> updateSchedule(String userId, ScheduleItem schedule) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ScheduleItem _item() => const ScheduleItem(
      id: 's1',
      timeLabel: '5:00 PM',
      offTimeLabel: '7:00 AM',
      repeatDays: ['Mon'],
      actionLabel: 'Pattern: Classic Christmas 2',
      enabled: true,
      wledPayload: {'on': true},
    );

ScheduleSyncResult _ok(List<ScheduleItem> s) =>
    ScheduleSyncResult(success: true, schedulesWithPresets: s);
ScheduleSyncResult _offLan(List<ScheduleItem> s) =>
    ScheduleSyncResult.deferredOffLan(schedulesWithPresets: s);
ScheduleSyncResult _failed(List<ScheduleItem> s) => ScheduleSyncResult(
    success: false, error: kScheduleCfgWriteFailed, schedulesWithPresets: s);
ScheduleSyncResult _unconverged(List<ScheduleItem> s) => ScheduleSyncResult(
      success: true,
      schedulesWithPresets: s,
      presetErrors: const ['Failed to save preset 10 (Pattern: X)'],
      unconvergedPresetIds: const [10],
    );

/// The controller the LAN-return tests switch to.
final _repoSwitch = StateProvider<WledRepository?>((_) => null);

final _tenAm = DateTime(2026, 11, 12, 10, 0);

({
  ProviderContainer container,
  StreamController<List<ScheduleItem>> stream,
  _ScriptedSyncService service,
  _RecordingMirror mirror,
}) harness({
  required List<ScheduleSyncResult Function(List<ScheduleItem>)> script,
  WledRepository? repo,
  bool lightsOn = false,
  ScheduleSyncMirror? mirror,
  ScheduleSyncStatusStore? store,
}) {
  final stream = StreamController<List<ScheduleItem>>();
  final service = _ScriptedSyncService(script);
  final rec = _RecordingMirror();
  final container = ProviderContainer(overrides: [
    userSchedulesStreamProvider.overrideWith((ref) => stream.stream),
    scheduleSyncServiceProvider.overrideWithValue(service),
    wledRepositoryProvider.overrideWith((ref) => ref.watch(_repoSwitch)),
    _repoSwitch.overrideWith((_) => repo),
    wledStateProvider.overrideWith(() => SeededWledNotifier(
        kHomeLitState.copyWith(isOn: lightsOn, connected: true))),
    effectiveUserUidProvider.overrideWithValue('u1'),
    authStateProvider.overrideWith((_) => Stream<User?>.value(_FakeUser())),
    userServiceProvider.overrideWithValue(_FakeUserService()),
    scheduleSyncMirrorProvider.overrideWithValue(mirror ?? rec),
    if (store != null) scheduleSyncStatusStoreProvider.overrideWithValue(store),
  ]);
  addTearDown(() {
    container.dispose();
    stream.close();
  });
  return (container: container, stream: stream, service: service, mirror: rec);
}

Future<SchedulesNotifier> _hydrated(
  ProviderContainer c,
  StreamController<List<ScheduleItem>> stream, {
  DateTime? clock,
}) async {
  final n = c.read(schedulesProvider.notifier);
  n.autoResyncClock = () => clock ?? _tenAm;
  stream.add([_item()]);
  await pumpEventQueue();
  return n;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the owed flag', () {
    test('is set by an off-LAN deferral, a failure and an unconverged write; '
        'cleared only by a clean sync; persisted per account', () async {
      for (final (label, result, state) in [
        ('off-LAN', _offLan, ScheduleSyncState.deferredOffLan),
        ('failed', _failed, ScheduleSyncState.failed),
        ('unconverged', _unconverged, ScheduleSyncState.writtenNotVerified),
      ]) {
        SharedPreferences.setMockInitialValues({});
        final h = harness(script: [result, _ok]);
        final n = await _hydrated(h.container, h.stream);

        await n.runSyncNow();
        expect(n.debugResyncOwed, isTrue, reason: label);
        expect(h.container.read(scheduleSyncStatusProvider)?.state, state,
            reason: label);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(scheduleSyncOwedKey('u1')), isTrue, reason: label);
        expect(h.mirror.writes.last.state, state, reason: 'mirrored: $label');

        await n.runSyncNow();
        expect(n.debugResyncOwed, isFalse, reason: '$label → cleared');
        expect(prefs.getBool(scheduleSyncOwedKey('u1')), isFalse);
        expect(h.container.read(scheduleSyncStatusProvider)?.state,
            ScheduleSyncState.synced);
      }
    });

    test('survives a restart: a new container over the same prefs sees it, '
        'and the launch trigger runs ONE automatic sync on the LAN',
        () async {
      // Session 1: off the home Wi-Fi, the edit's sync is deferred.
      final s1 = harness(script: [_offLan]);
      final n1 = await _hydrated(s1.container, s1.stream);
      await n1.runSyncNow();
      expect(n1.debugResyncOwed, isTrue);
      expect(s1.service.calls, hasLength(1));
      s1.container.dispose();

      // Session 2: at home, lights off, 10:00 — hydration is the launch.
      final s2 = harness(script: [_ok], repo: RecordingWledRepository());
      final n2 = await _hydrated(s2.container, s2.stream);
      await pumpEventQueue();
      expect(n2.lastAutoResyncVerdict, AutoResyncVerdict.run);
      expect(s2.service.calls, hasLength(1),
          reason: 'the owed sync ran by itself on launch');
      expect(n2.debugResyncOwed, isFalse, reason: 'converged → cleared');
      expect(s2.container.read(scheduleSyncStatusProvider)?.state,
          ScheduleSyncState.synced);
    });

    test('the launch trigger survives its container being disposed '
        'mid-flight (schedule_addall_test\'s shape): no read after dispose, '
        'no sync', () async {
      final store = _HeldStore();
      final h = harness(
          script: [_ok], repo: RecordingWledRepository(), store: store);
      final n = await _hydrated(h.container, h.stream);
      expect(n.lastAutoResyncVerdict, isNull,
          reason: 'parked on the owed-flag read');
      // Torn down while the launch trigger waits on its first await —
      // exactly what a short-lived test container or a signed-out
      // teardown does. Before the guard this threw "Tried to read a
      // provider from a ProviderContainer that was already disposed".
      h.container.dispose();
      store.gate.complete();
      await pumpEventQueue();
      expect(h.service.calls, isEmpty, reason: 'nothing ran on a dead ref');
    });

    test('a restart with nothing owed runs nothing', () async {
      final h = harness(script: [_ok], repo: RecordingWledRepository());
      final n = await _hydrated(h.container, h.stream);
      await pumpEventQueue();
      expect(n.lastAutoResyncVerdict, AutoResyncVerdict.nothingOwed);
      expect(h.service.calls, isEmpty);
    });
  });

  group('LAN return', () {
    test('off-LAN → LAN with the flag set runs one automatic sync', () async {
      final h = harness(script: [_offLan, _ok]);
      final n = await _hydrated(h.container, h.stream);
      await n.runSyncNow(); // deferred, owed
      expect(h.service.calls, hasLength(1));

      h.container.read(_repoSwitch.notifier).state = RecordingWledRepository();
      await pumpEventQueue();
      expect(n.lastAutoResyncVerdict, AutoResyncVerdict.run);
      expect(h.service.calls, hasLength(2));
      expect(n.debugResyncOwed, isFalse);
    });

    test('one attempt per LAN-return event, and at least ten minutes apart',
        () async {
      final h = harness(script: [_offLan, _failed, _ok]);
      final n = await _hydrated(h.container, h.stream);
      await n.runSyncNow();

      // Return 1 at 10:00: runs, and fails again (still owed).
      h.container.read(_repoSwitch.notifier).state = RecordingWledRepository();
      await pumpEventQueue();
      expect(h.service.calls, hasLength(2));
      expect(n.debugResyncOwed, isTrue);

      // Flap: away and back at 10:05 — too soon.
      h.container.read(_repoSwitch.notifier).state = null;
      await pumpEventQueue();
      n.autoResyncClock = () => _tenAm.add(const Duration(minutes: 5));
      h.container.read(_repoSwitch.notifier).state = RecordingWledRepository();
      await pumpEventQueue();
      expect(n.lastAutoResyncVerdict, AutoResyncVerdict.tooSoon);
      expect(h.service.calls, hasLength(2));

      // Back again at 10:11 — allowed.
      h.container.read(_repoSwitch.notifier).state = null;
      await pumpEventQueue();
      n.autoResyncClock = () => _tenAm.add(const Duration(minutes: 11));
      h.container.read(_repoSwitch.notifier).state = RecordingWledRepository();
      await pumpEventQueue();
      expect(n.lastAutoResyncVerdict, AutoResyncVerdict.run);
      expect(h.service.calls, hasLength(3));
    });

    test('at most six automatic attempts a day; the seventh is held', () async {
      final h = harness(script: [_offLan, _failed]);
      final n = await _hydrated(h.container, h.stream);
      await n.runSyncNow();
      var t = _tenAm;
      for (var i = 0; i < 6; i++) {
        n.autoResyncClock = () => t;
        h.container.read(_repoSwitch.notifier).state = RecordingWledRepository();
        await pumpEventQueue();
        expect(n.lastAutoResyncVerdict, AutoResyncVerdict.run,
            reason: 'attempt ${i + 1}');
        h.container.read(_repoSwitch.notifier).state = null;
        await pumpEventQueue();
        t = t.add(const Duration(minutes: 30));
      }
      expect(h.service.calls, hasLength(7)); // the manual one + six
      n.autoResyncClock = () => t;
      h.container.read(_repoSwitch.notifier).state = RecordingWledRepository();
      await pumpEventQueue();
      expect(n.lastAutoResyncVerdict, AutoResyncVerdict.dailyCapReached);
      expect(h.service.calls, hasLength(7));

      // A manual Retry is always allowed.
      await n.runSyncNow();
      expect(h.service.calls, hasLength(8));
    });

    test('held while the lights are on (a psave would be visible)', () async {
      final h = harness(script: [_offLan, _ok], lightsOn: true);
      final n = await _hydrated(h.container, h.stream);
      await n.runSyncNow();
      h.container.read(_repoSwitch.notifier).state = RecordingWledRepository();
      await pumpEventQueue();
      expect(n.lastAutoResyncVerdict, AutoResyncVerdict.lightsOn);
      expect(h.service.calls, hasLength(1));
      expect(n.debugResyncOwed, isTrue, reason: 'still owed');
    });

    test('held outside daytime (8:00–17:00 local)', () async {
      final h = harness(script: [_offLan, _ok]);
      final n = await _hydrated(h.container, h.stream,
          clock: DateTime(2026, 11, 12, 21, 15));
      await n.runSyncNow();
      h.container.read(_repoSwitch.notifier).state = RecordingWledRepository();
      await pumpEventQueue();
      expect(n.lastAutoResyncVerdict, AutoResyncVerdict.outsideDaytime);
      expect(h.service.calls, hasLength(1));
    });
  });

  group('the Firestore mirror', () {
    test('a rejected mirror write never reaches the sync\'s caller', () async {
      final rejecting = _RejectingMirror();
      final h = harness(script: [_ok], mirror: rejecting);
      final n = await _hydrated(h.container, h.stream);
      final r = await n.runSyncNow();
      await pumpEventQueue();
      expect(r.success, isTrue);
      expect(rejecting.attempts, 1);
      expect(h.container.read(scheduleSyncStatusProvider)?.state,
          ScheduleSyncState.synced,
          reason: 'the local status is recorded regardless');
    });
  });
}
