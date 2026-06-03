// test/features/wled/neon_color_wheel_test.dart
//
// Interaction tests for [NeonColorWheel] — the HSV color wheel used in the
// color-picker sheets. The wheel previously responded only to a direct tap;
// finger-drags were stolen by the enclosing modal sheet's drag-to-dismiss
// recognizer, so the picker didn't track the finger. The fix routes tracking
// through a raw [Listener] (pointer events bypass the gesture arena), so both
// tap-to-set and continuous drag always reach the wheel.
//
// These tests drive raw pointer gestures and assert the onChanged callback
// fires continuously across a drag, that a tap still sets a color, and that a
// drag past the rim clamps saturation to the edge rather than overshooting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/widgets/neon_color_wheel.dart';

void main() {
  const size = 220.0;

  Future<List<Color>> _pumpWheel(WidgetTester tester) async {
    final emitted = <Color>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: NeonColorWheel(
              size: size,
              color: const Color(0xFFFF0000),
              onChanged: emitted.add,
            ),
          ),
        ),
      ),
    );
    return emitted;
  }

  testWidgets('drag across the wheel updates the color continuously', (
    tester,
  ) async {
    final emitted = await _pumpWheel(tester);
    final center = tester.getCenter(find.byType(NeonColorWheel));

    // Pointer DOWN at center, then move through several rim positions. A raw
    // Listener delivers every pointer-move, so each step should emit a color.
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.moveTo(center + const Offset(70, 0)); // right  → ~red
    await tester.pump();
    await gesture.moveTo(center + const Offset(0, 70)); // down   → ~90°
    await tester.pump();
    await gesture.moveTo(center + const Offset(-70, 0)); // left  → ~180°
    await tester.pump();
    await gesture.up();
    await tester.pump();

    // Continuous tracking: the down + three moves each produced a color.
    expect(emitted.length, greaterThanOrEqualTo(4),
        reason: 'every pointer-move during the drag should emit a color');

    // The drag visited three distinct hue regions — confirm the picker
    // actually followed the finger rather than snapping once.
    final hues = <double>{
      HSVColor.fromColor(emitted[emitted.length - 3]).hue.roundToDouble(),
      HSVColor.fromColor(emitted[emitted.length - 2]).hue.roundToDouble(),
      HSVColor.fromColor(emitted.last).hue.roundToDouble(),
    };
    expect(hues.length, greaterThanOrEqualTo(3),
        reason: 'distinct drag positions should yield distinct hues');
  });

  testWidgets('a single tap still sets a color', (tester) async {
    final emitted = await _pumpWheel(tester);
    final center = tester.getCenter(find.byType(NeonColorWheel));

    await tester.tapAt(center + const Offset(70, 0)); // right of center → red
    await tester.pump();

    expect(emitted, isNotEmpty, reason: 'tap-to-set must still work');
    final hue = HSVColor.fromColor(emitted.last).hue;
    expect(hue, closeTo(0, 12), reason: 'right of center maps to red (~0°)');
  });

  testWidgets('dragging past the rim clamps saturation to the edge', (
    tester,
  ) async {
    final emitted = await _pumpWheel(tester);
    final center = tester.getCenter(find.byType(NeonColorWheel));

    final gesture = await tester.startGesture(center);
    // Move far outside the wheel bounds — saturation must clamp to 1.0, not
    // overshoot or break.
    await gesture.moveTo(center + const Offset(1000, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final sat = HSVColor.fromColor(emitted.last).saturation;
    expect(sat, closeTo(1.0, 0.001),
        reason: 'a drag beyond the rim clamps to full saturation');
  });
}
