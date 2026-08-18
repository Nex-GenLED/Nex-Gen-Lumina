// Tests for applySavedDesign (#62, audit 2026-05-29). Verifies the
// canonical 6-step apply runs end-to-end and produces the #81 fixes:
//   - activePresetLabelProvider is set to the DESIGN'S name (fingerprinted)
//   - wledStateProvider's preview cache is updated (colorSequence,
//     effectName) so the dashboard renders the as-sent payload immediately
//     instead of waiting for the next device poll.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/apply_saved_design.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
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
  bool applyJsonShouldSucceed = true;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(Map<String, dynamic>.from(payload));
    return applyJsonShouldSucceed;
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

CustomDesign _blueDesign() => CustomDesign(
      id: 'blue-1',
      name: 'Calming Sky',
      createdAt: DateTime(2026, 5, 29),
      updatedAt: DateTime(2026, 5, 29),
      ownerId: 'u',
      brightness: 200,
      channels: [
        const ChannelDesign(
          channelId: 0,
          channelName: 'Front Roofline',
          included: true,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 9, color: [0, 0, 255, 0]),
          ],
          effectId: 0,
        ),
      ],
    );

List<Override> _defaultOverrides(_FakeWledRepository repo) => [
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
      ),
      // Not in sync → SyncWarningDialog.checkAndProceed returns immediately.
      userSyncStatusProvider.overrideWith((ref) => const UserSyncStatus()),
      // Provide non-empty effective channels so the U1 gate passes.
      effectiveChannelIdsProvider.overrideWith((ref) => const [0]),
    ];

/// Mounts a tiny widget whose only job is to invoke [applySavedDesign] on
/// first frame so the test can pump + inspect provider state afterward.
Widget _harness({
  required ProviderContainer container,
  required CustomDesign design,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: Consumer(builder: (ctx, ref, _) {
            return ElevatedButton(
              onPressed: () => applySavedDesign(ctx, ref, design),
              child: const Text('Apply'),
            );
          }),
        );
      }),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetActivePresetLabelCacheForTest();
  });

  /// Wraps the `pump → tap → assert → cleanup` cycle, ensuring the
  /// container is disposed before the test exits. Disposal cancels
  /// WledNotifier's periodic poll Timer via `ref.onDispose`; without
  /// this, flutter_test's "no pending timers" invariant fires before
  /// addTearDown gets to dispose.
  Future<void> _runApplyTest(
    WidgetTester tester, {
    required ProviderContainer container,
    required CustomDesign design,
    required Future<void> Function() assertions,
  }) async {
    await tester.pumpWidget(_harness(container: container, design: design));
    await tester.tap(find.text('Apply'));
    // Drain the apply's async chain (SyncWarning gate → applyJson →
    // preview/label writes → snackbar). pump twice to cover the
    // microtasks in setLabelWithFingerprint's persisted-intent write.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await assertions();
    // Detach the widget tree then dispose the container so the polling
    // Timer is cancelled before the binding's invariant check runs.
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  }

  testWidgets(
      'applySavedDesign registers a LabelIntent with the design name',
      (tester) async {
    final repo = _FakeWledRepository();
    final container = ProviderContainer(overrides: _defaultOverrides(repo));
    await _runApplyTest(
      tester,
      container: container,
      design: _blueDesign(),
      assertions: () async {
        expect(container.read(activePresetLabelProvider), 'Calming Sky',
            reason: "#81 fix: label is the DESIGN's name, not effectName fallback");
      },
    );
  });

  testWidgets(
      'applySavedDesign updates wledStateProvider preview cache '
      '(colorSequence + effectName)', (tester) async {
    final repo = _FakeWledRepository();
    final container = ProviderContainer(overrides: _defaultOverrides(repo));
    await _runApplyTest(
      tester,
      container: container,
      design: _blueDesign(),
      assertions: () async {
        final state = container.read(wledStateProvider);
        expect(state.colorSequence, isNotEmpty,
            reason: '#81 fix: preview cache populated, no stale carry-over');
        expect(state.colorSequence.first.b * 255, closeTo(255, 1),
            reason: 'design colors made it into the dashboard preview');
        expect(state.customEffectName, 'Calming Sky',
            reason: 'effectName carries through for dashboard display');
        expect(state.isOn, isTrue);
      },
    );
  });

  testWidgets(
      'applySavedDesign sends payload to repo via applyJson chokepoint',
      (tester) async {
    final repo = _FakeWledRepository();
    final container = ProviderContainer(overrides: _defaultOverrides(repo));
    await _runApplyTest(
      tester,
      container: container,
      design: _blueDesign(),
      assertions: () async {
        expect(repo.applyJsonCalls, hasLength(1),
            reason: 'chokepoint hit exactly once');
        final sent = repo.applyJsonCalls.first;
        expect(sent['on'], isTrue);
        expect(sent['seg'], isA<List>());
      },
    );
  });

  testWidgets(
      'applySavedDesign does NOT mutate label when applyJson fails',
      (tester) async {
    final repo = _FakeWledRepository()..applyJsonShouldSucceed = false;
    final container = ProviderContainer(overrides: _defaultOverrides(repo));
    await _runApplyTest(
      tester,
      container: container,
      design: _blueDesign(),
      assertions: () async {
        expect(container.read(activePresetLabelProvider), isNull,
            reason: 'on write failure, no optimistic label commit');
      },
    );
  });

  testWidgets(
      'applySavedDesign skips silently when no effective channels (U1 gate)',
      (tester) async {
    final repo = _FakeWledRepository();
    final container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
      ),
      userSyncStatusProvider.overrideWith((ref) => const UserSyncStatus()),
      effectiveChannelIdsProvider.overrideWith((ref) => const <int>[]),
    ]);
    await _runApplyTest(
      tester,
      container: container,
      design: _blueDesign(),
      assertions: () async {
        expect(repo.applyJsonCalls, isEmpty,
            reason: 'U1 gate must short-circuit before any device write');
        expect(container.read(activePresetLabelProvider), isNull);
      },
    );
  });
}
