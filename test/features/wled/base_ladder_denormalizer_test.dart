// W4 / R2 — the base-ladder fact the Game Day gate has been missing.
//
// The gate (functions/src/gameDayGate.ts) reads
// `base_ladder_asserts_segments` as a TRI-STATE: absent is
// unknown-and-allowed, `false` fails CLOSED into log-only, `true` passes.
// Nothing published it, so every one of the ten accounts evaluates to
// unknown. This family is what starts hardening R2, one customer at a time,
// as each opens the app on their LAN — no server change required.
//
// WHAT IT MEASURES. #67 makes an excluded channel go dark for an event, and the
// end-of-event restore is a PRESET LOAD. If that preset does not assert `on`
// for every segment, the channel stays dark afterwards — the exclusion leaks
// past the event that asked for it. Presets 1 and 2 are the only two
// `baseRestorePayload` can load, so they are the only two that matter.
//
// The failure is real and observed: the ladder has been seen psaving with NO
// `seg` key at all (audit/BASE_LADDER.md). The bench was repaired 2026-08-09,
// which is exactly why this must be measured per account and not assumed.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/base_ladder_denormalizer.dart';

/// A preset asserting `on` for the given ids.
Map<String, dynamic> good(List<int> ids, {bool on = true}) => {
      'seg': [
        for (final id in ids) {'id': id, 'on': on, 'fx': 0},
      ],
    };

Map<int, Map<String, dynamic>> ladder(List<int> ids) => {
      1: good(ids),
      2: good(ids, on: false),
    };

const twoBus = <int>[0, 1];

