// +110 E1 — Explore apply paths, driven from their real controls.
//
// Rows 1 (Explore cards, Recent), 19, 20, 21, 80 (adjustment sheet).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/wled/pattern_library_browser.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_grid_widgets.dart';
import 'package:nexgen_command/features/wled/pattern_theme_selection.dart';
import 'package:nexgen_command/features/wled/pattern_tweak_payload.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

class _RecordingUsage extends UsageLoggerNotifier {
  _RecordingUsage(this.log);
  final List<Map<String, dynamic>> log;

  @override
  Future<void> logUsage({
    required String source,
    String? patternName,
    List<String>? colorNames,
    int? effectId,
    String? effectName,
    int? paletteId,
    int? brightness,
    int? speed,
    int? intensity,
    Map<String, dynamic>? wledPayload,
  }) async {
    log.add({'source': source, 'name': patternName, 'wled': wledPayload});
  }
}

ProviderContainer _container(
  RecordingWledRepository repo, {
  List<DeviceChannel> channels = kHomeTwoChannels,
  Set<int>? selected,
  bool noController = false,
  List<Override> extra = const [],
}) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => noController ? null : repo),
    wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    deviceChannelsProvider.overrideWithValue(channels),
    participatingChannelIdsProvider.overrideWithValue(null),
    currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
    demoModeProvider.overrideWith((ref) => false),
    userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
    ...extra,
  ]);
  addTearDown(c.dispose);
  c.read(selectedChannelIdsProvider.notifier).state = selected;
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

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

