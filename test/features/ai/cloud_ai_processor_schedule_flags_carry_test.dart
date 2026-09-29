// test/features/ai/cloud_ai_processor_schedule_flags_carry_test.dart
//
// UX audit row 7 — proves the multi-night schedule flags (`isSchedule`,
// `dayCount`, `schedule[]`, …) are carried on the TYPED
// LuminaCommandResult.scheduleFlags field instead of being dropped when the
// payload is parsed. The flags sit at the top level of the reply, beside
// `wled`; the payload merge only ever copied `wled` plus a fixed set of
// display keys, so no dispatch site could see them.
//
// Pure parser tests via the parseAiResponseForTest seam — no Firebase, no
// Riverpod, no widget harness. Mirrors
// cloud_ai_processor_scheduling_carry_test.dart (#58b).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';
import 'package:nexgen_command/features/ai/compound_command_detector.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_flags.dart';
import 'package:nexgen_command/features/ai/lumina_smart_scheduler.dart';
import 'package:nexgen_command/features/ai/user_variety_profile.dart';

/// A plan as LuminaSmartScheduler.generatePlan builds it, [nights] long.
SmartSchedulePlan _plan({int nights = 3}) {
  const effects = [43, 2, 52];
  const names = ['Twinkle', 'Breathe', 'Fireworks'];
  return SmartSchedulePlan(
    themeName: 'Christmas',
    appliedProfile: UserVarietyProfile.defaultProfile(),
    summaryText: "I've scheduled $nights nights of Christmas colors "
        'running sunset to sunrise.',
    hasVariety: nights > 1,
    occurrences: [
      for (int i = 0; i < nights; i++)
        ScheduledOccurrence(
          dayIndex: i,
          date: DateTime(2026, 12, 20 + i),
          patternName: 'Christmas ${names[i % 3]}',
          effectName: names[i % 3],
          effectId: effects[i % 3],
          speed: 120,
          intensity: 180,
          colors: const [
            [255, 0, 0, 0],
            [0, 255, 0, 0],
          ],
          wledPayload: {
            'on': true,
            'bri': 200,
            'seg': [
              {
                'fx': effects[i % 3],
                'sx': 120,
                'ix': 180,
                'col': [
                  [255, 0, 0, 0],
                  [0, 255, 0, 0],
                ],
              },
            ],
          },
          startTrigger: TimeTrigger.sunset,
          endTrigger: TimeTrigger.sunrise,
        ),
    ],
  );
}

/// The reply string exactly as LuminaBrain hands it to the parser: the
/// verbal summary followed by the encoded plan.
String _replyFor(SmartSchedulePlan plan) =>
    '${plan.summaryText} ${jsonEncode(LuminaSmartScheduler.planToResponseJson(plan))}';

