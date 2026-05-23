// Tests for resolveParticipatingChannels — the pure default-participation
// policy used by Neighborhood Sync and Game Day to decide which controller
// channels participate in a show.
//
// Contract (2026-05-23 — Lever 2 update):
//   - Explicit non-null list (user picker / trace-time choice) wins verbatim,
//     including explicit exclusions: if the list omits a channel it stays out.
//   - Null + roofline segments present:
//       • channels with at least one isPrimary segment participate
//       • channels with segments but none primary → excluded
//       • channels with NO segment at all but present in allDeviceChannelIds
//         (untraced device channels — patio, accent, side strip) → PARTICIPATE
//         (the Lever 2 fix; previously excluded)
//   - Null + no roofline segments (untraced install): ALL device channels
//     participate (backward-safe fallback, unchanged).
//   - Explicit empty list [] is distinct from null — explicit "no channels".

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/services/channel_participation_resolver.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

void main() {
  group('resolveParticipatingChannels — default policy (explicit == null)', () {
    test('Case 1: all-primary segments across 2 channels → both participate', () {
      final result = resolveParticipatingChannels(
        explicit: null,
        segments: [
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
          _seg(id: 's1', channelIndex: 0, isPrimary: true),
          _seg(id: 's2', channelIndex: 1, isPrimary: true),
        ],
        allDeviceChannelIds: const [0, 1],
      );
      expect(result, equals([0, 1]));
    });

    test('Case 2: channel 1 has only non-primary segments → excluded', () {
      final result = resolveParticipatingChannels(
        explicit: null,
        segments: [
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
          _seg(id: 's1', channelIndex: 1, isPrimary: false),
          _seg(id: 's2', channelIndex: 1, isPrimary: false),
        ],
        allDeviceChannelIds: const [0, 1],
      );
      expect(result, equals([0]));
    });

    test(
        'Case 3: no roofline configuration (empty segments) → ALL device '
        'channels participate (untraced-install fallback)', () {
      final result = resolveParticipatingChannels(
        explicit: null,
        segments: const [],
        allDeviceChannelIds: const [0, 1, 2, 3],
      );
      expect(result, equals([0, 1, 2, 3]));
    });

    test(
        'Case 4 (Lever 2 flipped): partially-traced — channel 2 has no '
        'segments while 0 and 1 have primary segments → channel 2 NOW '
        'PARTICIPATES (untraced device channel defaults in).', () {
      final result = resolveParticipatingChannels(
        explicit: null,
        segments: [
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
          _seg(id: 's1', channelIndex: 1, isPrimary: true),
        ],
        allDeviceChannelIds: const [0, 1, 2],
      );
      expect(result, equals([0, 1, 2]));
    });

    test(
        'Case 4b (Tyler bench scenario): single primary segment on ch0 plus '
        'an untraced ch1 device channel → both participate. This is the '
        'real-install symptom that motivated Lever 2.', () {
      final result = resolveParticipatingChannels(
        explicit: null,
        segments: [
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
        ],
        allDeviceChannelIds: const [0, 1],
      );
      expect(result, equals([0, 1]));
    });

    test(
        'Case 4c: untraced channel ids NOT in allDeviceChannelIds are NOT '
        'invented — only physical device channels can be defaulted in.', () {
      final result = resolveParticipatingChannels(
        explicit: null,
        segments: [
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
        ],
        // ch5 not on device — even though it has no segment, it shouldn't
        // appear in the result because allDeviceChannelIds doesn't list it.
        allDeviceChannelIds: const [0, 1],
      );
      expect(result, isNot(contains(5)));
      expect(result, equals([0, 1]));
    });
  });

  group('resolveParticipatingChannels — explicit override', () {
    test('Case 5: explicit [1] → returns [1] verbatim, ignoring defaults', () {
      final result = resolveParticipatingChannels(
        explicit: const [1],
        segments: [
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
          _seg(id: 's1', channelIndex: 1, isPrimary: true),
        ],
        allDeviceChannelIds: const [0, 1],
      );
      expect(result, equals([1]));
    });

    test(
        'Case 6: explicit empty [] → returns [] (explicit "no channels"), '
        'distinct from null', () {
      final result = resolveParticipatingChannels(
        explicit: const [],
        segments: [
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
          _seg(id: 's1', channelIndex: 1, isPrimary: true),
        ],
        allDeviceChannelIds: const [0, 1],
      );
      expect(result, isEmpty);
    });

    test('Case 7: null with valid config → runs primary-derived default', () {
      final result = resolveParticipatingChannels(
        explicit: null,
        segments: [
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
          _seg(id: 's1', channelIndex: 1, isPrimary: false),
        ],
        allDeviceChannelIds: const [0, 1],
      );
      expect(result, equals([0]));
    });

    test(
        'Case 8 (Lever 2 regression guard): explicit [0] with an untraced ch1 '
        'device channel → returns [0]. Explicit exclusions MUST still exclude, '
        'even when the omitted channel would otherwise default in under the '
        'new untraced-defaults-in policy.', () {
      final result = resolveParticipatingChannels(
        explicit: const [0],
        segments: [
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
        ],
        allDeviceChannelIds: const [0, 1],
      );
      expect(result, equals([0]));
    });
  });

  group('resolveParticipatingChannels — edge cases', () {
    test('explicit list survives unchanged even if it names unknown channels',
        () {
      // Picker is the source of truth; if it names channel 9 on a 2-channel
      // device, the resolver returns it as-is. Filtering against the device's
      // current bus list is the apply-site's job, not the resolver's.
      final result = resolveParticipatingChannels(
        explicit: const [9],
        segments: const [],
        allDeviceChannelIds: const [0, 1],
      );
      expect(result, equals([9]));
    });

    test('default-policy result is sorted by channel id ascending', () {
      final result = resolveParticipatingChannels(
        explicit: null,
        segments: [
          _seg(id: 's2', channelIndex: 2, isPrimary: true),
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
          _seg(id: 's1', channelIndex: 1, isPrimary: true),
        ],
        allDeviceChannelIds: const [0, 1, 2],
      );
      expect(result, equals([0, 1, 2]));
    });

    test(
        'mixed primary/non-primary on the same channel → channel participates '
        'as long as at least ONE segment is primary', () {
      final result = resolveParticipatingChannels(
        explicit: null,
        segments: [
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
          _seg(id: 's1', channelIndex: 0, isPrimary: false),
        ],
        allDeviceChannelIds: const [0],
      );
      expect(result, equals([0]));
    });

    test(
        'device-offline edge: allDeviceChannelIds is empty (resolver fired '
        'before the device responded) → returns only primary-derived '
        'channels. Untraced channels cannot be defaulted in when the device '
        'has not been seen; the next resolution after the device comes back '
        'will include them.', () {
      final result = resolveParticipatingChannels(
        explicit: null,
        segments: [
          _seg(id: 's0', channelIndex: 0, isPrimary: true),
        ],
        allDeviceChannelIds: const [],
      );
      expect(result, equals([0]));
    });
  });
}

/// Test helper: build a RooflineSegment with only the fields the resolver
/// inspects. All other fields take their constructor defaults.
RooflineSegment _seg({
  required String id,
  required int channelIndex,
  required bool isPrimary,
}) {
  return RooflineSegment(
    id: id,
    name: id,
    pixelCount: 10,
    channelIndex: channelIndex,
    isPrimary: isPrimary,
  );
}
