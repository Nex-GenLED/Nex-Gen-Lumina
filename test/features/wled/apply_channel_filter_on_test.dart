// Tests for the channel-2-dark fix in applyChannelFilter (Bundle 3b.3a).
//
// Before this bundle, applyChannelFilter expanded a single-seg template
// across channel ids but did NOT emit per-seg 'on':true. Inline dashboard
// builders (pattern_grid_widgets, scenes, sliders, etc.) put 'on' at the
// top level of the payload, not inside the seg map — so a seg left in
// on:false on the controller would stay dark after a dashboard apply.
// Bundle 3b.3a adds 'on': true to each expanded seg to match
// buildParticipatingSegArray's channel-2-dark fix semantics.
//
// Independent of participation; correct under any U1/U2/U3/U4 semantic.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

void main() {
  group('applyChannelFilter — channel-2-dark fix (per-seg on:true)', () {
    test('Case 1: channelIds [0,1] → each expanded seg has on:true', () {
      // Real inline-builder shape: top-level on:true, single seg without
      // its own 'on' field. Matches pattern_grid_widgets._preparePayload
      // output before applyChannelFilter runs.
      final input = {
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 28, 'sx': 160, 'ix': 128, 'col': [[255, 0, 0, 0]]},
        ],
      };
      final result = applyChannelFilter(input, const [0, 1]);
      final segs = result['seg'] as List;
      expect(segs, hasLength(2));
      expect(segs[0]['on'], isTrue);
      expect(segs[1]['on'], isTrue);
    });

    test(
        'Case 2: fix does not disturb existing fields (id/fx/col/template '
        'preserved)', () {
      const col = [
        [10, 20, 30, 0],
        [40, 50, 60, 0],
      ];
      final input = {
        'on': true,
        'bri': 100,
        'seg': [
          {'fx': 52, 'sx': 200, 'ix': 230, 'pal': 0, 'col': col},
        ],
      };
      final result = applyChannelFilter(input, const [0, 1]);
      final segs = result['seg'] as List;
      for (int i = 0; i < segs.length; i++) {
        expect(segs[i]['id'], i, reason: 'id is the channel index');
        expect(segs[i]['fx'], 52);
        expect(segs[i]['sx'], 200);
        expect(segs[i]['ix'], 230);
        expect(segs[i]['pal'], 0);
        expect(segs[i]['col'], equals(col));
        expect(segs[i]['on'], isTrue);
      }
      // Top-level fields preserved
      expect(result['on'], true);
      expect(result['bri'], 100);
    });

    test(
        'Case 3: template that already has on:true → still on:true on each '
        'expanded seg (idempotent, not duplicated or flipped)', () {
      final input = {
        'on': true,
        'bri': 200,
        'seg': [
          // Template has 'on':true baked in — unusual but possible
          {'on': true, 'fx': 0, 'col': [[255, 255, 255, 0]]},
        ],
      };
      final result = applyChannelFilter(input, const [0, 1]);
      final segs = result['seg'] as List;
      for (final s in segs) {
        expect(s['on'], isTrue);
      }
    });

    test(
        'Case 3b: template with on:false → STILL gets on:true after expansion '
        '(channel-2-dark fix forces channels we are targeting to light up)',
        () {
      // Defensive: if for some reason a template arrives with on:false,
      // the expansion should still light targeted channels — that is the
      // whole point of the channel-2-dark fix.
      final input = {
        'on': true,
        'seg': [
          {'on': false, 'fx': 0, 'col': [[0, 0, 255, 0]]},
        ],
      };
      final result = applyChannelFilter(input, const [0, 1]);
      final segs = result['seg'] as List;
      for (final s in segs) {
        expect(s['on'], isTrue,
            reason:
                'targeting a channel implies it must be on; template '
                'on:false must not propagate.');
      }
    });

    test('Case 4: empty channelIds → unchanged passthrough', () {
      final input = {
        'on': true,
        'seg': [
          {'fx': 0, 'col': [[255, 0, 0, 0]]},
        ],
      };
      final result = applyChannelFilter(input, const []);
      expect(result, equals(input));
    });

    test('Case 5: RGBW col passes through untouched in every expanded seg',
        () {
      const col = [
        [255, 180, 100, 255], // warm white with explicit W=255
      ];
      final input = {
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 0, 'col': col},
        ],
      };
      final result = applyChannelFilter(input, const [0, 1, 2]);
      for (final s in (result['seg'] as List)) {
        expect(s['col'], equals(col),
            reason:
                'RGBW col arrays (including W=255 for true warm white) '
                'must pass through byte-identical.');
      }
    });

    test('start/stop still set per DeviceChannel when provided', () {
      // Existing behavior — not part of the on:true fix but verify it
      // didn't regress.
      final input = {
        'on': true,
        'seg': [
          {'fx': 0, 'col': [[255, 0, 0, 0]]},
        ],
      };
      const channels = [
        DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
        DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 138, gpioPin: 14),
      ];
      final result = applyChannelFilter(input, const [0, 1], channels);
      final segs = result['seg'] as List;
      expect(segs[0]['start'], 0);
      expect(segs[0]['stop'], 128);
      expect(segs[1]['start'], 128);
      expect(segs[1]['stop'], 138);
      // And the new fix:
      expect(segs[0]['on'], isTrue);
      expect(segs[1]['on'], isTrue);
    });

    test('subset targeting [1] only → one seg id 1 with on:true', () {
      final input = {
        'on': true,
        'bri': 255,
        'seg': [
          {'fx': 88, 'col': [[0, 255, 0, 0]]},
        ],
      };
      final result = applyChannelFilter(input, const [1]);
      final segs = result['seg'] as List;
      expect(segs, hasLength(1));
      expect(segs.first['id'], 1);
      expect(segs.first['on'], isTrue);
      expect(segs.first['fx'], 88);
    });
  });
}
