import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// A lightweight HSV color wheel.
/// Hue = angle, Saturation = radius, Value fixed to 1 (brightness slider controls value).
class NeonColorWheel extends StatefulWidget {
  final double size;
  final Color color;
  final ValueChanged<Color> onChanged;
  const NeonColorWheel({super.key, required this.size, required this.color, required this.onChanged});

  @override
  State<NeonColorWheel> createState() => _NeonColorWheelState();
}

class _NeonColorWheelState extends State<NeonColorWheel> {
  Offset? _lastPos;

  @override
  Widget build(BuildContext context) {
    final radius = widget.size / 2;
    final hsv = HSVColor.fromColor(widget.color);
    final angle = hsv.hue * math.pi / 180.0;
    final sat = hsv.saturation;
    final cx = radius + math.cos(angle) * sat * (radius - 12);
    final cy = radius + math.sin(angle) * sat * (radius - 12);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(children: [
        // Wheel
        CustomPaint(size: Size(widget.size, widget.size), painter: _WheelPainter()),
        // Glow ring
        IgnorePointer(
          ignoring: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.1), blurRadius: 24, spreadRadius: 2),
                BoxShadow(color: Colors.pinkAccent.withValues(alpha: 0.08), blurRadius: 36, spreadRadius: 2),
              ],
            ),
          ),
        ),
        // Gesture layer
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanDown: (d) => _updateFromLocal(d.localPosition, radius),
            onPanStart: _handlePan,
            onPanUpdate: _handlePan,
            onPanEnd: (_) => _lastPos = null,
            onTapDown: (d) => _updateFromLocal(d.localPosition, radius),
            child: const SizedBox.expand(),
          ),
        ),
        // Thumb
        Positioned(
          left: cx - 12,
          top: cy - 12,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), color: widget.color),
          ),
        ),
      ]),
    );
  }

  void _handlePan(details) {
    final size = widget.size;
    final radius = size / 2;
    if (details is DragStartDetails) {
      _updateFromLocal(details.localPosition, radius);
    } else if (details is DragUpdateDetails) {
      _updateFromLocal(details.localPosition, radius);
    }
  }

  void _updateFromLocal(Offset local, double radius) {
    final center = Offset(radius, radius);
    final v = local - center;
    double r = v.distance;
    final maxR = radius - 12;
    if (r > maxR) r = maxR;
    final angle = math.atan2(v.dy, v.dx);
    final deg = (angle * 180.0 / math.pi + 360.0) % 360.0;
    final s = (r / maxR).clamp(0.0, 1.0);
    final hsv = HSVColor.fromAHSV(1.0, deg, s, 1.0);
    widget.onChanged(hsv.toColor());
  }

  @override
  void initState() {
    super.initState();
  }
}

class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, radius);

    // Hue ring base
    final rect = Rect.fromCircle(center: center, radius: radius - 1);
    final huePaint = Paint()
      ..shader = SweepGradient(colors: [
        const HSVColor.fromAHSV(1, 0, 1, 1).toColor(),
        const HSVColor.fromAHSV(1, 60, 1, 1).toColor(),
        const HSVColor.fromAHSV(1, 120, 1, 1).toColor(),
        const HSVColor.fromAHSV(1, 180, 1, 1).toColor(),
        const HSVColor.fromAHSV(1, 240, 1, 1).toColor(),
        const HSVColor.fromAHSV(1, 300, 1, 1).toColor(),
        const HSVColor.fromAHSV(1, 360, 1, 1).toColor(),
      ]).createShader(rect);
    canvas.drawCircle(center, radius - 1, huePaint);

    // Saturation mask (white center to transparent edge)
    final satPaint = Paint()
      ..shader = RadialGradient(colors: [Colors.white, Colors.white.withValues(alpha: 0)], stops: const [0.0, 1.0]).createShader(rect);
    canvas.drawCircle(center, radius - 1, satPaint);

    // Edge ring for definition
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.2);
    canvas.drawCircle(center, radius - 1, edge);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
