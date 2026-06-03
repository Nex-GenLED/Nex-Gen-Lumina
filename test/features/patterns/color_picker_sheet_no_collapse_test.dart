import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/patterns/color_sequence_builder.dart';
import 'package:nexgen_command/features/wled/widgets/neon_color_wheel.dart';

// #9 regression — the color-picker sheet must NOT collapse/dismiss when the
// user drags (or flings) on the NeonColorWheel; the wheel moves the picker and
// the sheet only dismisses via its explicit Cancel/Select control.
//
// The host (ColorSequenceBuilder._showColorPickerDialog) presents the wheel in
// a PLAIN showModalBottomSheet with enableDrag:false (7411fff). A companion
// probe established that on a plain modal enableDrag:false defeats even a
// high-velocity fling (whereas enableDrag:true dismisses on a fling — the
// original #9 — and a DraggableScrollableSheet collapses regardless of
// enableDrag). current_colors_editor_screen presents the same wheel in the
// identical plain-modal-with-enableDrag:false shape.
void main() {
  Future<void> openPicker(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ColorSequenceBuilder(
            baseColors: const [
              [255, 0, 0]
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    await tester.tap(find.text('1')); // first color slot
    await tester.pumpAndSettle();
    expect(find.text('Choose Color'), findsOneWidget);
  }

  testWidgets('a slow downward drag on the wheel does not dismiss the sheet',
      (tester) async {
    await openPicker(tester);
    await tester.drag(find.byType(NeonColorWheel), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Choose Color'), findsOneWidget,
        reason: 'a wheel drag must not collapse the picker sheet');
  });

  testWidgets('a high-velocity downward fling on the wheel does not dismiss '
      'the sheet (the original #9 fling path)', (tester) async {
    await openPicker(tester);
    await tester.fling(find.byType(NeonColorWheel), const Offset(0, 500), 2000);
    await tester.pumpAndSettle();
    expect(find.text('Choose Color'), findsOneWidget,
        reason: 'enableDrag:false must defeat even a fling on a plain modal');
  });

  testWidgets('the sheet still dismisses via its Cancel control', (tester) async {
    await openPicker(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Choose Color'), findsNothing);
  });
}
