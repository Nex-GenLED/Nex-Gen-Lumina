// Scheduling V3 D2 — channel-scoped preset bodies.
//
// The first group is the one that matters most: with `channels == null` the
// builders must be BYTE-IDENTICAL to their pre-D2 output. Every controller in
// the fleet is all-channel today, so a difference there is a fleet-wide change
// nobody asked for.
//
// The scoped semantics come from the two bench probes:
//   U-6 — a stored per-segment `on:false` is preserved AND asserted on load.
//   U-7 — `psave` snapshots every segment, so "absent ⇒ untouched" is
//         unreachable; scoping must be stated as explicit `on:false`.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

/// The bench rig's real layout: 2 segments, [0,128) and [128,290).
Map<String, dynamic> benchLive() => {
      'on': true,
      'bri': 128,
      'seg': [
        {'id': 0, 'start': 0, 'stop': 128, 'on': true, 'col': [[0, 70, 135, 0]]},
        {'id': 1, 'start': 128, 'stop': 290, 'on': true, 'col': [[0, 70, 135, 0]]},
      ],
    };

/// A 4-channel controller, the shape per-channel scheduling is really for.
Map<String, dynamic> fourChannelLive() => {
      'seg': [
        for (var i = 0; i < 4; i++) {'id': i, 'on': true},
      ],
    };

