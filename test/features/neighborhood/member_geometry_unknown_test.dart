// #78 — join stopped fabricating geometry; the client stops pretending too.
//
// Every joining member was written `ledCount: 300, rooflineMeters: 15.0`. 300
// is the per-channel pixel cap reused as a default; 15.0 m is 49.2 ft, the
// figure customers saw in the UI. Neither was ever measured — and because they
// LOOKED like data, nothing downstream could tell a genuine 300-pixel home from
// a placeholder, so everything trusted a number nobody had checked.
//
// The client half had the same defaults again as `fromFirestore` fallbacks, so
// even a null-writing server would have been papered over on read.
//
// The rule: STORED values stop lying. Render-time code may assume a number, but
// it must be local, named, and never written back.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';

NeighborhoodMember member({int? leds, double? metres}) => NeighborhoodMember(
      oderId: 'u1',
      displayName: 'Test',
      positionIndex: 0,
      ledCount: leds,
      rooflineMeters: metres,
      lastSeen: DateTime(2026, 8, 14),
    );

void main() {
  group('the model no longer fabricates', () {
    test('an unspecified member is UNKNOWN, not 300 / 15.0', () {
      final m = member();
      expect(m.ledCount, isNull);
      expect(m.rooflineMeters, isNull);
    });

    // The fallback that would have defeated the server fix.
    test('fromFirestore does not invent values for absent fields', () {
      final m = NeighborhoodMember.fromMap('u1', const {
        'displayName': 'Test',
        'positionIndex': 0,
      });
      expect(m.ledCount, isNull);
      expect(m.rooflineMeters, isNull);
    });

    test('an explicit null from the server reads as unknown', () {
      final m = NeighborhoodMember.fromMap('u1', const {
        'displayName': 'Test',
        'positionIndex': 0,
        'ledCount': null,
        'rooflineMeters': null,
      });
      expect(m.ledCount, isNull);
      expect(m.rooflineMeters, isNull);
    });

    // A REAL 300 must still survive — the point is telling it apart from a
    // placeholder, not refusing the number.
    test('a genuinely measured 300 is preserved and distinguishable', () {
      final m = NeighborhoodMember.fromMap('u1', const {
        'displayName': 'Test',
        'positionIndex': 0,
        'ledCount': 300,
        'rooflineMeters': 15.0,
      });
      expect(m.ledCount, 300);
      expect(m.rooflineMeters, 15.0);
    });

    test('numeric widening is handled (Firestore ints vs doubles)', () {
      final m = NeighborhoodMember.fromMap('u1', const {
        'displayName': 'Test',
        'positionIndex': 0,
        'ledCount': 128,
        'rooflineMeters': 12, // int on the wire
      });
      expect(m.ledCount, 128);
      expect(m.rooflineMeters, 12.0);
    });
  });

  group('render-time assumption is local, named, and never stored', () {
    test('timing maths still works for an unmeasured home', () {
      final unknown = member();
      final known = member(leds: kAssumedLedCount);
      expect(
        unknown.animationDurationMs(50),
        known.animationDurationMs(50),
        reason: 'an unknown home falls back to the named assumption',
      );
    });

    test('a measured home uses its OWN count, not the assumption', () {
      expect(
        member(leds: 128).animationDurationMs(50),
        isNot(member(leds: kAssumedLedCount).animationDurationMs(50)),
      );
    });

    // THE DISTINCTION #78 IS ABOUT. Assuming for a calculation is fine.
    // Assuming into storage is what made the data untrustworthy.
    test('the assumption does not leak back into the stored value', () {
      final m = member();
      m.animationDurationMs(50);
      expect(m.ledCount, isNull, reason: 'rendering must not mutate the fact');
      expect(m.toFirestore()['ledCount'], isNull);
    });

    test('the assumption is a named constant, not a literal in the maths', () {
      expect(kAssumedLedCount, 300);
    });
  });
}
