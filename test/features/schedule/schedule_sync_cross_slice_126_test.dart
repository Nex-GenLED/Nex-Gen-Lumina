// +126 cross-slice — slices A (queue-not-drop) and B (persisted status, owed
// flag, status row and Home chip) together, on the real SchedulesNotifier
// with a held fake sync service and the two surfaces mounted.
//
// The audited shape: an account whose last sync left a re-sync OWED (the
// edit was made off the home Wi-Fi) opens the app at home in the evening,
// toggles the Christmas schedule OFF, then ON four seconds later — inside
// the first sync's verification window. End state required: the controller's
// last word is the ON schedule (armed), the persisted status is "synced",
// the owed flag is cleared, and the row and the chip show the synced line
// with no Retry.

import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/schedule_sync_status.dart';
import 'package:nexgen_command/features/schedule/widgets/schedule_sync_status_row.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

/// Holds the FIRST syncAll open until [release] completes (the controller
/// "verifying" through its post-commit stall); every later call returns a
/// clean, converged result at once. Records the schedule list each call saw.
class _HeldSyncService extends ScheduleSyncService {
  _HeldSyncService() : super();
  final List<List<ScheduleItem>> calls = [];
  final Completer<void> release = Completer<void>();

  @override
  Future<ScheduleSyncResult> syncAll(
      Ref ref, List<ScheduleItem> schedules) async {
    calls.add(List.of(schedules));
    if (calls.length == 1) await release.future;
    return ScheduleSyncResult(success: true, schedulesWithPresets: schedules);
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

ScheduleItem _christmas({bool enabled = true}) => ScheduleItem(
      id: 'sch-xy',
      timeLabel: '5:00 PM',
      offTimeLabel: '7:00 AM',
      repeatDays: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
      actionLabel: 'Pattern: Classic Christmas 2',
      enabled: enabled,
      wledPayload: const {
        'on': true,
        'bri': 255,
        'seg': [
          {'id': 0, 'fx': 84, 'pal': 5}
        ],
      },
    );

/// The 800 ms debounce plus slack.
const _debounce = Duration(milliseconds: 950);

/// 20:15 local: the lights are on, the customer is home, and the automatic
/// re-sync is outside its 9:00–15:00 window — so the owed flag stays set
/// through launch and it is the customer's own toggles that resolve it.
final _eightPm = DateTime(2026, 11, 12, 20, 15);

void main() {
  setUp(() {
    // The last session: the edit was made off the home Wi-Fi, so a re-sync
    // is owed and the persisted status says so.
    final deferred = ScheduleSyncStatus(
      state: ScheduleSyncState.deferredOffLan,
      at: _eightPm.subtract(const Duration(hours: 3)),
      scheduleCount: 1,
    );
    SharedPreferences.setMockInitialValues({
      scheduleSyncOwedKey('u1'): true,
      scheduleSyncStatusKey('u1'): jsonEncode(deferred.toJson()),
    });
  });

  testWidgets(
      'toggle OFF then ON inside the verification window, owed flag set, '
      'row and chip mounted → ON schedule armed, status synced, chip cleared',
      (tester) async {
    final stream = StreamController<List<ScheduleItem>>();
    final service = _HeldSyncService();
    final mirror = _RecordingMirror();
    final container = ProviderContainer(overrides: [
      userSchedulesStreamProvider.overrideWith((ref) => stream.stream),
      scheduleSyncServiceProvider.overrideWithValue(service),
      wledRepositoryProvider.overrideWithValue(RecordingWledRepository()),
      wledStateProvider.overrideWith(() =>
          SeededWledNotifier(kHomeLitState.copyWith(isOn: true, connected: true))),
      effectiveUserUidProvider.overrideWithValue('u1'),
      authStateProvider.overrideWith((_) => Stream<User?>.value(_FakeUser())),
      userServiceProvider.overrideWithValue(_FakeUserService()),
      scheduleSyncMirrorProvider.overrideWithValue(mirror),
    ]);
    addTearDown(() {
      container.dispose();
      stream.close();
    });

    // Both homeowner surfaces, over the SAME container as the notifier.
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: nexGenPremiumDarkTheme,
        home: const Scaffold(
          body: Column(children: [
            ScheduleSyncStatusRow(),
            ScheduleSyncHomeChip(),
          ]),
        ),
      ),
    ));
    await tester.pump();

    final notifier = container.read(schedulesProvider.notifier);
    notifier.autoResyncClock = () => _eightPm;
    // toggle() reads the signed-in uid from the auth stream; warm it.
    await container.read(authStateProvider.future);

    // Launch: the schedules load; the owed flag is read; the automatic
    // re-sync is held (evening), so nothing has been written yet.
    stream.add([_christmas()]);
    await tester.pump();
    await tester.pump();
    expect(notifier.debugResyncOwed, isTrue, reason: 'owed from last session');
    expect(notifier.lastAutoResyncVerdict, AutoResyncVerdict.outsideDaytime);
    expect(service.calls, isEmpty);

    // The row and the chip show last session's state, with Retry offered.
    final deferredCopy = ScheduleSyncCopy.forState(ScheduleSyncState.deferredOffLan);
    expect(find.byKey(const ValueKey('schedule-sync-status-row')), findsOneWidget);
    expect(find.textContaining(deferredCopy.headline), findsNWidgets(2));
    expect(find.byKey(const ValueKey('schedule-sync-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-sync-chip-retry')), findsOneWidget);

    // Toggle OFF → debounced sync #1, which then holds the lock (the
    // clearing sync that verifies through the stall for ~11 s in the field).
    await notifier.toggle('sch-xy', false);
    await tester.pump(_debounce);
    expect(service.calls, hasLength(1));
    expect(service.calls.single.single.enabled, isFalse,
        reason: 'the clearing sync saw the OFF schedule');
    expect(notifier.debugSyncInFlight, isTrue);

    // Toggle ON four seconds later, inside the window: queued behind #1
    // (slice A), and the status row says so (slice B).
    await notifier.toggle('sch-xy', true);
    await tester.pump(_debounce);
    expect(service.calls, hasLength(1), reason: 'not dropped, not run yet');
    expect(notifier.debugSyncOwedAfterInFlight, isTrue);
    expect(container.read(scheduleSyncStatusProvider)?.state,
        ScheduleSyncState.queued);
    final queuedCopy = ScheduleSyncCopy.forState(ScheduleSyncState.queued);
    expect(find.textContaining(queuedCopy.headline), findsNWidgets(2));
    expect(find.byKey(const ValueKey('schedule-sync-retry')), findsNothing,
        reason: 'no Retry while one is already running by itself');
    expect(find.byKey(const ValueKey('schedule-sync-chip-retry')), findsNothing);

    // #1 resolves; the one follow-up runs with the CURRENT state (ON).
    service.release.complete();
    await tester.pump();
    await tester.pump(_debounce);
    await tester.pump();
    expect(service.calls, hasLength(2));
    expect(service.calls.last.single.enabled, isTrue,
        reason: 'the follow-up pushes the ON schedule — the controller is '
            'not left with the clearing write as its last word');

    // End state: synced, nothing owed, persisted, mirrored, and both
    // surfaces show the synced line with no Retry.
    final status = container.read(scheduleSyncStatusProvider);
    expect(status?.state, ScheduleSyncState.synced);
    expect(notifier.debugResyncOwed, isFalse, reason: 'converged → cleared');
    expect(notifier.debugSyncOwedAfterInFlight, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(scheduleSyncOwedKey('u1')), isFalse);
    expect(mirror.writes.last.state, ScheduleSyncState.synced);

    final syncedCopy = ScheduleSyncCopy.forState(ScheduleSyncState.synced);
    expect(find.textContaining(syncedCopy.headline), findsNWidgets(2));
    expect(find.byKey(const ValueKey('schedule-sync-retry')), findsNothing);
    expect(find.byKey(const ValueKey('schedule-sync-chip-retry')), findsNothing);
    expect(find.textContaining(deferredCopy.headline), findsNothing);
    expect(find.textContaining(queuedCopy.headline), findsNothing);

    // And nothing further fires.
    await tester.pump(_debounce);
    expect(service.calls, hasLength(2));
  });
}
