// D3 (+110 E2 follow-up) — "Delete" removes ONE entry, and the lease follows
// the survivor.
//
// A Game Day entry and a customer's own entry can share a night (V3 A1).
// Deleting either must leave the other — and the other must hold the night's
// single lease: the Game Day entry reclaims the night when the override on
// top of it goes; a delete of a bystander leaves the holder's lease alone;
// the last delete releases the slot. The heir is chosen under Policy B
// (leaseHolderAmong): Game Day above everything else on the date.
//
// Real CalendarScheduleNotifier + real CalendarEntryLeaseManager over the
// lease manager's own fake WLED repository, a fake UserService and a fake
// signed-in user. Synthetic ids only.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_set.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Fakes ───────────────────────────────────────────────────────────────────

class _FakeUser implements User {
  @override
  String get uid => 'test-uid';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserService implements UserService {
  final List<List<CalendarEntry>> saves = [];

  @override
  Future<CalendarEntrySet> loadCalendarEntries(String userId) async =>
      CalendarEntrySet.empty;

  @override
  Future<bool> saveCalendarEntries(String userId, CalendarEntrySet set) async {
    saves.add(set.allEntries);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SavePresetCall {
  const _SavePresetCall(this.presetId, this.state);
  final int presetId;
  final Map<String, dynamic> state;
}

class _FakeWledRepository extends WledRepository {
  final List<_SavePresetCall> savePresetCalls = [];
  final List<Map<String, dynamic>> applyConfigCalls = [];

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    savePresetCalls.add(_SavePresetCall(presetId, Map<String, dynamic>.from(state)));
    return true;
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    applyConfigCalls.add(Map<String, dynamic>.from(cfg));
    return true;
  }

  @override
  Future<Map<String, dynamic>?> getState() async => null;

  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      true;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async => true;

  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => true;

  @override
  Future<bool> configureSyncReceiver() async => true;

  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      true;
}

// ── Fixtures ────────────────────────────────────────────────────────────────

/// Tuesday noon; both entries below start the same evening, inside the 48 h
/// lease window and not yet expired.
final _fixedNow = DateTime(2026, 5, 19, 12, 0);
const _date = '2026-05-19';

CalendarEntry _gameDay() => CalendarEntry(
      entryId: CalendarEntryId.gameDay('team-a'),
      dateKey: _date,
      patternName: 'Team A Colors',
      color: const Color(0xFFCC0000),
      onTime: '19:00',
      offTime: '22:30',
      brightness: 90,
      type: CalendarEntryType.autopilot,
      autopilot: true,
      sourceTag: CalendarEntrySourceTag.gameDay,
      note: 'Team A vs Team B — Game Day autopilot',
    );

CalendarEntry _mine() => const CalendarEntry(
      entryId: 'user_1',
      dateKey: _date,
      patternName: 'Birthday Blue',
      color: Color(0xFF0033A0),
      onTime: '18:00',
      offTime: '23:00',
      brightness: 100,
      type: CalendarEntryType.user,
      autopilot: false,
    );

class _Harness {
  _Harness(this.repo, this.users, this.leases, this.calendar);
  final _FakeWledRepository repo;
  final _FakeUserService users;
  final CalendarEntryLeaseManager leases;
  final CalendarScheduleNotifier calendar;

  List<String> idsOn(String dateKey) =>
      calendar.state.forDate(dateKey).map((e) => e.entryId).toList();
}

Future<_Harness> _harness() async {
  final repo = _FakeWledRepository();
  final users = _FakeUserService();
  final c = ProviderContainer(overrides: [
    userServiceProvider.overrideWithValue(users),
    authStateProvider.overrideWith((_) => Stream<User?>.value(_FakeUser())),
    calendarLeaseScheduleSlotDemandProvider.overrideWith((_) => 0),
    calendarLeaseEntriesProvider.overrideWith((_) => const []),
    wledRepositoryProvider.overrideWithValue(repo),
    calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
  ]);
  addTearDown(c.dispose);
  await c.read(authStateProvider.future);
  final leases = c.read(calendarEntryLeaseManagerProvider);
  leases.nowProvider = () => _fixedNow;
  await leases.initialize();
  final calendar = c.read(calendarScheduleProvider.notifier);
  await Future<void>.delayed(Duration.zero);
  return _Harness(repo, users, leases, calendar);
}

/// Two rows on one night with the CUSTOMER'S entry holding the lease — the
/// #117 "last write wins" state. +112 Policy B refuses that write at
/// applyEntriesDetailed (see the group at the bottom), so the state can no
/// longer be CREATED here; builds up to 111 did create it, and D3's delete
/// semantics must still hold for those nights. Seed it the way legacy data
/// arrives: both rows present, then the lease layer handed the night to the
/// customer's row.
Future<_Harness> _sharedNight() async {
  final h = await _harness();
  expect(await h.calendar.applyEntries([_mine()]), isTrue);
  expect(await h.calendar.applyEntries([_gameDay()]), isTrue);
  expect(h.idsOn(_date), ['user_1', 'gd_team-a']);
  final handed = await h.leases.handleEntryCreated(_mine());
  expect(handed.outcome, LeaseOutcome.updated);
  expect(h.leases.leaseFor(_date)!.entryId, 'user_1',
      reason: "the legacy #117 state: the customer's row holds the night");
  return h;
}

/// The other write order: the customer's entry first, then the Game Day
/// entry, so Game Day holds the lease — the state Policy B wants.
Future<_Harness> _gameDayHeld() async {
  final h = await _harness();
  expect(await h.calendar.applyEntries([_mine()]), isTrue);
  expect(await h.calendar.applyEntries([_gameDay()]), isTrue);
  expect(h.idsOn(_date), ['user_1', 'gd_team-a']);
  expect(h.leases.leaseFor(_date)!.entryId, 'gd_team-a');
  return h;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('D3 — delete one entry, the lease follows the survivor', () {
    test('deleting the customer\'s entry hands the night back to Game Day',
        () async {
      final h = await _sharedNight();
      final savesBefore = h.repo.savePresetCalls.length;

      expect(await h.calendar.removeEntryById(_date, 'user_1'), isTrue);

      expect(h.idsOn(_date), ['gd_team-a'], reason: 'one row, not the day');
      final lease = h.leases.leaseFor(_date)!;
      expect(lease.entryId, 'gd_team-a');
      expect(lease.patternName, 'Team A Colors');
      expect(lease.wledHour, 19, reason: "the Game Day entry's on-time");
      // Re-derived: the preset now carries the Game Day payload, same slot.
      expect(h.repo.savePresetCalls.length, savesBefore + 1);
      expect(h.repo.savePresetCalls.last.presetId, lease.presetId);
      // Firestore sees the survivor only.
      expect(h.users.saves.last.map((e) => e.entryId), ['gd_team-a']);
    });

    test('deleting the Game Day entry leaves the customer\'s lease alone',
        () async {
      final h = await _sharedNight();
      final savesBefore = h.repo.savePresetCalls.length;
      final cfgBefore = h.repo.applyConfigCalls.length;

      expect(await h.calendar.removeEntryById(_date, 'gd_team-a'), isTrue);

      expect(h.idsOn(_date), ['user_1']);
      final lease = h.leases.leaseFor(_date)!;
      expect(lease.entryId, 'user_1');
      expect(lease.patternName, 'Birthday Blue');
      // The holder is still there: no preset re-save, no cfg write.
      expect(h.repo.savePresetCalls.length, savesBefore);
      expect(h.repo.applyConfigCalls.length, cfgBefore);
      expect(h.users.saves.last.map((e) => e.entryId), ['user_1']);
    });

    test('deleting the last entry on the night releases the lease', () async {
      final h = await _sharedNight();
      await h.calendar.removeEntryById(_date, 'user_1');
      final cfgBefore = h.repo.applyConfigCalls.length;

      expect(await h.calendar.removeEntryById(_date, 'gd_team-a'), isTrue);

      expect(h.idsOn(_date), isEmpty);
      expect(h.leases.leaseFor(_date), isNull);
      expect(h.repo.applyConfigCalls.length, cfgBefore + 1,
          reason: 'the slot is zeroed on the controller');
    });

    test('an id that is not on the night changes nothing', () async {
      final h = await _sharedNight();
      final savesBefore = h.users.saves.length;
      expect(await h.calendar.removeEntryById(_date, 'nope'), isTrue);
      expect(h.idsOn(_date), ['user_1', 'gd_team-a']);
      expect(h.users.saves.length, savesBefore);
      expect(h.leases.leaseFor(_date)!.entryId, 'user_1');
    });
  });

  group('Policy B — Game Day holds the night', () {
    test('deleting the Game Day row re-derives the lease to the customer '
        'entry', () async {
      final h = await _gameDayHeld();
      final savesBefore = h.repo.savePresetCalls.length;

      expect(await h.calendar.removeEntryById(_date, 'gd_team-a'), isTrue);

      expect(h.idsOn(_date), ['user_1']);
      final lease = h.leases.leaseFor(_date)!;
      expect(lease.entryId, 'user_1');
      expect(lease.patternName, 'Birthday Blue');
      expect(lease.wledHour, 18);
      expect(h.repo.savePresetCalls.length, savesBefore + 1);
      expect(h.repo.savePresetCalls.last.presetId, lease.presetId);
    });

    test('deleting the customer row leaves the Game Day lease untouched — '
        'no preset save', () async {
      final h = await _gameDayHeld();
      final savesBefore = h.repo.savePresetCalls.length;
      final cfgBefore = h.repo.applyConfigCalls.length;

      expect(await h.calendar.removeEntryById(_date, 'user_1'), isTrue);

      expect(h.idsOn(_date), ['gd_team-a']);
      final lease = h.leases.leaseFor(_date)!;
      expect(lease.entryId, 'gd_team-a');
      expect(lease.patternName, 'Team A Colors');
      expect(h.repo.savePresetCalls.length, savesBefore);
      expect(h.repo.applyConfigCalls.length, cfgBefore);
      expect(h.users.saves.last.map((e) => e.entryId), ['gd_team-a']);
    });
  });

  group('+112 Policy B — the write is refused, not displaced', () {
    test("a customer's entry onto a Game Day night is refused at the write, "
        'names the team, and leaves the Game Day lease untouched', () async {
      final h = await _harness();
      expect(await h.calendar.applyEntries([_gameDay()]), isTrue);
      final savesBefore = h.repo.savePresetCalls.length;

      final outcome = await h.calendar.applyEntriesDetailed([_mine()]);

      expect(outcome.ok, isFalse);
      expect(outcome.refusedForGameDay, isTrue);
      expect(outcome.refusedDateKey, _date);
      expect(outcome.message, 'The Team A game already has that night.');
      expect(h.idsOn(_date), ['gd_team-a'], reason: 'nothing was written');
      expect(h.leases.leaseFor(_date)!.entryId, 'gd_team-a');
      expect(h.repo.savePresetCalls.length, savesBefore,
          reason: 'no controller traffic for a refused write');
    });

    test('an edited Game Day row (type user, tag kept) still writes — it IS '
        'the game', () async {
      final h = await _harness();
      expect(await h.calendar.applyEntries([_gameDay()]), isTrue);
      final edited = _gameDay().copyWith(
          type: CalendarEntryType.user, autopilot: false, brightness: 40);
      expect((await h.calendar.applyEntriesDetailed([edited])).ok, isTrue);
      expect(h.idsOn(_date), ['gd_team-a']);
    });
  });

  group('leaseHolderAmong', () {
    test('Policy B: Game Day outranks every other entry on the date, the '
        'customer\'s own included, in either order', () {
      expect(leaseHolderAmong([_gameDay(), _mine()])!.entryId, 'gd_team-a');
      expect(leaseHolderAmong([_mine(), _gameDay()])!.entryId, 'gd_team-a');
      expect(leaseHolderAmong([_gameDay()])!.entryId, 'gd_team-a');
      final sync = _gameDay().copyWith(
          entryId: 'ns_1', sourceTag: CalendarEntrySourceTag.neighborhoodSync);
      expect(leaseHolderAmong([sync, _gameDay()])!.entryId, 'gd_team-a');
      expect(leaseHolderAmong([_gameDay(), sync])!.entryId, 'gd_team-a');
      // An edited Game Day entry ("This game only": type user, same source
      // tag) is still the game's night.
      final edited =
          _gameDay().copyWith(type: CalendarEntryType.user, autopilot: false);
      expect(leaseHolderAmong([_mine(), edited])!.entryId, 'gd_team-a');
      expect(leaseHolderAmong([edited, _mine()])!.entryId, 'gd_team-a');
    });

    test('below Game Day the composer tier order applies; a tie goes to the '
        'last written', () {
      final sync = _gameDay().copyWith(
          entryId: 'ns_1', sourceTag: CalendarEntrySourceTag.neighborhoodSync);
      expect(leaseHolderAmong([sync, _mine()])!.entryId, 'user_1');
      expect(leaseHolderAmong([_mine(), sync])!.entryId, 'user_1');
      final second = _mine().copyWith(entryId: 'user_2');
      expect(leaseHolderAmong([_mine(), second])!.entryId, 'user_2');
      final secondGame =
          _gameDay().copyWith(entryId: CalendarEntryId.gameDay('team-b'));
      expect(leaseHolderAmong([_gameDay(), secondGame])!.entryId, 'gd_team-b');
    });

    test('holidays never hold a lease', () {
      final holiday = _mine().copyWith(
          entryId: CalendarEntryId.holiday, type: CalendarEntryType.holiday);
      expect(leaseHolderAmong([holiday]), isNull);
      expect(leaseHolderAmong([holiday, _gameDay()])!.entryId, 'gd_team-a');
    });
  });

  group('the lease record carries its holder', () {
    test('round-trips through prefs JSON; a legacy record reads null', () {
      final lease = CalendarEntryLease(
        dateKey: _date,
        slotIndex: 0,
        presetId: 26,
        leasedAt: _fixedNow,
        expiresAt: _fixedNow.add(const Duration(hours: 10)),
        wledPayload: const {'on': true},
        patternName: 'x',
        wledHour: 18,
        wledMin: 0,
        dowMask: 2,
        entryId: 'user_1',
      );
      expect(CalendarEntryLease.fromJson(lease.toJson())!.entryId, 'user_1');
      final legacy = Map<String, dynamic>.from(lease.toJson())..remove('entryId');
      expect(CalendarEntryLease.fromJson(legacy)!.entryId, isNull);
    });
  });
}
