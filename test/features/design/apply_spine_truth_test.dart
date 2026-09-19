// M5 (audit F7) — the shared apply spine reports what ACTUALLY happened.
// M12 (audit F5) — a smart preset with nothing to accent says so, and sends
// nothing, instead of painting a plain solid and reporting "Applied."
//
// The spine has three callers (manual editor, AI studio "Apply to Lights",
// smart presets). They are tested through the spine so all three inherit.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/demo/demo_wled_repository.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_apply.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_models.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channels = [
  DeviceChannel(id: 0, name: 'Ch1', start: 0, stop: 128, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Ch2', start: 128, stop: 290, gpioPin: 3),
];

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

/// A controller whose answers are scripted. [pixelAnswers] is consumed one per
/// applyPerPixel call (default: accept).
class _ScriptedRepo implements WledRepository, PerPixelWriter {
  _ScriptedRepo({this.jsonOk = true, List<bool>? pixelAnswers})
      : _pixelAnswers = [...?pixelAnswers];
  final bool jsonOk;
  final List<bool> _pixelAnswers;
  final json = <Map<String, dynamic>>[];
  final pixelSegments = <int>[];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    json.add(payload);
    return jsonOk;
  }

  @override
  Future<bool> applyPerPixel({
    int segmentId = 0,
    required List<PixelSpan> spans,
    int chunkSize = kDefaultPixelChunkSize,
  }) async {
    pixelSegments.add(segmentId);
    return _pixelAnswers.isEmpty ? true : _pixelAnswers.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A repository that cannot paint per-pixel at all.
class _JsonOnlyRepo implements WledRepository {
  final json = <Map<String, dynamic>>[];
  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    json.add(payload);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RooflineConfiguration _config(List<RooflineSegment> segs) => RooflineConfiguration(
      id: 'ctrl', controllerId: 'ctrl', name: 'Roofline', segments: segs,
      createdAt: DateTime(2026, 9, 19), updatedAt: DateTime(2026, 9, 19));

Future<WidgetRef> _pump(
  WidgetTester tester,
  WledRepository? repo, {
  RooflineConfiguration? config,
}) async {
  SharedPreferences.setMockInitialValues({});
  late WidgetRef ref;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      currentRooflineConfigProvider.overrideWith((ref) => Stream.value(config)),
      deviceChannelsProvider.overrideWithValue(_channels),
      effectiveChannelIdsProvider.overrideWithValue(const [0, 1]),
      pixelMapStalenessProvider.overrideWithValue(const {0: false, 1: false}),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    ],
    child: Consumer(builder: (c, r, _) {
      ref = r;
      r.watch(currentRooflineConfigProvider);
      return const SizedBox();
    }),
  ));
  await tester.pump();
  return ref;
}

const _spans = {
  0: [PixelSpan(start: 10, end: 10, color: [255, 0, 0, 0])],
  1: [PixelSpan(start: 0, end: 3, color: [0, 0, 255, 0])],
};

