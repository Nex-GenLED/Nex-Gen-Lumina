// Design Studio Slice 3 — smart preset compile logic + apply orchestration.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_apply.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_logic.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_models.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

const _accent = [0, 229, 255, 0];

/// ch0 (128 LEDs): corner @0, run, peak family @ mid, corner @ end.
List<RooflineSegment> _ch0() => [
      const RooflineSegment(
          id: 'a', name: 'C1', startPixel: 0, pixelCount: 1,
          type: SegmentType.corner, channelIndex: 0, sortOrder: 0),
      const RooflineSegment(
          id: 'b', name: 'R1', startPixel: 1, pixelCount: 40,
          type: SegmentType.run, channelIndex: 0, sortOrder: 1),
      const RooflineSegment(
          id: 'c', name: 'PU', startPixel: 41, pixelCount: 6,
          type: SegmentType.peak, direction: SegmentDirection.upward,
          architecturalRole: ArchitecturalRole.peak, channelIndex: 0, sortOrder: 2),
      const RooflineSegment(
          id: 'd', name: 'PK', startPixel: 47, pixelCount: 1,
          type: SegmentType.peak, channelIndex: 0, sortOrder: 3),
      const RooflineSegment(
          id: 'e', name: 'PD', startPixel: 48, pixelCount: 6,
          type: SegmentType.peak, direction: SegmentDirection.downward,
          architecturalRole: ArchitecturalRole.peak, channelIndex: 0, sortOrder: 4),
      const RooflineSegment(
          id: 'f', name: 'R2', startPixel: 54, pixelCount: 73,
          type: SegmentType.run, channelIndex: 0, sortOrder: 5),
      const RooflineSegment(
          id: 'g', name: 'C2', startPixel: 127, pixelCount: 1,
          type: SegmentType.corner, channelIndex: 0, sortOrder: 6),
    ];

RooflineConfiguration _config({List<RooflineSegment>? ch1}) => RooflineConfiguration(
      id: 'ctrl',
      controllerId: 'ctrl',
      name: 'Roofline',
      segments: [..._ch0(), ...?ch1],
      createdAt: DateTime(2026, 7, 2),
      updatedAt: DateTime(2026, 7, 2),
      totalChannelCount: ch1 == null ? 1 : 2,
    );

