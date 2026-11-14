// Build 129 — brightness patterns. Written FIRST, failing at bd29c38.
//
// Explore › Architectural Downlighting › <Kelvin> › Brightness Gradients has
// shipped since 9c48001 (2026-03-17). Its cards preview a per-bulb cycle of
// brightness steps, and send fx 83 Solid Pattern with `sx 0`; the chokepoint
// fills `ix 128` and `pal 5`, so the controller shows ONE lit pixel and then
// 129 pixels of the second step (bench 2026-11-14, both firmwares). The
// step values ignore the controller's gamma 2.8, the fourth step of Soft
// Pulse never leaves the phone, and fx 65 Palette renders one still colour
// because the chokepoint's `c1 128` turns its gradient sideways.
//
// These tests look at the STRIP a card produces (test/helpers/
// wled_strip_simulator.dart, anchored to the bench frames) and at the dot
// preview the card draws, and ask for them to agree.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_grid_widgets.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';
import '../../helpers/wled_strip_simulator.dart';

/// The 3-percentage-point rule from the brief.
const double kTolerancePp = 3.0;

/// What the Brightness Gradients cards PROMISE: step [k] of the preset, as a
/// light level in %, on every bulb whose index is `(i ~/ bandWidth) %
/// steps.length` — the picture the card's dot preview has always drawn.
List<double> intendedBulbLevels(List<double> steps, int bandWidth, int count) =>
    [for (var i = 0; i < count; i++) steps[(i ~/ bandWidth) % steps.length] * 100];

/// Channel lengths of the harness home (two buses of 30).
final Map<int, int> kHomeLengths = {
  for (final c in kHomeTwoChannels) c.id: c.stop - c.start,
};

ProviderContainer _container(RecordingWledRepository repo) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
    participatingChannelIdsProvider.overrideWithValue(null),
    currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
    demoModeProvider.overrideWith((ref) => false),
    userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
  ]);
  addTearDown(c.dispose);
  c.read(selectedChannelIdsProvider.notifier).state = null;
  return c;
}

Future<void> _pump(WidgetTester tester, ProviderContainer c, Widget body) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await c.read(wledConnectivityStatusProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(home: Scaffold(body: body)),
  ));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps the card and returns what the two home channels show afterwards:
/// every body the card wrote, in order, through the wire chokepoint, onto
/// the simulated strips.
Future<Map<int, List<List<int>>>> _stripAfterTap(
    WidgetTester tester, PatternItem card) async {
  final repo = RecordingWledRepository();
  final c = _container(repo);
  await _pump(tester, c,
      SizedBox(width: 200, height: 220, child: PatternCard(pattern: card)));
  await tester.tap(find.text(card.name));
  await _settle(tester);
  expect(repo.applied, isNotEmpty, reason: 'the card wrote nothing');
  Map<int, List<List<int>>>? strips;
  for (final body in repo.applied) {
    final wire = normalizeWledPayload(_deepCopy(body));
    strips = renderPayloadOnto(wire, kHomeLengths, into: strips);
  }
  return strips!;
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> m) =>
    Map<String, dynamic>.from(_copy(m) as Map);
Object? _copy(Object? v) {
  if (v is Map) return {for (final e in v.entries) e.key: _copy(e.value)};
  if (v is List) return [for (final x in v) _copy(x)];
  return v;
}

/// Every catalog node that carries brightness preset [preset]: the card in
/// each Kelvin folder's gradients folder (the six shipped presets) and the
/// card in the Brightness Patterns root (every preset, warm white).
Future<List<LibraryNode>> _nodesForPreset(
    PatternRepository repo, String preset) async {
  final out = <LibraryNode>[];
  for (final style in ['k2000', 'k2700', 'k3000', 'k3500', 'k4000', 'k4500', 'k5000', 'k5500', 'k6500']) {
    final n = await repo.getNodeById('arch_${style}_gradients_$preset');
    if (n != null) out.add(n);
  }
  final rootNode = await repo.getNodeById('bright_$preset');
  if (rootNode != null) out.add(rootNode);
  return out;
}