void main() {
  setUp(resetBaseLadderMemo);

  group('presetAssertsAllChannels', () {
    test('every channel with an explicit on -> true', () {
      expect(presetAssertsAllChannels(good(twoBus), twoBus), isTrue);
    });

    // THE OBSERVED FAILURE. A preset psaved with no seg key at all.
    test('no seg key -> false', () {
      expect(presetAssertsAllChannels({'on': true, 'bri': 200}, twoBus), isFalse);
    });

    test('empty seg -> false', () {
      expect(presetAssertsAllChannels({'seg': []}, twoBus), isFalse);
    });

    test('a MISSING channel -> false', () {
      // seg0 asserted, seg1 absent: the restore would leave seg1 wherever the
      // event left it. That is the leak.
      expect(presetAssertsAllChannels(good([0]), twoBus), isFalse);
    });

    // A segment present but SILENT about `on` is the inherited-state case #67
    // exists to eliminate, so it is not good enough.
    test('a segment without an explicit on -> false', () {
      final silent = {
        'seg': [
          {'id': 0, 'on': true},
          {'id': 1, 'fx': 3}, // no `on`
        ],
      };
      expect(presetAssertsAllChannels(silent, twoBus), isFalse);
    });

    test('on:false still counts as asserted — off is a state, not a silence', () {
      expect(presetAssertsAllChannels(good(twoBus, on: false), twoBus), isTrue);
    });

    test('a null preset -> false', () {
      expect(presetAssertsAllChannels(null, twoBus), isFalse);
    });

    test('extra channels beyond the device are harmless', () {
      expect(presetAssertsAllChannels(good([0, 1, 2, 3]), twoBus), isTrue);
    });
  });

  group('ladderAssertsSegments — tri-state', () {
    test('both restore presets good -> true', () {
      expect(
        ladderAssertsSegments(presets: ladder(twoBus), deviceChannelIds: twoBus),
        isTrue,
      );
    });

    test('preset 1 bad -> false', () {
      final l = ladder(twoBus)..[1] = {'on': true};
      expect(ladderAssertsSegments(presets: l, deviceChannelIds: twoBus), isFalse);
    });

    test('preset 2 bad -> false', () {
      final l = ladder(twoBus)..[2] = {'on': false};
      expect(ladderAssertsSegments(presets: l, deviceChannelIds: twoBus), isFalse);
    });

    test('a MISSING restore preset -> false', () {
      final l = ladder(twoBus)..remove(2);
      expect(ladderAssertsSegments(presets: l, deviceChannelIds: twoBus), isFalse);
    });

    test('presets 3/4/5 are irrelevant — a restore never lands there', () {
      final l = ladder(twoBus)
        ..[3] = {'on': true}
        ..[4] = {'seg': []};
      expect(ladderAssertsSegments(presets: l, deviceChannelIds: twoBus), isTrue);
    });

    // THE ASYMMETRY THAT MATTERS. `false` puts an account into log-only. "We
    // could not look" must never produce it, or a failed HTTP GET gates the
    // fleet.
    test('unreadable presets -> NULL, never false', () {
      expect(
        ladderAssertsSegments(presets: null, deviceChannelIds: twoBus),
        isNull,
      );
    });

    test('unknown device shape -> NULL, never false', () {
      expect(
        ladderAssertsSegments(presets: ladder(twoBus), deviceChannelIds: const []),
        isNull,
      );
    });
  });

  group('prepareBaseLadderFacts — publish discipline', () {
    test('a known verdict publishes the boolean and its stamps', () {
      final f = prepareBaseLadderFacts(
        controllerId: 'c1',
        verdict: true,
        source: 'healer',
      );
      expect(f.isEmpty, isFalse);
      expect(f.fields[kBaseLadderAssertsSegmentsField], isTrue);
      expect(f.fields.containsKey('${kBaseLadderAssertsSegmentsField}_at'), isTrue);
      expect(f.fields['${kBaseLadderAssertsSegmentsField}_source'], 'healer');
    });

    test('an UNKNOWN verdict contributes nothing', () {
      expect(
        prepareBaseLadderFacts(controllerId: 'c1', verdict: null, source: 'healer')
            .isEmpty,
        isTrue,
      );
    });

    // THE ZERO-MUTATION GUARANTEE. A healthy controller reconnecting must
    // produce no write from this family. The #67 disposition mirror nearly
    // broke the equivalent guarantee by stamping unconditionally; this pins it.
    test('SECOND CONNECT with an unchanged verdict writes NOTHING', () {
      final first = prepareBaseLadderFacts(
        controllerId: 'c1',
        verdict: true,
        source: 'healer',
      );
      expect(first.isEmpty, isFalse);
      first.commit();

      final second = prepareBaseLadderFacts(
        controllerId: 'c1',
        verdict: true,
        source: 'healer',
      );
      expect(second.isEmpty, isTrue, reason: 'dedup must suppress the rewrite');
    });

    test('a CHANGED verdict publishes again, carrying the previous value', () {
      prepareBaseLadderFacts(controllerId: 'c1', verdict: true, source: 'healer')
          .commit();
      final f = prepareBaseLadderFacts(
        controllerId: 'c1',
        verdict: false,
        source: 'healer',
      );
      expect(f.isEmpty, isFalse);
      expect(f.fields[kBaseLadderAssertsSegmentsField], isFalse);
      expect(f.fields['${kBaseLadderAssertsSegmentsField}_previous'], isTrue);
    });

    // A failed write must not poison the memo into suppressing the retry —
    // which is why commit() is separate from prepare().
    test('preparing WITHOUT committing leaves the retry available', () {
      prepareBaseLadderFacts(controllerId: 'c1', verdict: true, source: 'healer');
      expect(
        prepareBaseLadderFacts(controllerId: 'c1', verdict: true, source: 'healer')
            .isEmpty,
        isFalse,
      );
    });

    test('the memo is per controller', () {
      prepareBaseLadderFacts(controllerId: 'c1', verdict: true, source: 'healer')
          .commit();
      expect(
        prepareBaseLadderFacts(controllerId: 'c2', verdict: true, source: 'healer')
            .isEmpty,
        isFalse,
      );
    });
  });

  group('the bench, and the fleet it does not represent', () {
    test('the repaired bench ladder reads TRUE', () {
      // .150 as read 2026-08-13: presets 1 and 2 both (0,on)+(1,on).
      expect(
        ladderAssertsSegments(presets: ladder(twoBus), deviceChannelIds: twoBus),
        isTrue,
      );
    });

    test('the pre-repair shape reads FALSE — psave with no seg key', () {
      final broken = <int, Map<String, dynamic>>{
        1: {'on': true, 'bri': 200},
        2: {'on': false},
      };
      expect(
        ladderAssertsSegments(presets: broken, deviceChannelIds: twoBus),
        isFalse,
      );
    });
  });
}
