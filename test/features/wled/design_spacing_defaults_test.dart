// #88 — THE PINNED TEST. A plain design applied over a segment carrying a
// stale `spc=2` leaves the device reading `spc:0`.
//
// The bench is the live case. Capture `20260817T014938Z` on `.150`:
//
//     seg0 [0,128)   len=128  grp=1 spc=2  fx=0   rev=False
//     seg1 [128,290) len=162  grp=1 spc=0  fx=83  rev=True
//
// `spc=2` with `grp=1` renders every third pixel — ~43 of 128 lit on channel
// 1 — and the two segments disagree in the same field. #76 had stripped
// grp/spc from seven builders as geometry while four other emitters kept
// writing them, so the same two fields obeyed two rules depending on which
// screen the user came from. The decision of record (2026-08-17) resolves the
// split toward DESIGN, which makes SILENCE the bug: an unstated grp/spc is an
// inherited grp/spc, and inherited state is a bug (#67, third appearance).
//
// This test uses a fake device that starts in the bench's poisoned state and
// checks what the payload would leave behind. The on-device smoke re-runs it
// against `.150` for real.

import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/team_design_catalog.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

/// The smallest honest stand-in for a WLED segment: it RETAINS every field it
/// is not told about, which is the whole reason omission is not neutral.
class _FakeSegment {
  final Map<String, dynamic> state;
  _FakeSegment(this.state);

  /// Apply a `/json/state` seg map the way the firmware does — merge, never
  /// replace. Unstated keys survive.
  void apply(Map<String, dynamic> seg) => state.addAll(seg);
}

/// The bench's actual poisoned seg0.
_FakeSegment _benchSeg0() => _FakeSegment(<String, dynamic>{
      'id': 0,
      'start': 0,
      'stop': 128,
      'grp': 1,
      'spc': 2, // <- the residue
      'fx': 0,
      'rev': false,
    });

Map<String, dynamic> _firstSeg(Map<String, dynamic> payload) =>
    ((payload['seg'] as List).first as Map).cast<String, dynamic>();

