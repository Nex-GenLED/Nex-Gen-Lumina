// Build 120 — the member-side stale-command guard (owner decision
// 2026-10-21). The listener's query returns the newest command with no age
// limit and a past start executes immediately, so a member whose app was
// closed when a sync started used to get the look the next time the app
// opened, hours or days later. Now:
//   • a START command first seen more than kSyncCommandMaxAge (4 h) after its
//     start time is ignored;
//   • a START command at or before the newest teardown acted on is ignored;
//   • teardowns are never ignored (a restore is always safe);
//   • nothing here touches a running session: the guard runs on a newly seen
//     emission only.
// The clock is a seam, so every case runs against a fixed "now".
//
// Synthetic group and member ids only.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 10, 21, 20, 0);

  SyncCommand start(String id, DateTime at) => SyncCommand(
        id: id,
        groupId: 'g',
        effectId: 5,
        colors: const [0xFF0000],
        speed: 128,
        intensity: 128,
        brightness: 200,
        startTimestamp: at,
        memberDelays: const {'u1': 0},
        timingConfig: const SyncTimingConfig(),
      );

  SyncCommand teardown(String id, DateTime at) => SyncCommand(
        id: id,
        groupId: 'g',
        effectId: 0,
        colors: const [],
        speed: 0,
        intensity: 0,
        brightness: 0,
        startTimestamp: at,
        memberDelays: const {},
        timingConfig: const SyncTimingConfig(),
        isTeardown: true,
      );

  _SpyEngine engineFor() {
    late _SpyEngine spy;
    final container = ProviderContainer(overrides: [
      neighborhoodSyncEngineProvider.overrideWith((ref) {
        spy = _SpyEngine(ref);
        return spy;
      }),
      currentUserMemberProvider.overrideWith((ref) => NeighborhoodMember(
            oderId: 'u1',
            displayName: 'Me',
            positionIndex: 0,
            lastSeen: now,
            isParticipating: true,
          )),
    ]);
    addTearDown(container.dispose);
    container.read(neighborhoodSyncEngineProvider);
    spy.clock = () => now;
    return spy;
  }

  void see(_SpyEngine spy, SyncCommand c, {SyncCommand? previous}) =>
      spy.handleCommandSnapshot(
        previous == null ? null : AsyncValue.data(previous),
        AsyncValue.data(c),
      );

  group('age rule (kSyncCommandMaxAge = 4 h)', () {
    test('the limit is four hours', () {
      expect(NeighborhoodSyncEngine.kSyncCommandMaxAge, const Duration(hours: 4));
    });

    test('a start first seen 3 h 59 min after its start time applies', () {
      final spy = engineFor();
      see(spy, start('s1', now.subtract(const Duration(hours: 3, minutes: 59))));
      expect(spy.applyCount, 1);
    });

    test('a start first seen 4 h 1 min after its start time is ignored', () {
      final spy = engineFor();
      see(spy, start('s1', now.subtract(const Duration(hours: 4, minutes: 1))));
      expect(spy.applyCount, 0);
    });

    test('a start whose start time is still ahead of the clock applies',
        () {
      final spy = engineFor();
      see(spy, start('s1', now.add(const Duration(seconds: 2))));
      expect(spy.applyCount, 1);
    });

    test('a teardown is never ignored, however old', () {
      final spy = engineFor();
      see(spy, teardown('t1', now.subtract(const Duration(days: 3))));
      expect(spy.teardownCount, 1);
      expect(spy.applyCount, 0);
    });
  });

  group('newest-teardown rule', () {
    test('a start at or before the newest teardown is ignored', () {
      final spy = engineFor();
      final endedAt = now.subtract(const Duration(minutes: 30));
      see(spy, teardown('t1', endedAt));
      see(spy, start('s-old', endedAt.subtract(const Duration(minutes: 1))),
          previous: teardown('t1', endedAt));
      see(spy, start('s-same', endedAt), previous: start('s-old', endedAt));
      expect(spy.teardownCount, 1);
      expect(spy.applyCount, 0, reason: 'both predate the end of the session');
    });

    test('a start after the newest teardown applies (a new session)', () {
      final spy = engineFor();
      final endedAt = now.subtract(const Duration(minutes: 30));
      see(spy, teardown('t1', endedAt));
      see(spy, start('s-new', endedAt.add(const Duration(minutes: 1))),
          previous: teardown('t1', endedAt));
      expect(spy.applyCount, 1);
    });

    test('a replayed teardown still records its time (dedup runs after)', () {
      final spy = engineFor();
      final endedAt = now.subtract(const Duration(minutes: 10));
      see(spy, teardown('t1', endedAt));
      see(spy, teardown('t1', endedAt), previous: teardown('t1', endedAt));
      expect(spy.teardownCount, 1, reason: 'dedup by id still holds');
      see(spy, start('s-old', endedAt.subtract(const Duration(minutes: 5))),
          previous: teardown('t1', endedAt));
      expect(spy.applyCount, 0);
    });

    test('an older teardown never moves the mark backwards', () {
      final spy = engineFor();
      final later = now.subtract(const Duration(minutes: 10));
      final earlier = now.subtract(const Duration(hours: 1));
      see(spy, teardown('t-later', later));
      see(spy, teardown('t-earlier', earlier),
          previous: teardown('t-later', later));
      see(spy, start('s', later.subtract(const Duration(minutes: 1))),
          previous: teardown('t-earlier', earlier));
      expect(spy.applyCount, 0, reason: 'the mark stayed at the later teardown');
    });
  });

  group('unchanged behaviour', () {
    test('a fresh start with no teardown history applies once and dedups '
        'the replay', () {
      final spy = engineFor();
      final c = start('s1', now.subtract(const Duration(minutes: 5)));
      see(spy, c);
      see(spy, c, previous: c);
      expect(spy.applyCount, 1);
    });

    test('an error emission schedules nothing and applies nothing', () {
      final spy = engineFor();
      spy.handleCommandSnapshot(
          null, AsyncValue.error(StateError('boom'), StackTrace.empty));
      expect(spy.applyCount, 0);
      expect(spy.teardownCount, 0);
    });
  });
}

class _SpyEngine extends NeighborhoodSyncEngine {
  _SpyEngine(super.ref);

  int teardownCount = 0;
  int applyCount = 0;

  @override
  void dispatchTeardown() {
    teardownCount++;
  }

  @override
  void onNewSyncCommand(SyncCommand command) {
    applyCount++;
  }

  @override
  void scheduleCommandStreamResubscribe() {}
}