/// The static card of one gradient preset under one Kelvin style.
Future<PatternItem> _staticCard(
    PatternRepository repo, String style, String preset) async {
  final node = await repo.getNodeById('arch_${style}_gradients_$preset');
  expect(node, isNotNull, reason: 'catalog node arch_${style}_gradients_$preset');
  return _cardOf(repo, node!);
}

Future<PatternItem> _cardOf(PatternRepository repo, LibraryNode node) async {
  final items = await repo.generatePatternsForNode(node);
  return items.firstWhere((p) => p.id.endsWith('_static'));
}

List<double> _steps(String preset) => PatternRepository.brightnessGradientPresets
    .firstWhere((p) => p.id == preset)
    .steps
    .map((s) => s.toDouble())
    .toList();

void _expectWithin(List<double> got, List<double> want, String what) {
  final n = want.length < got.length ? want.length : got.length;
  final misses = <String>[];
  for (var i = 0; i < n; i++) {
    if ((got[i] - want[i]).abs() > kTolerancePp) {
      misses.add('px $i: ${got[i].toStringAsFixed(1)} % (want ${want[i].toStringAsFixed(1)})');
    }
  }
  expect(misses, isEmpty, reason: '$what — ${misses.length} of $n pixels off by more than $kTolerancePp pp: ${misses.take(6).join('; ')}');
}

