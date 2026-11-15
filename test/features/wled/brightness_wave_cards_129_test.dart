// Build 129 follow-up — the two Wave presets become catalog cards. Written
// FIRST, failing at 3c0fcaa.
//
// The owner's words: "If a user wants it to gradiently change over 18 pixels
// instead of 9 it shouldn't be a problem", and "In whites, this should be an
// easily accessible design as was initially the goal." The look: light 1 at
// 100 %, then 80, 60, 40, 60, 80, repeating, in white.
//
// At 3c0fcaa Wave · 6 lights and Wave · 18 lights exist only as presets inside
// every brightness card's Adjust sheet. These tests ask for them to be cards
// inside the existing Brightness Patterns folder (Explore › Architectural
// Downlighting › each Kelvin style), built exactly like the six shipped
// presets there: a palette node that opens the same tuner, applies with the
// same Apply, and whose generated card shows the same Adjust link.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/wled/brightness_tile.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_grid_widgets.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/widgets/brightness_tile_controls.dart';
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

/// The look, in the owner's words.
const List<double> kWave6 = [100, 80, 60, 40, 60, 80];

/// The nine Kelvin styles, as the catalog spells them.
const List<String> kKelvinStyles = [
  'k2000', 'k2700', 'k3000', 'k3500', 'k4000', 'k4500', 'k5000', 'k5500', 'k6500', //
];

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

