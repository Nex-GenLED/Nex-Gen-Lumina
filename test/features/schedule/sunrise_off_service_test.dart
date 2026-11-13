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
  _FakeService({this.held = const [], this.readable = true})
      : super('http://mock');

  /// Build 127 — what the controller reads back (compacted). The toggle
  /// keeps every row it does not own, so the fake holds the table.
  final List<Map<String, dynamic>> held;

  /// False models a failed /json/cfg read (null = unknown).
  final bool readable;

  Map<String, dynamic>? lastCfg;

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async => readable
      ? [for (final t in held) Map<String, dynamic>.from(t)]
      : null;

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    lastCfg = cfg;
    return true;
  }
}

/// A clock schedule's ON row as the controller reads it back once a schedule
/// sync has written it (slot 10 = the first pattern preset).
Map<String, dynamic> _scheduleRow(int presetId, int hour) => {
      'en': 1,
      'hour': hour,
      'min': 0,
      'macro': presetId,
      'dow': 127,
      'start': {'mon': 1, 'day': 1},
      'end': {'mon': 12, 'day': 31},
    };

/// A one-night lease row as the controller reads it back.
const Map<String, dynamic> _leaseRow = {
  'en': 1,
  'hour': 18,
  'min': 0,
  'macro': 30,
  'dow': 32,
  'start': {'mon': 1, 'day': 1},
  'end': {'mon': 12, 'day': 31},
};

/// The daily sunrise-off as the controller reads it back (slot 8).
const Map<String, dynamic> _heldSunriseOff = {
  'en': 1,
  'hour': 255,
  'min': 0,
  'macro': 2,
  'dow': 127,
};

/// The toggle writes the table the controller HOLDS with slot 8 as the only
/// change (build 127, ownership): nothing is built from stored schedules or
/// the lease ledger any more.
({ProviderContainer container, _FakeService repo}) _harness({
  List<Map<String, dynamic>> held = const [],
  bool readable = true,
}) {
  final repo = _FakeService(held: held, readable: readable);
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
    test('arm writes the sunrise-off into slot 8 and keeps every schedule and '
        'lease row', () async {
      final h = _harness(held: [_scheduleRow(10, 19), _leaseRow]);
      final ref = h.container.read(_refProvider);

      final result = await const SunriseOffService().arm(ref);

      expect(result, SunriseOffWriteResult.confirmed);
      final ins = _pushedIns!;
      expect(_pushedPayload!['timers'], isNotNull,
          reason: 'must be a /json/cfg timers write');
      expect(ins.length, ScheduleSyncService.kWledTotalTimerSlots);
      expect(ins[0], _scheduleRow(10, 19),
          reason: 'schedule row kept byte for byte');
      expect(ins[1], _leaseRow, reason: 'lease row kept byte for byte');
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['en'], 1);
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['macro'], 2);
      expect(ins[ScheduleSyncService.kWledSunriseSlot]['hour'], 255);
    });

    test('disarm leaves slot 8 as the disabled placeholder and keeps the '
        'schedule row', () async {
      final h = _harness(held: [_scheduleRow(10, 19), _heldSunriseOff]);
      final ref = h.container.read(_refProvider);

      final result = await const SunriseOffService().disarm(ref);

      expect(result, SunriseOffWriteResult.confirmed);
      final ins = _pushedIns!;
      expect(ins[ScheduleSyncService.kWledSunriseSlot],
          {'en': 0, 'hour': 255, 'min': 0, 'macro': 0, 'dow': 0},
          reason: 'the timer stops firing; slot 8 stays in cfg.json');
      expect(ins[0], _scheduleRow(10, 19), reason: 'schedule row kept');
    });

    test("disarm leaves a schedule's own sunrise row alone — it is not this "
        'toggle\'s row to clear', () async {
      const scheduleSunriseOff = {
        'en': 1,
        'hour': 255,
        'min': 0,
        'macro': 2,
        'dow': 62, // Tue–Sat: the OFF days of a Mon–Fri overnight schedule
      };
      final h = _harness(held: [_scheduleRow(10, 19), scheduleSunriseOff]);
      final ref = h.container.read(_refProvider);

      final result = await const SunriseOffService().disarm(ref);

      expect(result, SunriseOffWriteResult.confirmed);
      expect(_pushedIns![ScheduleSyncService.kWledSunriseSlot],
          scheduleSunriseOff,
          reason: 'only the daily sunrise-off (dow 127) is the toggle\'s');
    });

    test('re-arming is idempotent — the same table, one sunrise-off row',
        () async {
      final h = _harness(held: [_scheduleRow(10, 19)]);
      final ref = h.container.read(_refProvider);

      await const SunriseOffService().arm(ref);
      final first = _pushedIns!;
      await const SunriseOffService().arm(ref);

      final ins = _pushedIns!;
      expect(ins, first);
      final armed = ins.where((t) => t['en'] == 1 && t['macro'] == 2).length;
      expect(armed, 1, reason: 'exactly one sunrise-off timer, ever');
    });

    test('the write is VERIFIED, not fire-and-forget — an unconfirmed push '
        'reports failure', () async {
      SunriseOffService.cfgPushFn =
          (repo, payload, ins) async => CfgPushOutcome.notConfirmed;
      final h = _harness();
      final ref = h.container.read(_refProvider);

      expect(await const SunriseOffService().arm(ref),
          SunriseOffWriteResult.failed,
          reason: 'never claim an arm the controller did not confirm');
    });

    test('a content MISMATCH also reports failure', () async {
      SunriseOffService.cfgPushFn =
          (repo, payload, ins) async => CfgPushOutcome.mismatch;
      final h = _harness();
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

    test("the controller's table unreadable → nothing written, reported as "
        'not done', () async {
      final h = _harness(held: [_scheduleRow(10, 19)], readable: false);
      final ref = h.container.read(_refProvider);

      expect(await const SunriseOffService().arm(ref),
          SunriseOffWriteResult.failed);
      expect(_pushedIns, isNull,
          reason: 'a table built without knowing what the controller holds '
              'could erase rows this toggle does not own');
    });

    test('a lone sun row with an ON macro cannot be placed → nothing written, '
        'reported as not done', () async {
      // A table written before the sunset marker: one 255 row, an ON macro —
      // a legacy "Sunset → 11 PM" or a current "Sunrise → 8 AM"; the wire
      // cannot say which, and guessing is how a sunset once became a sunrise.
      final h = _harness(held: [
        _scheduleRow(2, 23),
        {'en': 1, 'hour': 255, 'min': 0, 'macro': 10, 'dow': 127},
      ]);
      final ref = h.container.read(_refProvider);

      expect(await const SunriseOffService().arm(ref),
          SunriseOffWriteResult.failed);
      expect(_pushedIns, isNull);
    });
  });
}
