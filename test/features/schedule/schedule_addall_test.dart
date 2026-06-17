// test/features/schedule/schedule_addall_test.dart
//
// Unit tests for the atomic addAll batch path on SchedulesNotifier
// (Item #51 compound-schedule foundation).
//
// Test strategy: hand-rolled fakes for the Firebase Auth User and
// UserService (no mocktail in pubspec, matching the project convention
// established in calendar_entry_lease_manager_test.dart). Riverpod
// ProviderContainer overrides supply both fakes plus the
// calendarScheduleProvider stream so the notifier never reaches
// Firebase Auth or Firestore.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_dialog.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/services/user_service.dart';

// ─── Fakes ──────────────────────────────────────────────────────────────────

class _FakeUser implements User {
  @override
  String get uid => 'test-uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records every UserService method call this test cares about.
/// Configurable to throw on addSchedules so the all-or-nothing revert
/// path can be exercised.
class _FakeUserService implements UserService {
  final List<List<ScheduleItem>> addSchedulesCalls = [];
  Object? addSchedulesThrow;

  @override
  Future<void> addSchedules(String userId, List<ScheduleItem> items) async {
    addSchedulesCalls.add(List.of(items));
    if (addSchedulesThrow != null) throw addSchedulesThrow!;
  }

  // Stream the in-memory schedules so SchedulesNotifier's _init listener
  // doesn't block on an empty stream forever.
  @override
  Stream<List<ScheduleItem>> streamSchedules(String userId) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ─── Helpers ────────────────────────────────────────────────────────────────

ScheduleItem _mk({
  required String id,
  String timeLabel = '7:00 PM',
  String? offTimeLabel = '11:00 PM',
  String actionLabel = 'Pattern: Warm White',
  List<String> repeatDays = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
  bool enabled = true,
  String? sourcePromptId,
}) =>
    ScheduleItem(
      id: id,
      timeLabel: timeLabel,
      offTimeLabel: offTimeLabel,
      repeatDays: repeatDays,
      actionLabel: actionLabel,
      enabled: enabled,
      sourcePromptId: sourcePromptId,
    );

/// Build a ProviderContainer wired with the fakes. The caller can read
/// schedulesProvider to drive the notifier.
({ProviderContainer container, _FakeUserService userService}) _harness({
  List<ScheduleItem> existingSchedules = const [],
  Map<String, CalendarEntry> existingCalendarEntries = const {},
}) {
  final userService = _FakeUserService();
  final container = ProviderContainer(overrides: [
    userServiceProvider.overrideWithValue(userService),
    authStateProvider.overrideWith((_) => Stream<User?>.value(_FakeUser())),
    // Provide the calendar-entries map directly so checkConflictsForAddAll
    // can read it without going through Firestore.
    calendarScheduleProvider.overrideWith(
      (ref) => _StubCalendarScheduleNotifier(ref, existingCalendarEntries),
    ),
    // userSchedulesStreamProvider feeds the notifier's _init listener.
    // Seed it with the requested existing items so state starts non-empty.
    userSchedulesStreamProvider
        .overrideWith((_) => Stream.value(existingSchedules)),
  ]);
  addTearDown(container.dispose);
  return (container: container, userService: userService);
}

/// Drops a notifier into the test container with a known existing-state
/// seed. Awaits both stream providers' first emissions before returning
/// so addAll's synchronous _userId read finds the fake user, and the
/// notifier's _init listener finds the seeded schedule list.
Future<SchedulesNotifier> _readNotifier(ProviderContainer c) async {
  // Eagerly subscribe and await the first value so the streams resolve
  // from loading → data before any test method calls into the notifier.
  await c.read(authStateProvider.future);
  await c.read(userSchedulesStreamProvider.future);
  final notifier = c.read(schedulesProvider.notifier);
  // One microtask for the _init listener to absorb the stream value
  // into state.
  await Future.delayed(Duration.zero);
  return notifier;
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  // _showSaveError reaches WidgetsBinding for the SnackBar surface, so
  // the binding must be initialized even for non-widget unit tests that
  // exercise the failure-revert path.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SchedulesNotifier.addAll — atomic batch', () {
    test('addAll([]) is a no-op — no Firestore write', () async {
      final h = _harness();
      final notifier = await _readNotifier(h.container);

      await notifier.addAll(const []);

      expect(h.userService.addSchedulesCalls, isEmpty);
      expect(h.container.read(schedulesProvider), isEmpty);
    });

    test('addAll of 2 → state grows by 2, addSchedules called once', () async {
      final h = _harness();
      final notifier = await _readNotifier(h.container);

      final batch = [
        _mk(id: 'a', timeLabel: '5:00 PM', sourcePromptId: 'p1'),
        _mk(id: 'b', timeLabel: '9:00 PM', sourcePromptId: 'p1'),
      ];

      await notifier.addAll(batch);

      expect(h.userService.addSchedulesCalls.length, 1,
          reason: 'exactly one batch write, not N per-item writes');
      expect(h.userService.addSchedulesCalls.first.map((i) => i.id).toList(),
          ['a', 'b']);
      expect(h.container.read(schedulesProvider).length, 2);
    });

    test('addAll growth is additive on top of existing state', () async {
      final seed = [_mk(id: 'existing', timeLabel: '6:00 AM')];
      final h = _harness(existingSchedules: seed);
      final notifier = await _readNotifier(h.container);
      // Confirm seed landed.
      expect(h.container.read(schedulesProvider).length, 1);

      await notifier.addAll([
        _mk(id: 'new1', timeLabel: '5:00 PM'),
        _mk(id: 'new2', timeLabel: '9:00 PM'),
      ]);

      final ids = h.container.read(schedulesProvider).map((i) => i.id).toList();
      expect(ids, ['existing', 'new1', 'new2']);
    });

    test('addSchedules throwing → state fully reverts, no partial', () async {
      final seed = [_mk(id: 'pre-existing', timeLabel: '6:00 AM')];
      final h = _harness(existingSchedules: seed);
      h.userService.addSchedulesThrow = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'simulated outage',
      );
      final notifier = await _readNotifier(h.container);

      final batch = [
        _mk(id: 'batch1', timeLabel: '5:00 PM'),
        _mk(id: 'batch2', timeLabel: '9:00 PM'),
      ];

      await notifier.addAll(batch);

      // Either both items persist or neither. Neither here → revert to
      // the pre-existing-only state.
      final ids = h.container.read(schedulesProvider).map((i) => i.id).toList();
      expect(ids, ['pre-existing'],
          reason: 'all-or-nothing — partial state must not survive');
    });

