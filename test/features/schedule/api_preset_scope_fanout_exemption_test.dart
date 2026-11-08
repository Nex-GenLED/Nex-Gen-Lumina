// Roofline slice 2 — the scope rule and the bus fan-out never reshape a
// painted design's preset body.
//
// FAIL-BEFORE (defect-style). On the unchanged code:
//   • scopePatternPayload with a channel scope copies the FIRST segment that
//     states a design onto every census id as a template. For a per-pixel
//     body that collapses every bus to bus 0's picture (audit §B.2 "per-
//     channel pictures would collapse to channel 0's picture"); for an API
//     body it also strips the bounds and `o` is left on a body whose segments
//     no longer carry what the controller must replay.
//   • fanOutPatternPayloadToBuses fans a single id-less segment out over the
//     buses. An API body is built final; a one-bus API body with no id would
//     be fanned into N entries without bounds.
//
// After: both return the payload UNCHANGED (same instance) when it carries
// `o:true`, and the scope rule also stands aside for any `seg[].i`. The
// catalog cases pin today's behaviour so the exemption is exactly that wide.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/pattern_preset_fanout.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

Map<String, dynamic> apiBody() => {
      'o': true,
      'on': true,
      'bri': 200,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': 100,
          'on': true,
          'fx': 0,
          'i': [0, 100, [255, 0, 0, 0]],
        },
        {
          'id': 1,
          'start': 100,
          'stop': 200,
          'on': true,
          'fx': 0,
          'i': [0, 100, [0, 0, 255, 0]],
        },
      ],
    };

/// A per-pixel body WITHOUT `o` (a design's toWledPayload as an older build
/// stored it on a schedule): the scope rule must not template it either.
Map<String, dynamic> perPixelBody() => apiBody()..remove('o');

Map<String, dynamic> live2() => {
      'on': true,
      'seg': [
        {'id': 0, 'on': true},
        {'id': 1, 'on': true},
      ],
    };

void main() {
  group('scopePatternPayload stands aside', () {
    test('an API body with a channel scope is returned unchanged (same instance)',
        () {
      final body = apiBody();
      final out = ScheduleSyncService.scopePatternPayload(body, live2(),
          channels: const [1]);
      expect(identical(out, body), isTrue,
          reason: 'on the unchanged code bus 1 gets bus 0\'s picture and the '
              'bounds are stripped');
    });

    test('a per-pixel body (no o) with a channel scope is returned unchanged',
        () {
      final body = perPixelBody();
      final out = ScheduleSyncService.scopePatternPayload(body, live2(),
          channels: const [0]);
      expect(identical(out, body), isTrue);
    });

    test('a catalog pattern with a channel scope is still scoped (unchanged rule)',
        () {
      final body = {
        'on': true,
        'seg': [
          {
            'fx': 84,
            'col': [
              [255, 0, 0, 0]
            ]
          }
        ],
      };
      final out = ScheduleSyncService.scopePatternPayload(body, live2(),
          channels: const [1]);
      expect(out['seg'], [
        {'id': 0, 'on': false},
        {
          'id': 1,
          'fx': 84,
          'col': [
            [255, 0, 0, 0]
          ],
          'on': true
        },
      ]);
    });
  });

  group('fanOutPatternPayloadToBuses stands aside', () {
    test('a one-entry id-less API body is NOT fanned out (explicit no-op)', () {
      final body = {
        'o': true,
        'on': true,
        'seg': [
          {
            'start': 0,
            'stop': 100,
            'on': true,
            'fx': 0,
            'col': [
              [0, 0, 0, 0]
            ],
            // no `i`: the one shape the old guard did not already catch
          }
        ],
      };
      final out = fanOutPatternPayloadToBuses(body, const [0, 1, 2]);
      expect(identical(out, body), isTrue,
          reason: 'on the unchanged code this becomes three id-bearing '
              'entries with the bounds stripped');
    });

    test('a per-bus API body is untouched (several entries, ids)', () {
      final body = apiBody();
      expect(identical(fanOutPatternPayloadToBuses(body, const [0, 1]), body),
          isTrue);
    });

    test('the tuner shape is still fanned out (unchanged rule)', () {
      final out = fanOutPatternPayloadToBuses({
        'on': true,
        'seg': [
          {
            'fx': 84,
            'col': [
              [255, 0, 0, 0]
            ]
          }
        ],
      }, const [0, 1]);
      expect((out['seg'] as List).length, 2);
    });
  });
}
