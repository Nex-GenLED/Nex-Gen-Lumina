// The paint editor's per-light brightness (Dim, Ramp, build 129) must reach
// the lights when the design is APPLIED, not only when it is scheduled.
//
// Builds 129 and 130 sent every painted light at its pure colour: on the
// bench, a light dimmed to 5 % lit at full. The older editor tests could not
// see it, because their fake repositories throw the per-pixel spans away.
// These drive the real editor into the real converter, merge and chunker,
// then check the bytes and what the controller would render from them.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/per_pixel_wire.dart';
import '../../helpers/wled_strip_simulator.dart';

const _cyan = [0, 229, 255, 0]; // the editor's default paint colour
const _cyanAt5 = [0, 79, 88, 0]; // cyan at 5 % of its light (bri 13)
const _len = 100;
const _lengths = {0: _len};

class _Saver implements DesignService {
  CustomDesign? saved;
  @override
  Future<String> saveDesign(String userId, CustomDesign design) async {
    saved = design;
    return 'saved-1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The lights as the app sees them: answering, at half brightness.
class _Live extends WledNotifier {
  @override
  WledStateModel build() =>
      WledStateModel.initial().copyWith(connected: true, brightness: 128);
}

/// Pumps the editor (on [initial], when given) in a FRESH scope, so a
/// reopened design is loaded rather than the previous editor kept.
Future<WidgetRef> _pumpEditor(
  WidgetTester tester,
  PerPixelWireRecorder rec,
  _Saver saver, {
  CustomDesign? initial,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  late WidgetRef ref;
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      designServiceProvider.overrideWithValue(saver),
      designsStreamProvider.overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue('customer-uid'),
      currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
      houseImageUrlProvider.overrideWithValue(null),
      deviceChannelsProvider.overrideWithValue(const [
        DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: _len, gpioPin: 2),
      ]),
      effectiveChannelIdsProvider.overrideWithValue(const [0]),
      wledRepositoryProvider.overrideWith((ref) => rec),
      wledStateProvider.overrideWith(() => _Live()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (c, r, _) {
          ref = r;
          return ManualDesignEditor(initialDesign: initial);
        }),
      ),
    ),
  ));
  await tester.pump();
  return ref;
}

Future<void> _select(WidgetTester tester, String leds) async {
  await tester.enterText(find.byKey(const ValueKey('go-to-led')), leds);
  await tester.tap(find.widgetWithText(FilledButton, 'Select'));
  await tester.pumpAndSettle();
}

/// Paint lights 0 and 1 (default cyan), then dim light 1 to 5 %.
Future<void> _paintTwoDimOne(WidgetTester tester) async {
  await _select(tester, '0-1');
  await tester.tap(find.text('Paint'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(OutlinedButton, 'Clear sel.'));
  await tester.pumpAndSettle();
  await _select(tester, '1');
  // The slider's own callback (it moves in 5 % steps).
  tester
      .widget<Slider>(find.byKey(const ValueKey('pixel-brightness-slider')))
      .onChanged!(5);
  await tester.pump();
  expect(find.text('Dim to 5 %'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('pixel-dim')));
  await tester.pumpAndSettle();
}

Future<void> _apply(WidgetTester tester) async {
  await tester.tap(find.text('Apply to Lights'));
  await tester.pumpAndSettle();
}

/// What the controller lights from [bodies], sent in order.
List<List<int>> _rendered(List<Map<String, dynamic>> bodies) {
  Map<int, List<List<int>>>? strips;
  for (final b in bodies) {
    strips = renderPayloadOnto(b, _lengths, into: strips);
  }
  return strips![0]!;
}

CustomDesign _throughFirestore(CustomDesign d) {
  final data = d.toFirestore();
  data['channels'] = jsonDecode(jsonEncode(data['channels']));
  return CustomDesign.fromFirestoreData('saved-1', data);
}

void main() {
  testWidgets('Paint two lights, dim one to 5 %, Apply: the dim light is sent '
      'dim and the controller lights it at about 5 %', (tester) async {
    final rec = PerPixelWireRecorder();
    await _pumpEditor(tester, rec, _Saver());
    await _paintTwoDimOne(tester);
    rec.bodies.clear();
    await _apply(tester);

    final sent = sentPixelBytes(rec.pixelBodies, _lengths)[0]!;
    expect(sent[0], _cyan);
    expect(sent[1], isNot(sent[0]),
        reason: 'build 130 sent "i":[0,2,[0,229,255,0]]: both lights at full');
    expect(sent[1], litRgbwForBrightness(_cyan, 13));
    expect(sent[1], _cyanAt5);

    final levels = lightLevels(_rendered(rec.bodies));
    expect(levels[0], closeTo(100, 0.5));
    expect(levels[1], closeTo(5, 1));
  });

  testWidgets('Preview on lights sends the same dimmed light', (tester) async {
    final rec = PerPixelWireRecorder();
    await _pumpEditor(tester, rec, _Saver());
    await _paintTwoDimOne(tester);
    rec.bodies.clear();
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 350)); // the 300 ms throttle
    await tester.pumpAndSettle();

    final sent = sentPixelBytes(rec.pixelBodies, _lengths)[0]!;
    expect(sent[0], _cyan);
    expect(sent[1], _cyanAt5);
    expect(lightLevels(_rendered(rec.bodies))[1], closeTo(5, 1));
  });

  testWidgets('save, reopen, apply: the reopened design applies at the level it '
      'was saved with, from the editor and from My Designs', (tester) async {
    final rec = PerPixelWireRecorder();
    final saver = _Saver();
    await _pumpEditor(tester, rec, saver);
    await _paintTwoDimOne(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save')); // name dialog
    await tester.pumpAndSettle();

    final saved = saver.saved!;
    final light1 = saved.channels.single.colorGroups
        .firstWhere((g) => g.startLed <= 1 && g.endLed >= 1);
    expect(light1.color, _cyan, reason: 'the colour is saved pure');
    expect(light1.bri, 13, reason: 'and the level apart from it');

    final reopened = _throughFirestore(saved);
    final ref = await _pumpEditor(tester, rec, saver, initial: reopened);
    rec.bodies.clear();
    await _apply(tester);
    final fromEditor = sentPixelBytes(rec.pixelBodies, _lengths)[0]!;
    expect(fromEditor[0], _cyan);
    expect(fromEditor[1], _cyanAt5);
    expect(lightLevels(_rendered(rec.bodies))[1], closeTo(5, 1));

    // My Designs, scenes and favourites share this converter.
    rec.bodies.clear();
    final report = await applyCustomDesignDetailed(ref, reopened);
    expect(report.ok, isTrue, reason: report.message);
    final fromMyDesigns = sentPixelBytes(rec.pixelBodies, _lengths)[0]!;
    final ch = reopened.channels.single;
    expect(fromMyDesigns, spanPixelBytes(ch.positionalSpans(), ch.ledCount),
        reason: 'the same bytes a schedule of this design sends');
    expect(fromMyDesigns[1], _cyanAt5);
  });
}
