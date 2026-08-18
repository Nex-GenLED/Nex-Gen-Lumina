// +80 — the geometry pin at the wire exit.
//
// This is a PIN, not a unit test of a helper. Its job is to fail the day any
// apply path starts stating segment bounds again — the #76 → #88 → #89 → #95
// family, which four builder-shaped censuses each under-counted.
//
// The load-bearing case is `fails on a bounds-carrying DESIGN payload`: it is
// literally the payload shape that destroyed the bench's layout on +79 (seg 0
// re-bound to the full strip, seg 1 swallowed with its rev:true). If that test
// ever passes-by-not-detecting, the pin is broken.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/geometry_wire_pin.dart';

void main() {
  group('findGeometryViolations', () {
    test('DETECTS the +79 field-destruction payload shape', () {
      // The exact shape: seg 0 re-bound to the whole strip, seg 1 omitted.
      final payload = <String, dynamic>{
        'on': true,
        'bri': 255,
        'seg': [
          {'id': 0, 'start': 0, 'stop': 290, 'on': true, 'fx': 0, 'col': [[255, 0, 0, 0]]},
        ],
      };

      final v = findGeometryViolations(payload);

      expect(v, hasLength(1), reason: 'the bounds-carrying seg must be caught');
      expect(v.single.segId, 0);
      expect(v.single.keys, ['start', 'stop']);
    });

    test('DETECTS bounds on any seg, not just the first', () {
      final payload = <String, dynamic>{
        'seg': [
          {'id': 0, 'fx': 12},
          {'id': 1, 'start': 128, 'stop': 290},
        ],
      };
      final v = findGeometryViolations(payload);
      expect(v, hasLength(1));
      expect(v.single.index, 1);
      expect(v.single.segId, 1);
    });

    test('DETECTS a lone start with no stop (a half-stomp is still a stomp)', () {
      final v = findGeometryViolations({
        'seg': [
          {'id': 0, 'start': 0}
        ]
      });
      expect(v, hasLength(1));
      expect(v.single.keys, ['start']);
    });

    test('PASSES the applyChannelFilter full-partition output', () {
      // What a correct design apply looks like after #89: ids + on, no bounds.
      final payload = <String, dynamic>{
        'on': true,
        'seg': [
          {'id': 0, 'fx': 88, 'pal': 5, 'on': true},
          {'id': 1, 'on': false},
        ],
      };
      expect(findGeometryViolations(payload), isEmpty);
    });

    test('PASSES buildChannelPowerPayload Case 3 (id-only enumeration)', () {
      expect(
        findGeometryViolations({
          'on': true,
          'seg': [
            {'id': 0, 'on': true},
            {'id': 1, 'on': false},
          ],
        }),
        isEmpty,
      );
    });

    test('IGNORES len — WLED echoes it on readback and it cannot move a bound', () {
      expect(
        findGeometryViolations({
          'seg': [
            {'id': 0, 'len': 128, 'on': true}
          ]
        }),
        isEmpty,
      );
    });

    test('never invents a violation from a shape it does not understand', () {
      expect(findGeometryViolations({'on': false}), isEmpty);
      expect(findGeometryViolations({'seg': 'nonsense'}), isEmpty);
      expect(findGeometryViolations({'seg': []}), isEmpty);
      expect(findGeometryViolations({'seg': [null, 7]}), isEmpty);
    });
  });

  group('stripGeometry — the RELEASE protection', () {
    test('removes bounds and preserves everything else exactly', () {
      final before = <String, dynamic>{
        'on': true,
        'bri': 200,
        'seg': [
          {
            'id': 0,
            'start': 0,
            'stop': 290,
            'fx': 52,
            'sx': 160,
            'col': [[255, 0, 0, 0]],
            'on': true,
          },
        ],
      };

      final after = stripGeometry(before);
      final seg = (after['seg'] as List).single as Map;

      expect(seg.containsKey('start'), isFalse);
      expect(seg.containsKey('stop'), isFalse);
      // Everything else survives, untouched.
      expect(seg['id'], 0);
      expect(seg['fx'], 52);
      expect(seg['sx'], 160);
      expect(seg['col'], [[255, 0, 0, 0]]);
      expect(seg['on'], true);
      expect(after['on'], true);
      expect(after['bri'], 200);
      expect(findGeometryViolations(after), isEmpty);
    });

    test('does not mutate the caller\'s payload', () {
      final before = <String, dynamic>{
        'seg': [
          {'id': 0, 'start': 0, 'stop': 290}
        ]
      };
      stripGeometry(before);
      expect((before['seg'] as List).single, containsPair('stop', 290),
          reason: 'the pin must not mutate its input');
    });

    test('returns the SAME instance when there is nothing to strip', () {
      final clean = <String, dynamic>{
        'seg': [
          {'id': 0, 'on': true}
        ]
      };
      expect(identical(stripGeometry(clean), clean), isTrue,
          reason: 'the hot path must not pay a copy');
    });

    test('preserves seg ORDER and arity — an excluded seg is never dropped', () {
      final after = stripGeometry({
        'seg': [
          {'id': 0, 'start': 0, 'stop': 128},
          {'id': 1, 'on': false},
          {'id': 2, 'start': 290, 'stop': 400},
        ],
      });
      final seg = after['seg'] as List;
      expect(seg, hasLength(3));
      expect((seg[0] as Map)['id'], 0);
      expect((seg[1] as Map)['id'], 1);
      expect((seg[2] as Map)['id'], 2);
    });
  });

  group('pinNoGeometryOnWire', () {
    test('clean payload passes through untouched and reports nothing', () {
      final clean = <String, dynamic>{
        'seg': [
          {'id': 0, 'fx': 88, 'on': true}
        ]
      };
      final seen = <String>[];
      final out = pinNoGeometryOnWire(clean,
          caller: 'test', onViolation: seen.add);
      expect(identical(out, clean), isTrue);
      expect(seen, isEmpty);
    });

    test('a bounds-carrying payload REPORTS and is stripped', () {
      final dirty = <String, dynamic>{
        'seg': [
          {'id': 0, 'start': 0, 'stop': 290, 'fx': 0}
        ]
      };
      final seen = <String>[];

      // The assert fires in debug — that IS the pin. Catch it so the test can
      // also verify the release-path behaviour (report + strip) in one place.
      Map<String, dynamic>? out;
      try {
        out = pinNoGeometryOnWire(dirty, caller: 'test', onViolation: seen.add);
      } on AssertionError {
        out = stripGeometry(dirty);
      }

      expect(seen, hasLength(1), reason: 'the violation must be reported');
      expect(seen.single, contains('GEOMETRY ON THE WIRE'));
      expect(seen.single, contains('seg[0](id=0):start+stop'));
      expect(findGeometryViolations(out!), isEmpty,
          reason: 'bounds must not survive the pin');
      expect((out['seg'] as List).single, containsPair('fx', 0),
          reason: 'the LOOK must survive — only the SHAPE is removed');
    });
  });

  // ── ORIENTATION (added 2026-08-18) ──────────────────────────────────────
  //
  // THE INCIDENT THESE PIN: on +80, with the wire pin live and passing, `rev`
  // was cleared on the bench's seg 1 TWICE in one evening. The pin was never
  // routed around — `kGeometryKeys` was `['start','stop']`, so it simply never
  // looked at `rev`. A reversed channel silently flipped direction: the exact
  // failure bounds were fenced for, in the one axis the fence did not cover.
  //
  // A test's value is its ability to fail. Removing 'rev' or 'mi' from
  // kGeometryKeys fails these.
  group('orientation is geometry too', () {
    test("catches tonight's exact payload — {'id':1,'rev':false}", () {
      final dirty = <String, dynamic>{
        'seg': [
          {'id': 1, 'rev': false}
        ]
      };
      final seen = <String>[];
      Map<String, dynamic>? out;
      try {
        out = pinNoGeometryOnWire(dirty, caller: 'test', onViolation: seen.add);
      } on AssertionError {
        out = stripGeometry(dirty);
      }

      expect(seen, hasLength(1));
      // seg[0] is the ARRAY INDEX; (id=1) is the segment id. The payload has
      // one entry, so index 0 carries id 1.
      expect(seen.single, contains('seg[0](id=1):rev'));
      expect((out!['seg'] as List).single, isNot(contains('rev')),
          reason: 'rev must not reach the wire from an apply');
      expect((out['seg'] as List).single, containsPair('id', 1),
          reason: 'the seg must survive — only its orientation is removed');
    });

    test('rev:TRUE is stripped too — a payload may not assert direction in '
        'EITHER direction', () {
      // The #4 lesson, applied to orientation: "omit when false" was a partial
      // fix for bounds and would be a partial fix here. Asserting rev:true over
      // a device the installer wired forward is the same defect mirrored.
      expect(
        findGeometryViolations({
          'seg': [
            {'id': 1, 'rev': true}
          ]
        }),
        hasLength(1),
      );
    });

    test('mirror (mi) is fenced on the same reasoning', () {
      expect(
        findGeometryViolations({
          'seg': [
            {'id': 0, 'mi': true}
          ]
        }),
        hasLength(1),
      );
    });

    test('bounds and orientation together are reported as one violation, '
        'naming every offending key', () {
      final v = findGeometryViolations({
        'seg': [
          {'id': 1, 'start': 128, 'stop': 290, 'rev': false, 'mi': false}
        ]
      });
      expect(v, hasLength(1));
      expect(v.single.toString(), 'seg[0](id=1):start+stop+rev+mi');
    });

    test('a pure LOOK payload is still untouched — the fence has not widened '
        'onto colour, effect or speed', () {
      // Guards the other direction: over-fencing would break every ordinary
      // apply, which is a worse outcome than the leak being fixed.
      expect(
        findGeometryViolations({
          'seg': [
            {'id': 0, 'fx': 27, 'sx': 128, 'ix': 200, 'pal': 5, 'on': true}
          ]
        }),
        isEmpty,
      );
    });

    test('len is STILL exempt — readback echoes must not trip on a derived '
        'convenience field', () {
      expect(
        findGeometryViolations({
          'seg': [
            {'id': 0, 'len': 128}
          ]
        }),
        isEmpty,
      );
    });
  });
}
