// D2 (+110 E2 follow-up) — a Lumina night is the CUSTOMER'S entry.
//
// The Schedule tab labels it "You" (timeline chip; the day sheet's Source row
// reads "AI-Generated" for a user entry with `autopilot: true`,
// my_schedule_page.dart), and Edit opens the ordinary user-entry editor: a
// direct save, never the Game Day "This game only / All future games" scope
// sheet, which the editor shows only for `CalendarEntryType.autopilot`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/lumina_schedule_persistence.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_editor.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/day_timeline.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_dialog.dart';
import 'package:nexgen_command/features/schedule/widgets/timeline_row.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// Records what the editor writes; never touches Firestore or a lease.
class _StubCalendar extends CalendarScheduleNotifier {
  _StubCalendar(Ref ref) : super(ref, null);
  final List<List<CalendarEntry>> applied = [];

  @override
  Future<CalendarApplyOutcome> applyEntriesDetailed(
    List<CalendarEntry> entries, {
    ConflictResolution? resolution,
    RecurringIntent? recurringIntent,
    bool overwriteAcknowledged = false,
    NoFreeSlotsPolicy noFreeSlots = NoFreeSlotsPolicy.prompt,
  }) async {
    applied.add(entries);
    return const CalendarApplyOutcome(ok: true);
  }
}

final _lumina = calendarEntryForNight(
  PlannedNight(
    index: 1,
    date: DateTime(2026, 12, 21),
    patternName: 'Christmas night 2',
    effectName: 'Breathe',
    wled: const {'on': true},
    onTime: '20:00',
    offTime: '06:00',
    color: const Color(0xFFCC0000),
    brightnessPercent: 100,
  ),
  batchId: 'b',
)!;

final _gameDay = CalendarEntry(
  entryId: CalendarEntryId.gameDay('team-a'),
  dateKey: '2026-12-21',
  patternName: 'Team A Colors',
  onTime: '19:00',
  offTime: '22:30',
  type: CalendarEntryType.autopilot,
  autopilot: true,
  sourceTag: CalendarEntrySourceTag.gameDay,
  note: 'Team A vs Team B — Game Day autopilot',
);

Future<_StubCalendar> _openEditor(WidgetTester tester, CalendarEntry entry) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final appKey = GlobalKey();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      calendarScheduleProvider.overrideWith((ref) => _StubCalendar(ref)),
      // The editor's channel-scope picker reads these; no device in a test.
      deviceChannelsProvider.overrideWithValue(const []),
      selectedControllerIdProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      key: appKey,
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Center(
            child: ElevatedButton(
              onPressed: () => showCalendarEntryEditor(context, ref, entry: entry),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  // The provider is created lazily; read it so the stub exists before Save.
  final stub = ProviderScope.containerOf(appKey.currentContext!)
      .read(calendarScheduleProvider.notifier) as _StubCalendar;
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return stub;
}

void main() {
  test('the timeline chip says "You"', () {
    final row = TimelineEntry(
      id: 'cal:${_lumina.entryId}',
      source: TimelineSource.dated,
      dated: _lumina,
      startsAt: DateTime(2026, 12, 21, 20),
      endsAt: DateTime(2026, 12, 22, 6),
      endMode: CalendarEntryEndMode.fixedTime,
      label: _lumina.patternName,
    );
    expect(timelineSourceLabel(row), '👤 You');
    expect(_lumina.type, CalendarEntryType.user);
    expect(_lumina.autopilot, isTrue, reason: 'the day sheet says AI-Generated');
  });

  testWidgets('Edit opens the ordinary editor: Save writes the entry directly, '
      'with no Game Day scope sheet', (tester) async {
    final stub = await _openEditor(tester, _lumina);
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('This game only'), findsNothing);
    expect(find.textContaining('All future'), findsNothing);
    final written = stub.applied.single.single;
    expect(written.entryId, _lumina.entryId, reason: 'identity survives an edit');
    expect(written.type, CalendarEntryType.user);
    expect(written.sourceTag, kLuminaAiSourceTag);
  });

  testWidgets('contrast: a Game Day entry still gets the scope sheet',
      (tester) async {
    final stub = await _openEditor(tester, _gameDay);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('This game only'), findsOneWidget);
    expect(stub.applied, isEmpty, reason: 'nothing is written until a scope is chosen');
  });
}
