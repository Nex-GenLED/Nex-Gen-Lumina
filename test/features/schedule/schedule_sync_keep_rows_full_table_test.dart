// Build 129 — the keep guard's Failed copy when the TABLE IS FULL.
//
// The build-127 keep guard (schedule_sync_keep_rows_test.dart) refuses to
// send a table that would remove an enabled schedule's row the controller
// holds. Two different things put a sync there:
//
//   1. the sync could not REBUILD the schedule (a refused design) and its
//      kept rows did not fit — kScheduleKeepRowsRefused says so, and stays;
//   2. nothing was refused: held lease rows (one-night / Game Day) plus a
//      newer schedule simply leave NO ROOM for an older schedule the
//      controller holds. The older schedule overflowed the table's eight
//      general slots. Before this build the customer read the same "couldn't
//      rebuild" text, which names nothing they can do.
//
// Case 2 is told apart at the guard: every dropped schedule passed every arm
// check (it is in `armable`) and was cut by the slot budget alone (it is not
// in the table's `armed`). That case, and no other, gets the full-table copy.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show calendarLeaseActiveTimersProvider, LeaseLedgerReady;
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/schedule_sync_status.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart'
    show controllerDefaultsHealerProvider, ControllerHealReport;
import 'package:nexgen_command/features/wled/wled_providers.dart';

import 'arm_check_harness.dart';

/// The exact customer text for the full-table case (the brief's words).
const String kExpectedFullTableCopy =
    "Your controller's timer is full right now, so nothing was changed. "
    "Remove a schedule, or wait until tonight's calendar lighting ends, then "
    'tap Retry.';

/// A faithful controller that also HOLDS a timer table for the keep guard
/// to read (the arm-check harness echoes only what it was last sent).
class _HoldingController extends FaithfulController {
  _HoldingController(List<Map<String, dynamic>> held)
      : _held = [for (final t in held) Map<String, dynamic>.from(t)];

  final List<Map<String, dynamic>> _held;

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async {
    if (lastCfg == null) {
      return [for (final t in _held) Map<String, dynamic>.from(t)];
    }
    return super.fetchTimerInstances();
  }
}

Map<String, dynamic> _row(int hour, int min, int macro, int dow) => {
      'en': 1,
      'hour': hour,
      'min': min,
      'macro': macro,
      'dow': dow,
      'start': {'mon': 1, 'day': 1},
      'end': {'mon': 12, 'day': 31},
    };

/// Six one-night rows held tonight (hours 0–5, macros 26–31, Thursday).
List<Map<String, dynamic>> _sixLeases() => [
      for (var h = 0; h < 6; h++)
        {'en': 1, 'hour': h, 'min': 0, 'macro': 26 + h, 'dow': 16},
    ];

final _refProvider = Provider<Ref>((ref) => ref);

