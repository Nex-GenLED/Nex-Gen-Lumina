// M13 (followup N5) — EditPatternScreen's "Color Picker" tab is the app's
// colour WHEEL, and it does not lose the hue.
//
// It was three sliders (hue bar + Sat + Val) that re-derived HSV from the RGB
// colour on every build: drag Sat to 0 and the hue snapped 200° → 0°; drag Val
// to 0 and back and a blue came back WHITE.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/widgets/hsv_wheel_picker.dart';
import 'package:nexgen_command/features/wled/widgets/neon_color_wheel.dart';

/// Mimics a parent that stores ONLY the RGB colour (as EditPatternScreen does).
class _Host extends StatefulWidget {
  const _Host(this.initial);
  final Color initial;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late Color color = widget.initial;

  /// The parent choosing a colour itself (another swatch, an RGB slider…).
  void choose(Color c) => setState(() => color = c);
  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: HsvWheelPicker(color: color, onChanged: (c) => setState(() => color = c)),
          ),
        ),
      );
}

void main() {
  final blue = const HSVColor.fromAHSV(1, 200, 0.8, 1).toColor();

  Future<(HsvWheelPickerState, _HostState)> pump(WidgetTester tester, Color c) async {
    await tester.pumpWidget(_Host(c));
    return (
      tester.state<HsvWheelPickerState>(find.byType(HsvWheelPicker)),
      tester.state<_HostState>(find.byType(_Host)),
    );
  }

  testWidgets('it IS a colour wheel, with a single brightness control', (tester) async {
    await pump(tester, blue);
    expect(find.byType(NeonColorWheel), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget, reason: 'brightness only — no Sat/Val/Hue sliders');
  });

  testWidgets('brightness to 0 and back: the blue comes back BLUE', (tester) async {
    final (picker, host) = await pump(tester, blue);
    picker.setValue(0);
    await tester.pump();
    expect(host.color, const Color(0xFF000000));
    expect(picker.hsv.hue, closeTo(200, 0.5), reason: 'was 0 — hue lost in RGB black');
    expect(picker.hsv.saturation, closeTo(0.8, 0.01));

    picker.setValue(1);
    await tester.pump();
    final back = HSVColor.fromColor(host.color);
    expect(back.hue, closeTo(200, 1.0));
    expect(back.saturation, closeTo(0.8, 0.02), reason: 'was WHITE');
  });

  testWidgets('saturation to 0 (wheel centre) and back out: hue is kept', (tester) async {
    final (picker, host) = await pump(tester, blue);
    picker.setHueSaturation(0, 0); // the wheel has no hue to report at its centre
    await tester.pump();
    expect(HSVColor.fromColor(host.color).saturation, 0);
    expect(picker.hsv.hue, closeTo(200, 0.5), reason: 'was snapping to 0° (red)');
  });

  testWidgets('moving the wheel keeps the chosen brightness', (tester) async {
    final (picker, host) = await pump(tester, blue);
    picker.setValue(0.4);
    await tester.pump();
    picker.setHueSaturation(120, 1); // drag to green
    await tester.pump();
    final hsv = HSVColor.fromColor(host.color);
    expect(hsv.hue, closeTo(120, 1.5));
    expect(hsv.value, closeTo(0.4, 0.02), reason: 'the wheel reports value 1; ours is kept');
  });

  testWidgets('a colour chosen OUTSIDE the picker re-seeds it', (tester) async {
    final (picker, host) = await pump(tester, blue);
    // e.g. the user taps another swatch / a Common Color / moves an RGB slider.
    host.choose(const Color(0xFFFF0000));
    await tester.pump();
    expect(picker.hsv.hue, closeTo(0, 0.5));
    expect(picker.hsv.saturation, closeTo(1, 0.01));
    // …but an outside BLACK keeps the wheel where it was instead of snapping.
    host.choose(const Color(0xFF000000));
    await tester.pump();
    expect(picker.hsv.value, 0);
    expect(picker.hsv.saturation, closeTo(1, 0.01));
  });

  testWidgets('dragging on the wheel changes the colour', (tester) async {
    final (_, host) = await pump(tester, blue);
    final before = host.color;
    final wheel = find.byType(NeonColorWheel);
    final c = tester.getCenter(wheel);
    await tester.tapAt(c + const Offset(60, 0)); // east of centre = hue ~0°
    await tester.pump();
    expect(host.color, isNot(before));
  });
}