    test('ConflictResolution.cancel → no state change, no write', () async {
      final h = _harness();
      final notifier = await _readNotifier(h.container);

      await notifier.addAll(
        [_mk(id: 'a', timeLabel: '5:00 PM')],
        resolution: ConflictResolution.cancel,
      );

      expect(h.userService.addSchedulesCalls, isEmpty);
      expect(h.container.read(schedulesProvider), isEmpty);
    });

    test('addAll reports the real outcome — true on commit, false on failure',
        () async {
      // The confirm flow branches on this: a swallowed failure (old behavior,
      // returning normally) let the UI claim "scheduled" with no row written.
      final h = _harness();
      final notifier = await _readNotifier(h.container);

      final okGood =
          await notifier.addAll([_mk(id: 'g', timeLabel: '5:00 PM')]);
      expect(okGood, isTrue, reason: 'a committed write reports success');

      h.userService.addSchedulesThrow = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
        message: 'simulated outage',
      );
      final okBad =
          await notifier.addAll([_mk(id: 'b', timeLabel: '9:00 PM')]);
      expect(okBad, isFalse,
          reason: 'a reverted write must report failure, never silent success');

      // The failed item left no row; only the first committed item survives.
      expect(h.container.read(schedulesProvider).map((i) => i.id).toList(),
          ['g']);
    });