void main() {
  group('applyBaseAndSpans tells the truth', () {
    testWidgets('every write accepted → ok, label set', (tester) async {
      final repo = _ScriptedRepo();
      final ref = await _pump(tester, repo);
      final r = await applyBaseAndSpansDetailed(ref,
          baseRgbw: const [10, 10, 12, 0], spansByChannel: _spans, label: 'Mine');
      expect(r, SpineWriteResult.ok);
      expect(repo.pixelSegments, [0, 1]);
      expect(ref.read(activePresetLabelProvider), 'Mine');
    });

    testWidgets('base refused → baseFailed; nothing painted; NO label', (tester) async {
      final repo = _ScriptedRepo(jsonOk: false);
      final ref = await _pump(tester, repo);
      final r = await applyBaseAndSpansDetailed(ref,
          baseRgbw: const [10, 10, 12, 0], spansByChannel: _spans, label: 'BaseRefused');
      expect(r, SpineWriteResult.baseFailed);
      expect(repo.pixelSegments, isEmpty);
      // (Unique label per test: the label store outlives a ProviderScope.)
      expect(ref.read(activePresetLabelProvider), isNot('BaseRefused'));
      // The bool every existing caller consumes agrees.
      expect(await applyBaseAndSpans(ref,
          baseRgbw: const [10, 10, 12, 0], spansByChannel: _spans), isFalse);
    });

    testWidgets('a per-pixel paint refused → pixelsFailed; stops there', (tester) async {
      final repo = _ScriptedRepo(pixelAnswers: [false, true]);
      final ref = await _pump(tester, repo);
      final r = await applyBaseAndSpansDetailed(ref,
          baseRgbw: const [10, 10, 12, 0], spansByChannel: _spans, label: 'PixelsRefused');
      expect(r, SpineWriteResult.pixelsFailed);
      expect(repo.pixelSegments, [0], reason: 'channel 2 is not attempted');
      expect(r.userMessage, contains("painted pixels didn't"));
      expect(ref.read(activePresetLabelProvider), isNot('PixelsRefused'));
    });

    testWidgets('a repo that cannot paint: spans → pixelsFailed; none → ok', (tester) async {
      final ref = await _pump(tester, _JsonOnlyRepo());
      expect(
          await applyBaseAndSpansDetailed(ref,
              baseRgbw: const [0, 0, 0, 0], spansByChannel: _spans),
          SpineWriteResult.pixelsFailed,
          reason: 'used to skip the paint silently and return true');
      expect(
          await applyBaseAndSpansDetailed(ref,
              baseRgbw: const [0, 0, 0, 0], spansByChannel: const {}),
          SpineWriteResult.ok);
    });

    testWidgets('no controller → noDevice', (tester) async {
      final ref = await _pump(tester, null);
      expect(
          await applyBaseAndSpansDetailed(ref,
              baseRgbw: const [0, 0, 0, 0], spansByChannel: _spans),
          SpineWriteResult.noDevice);
    });

    testWidgets('AI studio path inherits: applyCustomDesignToLights → error', (tester) async {
      final ref = await _pump(tester, _ScriptedRepo(pixelAnswers: [false]));
      final design = CustomDesign(
        id: 'd', name: 'AI', ownerId: 'u',
        createdAt: DateTime(2026, 9, 19), updatedAt: DateTime(2026, 9, 19),
        channels: const [
          ChannelDesign(channelId: 0, channelName: 'Ch1', colorGroups: [
            LedColorGroup(startLed: 0, endLed: 9, color: [255, 0, 0, 0]),
          ]),
        ],
      );
      expect(await applyCustomDesignToLights(ref, design), DesignApplyResult.error);
    });
  });

  group('smart presets', () {
    // The production shape: every segment is a plain run (31 of 31, audit F5).
    final runOnly = _config(const [
      RooflineSegment(id: 'r1', name: 'Run 1', pixelCount: 128, channelIndex: 0),
      RooflineSegment(id: 'r2', name: 'Run 2', pixelCount: 162, channelIndex: 1),
    ]);

    testWidgets('run-only map → noFeatures and NOTHING is sent', (tester) async {
      final repo = _ScriptedRepo();
      final ref = await _pump(tester, repo, config: runOnly);
      for (final preset in kSmartPresets) {
        final r = await applySmartPreset(ref,
            preset: preset,
            baseRgbw: const [255, 147, 41, 200],
            accentRgbw: const [0, 229, 255, 0]);
        expect(r, SmartPresetApplyResult.noFeatures, reason: preset.name);
      }
      expect(repo.json, isEmpty, reason: 'used to paint a plain solid');
      expect(repo.pixelSegments, isEmpty);
    });

    testWidgets('features present but the controller refuses → error', (tester) async {
      final withCorner = _config(const [
        RooflineSegment(id: 'c', name: 'Corner', pixelCount: 2, channelIndex: 0,
            type: SegmentType.corner),
        RooflineSegment(id: 'r', name: 'Run', pixelCount: 126, startPixel: 2, channelIndex: 0),
      ]);
      final ref = await _pump(tester, _ScriptedRepo(pixelAnswers: [false]), config: withCorner);
      final r = await applySmartPreset(ref,
          preset: kSmartPresets[0],
          baseRgbw: const [255, 147, 41, 200],
          accentRgbw: const [0, 229, 255, 0]);
      expect(r, SmartPresetApplyResult.error);
    });
  });

  test('the demo / App-Review virtual device accepts per-pixel paints', () async {
    final WledRepository demo = DemoWledRepository();
    expect(demo, isA<PerPixelWriter>());
    expect(
        await (demo as PerPixelWriter).applyPerPixel(
            spans: const [PixelSpan(start: 0, end: 0, color: [1, 2, 3, 0])]),
        isTrue);
  });
}
