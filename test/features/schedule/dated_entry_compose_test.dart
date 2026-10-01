// +112 (#124) — the pure half of "Just this day".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/dated_entry_compose.dart';

void main() {
  final date = DateTime(2026, 10, 9); // Friday

  const payload = <String, dynamic>{
    'on': true,
    'bri': 217,
    'seg': [
      {
        'fx': 12,
        'pal': 5,
        'col': [
          [227, 24, 55, 0],
          [255, 184, 28, 0],
        ],
      },
    ],
  };

  group('composeDatedEntry', () {
    test('a pattern night is the customer\'s own and keeps the payload', () {
      final e = composeDatedEntry(
        date: date,
        action: DatedAction.runPattern,
        onHhmm: '19:00',
        offHhmm: '23:00',
        patternName: 'Team Night',
        patternPayload: payload,
      );
      expect(e.dateKey, '2026-10-09');
      expect(e.type, CalendarEntryType.user);
      expect(e.autopilot, isFalse);
      expect(e.sourceTag, isNull, reason: 'user-authored = no tag (contract)');
      expect(e.wledPayload, payload);
      expect(e.color, const Color(0xFFE31837), reason: 'first colour');
      expect(e.brightness, 85, reason: '217/255 → 85%');
      expect(e.onTime, '19:00');
      expect(e.offTime, '23:00');
    });

    test('Off fires dark', () {
      final e = composeDatedEntry(
        date: date,
        action: DatedAction.powerOff,
        onHhmm: '22:00',
        offHhmm: null,
      );
      expect(e.patternName, 'Off');
      expect(e.color, isNull);
      expect(e.brightness, 0);
      expect(e.wledPayload, isNull);
    });

    test('Brightness fires white at that level', () {
      final e = composeDatedEntry(
        date: date,
        action: DatedAction.brightness,
        onHhmm: '18:30',
        offHhmm: '23:30',
        brightnessPercent: 40,
      );
      expect(e.patternName, 'Brightness 40%');
      expect(e.color, const Color(0xFFFFFFFF));
      expect(e.brightness, 40);
    });

    test('channel scope rides along', () {
      final e = composeDatedEntry(
        date: date,
        action: DatedAction.runPattern,
        onHhmm: '19:00',
        offHhmm: '23:00',
        patternName: 'x',
        patternPayload: payload,
        channels: const [1],
        controllerId: 'ctl-1',
      );
      expect(e.channels, [1]);
      expect(e.controllerId, 'ctl-1');
    });
  });

  group('resolveDatedClock', () {
    test('a clock time passes through', () {
      final c = resolveDatedClock(trigger: '19:05', date: date, isEnd: false);
      expect(c.hhmm, '19:05');
      expect(c.fromSolar, isFalse);
      expect(c.solarResolved, isTrue);
    });

    test('sunset with coordinates resolves to that evening', () {
      final c = resolveDatedClock(
        trigger: 'Sunset',
        date: date,
        isEnd: false,
        latitude: 39.0,
        longitude: -94.6,
      );
      expect(c.fromSolar, isTrue);
      expect(c.solarResolved, isTrue);
      final h = int.parse(c.hhmm.split(':')[0]);
      expect(h, inInclusiveRange(17, 20), reason: 'an October sunset');
    });

    test('sunrise as the END resolves on the next morning', () {
      final c = resolveDatedClock(
        trigger: 'Sunrise',
        date: date,
        isEnd: true,
        latitude: 39.0,
        longitude: -94.6,
      );
      expect(c.fromSolar, isTrue);
      final h = int.parse(c.hhmm.split(':')[0]);
      expect(h, inInclusiveRange(5, 8));
    });

    test('solar with no coordinates falls back and says so', () {
      final c = resolveDatedClock(trigger: 'Sunset', date: date, isEnd: false);
      expect(c.hhmm, '20:00');
      expect(c.fromSolar, isTrue);
      expect(c.solarResolved, isFalse);
    });
  });

  group('recurrenceCopy', () {
    const rows = <List<String>, String>{
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']: 'Repeats every day',
      ['Daily']: 'Repeats every day',
      ['Tue']: 'Repeats every Tuesday',
      ['Mon', 'Tue', 'Wed', 'Thu', 'Fri']: 'Repeats on weekdays',
      ['Sat', 'Sun']: 'Repeats on weekends',
      ['Fri', 'Mon', 'Wed']: 'Repeats Mon, Wed, Fri',
      ['thursday']: 'Repeats every Thursday',
      <String>[]: 'No repeat days set',
    };
    rows.forEach((days, copy) {
      test('$days → "$copy"', () => expect(recurrenceCopy(days), copy));
    });
  });

  test('formatDatedDate / friendlyClock', () {
    expect(formatDatedDate(DateTime(2026, 10, 4)), 'Sunday, Oct 4, 2026');
    expect(friendlyClock('18:58'), '6:58 PM');
    expect(friendlyClock('00:05'), '12:05 AM');
  });
}
