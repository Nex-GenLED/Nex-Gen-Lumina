// Build 127 — drift detection: the LAN launch's timer read against the
// enabled schedules.
//
//   • pure: which schedules are judged, what counts as drifted, which reads
//     are usable (36 h, not older than the last sync);
//   • the healer hands its timer rows to the drift read;
//   • the notifier: a read missing an enabled schedule's ON row records the
//     `drifted` status (owed), and the bounded automatic re-sync gets one
//     attempt under its window; a matching read changes nothing; a stale read
//     is ignored; a read that landed before the schedules is compared once
//     they hydrate.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_drift.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/schedule_sync_status.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

// ─── Fixtures ──────────────────────────────────────────────────────────────

Map<String, dynamic> _row(int hour, int min, int macro, int dow,
        {int en = 1}) =>
    {
      'en': en,
      'hour': hour,
      'min': min,
      'macro': macro,
      'dow': dow,
      'start': {'mon': 1, 'day': 1},
      'end': {'mon': 12, 'day': 31},
    };

/// Monday 5:00 PM → 7:00 AM, a catalog pattern: ON row macro 10 dow 1.
ScheduleItem _christmas({bool enabled = true}) => ScheduleItem(
      id: 's1',
      timeLabel: '5:00 PM',
      offTimeLabel: '7:00 AM',
      repeatDays: const ['Mon'],
      actionLabel: 'Pattern: Classic Christmas 2',
      enabled: enabled,
      wledPayload: const {'on': true},
    );

ScheduleItem _turnOff() => const ScheduleItem(
      id: 's2',
      timeLabel: '11:00 PM',
      repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      actionLabel: 'Turn Off',
      enabled: true,
    );

ScheduleItem _sunset() => const ScheduleItem(
      id: 's3',
      timeLabel: 'Sunset',
      offTimeLabel: '11:00 PM',
      repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      actionLabel: 'Pattern: evening',
      enabled: true,
      wledPayload: {'on': true},
    );

final _tenAm = DateTime(2026, 11, 16, 10, 0); // Monday 10:00

// ─── Notifier harness (the +126 re-sync harness, with a drift read) ───────

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

ScheduleSyncResult _ok(List<ScheduleItem> s) =>
    ScheduleSyncResult(success: true, schedulesWithPresets: s);
ScheduleSyncResult _failed(List<ScheduleItem> s) => ScheduleSyncResult(
    success: false, error: kScheduleCfgWriteFailed, schedulesWithPresets: s);

({
  ProviderContainer container,
  StreamController<List<ScheduleItem>> stream,
  _ScriptedSyncService service,
  _RecordingMirror mirror,
}) _harness({
  required List<ScheduleSyncResult Function(List<ScheduleItem>)> script,
}) {
  final stream = StreamController<List<ScheduleItem>>();
  final service = _ScriptedSyncService(script);
  final mirror = _RecordingMirror();
  final container = ProviderContainer(overrides: [
    userSchedulesStreamProvider.overrideWith((ref) => stream.stream),
    scheduleSyncServiceProvider.overrideWithValue(service),
    wledRepositoryProvider.overrideWithValue(RecordingWledRepository()),
    wledStateProvider.overrideWith(() =>
        SeededWledNotifier(kHomeLitState.copyWith(isOn: false, connected: true))),
    effectiveUserUidProvider.overrideWithValue('u1'),
    authStateProvider.overrideWith((_) => Stream<User?>.value(_FakeUser())),
    userServiceProvider.overrideWithValue(_FakeUserService()),
    scheduleSyncMirrorProvider.overrideWithValue(mirror),
  ]);
  addTearDown(() {
    container.dispose();
    stream.close();
  });
  return (container: container, stream: stream, service: service, mirror: mirror);
}

Future<SchedulesNotifier> _hydrated(
  ProviderContainer c,
  StreamController<List<ScheduleItem>> stream, {
  List<ScheduleItem>? schedules,
}) async {
  final n = c.read(schedulesProvider.notifier);
  n.autoResyncClock = () => _tenAm;
  stream.add(schedules ?? [_christmas()]);
  await pumpEventQueue();
  return n;
}

