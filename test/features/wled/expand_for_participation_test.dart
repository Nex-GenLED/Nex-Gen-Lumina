// Paranoid tests for expandForParticipation — the single-chokepoint
// participation-expansion function (audit #4, Bundle 3b.1).
//
// The discriminator is the safety case for the chokepoint. Every real
// payload shape that flows through WledService.applyJson must classify
// correctly: either EXPAND (broadcast intent — single-seg, no id, has fx)
// or PASS-THROUGH (anything else).
//
// Shapes used in these tests are taken VERBATIM from the audited sites
// (game_day_screen, scene_models, sports_alert_service for EXPAND;
// lumina_custom_effects, pattern_adjustment_panel, voice_providers for
// PASS-THROUGH; buildParticipatingSegArray for the double-expansion
// guard).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

void main() {
  group('expandForParticipation — PASS-THROUGH (rule 1: null)', () {
    test('participating == null returns payload unchanged', () {
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 0, 'sx': 128, 'ix': 128, 'pal': 0, 'col': [[255, 0, 0, 0]]},
        ],
      };
      final result = expandForParticipation(payload, null);
      expect(result, equals(payload));
    });
  });

  group('expandForParticipation — PASS-THROUGH (rule 2: empty list)', () {
    test('participating == [] returns payload unchanged', () {
      // Caller's "explicit none" — they must skip-apply at their layer.
      // The chokepoint does NOT emit an empty seg array.
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 28, 'sx': 200, 'ix': 128, 'pal': 0, 'col': [[0, 255, 0, 0]]},
        ],
      };
      final result = expandForParticipation(payload, const []);
      expect(result, equals(payload));
    });
  });

  group('expandForParticipation — PASS-THROUGH (rule 3: no seg)', () {
    test('top-level only {on:false} (voice off) unchanged', () {
      final payload = {'on': false};
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });

    test('top-level only {on:true, bri:N} (voice brightness) unchanged', () {
      final payload = {'on': true, 'bri': 200};
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });

    test('preset select {ps:N} (alert preset restore) unchanged', () {
      final payload = {'ps': 3};
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });

    test('reboot {rb:true} unchanged', () {
      final payload = {'rb': true};
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });

    test('UDP config {udpn:...} unchanged', () {
      final payload = {
        'udpn': {'send': true, 'recv': false},
      };
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });

    test('seg present but not a List (corrupt) unchanged', () {
      final payload = {'on': true, 'seg': 'not-a-list'};
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });

    test('seg present as empty List unchanged', () {
      final payload = {'on': true, 'seg': <Map<String, dynamic>>[]};
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });
  });

  group('expandForParticipation — PASS-THROUGH (rule 4: multi-seg)', () {
    test(
        'multi-seg pixel-range animation (rising-tide frame from '
        'lumina_custom_effects) unchanged', () {
      final payload = {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'start': 0,
            'stop': 64,
            'on': true,
            'col': [
              [255, 100, 0, 0],
            ],
            'fx': 0,
          },
          {
            'id': 1,
            'start': 64,
            'stop': 128,
            'on': true,
            'col': [
              [0, 0, 0, 0],
            ],
            'fx': 0,
          },
        ],
      };
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });

    test('multi-seg with three entries unchanged regardless of ids', () {
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'fx': 28, 'col': [[255, 0, 0, 0]]},
          {'id': 1, 'fx': 28, 'col': [[0, 255, 0, 0]]},
          {'id': 2, 'fx': 28, 'col': [[0, 0, 255, 0]]},
        ],
      };
      expect(expandForParticipation(payload, const [0]), equals(payload));
    });
  });

  group('expandForParticipation — PASS-THROUGH (rule 5: single-seg with id)',
      () {
    test('single-seg WITH explicit id (voice {id:0, fx:0}) unchanged', () {
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'fx': 0},
        ],
      };
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });

    test('single-seg with id and full pattern fields unchanged', () {
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'id': 1,
            'fx': 28,
            'sx': 160,
            'ix': 128,
            'pal': 0,
            'col': [[0, 0, 255, 0]],
          },
        ],
      };
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });
  });

  group('expandForParticipation — PASS-THROUGH (rule 6: no fx — partial update)',
      () {
    test(
        'slider tweak sx/ix/rev (pattern_adjustment_panel debounced apply) '
        'unchanged', () {
      final payload = {
        'seg': [
          {'sx': 200, 'ix': 128, 'rev': true},
        ],
      };
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });

    test(
        'layout tweak grp/spc (pattern_adjustment_panel layout apply) '
        'unchanged', () {
      final payload = {
        'seg': [
          {'grp': 3, 'spc': 1},
        ],
      };
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });

    test('col-only partial update without fx unchanged', () {
      final payload = {
        'seg': [
          {'col': [[255, 255, 255, 0]]},
        ],
      };
      expect(expandForParticipation(payload, const [0, 1]), equals(payload));
    });
  });

  group('expandForParticipation — EXPAND (rule 7: single-seg, no id, has fx)',
      () {
    test(
        'game_day_screen.dart Light Up Now: 2-color RGBW broadcast → 2 segs '
        'each with on:true', () {
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'fx': 52,
            'sx': 160,
            'ix': 128,
            'pal': 0,
            'col': [
              [255, 0, 0, 0],
              [0, 255, 0, 0],
            ],
          },
        ],
      };
      final result = expandForParticipation(payload, const [0, 1]);
      final segs = result['seg'] as List;
      expect(segs, hasLength(2));
      expect(segs[0]['id'], 0);
      expect(segs[1]['id'], 1);
      expect(segs.every((s) => s['on'] == true), isTrue);
      // Top-level preserved
      expect(result['on'], true);
      expect(result['bri'], 200);
    });

    test('every expanded seg preserves all template fields', () {
      final payload = {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': 88,
            'sx': 200,
            'ix': 230,
            'pal': 0,
            'col': [[255, 0, 0, 0]],
          },
        ],
      };
      final result = expandForParticipation(payload, const [0, 1]);
      final segs = result['seg'] as List;
      for (final s in segs) {
        expect(s['fx'], 88);
        expect(s['sx'], 200);
        expect(s['ix'], 230);
        expect(s['pal'], 0); // pal preserved — don't drop it
        expect(s['col'], equals([[255, 0, 0, 0]]));
        expect(s['on'], true);
      }
    });

    test('single-channel participating [1] → one seg id 1 with on:true', () {
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 0, 'sx': 128, 'ix': 128, 'pal': 0, 'col': [[255, 180, 100, 255]]},
        ],
      };
      final result = expandForParticipation(payload, const [1]);
      final segs = result['seg'] as List;
      expect(segs, hasLength(1));
      expect(segs.first['id'], 1);
      expect(segs.first['on'], true);
      expect(segs.first['col'], equals([[255, 180, 100, 255]]));
    });

    test('participating [0,1,2,3] → four segs in order', () {
      final payload = {
        'on': true,
        'bri': 100,
        'seg': [
          {'fx': 28, 'sx': 128, 'ix': 128, 'col': [[100, 100, 100, 0]]},
        ],
      };
      final result = expandForParticipation(payload, const [0, 1, 2, 3]);
      final segs = result['seg'] as List;
      expect(segs.map((s) => s['id']).toList(), equals([0, 1, 2, 3]));
      expect(segs.every((s) => s['on'] == true), isTrue);
    });

    test('RGBW col verbatim across expanded segs (no rewriting)', () {
      const col = [
        [10, 20, 30, 0],
        [40, 50, 60, 0],
      ];
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 28, 'sx': 160, 'ix': 128, 'pal': 0, 'col': col},
        ],
      };
      final result = expandForParticipation(payload, const [0, 1]);
      for (final s in (result['seg'] as List)) {
        expect(s['col'], equals(col));
      }
    });

    test('input payload is NOT mutated (returns a new map)', () {
      final input = {
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 0, 'col': [[255, 0, 0, 0]]},
        ],
      };
      final inputSegOriginal = List.of(input['seg'] as List);
      expandForParticipation(input, const [0, 1]);
      expect((input['seg'] as List), equals(inputSegOriginal));
      expect((input['seg'] as List), hasLength(1));
    });
  });

  group('expandForParticipation — DOUBLE-EXPANSION GUARD', () {
    test(
        'Bundle 3 buildParticipatingSegArray output (multi-seg with ids) '
        'passes through unchanged — no double-expansion when chokepoint runs '
        'over a Bundle 3 payload', () {
      // Construct a payload identical to what Bundle 3 wired paths emit:
      // {'on': true, 'bri': X, 'seg': buildParticipatingSegArray(...)}
      final segs = buildParticipatingSegArray(
        participatingChannelIds: const [0, 1],
        effectId: 28,
        speed: 160,
        intensity: 128,
        colorSlots: const [[255, 0, 0, 0]],
      );
      final payload = {'on': true, 'bri': 200, 'seg': segs};
      final result = expandForParticipation(payload, const [0, 1]);
      expect(result, equals(payload));
    });

    test(
        'corner case: buildParticipatingSegArray output with ONE channel '
        '(seg.length == 1, but seg.first HAS id) still passes through', () {
      final segs = buildParticipatingSegArray(
        participatingChannelIds: const [1],
        effectId: 0,
        speed: 128,
        intensity: 128,
        colorSlots: const [[0, 0, 255, 0]],
      );
      final payload = {'on': true, 'bri': 200, 'seg': segs};
      final result = expandForParticipation(payload, const [0, 1]);
      expect(result, equals(payload));
      // Rule 5 (seg.first has id) catches this — verify:
      expect((result['seg'] as List).first['id'], 1);
    });
  });

  group('expandForParticipation — IDEMPOTENCY', () {
    test(
        'expandForParticipation(expandForParticipation(p)) == '
        'expandForParticipation(p) — expanding twice equals expanding once', () {
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 28, 'sx': 160, 'ix': 128, 'pal': 0, 'col': [[255, 0, 0, 0]]},
        ],
      };
      final once = expandForParticipation(payload, const [0, 1]);
      final twice = expandForParticipation(once, const [0, 1]);
      expect(twice, equals(once));
    });

    test('idempotency holds even with a different participating list on 2nd pass',
        () {
      // First pass expands to [0,1]. Second pass with [0] alone: since the
      // first pass produced multi-seg-with-ids, rule 4 catches it and
      // passes through unchanged regardless of the new participating list.
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 0, 'col': [[255, 0, 0, 0]]},
        ],
      };
      final once = expandForParticipation(payload, const [0, 1]);
      final twice = expandForParticipation(once, const [0]);
      expect(twice, equals(once));
    });
  });
}
