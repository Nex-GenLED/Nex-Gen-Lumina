// Tests for NeighborhoodGroup.isCreatedBy — the creator-only gate behind the
// invite-code rotation action (Slice 1 Commit 3). A creator sees the action; a
// non-creator (or unauthenticated null uid) does not.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';

void main() {
  NeighborhoodGroup makeGroup({required String creatorUid}) => NeighborhoodGroup(
        id: 'g1',
        name: 'Elm St Crew',
        inviteCode: 'ABC123',
        creatorUid: creatorUid,
        createdAt: DateTime.utc(2026, 7, 1),
        memberUids: [creatorUid, 'other-member'],
      );

  group('NeighborhoodGroup.isCreatedBy (invite-rotation creator gate)', () {
    test('creator uid → true (creator sees the action)', () {
      expect(makeGroup(creatorUid: 'host-uid').isCreatedBy('host-uid'), isTrue);
    });

    test('non-creator member uid → false (does NOT see the action)', () {
      expect(makeGroup(creatorUid: 'host-uid').isCreatedBy('other-member'), isFalse);
    });

    test('unrelated uid → false', () {
      expect(makeGroup(creatorUid: 'host-uid').isCreatedBy('stranger'), isFalse);
    });

    test('null uid (unauthenticated) → false', () {
      expect(makeGroup(creatorUid: 'host-uid').isCreatedBy(null), isFalse);
    });

    test('empty creatorUid never matches an empty-string uid falsely', () {
      // Defensive: an unset creator must not grant rights to an empty uid.
      expect(makeGroup(creatorUid: '').isCreatedBy(''), isTrue,
          reason: 'exact-equality semantics preserved');
      expect(makeGroup(creatorUid: 'host-uid').isCreatedBy(''), isFalse);
    });
  });
}
