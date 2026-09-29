// +110 E1 — Explore navigation surfaces.
//
// Row 88 (Search icon), 89 (pinned tree retired), 90/91 (category screen),
// 92 (per-pixel design in a picker), 119 (display colours), item C (an edited
// pattern in My Designs is a pattern card that opens the tuner).

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/pattern_category_detail.dart';
import 'package:nexgen_command/features/wled/pattern_explore_screen.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/pattern_theme_selection.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

List<Override> _base({List<CustomDesign> designs = const [], UserModel? profile}) => [
      authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(profile)),
      patternCategoriesProvider.overrideWith((_) async => const [
            PatternCategory(id: 'cat_holiday', name: 'Holidays', imageUrl: ''),
          ]),
      designsStreamProvider.overrideWith((ref) => Stream.value(designs)),
      wledRepositoryProvider.overrideWith((ref) => RecordingWledRepository()),
      wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
      deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
      participatingChannelIdsProvider.overrideWithValue(null),
      demoModeProvider.overrideWith((ref) => false),
      userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
    ];

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, Widget home, List<Override> overrides) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: home),
  ));
  await _frames(tester);
}

UserModel _pinnedProfile() => UserModel(
      id: 'customer-test',
      email: 'customer@example.com',
      displayName: 'Customer',
      ownerId: 'customer-test',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      preferredCategoryIds: const ['cat_holiday'],
    );

/// A pattern saved from the Pattern Editor, as item C now stores it.
CustomDesign _editorDesign() => CustomDesign(
      id: 'd1',
      name: 'Blue Chase',
      createdAt: DateTime(2026, 9, 29),
      updatedAt: DateTime(2026, 9, 29),
      ownerId: 'customer-test',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 0, color: [0, 0, 255, 0]),
          ],
          effectId: 28,
          speed: 44,
          intensity: 90,
        ),
      ],
      brightness: 150,
      brightnessStated: true,
      tags: const [kPatternEditorDesignTag],
    );

/// A painted design: a near-black base run, then accents.
CustomDesign _paintedDesign() => CustomDesign(
      id: 'p1',
      name: 'Painted',
      createdAt: DateTime(2026, 9, 29),
      updatedAt: DateTime(2026, 9, 29),
      ownerId: 'customer-test',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          ledCount: 30,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 9, color: [8, 8, 8, 0]),
            LedColorGroup(startLed: 10, endLed: 19, color: [255, 0, 0, 0]),
            LedColorGroup(startLed: 20, endLed: 29, color: [0, 255, 0, 0]),
          ],
        ),
      ],
      brightness: 200,
      perPixel: true,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('row 88: the Explore app-bar Search icon focuses the search '
      'field', (tester) async {
    await _pump(tester, const ExplorePatternsScreen(), _base());
    final field = find.byKey(const ValueKey('explore-search-field'));
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isFalse);

    await tester.tap(find.byKey(const ValueKey('explore-search-icon')));
    await tester.pump();

    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);
  });

  testWidgets('row 89: the legacy pinned tree is retired — no pinned rows on '
      'Explore even for an account that has pins', (tester) async {
    await _pump(tester, const ExplorePatternsScreen(),
        _base(profile: _pinnedProfile()));
    expect(find.byTooltip('Unpin folder'), findsNothing);
    expect(find.text('See All'), findsNothing);
  });

  group('the retired category screen (rows 89, 90, 91)', () {
    testWidgets('no Pin button, and the real design count', (tester) async {
      await _pump(
          tester,
          const CategoryDetailScreen(
              categoryId: 'cat_holiday', categoryName: 'Holidays'),
          _base());
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
      expect(find.byIcon(Icons.push_pin), findsNothing);
      expect(find.text('50+ designs available'), findsNothing);
      expect(
          find.text('${PatternRepository.kColorwayEffectIds.length} designs'),
          findsOneWidget);
    });

    testWidgets('row 90: "Ask Lumina" opens Lumina — it no longer shows a '
        'snackbar repeating itself', (tester) async {
      await _pump(
          tester,
          const CategoryDetailScreen(
              categoryId: 'cat_holiday', categoryName: 'Holidays'),
          _base());
      final container = ProviderScope.containerOf(
          tester.element(find.byType(CategoryDetailScreen)));
      final bar = find.byKey(const ValueKey('category-ask-lumina'));
      expect(find.textContaining('Ask Lumina for a Holidays look'),
          findsOneWidget);

      await tester.tap(bar);
      await tester.pump();

      expect(container.read(luminaSheetProvider).isOpen, isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  testWidgets('row 92: a per-pixel design in a schedule picker EXPLAINS — no '
      'spinner that never resolves', (tester) async {
    var handedBack = 0;
    await _pump(
      tester,
      LibraryBrowserScreen(
        nodeId: 'design_p1',
        saveDestinationLabel: 'schedule',
        onDesignSelected: (_) => handedBack++,
      ),
      _base(designs: [_paintedDesign()]),
    );

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('"Painted" is a per-pixel design'), findsOneWidget);
    expect(find.byKey(const ValueKey('per-pixel-choose-another')),
        findsOneWidget);
    expect(handedBack, 0);
  });

  test('row 119: display colours skip the near-black base run', () {
    expect(designDisplayColors(_paintedDesign()),
        const [Color(0xFFFF0000), Color(0xFF00FF00)]);
  });

  group('item C — an edited pattern in My Designs', () {
    testWidgets('renders as a PATTERN card: its effect running, the effect '
        'name and speed', (tester) async {
      await _pump(tester, const LibraryBrowserScreen(nodeId: kMyDesignsCategoryId),
          _base(designs: [_editorDesign()]));

      expect(find.byKey(const ValueKey('saved-design-preview-design_d1')),
          findsOneWidget);
      expect(find.text('Blue Chase'), findsOneWidget);
      expect(find.text('Chase · speed 44'), findsOneWidget);
    });

    testWidgets('tapping it opens the SAME tuner, on the design, with Apply',
        (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, __) =>
              const LibraryBrowserScreen(nodeId: kMyDesignsCategoryId),
        ),
        GoRoute(
          path: '/explore/library/:nodeId',
          builder: (_, s) =>
              LibraryBrowserScreen(nodeId: s.pathParameters['nodeId']),
        ),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: _base(designs: [_editorDesign()]),
        child: MaterialApp.router(routerConfig: router),
      ));
      await _frames(tester);

      await tester.tap(find.text('Blue Chase'));
      await _frames(tester, 8);

      expect(find.byType(ColorwayEffectSelectorPage), findsOneWidget);
      expect(find.byKey(const ValueKey('apply-design')), findsOneWidget);
      expect(find.byKey(const ValueKey('save-to-design')), findsOneWidget);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(ColorwayEffectSelectorPage)));
      expect(container.read(selectorEffectIdProvider), 28);
      expect(container.read(selectorSpeedProvider), 44);
      expect(container.read(selectorIntensityProvider), 90);
      expect(container.read(selectorSolidLayoutProvider), SolidLayout.blocks);
    });
  });
}
