// Contract tests for the join path's UI-observable outcome.
//
// Background: a join could FULLY SUCCEED in Firestore (uid appended to
// neighborhoods/{gid}/memberUids AND the members/{uid} doc written) while the
// UI showed nothing at all. Two causes, both covered here:
//   1. the notifier's success path must publish the joined group id, because
//      that is what the screen uses to enter the group; and
//   2. the notifier's failure path must PRESERVE the error in state, because
//      the call sites now read `notifierState.error` to show a red snackbar
//      (mirroring _createGroup). Previously the catch returned bare null and
//      the reason was unrecoverable.
//
// These assert the seam the UI depends on, not the widgets themselves.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';

NeighborhoodGroup _group({String id = 'g1', String name = 'Maple Street'}) {
  return NeighborhoodGroup(
    id: id,
    name: name,
    isPublic: false,
    inviteCode: 'ABC123',
    creatorUid: 'creator-uid',
    createdAt: DateTime.utc(2026, 7, 27),
    memberUids: const ['creator-uid', 'joiner-uid'],
    isActive: false,
  );
}

/// Stands in for the real service. `joinGroup` is the only member exercised.
///
/// `implements` (not `extends`) on purpose: NeighborhoodService's constructor
/// defaults to `FirebaseFirestore.instance`, which needs a live Firebase app.
/// noSuchMethod covers the rest of the surface — anything else this test calls
/// should fail loudly rather than hit a real backend.
class _FakeNeighborhoodService implements NeighborhoodService {
  _FakeNeighborhoodService({this.result, this.throws});

  final NeighborhoodGroup? result;
  final Object? throws;

  String? lastInviteCode;
  String? lastDisplayName;

  @override
  Future<NeighborhoodGroup?> joinGroup(
    String inviteCode, {
    String? displayName,
  }) async {
    lastInviteCode = inviteCode;
    lastDisplayName = displayName;
    if (throws != null) throw throws!;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

ProviderContainer _containerWith(_FakeNeighborhoodService service) {
  final container = ProviderContainer(
    overrides: [neighborhoodServiceProvider.overrideWithValue(service)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('NeighborhoodNotifier.joinGroup — success is observable by the UI', () {
    test('publishes the joined group id so the screen can enter the group', () async {
      final container = _containerWith(
        _FakeNeighborhoodService(result: _group(id: 'g-joined')),
      );

      expect(container.read(activeNeighborhoodIdProvider), isNull);

      final joined = await container
          .read(neighborhoodNotifierProvider.notifier)
          .joinGroup('ABC123');

      expect(joined, isNotNull);
      expect(joined!.id, 'g-joined');
      // THE regression guard: without this the join landed in Firestore but the
      // UI had no active group to open, so it sat on the Sync screen.
      expect(container.read(activeNeighborhoodIdProvider), 'g-joined');
    });

    test('leaves notifier state non-error on success', () async {
      final container = _containerWith(
        _FakeNeighborhoodService(result: _group()),
      );

      await container
          .read(neighborhoodNotifierProvider.notifier)
          .joinGroup('ABC123');

      expect(container.read(neighborhoodNotifierProvider).hasError, isFalse);
    });

    test('forwards invite code and display name to the service', () async {
      final service = _FakeNeighborhoodService(result: _group());
      final container = _containerWith(service);

      await container
          .read(neighborhoodNotifierProvider.notifier)
          .joinGroup('abc123', displayName: 'The Corner House');

      expect(service.lastInviteCode, 'abc123');
      expect(service.lastDisplayName, 'The Corner House');
    });
  });

  group('NeighborhoodNotifier.joinGroup — failure is recoverable by the UI', () {
    test('returns null AND preserves the error for the red snackbar', () async {
      final container = _containerWith(
        _FakeNeighborhoodService(throws: StateError('permission-denied')),
      );

      final joined = await container
          .read(neighborhoodNotifierProvider.notifier)
          .joinGroup('ABC123');

      expect(joined, isNull);
      final state = container.read(neighborhoodNotifierProvider);
      // Call sites branch on hasError to distinguish a real failure (red,
      // shows the reason) from a genuine bad code (orange, "check the code").
      expect(state.hasError, isTrue);
      expect(state.error.toString(), contains('permission-denied'));
    });

    test('does not set an active group id when the join fails', () async {
      final container = _containerWith(
        _FakeNeighborhoodService(throws: StateError('nope')),
      );

      await container
          .read(neighborhoodNotifierProvider.notifier)
          .joinGroup('ABC123');

      expect(container.read(activeNeighborhoodIdProvider), isNull);
    });

    test('a null result with NO error is distinguishable from an error', () async {
      // Service returns null without throwing == invite code matched nothing.
      // The rejoin path relies on this distinction before it DELETES the saved
      // group entry, so it must stay observable.
      final container = _containerWith(_FakeNeighborhoodService(result: null));

      final joined = await container
          .read(neighborhoodNotifierProvider.notifier)
          .joinGroup('BADCODE');

      expect(joined, isNull);
      expect(container.read(neighborhoodNotifierProvider).hasError, isFalse);
    });
  });
}
