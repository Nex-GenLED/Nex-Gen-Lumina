// Build 128, Step 1 — the dated-entry detail sheet under the glass dock.
//
// On an iPhone 15 Pro (393 x 852 pt) at the default text size the detail
// sheet for a dated calendar entry hid "Edit This Day" and "Delete This Entry":
// `showScheduleDetailSheetForEntry` opened a modal bottom sheet on the BRANCH
// navigator (a sibling of the dock, beneath it in z-order) without
// `isScrollControlled`, so its height was capped at 9/16 of the screen and the
// body — a plain Column with Edit and Delete LAST — was clipped, with the dock
// covering what was left.
//
// These tests pump the real sheet under the real GlassDockNavBar, exactly as
// MainScaffold hosts it (largeTextHost), at 393 x 852 for text scales 1.0, 1.3
// and 2.0 and across the +120 large-text matrix, and assert for both buttons:
//   * the button is fully on screen;
//   * its rect does not overlap the dock's rect;
//   * a hit test at its centre reaches the button (nothing above it takes the
//     tap).
// Written first and failing at de4766b; see docs/release/build_128_candidate.md
// section 4 for the failures.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/light_effect_animator.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart';
import 'package:nexgen_command/widgets/navigation/glass_dock_nav_bar.dart';

import '../../helpers/large_text_matrix.dart';
import '../../helpers/text_scale_harness.dart';

const _kEdit = 'Edit This Day';
const _kDelete = 'Delete This Entry';
const _kDateKey = '2026-11-20';

/// iPhone 15 Pro: 393 x 852 pt at 3x, 59 pt status area, 34 pt home indicator.
const _kIPhone15Pro = (
  size: Size(393, 852),
  dpr: 3.0,
  safe: EdgeInsets.only(top: 59, bottom: 34),
);

TextScaleProfile _iphone15Pro(double scale) => TextScaleProfile(
      textScale: scale,
      boldText: false,
      screenSize: _kIPhone15Pro.size,
      devicePixelRatio: _kIPhone15Pro.dpr,
      safeArea: _kIPhone15Pro.safe,
    );

/// A dated entry Lumina wrote (sourceTag lumina_ai, type user), as on the
/// customer's phone on 2026-11-11.
CalendarEntry _luminaEntry() => const CalendarEntry(
      entryId: 'lumina_1762819200000_0',
      dateKey: _kDateKey,
      patternName: 'Chiefs Game Night',
      color: Color(0xFFE31837),
      onTime: '18:00',
      offTime: '23:00',
      brightness: 85,
      type: CalendarEntryType.user,
      autopilot: true,
      sourceTag: CalendarEntrySourceTag.luminaAi,
      note: 'Lumina: Solid',
    );

/// A page that opens the detail sheet for [entry] on its first frame, through
/// the same function the Schedule tab's cards and the day sheet call.
class _OpensDetail extends ConsumerStatefulWidget {
  const _OpensDetail(this.entry);
  final CalendarEntry entry;

  @override
  ConsumerState<_OpensDetail> createState() => _OpensDetailState();
}

class _OpensDetailState extends ConsumerState<_OpensDetail> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final e = widget.entry;
      showScheduleDetailSheetForEntry(
        context,
        colors: [e.color!],
        effectType: EffectType.solid,
        speed: 0.5,
        brightness: e.brightness / 100.0,
        patternName: e.patternName,
        effectName: 'Solid',
        onTime: e.onTime,
        offTime: e.offTime,
        brightnessPercent: e.brightness,
        source: 'AI-Generated',
        editable: true,
        calEntry: e,
        dateKey: e.dateKey,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

Widget _host() => largeTextHost(
      overrides: const <Override>[],
      page: _OpensDetail(_luminaEntry()),
      dock: 1,
    );

/// `TextButton.icon` builds a private TextButton subclass, so match by type
/// predicate rather than `find.byType`.
Finder _button(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is TextButton),
    );

/// The three checks for one button, with the reason spelled out so a failure
/// says WHICH of the three went wrong at which cell.
void _expectReachable(WidgetTester tester, String label, String cell) {
  final button = _button(label);
  expect(button, findsOneWidget, reason: '$cell: "$label" is not in the tree');

  final rect = tester.getRect(button);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.top >= 0 && rect.bottom <= screen.height, isTrue,
      reason: '$cell: "$label" at $rect is not fully on the '
          '${screen.width.round()}x${screen.height.round()} screen');

  final dock = tester.getRect(find.byType(GlassDockNavBar));
  expect(rect.overlaps(dock), isFalse,
      reason: '$cell: "$label" at $rect is covered by the dock at $dock');

  final result = HitTestResult();
  tester.binding.hitTestInView(result, rect.center, tester.view.viewId);
  final target = tester.renderObject(button);
  expect(result.path.any((entry) => entry.target == target), isTrue,
      reason: '$cell: a tap at ${rect.center} does not reach "$label" — '
          'something above it (the dock, or a clip) takes the tap');
}

Future<void> _pumpSheet(WidgetTester tester, TextScaleProfile profile) async {
  await pumpAtTextScale(
    tester,
    _host(),
    profile: profile,
    host: TextScaleHost.none,
    frames: 6,
    settle: const Duration(milliseconds: 1800),
  );
  expect(find.byType(BottomSheet), findsOneWidget,
      reason: 'the detail sheet must be open before anything is measured');
}

Future<void> _tearDownSheet(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  group('dated-entry detail sheet, iPhone 15 Pro (393 x 852)', () {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets(
          'Edit and Delete are on screen, clear of the dock and '
          'tappable at text scale $scale', (tester) async {
        final cell = '393x852@$scale';
        await _pumpSheet(tester, _iphone15Pro(scale));
        _expectReachable(tester, _kEdit, cell);
        _expectReachable(tester, _kDelete, cell);
        await _tearDownSheet(tester);
      });
    }
  });

  group('dated-entry detail sheet, the +120 large-text matrix', () {
    testWidgets(
        'Edit and Delete are on screen, clear of the dock and '
        'tappable at every cell', (tester) async {
      for (final (tag, profile) in largeTextProfiles()) {
        await _pumpSheet(tester, profile);
        _expectReachable(tester, _kEdit, tag);
        _expectReachable(tester, _kDelete, tag);
        await _tearDownSheet(tester);
      }
    });

    testWidgets('no RenderFlex overflow at any cell', (tester) async {
      await expectNoOverflowAcrossLargeTextMatrix(
        tester,
        _host,
        label: 'dated-entry detail sheet',
        frames: 6,
        settle: const Duration(milliseconds: 1800),
      );
    });
  });
}