DeviceTimerRead _read(List<Map<String, dynamic>> rows, {DateTime? at}) =>
    DeviceTimerRead(rows: rows, at: at ?? _tenAm.subtract(const Duration(minutes: 1)));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('driftedSchedules (pure)', () {
    test('the ON row present at the time, days and role → not drifted', () {
      expect(
          driftedSchedules(
              schedules: [_christmas()], rows: [_row(17, 0, 10, 1)]),
          isEmpty);
    });

    test('row missing, wrong time, wrong days, wrong role, or disabled → '
        'drifted', () {
      for (final (label, rows) in [
        ('missing', <Map<String, dynamic>>[]),
        ('wrong time', [_row(18, 0, 10, 1)]),
        ('wrong days', [_row(17, 0, 10, 127)]),
        ('a lease row at its time', [_row(17, 0, 30, 1)]),
        ('a system row at its time', [_row(17, 0, 1, 1)]),
        ('disabled', [_row(17, 0, 10, 1, en: 0)]),
      ]) {
        expect(driftedSchedules(schedules: [_christmas()], rows: rows),
            hasLength(1),
            reason: label);
      }
    });

    test('a Turn Off schedule is judged against a system_off row', () {
      expect(
          driftedSchedules(schedules: [_turnOff()], rows: [_row(23, 0, 2, 127)]),
          isEmpty);
      expect(driftedSchedules(schedules: [_turnOff()], rows: const []),
          hasLength(1));
    });

    test('disabled schedules and sunrise/sunset ON schedules are not judged',
        () {
      expect(driftJudges(_christmas(enabled: false)), isFalse);
      expect(driftJudges(_sunset()), isFalse);
      expect(driftJudges(_christmas()), isTrue);
      expect(driftedSchedules(
              schedules: [_christmas(enabled: false), _sunset()], rows: const []),
          isEmpty);
    });
  });

  group('driftReadUsable (pure)', () {
    final at = _tenAm.subtract(const Duration(hours: 1));
    test('fresh and newer than the last sync', () {
      expect(driftReadUsable(_read(const [], at: at), now: _tenAm), isTrue);
      expect(
          driftReadUsable(_read(const [], at: at),
              now: _tenAm, lastSyncAt: at.subtract(const Duration(hours: 5))),
          isTrue);
    });

    test('older than 36 hours → not usable', () {
      final old = _tenAm.subtract(const Duration(hours: 36, minutes: 1));
      expect(driftReadUsable(_read(const [], at: old), now: _tenAm), isFalse);
      final edge = _tenAm.subtract(const Duration(hours: 35, minutes: 59));
      expect(driftReadUsable(_read(const [], at: edge), now: _tenAm), isTrue);
      expect(kDriftReadMaxAge, const Duration(hours: 36));
    });

    test('older than the last sync → not usable (the sync rewrote the table)',
        () {
      expect(
          driftReadUsable(_read(const [], at: at),
              now: _tenAm, lastSyncAt: at.add(const Duration(minutes: 1))),
          isFalse);
      expect(driftReadUsable(_read(const [], at: at), now: _tenAm, lastSyncAt: at),
          isFalse);
    });
  });

  group('the healer hands its timer rows to drift detection', () {
    test('a LAN read with rows calls back once with those rows', () async {
      final rows = [_row(17, 0, 10, 1), _row(7, 0, 2, 2)];
      final repo = RecordingWledRepository(
        clockInfo: ControllerClockInfo(
          latitude: 38.99,
          longitude: -94.25,
          timerRows: rows,
        ),
      );
      List<Map<String, dynamic>>? got;
      var calls = 0;
      final healer = ControllerDefaultsHealer(
        repo: repo,
        isLan: true,
        controllerIp: '192.0.2.10',
        ctx: ControllerHealContext(
          profileLat: null,
          profileLon: null,
          ianaTimezone: null,
          resolvePhonePosition: () async => null,
          now: () => _tenAm,
          phoneUtcOffset: _tenAm.timeZoneOffset,
        ),
        gammaAction: (ip) async => WledConfigPushResult.skipped('test'),
        onTimerRowsRead: (r) {
          calls++;
          got = r;
        },
      );
      await healer.run();
      expect(calls, 1);
      expect(got, rows);
    });

    test('an unreadable table (relay, failed read) calls nothing', () async {
      final repo = RecordingWledRepository(
        clockInfo: const ControllerClockInfo(latitude: 38.99, longitude: -94.25),
      );
      var calls = 0;
      final healer = ControllerDefaultsHealer(
        repo: repo,
        isLan: true,
        controllerIp: '192.0.2.10',
        ctx: ControllerHealContext(
          profileLat: null,
          profileLon: null,
          ianaTimezone: null,
          resolvePhonePosition: () async => null,
          now: () => _tenAm,
          phoneUtcOffset: _tenAm.timeZoneOffset,
        ),
        gammaAction: (ip) async => WledConfigPushResult.skipped('test'),
        onTimerRowsRead: (_) => calls++,
      );
      await healer.run();
      expect(calls, 0);
    });
  });

  group('the notifier', () {
    test('a read missing the ON row → drifted status, owed, one automatic '
        're-sync inside the window, then synced', () async {
      final h = _harness(script: [_ok]);
      final n = await _hydrated(h.container, h.stream);
      expect(h.service.calls, isEmpty);

      h.container.read(deviceTimerReadProvider.notifier).state =
          _read([_row(7, 0, 2, 2)]); // the OFF row only: the ON is gone
      await pumpEventQueue();

      expect(n.lastDriftedSchedules.map((s) => s.id), ['s1']);
      expect(h.mirror.writes.first.state, ScheduleSyncState.drifted);
      expect(h.mirror.writes.first.scheduleCount, 1);
      expect(h.mirror.writes.first.message, contains('Classic Christmas 2'));
      expect(n.lastAutoResyncVerdict, AutoResyncVerdict.run);
      expect(h.service.calls, hasLength(1), reason: 'the drift re-sync ran');
      expect(h.container.read(scheduleSyncStatusProvider)?.state,
          ScheduleSyncState.synced,
          reason: 'the re-sync converged');
      expect(n.debugResyncOwed, isFalse);
    });

    test('the drifted status persists when the re-sync fails, with Retry',
        () async {
      final h = _harness(script: [_failed]);
      final n = await _hydrated(h.container, h.stream);
      h.container.read(deviceTimerReadProvider.notifier).state =
          _read(const []);
      await pumpEventQueue();
      expect(h.mirror.writes.map((w) => w.state).toList(),
          [ScheduleSyncState.drifted, ScheduleSyncState.failed]);
      expect(n.debugResyncOwed, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(scheduleSyncOwedKey('u1')), isTrue);
    });

    test('outside the window the drifted status is recorded and the re-sync '
        'is held', () async {
      final h = _harness(script: [_ok]);
      final n = await _hydrated(h.container, h.stream);
      n.autoResyncClock = () => DateTime(2026, 11, 16, 20, 0);
      h.container.read(deviceTimerReadProvider.notifier).state =
          _read(const [], at: DateTime(2026, 11, 16, 19, 59));
      await pumpEventQueue();
      expect(h.container.read(scheduleSyncStatusProvider)?.state,
          ScheduleSyncState.drifted);
      expect(n.lastAutoResyncVerdict, AutoResyncVerdict.outsideDaytime);
      expect(h.service.calls, isEmpty);
      expect(n.debugResyncOwed, isTrue);
    });

    test('a read that matches changes nothing', () async {
      final h = _harness(script: [_ok]);
      final n = await _hydrated(h.container, h.stream);
      h.container.read(deviceTimerReadProvider.notifier).state =
          _read([_row(17, 0, 10, 1), _row(7, 0, 2, 2)]);
      await pumpEventQueue();
      expect(n.lastDriftedSchedules, isEmpty);
      expect(h.mirror.writes, isEmpty);
      expect(h.service.calls, isEmpty);
      expect(h.container.read(scheduleSyncStatusProvider), isNull);
    });

    test('a read older than 36 hours is ignored', () async {
      final h = _harness(script: [_ok]);
      final n = await _hydrated(h.container, h.stream);
      h.container.read(deviceTimerReadProvider.notifier).state =
          _read(const [], at: _tenAm.subtract(const Duration(hours: 40)));
      await pumpEventQueue();
      expect(n.lastDriftedSchedules, isEmpty);
      expect(h.mirror.writes, isEmpty);
      expect(h.service.calls, isEmpty);
    });

    test('a read that landed before the schedules is compared once they '
        'hydrate', () async {
      final h = _harness(script: [_ok]);
      h.container.read(schedulesProvider.notifier).autoResyncClock =
          () => _tenAm;
      h.container.read(deviceTimerReadProvider.notifier).state =
          _read(const []);
      await pumpEventQueue();
      expect(h.mirror.writes, isEmpty, reason: 'nothing to compare yet');

      final n = await _hydrated(h.container, h.stream);
      expect(n.lastDriftedSchedules.map((s) => s.id), ['s1']);
      expect(h.mirror.writes.first.state, ScheduleSyncState.drifted);
      expect(h.service.calls, hasLength(1));
    });
  });
}
