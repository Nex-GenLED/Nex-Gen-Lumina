// Tests for the in-memory participation cache (Bundle 3b.2).
//
// Cache contract:
//   - getCachedParticipatingChannels() lazy-loads from SharedPreferences
//     on first call, then returns the cached field on subsequent calls.
//   - saveLocalParticipatingChannels() updates the cache synchronously
//     before its async disk write (so applyJson sees the new value
//     immediately on the very next call).
//   - peekCachedParticipatingChannels() returns null until the cache is
//     warmed; never blocks.
//   - resetParticipationCacheForTest() clears the cache between tests.
//   - Null/empty/list semantics match Bundle 1/2 (null = no preference,
//     [] = explicit none, [..] = explicit set).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_persistence.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetParticipationCacheForTest();
  });

  group('participation cache', () {
    test('peek returns null before any load (cold cache)', () {
      expect(peekCachedParticipatingChannels(), isNull);
    });

    test('lazy load: first get() reads SharedPreferences', () async {
      await saveLocalParticipatingChannels(const [0, 1]);
      // Reset cache so the next get() must reload from disk.
      resetParticipationCacheForTest();
      expect(peekCachedParticipatingChannels(), isNull);
      final loaded = await getCachedParticipatingChannels();
      expect(loaded, equals([0, 1]));
      expect(peekCachedParticipatingChannels(), equals([0, 1]));
    });

    test('lazy load: subsequent get() does NOT re-read disk', () async {
      await saveLocalParticipatingChannels(const [0, 1]);
      resetParticipationCacheForTest();
      await getCachedParticipatingChannels();
      // Now mutate the SharedPreferences-backed value WITHOUT going
      // through saveLocalParticipatingChannels (so the cache is NOT
      // updated). The next get() should still return the cached value
      // because the lazy-load is one-shot.
      SharedPreferences.setMockInitialValues(
        <String, Object>{'bg_local_participating_channels': ['9']},
      );
      final second = await getCachedParticipatingChannels();
      expect(second, equals([0, 1]),
          reason: 'cache must not re-read disk on subsequent gets');
    });

    test(
        'saveLocalParticipatingChannels updates the cache synchronously '
        '(no need to await the disk write to see the new value)', () async {
      // Cold cache → null
      expect(peekCachedParticipatingChannels(), isNull);
      // Save without awaiting: the cache update is sync, so peek should
      // return the new value immediately. Disk write completes later.
      final saveFuture = saveLocalParticipatingChannels(const [1]);
      expect(peekCachedParticipatingChannels(), equals([1]),
          reason: 'cache should reflect save before disk write completes');
      await saveFuture;
      expect(peekCachedParticipatingChannels(), equals([1]));
    });

    test('save with null clears the cache', () async {
      await saveLocalParticipatingChannels(const [0, 1]);
      expect(peekCachedParticipatingChannels(), equals([0, 1]));
      await saveLocalParticipatingChannels(null);
      expect(peekCachedParticipatingChannels(), isNull);
    });

    test('save with empty list caches as empty (distinct from null)', () async {
      await saveLocalParticipatingChannels(const []);
      expect(peekCachedParticipatingChannels(), isNotNull);
      expect(peekCachedParticipatingChannels(), isEmpty);
    });

    test('cache update is defensive: caller cannot mutate the cached list',
        () async {
      final original = <int>[0, 1];
      await saveLocalParticipatingChannels(original);
      // Mutating the original list after save MUST NOT affect the cache.
      original.add(99);
      expect(peekCachedParticipatingChannels(), equals([0, 1]));
    });

    test('lazy load returns null when no key is persisted', () async {
      // SharedPreferences mock is empty.
      final loaded = await getCachedParticipatingChannels();
      expect(loaded, isNull);
      expect(peekCachedParticipatingChannels(), isNull);
    });

    test('resetParticipationCacheForTest fully clears state', () async {
      await saveLocalParticipatingChannels(const [0, 1]);
      expect(peekCachedParticipatingChannels(), equals([0, 1]));
      resetParticipationCacheForTest();
      expect(peekCachedParticipatingChannels(), isNull);
    });

    test(
        'multiple save/load cycles converge: last save wins, cache and '
        'disk stay aligned', () async {
      await saveLocalParticipatingChannels(const [0, 1]);
      await saveLocalParticipatingChannels(const [1]);
      await saveLocalParticipatingChannels(const [0, 1, 2]);
      expect(peekCachedParticipatingChannels(), equals([0, 1, 2]));
      // Cold-reload from disk should match.
      resetParticipationCacheForTest();
      final reloaded = await getCachedParticipatingChannels();
      expect(reloaded, equals([0, 1, 2]));
    });
  });
}
