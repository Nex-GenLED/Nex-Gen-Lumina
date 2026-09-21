// The paint editor has no brightness control. What it stores is the level the
// user was WATCHING the lights at while they painted — it used to store the
// model's default 200, which no apply path could honour without overriding a
// level somebody had actually set. An edit of a design that already states a
// brightness keeps it (and the editor's own Apply/preview send it).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
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

class _Repo implements WledRepository, PerPixelWriter {
  final json = <Map<String, dynamic>>[];
  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    json.add(Map<String, dynamic>.from(payload));
    return true;
  }

  @override
  Future<bool> applyPerPixel(
          {int segmentId = 0,
          required List<PixelSpan> spans,
          int chunkSize = kDefaultPixelChunkSize}) async =>
      true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The lights as the app sees them: answering, at [brightness].
class _LiveNotifier extends WledNotifier {
  _LiveNotifier(this.brightness, {this.connected = true});
  final int brightness;
  final bool connected;
  @override
  WledStateModel build() => WledStateModel.initial()
      .copyWith(connected: connected, brightness: brightness);
}

final _now = DateTime(2026, 9, 21);

CustomDesign _stored({required int brightness, bool? stated, List<String> tags = const []}) =>
    CustomDesign(
      id: 'stored-1',
      name: 'Porch',
      ownerId: 'customer-uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      brightness: brightness,
      brightnessStated: stated,
      tags: tags,
      channels: const [
        ChannelDesign(channelId: 0, channelName: 'Ch1', ledCount: 40, colorGroups: [
          LedColorGroup(startLed: 0, endLed: 19, color: [255, 0, 0, 0]),
          LedColorGroup(startLed: 20, endLed: 39, color: [0, 0, 255, 0]),
        ]),
      ],
    );

Future<_Repo?> _pumpEditor(
  WidgetTester tester,
  DesignService service, {
  CustomDesign? initial,
  int? liveBrightness,
  bool connected = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repo = liveBrightness == null ? null : _Repo();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      designServiceProvider.overrideWithValue(service),
      designsStreamProvider.overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue('customer-uid'),
      currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
      houseImageUrlProvider.overrideWithValue(null),
      deviceChannelsProvider.overrideWithValue(const [
        DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 40, gpioPin: 2),
      ]),
      effectiveChannelIdsProvider.overrideWithValue(const [0]),
      if (repo != null) ...[
        wledRepositoryProvider.overrideWith((ref) => repo),
        wledStateProvider
            .overrideWith(() => _LiveNotifier(liveBrightness!, connected: connected)),
      ],
    ],
    child: MaterialApp(home: Scaffold(body: ManualDesignEditor(initialDesign: initial))),
  ));
  await tester.pump();
  return repo;
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
  testWidgets('a NEW painting records the level the lights were at — not 200',
      (tester) async {
    final service = _OkDesignService();
    await _pumpEditor(tester, service, liveBrightness: 64);
    await _saveNew(tester);
    expect(service.saved!.brightness, 64);
    expect(service.saved!.brightnessStated, isTrue);
    expect(service.saved!.appliedBrightness, 64);
    expect(service.saved!.toFirestore()['brightness_stated'], isTrue);
  });

  testWidgets('no controller → there is no level to record, and the design '
      'says so rather than claiming 200', (tester) async {
    final service = _OkDesignService();
    await _pumpEditor(tester, service); // no repository at all
    await _saveNew(tester);
    expect(service.saved!.brightnessStated, isFalse);
    expect(service.saved!.appliedBrightness, isNull);
  });

  testWidgets('a controller that is not answering is not a level either',
      (tester) async {
    final service = _OkDesignService();
    await _pumpEditor(tester, service, liveBrightness: 128, connected: false);
    await _saveNew(tester);
    expect(service.saved!.brightnessStated, isFalse);
  });

  testWidgets('EDITING a design that states a brightness keeps it, whatever '
      'the lights are at now', (tester) async {
    final service = _OkDesignService();
    await _pumpEditor(tester, service,
        initial: _stored(brightness: 90, stated: true), liveBrightness: 230);
    await _saveEdit(tester);
    expect(service.saved!.id, 'stored-1');
    expect(service.saved!.brightness, 90);
    expect(service.saved!.brightnessStated, isTrue);
  });

  testWidgets('a legacy Pattern Editor design (tag, no marker) keeps its slider '
      'level through an edit — and the save makes it explicit', (tester) async {
    final service = _OkDesignService();
    await _pumpEditor(tester, service,
        initial: _stored(brightness: 180, tags: const [kPatternEditorDesignTag]),
        liveBrightness: 40);
    await _saveEdit(tester);
    expect(service.saved!.brightness, 180);
    expect(service.saved!.brightnessStated, isTrue);
  });

  testWidgets('EDITING an older painted design (unchosen 200) records the live '
      'level at this save', (tester) async {
    final service = _OkDesignService();
    await _pumpEditor(tester, service,
        initial: _stored(brightness: 200), liveBrightness: 64);
    await _saveEdit(tester);
    expect(service.saved!.brightness, 64);
    expect(service.saved!.brightnessStated, isTrue);
  });

  testWidgets("the editor's own Apply sends the stored brightness of the design "
      'being edited; a new painting sends none', (tester) async {
    final service = _OkDesignService();
    final repo = await _pumpEditor(tester, service,
        initial: _stored(brightness: 90, stated: true), liveBrightness: 230);
    await tester.tap(find.textContaining('Apply'));
    await tester.pumpAndSettle();
    expect(repo!.json, isNotEmpty);
    expect(repo.json.last['bri'], 90);
  });

  testWidgets('…a new painting sends none', (tester) async {
    final service = _OkDesignService();
    final repo = await _pumpEditor(tester, service, liveBrightness: 230);
    await tester.tap(find.textContaining('Apply'));
    await tester.pumpAndSettle();
    expect(repo!.json, isNotEmpty);
    expect(repo.json.last.containsKey('bri'), isFalse);
  });
}
