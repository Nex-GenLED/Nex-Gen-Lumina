// +112 (#122) — phrase table for multi-night detection, in the E2 style:
// one row per phrase, with the expected parse, and the negatives that must
// NOT read as multi-night. Fixed "now" so day-name arithmetic is stable:
// Wednesday 2026-04-01.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/compound_command_detector.dart';

void main() {
  final now = DateTime(2026, 4, 1); // Wednesday

  ({bool compound, int days, RecurrenceType? rec, String lighting}) parse(
      String s) {
    final r = CompoundCommandDetector.detect(s, now: now);
    return (
      compound: r.temporal != null,
      days: r.temporal?.dayCount ?? 1,
      rec: r.temporal?.recurrence,
      lighting: r.lightingIntent,
    );
  }

  group('multi-night phrases parse to a dated run', () {
    const rows = <String, int>{
      'chiefs for the next three nights': 3,
      'chiefs next 3 nights': 3,
      'warm white for the next two evenings': 2,
      'blue for the next 2 weeks': 14,
      'ocean pulse next week': 7,
      'patriotic the next few nights': 3,
      'red the next couple of nights': 2,
      'chiefs for the next four days': 4,
      'through sunday': 5, // Wed..Sun inclusive
      'warm white until sunday': 5,
      'green through saturday': 4,
      'this weekend': 2,
      'all weekend': 2,
      'the rest of the week': 7,
      'for the week': 7,
      'chiefs all week': 7,
    };
    rows.forEach((phrase, days) {
      test('"$phrase" → $days nights', () {
        final p = parse(phrase);
        expect(p.compound, isTrue, reason: 'temporal signal expected');
        expect(p.days, days);
        expect(p.rec, isNot(RecurrenceType.once));
      });
    });
  });

  group('the lighting intent survives the strip', () {
    test('"chiefs for the next three nights" keeps "chiefs"', () {
      expect(parse('chiefs for the next three nights').lighting.trim(),
          'chiefs');
    });
    test('"warm white through sunday" keeps "warm white"', () {
      expect(parse('warm white through sunday').lighting.trim(), 'warm white');
    });
    test('"blue the next few nights" keeps "blue"', () {
      expect(parse('blue the next few nights').lighting.trim(), 'blue');
    });
  });

  group('negatives — must NOT parse as multi-night', () {
    test('"tonight" is one night', () {
      final p = parse('chiefs tonight');
      expect(p.days, 1);
      expect(p.rec, RecurrenceType.once);
    });
    test('"a night light look" carries no temporal signal', () {
      expect(parse('a night light look').compound, isFalse);
    });
    test('"friday night lights" is a team phrase, not a schedule', () {
      expect(parse('friday night lights').compound, isFalse);
    });
    test('"nights" alone is not a schedule', () {
      expect(parse('something for nights').compound, isFalse);
    });
    test('"next" alone is not a schedule', () {
      expect(parse('next pattern please').compound, isFalse);
    });
  });
}
