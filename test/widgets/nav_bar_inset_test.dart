// The shell reserves the glass dock's height ONCE, for every tab body.
//
// MainScaffold draws the dock over a full-height branch host (extendBody).
// Until 2026-09-25 every screen had to reserve the dock's height itself and
// the ones that forgot lost their last rows under it — repeatedly. Now
// NavBarInsetShell (widgets/navigation/nav_bar_inset.dart) injects the
// dock's measured height into MediaQuery.padding / viewPadding, the way
// Scaffold does for a bottomNavigationBar, and navBarTotalHeight() reads it
// back. These pin that mechanism against the real dock so the constant, the
// injection and the helper cannot drift apart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/widgets/navigation/glass_dock_nav_bar.dart';
import 'package:nexgen_command/widgets/navigation/nav_bar_inset.dart';

const double kSafeBottom = 34; // iPhone home indicator
const Size kScreen = Size(390, 844);

void _useDevice(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = kScreen;
  tester.view.padding = const FakeViewPadding(bottom: kSafeBottom);
  tester.view.viewPadding = const FakeViewPadding(bottom: kSafeBottom);
  addTearDown(tester.view.reset);
}

GlassDockNavBar _dock() => GlassDockNavBar(index: 0, onTap: (_) {});

/// Pumps [body] under the real dock inside the shell inset, and returns the
/// MediaQuery the body sees once the dock has been measured.
Future<MediaQueryData> _pumpShell(WidgetTester tester, Widget body,
    {Widget? navBar}) async {
  _useDevice(tester);
  late MediaQueryData seen;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      extendBody: true,
      body: NavBarInsetShell(
        navBar: navBar ?? _dock(),
        body: Builder(builder: (ctx) {
          seen = MediaQuery.of(ctx);
          return body;
        }),
      ),
    ),
  ));
  // The dock is measured after its first layout and applied on the next
  // frame. (No pumpAndSettle: the Lumina button animates continuously.)
  await tester.pump();
  await tester.pump();
  return seen;
}

void main() {
  testWidgets('the glass dock is kNavBarContentHeight + safe area tall',
      (tester) async {
    _useDevice(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned(left: 0, right: 0, bottom: 0, child: _dock()),
        ]),
      ),
    ));
    await tester.pump();
    expect(tester.getSize(find.byType(GlassDockNavBar)).height,
        kNavBarContentHeight + kSafeBottom,
        reason: 'kNavBarContentHeight is the fallback the shell reserves '
            'before its first measurement; it must match the real dock');
  });

  testWidgets('NavBarInset adds the dock height to padding AND viewPadding',
      (tester) async {
    late MediaQueryData seen;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(
        padding: EdgeInsets.only(bottom: kSafeBottom),
        viewPadding: EdgeInsets.only(bottom: kSafeBottom),
      ),
      child: NavBarInset(
        child: Builder(builder: (ctx) {
          seen = MediaQuery.of(ctx);
          return const SizedBox();
        }),
      ),
    ));
    expect(seen.padding.bottom, kNavBarContentHeight + kSafeBottom);
    expect(seen.viewPadding.bottom, kNavBarContentHeight + kSafeBottom);
  });

  testWidgets('the shell injects the dock\'s rendered height', (tester) async {
    final seen = await _pumpShell(tester, const SizedBox.expand());
    final dockHeight = tester.getSize(find.byType(GlassDockNavBar)).height;
    expect(seen.padding.bottom, dockHeight);
    expect(seen.viewPadding.bottom, dockHeight);
    expect(dockHeight, kNavBarContentHeight + kSafeBottom);
  });

  testWidgets('a taller nav bar wins over the constant', (tester) async {
    // Simple mode's bar and any text-scaled dock are taller than the
    // constant; the measurement, not the constant, must be what is reserved.
    const tall = 150.0;
    final seen = await _pumpShell(
      tester,
      const SizedBox.expand(),
      navBar: Builder(
        builder: (ctx) => SizedBox(
          height: tall + MediaQuery.of(ctx).padding.bottom,
        ),
      ),
    );
    expect(seen.padding.bottom, tall + kSafeBottom);
  });

  testWidgets(
      'navBarTotalHeight() is dock + safe area under the dock, and safe '
      'area alone where there is no dock', (tester) async {
    _useDevice(tester);
    late double underDock;
    late double onRoot;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: NavBarInsetShell(
              navBar: _dock(),
              body: Builder(builder: (ctx) {
                underDock = navBarTotalHeight(ctx);
                return const SizedBox();
              }),
            ),
          ),
          Builder(builder: (ctx) {
            onRoot = navBarTotalHeight(ctx);
            return const SizedBox();
          }),
        ]),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(underDock, kNavBarContentHeight + kSafeBottom);
    expect(onRoot, kSafeBottom);
  });

  testWidgets(
      'a ListView with no explicit padding keeps its last row above the dock',
      (tester) async {
    // This is the framework convention the shell relies on: a padding-less
    // ListView applies MediaQuery.padding at its ends. New screens need
    // nothing more than this to be correct.
    await _pumpShell(
      tester,
      ListView(
        children: [
          for (var i = 0; i < 40; i++)
            SizedBox(height: 50, child: Text('row $i')),
        ],
      ),
    );
    await tester.fling(find.byType(ListView), const Offset(0, -5000), 4000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final dockTop = kScreen.height - (kNavBarContentHeight + kSafeBottom);
    expect(tester.getRect(find.text('row 39')).bottom,
        lessThanOrEqualTo(dockTop + 0.5),
        reason: 'the last row must scroll fully above the dock');
  });

  testWidgets('an inner Scaffold FAB floats above the dock on its own',
      (tester) async {
    // Scaffold lifts its FAB by viewPadding.bottom; with the dock injected
    // there, the per-screen `Padding(bottom: navBarTotalHeight)` wrappers
    // around FABs are redundant (and were double-counting the safe area).
    await _pumpShell(
      tester,
      Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
        body: const SizedBox.expand(),
      ),
    );
    final dockTop = kScreen.height - (kNavBarContentHeight + kSafeBottom);
    final fab = tester.getRect(find.byType(FloatingActionButton));
    expect(fab.bottom, lessThanOrEqualTo(dockTop),
        reason: 'FAB bottom ${fab.bottom} must clear the dock top $dockTop');
    // …and not float absurdly high either (single lift, not double).
    expect(fab.bottom, greaterThan(dockTop - 2 * kFloatingActionButtonMargin - 1));
  });

  testWidgets('a bottom sheet opened under the dock clears it via SafeArea',
      (tester) async {
    // Each tab is its own Navigator INSIDE the shell, so a sheet opened from
    // a tab page renders under the dock. A SafeArea (or a read of
    // padding.bottom) inside the sheet now lifts its content above it.
    await _pumpShell(
      tester,
      Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: ctx,
                builder: (_) => const SafeArea(
                  child: SizedBox(height: 40, child: Text('sheet action')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final dockTop = kScreen.height - (kNavBarContentHeight + kSafeBottom);
    expect(tester.getRect(find.text('sheet action')).bottom,
        lessThanOrEqualTo(dockTop + 0.5));
  });
}
