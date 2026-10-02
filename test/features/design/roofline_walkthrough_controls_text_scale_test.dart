// +113 — the walkthrough's new controls (section rows with merge-delete and
// their blocker text, Undo / Start over, the strip-length notice) survive the
// accessibility matrix: 1.0, 1.75 and 2.0 text scale, all with Bold Text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/roofline_walkthrough_widgets.dart';
import 'package:nexgen_command/theme.dart';

import '../../helpers/text_scale_harness.dart';

Widget _card(List<Widget> children) => Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );

void main() {
  testWidgets('section rows — enabled, and disabled with a reason', (tester) async {
    await expectNoTextScaleDefectsAcrossMatrix(
      tester,
      _card([
        RooflineSectionRow(
          label: 'Run 1',
          lights: 'lights 1–42',
          onMerge: () {},
        ),
        const RooflineSectionRow(
          label: 'Corner',
          lights: 'light 43',
          onMerge: null,
          blocker: 'This section comes from the saved map. Save the channel '
              'once to rebuild it, then remove it.',
        ),
        const RooflineSectionRow(
          label: 'Run 2',
          lights: 'lights 44–45',
          onMerge: null,
          blocker: 'This run sits between marked features. Remove the corner '
              'or peak next to it to merge them.',
        ),
      ]),
    );
  });

  testWidgets('Undo / Start over — enabled and disabled with reason', (tester) async {
    await expectNoTextScaleDefectsAcrossMatrix(
      tester,
      _card([
        WalkthroughMarkActions(onUndo: () {}, onStartOver: () {}),
        const SizedBox(height: 12),
        const WalkthroughMarkActions(
          onUndo: null,
          onStartOver: null,
          disabledReason: 'No marks on this channel yet — it is one straight run.',
        ),
      ]),
    );
  });

  testWidgets('strip-length notice', (tester) async {
    await expectNoTextScaleDefectsAcrossMatrix(
      tester,
      _card([
        const ChannelLengthNotice(channelNumber: 2, mapped: 57, strip: 104),
      ]),
    );
  });

  test('startOverDescription names what goes', () {
    expect(
      startOverDescription(
        channelNumber: 2,
        lights: 45,
        marks: (corners: 2, peaks: 1, splits: 1, other: 0),
      ),
      'This removes 2 corners, 1 peak, 1 run split on channel 2. The channel '
      'becomes one straight run of 45 lights. Nothing is saved until you tap '
      'Save.',
    );
    expect(
      startOverDescription(
          channelNumber: 1, lights: 44, marks: (corners: 0, peaks: 0, splits: 0, other: 0)),
      contains('every mark'),
    );
  });
}