PatternUsageEvent _event(String name, Object? wled) => PatternUsageEvent(
      id: name,
      createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      source: 'explore',
      patternName: name,
      effectId: 28,
      speed: 60,
      intensity: 128,
      wledPayload: wled is Map<String, dynamic> ? wled : null,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('row 19 — Recent Patterns', () {
    test('the stored `wled` field decodes as the usage model does', () {
      expect(decodeUsageWledPayload('{"on":true,"seg":[{"fx":1}]}'),
          {'on': true, 'seg': [{'fx': 1}]});
      expect(decodeUsageWledPayload({'on': true}), {'on': true});
      expect(decodeUsageWledPayload('not json'), isNull,
          reason: 'a bad payload is absent, not a hidden section');
      expect(decodeUsageWledPayload(null), isNull);
    });

    test('colours come from the DESIGN segment, not a leading "off" marker',
        () async {
      final c = ProviderContainer(overrides: [
        recentUsageProvider.overrideWith((ref, limit) => Stream.value([
              _event('Blue Garage', {
                'seg': [
                  {'id': 0, 'on': false},
                  {
                    'id': 1,
                    'fx': 28,
                    'col': [
                      [0, 0, 255, 0]
                    ]
                  },
                ],
              }),
            ])),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(recentPatternsProvider, (_, __) {});
      addTearDown(sub.close);
      await c.read(recentUsageProvider(5).future);
      final patterns = c.read(recentPatternsProvider).value!;
      expect(patterns.single.colors.first, const Color(0xFF0000FF));
    });

    testWidgets('tapping a Recent card applies it through the gated apply — '
        'no forced brightness, Home preview + Now Playing, and a usage event',
        (tester) async {
      final repo = RecordingWledRepository();
      final log = <Map<String, dynamic>>[];
      final c = _container(repo, extra: [
        recentUsageProvider.overrideWith(
            (ref, limit) => Stream.value([_event('Evening Glow', null)])),
        usageLoggerNotifierProvider.overrideWith(() => _RecordingUsage(log)),
      ]);
      await _pump(tester, c, const RecentPatternsSection());
      await _settle(tester);

      await tester.tap(find.text('Evening Glow'));
      await _settle(tester);

      final sent = repo.applied.single;
      expect(sent.containsKey('bri'), isFalse);
      expect(c.read(activePresetLabelProvider), isNotNull);
      expect(log.single['source'], 'recent');
      expect(log.single['name'], 'Evening Glow');
    });

    testWidgets('row 1: with the channel gate closed, a Recent tap says why',
        (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, channels: const [], extra: [
        recentUsageProvider.overrideWith(
            (ref, limit) => Stream.value([_event('Evening Glow', null)])),
      ]);
      await _pump(tester, c, const RecentPatternsSection());
      await _settle(tester);

      await tester.tap(find.text('Evening Glow'));
      await _settle(tester, 40);

      expect(repo.writeCount, 0);
      expect(c.read(wledCommandFailureProvider)?.message,
          contains("Couldn't read your controller's channels"));
    });

    testWidgets('row 1: with no controller, a Recent tap gives the shared '
        'reason — not "No device connected"', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, noController: true, extra: [
        recentUsageProvider.overrideWith(
            (ref, limit) => Stream.value([_event('Evening Glow', null)])),
      ]);
      await _pump(tester, c, const RecentPatternsSection());
      await _settle(tester);

      await tester.tap(find.text('Evening Glow'));
      await _settle(tester, 10);

      expect(repo.writeCount, 0);
      expect(c.read(wledCommandFailureProvider)?.message,
          contains('No controller is set up yet'));
      expect(find.text('No device connected'), findsNothing);
    });
  });

  group('rows 20, 21 — the theme grid card', () {
    const sub = SubCategory(
      id: 'sub_test',
      name: 'Holiday Trio',
      parentCategoryId: 'cat_holiday',
      themeColors: [Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFFFFFFFF)],
    );
    final item = PatternItem(
      id: 'gen_sub_test_fx_28',
      name: 'Holiday Trio Chase',
      imageUrl: '',
      categoryId: 'cat_holiday',
      wledPayload: const {
        'seg': [
          {
            'fx': 28,
            'sx': 60,
            'ix': 128,
            'pal': 5,
            'col': [
              [255, 0, 0, 0],
              [0, 255, 0, 0],
              [255, 255, 255, 0],
            ],
          }
        ],
      },
    );

    testWidgets('ONE write, carrying power on and the house\'s own level; all '
        'three colours survive; the preview shows all three', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, extra: [
        subCategoryByIdProvider.overrideWith((ref, id) async => sub),
        patternGeneratedItemsBySubCategoryProvider
            .overrideWith((ref, id) async => [item]),
      ]);
      await _pump(
          tester,
          c,
          const ThemeSelectionScreen(
              categoryId: 'cat_holiday', subCategoryId: 'sub_test'));
      await _settle(tester);

      await tester.tap(find.text('Holiday Trio Chase'));
      await _settle(tester);

      expect(repo.writeCount, 1,
          reason: 'row 20: no colour-1 re-send after the apply');
      final sent = repo.applied.single;
      expect(sent['on'], isTrue, reason: 'row 21: an off house comes on');
      expect(sent['bri'], kHomeLitState.brightness,
          reason: 'row 21: at the level the house is at — not a fixed one');
      for (final s in (sent['seg'] as List).cast<Map>()) {
        expect((s['col'] as List).length, 3);
        expect(s['col'][1], [0, 255, 0, 0]);
      }
      expect(c.read(wledStateProvider).colorSequence.length, 3);
      expect(find.text('Applied: Holiday Trio Chase'), findsOneWidget);
    });
  });

  group('rows 1, 80 — an Explore pattern card and its adjustment sheet', () {
    final card = PatternItem(
      id: 'p1',
      name: 'Blue Chase',
      imageUrl: '',
      categoryId: 'cat_holiday',
      wledPayload: const {
        'on': true,
        'seg': [
          {
            'fx': 28,
            'sx': 60,
            'ix': 128,
            'col': [
              [0, 0, 255, 0]
            ],
          }
        ],
      },
    );

    testWidgets('row 1: a closed gate is explained; nothing is sent',
        (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, channels: const []);
      await _pump(tester,
          c, SizedBox(width: 200, height: 220, child: PatternCard(pattern: card)));

      await tester.tap(find.text('Blue Chase'));
      await _settle(tester, 40);

      expect(repo.writeCount, 0);
      expect(c.read(wledCommandFailureProvider)?.message,
          contains("Couldn't read your controller's channels"));
    });

    testWidgets('row 19: an Explore card apply is recorded as a use, so it '
        'shows under Recent Patterns', (tester) async {
      final repo = RecordingWledRepository();
      final log = <Map<String, dynamic>>[];
      final c = _container(repo, extra: [
        usageLoggerNotifierProvider.overrideWith(() => _RecordingUsage(log)),
      ]);
      await _pump(tester,
          c, SizedBox(width: 200, height: 220, child: PatternCard(pattern: card)));

      await tester.tap(find.text('Blue Chase'));
      await _settle(tester);

      expect(repo.applied, hasLength(1));
      expect(log.single['source'], 'explore');
      expect(log.single['name'], 'Blue Chase');
    });

    testWidgets('row 1: with no controller, the card gives the shared reason '
        '— not "No device connected"', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, noController: true);
      await _pump(tester,
          c, SizedBox(width: 200, height: 220, child: PatternCard(pattern: card)));

      await tester.tap(find.text('Blue Chase'));
      await _settle(tester, 10);

      expect(repo.writeCount, 0);
      expect(c.read(wledCommandFailureProvider)?.message,
          contains('No controller is set up yet'));
      expect(find.text('No device connected'), findsNothing);
    });

    testWidgets('row 80 + priority: the sheet\'s sliders adjust only the '
        'selected channel and never change power; a refusal puts the slider '
        'back', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, selected: {0});
      await _pump(tester,
          c, SizedBox(width: 200, height: 220, child: PatternCard(pattern: card)));

      await tester.tap(find.text('Blue Chase'));
      await _settle(tester);
      expect(repo.applied, hasLength(1), reason: 'the card applied');

      // The adjustment sheet opened; nudge Intensity.
      final intensity = find.byType(Slider).last;
      await tester.drag(intensity, const Offset(60, 0));
      await _settle(tester);

      final tweak = repo.applied.last;
      expect(payloadTouchesPower(tweak), isFalse);
      expect([for (final s in (tweak['seg'] as List).cast<Map>()) s['id']], [0]);

      // Now the controller refuses.
      repo.succeed = false;
      final before = tester.widget<Slider>(intensity).value;
      await tester.drag(intensity, const Offset(60, 0));
      await _settle(tester);
      expect(tester.widget<Slider>(intensity).value, before);
      expect(c.read(wledCommandFailureProvider)?.message, isNotNull);
    });
  });
}
