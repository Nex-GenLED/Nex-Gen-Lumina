// Lumina's delete confirmation must finish, and report, after the customer
// closes the surface it was tapped on.
//
// THE SHAPE. The card's Delete runs `LuminaConversationDriver
// .confirmEntryDelete`: the removals go through a notifier captured before
// the first await (entry_delete_services.dart), but the outcome line was
// posted through `services.openThread()` AFTER the awaited removals, and that
// reads `luminaSheetProvider.notifier` through the surface's own WidgetRef.
// Each removal releases the night's lease (a timer-table write to the
// controller on the home Wi-Fi, 15 s timeout) and then writes Firestore, so
// the customer can close the sheet, or back out of the full screen, while it
// runs. The surface is then disposed and the read threw
// `StateError: Cannot use "ref" after the widget was disposed.` — uncaught,
// so the entries were removed but the conversation never said so.
//
// These tests drive the REAL sheet (opened through showLuminaSheet, as the
// dock does) and the REAL full screen, with a calendar notifier whose removal
// is held open until the surface is gone. Nothing reaches Firestore, a lease
// or a controller. Written first and failing at 0a364ce0 with that StateError.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/features/ai/entry_delete_confirm_card.dart';
import 'package:nexgen_command/features/ai/entry_delete_resolver.dart';
import 'package:nexgen_command/features/ai/lumina_ai_screen.dart';
import 'package:nexgen_command/features/ai/lumina_bottom_sheet.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_set.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kEntryId = 'lumina_1794403737068_6';

String _tomorrow() =>
    calendarDateKey(DateTime.now().add(const Duration(days: 1)));

CalendarEntry _chiefsNight() => CalendarEntry(
      entryId: _kEntryId,
      dateKey: _tomorrow(),
      patternName: 'Chiefs Fade',
      color: const Color(0xFFE30000),
      onTime: '18:00',
      offTime: '23:00',
      brightness: 100,
      type: CalendarEntryType.user,
      sourceTag: CalendarEntrySourceTag.luminaAi,
    );

/// The conversation as Lumina leaves it: the customer's ask, then the card.
/// isOpen stays false: showLuminaSheet refuses to open a sheet it believes
/// is already open.
class _SeededSheet extends LuminaSheetController {
  _SeededSheet(this._proposal);
  final EntryDeleteProposal _proposal;

  @override
  LuminaSheetState build() => LuminaSheetState(
        mode: LuminaSheetMode.expanded,
        messages: [
          LuminaMessage.user('Delete my Chiefs night tomorrow'),
          LuminaMessage.entryDeleteProposal(_proposal.leadText, _proposal),
        ],
      );
}

class _StillWled extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

/// The removal waits on [gate], the way a lease release plus a Firestore
/// write keeps it open. Records what was removed.
class _GatedCalendar extends CalendarScheduleNotifier {
  _GatedCalendar(Ref ref, List<CalendarEntry> seed) : super(ref, null) {
    state = CalendarEntrySet.fromEntries(seed);
  }

  final gate = Completer<void>();
  final List<String> started = [];
  final List<String> removed = [];

  @override
  Future<bool> removeEntryById(String dateKey, String entryId) async {
    started.add(entryId);
    await gate.future;
    removed.add(entryId);
    state = state.removeEntryById(dateKey, entryId);
    return true;
  }
}

/// Opens the real sheet, the way the dock does, once the host is on screen.
class _SheetHost extends ConsumerStatefulWidget {
  const _SheetHost();
  @override
  ConsumerState<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends ConsumerState<_SheetHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final open = showLuminaSheet(context, ref);
      ref.read(luminaSheetProvider.notifier).setMode(LuminaSheetMode.expanded);
      await open;
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SizedBox.expand());
}

/// Pushes the real full screen over a plain home once the host is on screen.
class _ScreenHost extends StatefulWidget {
  const _ScreenHost();
  @override
  State<_ScreenHost> createState() => _ScreenHostState();
}

class _ScreenHostState extends State<_ScreenHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const LuminaAIScreen()));
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SizedBox.expand());
}

/// The surfaces carry looping animations, so a fixed number of frames rather
/// than pumpAndSettle.
Future<void> _settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Taps the card's Delete, closes the surface the way the back button does
/// while the removal is held open, then lets the removal land.
Future<void> _deleteThenClose(
  WidgetTester tester, {
  required Widget home,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final proposal =
      EntryDeleteProposal(entries: [_chiefsNight()], scopeLabel: 'tomorrow');
  late _GatedCalendar calendar;
  final container = ProviderContainer(overrides: [
    luminaSheetProvider.overrideWith(() => _SeededSheet(proposal)),
    calendarScheduleProvider.overrideWith((ref) {
      calendar = _GatedCalendar(ref, [_chiefsNight()]);
      return calendar;
    }),
    wledStateProvider.overrideWith(() => _StillWled()),
    wledRepositoryProvider.overrideWith((ref) => null),
    authStateProvider.overrideWith((ref) => Stream.value(null)),
    demoModeProvider.overrideWith((ref) => false),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: nexGenPremiumDarkTheme,
      builder: TextScaleClamp.appBuilder,
      home: home,
    ),
  ));
  await _settle(tester);

  final card = find.byType(EntryDeleteConfirmCard);
  expect(card, findsOneWidget, reason: 'the confirmation card is on screen');
  await tester.tap(find.descendant(of: card, matching: find.text('Delete')));
  await tester.pump();
  expect(calendar.started, [_kEntryId], reason: 'the removal is in flight');
  expect(calendar.removed, isEmpty);

  // The customer closes the surface while the removal is still out.
  await Navigator.of(tester.element(card)).maybePop();
  await _settle(tester, frames: 6);
  expect(find.byType(EntryDeleteConfirmCard), findsNothing,
      reason: 'the surface is gone');

  // The removal lands; the driver carries on without the surface.
  calendar.gate.complete();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));

  expect(calendar.removed, [_kEntryId]);
  expect(container.read(luminaSheetProvider).messages.last.text,
      entryDeleteOutcomeText(requested: 1, deleted: 1),
      reason: 'the conversation says the entry went');
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the sheet closed mid-delete still removes and reports',
      (tester) async {
    await _deleteThenClose(tester, home: const _SheetHost());
  });

  testWidgets('the full screen closed mid-delete still removes and reports',
      (tester) async {
    await _deleteThenClose(tester, home: const _ScreenHost());
  });
}
