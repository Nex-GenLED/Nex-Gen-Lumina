// Selection-mode (schedule "Choose a pattern") behavior of
// ColorwayEffectSelectorPage. These tests drive the REAL effect-selector
// widget — capture-on-entry, live preview, and restore-on-exit — rather than
// the return DTO in isolation (the gap that let the apply-on-tap bug ship:
// library_design_selection_test only checked LibraryDesignSelection's fields
// and never mounted the card, so a dropped selection flag / missing restore
// went unnoticed).
//
// Locked mechanism (see colorway_effect_selector.dart): the live preview and
// the restore BOTH go through WledRepository.applyJson — restore re-applies the
// pre-preview WledStateModel snapshot, NOT a config/preset write. The fake repo
// records applyJson vs applyConfig so we can assert the mechanism.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeWledRepository implements WledRepository {
  /// Geometry (`start`/`stop`/`rev`/`mi`) is the PROVISIONING door — a separate
  /// method so `applyJson` can strip geometry unconditionally. This fake does
  /// not exercise it; `false` matches the interface default ("this transport
  /// cannot provision").
  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async => false;

  final List<Map<String, dynamic>> applyJsonCalls = [];
  final List<Map<String, dynamic>> applyConfigCalls = [];
  final List<int> loadPresetCalls = [];
  bool applyJsonShouldSucceed = true;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return applyJsonShouldSucceed;
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    applyConfigCalls.add(Map<String, dynamic>.from(cfg));
    return false;
  }

  @override
  Future<bool> loadPreset(int presetId) async {
    loadPresetCalls.add(presetId);
    return false;
  }

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
  List<WledPreset> getPresets() => const [];
  @override
  void reset() {}
}

/// Seed-only notifier: returns a fixed pre-preview device look and never starts
/// the periodic poll, so [ColorwayEffectSelectorPage.initState] captures a
/// KNOWN [WledStateModel] and no pending Timer trips the test binding.
class _SeededWledNotifier extends WledNotifier {
  _SeededWledNotifier(this._seed);
  final WledStateModel _seed;
  @override
  WledStateModel build() => _seed;
}

/// Distinctive pre-preview look: every scalar differs from what the preview /
/// commit paths emit (preview sends bri:255 + effect-derived fx), so a restore
/// payload is unambiguously the captured snapshot round-tripping back.
WledStateModel _capturedSeed() => const WledStateModel(
      isOn: true,
      brightness: 111,
      speed: 88,
      intensity: 99,
      color: Color(0xFF0A141E), // (10, 20, 30)
      connected: true,
      warmWhite: 0,
      supportsRgbw: false,
      effectId: 7,
      paletteId: 3,
      colorGroupSize: 2,
      spacing: 3,
      colorSequence: [Color(0xFF0A141E)],
    );

LibraryNode _paletteNode() => const LibraryNode(
      id: 'ocean_breeze',
      name: 'Ocean Breeze',
      nodeType: LibraryNodeType.palette,
      parentId: 'cat_water',
      themeColors: [Color(0xFF0066FF)],
      sortOrder: 0,
    );

List<Override> _overrides(
  _FakeWledRepository repo, {
  required WledStateModel seed,
}) =>
    [
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledStateProvider.overrideWith(() => _SeededWledNotifier(seed)),
      wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
      ),
      // Non-empty effective channels so the U1 gate passes for preview+restore.
      effectiveChannelIdsProvider.overrideWith((ref) => const [0]),
    ];

Widget _harness({
  required ProviderContainer container,
  required void Function(LibraryDesignSelection) onDesignSelected,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: ColorwayEffectSelectorPage(
          paletteNode: _paletteNode(),
          onDesignSelected: onDesignSelected,
        ),
      ),
    ),
  );
}

/// The single restore write (if any) — the applyJson call carrying the captured
/// snapshot's signature (bri:111), as opposed to a preview write (bri:255).
Map<String, dynamic>? _restoreCall(_FakeWledRepository repo) {
  for (final c in repo.applyJsonCalls) {
    if (c['bri'] == 111) return c;
  }
  return null;
}

