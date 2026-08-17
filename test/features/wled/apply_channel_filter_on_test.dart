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

    // INVERTED for #89 (was: 'start/stop still set per DeviceChannel when
    // provided'). Bounds are provisioning's, not an apply's — #76's rule, and
    // the whole point of the seg-deletion fix. `channels` is now the CENSUS.
    test('start/stop are NEVER written, even with DeviceChannels in hand', () {
      final input = {
        'on': true,
        'seg': [
          {'fx': 0, 'col': [[255, 0, 0, 0]]},
        ],
      };
      final result = applyChannelFilter(input, const [0, 1], _twoChannel);
      final segs = result['seg'] as List;
      for (final s in segs) {
        expect(s.containsKey('start'), isFalse,
            reason: 'an apply must not restate installation bounds');
        expect(s.containsKey('stop'), isFalse);
      }
      expect(segs[0]['on'], isTrue);
      expect(segs[1]['on'], isTrue);
    });

    test('a template carrying bounds has them STRIPPED, not propagated', () {
      final input = {
        'on': true,
        'seg': [
          {'start': 0, 'stop': 999, 'fx': 0, 'col': [[255, 0, 0, 0]]},
        ],
      };
      final result = applyChannelFilter(input, const [0, 1], _twoChannel);
      for (final s in (result['seg'] as List)) {
        expect(s.containsKey('start'), isFalse);
        expect(s.containsKey('stop'), isFalse);
      }
    });

    test(
        'subset targeting [1] with no channel census → one seg id 1 with '
        'on:true (nothing known to exclude)', () {
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

  // ==========================================================================
  // #89 — THE PINNED TEST. A single-channel design applied to a two-channel
  // device leaves BOTH segments existing, the unused one off, and bounds
  // untouched.
  //
  // Asserted against BOUNDS, not segment count — the #89 lesson. A count-only
  // assertion passes a full-strip swallow (seg0 rewritten to [0,290), seg1
  // dropped) just as happily as it passes the correct payload, which is
  // exactly how the collapse signature went unnoticed.
  // ==========================================================================
  group('#89 — "channel unused" is {id, on:false}, never bounds', () {
    test(
        'single-channel design on a two-channel device: both segs survive, '
        'unused one off, NO bounds anywhere', () {
      final design = {
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 88, 'sx': 160, 'ix': 128, 'pal': 5, 'col': [[255, 0, 0, 0]]},
        ],
      };

      final result = applyChannelFilter(design, const [0], _twoChannel);
      final segs = (result['seg'] as List).cast<Map>();

      // BOTH segments are expressed. The excluded one is not deleted.
      expect(segs.map((s) => s['id']).toList(), equals([0, 1]));

      // Channel 0 carries the design and is lit.
      expect(segs[0]['on'], isTrue);
      expect(segs[0]['fx'], 88);
      expect(segs[0]['col'], equals([[255, 0, 0, 0]]));

      // Channel 1 is excluded: {id, on:false} and NOTHING else. No look
      // fields (its own stay inherited on the device), no bounds.
      expect(segs[1]['on'], isFalse);
      expect(segs[1].keys.toSet(), equals({'id', 'on'}),
          reason: 'an exclusion states exclusion and nothing else');

      // THE BOUNDS ASSERTION — the one a count-only check would miss. Neither
      // segment carries start/stop, so the device's provisioned
      // seg0 [0,128) / seg1 [128,290) is arithmetically untouchable by this
      // payload: no [0,0) deletion AND no [0,290) full-strip swallow.
      for (final s in segs) {
        expect(s.containsKey('start'), isFalse,
            reason: 'a design apply must not restate bounds — '
                'the swallow and the deletion are the same defect');
        expect(s.containsKey('stop'), isFalse);
      }
    });

    test('targeting the SECOND channel only excludes channel 0, in id order',
        () {
      final design = {
        'on': true,
        'seg': [
          {'fx': 12, 'col': [[0, 0, 255, 0]]},
        ],
      };
      final segs =
          (applyChannelFilter(design, const [1], _twoChannel)['seg'] as List)
              .cast<Map>();
      expect(segs.map((s) => s['id']).toList(), equals([0, 1]));
      expect(segs[0].keys.toSet(), equals({'id', 'on'}));
      expect(segs[0]['on'], isFalse);
      expect(segs[1]['on'], isTrue);
      expect(segs[1]['fx'], 12);
    });

    test('participation == every channel is byte-equivalent to a plain fan-out',
        () {
      // The #67 regression-safety pin, restated for the interactive path:
      // the partition must not change what an all-channels apply looks like.
      final design = {
        'on': true,
        'seg': [
          {'fx': 28, 'sx': 160, 'col': [[1, 2, 3, 4]]},
        ],
      };
      final withCensus =
          applyChannelFilter(design, const [0, 1], _twoChannel)['seg'];
      final withoutCensus = applyChannelFilter(design, const [0, 1])['seg'];
      expect(withCensus, equals(withoutCensus));
    });

    test(
        'a target absent from the channel census is still emitted (stale map '
        'must not drop the aimed-at channel)', () {
      final design = {
        'on': true,
        'seg': [
          {'fx': 5, 'col': [[9, 9, 9, 0]]},
        ],
      };
      // Census knows only channel 0; the caller is aiming at channel 2.
      const partial = [
        DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
      ];
      final segs =
          (applyChannelFilter(design, const [2], partial)['seg'] as List)
              .cast<Map>();
      expect(segs.map((s) => s['id']).toList(), equals([0, 2]));
      expect(segs[1]['on'], isTrue, reason: 'the target is always represented');
      expect(segs[1]['fx'], 5);
      expect(segs[0]['on'], isFalse);
    });

    test('firstDesignSeg reads past the exclusion so previews do not blank',
        () {
      final segs = applyChannelFilter({
        'on': true,
        'seg': [
          {'fx': 42, 'col': [[7, 7, 7, 0]]},
        ],
      }, const [1], _twoChannel)['seg'];
      // seg[0] is the exclusion; the design lives at seg[1].
      expect((segs as List).first['fx'], isNull);
      expect(firstDesignSeg(segs)?['fx'], 42);
    });
  });
}

const _twoChannel = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 14),
];
