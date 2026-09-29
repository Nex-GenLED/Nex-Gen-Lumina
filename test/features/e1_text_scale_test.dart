// +110 E1 — every screen this package owns, through the foundation's
// text-scale harness: 1.0x, 1.75x and 2.0x, all with Bold Text on, on a
// 390×844 phone (docs/ACCESSIBILITY_TEXT_SCALE_TESTING.md).
//
// Home, Explore (root, folders, My Designs, the palette tuner in all three of
// its modes, the per-pixel explanation), the Pattern Editor, the theme grid,
// the category screen, and the sheets and dialogs they open.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/dashboard/wled_dashboard_page.dart';
import 'package:nexgen_command/features/dashboard/widgets/channel_selector_bar.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart'
    show favoritedPatternIdsProvider;
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/edit_pattern_screen.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_category_detail.dart';
import 'package:nexgen_command/features/wled/pattern_explore_screen.dart';
import 'package:nexgen_command/features/wled/pattern_grid_widgets.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_theme_selection.dart';
import 'package:nexgen_command/features/wled/save_custom_pattern_dialog.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/favorites_grid.dart';
import 'package:nexgen_command/widgets/pattern_adjustment_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/home_dashboard_harness.dart';
import '../helpers/recording_wled_repository.dart';
import '../helpers/text_scale_harness.dart';

/// True while surveying: report every screen's defects without failing, so
/// the full list is known before any fix. The committed test is false.
const bool _survey = bool.fromEnvironment('E1_TEXT_SCALE_SURVEY');

Future<void> _check(
  WidgetTester tester,
  String name,
  Widget widget, {
  TextScaleHost host = TextScaleHost.screen,
  List<Finder> allowEllipsis = const [],
  int frames = 1,
  Duration settle = const Duration(milliseconds: 500),
}) async {
  if (_survey) {
    final reports = <TextScaleReport>[];
    for (final p in TextScaleProfile.standardMatrix) {
      reports.add(await pumpAtTextScale(tester, widget,
          profile: p,
          host: host,
          allowEllipsis: allowEllipsis,
          frames: frames,
          settle: settle));
    }
    final failure = describeTextScaleMatrixFailures(reports);
    // ignore: avoid_print
    print('SURVEY [$name]: ${failure ?? 'clean'}');
    return;
  }
  await expectNoTextScaleDefectsAcrossMatrix(tester, widget,
      host: host, allowEllipsis: allowEllipsis, frames: frames, settle: settle);
}

// ignore: subtype_of_sealed_class
class _StubUser implements User {
  @override
  String get uid => 'customer-test';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

FavoritePattern _fav(String id, String name) => FavoritePattern(
      id: id,
      patternName: name,
      addedAt: DateTime(2026, 9, 1),
      usageCount: 1,
      patternData: const {
        'on': true,
        'seg': [
          {
            'fx': 28,
            'col': [
              [0, 0, 255, 0],
              [255, 255, 255, 0],
            ],
          }
        ],
      },
      autoAdded: false,
    );

SmartSuggestion _suggestion() => SmartSuggestion(
      id: 's1',
      type: SuggestionType.applyPattern,
      title: 'Turn on Warm White for Evening',
      description: "It's almost sunset - create a cozy ambiance?",
      createdAt: DateTime(2026, 9, 29),
      actionData: const {'pattern_name': 'Warm White Glow'},
      priority: 0.8,
    );

const _palette = LibraryNode(
  id: 'ocean_breeze',
  name: 'Ocean Breeze',
  nodeType: LibraryNodeType.palette,
  parentId: 'cat_water',
  themeColors: [Color(0xFF0066FF), Color(0xFFFFFFFF)],
);

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

List<Override> _explore({
  List<CustomDesign> designs = const [],
  ConnectivityStatus connectivity = ConnectivityStatus.local,
}) =>
    [
      ...homeDashboardOverrides(
          repo: RecordingWledRepository(), connectivity: connectivity),
      patternCategoriesProvider.overrideWith((_) async => const [
            PatternCategory(id: 'cat_holiday', name: 'Holidays', imageUrl: ''),
            PatternCategory(id: 'cat_sports', name: 'Game Day Fan Zone', imageUrl: ''),
          ]),
      designsStreamProvider.overrideWith((ref) => Stream.value(designs)),
      authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
    ];

List<Override> _editor() => [
      ...homeDashboardOverrides(repo: RecordingWledRepository()),
      designsStreamProvider
          .overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue('customer-test'),
      authStateProvider.overrideWith((ref) => Stream<User?>.value(_StubUser())),
      favoritedPatternIdsProvider
          .overrideWith((ref) => Stream.value(const <String>{})),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
    ];

Widget _scoped(List<Override> overrides, Widget child) =>
    ProviderScope(overrides: overrides, child: child);

/// For a screen that opens a sheet: the ProviderScope goes ABOVE the
/// MaterialApp, as in the app, so the sheet's route can read providers. Pump
/// with [TextScaleHost.none].
Widget _app(List<Override> overrides, Widget home) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: nexGenPremiumDarkTheme,
        builder: TextScaleClamp.appBuilder,
        home: home,
      ),
    );

