// Build 128, Step 4 — the AI delete goes through the SAME path as the detail
// sheet's "Delete This Entry": CalendarScheduleNotifier.removeEntryById, which
// does the lease work for the night and then writes through
// UserService.saveCalendarEntries.
//
// Real CalendarScheduleNotifier and real CalendarEntryLeaseManager over a
// fake UserService, a fake signed-in user and NO controller (the repository
// provider is null, as off the home Wi-Fi). RiverpodLuminaEntryDeleteServices
// is driven through a pumped Consumer's WidgetRef. Synthetic ids only.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ai/entry_delete_services.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_set.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUser implements User {
  @override
  String get uid => 'test-uid';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserService implements UserService {
  final List<List<String>> saves = [];

  @override
  Future<CalendarEntrySet> loadCalendarEntries(String userId) async =>
      CalendarEntrySet.empty;

  @override
  Future<bool> saveCalendarEntries(String userId, CalendarEntrySet set) async {
    saves.add(set.allEntries.map((e) => e.entryId).toList()..sort());
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Tuesday noon, 2026-05-19; the entries below are far in the future so no
/// lease is armed for them (the 48 h window), exactly the state of the seven
/// Lumina nights on the day they were written.
final _fixedNow = DateTime(2026, 5, 19, 12);

CalendarEntry _lumina(int i, String dateKey) => CalendarEntry(
      entryId: 'lumina_1762819200000_$i',
      dateKey: dateKey,
      patternName: 'Lumina Night ${i + 1}',
      color: const Color(0xFFE31837),
      onTime: '18:00',
      offTime: '23:00',
      brightness: 85,
      type: CalendarEntryType.user,
      autopilot: true,
      sourceTag: CalendarEntrySourceTag.luminaAi,
    );

const CalendarEntry _handMade = CalendarEntry(
  entryId: 'user_1',
  dateKey: '2026-11-20',
  patternName: 'Birthday Blue',
  onTime: '19:00',
  offTime: '23:30',
  type: CalendarEntryType.user,
  autopilot: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'deleteEntries removes each entry through removeEntryById and '
      'each removal is written through saveCalendarEntries', (tester) async {
    final users = _FakeUserService();
    final container = ProviderContainer(overrides: [
      calendarLeaseSchedulesHydratedProvider.overrideWithValue(true),
      userServiceProvider.overrideWithValue(users),
      authStateProvider.overrideWith((_) => Stream<User?>.value(_FakeUser())),
      calendarLeaseScheduleSlotDemandProvider.overrideWith((_) => 0),
      calendarLeaseEntriesProvider.overrideWith((_) => const []),
      wledRepositoryProvider.overrideWithValue(null),
      calendarLeaseLiveWritesEnabledSyncProvider.overrideWithValue(true),
    ]);
    addTearDown(container.dispose);
    final entries = [
      _lumina(0, '2026-11-19'),
      _lumina(1, '2026-11-20'),
      _lumina(2, '2026-11-21'),
    ];
    late CalendarEntryLeaseManager leases;
    late CalendarScheduleNotifier calendar;
    // The notifier and the lease manager await real futures (Firestore fakes,
    // Duration.zero delays); under the widget tester's fake clock they would
    // never complete, so the Riverpod work runs under runAsync.
    await tester.runAsync(() async {
      await container.read(authStateProvider.future);
      leases = container.read(calendarEntryLeaseManagerProvider);
      leases.nowProvider = () => _fixedNow;
      leases.readTimerRowsFn = (_) async => [];
      await leases.initialize();
      calendar = container.read(calendarScheduleProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      expect(await calendar.applyEntries([...entries, _handMade]), isTrue);
    });
    users.saves.clear();
    expect(calendar.entriesFor('2026-11-20').map((e) => e.entryId),
        containsAll(['lumina_1762819200000_1', 'user_1']));

    late WidgetRef capturedRef;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (context, ref, _) {
        capturedRef = ref;
        return const SizedBox();
      }),
    ));

    final svc = RiverpodLuminaEntryDeleteServices(capturedRef);
    expect(svc.calendarEntries().map((e) => e.entryId),
        containsAll(['lumina_1762819200000_0', 'user_1']));

    final removed = await tester.runAsync(() => svc.deleteEntries(entries));

    expect(removed, 3);
    expect(users.saves, hasLength(3),
        reason: 'one saveCalendarEntries per removeEntryById, as the manual '
            'button does');
    expect(users.saves.last, ['user_1'],
        reason: 'the hand-made entry on the shared night is untouched');
    expect(calendar.entriesFor('2026-11-19'), isEmpty);
    expect(calendar.entriesFor('2026-11-20').map((e) => e.entryId), ['user_1']);
    expect(calendar.entriesFor('2026-11-21'), isEmpty);
    expect(leases.leaseFor('2026-11-20'), isNull,
        reason: 'no lease was armed for a night six months out');
  });
}
