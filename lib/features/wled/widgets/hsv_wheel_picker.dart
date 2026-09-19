import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/widgets/neon_color_wheel.dart';
import 'package:nexgen_command/theme.dart';

/// The app's colour WHEEL ([NeonColorWheel]: hue = angle, saturation = radius)
/// plus one brightness control — the same pairing the Current Colors editor
/// and the Color Sequence builder use.
///
/// It HOLDS the colour as HSV. RGB cannot carry a hue once saturation or value
/// reaches 0, so a picker that re-derives HSV from the RGB colour on every
/// build loses the user's hue the moment a control touches zero: the old
/// "Color Picker" tab (a hue bar + Sat + Val sliders) snapped 200° → 0° when
/// Sat hit 0, and a blue dragged to Val 0 and back came back WHITE.
///
/// [color] is the source of truth from the parent. A change the parent makes
/// itself (another swatch selected, a preset colour tapped, RGB sliders) is
/// recognised — it differs from the last colour this widget emitted — and
/// re-seeds the wheel.
class HsvWheelPicker extends StatefulWidget {
  const HsvWheelPicker({
    super.key,
    required this.color,
    required this.onChanged,
    this.maxWheelSize = 260,
  });

  final Color color;
  final ValueChanged<Color> onChanged;
  final double maxWheelSize;

  @override
  State<HsvWheelPicker> createState() => HsvWheelPickerState();
}

class HsvWheelPickerState extends State<HsvWheelPicker> {
  late HSVColor _hsv;
  Color? _emitted;

  /// The held colour (exposed for tests).
  HSVColor get hsv => _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.color);
  }

  @override
  void didUpdateWidget(covariant HsvWheelPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.color == _emitted || widget.color == oldWidget.color) return;
    // Changed from outside. A colourless colour (black / grey / white) has no
    // hue of its own — keep the wheel where the user left it rather than
    // snapping to red.
    var fresh = HSVColor.fromColor(widget.color);
    if (fresh.saturation == 0 || fresh.value == 0) {
      fresh = fresh.withHue(_hsv.hue);
      if (fresh.value == 0) fresh = fresh.withSaturation(_hsv.saturation);
    }
    _hsv = fresh;
  }

  void _emit(HSVColor next) {
    final color = next.toColor();
    setState(() {
      _hsv = next;
      _emitted = color;
    });
    widget.onChanged(color);
  }

  /// Hue + saturation from the wheel; brightness is kept.
  void setHueSaturation(double hue, double saturation) => _emit(HSVColor.fromAHSV(
      1, saturation == 0 ? _hsv.hue : hue, saturation.clamp(0.0, 1.0), _hsv.value));

  /// Brightness from the slider; hue and saturation are kept.
  void setValue(double value) => _emit(_hsv.withValue(value.clamp(0.0, 1.0)));

  @override
  Widget build(BuildContext context) {
    // The wheel places its thumb from the colour it is given and always shows
    // value 1 — hand it the full-brightness colour so the thumb stays put
    // while brightness is dragged all the way down.
    final wheelColor =
        HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(builder: (context, c) {
          final size = c.maxWidth.clamp(160.0, widget.maxWheelSize);
          return Center(
            child: NeonColorWheel(
              size: size,
              color: wheelColor,
              onChanged: (picked) {
                final p = HSVColor.fromColor(picked);
                setHueSaturation(p.hue, p.saturation);
              },
            ),
          );
        }),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.brightness_6,
                color: NexGenPalette.textMedium, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                key: const ValueKey('hsv-wheel-brightness'),
                value: _hsv.value,
                min: 0,
                max: 1,
                activeColor: NexGenPalette.cyan,
                onChanged: setValue,
              ),
            ),
            Container(
              key: const ValueKey('hsv-wheel-swatch'),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                shape: BoxShape.circle,
                border: Border.all(color: NexGenPalette.line),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
