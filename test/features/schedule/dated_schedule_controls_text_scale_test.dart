// +112 (#124) — the new "+" editor controls and the day sheet action lay out
// without defects at 1.0 / 1.75 / 2.0 with Bold Text (the foundation matrix).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/widgets/dated_schedule_controls.dart';

import '../../helpers/text_scale_harness.dart';

void main() {
  testWidgets('mode toggle — Just this day / Repeats weekly', (tester) async {
    await expectNoTextScaleDefectsAcrossMatrix(
      tester,
      ScheduleModeToggle(
        mode: ScheduleEditorMode.justThisDay,
        onChanged: (_) {},
      ),
    );
  });

  testWidgets('date row', (tester) async {
    await expectNoTextScaleDefectsAcrossMatrix(
      tester,
      ScheduleDateRow(date: DateTime(2026, 10, 4), onChanged: (_) {}),
    );
  });

  testWidgets('add-for-this-day button', (tester) async {
    await expectNoTextScaleDefectsAcrossMatrix(
      tester,
      AddForThisDayButton(onPressed: () {}),
    );
  });

  testWidgets('solar note', (tester) async {
    await expectNoTextScaleDefectsAcrossMatrix(
      tester,
      const DatedScheduleNote(
        text: 'On Sunday, Oct 4, 2026, Sunset is 6:58 PM and Sunrise is '
            '7:05 AM. A one-night schedule uses the clock time.',
      ),
    );
  });
}
