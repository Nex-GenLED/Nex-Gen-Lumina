// test/features/wled/frozen_segment_fix_test.dart
//
// FROZEN SEGMENT — audit/FROZEN_SEGMENT.md, audit/FROZEN_SEGMENT_FIX.md.
//
// BENCH-PROVEN on 192.168.1.150 (WLED 0.15.1, vid 2507300): a per-pixel write
// ({"seg":[{"id":0,"i":[...]}]}) sets seg.frz = true. A FROZEN SEGMENT DOES NOT
// RUN ITS EFFECT, so every subsequent segment-level colour/effect write is
// stored, answers HTTP 200, reads back correctly from /json/state — and never
// reaches the LEDs. The app never sent `frz` at all, so the freeze persisted
// until a preset load or a reboot cleared it.
//
// TWO fixes, both pinned here:
//   FIX 1 — normalizeWledPayload clears frz on every seg entry that is NOT a
//           per-pixel write. One chokepoint; both repositories and savePreset
//           funnel through it (~66 applyJson call sites inherit it).
//   FIX 2 — ensurePsaveClearsFreeze stops a psave capturing frz:true. This is
//           the DURABLE half: a live freeze clears on the next segment write or
//           a reboot, but a poisoned preset re-freezes on EVERY load until it is
//           re-saved. The ON-preset states are seg-LESS, which is exactly the
//           gap fix 1 cannot see.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

void main() {
  List<Map<String, dynamic>> segsOf(Map<String, dynamic> p) =>
      (p['seg'] as List).cast<Map<String, dynamic>>();

  group('FIX 1 — normalizeWledPayload clears the freeze on segment writes', () {
    test('a plain segment colour write gets frz:false', () {
      final out = normalizeWledPayload({
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0, 'col': [[255, 0, 0, 0]]},
        ],
      });
      expect(segsOf(out).single['frz'], isFalse);
    });

    test('a PER-PIXEL write is left alone — it re-freezes by design', () {
      final out = normalizeWledPayload({
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0, 'i': [100, [0, 229, 255, 0]]},
        ],
      });
      expect(segsOf(out).single.containsKey('frz'), isFalse,
          reason: 'clearing frz on a per-pixel write would fight the paint it '
              'is about to perform');
    });

    test('mixed multi-seg: only the non-per-pixel entries are cleared', () {
      final out = normalizeWledPayload({
        'seg': [
          {'id': 0, 'i': [5, [1, 2, 3, 0]]},
          {'id': 1, 'fx': 0, 'col': [[0, 255, 0, 0]]},
        ],
      });
      final segs = segsOf(out);
      expect(segs[0].containsKey('frz'), isFalse);
      expect(segs[1]['frz'], isFalse);
    });

    test('an explicit frz:true from a caller is overridden', () {
      // Nothing in lib/ writes frz, so this can only be stale/foreign data.
      final out = normalizeWledPayload({
        'seg': [
          {'id': 0, 'fx': 0, 'frz': true},
        ],
      });
      expect(segsOf(out).single['frz'], isFalse);
    });

    test('a payload with no seg is untouched (root-only write)', () {
      final out = normalizeWledPayload({'on': true, 'bri': 128});
      expect(out.containsKey('seg'), isFalse);
      expect(out['bri'], 128);
    });

    test('a partial slider tweak still clears frz', () {
      // No fx — the default-injection branch is skipped, but this is still a
      // segment-level write that means "render this".
      final out = normalizeWledPayload({
        'seg': [
          {'id': 0, 'sx': 200},
        ],
      });
      expect(segsOf(out).single['frz'], isFalse);
    });
  });

  group('FIX 2 — ensurePsaveClearsFreeze stops a poisoned preset', () {
    test('seg-LESS ON-preset state gets a freeze-clearing seg array', () {
      // The exact shape of presets 1/3/4/5 — the ones schedules fire.
      const onPreset = {'on': true, 'bri': 51, 'ib': true};

      final out = ensurePsaveClearsFreeze(onPreset, [0, 1]);

      expect(segsOf(out), [
        {'id': 0, 'frz': false},
        {'id': 1, 'frz': false},
      ]);
      // Everything the caller asked for survives — this must not become a
      // colour write.
      expect(out['on'], isTrue);
      expect(out['bri'], 51);
      expect(out['ib'], isTrue);
    });

    test('the synthesized entry touches ONLY frz', () {
      final out = ensurePsaveClearsFreeze({'on': true}, [0]);
      expect(segsOf(out).single.keys.toSet(), {'id', 'frz'},
          reason: 'any extra key would overwrite live colour/effect state that '
              'the psave is supposed to capture');
    });

    test('null participating falls back to segment 0', () {
      final out = ensurePsaveClearsFreeze({'on': true}, null);
      expect(segsOf(out), [
        {'id': 0, 'frz': false}
      ]);
    });

    test('empty participating falls back to segment 0', () {
      final out = ensurePsaveClearsFreeze({'on': true}, const []);
      expect(segsOf(out), [
        {'id': 0, 'frz': false}
      ]);
    });

    test('a state that ALREADY has seg is returned untouched', () {
      // normalizeWledPayload runs first and has already cleared frz there;
      // synthesizing over it would clobber the caller's real segment state.
      final withSeg = {
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0, 'col': [[1, 2, 3, 0]], 'frz': false},
        ],
      };
      final out = ensurePsaveClearsFreeze(withSeg, [0, 1]);
      expect(identical(out, withSeg), isTrue);
    });

    test('does not mutate the caller\'s map', () {
      final input = <String, dynamic>{'on': true};
      ensurePsaveClearsFreeze(input, [0]);
      expect(input.containsKey('seg'), isFalse);
    });
  });

  group('the two fixes compose the way savePreset calls them', () {
    test('seg-LESS state: normalize is a no-op, ensure adds the clear', () {
      const state = {'on': true, 'bri': 102, 'ib': true};
      final out = ensurePsaveClearsFreeze(normalizeWledPayload(state), [0, 1]);
      expect(segsOf(out).every((s) => s['frz'] == false), isTrue);
    });

    test('seg-BEARING state: normalize clears, ensure leaves it alone', () {
      final state = {
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0, 'col': [[255, 170, 80, 0]]},
        ],
      };
      final out = ensurePsaveClearsFreeze(normalizeWledPayload(state), [0, 1]);
      final segs = segsOf(out);
      expect(segs.length, 1, reason: 'ensure must not fan a real seg array out');
      expect(segs.single['frz'], isFalse);
      expect(segs.single['fx'], 0);
    });

    test('a per-pixel payload survives both untouched', () {
      final state = {
        'seg': [
          {'id': 0, 'i': [7, [9, 9, 9, 0]]},
        ],
      };
      final out = ensurePsaveClearsFreeze(normalizeWledPayload(state), [0]);
      expect(segsOf(out).single.containsKey('frz'), isFalse);
    });
  });
}
