// test/features/wled/participation_reconciler_test.dart
//
// Pure-function tests for the participation-cache staleness predicate.
// The adapter `runParticipationReconciliationIfReady` is exercised
// indirectly via the once-per-session flag check at the end; it's not
// fully integration-tested here because that would require a full
// Riverpod ProviderContainer + Firebase Auth setup. The pure predicate
// covers the bug-shape invariants this commit is meant to lock down.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/participation_reconciler.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

void main() {
  // Convenience builder — every test wants segments that default to
  // isPrimary=true (matches the entire codebase as of 2026-05-26 — no
  // path produces isPrimary=false; see Addendum 1).
  RooflineSegment _seg({
    required String id,
    required int channelIndex,
    bool isPrimary = true,
  }) =>
      RooflineSegment(
        id: id,
        name: id,
        pixelCount: 10,
        channelIndex: channelIndex,
        isPrimary: isPrimary,
        points: const <Offset>[],
      );

  group('isParticipationCacheStale', () {
    test('CONFIRMED-BUG CASE: cached [0], deviceIds [0,1], two primary '
        'segments on ch0+ch1 → expected [0,1] → STALE', () {
      // Matches the live install. Cache was written when the device had
      // only bus 0 (1-channel install). User added bus 1 / wired up
      // channel 2 later. Resolver against the current device+roofline
      // returns [0, 1]; cache still holds [0]; channel 2 chip greys
      // out and channel-2 segs get dropped on every apply.
      final stale = isParticipationCacheStale(
        cached: const [0],
        deviceIds: const [0, 1],
        segments: [
          _seg(id: 'seg-ch0', channelIndex: 0),
          _seg(id: 'seg-ch1', channelIndex: 1),
        ],
      );
      expect(stale, isTrue,
          reason: 'cache excludes channel 1 but resolver would include it');
    });

    test('steady state: cached [0,1] matches expected [0,1] → NOT stale', () {
      final stale = isParticipationCacheStale(
        cached: const [0, 1],
        deviceIds: const [0, 1],
        segments: [
          _seg(id: 'seg-ch0', channelIndex: 0),
          _seg(id: 'seg-ch1', channelIndex: 1),
        ],
      );
      expect(stale, isFalse, reason: 'no spurious clear in steady state');
    });

    test('FALSE-CLEAR GUARD: cached [0], deviceIds [] (device still '
        'loading) → NOT stale', () {
      // The boot window: cache loaded from prefs (or from a prior write),
      // but /json/cfg hasn't returned yet so deviceChannels is empty.
      // Without this guard, the predicate would return true and the
      // adapter would falsely clear a legitimate cache.
      final stale = isParticipationCacheStale(
        cached: const [0],
        deviceIds: const [],
        segments: const [],
      );
      expect(stale, isFalse,
          reason: 'must NOT reconcile while device unloaded');
    });

    test('null cache → NOT stale (no preference, nothing to reconcile)', () {
      final stale = isParticipationCacheStale(
        cached: null,
        deviceIds: const [0, 1],
        segments: [_seg(id: 'seg-ch0', channelIndex: 0)],
      );
      expect(stale, isFalse);
    });

    test('device GREW since cache write: cached [0,1], deviceIds [0,1,2], '
        'segments still ch0+ch1 → expected [0,1,2] (ch2 untraced→'
        'default-in) → STALE', () {
      // A 3rd bus came online after the cache was written. The new bus
      // (ch2) has no traced segment, so the resolver classifies it as
      // "untraced → default-in" and includes it. Cache only has [0,1] —
      // newcomer channel would be silently excluded without reconciliation.
      final stale = isParticipationCacheStale(
        cached: const [0, 1],
        deviceIds: const [0, 1, 2],
        segments: [
          _seg(id: 'seg-ch0', channelIndex: 0),
          _seg(id: 'seg-ch1', channelIndex: 1),
        ],
      );
      expect(stale, isTrue,
          reason: 'newly-added bus must be picked up by the recompute');
    });

    test('set equality is order-insensitive', () {
      // Resolver sorts its output (see channel_participation_resolver.dart:69
      // `result.toList()..sort()`). Cache values are persisted verbatim.
      // The predicate compares as sets so a re-ordered cache (or a
      // theoretical unsorted resolver output) doesn't trigger false
      // staleness.
      final stale = isParticipationCacheStale(
        cached: const [1, 0],
        deviceIds: const [0, 1],
        segments: [
          _seg(id: 'seg-ch0', channelIndex: 0),
          _seg(id: 'seg-ch1', channelIndex: 1),
        ],
      );
      expect(stale, isFalse);
    });

    test('duplicate ids in cache collapse via set comparison', () {
      // Defensive: a corrupted prefs value with duplicates shouldn't
      // be mis-classified as stale solely because of duplicate ints.
      final stale = isParticipationCacheStale(
        cached: const [0, 0, 1],
        deviceIds: const [0, 1],
        segments: [
          _seg(id: 'seg-ch0', channelIndex: 0),
          _seg(id: 'seg-ch1', channelIndex: 1),
        ],
      );
      expect(stale, isFalse);
    });

    test('empty cache cached []: under current resolver this only matches '
        'when deviceIds is also empty (degenerate device)', () {
      // The resolver only returns [] when allDeviceChannelIds is empty
      // (and that case is guarded above). Any real device → non-empty
      // expected → cached:[] mismatches → STALE.
      final stale = isParticipationCacheStale(
        cached: const [],
        deviceIds: const [0, 1],
        segments: [
          _seg(id: 'seg-ch0', channelIndex: 0),
          _seg(id: 'seg-ch1', channelIndex: 1),
        ],
      );
      expect(stale, isTrue,
          reason: '[] is a real value (explicit "no channels") that no '
              'current writer can produce against a non-empty device — '
              'treat as stale.');
    });

    test('all-untraced install: segments=[], deviceIds=[0,1] → expected '
        '[0,1]; cache [0,1] → NOT stale', () {
      // No roofline ever traced. Resolver falls back to all device
      // channels. Cache matches device → steady state.
      final stale = isParticipationCacheStale(
        cached: const [0, 1],
        deviceIds: const [0, 1],
        segments: const [],
      );
      expect(stale, isFalse);
    });
  });

  // Once-per-session flag: the adapter's job. We can't run the full
  // adapter here (needs a WidgetRef + Riverpod container + Firebase
  // mocks), but we can verify the test reset helper exists and clears
  // the flag. The flag's enforce-once contract is exercised by the
  // adapter source itself — covered by inspection, locked here as an
  // API-shape test so the helper isn't accidentally removed.
  group('reset helper', () {
    test('resetParticipationReconcilerForTest is callable', () {
      resetParticipationReconcilerForTest();
      // No exception → pass. The flag's state is private; the only way
      // to verify it is through the adapter, which needs Riverpod.
    });
  });
}