ProviderContainer _container(
    _HoldingController repo, List<Map<String, dynamic>> leases) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    calendarLeaseActiveTimersProvider.overrideWithValue(LeaseLedgerReady(leases)),
    solarSchedulingEnabledSyncProvider.overrideWithValue(false),
    globalSunriseOffTimerProvider.overrideWithValue(sunriseOffRow()),
    controllerDefaultsHealerProvider.overrideWithValue(
        () async => ControllerHealReport()..reachable = false),
  ]);
  addTearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.dispose();
  });
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const svc = ScheduleSyncService(paceDelay: Duration.zero);

  test(
      'held lease rows + a new schedule leave no room for an older schedule the '
      'controller holds: nothing is sent, and the Failed copy says the timer is '
      'full and what to do', () async {
    // "Pattern: overnight" (5 PM on, 7 AM off) is on the controller, and its
    // design is intact — nothing about it is refused.
    final older = patternSchedule(on: '5:00 PM', off: '7:00 AM');
    // The customer just added "Pattern: evening" (7 PM on, 10 PM off).
    final newer = patternSchedule(on: '7:00 PM', off: '10:00 PM', label: 'Pattern: evening');
    final held = [_row(17, 0, 10, 127), _row(7, 0, 2, 127)];
    final repo = _HoldingController(held);
    // Six lease rows + two for the new schedule = the eight general slots.
    final c = _container(repo, _sixLeases());

    final result = await svc.syncAll(c.read(_refProvider), [newer, older]);

    expect(result.success, isFalse);
    expect(repo.timerCfgWrites, 0, reason: 'nothing was sent');
    expect(result.deferredOffLan, isFalse);
    expect(result.error, kExpectedFullTableCopy);
    expect(result.presetErrors.join('\n'), isNot(contains('has no saved design')),
        reason: 'nothing was refused — the older schedule only ran out of room');
    expect(result.presetErrors.join('\n'), contains('timer slot'),
        reason: 'the slot warning for the older schedule is still reported');
    final status = ScheduleSyncStatus.fromResult(result)!;
    expect(status.state, ScheduleSyncState.failed);
    expect(status.message, kExpectedFullTableCopy);
    expect(ScheduleSyncCopy.forState(status.state).showsRetry, isTrue);
    expect(status.owesResync, isTrue);
  });

  test('the refused-and-not-kept case keeps the build-127 copy, word for word',
      () async {
    // The 127 shape: the schedule's design is gone, so this sync refuses it,
    // and eight lease rows leave no room to keep its device rows.
    final refused = patternSchedule(on: '5:00 PM', off: '7:00 AM')
        .copyWith(clearWledPayload: true, actionLabel: 'Pattern: overnight');
    final held = [_row(17, 0, 10, 127), _row(7, 0, 2, 127)];
    final repo = _HoldingController(held);
    final eightLeases = [
      for (var h = 0; h < 8; h++)
        {'en': 1, 'hour': h, 'min': 0, 'macro': 26 + h, 'dow': 16},
    ];
    final c = _container(repo, eightLeases);

    final result = await svc.syncAll(c.read(_refProvider), [refused]);

    expect(result.success, isFalse);
    expect(repo.timerCfgWrites, 0);
    expect(result.error, kScheduleKeepRowsRefused);
    expect(
        kScheduleKeepRowsRefused,
        "Your controller still has a schedule the app couldn't rebuild this time, "
        'so nothing was changed. Tap Retry; if this keeps happening, contact '
        'support.');
    expect(result.error, isNot(kExpectedFullTableCopy));
  });

  test('a mixed sync (one refused and NOT kept, one out of room) keeps the '
      'build-127 copy — the full-table words are for the no-refusal case only',
      () async {
    final refused = patternSchedule(on: '5:00 PM', off: '7:00 AM')
        .copyWith(clearWledPayload: true, actionLabel: 'Pattern: overnight');
    final older = patternSchedule(on: '6:00 AM', off: '8:00 AM', label: 'Pattern: dawn');
    final newer = patternSchedule(on: '7:00 PM', off: '10:00 PM', label: 'Pattern: evening');
    final held = [
      _row(17, 0, 10, 127), _row(7, 0, 2, 127), // the refused one's rows
      _row(6, 0, 11, 127), _row(8, 0, 2, 127), // the older one's rows
    ];
    final repo = _HoldingController(held);
    // Eight lease rows: the refused schedule's rows cannot be kept beside
    // them, and no schedule fits either — both held schedules drop.
    final eightLeases = [
      for (var h = 0; h < 8; h++)
        {'en': 1, 'hour': h, 'min': 0, 'macro': 26 + h, 'dow': 16},
    ];
    final c = _container(repo, eightLeases);

    final result = await svc.syncAll(c.read(_refProvider), [newer, older, refused]);

    expect(result.success, isFalse);
    expect(repo.timerCfgWrites, 0);
    expect(result.presetErrors.join('\n'), contains('has no saved design'));
    expect(result.error, kScheduleKeepRowsRefused);
  });

  test('a refused schedule whose rows ARE kept, beside another that is out of '
      'room: the only missing row is the out-of-room one, so the table is full',
      () async {
    final refused = patternSchedule(on: '5:00 PM', off: '7:00 AM')
        .copyWith(clearWledPayload: true, actionLabel: 'Pattern: overnight');
    final older = patternSchedule(on: '6:00 AM', off: '8:00 AM', label: 'Pattern: dawn');
    final newer = patternSchedule(on: '7:00 PM', off: '10:00 PM', label: 'Pattern: evening');
    final held = [
      _row(17, 0, 10, 127), _row(7, 0, 2, 127),
      _row(6, 0, 11, 127), _row(8, 0, 2, 127),
    ];
    final repo = _HoldingController(held);
    // Six lease rows: the refused schedule's two rows are kept (room for
    // two), which leaves nothing for the older schedule.
    final c = _container(repo, _sixLeases());

    final result = await svc.syncAll(c.read(_refProvider), [newer, older, refused]);

    expect(result.success, isFalse);
    expect(repo.timerCfgWrites, 0);
    expect(result.error, kExpectedFullTableCopy);
  });

  test('with room for everyone the write goes out — the guard does not fire',
      () async {
    final older = patternSchedule(on: '5:00 PM', off: '7:00 AM');
    final newer = patternSchedule(on: '7:00 PM', off: '10:00 PM', label: 'Pattern: evening');
    final held = [_row(17, 0, 10, 127), _row(7, 0, 2, 127)];
    final repo = _HoldingController(held);
    final c = _container(repo, _sixLeases().take(4).toList());

    final result = await svc.syncAll(c.read(_refProvider), [newer, older]);

    expect(result.success, isTrue, reason: '${result.error}');
    expect(repo.timerCfgWrites, 1);
  });
}
