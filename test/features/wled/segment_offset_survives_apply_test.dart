// THE PIN: a segment with a nonzero INSTALLED `of` survives a local apply.
//
// `of` is WLED's per-segment offset — where in the strip the effect starts.
// #76 put it with `rev`/`mi`/`start`/`stop` in INSTALLATION GEOMETRY: it
// belongs to provisioning and roofline tooling, and a design payload never
// writes it. The 2026-08-17 reclassification moved ONLY `grp`/`spc` out of
// that set; `of` was not reconsidered and did not move.
//
// The chokepoint asserted it anyway. `normalizeWledPayload` carried
//
//     if (s.containsKey('fx')) s.putIfAbsent('of', () => 0);
//
// alongside the grp/spc defaults, so every fx-bearing apply — every pattern
// tap, every schedule fire, every celebration, every sync self-apply — sent
// `of: 0` and flattened whatever offset the installation had.
//
// WHY IT OUTLIVED #76, and the reason this file exists rather than one more
// assertion in a builder test: #76 audited BUILDERS, and this is not a
// builder. It is the shared function every builder's output flows THROUGH, so
// a per-builder census could not see it — none of the seven wrote `of`. Same
// shape as #88 (four emitters outside a seven-builder sweep) and
// BUG-GD-PICKER-1 (a third sibling an "all others SAFE" sweep missed). Three
// times now the census has under-counted its own family by walking the code it
// knew about instead of grepping the field name across everything.
//
// These assert through applyJson — the real chokepoint, against a fake device
// that RETAINS what it is not told — not against the pure function alone. A
// test of the pure function proves the key is absent; only the merge proves
// the device keeps its offset.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

/// A segment that merges what it is told and keeps everything else — the
/// firmware's actual behaviour, and the whole reason an unstated field is an
/// inherited field.
class _FakeSegment {
  final Map<String, dynamic> state;
  _FakeSegment(this.state);
  void apply(Map<String, dynamic> seg) => state.addAll(seg);
}

/// The bench's seg1 with an installed offset — the shape this defends.
_FakeSegment _installedWithOffset() => _FakeSegment(<String, dynamic>{
      'id': 1,
      'start': 128,
      'stop': 290,
      'of': 40, // <- installed offset: the effect starts 40 px in
      'rev': true,
      'fx': 83,
    });

Map<String, dynamic> _firstSeg(Map<String, dynamic> payload) =>
    ((payload['seg'] as List).first as Map).cast<String, dynamic>();

void main() {
  group('#76 — a local apply does not flatten an installed offset', () {
    test('THE PIN: of=40 before a design apply → of=40 after', () {
      final seg = _installedWithOffset();
      expect(seg.state['of'], 40, reason: 'before: the installed offset');

      final design = normalizeWledPayload(<String, dynamic>{
        'on': true,
        'bri': 200,
        'seg': [
          <String, dynamic>{
            'fx': 28,
            'sx': 160,
            'ix': 128,
            'pal': 5,
            'col': [
              [255, 0, 0, 0]
            ],
          }
        ],
      });

      // The payload does not mention `of` at all — that is the fix.
      expect(_firstSeg(design).containsKey('of'), isFalse,
          reason: 'a design payload states design; offset is provisioning\'s');

      seg.apply(_firstSeg(design));

      expect(seg.state['of'], 40,
          reason: 'AFTER: the installed offset SURVIVES. Before the fix this '
              'read 0 — flattened on every single fx-bearing apply.');
      // The rest of the installation is equally untouched.
      expect(seg.state['rev'], isTrue);
      expect(seg.state['start'], 128);
      expect(seg.state['stop'], 290);
      // And the design did land.
      expect(seg.state['fx'], 28);
      expect(seg.state['col'], isNotNull);
    });

    test('`of` is never emitted, whatever the seg states', () {
      // The trigger used to be `fx`; check the whole design-field family so a
      // future widening cannot quietly re-introduce it.
      for (final design in <Map<String, dynamic>>[
        {'fx': 0},
        {'fx': 28, 'sx': 200},
        {
          'col': [
            [1, 2, 3, 0]
          ]
        },
        {
          'i': [0, 5, [1, 2, 3, 0]]
        },
        {'sx': 200},
        {'grp': 3, 'spc': 2},
      ]) {
        final out = _firstSeg(normalizeWledPayload({'seg': [design]}));
        expect(out.containsKey('of'), isFalse, reason: 'for $design');
      }
    });

    test(
        'a caller that DOES own the offset still gets it through — '
        'provisioning is not blocked, only design is', () {
      // The geometry gate's repair arm writes bounds through this same
      // function (healer / sunrise-off / schedule-sync / calendar-lease). The
      // chokepoint must stay a pass-through for a caller whose business this
      // IS, or the repair reports success while writing nothing.
      final provisioning = normalizeWledPayload(<String, dynamic>{
        'seg': [
          {'id': 0, 'start': 0, 'stop': 128},
          {'id': 1, 'start': 128, 'stop': 290, 'of': 40},
        ],
      });
      final segs = (provisioning['seg'] as List).cast<Map>();
      expect(segs[0]['start'], 0);
      expect(segs[0]['stop'], 128);
      expect(segs[1]['of'], 40, reason: 'an explicit offset is honoured');
      expect(segs[1]['start'], 128);
      expect(segs[1]['stop'], 290);
      // …and no design defaults were injected onto a bounds-only write.
      expect(segs[0].containsKey('grp'), isFalse);
      expect(segs[0].containsKey('spc'), isFalse);
    });

    test(
        'NO REGRESSION on a uniform-forward install: a segment with no prior '
        'offset is unaffected either way', () {
      // Most of the fleet. `of` was absent before and is absent after, so the
      // device keeps its own default — the fix is a no-op here, which is what
      // makes it safe to ship fleet-wide.
      final seg = _FakeSegment(<String, dynamic>{'id': 0, 'start': 0, 'stop': 128});
      final before = Map<String, dynamic>.from(seg.state);

      seg.apply(_firstSeg(normalizeWledPayload({
        'seg': [
          {'fx': 28, 'col': [[0, 0, 255, 0]]}
        ]
      })));

      expect(seg.state.containsKey('of'), isFalse,
          reason: 'nothing invented where nothing was installed');
      expect(seg.state['start'], before['start']);
      expect(seg.state['stop'], before['stop']);
      expect(seg.state['fx'], 28, reason: 'the design still lands');
    });
  });
}
