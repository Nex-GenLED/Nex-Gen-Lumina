// +112 (#121) — the Schedule tab's Lumina box: dated nights unless the words
// asked to repeat; every night tagged lumina_ai; a team request carries the
// team look (both colours, motion) on every night.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';

String reply(List<String> dates, {String pattern = 'KC Chiefs Red', String color = '#E31837', bool flag = false}) =>
    jsonEncode({
      'message': 'Done.',
      if (flag) 'recurringIntent': true,
      'changes': [
        for (final d in dates)
          {'date': d, 'pattern': pattern, 'color': color, 'onTime': '19:00', 'offTime': '23:00', 'brightness': 85},
      ],
    });

const week = ['2026-10-05', '2026-10-06', '2026-10-07', '2026-10-08', '2026-10-09', '2026-10-10', '2026-10-11'];

void main() {
  group('dated by default', () {
    test('"chiefs all week" → seven dated nights, no recurring item, even with the model flag', () {
      final p = LuminaCalendarService.parseAiResponseForTest(reply(week, flag: true), request: 'chiefs all week')!;
      expect(p.recurringIntent, isNull, reason: 'RULE 0 / RULE 1 no longer collapse a bounded run');
      expect(p.changes.length, 7);
      for (final c in p.changes) {
        expect(c.sourceTag, CalendarEntrySourceTag.luminaAi);
        expect(c.autopilot, isTrue);
        expect(c.type, CalendarEntryType.user);
      }
    });

    test('a team request carries the team look on every night', () {
      final p = LuminaCalendarService.parseAiResponseForTest(reply(week.take(3).toList()), request: 'chiefs for the next three nights')!;
      for (final c in p.changes) {
        final seg = (c.wledPayload!['seg'] as List).first as Map;
        expect((seg['col'] as List).length, greaterThanOrEqualTo(2), reason: 'red + gold');
        expect(seg.containsKey('fx'), isTrue);
      }
      expect(p.changes.first.color, isNotNull);
    });

    test('a non-team request carries no payload (solid colour night)', () {
      final p = LuminaCalendarService.parseAiResponseForTest(
          reply(['2026-10-05'], pattern: 'Warm White', color: '#FFE8C0'),
          request: 'warm white tomorrow')!;
      expect(p.changes.single.wledPayload, isNull);
      expect(p.changes.single.sourceTag, CalendarEntrySourceTag.luminaAi);
    });

    test('an Off night stays Off', () {
      final raw = jsonEncode({
        'message': 'Off.',
        'changes': [
          {'date': '2026-10-05', 'pattern': 'Off', 'color': null, 'brightness': 0}
        ],
      });
      final p = LuminaCalendarService.parseAiResponseForTest(raw, request: 'chiefs off tomorrow')!;
      expect(p.changes.single.patternName, 'Off');
      expect(p.changes.single.wledPayload, isNull);
    });
  });

  group('recurring only when asked', () {
    test('"chiefs every friday" → one recurring item on Fridays with the team look', () {
      final p = LuminaCalendarService.parseAiResponseForTest(
          reply(['2026-10-09', '2026-10-16', '2026-10-23']),
          request: 'chiefs every friday')!;
      expect(p.recurringIntent, isNotNull);
      expect(p.recurringIntent!.repeatDays, {'Fri'});
      expect(p.recurringIntent!.wledPayload, isNotNull);
    });

    test('"warm white every night" with a single returned date still repeats daily', () {
      final p = LuminaCalendarService.parseAiResponseForTest(
          reply(['2026-10-05'], pattern: 'Warm White', color: '#FFE8C0'),
          request: 'warm white every night')!;
      expect(p.recurringIntent, isNotNull);
      expect(p.recurringIntent!.repeatDays.length, 7);
      expect(p.recurringIntent!.wledPayload, isNull);
    });

    test('"every night this week" is a bounded run, not a routine', () {
      final p = LuminaCalendarService.parseAiResponseForTest(reply(week, flag: true), request: 'warm white every night this week')!;
      expect(p.recurringIntent, isNull);
      expect(p.changes.length, 7);
    });
  });
}
