// Roofline slice 1, item 1 — the paint editor STAMPS what it saves with the
// controller id and the per-bus LED lengths it painted over.
//
// Before: ManualDesignEditor._save() built the CustomDesign from the
// document's channel lengths and nothing else about the layout; the design
// was tied to the account only. After: a new painting and an edit both carry
// `DesignLayoutStamp.fromChannels(deviceChannelsProvider, selected controller
// id)`; a design opened and re-saved over a different layout is re-stamped
// for that layout (which is the "open the design and save it again" repair
// the apply-time gate names).
//
// Fixture: one controller `ctl-a`, three buses of 100 LEDs (ids 0, 1, 2).
// Same harness as manual_editor_brightness_save_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OkDesignService implements DesignService {
  CustomDesign? saved;
  @override
  Future<String> saveDesign(String userId, CustomDesign design) async {
    saved = design;
    return 'id';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _threeBuses = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 300, gpioPin: 12),
];

final _now = DateTime(2026, 11, 4);

/// A painted design saved earlier for a TWO-bus layout on another controller.
CustomDesign _storedForOtherLayout() => CustomDesign(
      id: 'stored-1',
      name: 'Porch',
      ownerId: 'customer-uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      brightness: 90,
      brightnessStated: true,
      layoutStamp: const DesignLayoutStamp(
          controllerId: 'ctl-old', busLengths: [100, 100]),
      channels: const [
        ChannelDesign(channelId: 0, channelName: 'Ch1', ledCount: 100, colorGroups: [
          LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
          LedColorGroup(startLed: 50, endLed: 99, color: [0, 0, 255, 0]),
        ]),
        ChannelDesign(channelId: 1, channelName: 'Ch2', ledCount: 100, colorGroups: [
          LedColorGroup(startLed: 0, endLed: 99, color: [0, 255, 0, 0]),
        ]),
      ],
    );

Future<void> _pumpEditor(
  WidgetTester tester,
  DesignService service, {
  CustomDesign? initial,
  List<DeviceChannel> channels = _threeBuses,
  String? controllerId = 'ctl-a',
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      designServiceProvider.overrideWithValue(service),
      designsStreamProvider.overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue('customer-uid'),
      currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
      houseImageUrlProvider.overrideWithValue(null),
      deviceChannelsProvider.overrideWithValue(channels),
      effectiveChannelIdsProvider.overrideWithValue([for (final c in channels) c.id]),
      selectedControllerIdProvider.overrideWithValue(controllerId),
    ],
    child: MaterialApp(home: Scaffold(body: ManualDesignEditor(initialDesign: initial))),
  ));
  await tester.pump();
}

Future<void> _saveNew(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Save')); // name dialog
  await tester.pumpAndSettle();
}

Future<void> _saveEdit(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a NEW painting is stamped with the live buses and the selected '
      'controller: three buses of 100 on ctl-a', (tester) async {
    final service = _OkDesignService();
    await _pumpEditor(tester, service);
    await _saveNew(tester);
    final saved = service.saved!;
    expect(saved.layoutStamp, isNotNull, reason: 'used to be tied to the account only');
    expect(saved.layoutStamp!.controllerId, 'ctl-a');
    expect(saved.layoutStamp!.busLengths, [100, 100, 100]);
    // The stamp and the channels agree — both come from the same lengths.
    expect(saved.channels.map((c) => c.ledCount), [100, 100, 100]);
    final doc = saved.toFirestore();
    expect(doc[kDesignControllerIdField], 'ctl-a');
    expect(doc[kDesignBusLengthsField], [100, 100, 100]);
  });

  testWidgets('no selected controller record → stamped with the lengths only',
      (tester) async {
    final service = _OkDesignService();
    await _pumpEditor(tester, service, controllerId: null);
    await _saveNew(tester);
    expect(service.saved!.layoutStamp!.controllerId, isNull);
    expect(service.saved!.layoutStamp!.busLengths, [100, 100, 100]);
  });

  testWidgets('EDITING a design saved for another layout re-stamps it for the '
      'layout it was just re-fitted over (the "open and save again" repair)',
      (tester) async {
    final service = _OkDesignService();
    await _pumpEditor(tester, service, initial: _storedForOtherLayout());
    await _saveEdit(tester);
    final saved = service.saved!;
    expect(saved.id, 'stored-1', reason: 'an edit updates the same document');
    expect(saved.layoutStamp!.controllerId, 'ctl-a');
    expect(saved.layoutStamp!.busLengths, [100, 100, 100]);
    expect(saved.channels.map((c) => c.channelId), [0, 1, 2],
        reason: 'reconciled over the live three-bus layout');
    expect(saved.brightness, 90, reason: 'nothing else the editor does not own changes');
    expect(saved.brightnessStated, isTrue);
  });
}
