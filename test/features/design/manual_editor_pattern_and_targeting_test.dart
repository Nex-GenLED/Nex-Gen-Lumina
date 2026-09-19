// M10 (followup N3a) — the on/off pattern tool REPLACES a pattern.
// M2  (audit F2, minimal) — one specific LED is reachable: Go to LED + zoom.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/manual_editor/selection_logic.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

class _CapturingService implements DesignService {
  CustomDesign? saved;
  @override
  Future<String> saveDesign(String userId, CustomDesign design) async {
    saved = design;
    return 'id';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _len = 128;
const _base = [10, 10, 12, 0];

Future<_CapturingService> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final service = _CapturingService();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      designServiceProvider.overrideWithValue(service),
      designsStreamProvider.overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue('u'),
      currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
      houseImageUrlProvider.overrideWithValue(null),
      deviceChannelsProvider.overrideWithValue(const [
        DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: _len, gpioPin: 2),
      ]),
    ],
    child: const MaterialApp(home: Scaffold(body: ManualDesignEditor())),
  ));
  await tester.pump();
  return service;
}

/// Opens the pattern tool, moves Dark from [from] to [dark] with + / −, paints.
Future<void> _paintPattern(WidgetTester tester,
    {required int dark, required int from}) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'On / off pattern'));
  await tester.pumpAndSettle();
  // Dialog rows: Lit, Dark, From LED, To LED → Dark owns the 2nd + and −.
  final plus = find.byIcon(Icons.add).at(1);
  final minus = find.byIcon(Icons.remove).at(1);
  for (int i = from; i < dark; i++) {
    await tester.tap(plus);
    await tester.pump();
  }
  for (int i = from; i > dark; i--) {
    await tester.tap(minus);
    await tester.pump();
  }
  await tester.tap(find.widgetWithText(FilledButton, 'Paint pattern'));
  await tester.pumpAndSettle();
}

Future<List<int>> _savedLit(WidgetTester tester, _CapturingService service) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
  final doc = PixelDesignDocument.fromLedColorGroups(
    baseColor: _base,
    channelLengths: const {0: _len},
    groupsByChannel: {0: service.saved!.channels.first.colorGroups},
  );
  return [
    for (int i = 0; i < _len; i++)
      if (doc.colorAt(0, i).toString() != _base.toString()) i,
  ];
}

void main() {
  group('onOffPatternInRange', () {
    test('1 on / 4 off = every 5th; 1 on / 6 off = every 7th', () {
      final p5 = onOffPatternInRange(start: 0, end: 127, on: 1, off: 4);
      expect(p5.lit, everyNthInRange(start: 0, end: 127, step: 5));
      expect(p5.lit.length + p5.dark.length, 128);
      expect(onOffPatternInRange(start: 0, end: 127, on: 1, off: 6).lit.length, 19);
    });

    test('multi-LED bands, offsets from Start, degenerate inputs', () {
      expect(onOffPatternInRange(start: 10, end: 19, on: 2, off: 3).lit, [10, 11, 15, 16]);
      expect(onOffPatternInRange(start: 0, end: 4, on: 0, off: -2).lit, [0, 1, 2, 3, 4]);
      expect(onOffPatternInRange(start: 9, end: 3, on: 1, off: 1).lit, isEmpty);
      // The single-LED result the user reported: a range shorter than a repeat.
      expect(onOffPatternInRange(start: 0, end: 6, on: 1, off: 6).lit, [0]);
    });
  });

  group('parseLedTarget', () {
    test('a number, a range in either order, several separators', () {
      expect(parseLedTarget('57', 128), (start: 57, end: 57));
      expect(parseLedTarget(' 12-40 ', 128), (start: 12, end: 40));
      expect(parseLedTarget('40 – 12', 128), (start: 12, end: 40));
      expect(parseLedTarget('12 to 40', 128), (start: 12, end: 40));
      expect(parseLedTarget('12:40', 128), (start: 12, end: 40));
    });
    test('rejects non-numbers and LEDs past the end of the channel', () {
      expect(parseLedTarget('abc', 128), isNull);
      expect(parseLedTarget('128', 128), isNull);
      expect(parseLedTarget('5-300', 128), isNull);
      expect(parseLedTarget('', 128), isNull);
    });
  });

  testWidgets('"4 off" then "6 off" gives the NEW pattern, not the union', (tester) async {
    final service = await _pump(tester);
    await _paintPattern(tester, dark: 4, from: 2); // default Dark is 2
    await _paintPattern(tester, dark: 6, from: 4); // the dialog REMEMBERED 4
    final lit = await _savedLit(tester, service);
    expect(lit, everyNthInRange(start: 0, end: _len - 1, step: 7),
        reason: 'was the union of every-5th and every-7th (41 LEDs, not 19)');
    expect(lit.length, 19);
  });

  testWidgets('the dialog says how many LEDs it will light', (tester) async {
    await _pump(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'On / off pattern'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 on, 2 off across LEDs 0–127 (128 LEDs) → 43 lit.'),
        findsOneWidget);
  });

  testWidgets('Go to LED selects exactly that LED and zooms to it', (tester) async {
    final service = await _pump(tester);
    await tester.enterText(find.byKey(const ValueKey('go-to-led')), '57');
    await tester.tap(find.widgetWithText(FilledButton, 'Select'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 selected on Channel 1'), findsOneWidget);
    expect(find.text('1×'), findsNothing, reason: 'zoomed in so LED 57 is visible');
    expect(find.textContaining('LED 57'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Paint'));
    await tester.pumpAndSettle();
    expect(await _savedLit(tester, service), [57],
        reason: 'one typed number → exactly one painted pixel');
  });

  testWidgets('Go to LED: a range, and a helpful error for nonsense', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const ValueKey('go-to-led')), '12-40');
    await tester.tap(find.widgetWithText(FilledButton, 'Select'));
    await tester.pumpAndSettle();
    expect(find.textContaining('29 selected on Channel 1'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('go-to-led')), '999');
    await tester.tap(find.widgetWithText(FilledButton, 'Select'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an LED 0–127'), findsOneWidget);
  });

  testWidgets('zoom in / out: 1× fits the channel, zooming makes it pannable',
      (tester) async {
    await _pump(tester);
    expect(find.text('1×'), findsOneWidget);
    final scroll = find.byKey(const ValueKey('strip-scroll'));
    expect(tester.widget<SingleChildScrollView>(scroll).physics,
        isA<NeverScrollableScrollPhysics>());

    await tester.tap(find.byKey(const ValueKey('strip-zoom-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('strip-zoom-in')));
    await tester.pumpAndSettle();
    expect(find.text('4×'), findsOneWidget);
    expect(tester.widget<SingleChildScrollView>(scroll).physics,
        isA<ClampingScrollPhysics>());

    await tester.tap(find.byKey(const ValueKey('strip-zoom-out')));
    await tester.pumpAndSettle();
    expect(find.text('2×'), findsOneWidget);
  });

  testWidgets('tapping the zoomed strip toggles ONE LED', (tester) async {
    await _pump(tester);
    for (int i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const ValueKey('strip-zoom-in')));
      await tester.pumpAndSettle();
    }
    expect(find.text('16×'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('strip-scroll')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 selected on Channel 1'), findsOneWidget);
  });
}
