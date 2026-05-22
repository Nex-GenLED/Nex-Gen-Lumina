import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal stub repository — preview-sync tests don't exercise device IO,
/// they drive the notifier through its test-only entry points.
class _FakeWledRepository implements WledRepository {
  @override
  Future<Map<int, String>> fetchPresetNames() async => const <int, String>{};
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
  Future<bool> applyJson(Map<String, dynamic> payload) async => false;
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
  Future<List<WledSegment>> fetchSegments() async => const <WledSegment>[];
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

/// Builds a /json/state-shaped map carrying a single seg with the given
/// fx + color list. The color list is sent verbatim as `col` slots; the
/// caller is responsible for crafting the polled-shape (e.g. including
/// `[0,0,0]` to verify the parser strips it).
Map<String, dynamic> _polledState({
  required int fx,
  required List<List<int>> cols,
  int bri = 200,
  int sx = 128,
  int ix = 128,
  int grp = 1,
  int spc = 0,
}) {
  return <String, dynamic>{
    'on': true,
    'bri': bri,
    'ps': 0,
    'seg': [
      {
        'id': 0,
        'fx': fx,
        'sx': sx,
        'ix': ix,
        'grp': grp,
        'spc': spc,
        'col': cols,
      },
    ],
  };
}

ProviderContainer _makeContainer() {
  return ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => _FakeWledRepository()),
    wledConnectivityStatusProvider.overrideWith(
      (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local),
    ),
  ]);
}

Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('applyPreviewSync — single chokepoint writes both sinks', () {
    test('writes wledStateProvider AND explorePreviewProvider atomically',
        () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);

      // Precondition: explore preview is null (no design selected yet).
      expect(container.read(explorePreviewProvider), isNull);

      notifier.applyPreviewSync(
        colors: const [Color(0xFFFF0000), Color(0xFF00FF00)],
        effectId: 12,
        effectName: 'Theater Chase',
        speed: 80,
        intensity: 180,
        brightness: 220,
        colorGroupSize: 2,
        spacing: 1,
      );

      // wledStateProvider mirrors the as-sent payload.
      final wState = container.read(wledStateProvider);
      expect(wState.colorSequence,
          equals(const [Color(0xFFFF0000), Color(0xFF00FF00)]));
      expect(wState.effectId, 12);
      expect(wState.speed, 80);
      expect(wState.intensity, 180);
      expect(wState.brightness, 220);
      expect(wState.colorGroupSize, 2);
      expect(wState.spacing, 1);
      expect(wState.customEffectName, 'Theater Chase');
      expect(wState.isOn, isTrue);

      // explorePreviewProvider carries the same as-sent values.
      final ePreview = container.read(explorePreviewProvider);
      expect(ePreview, isNotNull);
      expect(ePreview!.colors,
          equals(const [Color(0xFFFF0000), Color(0xFF00FF00)]));
      expect(ePreview.effectId, 12);
      expect(ePreview.speed, 80);
      expect(ePreview.brightness, 220);
      expect(ePreview.name, 'Theater Chase');
      expect(ePreview.colorGroupSize, 2);
      expect(ePreview.spacing, 1);
    });

    test('updateExplorePreview:false leaves explore sink untouched', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);

      // Pre-set explore to a known value to verify it survives.
      container.read(explorePreviewProvider.notifier).state =
          const ExplorePreviewState(
        colors: [Color(0xFF000000)],
        effectId: 99,
        name: 'Sentinel',
      );

      notifier.applyPreviewSync(
        colors: const [Color(0xFFFFFFFF)],
        effectId: 0,
        effectName: 'Solid',
        updateExplorePreview: false,
      );

      expect(container.read(explorePreviewProvider)?.name, 'Sentinel',
          reason: 'updateExplorePreview:false must not clobber the sentinel');
      expect(container.read(wledStateProvider).effectId, 0,
          reason: 'wledStateProvider still updates regardless');
    });
  });

  group('Poll-overwrite suppression after local apply', () {
    test('polled colors do NOT overwrite just-applied colors within window',
        () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);

      // 1. Local apply with a 3-color sequence that includes a black slot.
      //    This is the as-sent representation; the device will return the
      //    same slots faithfully but the poller's parser strips zero-value
      //    slots, producing a lossy [red, blue] instead of [red, black, blue].
      notifier.applyPreviewSync(
        colors: const [
          Color(0xFFFF0000),
          Color(0xFF000000),
          Color(0xFF0000FF),
        ],
        effectId: 17,
        effectName: 'Twinkle',
      );

      // Sanity: as-sent sequence landed in state.
      expect(container.read(wledStateProvider).colorSequence.length, 3);

      // 2. Simulate the next poll arriving ~150ms later (well inside the
      //    2s suppression window). The parser would normally strip the
      //    middle slot — the suppression guard must prevent that write.
      notifier.applyStateDataForTest(_polledState(
        fx: 17,
        cols: const [
          [255, 0, 0],
          [0, 0, 0],
          [0, 0, 255],
        ],
      ));
      await _settle();

      // The as-sent 3-color sequence survives. If the suppression guard
      // were missing, this would be 2 colors (black stripped).
      expect(container.read(wledStateProvider).colorSequence.length, 3,
          reason: 'poll within 2s window must not overwrite local color seq');
      expect(container.read(wledStateProvider).colorSequence[1],
          const Color(0xFF000000),
          reason: 'middle (black) slot must survive — drift bug otherwise');
      expect(container.read(wledStateProvider).effectId, 17,
          reason: 'effectId stays at locally-applied value');
    });

    test('connected + presetId still update from poll within window',
        () async {
      // The suppression window blocks ONLY the visual fields applyLocalPreview
      // owns. Connection state and preset-id changes from the device are
      // unrelated to drift and must continue to flow through.
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);

      notifier.applyPreviewSync(
        colors: const [Color(0xFFFF0000)],
        effectId: 0,
        effectName: 'Solid',
      );

      // Sanity: pre-poll state.
      expect(container.read(wledStateProvider).connected, isFalse,
          reason: 'initial state.connected is false');

      // Poll within window: device reports a different ps (preset slot).
      notifier.applyStateDataForTest(<String, dynamic>{
        'on': true,
        'bri': 200,
        'ps': 7,
        'seg': [
          {
            'id': 0,
            'fx': 0,
            'sx': 128,
            'ix': 128,
            'col': [
              [255, 0, 0]
            ],
          }
        ],
      });
      await _settle();

      expect(container.read(wledStateProvider).connected, isTrue,
          reason: 'connected must flip true even during suppression');
      expect(container.read(wledStateProvider).presetId, 7,
          reason: 'preset id changes still flow through during suppression');
    });

    test('after window expires, polled colors resume overwriting', () async {
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);

      notifier.applyPreviewSync(
        colors: const [
          Color(0xFFFF0000),
          Color(0xFF000000),
          Color(0xFF0000FF),
        ],
        effectId: 17,
        effectName: 'Twinkle',
      );

      // Backdate the suppression timestamp past the 2s window. This is the
      // test-only knob added on the notifier so tests don't need to wait
      // 2 real seconds.
      notifier.debugSetLastLocalApplyAtForTest(
        DateTime.now().subtract(const Duration(seconds: 3)),
      );

      // Now poll — the polled (lossy) sequence should apply normally.
      notifier.applyStateDataForTest(_polledState(
        fx: 17,
        cols: const [
          [255, 0, 0],
          [0, 0, 0],
          [0, 0, 255],
        ],
      ));
      await _settle();

      // Polled lossy version applies: parser stripped the [0,0,0] slot.
      expect(container.read(wledStateProvider).colorSequence.length, 2,
          reason:
              'after 2s window, polled state resumes overwriting (lossy parse)');
    });

    test('effectId drift from device DOES update after window', () async {
      // External state change scenario: user applies pattern A, then
      // autopilot/wall-switch loads pattern B on the device. After the
      // suppression window the dashboard should reflect the new effect.
      final container = _makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(wledStateProvider.notifier);

      notifier.applyPreviewSync(
        colors: const [Color(0xFFFF0000)],
        effectId: 0,
        effectName: 'Solid',
      );

      notifier.debugSetLastLocalApplyAtForTest(
        DateTime.now().subtract(const Duration(seconds: 3)),
      );

      notifier.applyStateDataForTest(_polledState(
        fx: 42,
        cols: const [
          [0, 255, 0]
        ],
      ));
      await _settle();

      expect(container.read(wledStateProvider).effectId, 42,
          reason: 'external effect changes surface after the window');
      expect(container.read(wledStateProvider).colorSequence.length, 1);
    });
  });
}
