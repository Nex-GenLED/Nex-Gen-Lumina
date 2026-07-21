// Empty-read guard — THE "schedules consistently don't fire" P0.
//
// syncAll builds the timers.ins payload from the notifier's in-memory `state`.
// Before the schedule stream's first Firestore emission, `state` is the empty
// initial value. The old path pushed that: 8 disabled stubs over the device's
// real timers, WLED returns 200, and it was marked SUCCESS — a silent no-op
// that left the controller showing only its native sunrise/sunset stubs.
//
// The fix gates the push on HYDRATION (the `_initialized` loaded-flag), NOT on
// `state.isEmpty`, and DEFERS an un-hydrated push, re-running it once the stream
// loads. The three cases the guard must tell apart:
//   • not yet hydrated            → DEFER (no write, not success)
//   • hydrated, real schedules    → push them
//   • hydrated, genuinely zero    → push empty stubs (clears device — correct)

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

/// A ScheduleSyncService that records the schedule list each syncAll was
/// invoked with instead of touching a device. If syncAll is called at all, the
/// list it saw is captured — so an empty-read push is observable.
class _RecordingSyncService extends ScheduleSyncService {
  _RecordingSyncService(this.calls) : super();
  final List<List<ScheduleItem>> calls;

  @override
  Future<ScheduleSyncResult> syncAll(Ref ref, List<ScheduleItem> schedules) async {
    calls.add(List.of(schedules));
    return ScheduleSyncResult(success: true, schedulesWithPresets: schedules);
  }
}

ScheduleItem _tenForty() => const ScheduleItem(
      id: 's1040',
      timeLabel: '10:40 AM',
      repeatDays: ['Mon'],
      actionLabel: 'Turn On',
      enabled: true,
    );

void main() {
  ({
    ProviderContainer container,
    StreamController<List<ScheduleItem>> stream,
    List<List<ScheduleItem>> calls,
  }) harness() {
    final stream = StreamController<List<ScheduleItem>>();
    final calls = <List<ScheduleItem>>[];
    final container = ProviderContainer(overrides: [
      userSchedulesStreamProvider.overrideWith((ref) => stream.stream),
      scheduleSyncServiceProvider
          .overrideWithValue(_RecordingSyncService(calls)),
      wledRepositoryProvider.overrideWithValue(null),
      effectiveUserUidProvider.overrideWithValue('u1'),
    ]);
    addTearDown(() {
      container.dispose();
      stream.close();
    });
    return (container: container, stream: stream, calls: calls);
  }

  test('push BEFORE hydration defers — no empty-stub push, not success',
      () async {
    final h = harness();
    final notifier = h.container.read(schedulesProvider.notifier);

    final result = await notifier.runSyncNow();

    expect(result.deferredNotLoaded, isTrue);
    expect(result.success, isFalse,
        reason: 'nothing was written — success must not lie');
    expect(h.calls, isEmpty,
        reason: 'syncAll must NOT run against the unhydrated empty state');
  });

  test('deferred push RUNS after hydration, with the loaded real timers',
      () async {
    final h = harness();
    final notifier = h.container.read(schedulesProvider.notifier);

    // Requested before load → deferred.
    final deferred = await notifier.runSyncNow();
    expect(deferred.deferredNotLoaded, isTrue);
    expect(h.calls, isEmpty);

    // Stream hydrates with the real schedule.
    h.stream.add([_tenForty()]);
    await pumpEventQueue();
    // The deferred re-run is armed via the 800ms debounce.
    await Future<void>.delayed(const Duration(milliseconds: 900));

    expect(h.calls, isNotEmpty, reason: 'deferred sync must run once loaded');
    expect(h.calls.last.map((s) => s.id), contains('s1040'),
        reason: 'it arms the real schedule, not empty stubs');
  });

  test('push AFTER hydration with real schedules pushes them', () async {
    final h = harness();
    final notifier = h.container.read(schedulesProvider.notifier);

    h.stream.add([_tenForty()]);
    await pumpEventQueue();

    final result = await notifier.runSyncNow();

    expect(result.success, isTrue);
    expect(h.calls, hasLength(1));
    expect(h.calls.single.map((s) => s.id), ['s1040']);
  });

  test('push AFTER hydration with genuinely ZERO schedules still pushes '
      '(clears the device — correct)', () async {
    final h = harness();
    final notifier = h.container.read(schedulesProvider.notifier);

    // Hydrated, but the user really has no schedules.
    h.stream.add(<ScheduleItem>[]);
    await pumpEventQueue();

    final result = await notifier.runSyncNow();

    expect(result.deferredNotLoaded, isFalse,
        reason: 'hydrated-empty is NOT the same as unhydrated');
    expect(h.calls, hasLength(1),
        reason: 'a real zero-schedule push must reach syncAll to clear timers');
    expect(h.calls.single, isEmpty);
  });

  test('the 10:40 schedule builds a real hour:10 min:40 clock timer', () {
    final built = const ScheduleSyncService().buildCfgPayload([_tenForty()]);
    final ins = ((built['timers'] as Map)['ins'] as List)
        .cast<Map<String, dynamic>>();

    expect(
      ins.any((t) => t['hour'] == 10 && t['min'] == 40 && t['en'] == true),
      isTrue,
      reason: 'the translation itself was never the bug — proves it still works',
    );
  });

  group('ScheduleSyncResult.notLoaded', () {
    test('is a neutral deferral: not success, not an alarming error', () {
      final r = ScheduleSyncResult.notLoaded();
      expect(r.deferredNotLoaded, isTrue);
      expect(r.success, isFalse);
      final msg = r.summaryMessage.toLowerCase();
      for (final alarming in ['fail', 'error', 'exception']) {
        expect(msg, isNot(contains(alarming)));
      }
    });
  });
}
