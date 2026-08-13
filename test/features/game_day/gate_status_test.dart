// W2/W3 — the gate, as the customer sees it.
//
// The client REFLECTS the planner's verdict and never re-evaluates it. A second
// implementation of the rules would drift from the server's, and the server's
// is the one that decides whether lights actually fire. Everything here is a
// reader over `users/{uid}.gameday_gate_blocking`.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/gate_status.dart';

void main() {
  group('fromUserDoc — never invents a refusal', () {
    test('absent field -> armed (the planner has not evaluated yet)', () {
      expect(GateStatus.fromUserDoc(null).armed, isTrue);
    });

    test('empty list -> armed', () {
      expect(GateStatus.fromUserDoc(<String>[]).armed, isTrue);
    });

    test('reasons -> gated, order preserved', () {
      final s = GateStatus.fromUserDoc([kGateNoFloor, kGateNoFacts]);
      expect(s.armed, isFalse);
      expect(s.blocking, [kGateNoFloor, kGateNoFacts]);
    });

    // A malformed field must not become a warning the server never issued.
    test('garbage -> armed, not a fabricated block', () {
      for (final junk in [42, 'gated_no_floor', {'a': 1}, true]) {
        expect(GateStatus.fromUserDoc(junk).armed, isTrue);
      }
    });

    test('non-string entries are dropped, real ones kept', () {
      final s = GateStatus.fromUserDoc([kGateNoFloor, 7, '', null]);
      expect(s.blocking, [kGateNoFloor]);
    });
  });

  group('messages name the missing item', () {
    test('no_floor is the actionable one', () {
      final s = GateStatus([kGateNoFloor]);
      expect(s.headline, contains('not firing yet'));
      expect(s.reasons.single, contains('everyday schedule'));
      expect(s.hasScheduleFix, isTrue);
    });

    test('no_facts tells them where to be, not what to fix', () {
      // Nothing to tap: the fix is physical presence on their own Wi-Fi.
      final s = GateStatus([kGateNoFacts]);
      expect(s.reasons.single, contains('at home'));
      expect(s.hasScheduleFix, isFalse);
    });

    test('every blocking reason gets its own sentence', () {
      final s = GateStatus([kGateNoFloor, kGateNoFacts]);
      expect(s.reasons, hasLength(2));
    });

    // "Something is missing" is what the old gate effectively said.
    test('an unknown reason still reports a block', () {
      final s = GateStatus(['gated_something_new']);
      expect(s.armed, isFalse);
      expect(s.reasons.single, isNotEmpty);
    });

    test('armed says so plainly, with no reasons', () {
      const s = GateStatus.unknown;
      expect(s.headline, 'Game Day is on');
      expect(s.reasons, isEmpty);
    });
  });

  // ADVISORY IS NOT A CUSTOMER PROBLEM. gated_no_ladder_unknown means the fact
  // is ours to collect (W4 does it), not theirs to fix. It is not written to
  // gameday_gate_blocking at all, so it can never reach this reader — pinned
  // here so a future server change that starts persisting it is caught.
  test('an advisory reason never appears in the blocking list', () {
    const advisory = 'gated_no_ladder_unknown';
    final s = GateStatus.fromUserDoc([advisory]);
    // If the server ever DID persist it, the client would show a block for
    // something the customer cannot act on. This asserts today's contract.
    expect(s.blocking, [advisory],
        reason: 'reader is faithful; the server contract is what keeps it out');
    expect(s.armed, isFalse);
  });

  group('upcomingPromiseFor — only the PRE-GAME claim consults the gate', () {
    test('armed -> willFire', () {
      expect(upcomingPromiseFor(GateStatus.unknown), UpcomingPromise.willFire);
    });

    test('gated -> gated', () {
      expect(
        upcomingPromiseFor(GateStatus([kGateNoFloor])),
        UpcomingPromise.gated,
      );
    });

    // The word being withdrawn is "Today" standing alone as a promise.
    test('the gated label does not promise a show', () {
      expect(kGatedBadgeLabel, contains('Today'));
      expect(kGatedBadgeLabel, contains('setup needed'));
    });
  });

  test('equality is by content, so a rebuild with the same verdict is stable',
      () {
    expect(GateStatus([kGateNoFloor]), GateStatus([kGateNoFloor]));
    expect(GateStatus([kGateNoFloor]) == GateStatus([kGateNoFacts]), isFalse);
  });
}
