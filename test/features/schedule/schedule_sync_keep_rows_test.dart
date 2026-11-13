// Build 127 (i) — schedule sync never sends a table that removes an enabled
// schedule's row the controller holds.
//
// The ownership keep (timer_table_ownership_test.dart, case d) covers the
// common shape: a refused schedule's device rows are kept in their place.
// This file covers the guard behind it: when the kept rows cannot fit — here
// the lease ledger holds all eight general slots — the write is SKIPPED and
// the sync fails with the Failed status's Retry, the controller untouched.
// Before 127 the POST went out and the schedule's rows were gone.

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

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const svc = ScheduleSyncService(paceDelay: Duration.zero);

  test(
      'a refused schedule whose rows cannot be kept beside eight lease rows: '
      'the write is skipped, the sync fails with Retry, the controller is '
      'untouched', () async {
    // "Pattern: overnight" at 5 PM is on the controller (macro 10); its
    // design has no saved payload any more, so this sync refuses it.
    final refused = patternSchedule(on: '5:00 PM', off: '7:00 AM')
        .copyWith(clearWledPayload: true, actionLabel: 'Pattern: overnight');
    final held = [_row(17, 0, 10, 127), _row(7, 0, 2, 127)];
    final repo = _HoldingController(held);
    final eightLeases = [
      for (var h = 0; h < 8; h++)
        {'en': 1, 'hour': h, 'min': 0, 'macro': 26 + h, 'dow': 16},
    ];
    final c = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWithValue(repo),
      calendarLeaseActiveTimersProvider
          .overrideWithValue(LeaseLedgerReady(eightLeases)),
      solarSchedulingEnabledSyncProvider.overrideWithValue(false),
      globalSunriseOffTimerProvider.overrideWithValue(sunriseOffRow()),
      controllerDefaultsHealerProvider.overrideWithValue(
          () async => ControllerHealReport()..reachable = false),
    ]);
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      c.dispose();
    });

    final result = await svc.syncAll(c.read(_refProvider), [refused]);

    expect(result.success, isFalse);
    expect(result.error, kScheduleKeepRowsRefused);
    expect(result.deferredOffLan, isFalse);
    expect(repo.timerCfgWrites, 0, reason: 'nothing was sent');
    expect(result.presetErrors.join('\n'), contains('has no saved design'),
        reason: 'the refusal itself is still reported');
    final status = ScheduleSyncStatus.fromResult(result)!;
    expect(status.state, ScheduleSyncState.failed);
    expect(ScheduleSyncCopy.forState(status.state).showsRetry, isTrue);
    expect(status.owesResync, isTrue);
  });

  test('the same schedule with room beside the leases: its rows are kept and '
      'the write goes out', () async {
    final refused = patternSchedule(on: '5:00 PM', off: '7:00 AM')
        .copyWith(clearWledPayload: true, actionLabel: 'Pattern: overnight');
    final held = [_row(17, 0, 10, 127), _row(7, 0, 2, 127)];
    final repo = _HoldingController(held);
    final c = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWithValue(repo),
      calendarLeaseActiveTimersProvider.overrideWithValue(LeaseLedgerReady([
        {'en': 1, 'hour': 20, 'min': 0, 'macro': 30, 'dow': 16},
      ])),
      solarSchedulingEnabledSyncProvider.overrideWithValue(false),
      globalSunriseOffTimerProvider.overrideWithValue(sunriseOffRow()),
      controllerDefaultsHealerProvider.overrideWithValue(
          () async => ControllerHealReport()..reachable = false),
    ]);
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      c.dispose();
    });

    final result = await svc.syncAll(c.read(_refProvider), [refused]);

    expect(result.success, isTrue, reason: '${result.error}');
    expect(repo.timerCfgWrites, 1);
    expect(repo.lastIns, containsAll(held), reason: 'kept byte for byte');
    expect(repo.lastIns.where((t) => t['macro'] == 30), hasLength(1),
        reason: 'the lease row too');
    expect(repo.lastIns[8], sunriseOffRow());
  });
}