void main() {
  group('#88 — a plain design FLATTENS a stale spc, it does not inherit it',
      () {
    test('THE PIN: seg0 spc=2 → a plain design apply leaves spc:0', () {
      final seg = _benchSeg0();
      expect(seg.state['spc'], 2, reason: 'before: the bench residue');

      // A plain design with no opinion on spacing: the Game Day auto-built
      // look, through the same normalize chokepoint every apply crosses.
      final design = normalizeWledPayload(<String, dynamic>{
        'on': true,
        'bri': 200,
        'seg': [
          <String, dynamic>{
            ...kDesignSpacingDefaults,
            'fx': 52,
            'sx': 160,
            'ix': 128,
            'pal': 0,
            'col': [
              [0, 70, 135, 0]
            ],
          }
        ],
      });

      seg.apply(_firstSeg(design));

      expect(seg.state['spc'], 0,
          reason: 'AFTER: the residue is flattened, not inherited');
      expect(seg.state['grp'], 1);
      // And the geometry it had no business touching is untouched.
      expect(seg.state['start'], 0);
      expect(seg.state['stop'], 128);
      expect(seg.state['rev'], false,
          reason: 'grp/spc moved to design; rev/start/stop did NOT');
    });

    test(
        'the normalize chokepoint asserts the defaults for any seg that '
        'states a design — fx, col, or a per-pixel i', () {
      for (final design in <Map<String, dynamic>>[
        {'fx': 28},
        {
          'col': [
            [1, 2, 3, 0]
          ]
        },
        {
          'i': [0, 5, [1, 2, 3, 0]]
        },
      ]) {
        final out = _firstSeg(normalizeWledPayload({'seg': [design]}));
        expect(out['grp'], kDesignDefaultGrp, reason: 'for $design');
        expect(out['spc'], kDesignDefaultSpc, reason: 'for $design');
      }
    });

    test(
        'a PARTIAL slider payload is left alone — a speed drag must never '
        'flatten spacing the user chose', () {
      final out = _firstSeg(normalizeWledPayload({
        'seg': [
          {'sx': 200}
        ]
      }));
      expect(out.containsKey('grp'), isFalse);
      expect(out.containsKey('spc'), isFalse);
      expect(out['sx'], 200);
      // (`frz:false` is the unrelated frozen-segment guard, always injected.)
    });

    test('a design that OWNS its spacing keeps it — defaults never override',
        () {
      final out = _firstSeg(normalizeWledPayload({
        'seg': [
          {'fx': 0, 'grp': 3, 'spc': 3}
        ]
      }));
      expect(out['grp'], 3, reason: 'candy cane owns its banding');
      expect(out['spc'], 3);
    });

    test('`of` stays on the fx-only trigger — offset is still GEOMETRY', () {
      final colOnly = _firstSeg(normalizeWledPayload({
        'seg': [
          {
            'col': [
              [1, 2, 3, 0]
            ]
          }
        ]
      }));
      expect(colOnly.containsKey('of'), isFalse,
          reason: '#76 classified `of` as geometry; only grp/spc were '
              'reclassified');
    });
  });

  group('#88 — the builders assert it themselves, not only at the boundary',
      () {
    // At-rest correctness. savePreset/psave and Firestore-persisted design
    // blobs do not all cross normalizeWledPayload, so a payload that is only
    // correct on the wire is a payload that bakes the residue into a preset.

    test('GradientPattern.toWledPayload (a #76 strip site) asserts defaults',
        () {
      final seg = _firstSeg(const GradientPattern(
        name: 'Warm',
        colors: [Color(0xFFFF0000), Color(0xFF00FF00)],
        effectId: 28,
      ).toWledPayload());
      expect(seg['grp'], kDesignDefaultGrp);
      expect(seg['spc'], kDesignDefaultSpc);
      expect(seg.containsKey('of'), isFalse, reason: 'offset stays geometry');
      expect(seg.containsKey('rev'), isFalse);
      expect(seg.containsKey('start'), isFalse);
    });

    test('EditablePattern effect payload asserts grp from the design, spc:0',
        () {
      final seg = _firstSeg(const EditablePattern(
        id: 'p1',
        effectId: 28,
        colorGroupSize: 4,
        actionColors: [Color(0xFFFF0000)],
      ).toWledPayload(290));
      expect(seg['grp'], 4, reason: 'banding IS the design');
      expect(seg['spc'], kDesignDefaultSpc);
      expect(seg.containsKey('rev'), isFalse, reason: 'direction stays out');
      expect(seg.containsKey('mi'), isFalse);
    });

    test('TeamDesignCatalog asserts grp (incl. the candy-cane 3) and spc:0',
        () {
      final catalog = TeamDesignCatalog.build(
        teamName: 'Royals',
        primary: const Color(0xFF004687),
        secondary: const Color(0xFFBD9B60),
      );
      for (final d in catalog) {
        final seg = _firstSeg(d.wledPayload);
        expect(seg['grp'], d.colorGroupSize, reason: d.name);
        expect(seg['spc'], kDesignDefaultSpc, reason: d.name);
      }
      // The stripe design is the one that genuinely owns its banding.
      expect(catalog.last.colorGroupSize, 3);
      expect(_firstSeg(catalog.last.wledPayload)['grp'], 3);
    });

    test('CustomDesign.toWledPayload asserts defaults on every channel', () {
      final design = CustomDesign(
        id: 'd1',
        name: 'Two Channel',
        createdAt: DateTime.utc(2026, 8, 17),
        updatedAt: DateTime.utc(2026, 8, 17),
        ownerId: 'u1',
        channels: const [
          ChannelDesign(channelId: 0, channelName: 'Front', effectId: 28),
          ChannelDesign(channelId: 1, channelName: 'Side', effectId: 12),
        ],
      );
      for (final seg in (design.toWledPayload()['seg'] as List).cast<Map>()) {
        expect(seg['grp'], kDesignDefaultGrp);
        expect(seg['spc'], kDesignDefaultSpc);
        expect(seg.containsKey('rev'), isFalse);
        expect(seg.containsKey('start'), isFalse);
      }
    });
  });
}