/// Records the colour of every circle a CustomPainter draws, in order.
class _RecordingCanvas implements ui.Canvas {
  final List<Color> circles = [];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #drawCircle) {
      circles.add((invocation.positionalArguments[2] as Paint).color);
    }
    return null;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final repo = PatternRepository();

  group('the strip simulator reproduces the 2026-11-14 bench frames', () {
    const sim = WledStripSimulator();
    test('fx 83 sx 0 ix 128 pal 5 (the shipped gradient wire shape)', () {
      final px = sim.render({
        'fx': 83, 'sx': 0, 'ix': 128, 'pal': 5, 'grp': 1, 'spc': 0,
        'col': [[255, 255, 255, 0], [217, 217, 217, 0], [179, 179, 179, 0]],
      }, 100);
      // Spare seg 0: [255, 162, 162, 162, 162, 162 … 162]
      expect(px.map((p) => p[0]).toList(), [255, ...List.filled(99, 162)]);
    });
    test('fx 65 c1 128 (the app default) is one still colour per segment', () {
      // Spare: seg 0 lit 255, seg 1 lit 103, seg 2 lit 255.
      final seg = {
        'fx': 65, 'pal': 4, 'c1': 128, 'o1': false, 'o2': false, 'o3': true,
        'sx': 0, 'ix': 128,
        'col': [[255, 255, 255, 0], [184, 184, 184, 0], [255, 255, 255, 0]],
      };
      for (final (i, want) in [(0, 255), (1, 103), (2, 255)]) {
        final px = sim.render(seg, 100, segmentIndex: i, segmentCount: 3);
        final reds = px.map((p) => p[0]).toSet();
        expect(reds, hasLength(1), reason: 'seg $i not uniform');
        expect(reds.single, closeTo(want, 2), reason: 'seg $i');
      }
    });
    test('fx 65 c1 0 ix 128: one V per segment', () {
      final px = sim.render({
        'fx': 65, 'pal': 4, 'c1': 0, 'o1': false, 'o2': false, 'o3': true,
        'sx': 0, 'ix': 128,
        'col': [[255, 255, 255, 0], [184, 184, 184, 0], [255, 255, 255, 0]],
      }, 100, segmentCount: 3);
      // Spare seg 0 px 0/25/50/75/99 = 255/178/102/191/255
      for (final (i, want) in [(0, 255), (25, 178), (50, 102), (75, 191), (99, 255)]) {
        expect(px[i][0], closeTo(want, 3), reason: 'px $i');
      }
    });
    test('fx 65 c1 0 ix 200 (an 18-pixel V): first two cycles within 8 lit units', () {
      const bench = [255, 241, 222, 209, 188, 175, 157, 136, 123, 104, 113, 137, 151, 173, 197, 212, 234, 249, //
        255, 245, 225, 205, 192, 173, 160, 140, 126, 107, 117, 133, 154, 170, 193, 208, 230, 253];
      final px = sim.render({
        'fx': 65, 'pal': 4, 'c1': 0, 'o1': false, 'o2': false, 'o3': true,
        'sx': 0, 'ix': 200,
        'col': [[255, 255, 255, 0], [184, 184, 184, 0], [255, 255, 255, 0]],
      }, 100, segmentCount: 3);
      for (var i = 0; i < bench.length; i++) {
        expect(px[i][0], closeTo(bench[i], 8), reason: 'px $i');
      }
    });
    test('per-pixel i ranges are gamma-corrected like the firmware', () {
      final px = sim.render({'fx': 0, 'i': [0, 3, [184, 184, 184, 0], 5, [255, 0, 0, 0]]}, 8);
      expect(px[0], [102, 102, 102, 0]);
      expect(px[2], [102, 102, 102, 0]);
      expect(px[3], [0, 0, 0, 0], reason: 'range stop is exclusive');
      expect(px[5], [255, 0, 0, 0]);
      expect(px[7], [0, 0, 0, 0], reason: 'a frozen segment starts black');
    });
  });

  group('shipped Brightness Gradients cards — the strip shows the per-bulb cycle the card promises', () {
    for (final preset in PatternRepository.brightnessGradientPresets) {
      testWidgets('${preset.name} (${preset.id}) on every card that carries it', (tester) async {
        final nodes = await _nodesForPreset(repo, preset.id);
        expect(nodes, isNotEmpty, reason: 'no catalog card carries ${preset.id}');
        for (final node in nodes) {
          final card = await _cardOf(repo, node);
          final strips = await _stripAfterTap(tester, card);
          for (final ch in kHomeLengths.keys) {
            final levels = lightLevels(strips[ch]!);
            _expectWithin(levels, intendedBulbLevels(_steps(preset.id), 1, levels.length),
                '${preset.name} / ${node.id} / channel $ch');
          }
        }
      });
    }

    testWidgets('Soft Pulse: the fourth step (60 %) reaches the strip', (tester) async {
      final card = await _staticCard(repo, 'k2700', 'pulse');
      final strips = await _stripAfterTap(tester, card);
      final levels = lightLevels(strips[0]!);
      // steps 1.0, 0.8, 1.0, 0.6 → bulb 3 of every tile is the 60 % step
      expect(levels[3], closeTo(60, kTolerancePp), reason: 'bulb 3');
      expect(levels[7], closeTo(60, kTolerancePp), reason: 'bulb 7');
    });

    testWidgets('gamma: Deep Fade\'s 30 % step LIGHTS at 30 %, not at 3.4 %', (tester) async {
      final card = await _staticCard(repo, 'k2700', 'deep');
      final strips = await _stripAfterTap(tester, card);
      final levels = lightLevels(strips[0]!);
      final dimmest = levels.take(6).reduce((a, b) => a < b ? a : b);
      expect(dimmest, closeTo(30, kTolerancePp),
          reason: 'the dimmest bulb of the first two tiles lights at ${dimmest.toStringAsFixed(1)} %');
    });

    testWidgets('no gradient card goes out as fx 83 with the positional pal 5', (tester) async {
      final card = await _staticCard(repo, 'k2700', 'gentle');
      final wireRepo = RecordingWledRepository();
      final c = _container(wireRepo);
      await _pump(tester, c, SizedBox(width: 200, height: 220, child: PatternCard(pattern: card)));
      await tester.tap(find.text(card.name));
      await _settle(tester);
      for (final body in wireRepo.applied) {
        final wire = normalizeWledPayload(_deepCopy(body));
        for (final seg in (wire['seg'] as List).whereType<Map>()) {
          expect(seg['fx'] == 83 && seg['pal'] == 5, isFalse,
              reason: 'fx 83 + pal 5 lays the steps out positionally: $seg');
        }
      }
    });

    test('a brightness card is ONE still picture — no Breathing variant, because a '
        'per-pixel frame freezes the segment and no effect can run over it', () async {
      final node = await repo.getNodeById('arch_k2700_gradients_medium');
      final items = await repo.generatePatternsForNode(node!);
      expect(items, hasLength(1), reason: items.map((p) => p.id).join(', '));
      final seg = (items.single.wledPayload['seg'] as List).first as Map;
      expect(seg['fx'], 0, reason: 'the base the spine writes is Solid, not an effect');
    });
  });

  group('the dot preview draws what the strip shows', () {
    testWidgets('Gentle Fade card: preview bulbs vs simulated strip, first 12 bulbs', (tester) async {
      final card = await _staticCard(repo, 'k2700', 'gentle');
      final strips = await _stripAfterTap(tester, card);
      final stripLevels = lightLevels(strips[0]!);

      final paintFinder = find.byWidgetPredicate((w) =>
          w is CustomPaint && w.painter.runtimeType.toString().contains('GradientDot'));
      expect(paintFinder, findsOneWidget, reason: 'the gradient card draws a dot preview');
      final painter = tester.widget<CustomPaint>(paintFinder).painter!;
      final canvas = _RecordingCanvas();
      painter.paint(canvas, const Size(12 * 8.0, 8));
      expect(canvas.circles.length, greaterThanOrEqualTo(12));
      int red(Color c) => (c.r * 255.0).round();
      final peak = canvas.circles.map(red).reduce((a, b) => a > b ? a : b);
      final previewLevels = [for (final c in canvas.circles.take(12)) red(c) / peak * 100];
      _expectWithin(stripLevels.take(12).toList(), previewLevels, 'preview vs strip');
    });
  });

  group('chokepoint — fx 65 Palette', () {
    test('completeEffectSegment states c1 0 on fx 65 (the effect\'s own default; 128 turns it sideways)', () {
      final seg = completeEffectSegment(
        {'fx': 65, 'col': [[255, 0, 0, 0], [255, 168, 0, 0]]},
        paletteFor: WledEffectsCatalog.paletteForEffect,
      );
      expect(seg['c1'], 0);
      expect(seg['o1'], false, reason: 'still, not animated');
      expect(seg['o2'], false);
    });

    test('table: every effect in the pool keeps its option fill, fx 65 alone moves c1 to 0', () {
      final mismatches = <String>[];
      for (var id = 0; id < kWledKnownEffectIdCeiling; id++) {
        final seg = completeEffectSegment(
          {'fx': id, 'col': [[255, 0, 0, 0]]},
          paletteFor: WledEffectsCatalog.paletteForEffect,
        );
        final reads = optionKeysReadBy(id).toSet();
        final expected = <String, Object?>{
          'c1': reads.contains('c1') ? (id == 65 ? 0 : kSegDefaultC1) : null,
          'c2': reads.contains('c2') ? kSegDefaultC2 : null,
          'c3': reads.contains('c3') ? kSegDefaultC3 : null,
          'o1': reads.contains('o1') ? kSegDefaultOption : null,
          'o2': reads.contains('o2') ? kSegDefaultOption : null,
          'o3': reads.contains('o3') ? kSegDefaultOption : null,
        };
        for (final e in expected.entries) {
          if (seg[e.key] != e.value) {
            mismatches.add('fx $id ${e.key}: ${seg[e.key]} (want ${e.value})');
          }
        }
      }
      expect(mismatches, isEmpty, reason: mismatches.join('; '));
    });
  });
}