/// After a strict check, the last profile's tree is still up: the sheet must
/// be in it, or the check measured only the screen behind.
void _expectSheetMeasured() {
  if (_survey) return;
  expect(find.byType(BottomSheet), findsOneWidget,
      reason: 'the sheet opened and was measured');
}

/// Opens something on the first frame after the screen appears.
class _OpenAfterFirstFrame extends StatefulWidget {
  const _OpenAfterFirstFrame({required this.child, required this.open});
  final Widget child;
  final void Function(BuildContext context) open;

  @override
  State<_OpenAfterFirstFrame> createState() => _OpenAfterFirstFrameState();
}

class _OpenAfterFirstFrameState extends State<_OpenAfterFirstFrame> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Favourite names and design names are customer data: two lines, then an
  // ellipsis, with the full name in the tile's action sheet / Now Playing /
  // the design's own screen (the doc's criteria for `allowEllipsis`).
  final dataLabels = [
    find.byKey(const ValueKey('favorite-tile-name')),
  ];

  group('Home', () {
    testWidgets('default', (tester) async {
      await _check(
        tester,
        'Home',
        _scoped(
          homeDashboardOverrides(
            repo: RecordingWledRepository(),
            favorites: [_fav('f1', 'Blue Chase'), _fav('f2', 'Candy Cane Chase')],
            suggestions: [_suggestion()],
          ),
          const WledDashboardPage(),
        ),
        allowEllipsis: dataLabels,
      );
    });

    testWidgets('disconnected', (tester) async {
      await _check(
        tester,
        'Home — disconnected',
        _scoped(
          homeDashboardOverrides(
            repo: RecordingWledRepository(),
            state: kHomeLitState.copyWith(connected: false),
          ),
          const WledDashboardPage(),
        ),
        allowEllipsis: dataLabels,
      );
    });

    testWidgets('no controller yet', (tester) async {
      await _check(
        tester,
        'Home — no controller',
        _scoped(
          homeDashboardOverrides(
              repo: RecordingWledRepository(), controllers: const []),
          const WledDashboardPage(),
        ),
        allowEllipsis: dataLabels,
      );
    });

    // +110 E1 follow-ups 2 and 3: the lights-off notice, and the direction
    // wording away from home.
    for (final (name, overrides) in [
      (
        'Home — Tune panel, lights off',
        homeDashboardOverrides(
          repo: RecordingWledRepository(),
          state: kHomeLitState.copyWith(isOn: false),
        ),
      ),
      (
        'Home — Tune panel, away',
        homeDashboardOverrides(
          repo: RecordingWledRepository(),
          connectivity: ConnectivityStatus.remote,
        ),
      ),
    ]) {
      testWidgets(name, (tester) async {
        await _check(
          tester,
          name,
          _scoped(
            overrides,
            const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: PatternAdjustmentPanel(
                  initialEffectId: 28,
                  effectName: 'Chase',
                ),
              ),
            ),
          ),
        );
      });
    }

    testWidgets('Tune panel', (tester) async {
      await _check(
        tester,
        'Home — Tune panel',
        _scoped(
          homeDashboardOverrides(repo: RecordingWledRepository()),
          const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: PatternAdjustmentPanel(
                initialEffectId: 28,
                effectName: 'Chase',
                initialColors: [
                  [255, 0, 0, 0],
                  [0, 0, 255, 0],
                ],
              ),
            ),
          ),
        ),
      );
    });

    testWidgets('channel bar, open', (tester) async {
      await _check(
        tester,
        'Home — channel bar',
        _scoped(
          [
            ...homeDashboardOverrides(repo: RecordingWledRepository()),
            channelPowerStatesProvider
                .overrideWith((ref) => const {0: true, 1: false}),
          ],
          const Scaffold(
            body: _ExpandedChannelBar(),
          ),
        ),
      );
    });

    testWidgets('favourite tile actions sheet', (tester) async {
      await _check(
        tester,
        'Home — favourite actions sheet',
        _app(
          homeDashboardOverrides(
            repo: RecordingWledRepository(),
            favorites: [_fav('f1', 'Blue Chase')],
          ),
          _TapAfterFirstFrame(
            target: find.byKey(const ValueKey('favorite-tile-f1')),
            child: const Scaffold(
              body: SingleChildScrollView(
                  child: FavoritesGrid(initiallyEditing: true)),
            ),
          ),
        ),
        host: TextScaleHost.none,
        allowEllipsis: dataLabels,
        frames: 6,
        settle: const Duration(milliseconds: 900),
      );
      _expectSheetMeasured();
    });

    testWidgets('Save Custom Pattern dialog', (tester) async {
      await _check(
        tester,
        'Save Custom Pattern dialog',
        _OpenAfterFirstFrame(
          open: (context) => showDialog<String>(
              context: context,
              builder: (_) => const SaveCustomPatternDialog()),
          child: const Scaffold(body: SizedBox.shrink()),
        ),
        frames: 6,
        settle: const Duration(milliseconds: 900),
      );
    });
  });

  group('Explore', () {
    testWidgets('root', (tester) async {
      await _check(tester, 'Explore root',
          _scoped(_explore(), const ExplorePatternsScreen()));
    });

    testWidgets('library root folders', (tester) async {
      await _check(tester, 'Library folders',
          _scoped(_explore(), const LibraryBrowserScreen(nodeId: null)));
    });

    testWidgets('My Designs', (tester) async {
      await _check(
        tester,
        'My Designs',
        _scoped(_explore(designs: [_editorDesign()]),
            const LibraryBrowserScreen(nodeId: kMyDesignsCategoryId)),
      );
    });

    testWidgets('palette tuner — catalog', (tester) async {
      await _check(
          tester,
          'Tuner — catalog',
          _scoped(_explore(),
              const Scaffold(body: ColorwayEffectSelectorPage(paletteNode: _palette))));
    });

    testWidgets('palette tuner — selection (schedule)', (tester) async {
      await _check(
          tester,
          'Tuner — selection',
          _scoped(
              _explore(),
              Scaffold(
                  body: ColorwayEffectSelectorPage(
                      paletteNode: _palette,
                      saveDestinationLabel: 'schedule',
                      onDesignSelected: (_) {}))));
    });

    testWidgets('palette tuner — a design from My Designs', (tester) async {
      await _check(
          tester,
          'Tuner — design',
          _scoped(
              _explore(designs: [_editorDesign()]),
              Scaffold(
                  body: ColorwayEffectSelectorPage.forDesign(
                      design: _editorDesign()))));
    });

    testWidgets('theme grid', (tester) async {
      await _check(
        tester,
        'Theme grid',
        _scoped([
          ..._explore(),
          subCategoryByIdProvider.overrideWith((ref, id) async => const SubCategory(
                id: 'sub_test',
                name: 'Holiday Trio',
                parentCategoryId: 'cat_holiday',
                themeColors: [Color(0xFFFF0000), Color(0xFF00FF00)],
              )),
        ], const ThemeSelectionScreen(categoryId: 'cat_holiday', subCategoryId: 'sub_test')),
      );
    });

    testWidgets('category screen', (tester) async {
      await _check(
          tester,
          'Category screen',
          _scoped(_explore(),
              const CategoryDetailScreen(categoryId: 'cat_holiday', categoryName: 'Holidays')));
    });

    testWidgets('pattern card applied — the confirmation with "Adjust"',
        (tester) async {
      await _check(
        tester,
        'Explore card confirmation',
        _app(
          _explore(),
          _TapAfterFirstFrame(
            target: find.text('Blue Chase'),
            child: const _PatternCardHost(),
          ),
        ),
        host: TextScaleHost.none,
        frames: 8,
        settle: const Duration(milliseconds: 1200),
      );
      if (!_survey) {
        expect(find.byType(SnackBar), findsOneWidget,
            reason: 'the confirmation was measured');
      }
    });

    testWidgets('adjustment sheet, away from home', (tester) async {
      await _check(
        tester,
        'Explore adjustment sheet — away',
        _app(
          _explore(connectivity: ConnectivityStatus.remote),
          _TapAfterFirstFrame(
            target: find.text('Blue Chase'),
            then: [find.text('Adjust')],
            child: const _PatternCardHost(),
          ),
        ),
        host: TextScaleHost.none,
        frames: 12,
        settle: const Duration(milliseconds: 1500),
      );
      _expectSheetMeasured();
    });

    testWidgets('pattern card + adjustment sheet', (tester) async {
      await _check(
        tester,
        'Explore adjustment sheet',
        _app(
          _explore(),
          // +110 E1 follow-up 1: the sheet opens only from "Adjust" on the
          // confirmation, no longer on every tap.
          _TapAfterFirstFrame(
            target: find.text('Blue Chase'),
            then: [find.text('Adjust')],
            child: const _PatternCardHost(),
          ),
        ),
        host: TextScaleHost.none,
        frames: 12,
        settle: const Duration(milliseconds: 1500),
      );
      _expectSheetMeasured();
    });
  });

  group('Pattern Editor', () {
    testWidgets('animated, one colour (BG shown)', (tester) async {
      await _check(
        tester,
        'Pattern Editor — animated',
        _scoped(
          _editor(),
          const EditPatternScreen(
            initialPattern: EditablePattern(
                id: 'edit_1',
                name: 'Blue Chase',
                actionColors: [Color(0xFF0000FF)],
                effectId: 28),
          ),
        ),
      );
    });

    testWidgets('Static, three colours', (tester) async {
      await _check(
        tester,
        'Pattern Editor — static',
        _scoped(
          _editor(),
          const EditPatternScreen(
            initialPattern: EditablePattern(
                id: 'edit_2',
                name: 'Kansas City Chiefs',
                actionColors: [
                  Color(0xFFE31837),
                  Color(0xFFFFB81C),
                  Color(0xFFFFFFFF)
                ],
                effectId: 0),
          ),
        ),
      );
    });
  });
}