void main() {
  group('CloudAIProcessor schedule-flag carry (UX audit row 7)', () {
    test('a smart-scheduler reply keeps its flags on the typed field', () {
      final result = CloudAIProcessor.parseAiResponseForTest(
        _replyFor(_plan(nights: 3)),
        'christmas for the next three nights',
      );

      // Pre-fix this was unreachable: the flags were dropped at parse time.
      final flags = result.scheduleFlags;
      expect(flags, isNotNull);
      expect(flags!.isSchedule, isTrue);
      expect(flags.scheduleType, 'multi_day');
      expect(flags.dayCount, 3);
      expect(flags.hasVariety, isTrue);
      expect(flags.patternName, 'Christmas — 3-Night Schedule');
      expect(flags.hasOccurrences, isTrue);
      expect(flags.schedule.length, 3);
    });

    test('every night survives with its own design and date', () {
      final result = CloudAIProcessor.parseAiResponseForTest(
        _replyFor(_plan(nights: 3)),
        'christmas for the next three nights',
      );

      final schedule = result.scheduleFlags!.schedule;
      expect(schedule.map((n) => n['effectId']), [43, 2, 52]);
      expect(schedule.map((n) => n['dayIndex']), [0, 1, 2]);
      for (final night in schedule) {
        expect(DateTime.tryParse(night['date'] as String), isNotNull);
        expect(night['wled'], isA<Map<String, dynamic>>());
      }

      final firstWled = result.scheduleFlags!.firstNightWled;
      expect(firstWled, isNotNull);
      expect((firstWled!['seg'] as List).first['fx'], 43);
    });

    test('the import payload carries the shape the scheduler reads', () {
      final result = CloudAIProcessor.parseAiResponseForTest(
        _replyFor(_plan(nights: 2)),
        'christmas tonight and tomorrow',
      );

      final payload = result.scheduleFlags!.toImportPayload();
      expect(payload['isSchedule'], isTrue);
      expect(payload['dayCount'], 2);
      // AutopilotScheduler.importSmartSchedule casts each entry, and each
      // entry's `wled`, to Map<String, dynamic>.
      final schedule = payload['schedule'] as List<dynamic>;
      expect(schedule.length, 2);
      for (final entry in schedule) {
        expect(entry, isA<Map<String, dynamic>>());
        expect((entry as Map<String, dynamic>)['wled'],
            isA<Map<String, dynamic>>());
      }
    });

    test('REGRESSION: the flags stay OUT of the payload sent to the lights',
        () {
      final result = CloudAIProcessor.parseAiResponseForTest(
        _replyFor(_plan(nights: 3)),
        'christmas for the next three nights',
      );

      // The payload is what applyToDevice sends — it keeps night 1's design
      // and the display metadata, nothing else.
      expect(result.wledPayload, isNotNull);
      expect(result.wledPayload!['on'], true);
      expect(result.wledPayload!['patternName'],
          'Christmas — 3-Night Schedule');
      for (final key in ['isSchedule', 'schedule', 'dayCount', 'hasVariety']) {
        expect(result.wledPayload!.containsKey(key), isFalse,
            reason: '$key must ride on scheduleFlags, not wledPayload');
      }
    });

    test('flags survive a null top-level wled', () {
      const response = 'Setting that up. '
          '{"patternName":"Christmas — 1-Night Schedule","wled":null,'
          '"isSchedule":true,"scheduleType":"multi_day","dayCount":1,'
          '"hasVariety":false,"schedule":[{"dayIndex":0,'
          '"date":"2026-12-24T00:00:00.000","effectId":0,'
          '"wled":{"on":true,"seg":[{"fx":0,"col":[[255,0,0,0]]}]}}]}';

      final result =
          CloudAIProcessor.parseAiResponseForTest(response, 'christmas eve');

      expect(result.wledPayload, isNull);
      expect(result.scheduleFlags, isNotNull);
      expect(result.scheduleFlags!.schedule.length, 1);
    });

    test('season_fill: flags with no plan are carried, with no occurrences',
        () {
      // The shape the cloud prompt asks for — flags and a season name, no
      // per-night list.
      const response = 'Christmas all month. '
          '{"patternName":"Christmas Classic","wled":{"on":true,'
          '"seg":[{"fx":0,"col":[[255,0,0,0]]}]},'
          '"isSchedule":true,"scheduleType":"season_fill",'
          '"seasonId":"christmas_season"}';

      final result = CloudAIProcessor.parseAiResponseForTest(
          response, 'christmas lights for the month');

      final flags = result.scheduleFlags;
      expect(flags, isNotNull);
      expect(flags!.scheduleType, 'season_fill');
      expect(flags.seasonId, 'christmas_season');
      expect(flags.hasOccurrences, isFalse);
      expect(flags.firstNightWled, isNull);
      expect(flags.dayCount, 0);
    });

    test('no schedule flag in the reply → typed field null', () {
      const response = 'Here you go. '
          '{"patternName":"Warm White","wled":{"on":true,'
          '"seg":[{"fx":0,"col":[[255,180,40,0]]}]}}';

      final result =
          CloudAIProcessor.parseAiResponseForTest(response, 'warm white');

      expect(result.scheduleFlags, isNull);
    });

    test('isSchedule:false → typed field null', () {
      const response = 'Here you go. '
          '{"patternName":"Warm White","isSchedule":false,"wled":{"on":true,'
          '"seg":[{"fx":0,"col":[[255,180,40,0]]}]}}';

      final result =
          CloudAIProcessor.parseAiResponseForTest(response, 'warm white');

      expect(result.scheduleFlags, isNull);
    });
  });

  group('LuminaScheduleFlags.fromResponseJson', () {
    test('malformed entries are dropped, never thrown', () {
      final flags = LuminaScheduleFlags.fromResponseJson({
        'isSchedule': true,
        'dayCount': 'seven',
        'scheduleType': 7,
        'schedule': [
          'not a night',
          null,
          {
            'dayIndex': 0,
            'wled': {'on': true},
          },
        ],
      });

      expect(flags, isNotNull);
      expect(flags!.dayCount, 0);
      expect(flags.scheduleType, isNull);
      expect(flags.schedule.length, 1);
      expect(flags.firstNightWled, {'on': true});
    });

    test('a schedule that is not a list yields no occurrences', () {
      final flags = LuminaScheduleFlags.fromResponseJson({
        'isSchedule': true,
        'schedule': 'every night',
      });

      expect(flags, isNotNull);
      expect(flags!.hasOccurrences, isFalse);
    });

    test('null reply → null', () {
      expect(LuminaScheduleFlags.fromResponseJson(null), isNull);
    });
  });
}
