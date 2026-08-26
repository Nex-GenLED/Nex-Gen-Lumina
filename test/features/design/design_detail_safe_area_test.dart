// Regression: the design detail action buttons must be fully visible and
// hit-testable ABOVE the glass dock, on a narrow/short device with a home
// indicator.
//
// The bug: DesignDetailScreen's ListView shipped with a flat `32` bottom
// padding. The dock is a Stack OVERLAY — MainScaffold renders it
// `Positioned(bottom: 0)` over a `Positioned.fill` branch host with
// `extendBody: true` (main_scaffold.dart:190-215) — so content extends under
// it and a scrollable must reserve its height itself. The last ~100px plus the
// device inset rendered beneath the dock, and the dock, being above in
// z-order, takes the taps in that band.
//
// ON WHAT THIS CAN AND CANNOT SIMULATE: a widget test has no iOS glass bar and
// no real home indicator. It can reproduce the two things that actually
// determine the outcome — the viewport size and the bottom inset that
// `navBarTotalHeight` reads out of MediaQuery — and it can assert geometry
// exactly. It cannot prove anything about the platform's own translucent bar
// rendering. The dock band is therefore modelled here from the same constant
// the real dock is laid out from (`kNavBarContentHeight` + inset), which is
// the closest the framework allows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/screens/design_detail_screen.dart';

/// iPhone SE (2nd/3rd gen) logical size — the narrowest/shortest class the app
/// supports, and the worst case for this bug.
const Size kPhoneSe = Size(375, 667);
const double kPhoneSeHeight = 667;

/// Home-indicator inset. 34 is the iPhone value with a home indicator; SE has
/// none, but pairing the SMALLEST height with a NON-ZERO inset is the harsher
/// combination and is what the regression must survive.
const double kHomeIndicatorInset = 34;

CustomDesign _design({int groupCount = 1, Map<String, dynamic>? composed}) =>
    CustomDesign(
      id: 'd1',
      name: 'Sunset Fade',
      description: 'a description',
      createdAt: DateTime(2026, 5, 29),
      updatedAt: DateTime(2026, 6, 1),
      ownerId: 'u',
      brightness: 180,
      channels: [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          included: true,
          effectId: 12,
          colorGroups: [
            for (var i = 0; i < groupCount; i++)
              LedColorGroup(
                  startLed: i * 5,
                  endLed: i * 5 + 4,
                  color: const [255, 80, 0, 0]),
          ],
          ledCount: groupCount * 5,
        ),
      ],
      composedPattern: composed,
    );

Future<void> _pump(WidgetTester tester, CustomDesign design) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = kPhoneSe;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      designsStreamProvider.overrideWith((_) => Stream.value([design])),
      designByIdProvider(design.id).overrideWith((_) async => design),
    ],
    child: MaterialApp(
      home: MediaQuery(
        // The inset navBarTotalHeight() reads. Injecting it here is what makes
        // the assertion meaningful — without it the helper returns the bare
        // dock height and the test would pass on a device that still clips.
        data: const MediaQueryData(
          size: kPhoneSe,
          padding: EdgeInsets.only(bottom: kHomeIndicatorInset),
          viewPadding: EdgeInsets.only(bottom: kHomeIndicatorInset),
        ),
        child: DesignDetailScreen(designId: design.id),
      ),
    ),
  ));
  await tester.pumpAndSettle();

  // The action block sits at the END of the list, below the fold on this
  // viewport. Fling to the bottom once so all five are laid out together —
  // which is also the state the user is in when they tap them.
  await tester.fling(find.byType(ListView), const Offset(0, -1200), 3000);
  await tester.pumpAndSettle();
}

/// On-screen rect of the action button labelled [label], with the list already
/// scrolled to its end by [_pump].
Rect _rectOf(WidgetTester tester, String label) {
  // byWidgetPredicate, NOT byType: `find.byType` matches the exact runtime
  // type, and these are FilledButton / OutlinedButton — subclasses of the
  // abstract ButtonStyleButton, which byType would never match.
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  expect(finder, findsOneWidget,
      reason: '"$label" must be laid out and reachable at the list end');
  return tester.getRect(finder);
}

void main() {
  const actions = ['Apply to Lights', 'Edit', 'Rename', 'Duplicate', 'Delete'];

  group('action buttons on a narrow device with a bottom inset', () {
    testWidgets('no two action buttons overlap', (tester) async {
      await _pump(tester, _design());

      final rects = <String, Rect>{};
      for (final label in actions) {
        rects[label] = _rectOf(tester, label);
      }

      // Pairwise: an overlap is what makes a tap land on the wrong control,
      // which is the reported symptom (pressing Edit, Duplicate reacts).
      for (final a in actions) {
        for (final b in actions) {
          if (a == b) continue;
          final overlap = rects[a]!.intersect(rects[b]!);
          expect(overlap.isEmpty || overlap.width <= 0 || overlap.height <= 0,
              isTrue,
              reason: '"$a" ${rects[a]} overlaps "$b" ${rects[b]} — '
                  'overlapping hit targets are how a tap on one fires the '
                  'other');
        }
      }
    });

    testWidgets('every action clears the glass dock band', (tester) async {
      await _pump(tester, _design());

      // The dock occupies the bottom `kNavBarContentHeight + inset` of the
      // viewport, laid out from the same constant the real dock uses.
      const dockTop =
          kPhoneSeHeight - (kNavBarContentHeight + kHomeIndicatorInset);

      for (final label in actions) {
        final r = _rectOf(tester, label);
        expect(r.bottom, lessThanOrEqualTo(dockTop + 0.5),
            reason: '"$label" bottom ${r.bottom} extends into the dock band '
                '(starts at $dockTop) — it would render under the dock and '
                'the dock, being above in z-order, would take the tap');
      }
    });

    testWidgets('the scrollable reserves the dock height, not a flat inset',
        (tester) async {
      await _pump(tester, _design());

      final listView = tester.widget<ListView>(find.byType(ListView));
      final pad = listView.padding as EdgeInsets;

      // 100 (kNavBarContentHeight) + 34 (inset) + 16 breathing room.
      expect(pad.bottom,
          greaterThanOrEqualTo(kNavBarContentHeight + kHomeIndicatorInset),
          reason: 'a flat bottom padding is the bug: it does not scale with '
              'the device inset and does not reserve the dock');
    });
  });

  group('AI-composed designs — Edit is disabled but still not overlapping', () {
    testWidgets('the disabled Edit button keeps its own hit box', (tester) async {
      await _pump(tester, _design(composed: const {'source_intent': 1}));

      // The explanatory note renders between the two rows in this case, which
      // is the layout most likely to push the last row down into the dock.
      final edit = _rectOf(tester, 'Edit');
      final del = _rectOf(tester, 'Delete');
      expect(edit.intersect(del).isEmpty || edit.intersect(del).height <= 0,
          isTrue);

      const dockTop =
          kPhoneSeHeight - (kNavBarContentHeight + kHomeIndicatorInset);
      expect(del.bottom, lessThanOrEqualTo(dockTop + 0.5));
    });
  });
}