Map<String, dynamic> _firstSeg(Map<String, dynamic> payload) {
  final seg = payload['seg'];
  final list = seg is List ? seg : [seg];
  return Map<String, dynamic>.from(list.first as Map);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
      '(a)+(c) Save ("Set design") returns the selection AND restores the '
      'captured look via applyJson (not applyConfig/loadPreset)',
      (tester) async {
    final repo = _FakeWledRepository();
    final container =
        ProviderContainer(overrides: _overrides(repo, seed: _capturedSeed()));
    LibraryDesignSelection? received;
    await tester.pumpWidget(_harness(
      container: container,
      onDesignSelected: (s) => received = s,
    ));
    await tester.pump();

    await tester.tap(find.text('Set design'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // (e) the selection lands with the design's identity + a non-empty payload
    // (this is exactly what the schedule editor stores into _selectedPattern).
    expect(received, isNotNull, reason: 'Save must hand a selection back');
    expect(received!.id, 'ocean_breeze');
    expect(received!.name, contains('Ocean Breeze'));
    expect(received!.wledPayload['on'], isTrue);
    expect(received!.wledPayload['seg'], isA<List>());

    // (c) mechanism: restore went through applyJson, carrying the captured
    // snapshot verbatim — NOT a config or preset write.
    expect(repo.applyConfigCalls, isEmpty,
        reason: 'restore must not write /json/cfg');
    expect(repo.loadPresetCalls, isEmpty,
        reason: 'restore must not use the preset path');
    final restore = _restoreCall(repo);
    expect(restore, isNotNull,
        reason: 'the pre-preview look must be re-applied on Save');
    // (a) capture-on-entry proven: the restore payload reflects the seeded
    // pre-preview WledStateModel, not preview defaults.
    expect(restore!['on'], isTrue);
    final seg = _firstSeg(restore);
    expect(seg['fx'], 7);
    expect(seg['sx'], 88);
    expect(seg['ix'], 99);
    expect(seg['pal'], 3);
    expect(seg['grp'], 2);
    expect(seg['spc'], 3);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('(b) preview applies live on adjustment in selection mode',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeWledRepository();
    final container =
        ProviderContainer(overrides: _overrides(repo, seed: _capturedSeed()));
    await tester.pumpWidget(_harness(
      container: container,
      onDesignSelected: (_) {},
    ));
    await tester.pump();

    // Twist the speed slider — the preview path (_sendToWled) is NOT gated by
    // selection mode, so it must write to the device.
    final slider = find.byType(Slider).first;
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(60, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // clear the debounce

    final previewWrites =
        repo.applyJsonCalls.where((c) => c['bri'] == 255).toList();
    expect(previewWrites, isNotEmpty,
        reason: 'live preview must apply on adjustment in selection mode');

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('(d) Cancel (backing out / dispose) restores the captured look',
      (tester) async {
    final repo = _FakeWledRepository();
    final container =
        ProviderContainer(overrides: _overrides(repo, seed: _capturedSeed()));
    await tester.pumpWidget(_harness(
      container: container,
      onDesignSelected: (_) {},
    ));
    await tester.pump();

    // No Save — user backs out. Disposing the effect selector (as the parent
    // LibraryBrowserScreen's back button would) must restore.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));

    final restore = _restoreCall(repo);
    expect(restore, isNotNull,
        reason: 'backing out must undo the preview via applyJson');
    expect(_firstSeg(restore!)['fx'], 7);
    expect(repo.applyConfigCalls, isEmpty);

    container.dispose();
  });

  testWidgets(
      '(f) a FAILED restore does not report success — snapshot is retained '
      'so a later exit/apply retries', (tester) async {
    final repo = _FakeWledRepository()..applyJsonShouldSucceed = false;
    final container =
        ProviderContainer(overrides: _overrides(repo, seed: _capturedSeed()));
    LibraryDesignSelection? received;
    await tester.pumpWidget(_harness(
      container: container,
      onDesignSelected: (s) => received = s,
    ));
    await tester.pump();

    // Save with a failing device: the selection must still be delivered (the
    // user's choice is not lost), but the restore write fails.
    await tester.tap(find.text('Set design'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(received, isNotNull,
        reason: 'a failed restore must not lose the selection');
    final restoreAttemptsOnSave =
        repo.applyJsonCalls.where((c) => c['bri'] == 111).length;
    expect(restoreAttemptsOnSave, greaterThanOrEqualTo(1),
        reason: 'restore was attempted');

    // Snapshot NOT consumed (write failed) → dispose retries the restore.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    final totalRestoreAttempts =
        repo.applyJsonCalls.where((c) => c['bri'] == 111).length;
    expect(totalRestoreAttempts, greaterThan(restoreAttemptsOnSave),
        reason:
            'failed restore leaves the snapshot set, so dispose retries it');

    container.dispose();
  });
}
