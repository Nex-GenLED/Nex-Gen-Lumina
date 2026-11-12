// +126 (e) — a sync requested while another is verifying is QUEUED, not
// dropped.
//
// The in-flight lock (SchedulesNotifier._syncInFlight) exists so a second cfg
// write never goes into the controller's post-commit stall. Until build 126
// the branch behind it returned the interim "verifying" result and DROPPED the
// request. Classic Christmas audit (2026-11-11): a customer toggled a schedule
// OFF and then ON four seconds later; the clearing sync held the lock for about
// eleven seconds, the ON edit's sync was dropped, and the controller was left
// with no timers and no slot 10 while the app showed the schedule as enabled.
//
// Now the branch records that a sync is owed and the in-flight sync's `finally`
// fires exactly ONE debounced follow-up with the notifier's state as it stands
// then. These tests hold the first sync open with a Completer and count what
// the fake service sees.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Holds the FIRST syncAll open until [release] completes; every later call
/// returns at once. Records the schedule list each call saw.
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

class _FakeUser implements User {
  @override
  String get uid => 'u1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Persists nothing; the notifier's optimistic state is the state under test.
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

void main() {
  ({
    ProviderContainer container,
    StreamController<List<ScheduleItem>> stream,
    _HeldSyncService service,
  }) harness() {
    final stream = StreamController<List<ScheduleItem>>();
    final service = _HeldSyncService();
    final container = ProviderContainer(overrides: [
      userSchedulesStreamProvider.overrideWith((ref) => stream.stream),
      scheduleSyncServiceProvider.overrideWithValue(service),
      wledRepositoryProvider.overrideWithValue(null),
      effectiveUserUidProvider.overrideWithValue('u1'),
      authStateProvider.overrideWith((_) => Stream<User?>.value(_FakeUser())),
      userServiceProvider.overrideWithValue(_FakeUserService()),
    ]);
    addTearDown(() {
      container.dispose();
      stream.close();
    });
    return (container: container, stream: stream, service: service);
  }

  test('a request during an in-flight sync is queued and runs EXACTLY once '
      'after the lock clears', () async {
    final h = harness();
    final notifier = h.container.read(schedulesProvider.notifier);
    h.stream.add([_christmas()]);
    await pumpEventQueue();

    // Sync #1: held open by the Completer (the controller "verifying").
    final first = notifier.runSyncNow();
    await pumpEventQueue();
    expect(h.service.calls, hasLength(1));
    expect(notifier.debugSyncInFlight, isTrue);

    // Two more requests land while it holds the lock.
    final second = await notifier.runSyncNow();
    final third = await notifier.runSyncNow();
    expect(second.queuedBehindInFlight, isTrue);
    expect(third.queuedBehindInFlight, isTrue);
    expect(second.verifying, isFalse, reason: 'queued is its own state');
    expect(second.success, isFalse, reason: 'nothing was written by it');
    expect(notifier.debugSyncOwedAfterInFlight, isTrue);
    expect(h.service.calls, hasLength(1),
        reason: 'no second cfg write into the stall');

    // Release sync #1.
    h.service.release.complete();
    await first;
    expect(notifier.debugSyncOwedAfterInFlight, isFalse,
        reason: 'the owed flag is consumed by the finally');
    await Future<void>.delayed(_debounce);
    expect(h.service.calls, hasLength(2),
        reason: 'ONE follow-up for however many requests were queued');

    // And nothing further.
    await Future<void>.delayed(_debounce);
    expect(h.service.calls, hasLength(2));
  });

  test('a request queued inside a batch waits for the batch to close '
      '(batch-depth interaction)', () async {
    final h = harness();
    final notifier = h.container.read(schedulesProvider.notifier);
    h.stream.add([_christmas()]);
    await pumpEventQueue();

    final first = notifier.runSyncNow(); // held
    await pumpEventQueue();
    expect(h.service.calls, hasLength(1));

    notifier.beginSyncBatch();
    final queued = await notifier.runSyncNow();
    expect(queued.queuedBehindInFlight, isTrue);

    // The lock clears while the batch is still open: the owed sync must be
    // handed to the batch, not fired past it.
    h.service.release.complete();
    await first;
    expect(notifier.debugSyncPendingAfterBatch, isTrue,
        reason: 'owed to endSyncBatch while a batch is open');
    await Future<void>.delayed(_debounce);
    expect(h.service.calls, hasLength(1),
        reason: 'nothing fires while the batch is open');

    notifier.endSyncBatch();
    await Future<void>.delayed(_debounce);
    expect(h.service.calls, hasLength(2),
        reason: 'the batch close fires the one owed sync');
  });

  test('the xySyj6 shape: toggle OFF, then ON inside the verification window '
      '— the device ends with the ON schedule armed', () async {
    final h = harness();
    final notifier = h.container.read(schedulesProvider.notifier);
    h.stream.add([_christmas()]);
    // toggle() reads the signed-in uid from the auth stream; warm it.
    await h.container.read(authStateProvider.future);
    await pumpEventQueue();

    // Toggle OFF → debounced sync #1, which then holds the lock (the clearing
    // sync that verifies through the stall for ~11 s in the field).
    await notifier.toggle('sch-xy', false);
    await Future<void>.delayed(_debounce);
    expect(h.service.calls, hasLength(1));
    expect(h.service.calls.single.single.enabled, isFalse,
        reason: 'the clearing sync saw the OFF schedule');
    expect(notifier.debugSyncInFlight, isTrue);

    // Toggle ON four seconds later, well inside the window: its sync request
    // arrives while #1 holds the lock.
    await notifier.toggle('sch-xy', true);
    await Future<void>.delayed(_debounce);
    expect(h.service.calls, hasLength(1),
        reason: 'not dropped, not run yet — queued behind #1');
    expect(notifier.debugSyncOwedAfterInFlight, isTrue);

    // #1 resolves; the follow-up runs with the CURRENT state (ON).
    h.service.release.complete();
    await Future<void>.delayed(_debounce);
    expect(h.service.calls, hasLength(2));
    expect(h.service.calls.last.single.enabled, isTrue,
        reason: 'the follow-up pushes the ON schedule — the controller is '
            'not left with the clearing write as its last word');
  });

  group('ScheduleSyncResult.queued', () {
    test('is neutral: not success, not verifying, not alarming', () {
      final r = ScheduleSyncResult.queued();
      expect(r.queuedBehindInFlight, isTrue);
      expect(r.success, isFalse);
      expect(r.verifying, isFalse);
      final msg = r.summaryMessage.toLowerCase();
      for (final alarming in ['fail', 'error', 'exception', 'dropped']) {
        expect(msg, isNot(contains(alarming)));
      }
      expect(msg, contains('automatically'));
    });
  });
}