Future<void> _pump(WidgetTester tester, ProviderContainer c, Widget body,
    {Size size = const Size(900, 2400)}) async {
  tester.view.physicalSize = size;
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

Map<String, dynamic> _deepCopy(Map<String, dynamic> m) =>
    Map<String, dynamic>.from(_copy(m) as Map);
Object? _copy(Object? v) {
  if (v is Map) return {for (final e in v.entries) e.key: _copy(e.value)};
  if (v is List) return [for (final x in v) _copy(x)];
  return v;
}

/// Everything [repo] wrote, in order, through the wire chokepoint, onto the
/// simulated home strips.
Map<int, List<List<int>>> _strips(RecordingWledRepository repo) {
  expect(repo.applied, isNotEmpty, reason: 'nothing was written');
  Map<int, List<List<int>>>? strips;
  for (final body in repo.applied) {
    final wire = normalizeWledPayload(_deepCopy(body));
    strips = renderPayloadOnto(wire, kHomeLengths, into: strips);
  }
  return strips!;
}

List<double> _intended(List<double> steps, int count) =>
    [for (var i = 0; i < count; i++) steps[i % steps.length]];

void _expectWithin(List<double> got, List<double> want, String what) {
  final n = want.length < got.length ? want.length : got.length;
  final misses = <String>[];
  for (var i = 0; i < n; i++) {
    if ((got[i] - want[i]).abs() > kTolerancePp) {
      misses.add('px $i: ${got[i].toStringAsFixed(1)} % (want ${want[i].toStringAsFixed(1)})');
    }
  }
  expect(misses, isEmpty,
      reason: '$what — ${misses.length} of $n pixels off by more than $kTolerancePp pp: ${misses.take(6).join('; ')}');
}

Future<PatternItem> _cardOf(PatternRepository repo, LibraryNode node) async {
  final items = await repo.generatePatternsForNode(node);
  expect(items, hasLength(1), reason: '${node.id}: ${items.map((p) => p.id).join(', ')}');
  return items.single;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final repo = PatternRepository();
  final wave6 = brightnessPatternPresetById('wave6')!;
  final wave18 = brightnessPatternPresetById('wave18')!;

  group('the Brightness Patterns folder of every Kelvin style', () {
    test('holds eight cards: Wave 6 and Wave 18 first, then the six shipped presets', () async {
      for (final k in kKelvinStyles) {
        final folder = 'arch_${k}_gradients';
        final kids = await repo.getChildNodes(folder);
        expect(kids.map((n) => n.id).toList(), [
          '${folder}_wave6',
          '${folder}_wave18',
          '${folder}_gentle',
          '${folder}_medium',
          '${folder}_deep',
          '${folder}_stair',
          '${folder}_duo',
          '${folder}_pulse',
        ], reason: folder);
      }
    });

    test('each Wave node is built like the six: a palette node carrying its tile and the style\'s white', () async {
      for (final k in kKelvinStyles) {
        final style = PatternRepository.archWhiteStyles.firstWhere((s) => s.id == k);
        final folder = 'arch_${k}_gradients';
        final shipped = (await repo.getNodeById('${folder}_gentle'))!;
        for (final preset in [wave6, wave18]) {
          final node = await repo.getNodeById('${folder}_${preset.id}');
          expect(node, isNotNull, reason: '${folder}_${preset.id}');
          expect(node!.isPalette, isTrue, reason: node.id);
          expect(node.parentId, folder, reason: node.id);
          expect(node.name, preset.name, reason: node.id);
          final meta = node.metadata!;
          expect(meta['type'], shipped.metadata!['type'], reason: node.id);
          expect(meta['presetId'], preset.id, reason: node.id);
          expect(BrightnessTile.fromJson(meta['brightnessTile']), preset.tile, reason: node.id);
          expect(meta['baseColorValue'], style.colors[0].toARGB32(), reason: node.id);
          expect(meta['suggestedEffects'], shipped.metadata!['suggestedEffects'], reason: node.id);
          expect(node.themeColors, isNotNull, reason: node.id);
          expect(node.themeColors, isNotEmpty, reason: node.id);
        }
      }
    });

    test('each Kelvin style still has its 18 direct children (the folder counts once)', () async {
      for (final k in kKelvinStyles) {
        final direct = await repo.getChildNodes('arch_$k');
        expect(direct.length, 18, reason: 'arch_$k');
        expect(direct.where((n) => n.id == 'arch_${k}_gradients').length, 1, reason: 'arch_$k');
      }
    });

    test('a Wave node generates ONE still card carrying its tile (the same shape as the six)', () async {
      for (final preset in [wave6, wave18]) {
        final node = (await repo.getNodeById('arch_k3000_gradients_${preset.id}'))!;
        final card = await _cardOf(repo, node);
        expect(card.id, endsWith('_static'));
        expect(card.name, preset.name);
        expect(BrightnessTile.fromJson(card.wledPayload[kBrightnessTilePayloadKey]), preset.tile);
        final seg = (card.wledPayload['seg'] as List).first as Map;
        expect(seg['fx'], 0, reason: 'the base the spine writes is Solid');
        expect((card.wledPayload['_gradientMeta'] as Map)['presetId'], preset.id);
      }
    });
  });

  group('Wave 6 in white, from the catalog node', () {
    testWidgets('the card applies in one tap: light 1 at 100 %, then 80, 60, 40, 60, 80, '
        'repeating, on both channels, in every Kelvin white', (tester) async {
      for (final k in kKelvinStyles) {
        final node = (await repo.getNodeById('arch_${k}_gradients_wave6'))!;
        final card = await _cardOf(repo, node);
        final wledRepo = RecordingWledRepository();
        final c = _container(wledRepo);
        await _pump(tester, c,
            SizedBox(width: 200, height: 220, child: PatternCard(pattern: card)));
        await tester.tap(find.text(card.name));
        await _settle(tester);
        final strips = _strips(wledRepo);
        for (final ch in kHomeLengths.keys) {
          final levels = lightLevels(strips[ch]!);
          _expectWithin(levels, _intended(kWave6, levels.length), '$k / channel $ch');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('Wave 18 from its card: 100 down to 40 over nine lights and back, on both channels',
        (tester) async {
      final node = (await repo.getNodeById('arch_k3000_gradients_wave18'))!;
      final card = await _cardOf(repo, node);
      final wledRepo = RecordingWledRepository();
      final c = _container(wledRepo);
      await _pump(tester, c,
          SizedBox(width: 200, height: 220, child: PatternCard(pattern: card)));
      await tester.tap(find.text(card.name));
      await _settle(tester);
      final strips = _strips(wledRepo);
      final want = wave18.tile.levels.map((l) => l.toDouble()).toList();
      expect(want, hasLength(18));
      expect(want.first, 100);
      expect(want[9], 40);
      for (final ch in kHomeLengths.keys) {
        final levels = lightLevels(strips[ch]!);
        _expectWithin(levels, _intended(want, levels.length), 'channel $ch');
      }
    });

    testWidgets('the Wave 6 card shows the Adjust link, like every other brightness card',
        (tester) async {
      final node = (await repo.getNodeById('arch_k3000_gradients_wave6'))!;
      final card = await _cardOf(repo, node);
      final c = _container(RecordingWledRepository());
      await _pump(tester, c,
          SizedBox(width: 200, height: 220, child: PatternCard(pattern: card)));
      expect(find.byKey(const ValueKey('brightness-card-adjust')), findsOneWidget);
    });

    testWidgets('opening the Wave 6 node from Explore shows the brightness controls, and Apply '
        'paints the wave on both channels', (tester) async {
      final node = (await repo.getNodeById('arch_k3000_gradients_wave6'))!;
      final wledRepo = RecordingWledRepository();
      final c = _container(wledRepo);
      await _pump(tester, c, ColorwayEffectSelectorPage(paletteNode: node),
          size: const Size(1200, 3000));
      await _settle(tester);
      expect(find.byType(BrightnessTileControls), findsOneWidget,
          reason: 'the Adjust controls every brightness node opens on');
      expect(wledRepo.applied, isEmpty, reason: 'browsing does not touch the lights');
      await tester.tap(find.byKey(const ValueKey('apply-design')));
      await _settle(tester);
      final strips = _strips(wledRepo);
      for (final ch in kHomeLengths.keys) {
        final levels = lightLevels(strips[ch]!);
        _expectWithin(levels, _intended(kWave6, levels.length), 'channel $ch');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    });
  });

  group('how far Wave 6 in white is from the Explore home screen', () {
    test('four taps into the tree (root, Kelvin style, folder, Wave 6), then Apply = five', () async {
      final node = await repo.getNodeById('arch_k3000_gradients_wave6');
      expect(node, isNotNull);
      final chain = <String>[];
      LibraryNode? cur = node;
      while (cur != null) {
        chain.insert(0, cur.id);
        cur = cur.parentId == null ? null : await repo.getNodeById(cur.parentId!);
      }
      expect(chain, [
        LibraryCategoryIds.architectural, // 1: Explore home → Architectural Downlighting
        'arch_k3000', // 2: → 3000K
        'arch_k3000_gradients', // 3: → Brightness Patterns
        'arch_k3000_gradients_wave6', // 4: → Wave · 6 lights (opens the tuner)
      ]);
      // 5: Apply (the tuner's primary action; browsing does not write).
      expect(chain.length + 1, 5);
    });
  });
}
