// Closeout: design-edit cancel restores the DEVICE, not just the picker.
//
// Phase C shipped design-edit and selection mode asymmetric — selection mode
// undid its live preview on exit via `_restoreCapturedLook`, design-edit did
// not, so backing out of an edit left a half-tuned look on the house. This
// aligns them and pins the two halves of the rule:
//
//   • CANCEL (back / dispose) → restore the pre-edit look, exactly once.
//   • SAVE                    → do NOT restore. The design now stores what the
//                               lights are showing; undoing it would
//                               contradict the save the user just made.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// Counts device writes. `applyJson` is the ONLY mechanism the restore path
/// uses (`_restoreCapturedLook` → `repo.applyJson`), which is what makes the
/// count a real observation rather than a proxy for one.
class _RecordingRepo implements WledRepository {
  final List<Map<String, dynamic>> applyJsonCalls = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return true;
  }

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => false;
  @override
  Future<Map<int, String>> fetchPresetNames() async => const {};
  @override
  void invalidatePresetCache() {}
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
      false;
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => false;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => false;
  @override
  Future<bool> configureSyncReceiver() async => false;
  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      false;
  @override
  Future<WledHardwareConfig?> getConfig() async => null;
  @override
  Future<bool> supportsRgbw() async => false;
  @override
  Future<List<WledSegment>> fetchSegments() async => const [];
  @override
  Future<bool> renameSegment({required int id, required String name}) async =>
      false;
  @override
  Future<bool> applyToSegments({
    required List<int> ids,
    Color? color,
    int? white,
    int? fx,
    int? speed,
    int? intensity,
  }) async =>
      false;
  @override
  Future<bool> updateSegmentConfig({
    required int segmentId,
    int? start,
    int? stop,
  }) async =>
      false;
  @override
  Future<int?> getTotalLedCount() async => null;
  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async =>
      false;
  @override
  Future<bool> loadPreset(int presetId) async => false;
  @override
  List<WledPreset> getPresets() => const [];
  @override
  void reset() {}
}

CustomDesign _effectDesign() => CustomDesign(
      id: 'fx-1',
      name: 'Sunset Fade',
      createdAt: DateTime(2026, 5, 29),
      updatedAt: DateTime(2026, 6, 1),
      ownerId: 'u',
      brightness: 180,
      channels: [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          included: true,
          effectId: 12,
          speed: 90,
          intensity: 200,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 9, color: const [255, 80, 0, 0]),
          ],
          ledCount: 10,
        ),
      ],
    );

List<Override> _overrides(_RecordingRepo repo) => [
      wledRepositoryProvider.overrideWith((ref) => repo),
      demoModeProvider.overrideWith((ref) => false),
      // A non-empty channel set: the U1 gate short-circuits the restore write
      // before it reaches the repository otherwise, which would make the
      // assertion pass for the wrong reason.
      effectiveChannelIdsProvider.overrideWith((ref) => const <int>[0]),
      deviceChannelsProvider.overrideWith(
        (ref) => const <DeviceChannel>[
          DeviceChannel(id: 0, start: 0, stop: 10, name: 'Front', gpioPin: 2),
        ],
      ),
    ];

void main() {
  group('design-edit cancel restores the device', () {
    testWidgets('backing out after a live preview fires the restore exactly '
        'once', (tester) async {
      final repo = _RecordingRepo();
      final nav = GlobalKey<NavigatorState>();

      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(repo),
        child: MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: SizedBox()),
        ),
      ));

      // Push the tuner in design-edit mode, then pop it — the CANCEL exit is
      // dispose, which is exactly how LibraryBrowserScreen's back button
      // reaches it in the app.
      nav.currentState!.push(MaterialPageRoute(
        builder: (_) => Scaffold(
          body: ColorwayEffectSelectorPage.forDesign(design: _effectDesign()),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      final writesBeforePop = repo.applyJsonCalls.length;

      nav.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 400));

      final restoreWrites = repo.applyJsonCalls.length - writesBeforePop;
      expect(restoreWrites, 1,
          reason: 'cancel must replay the captured pre-edit look once — not '
              'zero (Phase C behaviour, leaves a half-tuned look on the '
              'house) and not twice (double restore)');
    });

    testWidgets('a second pop cannot restore twice — the snapshot is consumed',
        (tester) async {
      final repo = _RecordingRepo();
      final nav = GlobalKey<NavigatorState>();

      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(repo),
        child: MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: SizedBox()),
        ),
      ));

      for (var i = 0; i < 2; i++) {
        nav.currentState!.push(MaterialPageRoute(
          builder: (_) => Scaffold(
            body: ColorwayEffectSelectorPage.forDesign(design: _effectDesign()),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        nav.currentState!.pop();
        await tester.pump(const Duration(milliseconds: 400));
      }

      // Two independent open/cancel cycles → two restores, one each. A single
      // widget restoring twice would show up as 3+.
      expect(repo.applyJsonCalls.length, 2);
    });

    testWidgets('a successful SAVE consumes the snapshot, so the following '
        'dispose does NOT restore', (tester) async {
      final repo = _RecordingRepo();
      final nav = GlobalKey<NavigatorState>();

      // The tuner is a tall CustomScrollView; give it a viewport that lays the
      // commit row out rather than scrolling to find it.
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._overrides(repo),
          // Save succeeds without touching Firestore.
          updateDesignProvider.overrideWithValue((design) async => true),
        ],
        child: MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: SizedBox()),
        ),
      ));

      nav.currentState!.push(MaterialPageRoute(
        builder: (_) => Scaffold(
          body: ColorwayEffectSelectorPage.forDesign(design: _effectDesign()),
        ),
      ));
      // Let the push transition finish so the page is on-stage and laid out.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }

      final before = repo.applyJsonCalls.length;

      // Commit through the real button.
      final save = find.text('Save to design');
      expect(save, findsOneWidget,
          reason: 'the tall viewport set below should put the commit row on '
              'screen; if this fails the tuner layout changed');
      await tester.tap(save);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(repo.applyJsonCalls.length, before,
          reason: 'Save must not replay the pre-edit look — the design now '
              'stores what the lights are showing');
    });

    testWidgets('catalog mode captures nothing, so a pop writes nothing',
        (tester) async {
      final repo = _RecordingRepo();
      final nav = GlobalKey<NavigatorState>();

      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(repo),
        child: MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: SizedBox()),
        ),
      ));

      nav.currentState!.push(MaterialPageRoute(
        builder: (_) => const Scaffold(
          body: ColorwayEffectSelectorPage(
            paletteNode: LibraryNode(
              id: 'holiday_xmas_classic',
              name: 'Classic',
              nodeType: LibraryNodeType.palette,
              themeColors: [Colors.red, Colors.green],
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      nav.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 400));

      expect(repo.applyJsonCalls, isEmpty,
          reason: 'plain catalog browsing must be byte-identical to before: '
              'no capture on entry, no restore on exit');
    });
  });
}