void main() {
  group('accentSpansForChannel', () {
    test('cornerAccents: ±spread around corners; runs/peaks untouched', () {
      final spans = accentSpansForChannel(
        segments: _ch0(),
        kind: SmartPresetKind.cornerAccents,
        accentRgbw: _accent,
        busLen: 128,
        cornerSpread: 2,
      );
      // Two corners: @0 → [0,2] (clamped low), @127 → [125,127] (clamped high).
      expect(spans.length, 2);
      expect([spans[0].start, spans[0].end], [0, 2]);
      expect([spans[1].start, spans[1].end], [125, 127]);
      expect(spans[0].color, _accent);
    });

    test('peakHighlights: whole peak family, runs/corners untouched', () {
      final spans = accentSpansForChannel(
        segments: _ch0(),
        kind: SmartPresetKind.peakHighlights,
        accentRgbw: _accent,
        busLen: 128,
      );
      // peakUp[41-46], peak[47], peakDown[48-53].
      expect(spans.map((s) => [s.start, s.end]),
          [[41, 46], [47, 47], [48, 53]]);
    });

    test('featureOutline: all non-run features; runs stay base', () {
      final spans = accentSpansForChannel(
        segments: _ch0(),
        kind: SmartPresetKind.featureOutline,
        accentRgbw: _accent,
        busLen: 128,
        cornerSpread: 0,
      );
      // 2 corners + 3 peak segments = 5 features; the two runs produce nothing.
      expect(spans.length, 5);
    });

    test('runs never produce accent spans (runs-as-base)', () {
      final runsOnly = [
        const RooflineSegment(
            id: 'r', name: 'R', startPixel: 0, pixelCount: 50,
            type: SegmentType.run, channelIndex: 0),
      ];
      for (final kind in SmartPresetKind.values) {
        expect(
          accentSpansForChannel(
              segments: runsOnly, kind: kind, accentRgbw: _accent, busLen: 50),
          isEmpty,
        );
      }
    });

    test('clamps to busLen for a STALE map (features beyond live length)', () {
      final segs = [
        const RooflineSegment(
            id: 'c', name: 'C', startPixel: 100, pixelCount: 1,
            type: SegmentType.corner, channelIndex: 0),
      ];
      // Live bus shrank to 60 LEDs — the corner @100 is out of range → dropped.
      final spans = accentSpansForChannel(
          segments: segs, kind: SmartPresetKind.cornerAccents,
          accentRgbw: _accent, busLen: 60, cornerSpread: 2);
      expect(spans, isEmpty);

      // Live bus 105 → corner @100 (endPixel 100) ±2 clamps to [98,102].
      final spans2 = accentSpansForChannel(
          segments: segs, kind: SmartPresetKind.cornerAccents,
          accentRgbw: _accent, busLen: 105, cornerSpread: 2);
      expect([spans2.single.start, spans2.single.end], [98, 102]);
    });

    test('busLen <= 0 → empty', () {
      expect(
        accentSpansForChannel(
            segments: _ch0(), kind: SmartPresetKind.cornerAccents,
            accentRgbw: _accent, busLen: 0),
        isEmpty,
      );
    });
  });

  group('compileAccentSpans (multi-channel)', () {
    test('per-channel spans; unmapped-count channel falls back to extent', () {
      final ch1 = [
        const RooflineSegment(
            id: 'x', name: 'C', startPixel: 10, pixelCount: 1,
            type: SegmentType.corner, channelIndex: 1),
      ];
      final config = _config(ch1: ch1);
      // Provide bus len for ch0 only; ch1 falls back to segment extent (11).
      final map = compileAccentSpans(
        config: config,
        kind: SmartPresetKind.cornerAccents,
        accentRgbw: _accent,
        busLenByChannel: const {0: 128},
        cornerSpread: 2,
      );
      expect(map.keys.toSet(), {0, 1});
      expect(map[0]!.length, 2); // two corners on ch0
      expect(map[1]!.length, 1); // one corner on ch1
      expect([map[1]!.single.start, map[1]!.single.end], [8, 10]); // clamped to extent 11
    });

    test('channel with no matching feature → empty (base only)', () {
      final map = compileAccentSpans(
        config: _config(),
        kind: SmartPresetKind.peakHighlights,
        accentRgbw: _accent,
        busLenByChannel: const {0: 128},
      );
      // ch0 has peaks → non-empty; a hypothetical peak-less channel would be [].
      expect(map[0], isNotEmpty);
    });
  });

  group('applySmartPreset orchestration', () {
    testWidgets('base via applyJson, accents via applyPerPixel, label set',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = _RecordingRepo();
      late WidgetRef ref;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          wledRepositoryProvider.overrideWith((ref) => repo),
          currentRooflineConfigProvider
              .overrideWith((ref) => Stream.value(_config())),
          deviceChannelsProvider.overrideWithValue(const [
            DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 128, gpioPin: 2),
          ]),
          effectiveChannelIdsProvider.overrideWithValue(const [0]),
          pixelMapStalenessProvider.overrideWithValue(const {0: false}),
          wledStateProvider.overrideWith(() => _FakeWledNotifier()),
        ],
        child: Consumer(builder: (c, r, _) {
          ref = r;
          r.watch(currentRooflineConfigProvider); // subscribe so the stream emits
          return const SizedBox();
        }),
      ));
      await tester.pump(); // let the overridden config stream emit

      final result = await applySmartPreset(
        ref,
        preset: kSmartPresets[0], // Corner Accents
        baseRgbw: const [255, 147, 41, 200],
        accentRgbw: _accent,
      );

      expect(result, SmartPresetApplyResult.applied);
      // Base applied first via the chokepoint (channel-filtered single seg).
      expect(repo.applyJsonCalls.length, 1);
      expect((repo.applyJsonCalls.first['seg'] as List).first['col'],
          [[255, 147, 41, 200]]);
      // Accents applied via applyPerPixel on the mapped channel (segId 0).
      expect(repo.perPixelCalls.length, 1);
      expect(repo.perPixelCalls.first.segmentId, 0);
      expect(repo.perPixelCalls.first.spans.length, 2); // two corners
      // Label wired.
      expect(ref.read(activePresetLabelProvider), 'Corner Accents');
    });

    testWidgets('no map → noMap result, nothing applied', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = _RecordingRepo();
      late WidgetRef ref;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          wledRepositoryProvider.overrideWith((ref) => repo),
          currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
          deviceChannelsProvider.overrideWithValue(const []),
          effectiveChannelIdsProvider.overrideWithValue(const [0]),
          pixelMapStalenessProvider.overrideWithValue(const {}),
          wledStateProvider.overrideWith(() => _FakeWledNotifier()),
        ],
        child: Consumer(builder: (c, r, _) {
          ref = r;
          r.watch(currentRooflineConfigProvider); // subscribe so the stream emits
          return const SizedBox();
        }),
      ));
      await tester.pump(); // let the overridden config stream emit
      final result = await applySmartPreset(
        ref,
        preset: kSmartPresets[0],
        baseRgbw: const [255, 255, 255, 0],
        accentRgbw: _accent,
      );
      expect(result, SmartPresetApplyResult.noMap);
      expect(repo.applyJsonCalls, isEmpty);
      expect(repo.perPixelCalls, isEmpty);
    });

    testWidgets('stale channel → staleApplied (still applies)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = _RecordingRepo();
      late WidgetRef ref;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          wledRepositoryProvider.overrideWith((ref) => repo),
          currentRooflineConfigProvider
              .overrideWith((ref) => Stream.value(_config())),
          deviceChannelsProvider.overrideWithValue(const [
            DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 128, gpioPin: 2),
          ]),
          effectiveChannelIdsProvider.overrideWithValue(const [0]),
          pixelMapStalenessProvider.overrideWithValue(const {0: true}),
          wledStateProvider.overrideWith(() => _FakeWledNotifier()),
        ],
        child: Consumer(builder: (c, r, _) {
          ref = r;
          r.watch(currentRooflineConfigProvider); // subscribe so the stream emits
          return const SizedBox();
        }),
      ));
      await tester.pump(); // let the overridden config stream emit
      final result = await applySmartPreset(
        ref,
        preset: kSmartPresets[0],
        baseRgbw: const [255, 255, 255, 0],
        accentRgbw: _accent,
      );
      expect(result, SmartPresetApplyResult.staleApplied);
      expect(repo.applyJsonCalls.length, 1); // still applied
    });
  });
}

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

class _PerPixelCall {
  final int segmentId;
  final List<PixelSpan> spans;
  _PerPixelCall(this.segmentId, this.spans);
}

class _RecordingRepo extends WledRepository implements PerPixelWriter {
  final List<Map<String, dynamic>> applyJsonCalls = [];
  final List<_PerPixelCall> perPixelCalls = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls.add(payload);
    return true;
  }

  @override
  Future<bool> applyPerPixel({
    int segmentId = 0,
    required List<PixelSpan> spans,
    int chunkSize = kDefaultPixelChunkSize,
  }) async {
    perPixelCalls.add(_PerPixelCall(segmentId, spans));
    return true;
  }

  @override
  Future<Map<String, dynamic>?> getState() async => null;
  @override
  Future<bool> setState(
          {bool? on,
          int? brightness,
          int? speed,
          Color? color,
          int? white,
          bool? forceRgbwZeroWhite}) async =>
      true;
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => true;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => true;
  @override
  Future<bool> configureSyncReceiver() async => true;
  @override
  Future<bool> configureSyncSender(
          {List<String> targets = const [], int ddpPort = 4048}) async =>
      true;
}
