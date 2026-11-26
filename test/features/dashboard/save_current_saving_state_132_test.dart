// Build 132 — Save As Custom Pattern / the Now Playing save show they are
// saving.
//
// The save now reads the controller's current look once before it writes
// (up to 50 s away from home), and Home showed nothing meanwhile — a second
// tap opened the dialog again. While the save waits, Home shows a "Saving…"
// bar with a progress ring, the Save As Custom Pattern button shows the same,
// and further taps are ignored. All of it clears when the save succeeds and
// when it fails.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/dashboard/wled_dashboard_page.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/wled/display_pattern_providers.dart';
import 'package:nexgen_command/features/wled/save_custom_pattern_dialog.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

/// The save, held open until the test answers it.
class _HeldSave {
  final calls = <String>[];
  Completer<String?>? _pending;

  Future<String?> call(String name) {
    calls.add(name);
    _pending = Completer<String?>();
    return _pending!.future;
  }

  void succeed() => _pending!.complete('auto-1');
  void fail(Object e) => _pending!.completeError(e);
}

Future<_HeldSave> _home(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final save = _HeldSave();
  final c = ProviderContainer(overrides: [
    ...homeDashboardOverrides(repo: RecordingWledRepository()),
    // Home believes the running look is unsaved, so Now Playing offers Save.
    isUnsavedCustomConfigProvider.overrideWithValue(true),
    displayPatternNameProvider.overrideWithValue('Mixed look'),
    saveCurrentAsDesignProvider.overrideWithValue(save.call),
  ]);
  addTearDown(c.dispose);
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await c.read(wledConnectivityStatusProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: WledDashboardPage()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return save;
}

Finder get _nowPlayingName => find.text('Mixed look').first;

Future<void> _saveAs(WidgetTester tester, String name) async {
  await tester.tap(_nowPlayingName);
  await _frames(tester);
  expect(find.byType(SaveCustomPatternDialog), findsOneWidget);
  await tester.enterText(find.byType(TextFormField), name);
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pump(); // the dialog closes
  await tester.pump(const Duration(milliseconds: 400)); // the bar slides in
}

Finder get _savingBar => find.descendant(
    of: find.byType(SnackBar), matching: find.text('Saving…'));

Finder get _savingRing => find.descendant(
    of: find.byType(SnackBar), matching: find.byType(CircularProgressIndicator));

/// Home animates without end (the sky, the roofline), so it never "settles";
/// a fixed run of frames lets a dialog or a bar finish arriving.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _settleBars(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

void main() {
  testWidgets('while the save waits: "Saving…" with a progress ring, and a '
      'second tap is ignored; on success it clears', (tester) async {
    final save = await _home(tester);
    await _saveAs(tester, 'Evening');

    expect(save.calls, ['Evening']);
    expect(_savingBar, findsOneWidget);
    expect(_savingRing, findsOneWidget);

    // A second tap while saving: no second dialog, no second save.
    await tester.tap(_nowPlayingName);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SaveCustomPatternDialog), findsNothing);
    expect(save.calls, hasLength(1));

    save.succeed();
    await _settleBars(tester);
    expect(_savingBar, findsNothing);
    expect(find.text('Saved "Evening" to My Designs'), findsOneWidget);

    // Cleared: Save works again.
    await tester.tap(_nowPlayingName);
    await _frames(tester);
    expect(find.byType(SaveCustomPatternDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await _settleBars(tester);
    await unmountHome(tester);
  });

  testWidgets('a save that cannot read the lights: the saving state clears '
      'and the reason is shown', (tester) async {
    final save = await _home(tester);
    await _saveAs(tester, 'Evening');
    expect(_savingBar, findsOneWidget);

    save.fail(const CurrentLookNotSaved(kCurrentLookUnreadableMessage));
    await _settleBars(tester);
    expect(_savingBar, findsNothing);
    expect(find.text(kCurrentLookUnreadableMessage), findsOneWidget);

    await tester.tap(_nowPlayingName);
    await _frames(tester);
    expect(find.byType(SaveCustomPatternDialog), findsOneWidget,
        reason: 'the saving state cleared, so Save works again');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await _settleBars(tester);
    await unmountHome(tester);
  });

  testWidgets('the Save As Custom Pattern button shows "Saving…" and cannot '
      'be pressed while the save waits', (tester) async {
    final save = await _home(tester);
    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pump(const Duration(milliseconds: 400));
    final button = find.widgetWithText(OutlinedButton, 'Save As Custom Pattern');
    expect(button, findsOneWidget);

    await _saveAs(tester, 'Evening');
    final saving = find.widgetWithText(OutlinedButton, 'Saving…');
    expect(saving, findsOneWidget);
    expect(tester.widget<OutlinedButton>(saving).onPressed, isNull);
    expect(
        find.descendant(of: saving, matching: find.byType(CircularProgressIndicator)),
        findsOneWidget);

    save.succeed();
    await _settleBars(tester);
    expect(find.widgetWithText(OutlinedButton, 'Saving…'), findsNothing);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    await unmountHome(tester);
  });
}