class _ExpandedChannelBar extends StatefulWidget {
  const _ExpandedChannelBar();
  @override
  State<_ExpandedChannelBar> createState() => _ExpandedChannelBarState();
}

class _ExpandedChannelBarState extends State<_ExpandedChannelBar> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Tap the header to open the chips.
      final finder = find.byIcon(Icons.expand_more);
      if (finder.evaluate().isEmpty) return;
      final box = finder.evaluate().first.renderObject! as RenderBox;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      final gesture = GestureBinding.instance;
      gesture.handlePointerEvent(PointerDownEvent(position: center));
      gesture.handlePointerEvent(PointerUpEvent(position: center));
    });
  }

  @override
  Widget build(BuildContext context) =>
      const SingleChildScrollView(child: ChannelSelectorBar());
}

/// Taps whatever [target] finds on the first frame it appears in (it may
/// arrive from a stream a frame or two late), so the harness measures the
/// sheet or dialog that tap opens. [then] are tapped next, in order, each as
/// soon as it appears (e.g. a snackbar's action).
class _TapAfterFirstFrame extends StatefulWidget {
  const _TapAfterFirstFrame(
      {required this.target, this.then = const [], required this.child});
  final Finder target;
  final List<Finder> then;
  final Widget child;
  @override
  State<_TapAfterFirstFrame> createState() => _TapAfterFirstFrameState();
}

