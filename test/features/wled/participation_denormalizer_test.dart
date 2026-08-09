// Tests for the S3b participation denormalizer (app-side publish decision).
//
// Pure logic only — no Firestore, no Riverpod. The Firestore write itself is
// a fire-and-forget wrapper verified on the bench (audit/S3B_CHANNELS.md §6).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/participation_denormalizer.dart';

void main() {
  setUp(resetParticipationMemo);

  group('shouldPublishParticipation', () {
    test('publishes when nothing has been published yet', () {
      expect(
        shouldPublishParticipation(resolved: [0, 1], lastPublished: null),
        isTrue,
      );
    });

    test('does NOT republish an unchanged set', () {
      // The resolve runs on every payload build; republishing each one would be
      // a write per apply, per user, forever, for a value that only changes
      // when hardware does.
      expect(
        shouldPublishParticipation(resolved: [0, 1], lastPublished: [0, 1]),
        isFalse,
      );
    });

    test('publishes when a channel is added', () {
      expect(
        shouldPublishParticipation(resolved: [0, 1, 2], lastPublished: [0, 1]),
        isTrue,
      );
    });

    test('publishes when a channel is removed', () {
      expect(
        shouldPublishParticipation(resolved: [0], lastPublished: [0, 1]),
        isTrue,
      );
    });

    test('publishes when the set changes without changing length', () {
      expect(
        shouldPublishParticipation(resolved: [0, 2], lastPublished: [0, 1]),
        isTrue,
      );
    });

    test('ORDER MATTERS — [1,0] is not treated as equal to [0,1]', () {
      // The resolver emits a sorted list, so a difference in order signals the
      // value did not come from the resolver and should be republished rather
      // than silently accepted as equal.
      expect(
        shouldPublishParticipation(resolved: [1, 0], lastPublished: [0, 1]),
        isTrue,
      );
    });

    test('an EMPTY set is publishable and distinct from never-published', () {
      // [] means "the customer excluded everything" — a real answer that must
      // reach the server, and must not be confused with "unknown".
      expect(
        shouldPublishParticipation(resolved: [], lastPublished: null),
        isTrue,
      );
      expect(
        shouldPublishParticipation(resolved: [], lastPublished: []),
        isFalse,
      );
    });
  });

  group('memo', () {
    test('remembering suppresses the next identical publish', () {
      expect(
        shouldPublishParticipation(
          resolved: [0, 1],
          lastPublished: publishedParticipationMemo['ctrl1'],
        ),
        isTrue,
      );
      rememberPublishedParticipation('ctrl1', [0, 1]);
      expect(
        shouldPublishParticipation(
          resolved: [0, 1],
          lastPublished: publishedParticipationMemo['ctrl1'],
        ),
        isFalse,
      );
    });

    test('is per-controller — one does not suppress another', () {
      rememberPublishedParticipation('ctrl1', [0, 1]);
      expect(
        shouldPublishParticipation(
          resolved: [0, 1],
          lastPublished: publishedParticipationMemo['ctrl2'],
        ),
        isTrue,
      );
    });

    test('stores a COPY — mutating the source cannot corrupt the memo', () {
      final live = [0, 1];
      rememberPublishedParticipation('ctrl1', live);
      live.add(2);
      expect(publishedParticipationMemo['ctrl1'], equals([0, 1]));
    });
  });

  group('buildParticipationDoc', () {
    test('carries the resolved set, the device shape, and the source', () {
      final doc = buildParticipationDoc(
        resolved: [0, 2],
        deviceChannelIds: [0, 1, 2, 3],
        source: 'game_day',
      );
      expect(doc[kParticipatingChannelsField], equals([0, 2]));
      expect(doc[kParticipatingChannelsDeviceIdsField], equals([0, 1, 2, 3]));
      expect(doc[kParticipatingChannelsSourceField], equals('game_day'));
      expect(doc.containsKey(kParticipatingChannelsAtField), isTrue);
    });

    test('records the DEVICE SHAPE, not just the answer', () {
      // Provenance: the resolved set is only meaningful against the bus list it
      // was computed from. Without it the stored list is an assertion with no
      // basis, and no future reader can judge whether it still applies.
      final doc = buildParticipationDoc(
        resolved: [0],
        deviceChannelIds: [0, 1],
        source: 'neighborhood_sync',
      );
      expect(doc[kParticipatingChannelsDeviceIdsField], equals([0, 1]));
    });

    test('copies its inputs — later mutation cannot alter the built doc', () {
      final resolved = [0];
      final devices = [0, 1];
      final doc = buildParticipationDoc(
        resolved: resolved,
        deviceChannelIds: devices,
        source: 'game_day',
      );
      resolved.add(9);
      devices.add(9);
      expect(doc[kParticipatingChannelsField], equals([0]));
      expect(doc[kParticipatingChannelsDeviceIdsField], equals([0, 1]));
    });

    test('field names are snake_case, matching the user/controller doc convention', () {
      expect(kParticipatingChannelsField, equals('participating_channels'));
      expect(kParticipatingChannelsAtField, equals('participating_channels_at'));
      expect(kParticipatingChannelsDeviceIdsField,
          equals('participating_channels_device_ids'));
    });
  });

  group('staleness horizon', () {
    test('is long enough not to strand a customer who rarely opens the app', () {
      expect(kParticipationMaxAge.inDays, greaterThanOrEqualTo(60));
    });

    test('is bounded — abandoned data does not drive lights forever', () {
      expect(kParticipationMaxAge.inDays, lessThanOrEqualTo(180));
    });
  });
}
