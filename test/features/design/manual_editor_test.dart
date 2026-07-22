// Design Studio Slice 4 — manual editor pure core + shared per-pixel apply
// spine + #86 apply. (UI is covered separately.)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/design_frame.dart';
import 'package:nexgen_command/features/design/manual_editor/edit_history.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/manual_editor/selection_logic.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

const _red = [255, 0, 0, 0];
const _green = [0, 255, 0, 0];

PixelDesignDocument _doc() => PixelDesignDocument.blank(
      baseColor: const [10, 10, 10, 0],
      channelLengths: const {0: 20, 1: 10},
    );

void main() {
  group('PixelDesignDocument', () {
    test('paint / colorAt / isPainted', () {
      final d = _doc().paint(0, [3, 4, 5], _red);
      expect(d.colorAt(0, 4), _red);
      expect(d.isPainted(0, 4), isTrue);
      expect(d.colorAt(0, 0), const [10, 10, 10, 0]); // base
      expect(d.isPainted(0, 0), isFalse);
      expect(d.paintedCount, 3);
    });

    test('out-of-range paint indices are ignored', () {
      final d = _doc().paint(0, [-1, 19, 20, 100], _red);
      expect(d.isPainted(0, 19), isTrue);
      expect(d.isPainted(0, 20), isFalse); // len is 20 → max index 19
      expect(d.paintedCount, 1);
    });

    test('toLedColorGroups (full coverage) merges base + painted runs', () {
      final d = _doc().paint(0, [3, 4, 5], _red);
      final groups = d.toLedColorGroups()[0]!;
      // base[0-2], red[3-5], base[6-19]
      expect(groups.length, 3);
      expect([groups[0].startLed, groups[0].endLed], [0, 2]);
      expect([groups[1].startLed, groups[1].endLed], [3, 5]);
      expect(groups[1].color, _red);
      expect([groups[2].startLed, groups[2].endLed], [6, 19]);
    });

    test('toLedColorGroups(onlyPainted) emits only non-base runs', () {
      final d = _doc().paint(0, [3, 4, 5], _red).paint(0, [10], _green);
      final groups = d.toLedColorGroups(onlyPainted: true)[0]!;
      expect(groups.map((g) => [g.startLed, g.endLed]), [[3, 5], [10, 10]]);
    });

    test('fromLedColorGroups round-trips the painted picture', () {
      final d = _doc().paint(0, [3, 4, 5], _red).paint(1, [0, 1], _green);
      final groups = d.toLedColorGroups(onlyPainted: true);
      final restored = PixelDesignDocument.fromLedColorGroups(
        baseColor: const [10, 10, 10, 0],
        channelLengths: const {0: 20, 1: 10},
        groupsByChannel: groups,
      );
      for (final ch in [0, 1]) {
        for (int i = 0; i < d.channelLength(ch); i++) {
          expect(restored.colorAt(ch, i), d.colorAt(ch, i), reason: 'ch$ch[$i]');
        }
      }
    });

    test('clearToBase / clearAll', () {
      final d = _doc().paint(0, [3, 4], _red);
      expect(d.clearToBase(0, [3]).isPainted(0, 3), isFalse);
      expect(d.clearAll().paintedCount, 0);
    });
  });

  group('EditHistory', () {
    test('push / undo / redo; redo tail truncated on new push', () {
      final a = _doc();
      final b = a.paint(0, [1], _red);
      final c = b.paint(0, [2], _green);
      final h = EditHistory(a);
      h.push(b);
      h.push(c);
      expect(h.current, c);
      expect(h.undo(), b);
      expect(h.undo(), a);
      expect(h.canUndo, isFalse);
      expect(h.redo(), b);
      // New push from b truncates the redo (c) tail.
      final d = b.paint(0, [3], _red);
      h.push(d);
      expect(h.current, d);
      expect(h.canRedo, isFalse);
    });

    test('depth is capped at maxDepth', () {
      final h = EditHistory(_doc(), maxDepth: 3);
      for (int i = 0; i < 10; i++) {
        h.push(_doc().paint(0, [i % 20], _red));
      }
      expect(h.depth, 3);
    });
  });

  group('selection_logic', () {
    test('everyNthInRange (candy-cane)', () {
      expect(everyNthInRange(start: 0, end: 10, step: 3), [0, 3, 6, 9]);
      expect(everyNthInRange(start: 2, end: 10, step: 2, offset: 1), [3, 5, 7, 9]);
      expect(everyNthInRange(start: 0, end: 5, step: 0), [0, 1, 2, 3, 4, 5]); // step<1→1
    });

    test('featureIndices by type', () {
      final segs = [
        const RooflineSegment(id: 'a', name: 'C', startPixel: 0, pixelCount: 2, type: SegmentType.corner, channelIndex: 0),
        const RooflineSegment(id: 'b', name: 'R', startPixel: 2, pixelCount: 5, type: SegmentType.run, channelIndex: 0),
        const RooflineSegment(id: 'c', name: 'P', startPixel: 7, pixelCount: 3, type: SegmentType.peak, channelIndex: 0),
      ];
      expect(featureIndices(segs, FeatureFilter.allCorners), {0, 1});
      expect(featureIndices(segs, FeatureFilter.allPeaks), {7, 8, 9});
      expect(featureIndices(segs, FeatureFilter.allRuns), {2, 3, 4, 5, 6});
      expect(segmentIndices(segs[2]), {7, 8, 9});
    });

    test('anchorIndices are channel-local + zone-expanded', () {
      final segs = [
        const RooflineSegment(
            id: 'a', name: 'R', startPixel: 10, pixelCount: 20,
            type: SegmentType.run, anchorPixels: [0, 18], anchorLedCount: 2,
            channelIndex: 0),
      ];
      // local anchors 0,18 → global-in-channel 10,28; zone 2 → {10,11, 28,29}
      expect(anchorIndices(segs), {10, 11, 28, 29});
    });
  });

  group('shared apply spine (pure)', () {
    test('ledColorGroupsToSpans normalizes RGB→RGBW, preserves RGBW', () {
      final spans = ledColorGroupsToSpans([
        const LedColorGroup(startLed: 0, endLed: 3, color: [0, 255, 0]), // RGB
        const LedColorGroup(startLed: 4, endLed: 4, color: [1, 2, 3, 200]), // RGBW
      ]);
      expect(spans[0].color, [0, 255, 0, 0]); // W=0 appended
      expect(spans[1].color, [1, 2, 3, 200]); // preserved
    });

    test('customDesignToSpans keys by channelId, skips excluded/empty', () {
      final design = _customDesign();
      final spans = customDesignToSpans(design);
      expect(spans.keys.toSet(), {0}); // ch1 excluded
      expect(spans[0]!.length, 2);
      expect([spans[0]!.first.start, spans[0]!.first.end], [0, 5]);
    });
  });

  group('design_frame', () {
    test('frameFromDocument yields per-channel per-LED colors', () {
      final d = _doc().paint(0, [0], _red);
      final frame = frameFromDocument(d);
      expect(frame[0]!.length, 20);
      expect(frame[1]!.length, 10);
    });

    test('frameFromGlobalGroups maps global→channel via bus offsets', () {
      final frame = frameFromGlobalGroups(
        groups: const [LedColorGroup(startLed: 130, endLed: 132, color: [0, 0, 255])],
        channels: const [
          DeviceChannel(id: 0, name: 'C1', start: 0, stop: 128, gpioPin: 2),
          DeviceChannel(id: 1, name: 'C2', start: 128, stop: 188, gpioPin: 14),
        ],
      );
      // Global 130 → channel 1 local 2.
      expect(frame[1]!.length, 60);
      expect(frame[1]![2] != Colors.black, isTrue); // painted blue-ish
      expect(frame[1]![0], Colors.black); // unpainted
    });
  });

  group('applyCustomDesignToLights (#86 shared path)', () {
    testWidgets('AI-shaped design applies via base + i spans + label',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = _RecordingRepo();
      late WidgetRef ref;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          wledRepositoryProvider.overrideWith((ref) => repo),
          deviceChannelsProvider.overrideWithValue(const [
            DeviceChannel(id: 0, name: 'C1', start: 0, stop: 128, gpioPin: 2),
          ]),
          effectiveChannelIdsProvider.overrideWithValue(const [0]),
          wledStateProvider.overrideWith(() => _FakeWledNotifier()),
        ],
        child: Consumer(builder: (c, r, _) {
          ref = r;
          return const SizedBox();
        }),
      ));

      // An AI-saved design carries composedPattern AND channels — apply uses
      // the channels (per-channel colorGroups), same as a manual design.
      final design = _customDesign()
          .copyWith(composedPattern: const {'sourceIntent': 'ai'});
      final result = await applyCustomDesignToLights(ref, design);

      expect(result, DesignApplyResult.applied);
      expect(repo.applyJsonCalls.length, 1); // base
      expect(repo.perPixelCalls.length, 1); // accents on ch0
      expect(repo.perPixelCalls.first.segmentId, 0);
      expect(repo.perPixelCalls.first.spans.length, 2);
    });

    testWidgets('empty design → noMap', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repo = _RecordingRepo();
      late WidgetRef ref;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          wledRepositoryProvider.overrideWith((ref) => repo),
          deviceChannelsProvider.overrideWithValue(const []),
          effectiveChannelIdsProvider.overrideWithValue(const [0]),
          wledStateProvider.overrideWith(() => _FakeWledNotifier()),
        ],
        child: Consumer(builder: (c, r, _) {
          ref = r;
          return const SizedBox();
        }),
      ));
      final empty = CustomDesign(
        id: '', name: 'Empty', createdAt: DateTime(2026), updatedAt: DateTime(2026),
        ownerId: 'u', channels: const [],
      );
      expect(await applyCustomDesignToLights(ref, empty), DesignApplyResult.noMap);
      expect(repo.applyJsonCalls, isEmpty);
    });
  });
}

CustomDesign _customDesign() => CustomDesign(
      id: 'd1',
      name: 'Test Design',
      createdAt: DateTime(2026, 7, 2),
      updatedAt: DateTime(2026, 7, 2),
      ownerId: 'u',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'C1',
          included: true,
          ledCount: 128,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 5, color: [255, 0, 0, 0]),
            LedColorGroup(startLed: 10, endLed: 12, color: [0, 255, 0]),
          ],
        ),
        ChannelDesign(
          channelId: 1,
          channelName: 'C2',
          included: false, // excluded → skipped by customDesignToSpans
          ledCount: 60,
          colorGroups: [LedColorGroup(startLed: 0, endLed: 3, color: [0, 0, 255])],
        ),
      ],
    );

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
          {bool? on, int? brightness, int? speed, Color? color, int? white, bool? forceRgbwZeroWhite}) async =>
      true;
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => true;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => true;
  @override
  Future<bool> configureSyncReceiver() async => true;
  @override
  Future<bool> configureSyncSender({List<String> targets = const [], int ddpPort = 4048}) async => true;
}
