// Build 119: the Neighborhood Sync action bar and the onboarding's last page
// padded for the glass dock twice (a SafeArea plus navBarTotalHeight read from
// a context above it), leaving a 112–146 px black band above the dock with the
// "Start a Block Party" / "Join the Party" buttons floating high. This pins
// the band at the four iPhone logical sizes: intended 12 px, small tolerance.
//
// Hosts the real screen the way MainScaffold does (NavBarInsetShell + the
// real GlassDockNavBar) with every provider the screen reads overridden to
// plain values. No network, no Firestore, no controller; synthetic ids only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_screen.dart';
import 'package:nexgen_command/widgets/navigation/glass_dock_nav_bar.dart';
import 'package:nexgen_command/widgets/navigation/nav_bar_inset.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Phone {
  const _Phone(this.label, this.size, this.dpr, this.top, this.bottom);
  final String label;
  final Size size;
  final double dpr;
  final double top; // status bar, logical px
  final double bottom; // home indicator, logical px
}

const _phones = <_Phone>[
  _Phone('smallest (SE class)', Size(375, 667), 2.0, 20, 0),
  _Phone('6.1 inch', Size(390, 844), 3.0, 47, 34),
  _Phone('6.1 inch Pro', Size(393, 852), 3.0, 59, 34),
  _Phone('Max', Size(430, 932), 3.0, 59, 34),
];

/// Intended gap between the buttons' bottom edge and the dock's top edge: the
/// action bar's own 12 px bottom padding.
const double _kIntendedBand = 12;
const double _kTolerance = 4;

void _applyPhone(WidgetTester tester, _Phone p) {
  final pad = FakeViewPadding(top: p.top * p.dpr, bottom: p.bottom * p.dpr);
  tester.view.devicePixelRatio = p.dpr;
  tester.view.physicalSize = p.size * p.dpr;
  tester.view.padding = pad;
  tester.view.viewPadding = pad;
  addTearDown(tester.view.reset);
}

final _groups = <NeighborhoodGroup>[
  NeighborhoodGroup(
    id: 'grp-a',
    name: 'Maple Street Crew',
    inviteCode: 'TESTA1',
    creatorUid: 'customer-a',
    createdAt: DateTime(2026, 1, 1),
    memberUids: const ['customer-a', 'customer-b', 'customer-c'],
    isActive: true,
    activePatternName: 'Candy Cane',
  ),
  NeighborhoodGroup(
    id: 'grp-b',
    name: 'Cul-de-sac Lights',
    inviteCode: 'TESTB2',
    creatorUid: 'customer-a',
    createdAt: DateTime(2026, 1, 2),
    memberUids: const ['customer-a', 'customer-d'],
  ),
];

/// Replica of MainScaffold's host: extendBody Scaffold → NavBarInsetShell
/// (body, GlassDockNavBar).
Widget _host({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: nexGenPremiumDarkTheme,
      home: Scaffold(
        extendBody: true,
        body: NavBarInsetShell(
          body: const NeighborhoodSyncScreen(),
          navBar: GlassDockNavBar(index: 0, onTap: (_) {}),
        ),
      ),
    ),
  );
}

List<Override> _returningUser() => [
      syncEngineControllerProvider.overrideWith((ref) {}),
      userNeighborhoodsProvider.overrideWith((ref) => Stream.value(_groups)),
      neighborhoodSyncOnboardingCompleteProvider
          .overrideWith((ref) async => true),
      previousGroupsProvider
          .overrideWith((ref) async => const <PreviousGroup>[]),
    ];

List<Override> _newUser() => [
      syncEngineControllerProvider.overrideWith((ref) {}),
      userNeighborhoodsProvider
          .overrideWith((ref) => Stream.value(const <NeighborhoodGroup>[])),
      neighborhoodSyncOnboardingCompleteProvider
          .overrideWith((ref) async => false),
      previousGroupsProvider
          .overrideWith((ref) async => const <PreviousGroup>[]),
    ];

/// The screen runs repeating animations, so pumpAndSettle never returns.
/// The overrides emit after a microtask and NavBarInsetShell measures the
/// dock in one post-frame setState; a handful of frames is enough.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Records RenderFlex overflows instead of failing: the onboarding page has a
/// pre-existing 14 px horizontal overflow at 375 pt (tracked for 120) that
/// is not what this test measures. Every other error still fails the test.
void _tolerateOverflow() {
  final prev = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed by')) return;
    prev?.call(details);
  };
  addTearDown(() => FlutterError.onError = prev);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('group list: the buttons sit 12 px above the dock', () {
    for (final p in _phones) {
      testWidgets(p.label, (tester) async {
        _applyPhone(tester, p);
        _tolerateOverflow();
        await tester.pumpWidget(_host(overrides: _returningUser()));
        await _settle(tester);

        final start = find.widgetWithText(ElevatedButton, 'Start a Block Party');
        final join = find.widgetWithText(OutlinedButton, 'Join the Party');
        expect(start, findsOneWidget);
        expect(join, findsOneWidget);

        final startR = tester.getRect(start);
        final joinR = tester.getRect(join);
        final dockTop = tester.getRect(find.byType(GlassDockNavBar)).top;
        final buttonsBottom =
            startR.bottom > joinR.bottom ? startR.bottom : joinR.bottom;
        final band = dockTop - buttonsBottom;

        expect(band, closeTo(_kIntendedBand, _kTolerance),
            reason: '${p.label}: band between the buttons and the dock is '
                '${band.toStringAsFixed(1)} px; intended $_kIntendedBand '
                '(before the fix: 112 px on the SE, 146 px on notched phones)');
        expect(buttonsBottom, lessThan(dockTop),
            reason: 'the buttons must not sit under the dock');
      });
    }
  });

  group('onboarding last page: no tall band under the buttons', () {
    for (final p in _phones) {
      testWidgets(p.label, (tester) async {
        _applyPhone(tester, p);
        _tolerateOverflow();
        await tester.pumpWidget(_host(overrides: _newUser()));
        await _settle(tester);
        await tester.tap(find.text('Skip to Get Started'));
        await _settle(tester);

        final discover =
            find.widgetWithText(TextButton, 'Discover Nearby Groups');
        expect(discover, findsOneWidget);
        final lastBottom = tester.getRect(discover).bottom;
        final dockTop = tester.getRect(find.byType(GlassDockNavBar)).top;
        final band = dockTop - lastBottom;

        expect(band, inInclusiveRange(0, 8 + _kTolerance),
            reason: '${p.label}: band below the last content is '
                '${band.toStringAsFixed(1)} px; the trailing spacer is 8 px '
                '(before the fix it was the whole dock inset again)');
      });
    }
  });
}
