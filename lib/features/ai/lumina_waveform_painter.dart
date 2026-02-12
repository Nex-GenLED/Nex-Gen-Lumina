import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// CustomPainter that draws animated sine waves responding to microphone amplitude.
///
/// Renders 3 overlapping sine waves with varying phase, frequency, and opacity
/// to create a fluid audio visualization. The [amplitude] parameter (0.0–1.0)
/// controls wave height, simulating microphone input levels.
class LuminaWaveformPainter extends CustomPainter {
  /// Current amplitude from microphone input (0.0 = silent, 1.0 = max).
  final double amplitude;

  /// Animation phase value (typically from an AnimationController, 0.0–1.0).
  final double phase;

  /// Primary color for the waveform (defaults to NexGen cyan).
  final Color color;

  LuminaWaveformPainter({
    required this.amplitude,
    required this.phase,
    this.color = NexGenPalette.cyan,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    // Clamp amplitude so we always have a subtle idle wave
    final amp = max(0.05, amplitude);

    // Draw 3 overlapping waves with decreasing opacity
    for (int i = 0; i < 3; i++) {
      final waveAmp = amp * size.height * 0.35 * (1.0 - i * 0.25);
      final frequency = 1.5 + i * 0.5;
      final phaseOffset = i * 0.8;
      final opacity = (0.8 - i * 0.25).clamp(0.15, 1.0);

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..strokeWidth = 2.5 - i * 0.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      final steps = size.width.toInt();

      for (int x = 0; x <= steps; x++) {
        final normalizedX = x / steps;
        // Window function: fade at edges for smooth start/end
        final window = sin(normalizedX * pi);
        final y = centerY +
            sin((normalizedX * frequency * 2 * pi) +
                    (phase * 2 * pi) +
                    phaseOffset) *
                waveAmp *
                window;

        if (x == 0) {
          path.moveTo(x.toDouble(), y);
        } else {
          path.lineTo(x.toDouble(), y);
        }
      }

      canvas.drawPath(path, paint);
    }

    // Draw a subtle center line at idle
    if (amplitude < 0.1) {
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.15)
        ..strokeWidth = 1.0;
      canvas.drawLine(
        Offset(0, centerY),
        Offset(size.width, centerY),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(LuminaWaveformPainter oldDelegate) =>
      oldDelegate.amplitude != amplitude || oldDelegate.phase != phase;
}
