// presetForAction routing — audit/BASE_LADDER.md §5d.
//
// Only PAYLOAD-LESS schedules reach this function. The three bugs fixed here
// were unreachable in the fleet only because every schedule happens to carry a
// wledPayload — the path was unguarded, not unreachable.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/cfg_payload_builder.dart';

void main() {
  group('recognised actions', () {
    test('Turn On → 1, Turn Off → 2', () {
      expect(presetForAction('Turn On'), 1);
      expect(presetForAction('Turn Off'), 2);
      expect(presetForAction('turn on'), 1);
      expect(presetForAction('  Turn Off  '), 2);
      expect(presetForAction('On'), 1);
      expect(presetForAction('Off'), 2);
    });

    test('Brightness: N% maps to the ladder by threshold', () {
      expect(presetForAction('Brightness: 20%'), 3);
      expect(presetForAction('Brightness: 25%'), 3);
      expect(presetForAction('Brightness: 40%'), 4);
      expect(presetForAction('Brightness: 45%'), 4);
      expect(presetForAction('Brightness: 60%'), 5);
      expect(presetForAction('Brightness: 70%'), 5);
      expect(presetForAction('Brightness: 100%'), 1);
    });

    test('brightness label variants the UI could emit', () {
      expect(presetForAction('Brightness 40%'), 4);
      expect(presetForAction('brightness:40'), 4);
    });
  });

  group('BUG 1 — contains(off) ran first and matched substrings', () {
    test('a design label containing "Off" is NOT the OFF action', () {
      // Live on two fleet accounts. Payload-less, the old code returned 2 and
      // would have turned the lights OFF at the schedule's ON boundary.
      expect(presetForAction('Pattern: 1 On 4 Off - Solid'), isNull);
      expect(presetForAction('Pattern: 3 On 2 Off - Solid'), isNull);
      expect(presetForAction('Off-Peak Glow'), isNull);
    });
  });

  group('BUG 2 — contains(on) ran before the pattern test', () {
    test('labels merely containing "on" do not become Turn On', () {
      for (final label in ['Neon Dream', 'Bronze Autumn', 'Monday Mood']) {
        expect(presetForAction(label), isNull, reason: '$label → macro 1');
      }
    });

    test('"Turn On The Lights" is a design name, not the Turn On action', () {
      expect(presetForAction('Turn On The Lights'), isNull);
    });
  });

  group('BUG 3 — the return 1 fallthrough', () {
    test('unrecognised labels REFUSE instead of arming the ladder', () {
      // Both exist in the fleet today; both used to land on macro 1.
      expect(presetForAction('Deep Blue'), isNull);
      expect(presetForAction('Warm White'), isNull);
      expect(presetForAction(''), isNull);
      expect(presetForAction('   '), isNull);
      expect(presetForAction('Christmas Twinkle'), isNull);
    });

    test('a bare "Brightness" with no percentage refuses (was: guessed Dim)',
        () {
      expect(presetForAction('Brightness'), isNull);
      expect(presetForAction('Brightness: '), isNull);
    });

    test('out-of-range percentages refuse rather than clamp', () {
      expect(presetForAction('Brightness: 150%'), isNull);
      expect(presetForAction('Brightness: 999%'), isNull);
    });
  });

  group('no label can silently reach the ON ladder', () {
    test('only explicit on/brightness actions ever return 1/3/4/5', () {
      const decoys = [
        'Deep Blue', 'Warm White', 'Neon Dream', 'Pattern: 1 On 4 Off - Solid',
        'Sunset Fade', 'Turn On The Lights', 'Brightness Boost', 'onward',
        'Halloween', 'Bonfire',
      ];
      for (final d in decoys) {
        final r = presetForAction(d);
        expect(r == null || r == 2, isTrue,
            reason: '"$d" resolved to $r — a decoy reached the ON ladder');
      }
    });
  });
}
