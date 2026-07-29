// test/features/schedule/sunrise_off_service_test.dart
//
// Encoding + direct arm/disarm for the global sunrise-off.
//
// The encoding assertions are the load-bearing ones. WLED 0.15.1 keys solar BY
// SLOT POSITION (ins[8]=sunrise), `hour` is ignored there and `min` is a signed
// offset; 255 is the firmware's serialized marker. `hour:24` means "fire
// HOURLY" and `hour:25` never matches the RTC — writing either here would snap
// the customer's lights off around the clock. These tests pin that so the old
// encoding can't creep back in.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

class _FakeService extends WledService {
  _FakeService({this.existing}) : super('http://mock');

  /// The controller's current timer table (null = unreadable).
  List<Map<String, dynamic>>? existing;
  Map<String, dynamic>? lastCfg;

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async => existing;

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    lastCfg = cfg;
    return true;
  }
}

Map<String, dynamic> _clockTimer(int macro, int hour) =>
    {'en': 1, 'hour': hour, 'min': 0, 'macro': macro, 'dow': 127};

({ProviderContainer container, _FakeService repo}) _harness({
  List<Map<String, dynamic>>? existing,
}) {
  final repo = _FakeService(existing: existing);
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
  ]);
  addTearDown(container.dispose);
  return (container: container, repo: repo);
}

final _refProvider = Provider<Ref>((ref) => ref);

/// Captures what the service handed to the hardened push. The seam REPLACES
/// pushCfgWithVerify, so the payload is read here rather than off the fake
/// repo — the production path is what routes it to applyConfig.
List<Map<String, dynamic>>? _pushedIns;
Map<String, dynamic>? _pushedPayload;

void _seam(CfgPushOutcome outcome) {
  SunriseOffService.cfgPushFn = (repo, payload, ins) async {
    _pushedPayload = payload;
    _pushedIns = ins;
    return outcome;
  };
}

void main() {
  setUp(() {
    _pushedIns = null;
    _pushedPayload = null;
    // Default seam: report a confirmed verified write.
    _seam(CfgPushOutcome.confirmed);
  });

  tearDown(() {
    SunriseOffService.cfgPushFn = (repo, payload, ins) =>
        pushCfgWithVerify(repo: repo, payload: payload, ins: ins);
  });

  group('encoding', () {
    test('sunrise-off entry uses the POSITIONAL 0.15.1 encoding', () {
      final e = buildSunriseOffTimerEntry();
      expect(e['hour'], ScheduleSyncService.kWledSolarHourMarker);
      expect(e['hour'], 255);
      expect(e['min'], 0, reason: 'min is a solar OFFSET, not a wall clock');
      expect(e['en'], 1, reason: 'WLED reads en TYPE-STRICT as int; a bool → 0');
      expect(e['macro'], 2, reason: 'NGL Off = explicit master off');
      expect(e['dow'], 127, reason: 'every day');
    });

    test('NEVER writes hour 24 or 25 — 24 = fire-hourly, 25 = never matches',
        () {
      final e = buildSunriseOffTimerEntry();
      expect(e['hour'], isNot(24),
          reason: 'hour:24 would turn the lights off every hour, all day');
      expect(e['hour'], isNot(25), reason: 'hour:25 never fires at all');
    });

    test('the reserved slot is index 8 and sits OUTSIDE the 8 general slots',
        () {
      expect(ScheduleSyncService.kWledSunriseSlot, 8);
      expect(ScheduleSyncService.kMaxWledTimers, 8);
      expect(ScheduleSyncService.kWledSunriseSlot,
          greaterThanOrEqualTo(ScheduleSyncService.kMaxWledTimers),
          reason: 'cannot collide with schedule or lease (macro 26-41) slots');
    });
  });

  group('arm / disarm', () {
    test('arm writes the sunrise-off into slot 8 and PRESERVES other slots',
        () async {
      final h = _harness(existing: [
        _clockTimer(10, 19), // slot 0 — a schedule
        _clockTimer(30, 18), // slot 1 — a lease
      ]);
      final ref = h.container.read(_refProvider);

      final result = await const SunriseOffService().arm(ref);

      expect(result, SunriseOffWriteResult.confirmed);
      final ins = _pushedIns!;
      expect(_pushedPayload!['timers'], isNotNull,
          reason: 'must be a /json/cfg timers write');
      expect(ins.length, ScheduleSyncService.kWledTotalTimerSlots);
      expect(ins[0]['macro'], 10, reason: 'schedule timer untouched');
      expect(ins[1]['macro'], 30, reason: 'lease timer untouched');
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['en'], 1);
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['macro'], 2);
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['hour'], 255);
    });

    test('disarm clears slot 8 (en:0) and PRESERVES other slots', () async {
      final h = _harness(existing: [
        _clockTimer(10, 19),
      ]);
      final ref = h.container.read(_refProvider);

      final result = await const SunriseOffService().disarm(ref);

      expect(result, SunriseOffWriteResult.confirmed);
      final ins = _pushedIns!;
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['en'], 0,
          reason: 'the timer must actually stop firing');
      expect(ins[0]['macro'], 10, reason: 'schedule timer untouched');
    });

    test('re-arming is idempotent — one slot, overwritten, never duplicated',
        () async {
      final h = _harness(existing: []);
      final ref = h.container.read(_refProvider);

      await const SunriseOffService().arm(ref);
      // Feed the first write back as the controller's state, then re-arm.
      h.repo.existing = _pushedIns;
      await const SunriseOffService().arm(ref);

      final ins = _pushedIns!;
      expect(ins.length, ScheduleSyncService.kWledTotalTimerSlots);
      final armed = ins.where((t) => t['en'] == 1 && t['macro'] == 2).length;
      expect(armed, 1, reason: 'exactly one sunrise-off timer, ever');
    });

    test('the write is VERIFIED, not fire-and-forget — an unconfirmed push '
        'reports failure', () async {
      SunriseOffService.cfgPushFn =
          (repo, payload, ins) async => CfgPushOutcome.notConfirmed;
      final h = _harness(existing: []);
      final ref = h.container.read(_refProvider);

      expect(await const SunriseOffService().arm(ref),
          SunriseOffWriteResult.failed,
          reason: 'never claim an arm the controller did not confirm');
    });

    test('a content MISMATCH also reports failure', () async {
      SunriseOffService.cfgPushFn =
          (repo, payload, ins) async => CfgPushOutcome.mismatch;
      final h = _harness(existing: []);
      final ref = h.container.read(_refProvider);

      expect(await const SunriseOffService().arm(ref),
          SunriseOffWriteResult.failed);
    });

    test('no controller → noController, nothing written', () async {
      final container = ProviderContainer(overrides: [
        wledRepositoryProvider.overrideWithValue(null),
      ]);
      addTearDown(container.dispose);

      expect(await const SunriseOffService().arm(container.read(_refProvider)),
          SunriseOffWriteResult.noController);
    });

    test('unreadable timer table → general slots become stubs, sunrise-off '
        'still armed (next schedule sync re-asserts 0-7)', () async {
      final h = _harness(existing: null);
      final ref = h.container.read(_refProvider);

      expect(await const SunriseOffService().arm(ref),
          SunriseOffWriteResult.confirmed);
      final ins = _pushedIns!;
      expect(ins.length, ScheduleSyncService.kWledTotalTimerSlots);
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['en'], 1);
      expect(ins.take(8).every((t) => t['en'] == 0), isTrue);
    });
  });
}
