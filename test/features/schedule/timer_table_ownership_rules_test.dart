// Build 127 — the ownership rules (timer_table_ownership.dart), pure.
//
// Who owns a row is read off its macro with the healer's base_boundaries
// classification ([wledPresetRole]) and never off its position; a readback
// is re-assembled by content; a lease write replaces only lease rows; the
// sunrise-off toggle changes only the sunrise slot; schedule sync keeps a
// refused schedule's rows and refuses a table that would drop an enabled
// schedule's row.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/timer_table.dart';
import 'package:nexgen_command/features/schedule/timer_table_ownership.dart';
import 'package:nexgen_command/features/wled/wled_preset_ranges.dart';

Map<String, dynamic> row({
  int en = 1,
  required int hour,
  int min = 0,
  required int macro,
  int dow = 127,
  bool dated = true,
}) =>
    {
      'en': en,
      'hour': hour,
      'min': min,
      'macro': macro,
      'dow': dow,
      if (dated) 'start': {'mon': 1, 'day': 1},
      if (dated) 'end': {'mon': 12, 'day': 31},
    };

const placeholder = {'en': 0, 'hour': 255, 'min': 0, 'macro': 0, 'dow': 0};
const stub = {'en': 0, 'hour': 0, 'min': 0, 'macro': 0, 'dow': 0};
Map<String, dynamic> sunriseOff() =>
    {'en': 1, 'hour': 255, 'min': 0, 'macro': 2, 'dow': 127};
Map<String, dynamic> sunset(int macro) =>
    {'en': 1, 'hour': 254, 'min': 0, 'macro': macro, 'dow': 127};

const kDaily = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

ScheduleItem pattern({
  String id = 'p',
  String on = '5:00 PM',
  String? off = '7:00 AM',
  List<String> days = kDaily,
  String label = 'Pattern: Classic Christmas 2',
  bool enabled = true,
}) =>
    ScheduleItem(
      id: id,
      timeLabel: on,
      offTimeLabel: off,
      repeatDays: days,
      actionLabel: label,
      enabled: enabled,
      wledPayload: const {'on': true},
    );

ScheduleItem turnOn({String on = '6:00 PM'}) => ScheduleItem(
      id: 'on',
      timeLabel: on,
      repeatDays: kDaily,
      actionLabel: 'Turn On',
      enabled: true,
    );

