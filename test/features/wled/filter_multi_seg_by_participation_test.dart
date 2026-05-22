// Tests for [filterMultiSegByParticipation] — the pre-applyJson
// defensive filter that strips non-participating segs from
// externally-sourced multi-seg-with-ids payloads BEFORE they reach
// the chokepoint. Sibling of expandForParticipation (the chokepoint),
// which Rule 4 short-circuits multi-seg payloads through.
//
// Surfaced by the Phase 2 Stop-Sync teardown audit (commit on
// review/sync-teardown). These tests lock the discriminator + the
// filter behavior so the regression that motivated this helper (T5-
// equivalent: scene-tier restore force-lighting a non-participating
// channel) can't sneak back in.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';

void main() {
  group('filterMultiSegByParticipation — pass-through cases', () {
    test('null participating → pass-through (chokepoint Rule 1 semantics)',
        () {
      final payload = {
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0},
          {'id': 1, 'fx': 0},
        ],
      };
      final result = filterMultiSegByParticipation(payload, null);
      expect(result, same(payload),
          reason: 'no preference set → caller did not opt into filtering; '
              'must return the same map reference');
    });

    test('empty participating → pass-through (chokepoint Rule 2 semantics)',
        () {
      final payload = {
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0},
          {'id': 1, 'fx': 0},
        ],
      };
      final result = filterMultiSegByParticipation(payload, []);
      expect(result, same(payload),
          reason: 'explicit-none upstream skip — not "filter all" here');
    });

    test('top-level-only payload (no seg) → pass-through', () {
      final payload = {'on': false};
      final result = filterMultiSegByParticipation(payload, [0]);
      expect(result, same(payload));
    });

    test('top-level-only payload (non-list seg) → pass-through', () {
      final payload = {'on': true, 'seg': 'not-a-list'};
      final result = filterMultiSegByParticipation(payload, [0]);
      expect(result, same(payload));
    });

    test('single-seg payload → pass-through (chokepoint handles single-seg)',
        () {
      // Single-seg-no-id-with-fx (broadcast shape) → chokepoint Rule 7
      final broadcast = {
        'on': true,
        'seg': [
          {'fx': 28, 'col': [[255, 0, 0, 0]]},
        ],
      };
      expect(filterMultiSegByParticipation(broadcast, [0]), same(broadcast));

      // Single-seg-WITH-id (Lumina AI / ComposedPattern shape) → Rule 5
      final targeted = {
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0, 'col': [[100, 200, 50, 0]]},
        ],
      };
      expect(filterMultiSegByParticipation(targeted, [0]), same(targeted),
          reason: 'single-seg passes through regardless of id — the chokepoint '
              'handles single-seg shapes correctly on its own');
    });

    test(
        'multi-seg where at least one entry lacks an id → pass-through '
        '(not the externally-sourced getState() bug-shape)', () {
      // E.g. pixel-range animation: multi-seg with explicit start/stop
      // but no ids. Caller pre-built it intentionally.
      final payload = {
        'on': true,
        'seg': [
          {'start': 0, 'stop': 60, 'fx': 0},
          {'start': 60, 'stop': 120, 'fx': 0},
        ],
      };
      final result = filterMultiSegByParticipation(payload, [0]);
      expect(result, same(payload),
          reason: 'no ids → not the externally-sourced shape; preserve the '
              'caller\'s intentional multi-seg payload');
    });
  });

  group('filterMultiSegByParticipation — filter cases (the bug fix)', () {
    test(
        'multi-seg-with-ids with participating=[0]: keeps id 0, drops id 1 '
        '(the T5-equivalent scenario)', () {
      final payload = {
        'on': true,
        'bri': 217,
        'seg': [
          {'id': 0, 'fx': 0, 'col': [[255, 232, 192, 0]]},
          {'id': 1, 'fx': 0, 'col': [[0, 0, 255, 0]]},
        ],
      };
      final result = filterMultiSegByParticipation(payload, [0]);
      final segs = result['seg'] as List;
      expect(segs, hasLength(1));
      expect((segs.first as Map)['id'], 0);
      // Top-level fields preserved.
      expect(result['on'], true);
      expect(result['bri'], 217);
    });

    test(
        'multi-seg-with-ids with participating=[0,1]: keeps both '
        '(full-participation guard against over-filter)', () {
      final payload = {
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0},
          {'id': 1, 'fx': 0},
        ],
      };
      final result = filterMultiSegByParticipation(payload, [0, 1]);
      final segs = result['seg'] as List;
      expect(segs, hasLength(2));
      final ids = segs.map((s) => (s as Map)['id']).toList();
      expect(ids, containsAll(<int>[0, 1]));
    });

    test(
        'multi-seg-with-ids where NO participating id matches: rewrites to '
        '{"on": false} (safe fallback — does NOT leak through as seg-less)',
        () {
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'fx': 0},
          {'id': 1, 'fx': 0},
        ],
      };
      final result = filterMultiSegByParticipation(payload, [2, 3]);
      expect(result, {'on': false},
          reason: 'when filter would strip everything, fall back to off '
              'rather than POST a seg-less payload (which would leave the '
              'controller in its prior state — the OLD freeze bug)');
    });

    test('filter is pure: input payload is not mutated', () {
      final payload = {
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0},
          {'id': 1, 'fx': 0},
        ],
      };
      // Capture an immutable snapshot of the input.
      final inputSegBefore = List<Map>.from(payload['seg'] as List);
      filterMultiSegByParticipation(payload, [0]);
      // Input remains unmodified.
      final inputSegAfter = payload['seg'] as List;
      expect(inputSegAfter, hasLength(inputSegBefore.length));
      expect((inputSegAfter[0] as Map)['id'], 0);
      expect((inputSegAfter[1] as Map)['id'], 1);
    });

    test('filter preserves non-seg top-level fields when filtering succeeds',
        () {
      final payload = {
        'on': true,
        'bri': 200,
        'transition': 7,
        'seg': [
          {'id': 0, 'fx': 0},
          {'id': 1, 'fx': 0},
        ],
      };
      final result = filterMultiSegByParticipation(payload, [0]);
      expect(result['on'], true);
      expect(result['bri'], 200);
      expect(result['transition'], 7);
    });

    test('filter handles 3+ segs (only kept ids survive)', () {
      // Some controllers expose more than two channels; verify the
      // filter scales.
      final payload = {
        'on': true,
        'seg': [
          {'id': 0, 'fx': 0},
          {'id': 1, 'fx': 0},
          {'id': 2, 'fx': 0},
          {'id': 3, 'fx': 0},
        ],
      };
      final result = filterMultiSegByParticipation(payload, [0, 2]);
      final segs = result['seg'] as List;
      final ids = segs.map((s) => (s as Map)['id']).toList();
      expect(ids, containsAll(<int>[0, 2]));
      expect(ids, isNot(contains(1)));
      expect(ids, isNot(contains(3)));
    });
  });
}