    test('ConflictResolution.cancel returns false (nothing committed)',
        () async {
      final h = _harness();
      final notifier = await _readNotifier(h.container);
      final ok = await notifier.addAll(
        [_mk(id: 'a', timeLabel: '5:00 PM')],
        resolution: ConflictResolution.cancel,
      );
      expect(ok, isFalse);
    });
  });

  group('SchedulesNotifier.checkConflictsForAddAll', () {
    test('flags intra-batch collision: two items same day + overlap',
        () async {
      final h = _harness();
      final notifier = await _readNotifier(h.container);

      // Two items in the same compound batch, sharing Mon and overlapping
      // 7-10pm vs 9-11pm. Intra-batch detection must catch this.
      final batch = [
        _mk(
          id: 'b1',
          timeLabel: '7:00 PM',
          offTimeLabel: '10:00 PM',
          repeatDays: const ['Mon'],
        ),
        _mk(
          id: 'b2',
          timeLabel: '9:00 PM',
          offTimeLabel: '11:00 PM',
          repeatDays: const ['Mon'],
        ),
      ];

      final info = notifier.checkConflictsForAddAll(batch);

      final flaggedIds =
          info.conflictingItems.map((i) => i.id).toSet();
      expect(flaggedIds, containsAll(['b1', 'b2']),
          reason:
              'both sides of an intra-batch overlap must surface so the user sees what their prompt produced');
    });

    test('no false positives: two items different days', () async {
      final h = _harness();
      final notifier = await _readNotifier(h.container);

      final batch = [
        _mk(id: 'b1', timeLabel: '7:00 PM', repeatDays: const ['Mon']),
        _mk(id: 'b2', timeLabel: '7:00 PM', repeatDays: const ['Tue']),
      ];

      final info = notifier.checkConflictsForAddAll(batch);

      expect(info.conflictingItems, isEmpty);
    });

    test('flags batch-vs-existing collision', () async {
      final seed = [
        _mk(
          id: 'existing-evening',
          timeLabel: '8:00 PM',
          offTimeLabel: '10:00 PM',
          repeatDays: const ['Mon'],
        ),
      ];
      final h = _harness(existingSchedules: seed);
      final notifier = await _readNotifier(h.container);

      final batch = [
        _mk(
          id: 'newcomer',
          timeLabel: '9:00 PM',
          offTimeLabel: '11:00 PM',
          repeatDays: const ['Mon'],
        ),
      ];

      final info = notifier.checkConflictsForAddAll(batch);

      expect(info.conflictingItems.map((i) => i.id), contains('existing-evening'));
    });

    test('addAll([]) → empty conflict info', () async {
      final h = _harness();
      final notifier = await _readNotifier(h.container);

      final info = notifier.checkConflictsForAddAll(const []);

      expect(info.hasConflicts, isFalse);
      expect(info.conflictingItems, isEmpty);
    });
  });

  group('regression — mergeWithDedup unchanged', () {
    test('mergeWithDedup still dedups identical content fingerprint',
        () async {
      final seed = [
        _mk(
          id: 'orig',
          timeLabel: '7:00 PM',
          repeatDays: const ['Mon'],
          actionLabel: 'Pattern: Warm White',
        ),
      ];
      final h = _harness(existingSchedules: seed);
      final notifier = await _readNotifier(h.container);

      // Same content fingerprint as the seed (just a fresh UUID) — the
      // autopilot-shaped dedup must drop it.
      await notifier.mergeWithDedup([
        _mk(
          id: 'fresh-uuid',
          timeLabel: '7:00 PM',
          repeatDays: const ['Mon'],
          actionLabel: 'Pattern: Warm White',
        ),
      ]);

      // Still 1 item; the duplicate was filtered out before write.
      expect(h.container.read(schedulesProvider).length, 1);
      expect(h.container.read(schedulesProvider).first.id, 'orig');
    });
  });
}

// ─── Stub CalendarScheduleNotifier ─────────────────────────────────────────
//
// The real one's constructor calls _loadFromFirestore which needs a
// Firebase App. Passing a null userId makes it early-return; we then
// overwrite state with the test seed. Subclassing (vs implementing)
// gives us the StateNotifier machinery for free and keeps the provider
// override type-compatible.

class _StubCalendarScheduleNotifier extends CalendarScheduleNotifier {
  _StubCalendarScheduleNotifier(Ref ref, Map<String, CalendarEntry> seed)
      : super(ref, null) {
    state = seed;
  }

  @override
  Future<bool> removeEntry(String dateKey) async {
    state = {...state}..remove(dateKey);
    return true;
  }
}
