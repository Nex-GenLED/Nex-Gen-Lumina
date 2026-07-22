// test/utils/async_lock_test.dart
//
// Coverage for [AsyncLock] — the dependency-free async mutex that
// Item #61 Workstream B Prompt 5 uses to serialize WLED writes.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/utils/async_lock.dart';

void main() {
  // ────────────────────────────────────────────────────────────────
  // Group: AsyncLock basics
  // ────────────────────────────────────────────────────────────────
  group('AsyncLock basics', () {
    test("single synchronized call returns the body's return value",
        () async {
      final lock = AsyncLock();
      final result = await lock.synchronized(() async => 42);
      expect(result, 42);
    });

    test('synchronized call with a void body completes', () async {
      final lock = AsyncLock();
      var ran = false;
      await lock.synchronized<void>(() async {
        ran = true;
      });
      expect(ran, isTrue);
    });

    test('exception in body propagates to caller', () async {
      final lock = AsyncLock();
      Object? caught;
      try {
        await lock.synchronized(() async => throw StateError('boom'));
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>());
      expect((caught as StateError).message, 'boom');
    });

    test('lock releases after exception (next caller still runs)',
        () async {
      final lock = AsyncLock();
      try {
        await lock.synchronized(() async => throw Exception('boom'));
      } catch (_) {/* swallow */}
      final result = await lock.synchronized(() async => 'ok');
      expect(result, 'ok');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: AsyncLock serialization
  // ────────────────────────────────────────────────────────────────
  group('AsyncLock serialization', () {
    test('two simultaneous calls run sequentially, not in parallel',
        () async {
      final lock = AsyncLock();
      var inside = false;
      var overlapDetected = false;

      Future<void> run() => lock.synchronized(() async {
            if (inside) overlapDetected = true;
            inside = true;
            // Yield to give a second caller the opportunity to enter
            // — if the lock is broken, this is where overlap occurs.
            await Future.delayed(const Duration(milliseconds: 10));
            inside = false;
          });

      await Future.wait([run(), run()]);
      expect(overlapDetected, isFalse);
    });

    test('ten simultaneous calls preserve FIFO order', () async {
      final lock = AsyncLock();
      final order = <int>[];
      final futures = <Future<void>>[];

      for (int i = 0; i < 10; i++) {
        futures.add(lock.synchronized(() async {
          order.add(i);
          // Force a microtask yield inside the critical section so
          // FIFO ordering is non-trivial (if it were just "synchronous
          // body" semantics, the test wouldn't exercise the lock).
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }));
      }
      await Future.wait(futures);
      expect(order, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    });

    test('a slow call followed by a fast call — fast waits for slow',
        () async {
      final lock = AsyncLock();
      DateTime? slowCompletedAt;
      DateTime? fastStartedAt;

      final slow = lock.synchronized(() async {
        await Future.delayed(const Duration(milliseconds: 50));
        slowCompletedAt = DateTime.now();
      });
      final fast = lock.synchronized(() async {
        fastStartedAt = DateTime.now();
      });

      await Future.wait([slow, fast]);
      expect(slowCompletedAt, isNotNull);
      expect(fastStartedAt, isNotNull);
      expect(
        fastStartedAt!.isBefore(slowCompletedAt!),
        isFalse,
        reason: 'Fast caller should not have started before slow finished',
      );
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: AsyncLock with mixed types
  // ────────────────────────────────────────────────────────────────
  group('AsyncLock with mixed types', () {
    test('synchronized<int> returns int', () async {
      final lock = AsyncLock();
      final r = await lock.synchronized<int>(() async => 42);
      expect(r, isA<int>());
      expect(r, 42);
    });

    test('synchronized<String> returns String', () async {
      final lock = AsyncLock();
      final r = await lock.synchronized<String>(() async => 'hello');
      expect(r, isA<String>());
      expect(r, 'hello');
    });

    test('synchronized<void> works without explicit type', () async {
      final lock = AsyncLock();
      var ran = false;
      // Implicit type inference — the body returns Future<Null>, but
      // the call site doesn't care about the return value.
      await lock.synchronized(() async {
        ran = true;
      });
      expect(ran, isTrue);
    });

    test('a Future-returning body is awaited (next caller waits)',
        () async {
      final lock = AsyncLock();
      var bodyFinished = false;
      String? slowResult;

      final slow = lock.synchronized(() async {
        await Future.delayed(const Duration(milliseconds: 30));
        bodyFinished = true;
        return 'slow done';
      });
      final fast = lock.synchronized(() async {
        // When this body finally runs, slow's body must already be done.
        return bodyFinished;
      });

      slowResult = await slow;
      final fastSawSlowFinished = await fast;
      expect(slowResult, 'slow done');
      expect(fastSawSlowFinished, isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: AsyncLock under error pressure
  // ────────────────────────────────────────────────────────────────
  group('AsyncLock under error pressure', () {
    test('half the callers throw, half succeed — all ten complete',
        () async {
      final lock = AsyncLock();
      final results = <Object>[];

      final futures = <Future<void>>[];
      for (int i = 0; i < 10; i++) {
        final shouldThrow = i.isOdd;
        futures.add(
          lock.synchronized<int>(() async {
            if (shouldThrow) throw StateError('caller $i failed');
            return i;
          }).then<void>(
            (value) {
              results.add(value);
            },
            onError: (Object e) {
              results.add('err');
            },
          ),
        );
      }
      await Future.wait(futures);

      expect(results.length, 10);
      // Even indices succeed, odd throw.
      expect(
        results.where((r) => r != 'err').toList(),
        [0, 2, 4, 6, 8],
      );
      expect(results.where((r) => r == 'err').length, 5);
    });

    test('lock state remains usable after many consecutive exceptions',
        () async {
      final lock = AsyncLock();
      for (int i = 0; i < 20; i++) {
        try {
          await lock.synchronized(() async => throw Exception('boom $i'));
        } catch (_) {/* swallow */}
      }
      final result = await lock.synchronized(() async => 'still works');
      expect(result, 'still works');
    });
  });
}
