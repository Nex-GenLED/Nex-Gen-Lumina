// Tests for buildParticipatingSegArray — the SINGLE shared payload builder
// used by all sync/game-day apply sites (foreground sync engine, foreground
// game-day service, plus the background sync + game-day workers in Bundle 4).
//
// Contract (locked by Bundle 3 design):
//   - One seg entry per participating channel id.
//   - Each entry has per-seg 'on':true (channel-2-dark fix; confirmed by
//     hardware probe — a seg in on:false is NOT re-lit by top-level on:true).
//   - No 'start' / 'stop' / 'rev' keys (WLED retains install-time ranges;
//     rev is a later bundle).
//   - Empty participating list → empty seg array; caller must handle.
//   - col is passed through unchanged.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

void main() {
  group('buildParticipatingSegArray', () {
    test('Case 1: [0,1] → two seg entries, ids 0 and 1, all with on:true', () {
      final segs = buildParticipatingSegArray(
        participatingChannelIds: const [0, 1],
        effectId: 28,
        speed: 160,
        intensity: 128,
        colorSlots: const [
          [255, 0, 0, 0],
          [0, 255, 0, 0],
        ],
      );
      expect(segs, hasLength(2));
      expect(segs[0]['id'], 0);
      expect(segs[1]['id'], 1);
      expect(segs.every((s) => s['on'] == true), isTrue);
      expect(segs.every((s) => s['fx'] == 28), isTrue);
      expect(segs.every((s) => s['sx'] == 160), isTrue);
      expect(segs.every((s) => s['ix'] == 128), isTrue);
    });

    test('Case 2: [1] only → one seg entry id 1; NO id 0 in array', () {
      final segs = buildParticipatingSegArray(
        participatingChannelIds: const [1],
        effectId: 0,
        speed: 128,
        intensity: 128,
        colorSlots: const [
          [0, 0, 255, 0],
        ],
      );
      expect(segs, hasLength(1));
      expect(segs.first['id'], 1);
      expect(segs.first['on'], isTrue);
      expect(segs.any((s) => s['id'] == 0), isFalse);
    });

    test(
        'Case 3: empty participating list → empty seg array (caller must '
        'skip the apply)', () {
      final segs = buildParticipatingSegArray(
        participatingChannelIds: const [],
        effectId: 0,
        speed: 128,
        intensity: 128,
        colorSlots: const [
          [255, 255, 255, 0],
        ],
      );
      expect(segs, isEmpty);
    });

    test('Case 4: every entry has on:true (the channel-2-dark fix)', () {
      final segs = buildParticipatingSegArray(
        participatingChannelIds: const [0, 1, 2, 3],
        effectId: 0,
        speed: 128,
        intensity: 128,
        colorSlots: const [
          [255, 255, 255, 0],
        ],
      );
      expect(segs, hasLength(4));
      for (final s in segs) {
        expect(s['on'], isTrue,
            reason:
                'every participating channel MUST get per-seg on:true — top-'
                'level on:true is insufficient for channels left in on:false');
      }
    });

    test('Case 5: NO entry contains a start or stop key', () {
      // WLED retains install-time start/stop. Sync apply must not send them.
      final segs = buildParticipatingSegArray(
        participatingChannelIds: const [0, 1],
        effectId: 28,
        speed: 160,
        intensity: 128,
        colorSlots: const [
          [255, 0, 0, 0],
        ],
      );
      for (final s in segs) {
        expect(s.containsKey('start'), isFalse,
            reason: 'seg.start would override the install-time range');
        expect(s.containsKey('stop'), isFalse,
            reason: 'seg.stop would override the install-time range');
      }
    });

    test('Case 6: NO entry contains a rev key (rev is a later bundle)', () {
      final segs = buildParticipatingSegArray(
        participatingChannelIds: const [0],
        effectId: 0,
        speed: 128,
        intensity: 128,
        colorSlots: const [
          [255, 255, 255, 0],
        ],
      );
      for (final s in segs) {
        expect(s.containsKey('rev'), isFalse,
            reason: 'rev integration is reserved for a later bundle');
      }
    });

    test('Case 7: col is passed through unchanged', () {
      const colors = [
        [10, 20, 30, 0],
        [40, 50, 60, 0],
        [70, 80, 90, 0],
      ];
      final segs = buildParticipatingSegArray(
        participatingChannelIds: const [0, 1],
        effectId: 0,
        speed: 0,
        intensity: 0,
        colorSlots: colors,
      );
      for (final s in segs) {
        expect(s['col'], equals(colors));
      }
    });

    test(
        'preserves the order of participatingChannelIds (no implicit sort '
        'at the builder layer; the resolver sorts when appropriate)', () {
      final segs = buildParticipatingSegArray(
        participatingChannelIds: const [2, 0, 1],
        effectId: 0,
        speed: 0,
        intensity: 0,
        colorSlots: const [
          [255, 0, 0, 0],
        ],
      );
      expect(segs.map((s) => s['id']).toList(), equals([2, 0, 1]));
    });
  });
}
