// test/features/schedule/sortkey_seed_test.dart
//
// Guards SchedulesNotifier.nextSortKeySeed — the belt-and-braces floor that
// stops a backfill gap from re-creating the sortKey-collision class.
//
// THE BUG IT DEFENDS: the array→subcollection backfill stamped sortKey onto the
// SUBCOLLECTION docs only. A user whose legacy ARRAY items predate the field
// deserializes to all-zero (ScheduleItem.fromJson: `?? 0`), so a max-based seed
// collapses to 1 — colliding with the contiguous 0..n-1 already in their
// subcollection. The mirrored write ties on sortKey and the subcollection's
// orderBy read diverges from the array's insertion order on a later flag flip.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';

ScheduleItem mk(String id, int sortKey) => ScheduleItem(
      id: id,
      timeLabel: '7:00 PM',
      repeatDays: const ['Daily'],
      actionLabel: 'Pattern: $id',
      enabled: true,
      sortKey: sortKey,
    );

/// A legacy array read: every item deserializes to sortKey 0.
List<ScheduleItem> legacyArray(int n) =>
    [for (var i = 0; i < n; i++) mk('legacy-$i', 0)];

/// A repaired / natively-written set: contiguous 0..n-1.
List<ScheduleItem> contiguous(int n) =>
    [for (var i = 0; i < n; i++) mk('item-$i', i)];

void main() {
  group('nextSortKeySeed', () {
    test('empty state → 1 (unchanged legacy behaviour)', () {
      expect(SchedulesNotifier.nextSortKeySeed(const []), 1);
    });

    test('all-zero legacy array of n → n (THE FIX; max-based seed would give 1)', () {
      // 3 legacy items + a subcollection backfilled 0,1,2 → the new key must
      // clear that block. The old `max+1` gave 1, colliding with sub sortKey 1.
      expect(SchedulesNotifier.nextSortKeySeed(legacyArray(3)), 3);
      expect(SchedulesNotifier.nextSortKeySeed(legacyArray(7)), 7);
      expect(SchedulesNotifier.nextSortKeySeed(legacyArray(1)), 1);
    });

    test('contiguous 0..n-1 → n (identical to the max-based seed)', () {
      expect(SchedulesNotifier.nextSortKeySeed(contiguous(3)), 3);
      expect(SchedulesNotifier.nextSortKeySeed(contiguous(7)), 7);
    });

    test('sparse keys → max+1; the length floor never LOWERS the seed', () {
      expect(SchedulesNotifier.nextSortKeySeed([mk('a', 0), mk('b', 1), mk('c', 5)]), 6);
      expect(SchedulesNotifier.nextSortKeySeed([mk('a', 99)]), 100);
    });

    test('seed never collides with a key already in state', () {
      final states = <List<ScheduleItem>>[
        const [],
        legacyArray(1),
        legacyArray(5),
        contiguous(4),
        [mk('a', 0), mk('b', 1), mk('c', 5)],
        [mk('a', 99)],
      ];
      for (final s in states) {
        final seed = SchedulesNotifier.nextSortKeySeed(s);
        expect(s.map((e) => e.sortKey), isNot(contains(seed)),
            reason: 'seed $seed collides with an existing key');
        for (final item in s) {
          expect(seed, greaterThan(item.sortKey),
              reason: 'seed must exceed every existing key');
        }
      }
    });

    test('regression: legacy array + backfilled subcollection → no collision', () {
      // The exact production shape found on all 4 migrated users.
      const backfilledSubKeys = [0, 1, 2]; // what the backfill stamped
      final seed = SchedulesNotifier.nextSortKeySeed(legacyArray(3));
      expect(backfilledSubKeys, isNot(contains(seed)),
          reason: 'new key must not collide with the backfilled block');
      expect(seed, 3);
    });
  });
}
