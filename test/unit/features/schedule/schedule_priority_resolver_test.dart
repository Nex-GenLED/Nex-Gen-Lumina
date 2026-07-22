// test/unit/features/schedule/schedule_priority_resolver_test.dart
//
// Coverage for the Phase 2 night-segment composer (the
// `composeNightSegments` pure function in
// lib/features/schedule/schedule_priority_resolver.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_priority_resolver.dart';

void main() {
  // Anchor every test on a fixed date so the assertions are stable.
  final date = DateTime(2026, 1, 15);
  final sunset = DateTime(2026, 1, 15, 18, 0);   // 6:00pm
  final sunrise = DateTime(2026, 1, 16, 6, 0);   // 6:00am next morning

  // Reusable baseline: Warm White, sunset→sunrise, every day.
  ScheduleItem warmWhiteBaseline() => const ScheduleItem(
        id: 'baseline-warm-white',
        timeLabel: 'Sunset',
        offTimeLabel: 'Sunrise',
        repeatDays: ['Daily'],
        actionLabel: 'Pattern: Warm White',
        enabled: true,
      );

  // Helper: build a CalendarEntry for `date` with HH:mm strings and a
  // specific source tag.
  CalendarEntry entry({
    required String onTime,
    required String offTime,
    required CalendarEntryType type,
    String? sourceTag,
    String patternName = 'Test Pattern',
  }) =>
      CalendarEntry(
        dateKey: '${date.year}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}',
        patternName: patternName,
        onTime: onTime,
        offTime: offTime,
        type: type,
        sourceTag: sourceTag,
      );

  // ──────────────────────────────────────────────────────────────────
  // Example 1 — Game Day + Warm White baseline
  // ──────────────────────────────────────────────────────────────────
  test('Example 1: Game Day 9:30pm→1:30am sandwiched in Warm White '
      'sunset→sunrise produces 3 segments', () {
    final gameDay = entry(
      onTime: '21:30',
      offTime: '01:30',
      type: CalendarEntryType.autopilot,
      sourceTag: CalendarEntrySourceTag.gameDay,
      patternName: 'Game Day',
    );

    final segments = composeNightSegments(
      date: date,
      entries: [gameDay],
      baseline: warmWhiteBaseline(),
      sunrise: sunrise,
      sunset: sunset,
    );

    expect(segments.length, 3);

    // Segment 1: Warm White sunset → 9:30pm
    expect(segments[0].tier, SegmentTier.baselineRecurring);
    expect(segments[0].start, sunset);
    expect(segments[0].end, DateTime(2026, 1, 15, 21, 30));

    // Segment 2: Game Day 9:30pm → 1:30am (next day)
    expect(segments[1].tier, SegmentTier.gameDay);
    expect(segments[1].start, DateTime(2026, 1, 15, 21, 30));
    expect(segments[1].end, DateTime(2026, 1, 16, 1, 30));

    // Segment 3: Warm White 1:30am → sunrise
    expect(segments[2].tier, SegmentTier.baselineRecurring);
    expect(segments[2].start, DateTime(2026, 1, 16, 1, 30));
    expect(segments[2].end, sunrise);
  });

  // ──────────────────────────────────────────────────────────────────
  // Example 2 — Neighborhood Sync + Warm White baseline
  // ──────────────────────────────────────────────────────────────────
  test('Example 2: Neighborhood Sync 8pm→10pm sandwiched in Warm White '
      'produces 3 segments', () {
    final sync = entry(
      onTime: '20:00',
      offTime: '22:00',
      type: CalendarEntryType.autopilot,
      sourceTag: CalendarEntrySourceTag.neighborhoodSync,
      patternName: 'Block Party Sync',
    );

    final segments = composeNightSegments(
      date: date,
      entries: [sync],
      baseline: warmWhiteBaseline(),
      sunrise: sunrise,
      sunset: sunset,
    );

    expect(segments.length, 3);

    expect(segments[0].tier, SegmentTier.baselineRecurring);
    expect(segments[0].start, sunset);
    expect(segments[0].end, DateTime(2026, 1, 15, 20, 0));

    expect(segments[1].tier, SegmentTier.neighborhoodSync);
    expect(segments[1].start, DateTime(2026, 1, 15, 20, 0));
    expect(segments[1].end, DateTime(2026, 1, 15, 22, 0));

    expect(segments[2].tier, SegmentTier.baselineRecurring);
    expect(segments[2].start, DateTime(2026, 1, 15, 22, 0));
    expect(segments[2].end, sunrise);
  });

  // ──────────────────────────────────────────────────────────────────
  // Example 3 — Game Day + Neighborhood Sync + Warm White baseline
  // ──────────────────────────────────────────────────────────────────
  //
  // The original spec listed FOUR expected segments here. Applying the
  // composition algorithm strictly produces FIVE: there is a 30-minute
  // gap between Sync's end (9:00pm) and Game's start (9:30pm) that the
  // baseline must fill — otherwise the lights would be in an undefined
  // state for that window. The 5-segment output below is the correct
  // behavior; the original 4-segment narration overlooked the 9:00→
  // 9:30pm slice.
  test('Example 3: Game Day + Sync + Warm White composes into 5 '
      'segments (with a Warm White slice between Sync end and Game start)',
      () {
    final gameDay = entry(
      onTime: '21:30',
      offTime: '01:30',
      type: CalendarEntryType.autopilot,
      sourceTag: CalendarEntrySourceTag.gameDay,
      patternName: 'Game Day',
    );
    final sync = entry(
      onTime: '19:00',
      offTime: '21:00',
      type: CalendarEntryType.autopilot,
      sourceTag: CalendarEntrySourceTag.neighborhoodSync,
      patternName: 'Neighborhood Sync',
    );

    final segments = composeNightSegments(
      date: date,
      entries: [gameDay, sync],
      baseline: warmWhiteBaseline(),
      sunrise: sunrise,
      sunset: sunset,
    );

    expect(segments.length, 5);

    // 1. Warm White sunset → 7pm
    expect(segments[0].tier, SegmentTier.baselineRecurring);
    expect(segments[0].start, sunset);
    expect(segments[0].end, DateTime(2026, 1, 15, 19, 0));

    // 2. Neighborhood Sync 7pm → 9pm
    expect(segments[1].tier, SegmentTier.neighborhoodSync);
    expect(segments[1].start, DateTime(2026, 1, 15, 19, 0));
    expect(segments[1].end, DateTime(2026, 1, 15, 21, 0));

    // 3. Warm White 9pm → 9:30pm  (the slice the spec narration missed)
    expect(segments[2].tier, SegmentTier.baselineRecurring);
    expect(segments[2].start, DateTime(2026, 1, 15, 21, 0));
    expect(segments[2].end, DateTime(2026, 1, 15, 21, 30));

    // 4. Game Day 9:30pm → 1:30am next day
    expect(segments[3].tier, SegmentTier.gameDay);
    expect(segments[3].start, DateTime(2026, 1, 15, 21, 30));
    expect(segments[3].end, DateTime(2026, 1, 16, 1, 30));

    // 5. Warm White 1:30am → sunrise
    expect(segments[4].tier, SegmentTier.baselineRecurring);
    expect(segments[4].start, DateTime(2026, 1, 16, 1, 30));
    expect(segments[4].end, sunrise);
  });

  // ──────────────────────────────────────────────────────────────────
  // Example 4 — User manual entry owns the night (no composition)
  // ──────────────────────────────────────────────────────────────────
  test('Example 4: a user-typed entry owns the full night and is not '
      'split by the baseline', () {
    final userEntry = entry(
      onTime: '20:00',
      offTime: '23:30',
      type: CalendarEntryType.user,
      patternName: 'Anniversary Gold',
      // sourceTag intentionally null — user entries don't carry one.
    );

    final segments = composeNightSegments(
      date: date,
      entries: [userEntry],
      baseline: warmWhiteBaseline(),
      sunrise: sunrise,
      sunset: sunset,
    );

    expect(segments.length, 1);
    expect(segments.single.tier, SegmentTier.user);
    expect(segments.single.entry, userEntry);
    expect(segments.single.start, DateTime(2026, 1, 15, 20, 0));
    expect(segments.single.end, DateTime(2026, 1, 15, 23, 30));
  });

  // ──────────────────────────────────────────────────────────────────
  // Example 5 — Single event night, no baseline (backward compat)
  // ──────────────────────────────────────────────────────────────────
  test('Example 5: a Game Day entry with no baseline collapses to a '
      'single segment, preserving prior behavior', () {
    final gameDay = entry(
      onTime: '21:30',
      offTime: '01:30',
      type: CalendarEntryType.autopilot,
      sourceTag: CalendarEntrySourceTag.gameDay,
      patternName: 'Game Day',
    );

    final segments = composeNightSegments(
      date: date,
      entries: [gameDay],
      baseline: null,
      sunrise: sunrise,
      sunset: sunset,
    );

    expect(segments.length, 1);
    expect(segments.single.tier, SegmentTier.gameDay);
    expect(segments.single.entry, gameDay);
    expect(segments.single.start, DateTime(2026, 1, 15, 21, 30));
    expect(segments.single.end, DateTime(2026, 1, 16, 1, 30));
  });

  // ──────────────────────────────────────────────────────────────────
  // Bonus — holiday short-circuit (mirrors Example 4's invariant for
  // tier 2). Cheap to add and prevents future regressions in the
  // tier-1/tier-2 short-circuit path.
  // ──────────────────────────────────────────────────────────────────
  test('a holiday-typed entry owns the full night and is not split by '
      'the baseline', () {
    final holiday = entry(
      onTime: '17:30',
      offTime: '23:59',
      type: CalendarEntryType.holiday,
      patternName: 'Christmas Lights',
    );

    final segments = composeNightSegments(
      date: date,
      entries: [holiday],
      baseline: warmWhiteBaseline(),
      sunrise: sunrise,
      sunset: sunset,
    );

    expect(segments.length, 1);
    expect(segments.single.tier, SegmentTier.holiday);
    expect(segments.single.entry, holiday);
  });
}