void main() {
  group('a row\'s owner is its macro\'s role — the healer\'s classification',
      () {
    test('every macro the schedule band can hold is a schedule row, never a '
        'lease row', () {
      for (var m = kFirstSchedulePresetId; m <= kLastSchedulePresetId; m++) {
        final r = row(hour: 17, macro: m);
        expect(timerRowRole(r), 'schedule', reason: 'macro $m');
        expect(isLeaseRow(r), isFalse, reason: 'macro $m');
      }
      expect(kLastSchedulePresetId, lessThan(kFirstLeasePresetId),
          reason: 'the bands do not overlap, so a schedule row can never '
              'carry a lease macro');
    });

    test('the lease band is 26–41 and nothing else', () {
      for (var m = kFirstLeasePresetId; m <= kLastLeasePresetId; m++) {
        expect(isLeaseRow(row(hour: 20, macro: m)), isTrue, reason: 'macro $m');
      }
      for (final m in [1, 2, 3, 4, 5, 9, 10, 25, 42, 99, 100, 200, 250]) {
        expect(isLeaseRow(row(hour: 20, macro: m)), isFalse,
            reason: 'macro $m');
      }
    });

    test('system rows: 2 is system_off, 1/3/4/5 are system_on', () {
      expect(timerRowRole(row(hour: 7, macro: 2)), 'system_off');
      for (final m in [1, 3, 4, 5]) {
        expect(timerRowRole(row(hour: 7, macro: m)), 'system_on');
      }
    });

    test('position never decides: a schedule row sitting where a lease record '
        'says its slot is stays a schedule row, and a lease row anywhere is a '
        'lease row', () {
      // A lease registered at slotIndex 0 — and the controller's first row
      // is a schedule's (the readback is compacted; positions mean nothing).
      final readback = [
        row(hour: 17, macro: 10), // "slot 0" holds a schedule row
        row(hour: 7, macro: 2),
        row(hour: 20, min: 30, macro: 30, dow: 16), // the lease, anywhere
      ];
      final composed = composeLeaseWrite(readback: readback, leaseRows: const []);
      final ins = composed.ins!;
      expect(ins[0], readback[0], reason: 'kept, byte for byte');
      expect(ins[1], readback[1]);
      expect(ins.where((t) => t['macro'] == 30), isEmpty,
          reason: 'the lease row (macro 30) was the one replaced');
    });

    test('the daily sunrise-off is the one row the toggle owns', () {
      expect(isGlobalSunriseOffRow(sunriseOff()), isTrue);
      expect(isGlobalSunriseOffRow({...sunriseOff(), 'dow': 62}), isFalse,
          reason: 'a schedule\'s sunrise OFF on some days is not the toggle\'s');
      expect(isGlobalSunriseOffRow({...sunriseOff(), 'macro': 10}), isFalse);
      expect(isGlobalSunriseOffRow({...sunriseOff(), 'en': 0}), isFalse);
      expect(isGlobalSunriseOffRow(row(hour: 7, macro: 2)), isFalse,
          reason: 'a clock OFF is not a sun row');
    });
  });

  group('re-assembling the table from a compacted readback', () {
    test('current encoding: 254 is the sunset, a disabled 255 the placeholder, '
        'general rows kept in order with their date range', () {
      final r = deviceTableFromReadback([
        row(hour: 17, macro: 10),
        row(hour: 7, macro: 2),
        placeholder,
        sunset(11),
      ]);
      final t = r.table!;
      expect(t.general, [row(hour: 17, macro: 10), row(hour: 7, macro: 2)]);
      expect(t.sunrise, placeholder);
      expect(t.sunset, sunset(11));
    });

    test('a table written before the sunset marker: two 255 rows, first is '
        'the sunrise and second the sunset', () {
      final up = {'en': 1, 'hour': 255, 'min': 0, 'macro': 2, 'dow': 127};
      final down = {'en': 1, 'hour': 255, 'min': 0, 'macro': 11, 'dow': 127};
      final t = deviceTableFromReadback([row(hour: 23, macro: 2), up, down]).table!;
      expect(t.sunrise, up);
      expect(t.sunset, down);
    });

    test('a lone 255 row that is a master OFF is the sunrise', () {
      expect(deviceTableFromReadback([sunriseOff()]).table!.sunrise,
          sunriseOff());
      final partial = {...sunriseOff(), 'dow': 62};
      expect(deviceTableFromReadback([row(hour: 17, macro: 10), partial])
              .table!
              .sunrise,
          partial);
    });

    test('a lone 255 row with an ON macro is refused, not guessed', () {
      final r = deviceTableFromReadback([
        row(hour: 23, macro: 2),
        {'en': 1, 'hour': 255, 'min': 0, 'macro': 10, 'dow': 127},
      ]);
      expect(r.table, isNull);
      expect(r.refusal, kDeviceTableAmbiguousSunRow);
    });

    test('a disabled general row with content is kept; an all-zero row is not',
        () {
      final disabled = row(en: 0, hour: 17, macro: 10);
      final t = deviceTableFromReadback([disabled, stub]).table!;
      expect(t.general, [disabled]);
    });

    test('more than eight general rows is refused', () {
      final r = deviceTableFromReadback(
          [for (var h = 0; h < 9; h++) row(hour: h, macro: 10)]);
      expect(r.table, isNull);
      expect(r.refusal, kDeviceTableTooManyRows);
    });

    test('rows are copied, never aliased', () {
      final src = row(hour: 17, macro: 10);
      final t = deviceTableFromReadback([src]).table!;
      (t.general.single['start'] as Map)['mon'] = 6;
      expect((src['start'] as Map)['mon'], 1);
    });
  });

  group('the lease write', () {
    test('replaces the lease rows, keeps everything else, sun slots as read',
        () {
      final kept = [row(hour: 17, macro: 10), row(hour: 7, macro: 2)];
      final old = row(hour: 20, min: 30, macro: 30, dow: 16);
      final mine = [
        {'en': 1, 'hour': 14, 'min': 55, 'macro': 31, 'dow': 32},
      ];
      final c = composeLeaseWrite(
          readback: [...kept, old, sunriseOff(), sunset(11)], leaseRows: mine);
      final ins = c.ins!;
      expect(ins.length, kTableSlots);
      expect(ins.sublist(0, 2), kept);
      expect(ins[2], mine.single);
      for (var i = 3; i < 8; i++) {
        expect(ins[i], stub, reason: 'slot $i padded');
      }
      expect(ins[8], sunriseOff());
      expect(ins[9], sunset(11));
      expect(c.keptRows, 2);
    });

    test('no free slot: nothing is evicted, the night is skipped', () {
      final full = [for (var h = 0; h < 8; h++) row(hour: h, macro: 10)];
      final c = composeLeaseWrite(readback: full, leaseRows: [
        {'en': 1, 'hour': 20, 'min': 0, 'macro': 30, 'dow': 16},
      ]);
      expect(c.ins, isNull);
      expect(c.noFreeSlot, isTrue);
      expect(c.refusal, contains('nothing is evicted'));
      expect(c.keptRows, 8);
    });

    test('a stale lease row on the device does not count against the room: '
        'it is replaced', () {
      final seven = [for (var h = 0; h < 7; h++) row(hour: h, macro: 10)];
      final stale = row(hour: 20, macro: 30, dow: 16);
      final c = composeLeaseWrite(readback: [...seven, stale], leaseRows: [
        {'en': 1, 'hour': 21, 'min': 0, 'macro': 31, 'dow': 32},
      ]);
      expect(c.ins, isNotNull);
      expect(c.ins![7]['macro'], 31);
      expect(c.ins!.where((t) => t['macro'] == 30), isEmpty);
    });

    test('a zeroing write sends the lease rows that fit and drops the rest',
        () {
      final full = [for (var h = 0; h < 8; h++) row(hour: h, macro: 10)];
      final c = composeLeaseWrite(
        readback: full,
        leaseRows: [
          {'en': 1, 'hour': 20, 'min': 0, 'macro': 30, 'dow': 16},
        ],
        truncateLeases: true,
      );
      expect(c.ins, isNotNull);
      expect(c.ins!.where((t) => t['macro'] == 30), isEmpty);
      expect(c.ins!.sublist(0, 8), full);
    });

    test('an unreadable sun row refuses the write', () {
      final c = composeLeaseWrite(readback: [
        {'en': 1, 'hour': 255, 'min': 0, 'macro': 10, 'dow': 127},
      ], leaseRows: const []);
      expect(c.ins, isNull);
      expect(c.noFreeSlot, isFalse);
      expect(c.refusal, kDeviceTableAmbiguousSunRow);
    });
  });

  group('the sunrise-off toggle write', () {
    final held = [row(hour: 17, macro: 10), row(hour: 7, macro: 2)];

    test('arm: slot 8 becomes the sunrise-off, every other row as read', () {
      final c = composeSunriseOffWrite(
          readback: [...held, placeholder, sunset(11)],
          enabled: true,
          sunriseOffRow: sunriseOff());
      expect(c.ins!.sublist(0, 2), held);
      expect(c.ins![8], sunriseOff());
      expect(c.ins![9], sunset(11));
    });

    test('arm takes the slot even over a schedule\'s sunrise ON (the setting '
        'outranks it, as the arm checks say)', () {
      final dawn = {'en': 1, 'hour': 255, 'min': 0, 'macro': 12, 'dow': 127};
      final c = composeSunriseOffWrite(
          readback: [...held, dawn, sunset(11)],
          enabled: true,
          sunriseOffRow: sunriseOff());
      expect(c.ins![8], sunriseOff());
    });

    test('disarm: the toggle\'s own row becomes the placeholder', () {
      final c = composeSunriseOffWrite(
          readback: [...held, sunriseOff()],
          enabled: false,
          sunriseOffRow: sunriseOff());
      expect(c.ins!.sublist(0, 2), held);
      expect(c.ins![8], sunrisePlaceholder());
      expect(c.ins![9], stub);
    });

    test('disarm leaves a schedule\'s own sunrise OFF (some days) alone', () {
      final partial = {...sunriseOff(), 'dow': 62};
      final c = composeSunriseOffWrite(
          readback: [...held, partial],
          enabled: false,
          sunriseOffRow: sunriseOff());
      expect(c.ins![8], partial);
    });

    test('an ambiguous readback refuses the write', () {
      final c = composeSunriseOffWrite(
          readback: [
            {'en': 1, 'hour': 255, 'min': 0, 'macro': 10, 'dow': 127},
          ],
          enabled: true,
          sunriseOffRow: sunriseOff());
      expect(c.ins, isNull);
      expect(c.refusal, kDeviceTableAmbiguousSunRow);
    });
  });

  group('schedule sync: a schedule\'s rows on the device', () {
    test('a design schedule\'s ON row is a schedule-role row at its time and '
        'days; a lease row at the same time is NOT adopted', () {
      final s = pattern();
      final mine = row(hour: 17, macro: 10);
      final lease = row(hour: 17, macro: 30);
      expect(deviceOnRowFor(s, [lease]), isNull,
          reason: 'a lease row at the schedule\'s time is a lease row');
      expect(deviceOnRowFor(s, [lease, mine]), mine);
    });

    test('a Turn On schedule\'s row is a system_on row; a design row at that '
        'time is not it', () {
      final s = turnOn();
      expect(deviceOnRowFor(s, [row(hour: 18, macro: 10)]), isNull);
      expect(deviceOnRowFor(s, [row(hour: 18, macro: 1)]),
          row(hour: 18, macro: 1));
    });

    test('a "Pattern: …" schedule with no stored payload still owns a '
        'schedule-band row; an unresolvable label owns either ON kind, never '
        'an OFF or a lease', () {
      const noPayload = ScheduleItem(
        id: 'np',
        timeLabel: '5:00 PM',
        repeatDays: kDaily,
        actionLabel: 'Pattern: overnight',
        enabled: true,
      );
      expect(scheduleOnRoles(noPayload), {'schedule'});
      expect(deviceOnRowFor(noPayload, [row(hour: 17, macro: 10)]),
          row(hour: 17, macro: 10));
      const chat = ScheduleItem(
        id: 'chat',
        timeLabel: '5:12 PM',
        repeatDays: kDaily,
        actionLabel: 'Deep Blue',
        enabled: true,
      );
      expect(scheduleOnRoles(chat), {'schedule', 'system_on'});
      expect(deviceOnRowFor(chat, [row(hour: 17, min: 12, macro: 1)]),
          isNotNull);
      expect(deviceOnRowFor(chat, [row(hour: 17, min: 12, macro: 2)]), isNull);
      expect(deviceOnRowFor(chat, [row(hour: 17, min: 12, macro: 30)]), isNull);
    });

    test('the OFF row of an overnight schedule is on the next day\'s bits',
        () {
      final weekdays = pattern(days: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']);
      // Mon–Fri = 0b0011111 = 31; the OFF at 7 AM fires Tue–Sat = 62.
      expect(deviceOffRowFor(weekdays, [row(hour: 7, macro: 2, dow: 31)]),
          isNull);
      expect(deviceOffRowFor(weekdays, [row(hour: 7, macro: 2, dow: 62)]),
          row(hour: 7, macro: 2, dow: 62));
    });

    test('kept rows: ON then OFF, copies; a lone OFF is never kept', () {
      final on = row(hour: 17, macro: 10);
      final off = row(hour: 7, macro: 2);
      expect(deviceRowsFor(pattern(), [off, on]), [on, off]);
      expect(deviceRowsFor(pattern(), [off]), isEmpty);
      final kept = deviceRowsFor(pattern(), [on]);
      (kept.single['start'] as Map)['mon'] = 9;
      expect((on['start'] as Map)['mon'], 1, reason: 'a copy, not the row');
    });

    test('a sunrise/sunset ON, an unparseable time or no days: no device row '
        'to find', () {
      expect(deviceOnRowFor(pattern(on: 'Sunset'), [row(hour: 17, macro: 10)]),
          isNull);
      expect(deviceOnRowFor(pattern(on: 'at dusk'), [row(hour: 17, macro: 10)]),
          isNull);
      expect(
          deviceOnRowFor(pattern(days: const []), [row(hour: 17, macro: 10)]),
          isNull);
    });

    test('scheduleRowsDropped: an enabled schedule whose device row the '
        'outgoing table lacks', () {
      final s = pattern();
      final device = [row(hour: 17, macro: 10), row(hour: 7, macro: 2)];
      final outgoingWithout = assembleTable([row(hour: 18, macro: 11)]);
      expect(scheduleRowsDropped(
              enabled: [s], readback: device, outgoing: outgoingWithout),
          [s]);
      final outgoingWith = assembleTable([row(hour: 17, macro: 11, dated: false)]);
      expect(scheduleRowsDropped(
              enabled: [s], readback: device, outgoing: outgoingWith),
          isEmpty,
          reason: 'a re-allocated slot (macro 11) is still a schedule row at '
              'the same time and days');
    });

    test('scheduleRowsDropped: a schedule whose time changed matches no '
        'device row, so its old row goes as intended; a disabled schedule is '
        'ignored', () {
      final moved = pattern(on: '6:00 PM');
      final device = [row(hour: 17, macro: 10)];
      final outgoing = assembleTable([row(hour: 18, macro: 10, dated: false)]);
      expect(scheduleRowsDropped(
              enabled: [moved], readback: device, outgoing: outgoing),
          isEmpty);
      final off = pattern(enabled: false);
      expect(scheduleRowsDropped(
              enabled: [off], readback: device, outgoing: assembleTable([])),
          isEmpty);
    });

    test('scheduleRowsDropped ignores a disabled outgoing row: a row sent as '
        'disabled is a removal', () {
      final s = pattern();
      final device = [row(hour: 17, macro: 10)];
      final outgoing = assembleTable([row(en: 0, hour: 17, macro: 10)]);
      expect(scheduleRowsDropped(
              enabled: [s], readback: device, outgoing: outgoing),
          [s]);
    });
  });

  group('buildTimerTable with kept rows', () {
    test('kept rows sit after the clock rows and before the leases, and '
        'reduce the schedules\' budget', () {
      final t = buildTimerTable(
        armable: [pattern(id: 'a', on: '6:00 PM', off: '11:00 PM')
            .copyWith(presetId: 11)],
        leaseRows: [
          {'en': 1, 'hour': 20, 'min': 0, 'macro': 30, 'dow': 16},
        ],
        preservedRows: [row(hour: 17, macro: 10), row(hour: 7, macro: 2)],
        solarEnabled: false,
      );
      expect(t.ins[0]['hour'], 18);
      expect(t.ins[1]['hour'], 23);
      expect(t.ins[2], row(hour: 17, macro: 10));
      expect(t.ins[3], row(hour: 7, macro: 2));
      expect(t.ins[4]['macro'], 30);
    });

    test('kept rows never push a lease row out: the ones that do not fit are '
        'dropped (and the sync\'s keep guard refuses the write)', () {
      final leases = [
        for (var h = 0; h < 8; h++)
          {'en': 1, 'hour': h, 'min': 0, 'macro': 26 + h, 'dow': 16},
      ];
      final t = buildTimerTable(
        armable: const [],
        leaseRows: leases,
        preservedRows: [row(hour: 17, macro: 10)],
        solarEnabled: false,
      );
      expect(t.ins.sublist(0, 8), leases);
      expect(scheduleRowsDropped(
              enabled: [pattern()],
              readback: [row(hour: 17, macro: 10)],
              outgoing: t.ins),
          hasLength(1));
    });
  });
}