void main() {
  group('channels == null is byte-identical to pre-D2', () {
    test('ON ladder on the bench rig layout', () {
      final state = ScheduleSyncService.buildNglOnPresetState(200, benchLive());
      expect(state, {
        'on': true,
        'bri': 200,
        'ib': true,
        'seg': [
          {'id': 0, 'on': true},
          {'id': 1, 'on': true},
        ],
      });
    });

    test('OFF preset on the bench rig layout', () {
      final state = ScheduleSyncService.buildNglOffPresetState(benchLive());
      expect(state, {
        'on': false,
        'ib': true,
        'seg': [
          {'id': 0, 'on': false},
          {'id': 1, 'on': false},
        ],
      });
    });

    test('degraded (no live state) fallbacks are unchanged', () {
      expect(ScheduleSyncService.buildNglOnPresetState(200, null)['seg'],
          [{'on': true}]);
      expect(ScheduleSyncService.buildNglOffPresetState(null)['seg'],
          [{'on': false}]);
    });

    test('a pattern payload passes through untouched', () {
      final payload = {
        'bri': 200,
        'seg': [
          {'id': 0, 'fx': 12, 'col': [[255, 0, 0, 0]]}
        ],
      };
      expect(
        ScheduleSyncService.scopePatternPayload(payload, benchLive()),
        same(payload),
        reason: 'identical object, not merely equal — no allocation, no risk',
      );
    });
  });

  group('scoped ON — excluded channels are DARKENED, not left alone', () {
    test('4-channel controller, scoped to channel 1', () {
      final state = ScheduleSyncService.buildNglOnPresetState(
          200, fourChannelLive(),
          channels: const [1]);
      expect(state['seg'], [
        {'id': 0, 'on': false},
        {'id': 1, 'on': true},
        {'id': 2, 'on': false},
        {'id': 3, 'on': false},
      ]);
      // Root master still asserted: the event IS taking the house over.
      expect(state['on'], true);
      expect(state['ib'], true);
    });

    test('every live segment is named — absence is not an option (U-7)', () {
      final state = ScheduleSyncService.buildNglOnPresetState(
          200, fourChannelLive(),
          channels: const [0, 3]);
      final ids = (state['seg'] as List).map((s) => s['id']).toList();
      expect(ids, [0, 1, 2, 3],
          reason: 'psave would re-add any omitted segment from live state');
    });

    test('degraded state with a scope names the requested ids', () {
      final state = ScheduleSyncService.buildNglOnPresetState(200, null,
          channels: const [2]);
      expect(state['seg'], [{'id': 2, 'on': true}]);
    });
  });

  group('scoped OFF — turns off ONLY its channels, and never master', () {
    test('excluded segments are ABSENT, so psave leaves them as they are', () {
      final state = ScheduleSyncService.buildNglOffPresetState(
          fourChannelLive(),
          channels: const [1]);
      expect(state['seg'], [
        {'id': 1, 'on': false}
      ]);
    });

    test('a scoped OFF asserts NO root power — the load-bearing assertion', () {
      final state = ScheduleSyncService.buildNglOffPresetState(
          fourChannelLive(),
          channels: const [1]);
      expect(state.containsKey('on'), isFalse,
          reason: 'root on:false is GLOBAL — it would darken every channel, '
              'turning "off the porch" into "off the house"');
      expect(state.containsKey('ib'), isFalse,
          reason: 'ib only means anything alongside a root master state');
    });

    test('an ALL-channel OFF still asserts root power, unchanged', () {
      final state = ScheduleSyncService.buildNglOffPresetState(fourChannelLive());
      expect(state['on'], false);
      expect(state['ib'], true);
    });
  });

  group('scoped pattern payload', () {
    test('the design lands on addressed channels, others are darkened', () {
      final payload = {
        'bri': 180,
        'seg': [
          {'id': 0, 'fx': 12, 'sx': 200, 'col': [[255, 0, 0, 0]]}
        ],
      };
      final out = ScheduleSyncService.scopePatternPayload(
          payload, fourChannelLive(),
          channels: const [2]);

      expect(out['bri'], 180, reason: 'top-level keys survive');
      expect(out['seg'], [
        {'id': 0, 'on': false},
        {'id': 1, 'on': false},
        {'id': 2, 'fx': 12, 'sx': 200, 'col': [[255, 0, 0, 0]], 'on': true},
        {'id': 3, 'on': false},
      ]);
    });

    test('bounds and ids are never copied from the template', () {
      final payload = {
        'seg': [
          {'id': 0, 'start': 0, 'stop': 128, 'fx': 5}
        ],
      };
      final out = ScheduleSyncService.scopePatternPayload(
          payload, fourChannelLive(),
          channels: const [1]);
      final targeted =
          (out['seg'] as List).firstWhere((s) => s['id'] == 1) as Map;
      expect(targeted.containsKey('start'), isFalse,
          reason: 'bounds belong to provisioning — the Item-#82 stomp');
      expect(targeted.containsKey('stop'), isFalse);
      expect(targeted['fx'], 5);
    });

    test('the DESIGN seg is used as the template, not seg[0]', () {
      // A payload that already carries an exclusion first — the shape
      // applyChannelFilter emits.
      final payload = {
        'seg': [
          {'id': 0, 'on': false},
          {'id': 1, 'fx': 9, 'col': [[0, 255, 0, 0]]},
        ],
      };
      final out = ScheduleSyncService.scopePatternPayload(
          payload, fourChannelLive(),
          channels: const [3]);
      final targeted =
          (out['seg'] as List).firstWhere((s) => s['id'] == 3) as Map;
      expect(targeted['fx'], 9, reason: 'took the design seg, not the exclusion');
    });

    test('a top-level-only payload still produces the partition', () {
      final out = ScheduleSyncService.scopePatternPayload(
          {'bri': 100}, fourChannelLive(),
          channels: const [0]);
      expect(out['seg'], [
        {'id': 0, 'on': true},
        {'id': 1, 'on': false},
        {'id': 2, 'on': false},
        {'id': 3, 'on': false},
      ]);
    });

    test('a targeted channel absent from live state is still represented', () {
      // Cold/partial live read: the census unions the target in (#89).
      final out = ScheduleSyncService.scopePatternPayload(
          {'seg': [{'id': 0, 'fx': 3}]}, null,
          channels: const [7]);
      expect((out['seg'] as List).map((s) => s['id']), [7]);
      expect((out['seg'] as List).single['on'], true);
    });
  });
}
