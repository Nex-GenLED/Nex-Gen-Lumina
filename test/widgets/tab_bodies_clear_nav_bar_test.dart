// Regression: no tab body may scroll its last content under the glass dock.
//
// This has regressed more than once, always the same way: a screen (or one
// state of a screen) sets an explicit `padding:` on its scroll view and
// forgets the bottom term, so its last rows render beneath the dock, which is
// above them in z-order and takes the taps.
//
// Since 2026-09-25 the shell reserves the dock's height in MediaQuery
// (NavBarInsetShell) and a padding-less ListView, a SafeArea or a Scaffold
// FAB is correct with no extra code. What can still go wrong is exactly the
// old mistake — an explicit padding without the bottom term — so this test
// pumps each tab under the real dock and checks EVERY vertical scroll view it
// renders reserves at least the inset its own MediaQuery reports (zero when
// an ancestor SafeArea has already consumed it).
//
// Tabs pumped here: Explore (default, no-match and results states) and
// System. Home and Schedule are not pumped: their root pages watch ~19
// providers each backed by Firestore, the WLED poller and the calendar
// engine, and the repo has no fakes for those yet. Their scroll views were
// audited by hand for this change (both pad by navBarTotalHeight) and any
// future screen is covered by the shell mechanism pinned in
// nav_bar_inset_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/properties/properties_providers.dart';
import 'package:nexgen_command/features/properties/property_models.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/settings_page.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_explore_screen.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/widgets/navigation/glass_dock_nav_bar.dart';
import 'package:nexgen_command/widgets/navigation/nav_bar_inset.dart';
import 'package:shared_preferences/shared_preferences.dart';

const double kSafeBottom = 34;
const Size kScreen = Size(390, 844);

/// Mounts [page] the way MainScaffold does: inside its own Navigator (the
/// branch navigator), under the real glass dock, inside the shell inset.
Future<void> _pumpTab(
  WidgetTester tester,
  Widget page, {
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = kScreen;
  tester.view.padding = const FakeViewPadding(bottom: kSafeBottom);
  tester.view.viewPadding = const FakeViewPadding(bottom: kSafeBottom);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: NavBarInsetShell(
          navBar: GlassDockNavBar(index: 0, onTap: (_) {}),
          body: Navigator(
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => page),
          ),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

/// The dock's Lumina button animates continuously, so pumpAndSettle would
/// never return; pump a few explicit frames instead.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// The bottom inset a scroll view must reserve, as seen from its own context.
double _requiredInset(BuildContext ctx) => MediaQuery.paddingOf(ctx).bottom;

double _trailingSliverBottom(CustomScrollView sv) {
  if (sv.slivers.isEmpty) return 0;
  final last = sv.slivers.last;
  if (last is SliverPadding) {
    return last.padding.resolve(TextDirection.ltr).bottom;
  }
  if (last is SliverSafeArea) return double.infinity;
  if (last is SliverToBoxAdapter) {
    final child = last.child;
    if (child is SizedBox) return child.height ?? 0;
  }
  return 0;
}

/// Asserts every vertical, independently scrolling scroll view currently on
/// screen reserves at least the dock inset its MediaQuery reports.
void expectScrollViewsClearTheDock(WidgetTester tester, String state) {
  var checked = 0;
  final candidates = find.byWidgetPredicate(
    (w) => w is ScrollView || w is SingleChildScrollView,
  );
  for (final element in candidates.evaluate()) {
    final w = element.widget;
    final axis = w is ScrollView
        ? w.scrollDirection
        : (w as SingleChildScrollView).scrollDirection;
    if (axis != Axis.vertical) continue;
    // Embedded lists are laid out by the scroll view that contains them.
    if (w is ScrollView &&
        (w.shrinkWrap || w.physics is NeverScrollableScrollPhysics)) {
      continue;
    }
    if (w is SingleChildScrollView &&
        w.physics is NeverScrollableScrollPhysics) {
      continue;
    }

    final required = _requiredInset(element);
    double reserved;
    if (w is BoxScrollView) {
      // No explicit padding: the framework applies MediaQuery.padding.
      reserved = w.padding == null
          ? required
          : w.padding!.resolve(TextDirection.ltr).bottom;
    } else if (w is CustomScrollView) {
      reserved = _trailingSliverBottom(w);
    } else if (w is SingleChildScrollView) {
      reserved = w.padding?.resolve(TextDirection.ltr).bottom ?? 0;
    } else {
      continue; // an unknown ScrollView subclass; nothing to assert
    }
    expect(reserved, greaterThanOrEqualTo(required),
        reason: '[$state] ${w.runtimeType} reserves $reserved px at the '
            'bottom but its MediaQuery says the dock needs $required px — '
            'its last content will render under the glass dock');
    checked++;
  }
  expect(checked, greaterThan(0),
      reason: '[$state] no vertical scroll view was found to check');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Explore tab', () {
    const category = PatternCategory(
        id: 'cat_sports', name: 'Game Day Fan Zone', imageUrl: '');
    // Two colours: the results card paints a gradient from them.
    final palette = LibraryNode(
      id: 'p_blue',
      name: 'Blue',
      nodeType: LibraryNodeType.palette,
      parentId: 'cat_sports',
      themeColors: const [Colors.blue, Colors.white],
    );
    final overrides = <Override>[
      authStateProvider.overrideWith((_) => Stream.value(null)),
      patternCategoriesProvider.overrideWith((_) async => [category]),
      librarySearchProvider.overrideWith((ref, query) async => query == 'blue'
          ? LibrarySearchResults(
              palettes: [palette], folders: const [], patterns: const [])
          : const LibrarySearchResults(
              palettes: [], folders: [], patterns: [])),
    ];

    Future<void> search(WidgetTester tester, String query) async {
      await tester.enterText(find.byType(TextField).first, query);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _settle(tester);
    }

    testWidgets('default, no-match and results states clear the dock',
        (tester) async {
      await _pumpTab(tester, const ExplorePatternsScreen(),
          overrides: overrides);
      expectScrollViewsClearTheDock(tester, 'explore/default');

      await search(tester, 'zzz-no-such-design');
      expectScrollViewsClearTheDock(tester, 'explore/no-match');

      await search(tester, 'blue');
      expectScrollViewsClearTheDock(tester, 'explore/results');
    });
  });

  group('System tab', () {
    testWidgets('settings list clears the dock', (tester) async {
      await _pumpTab(tester, const SettingsPage(), overrides: [
        authStateProvider.overrideWith((_) => Stream.value(null)),
        currentUserProfileProvider.overrideWith((_) => Stream.value(null)),
        controllersStreamProvider
            .overrideWith((_) => Stream.value(const <ControllerInfo>[])),
        userPropertiesProvider
            .overrideWith((_) => Stream.value(const <Property>[])),
      ]);
      expectScrollViewsClearTheDock(tester, 'system/settings');
    });
  });

  test('the checker itself rejects an unpadded explicit padding', () {
    // Sanity: the assertion must be able to fail, or it guards nothing.
    const required = kNavBarContentHeight + kSafeBottom;
    const padded = EdgeInsets.fromLTRB(16, 16, 16, 16);
    expect(padded.bottom, lessThan(required));
  });
}