class _TapAfterFirstFrameState extends State<_TapAfterFirstFrame> {
  var _attempts = 0;
  var _next = 0;
  var _seenFor = 0;

  List<Finder> get _targets => [widget.target, ...widget.then];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(_tryTap);
  }

  void _again() {
    if (++_attempts < 40) {
      WidgetsBinding.instance.addPostFrameCallback(_tryTap);
    }
  }

  void _tryTap(Duration _) {
    if (_next >= _targets.length) return;
    final hits = _targets[_next].evaluate();
    if (hits.isEmpty) {
      _seenFor = 0;
      _again();
      return;
    }
    // A follow-up target (a snackbar action) slides in: tap it once it has
    // been on screen for a few frames, not mid-entrance.
    if (_next > 0 && ++_seenFor < 4) {
      _again();
      return;
    }
    _seenFor = 0;
    final box = hits.first.renderObject! as RenderBox;
    final center = box.localToGlobal(box.size.center(Offset.zero));
    GestureBinding.instance
      ..handlePointerEvent(PointerDownEvent(position: center))
      ..handlePointerEvent(PointerUpEvent(position: center));
    _next++;
    if (_next < _targets.length) _again();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PatternCardHost extends StatelessWidget {
  const _PatternCardHost();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SizedBox(
          width: 200,
          height: 240,
          child: PatternCard(
            pattern: PatternItem(
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
                    'col': [
                      [0, 0, 255, 0]
                    ]
                  }
                ],
              },
            ),
          ),
        ),
      );
}
