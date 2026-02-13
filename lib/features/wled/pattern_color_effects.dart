import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/wled_models.dart' show kEffectNames;
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/wled/pattern_library_pages.dart';

/// Bottom sheet for picking a solid color when using Solid effect.
class SolidColorPickerSheet extends StatelessWidget {
  final List<Color> colors;
  const SolidColorPickerSheet({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette, color: NexGenPalette.cyan, size: 20),
              const SizedBox(width: 8),
              Text(
                'Choose Solid Color',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: NexGenPalette.textHigh,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Solid effect displays a single color. Select which color to use:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: NexGenPalette.textMedium,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: colors.map((color) => _ColorPickerTile(
              color: color,
              onTap: () => Navigator.pop(context, color),
            )).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet for assigning colors to effect slots.
class ColorAssignmentSheet extends StatefulWidget {
  final List<Color> availableColors;
  final int slots;
  final int effectId;
  const ColorAssignmentSheet({
    super.key,
    required this.availableColors,
    required this.slots,
    required this.effectId,
  });

  @override
  State<ColorAssignmentSheet> createState() => _ColorAssignmentSheetState();
}

class _ColorAssignmentSheetState extends State<ColorAssignmentSheet> {
  late List<Color> _assignedColors;

  @override
  void initState() {
    super.initState();
    // Pre-fill with first N colors
    _assignedColors = widget.availableColors.take(widget.slots).toList();
    // Pad if needed
    while (_assignedColors.length < widget.slots) {
      _assignedColors.add(widget.availableColors.first);
    }
  }

  String _getSlotLabel(int index) {
    switch (index) {
      case 0: return 'Primary';
      case 1: return 'Secondary';
      case 2: return 'Accent';
      default: return 'Color ${index + 1}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectName = kEffectNames[widget.effectId] ?? 'Effect ${widget.effectId}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: NexGenPalette.cyan, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Assign Colors for $effectName',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'This effect uses ${widget.slots} color${widget.slots > 1 ? 's' : ''}. Assign colors to each slot:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: NexGenPalette.textMedium,
            ),
          ),
          const SizedBox(height: 16),
          // Slot assignment rows
          ...List.generate(widget.slots, (slotIndex) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      _getSlotLabel(slotIndex),
                      style: const TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: widget.availableColors.map((color) {
                          final isSelected = _assignedColors[slotIndex] == color;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _assignedColors[slotIndex] = color;
                              });
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
                                  width: isSelected ? 3 : 1,
                                ),
                                boxShadow: isSelected ? [
                                  BoxShadow(
                                    color: NexGenPalette.cyan.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ] : null,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          // Preview strip
          Container(
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(colors: _assignedColors),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _assignedColors),
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                  ),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Color picker tile for the solid color picker.
class _ColorPickerTile extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _ColorPickerTile({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.touch_app, color: Colors.white54, size: 20),
        ),
      ),
    );
  }
}

/// Wrapper to keep LiveGradientStrip lightweight in item cards.
class _ItemLiveGradient extends StatelessWidget {
  final List<Color> colors;
  final double speed;
  const _ItemLiveGradient({required this.colors, required this.speed});

  @override
  Widget build(BuildContext context) => LiveGradientStrip(colors: colors, speed: speed);
}

/// Realistic effect preview that animates based on the WLED effect type.
/// Shows users what the effect will look like on their lighting system.
class EffectPreviewStrip extends StatefulWidget {
  final List<Color> colors;
  final int effectId;
  final double speed;

  const EffectPreviewStrip({
    super.key,
    required this.colors,
    required this.effectId,
    this.speed = 128,
  });

  @override
  State<EffectPreviewStrip> createState() => _EffectPreviewStripState();
}

class _EffectPreviewStripState extends State<EffectPreviewStrip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _twinkleOpacities = [];
  final List<int> _twinkleColorIndices = [];

  @override
  void initState() {
    super.initState();
    // Map speed (0-255) to animation duration
    final durationMs = (3000 - (widget.speed / 255) * 2500).clamp(500, 5000).round();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );

    // Initialize twinkle state for popcorn/sparkle effects
    for (int i = 0; i < 20; i++) {
      _twinkleOpacities.add(0.0);
      _twinkleColorIndices.add(i % widget.colors.length);
    }

    if (widget.effectId != 0) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _EffectPainter(
            colors: widget.colors,
            effectId: widget.effectId,
            progress: _controller.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

/// Custom painter that draws realistic effect previews
class _EffectPainter extends CustomPainter {
  final List<Color> colors;
  final int effectId;
  final double progress;

  _EffectPainter({
    required this.colors,
    required this.effectId,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (colors.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final ledCount = 30; // Simulated LED count for preview
    final ledWidth = size.width / ledCount;
    final ledHeight = size.height;

    switch (_getEffectType(effectId)) {
      case _EffectType.solid:
        _paintSolid(canvas, size, paint);
        break;
      case _EffectType.breathing:
        _paintBreathing(canvas, size, paint);
        break;
      case _EffectType.chase:
        _paintChase(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.wipe:
        _paintWipe(canvas, size, paint);
        break;
      case _EffectType.sparkle:
        _paintSparkle(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.scan:
        _paintScan(canvas, size, paint, ledWidth, ledHeight);
        break;
      case _EffectType.fade:
        _paintFade(canvas, size, paint);
        break;
      case _EffectType.gradient:
        _paintGradient(canvas, size, paint);
        break;
      case _EffectType.theater:
        _paintTheater(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.running:
        _paintRunning(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.twinkle:
        _paintTwinkle(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.fire:
        _paintFire(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.meteor:
        _paintMeteor(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
      case _EffectType.wave:
        _paintWave(canvas, size, paint, ledCount, ledWidth, ledHeight);
        break;
    }
  }

  _EffectType _getEffectType(int effectId) {
    // Map WLED effect IDs to visual effect types
    switch (effectId) {
      case 0: return _EffectType.solid;
      case 1: // Blink
      case 2: // Breathe
        return _EffectType.breathing;
      case 3: // Wipe
      case 4: // Wipe Random
        return _EffectType.wipe;
      case 6: // Sweep
      case 10: // Scan
      case 11: // Dual Scan
      case 13: // Scanner
      case 14: // Dual Scanner
        return _EffectType.scan;
      case 12: // Fade
      case 18: // Dissolve
        return _EffectType.fade;
      case 22: // Running 2
      case 23: // Chase
      case 24: // Chase Rainbow
      case 25: // Running Dual
      case 41: // Running
      case 42: // Running 2
        return _EffectType.running;
      case 43: // Theater Chase
      case 44: // Theater Chase Rainbow
        return _EffectType.theater;
      case 37: // Fill Noise
      case 46: // Twinklefox
      case 47: // Twinklecat
        return _EffectType.twinkle;
      case 51: // Gradient
      case 63: // Palette
      case 65: // Colorwaves
        return _EffectType.gradient;
      case 49: // Fire 2012
      case 54: // Fire Flicker
      case 74: // Candle
      case 75: // Fire
        return _EffectType.fire;
      case 78: // Meteor Rainbow
      case 108: // Meteor
      case 109: // Meteor Smooth
        return _EffectType.meteor;
      case 52: // Loading
      case 67: // Ripple
      case 70: // Lake
      case 73: // Pacifica
        return _EffectType.wave;
      case 76: // Fireworks
      case 77: // Rain
      case 120: // Sparkle
      case 121: // Sparkle+
        return _EffectType.sparkle;
      default:
        return _EffectType.chase; // Default to chase for unknown effects
    }
  }

  void _paintSolid(Canvas canvas, Size size, Paint paint) {
    paint.color = colors.first;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintBreathing(Canvas canvas, Size size, Paint paint) {
    // Smooth sine wave breathing
    final breathValue = (sin(progress * 2 * pi) + 1) / 2;
    paint.color = colors.first.withValues(alpha: 0.3 + breathValue * 0.7);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintChase(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    final chaseLength = 5;
    final chasePos = (progress * ledCount).floor();

    for (int i = 0; i < ledCount; i++) {
      final distFromChase = (i - chasePos + ledCount) % ledCount;
      if (distFromChase < chaseLength) {
        final colorIdx = distFromChase % colors.length;
        final brightness = 1.0 - (distFromChase / chaseLength);
        paint.color = colors[colorIdx].withValues(alpha: brightness);
      } else {
        paint.color = colors.last.withValues(alpha: 0.1);
      }
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintWipe(Canvas canvas, Size size, Paint paint) {
    final wipePos = progress * size.width;
    // First color (wiped area)
    paint.color = colors.first;
    canvas.drawRect(Rect.fromLTWH(0, 0, wipePos, size.height), paint);
    // Second color (unwipped area)
    paint.color = colors.length > 1 ? colors[1] : colors.first.withValues(alpha: 0.3);
    canvas.drawRect(Rect.fromLTWH(wipePos, 0, size.width - wipePos, size.height), paint);
  }

  void _paintSparkle(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Background
    paint.color = colors.last.withValues(alpha: 0.15);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Sparkles - use progress to create pseudo-random positions
    final sparkleCount = 8;
    for (int i = 0; i < sparkleCount; i++) {
      final seed = (progress * 1000 + i * 137).floor() % ledCount;
      final colorIdx = i % colors.length;
      final fadePhase = ((progress * 3 + i * 0.3) % 1.0);
      final opacity = fadePhase < 0.5 ? fadePhase * 2 : (1 - fadePhase) * 2;

      paint.color = colors[colorIdx].withValues(alpha: opacity.clamp(0.0, 1.0));
      final x = seed * ledWidth;
      // Draw as small circle for sparkle effect
      canvas.drawCircle(Offset(x + ledWidth / 2, size.height / 2), ledWidth * 0.8, paint);
    }
  }

  void _paintScan(Canvas canvas, Size size, Paint paint, double ledWidth, double ledHeight) {
    // Background
    paint.color = colors.last.withValues(alpha: 0.1);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Scanning bar that bounces
    final bounce = (sin(progress * 2 * pi) + 1) / 2;
    final scanPos = bounce * (size.width - ledWidth * 3);
    final scanWidth = ledWidth * 3;

    // Glow behind scan bar
    final glowGradient = LinearGradient(
      colors: [
        colors.first.withValues(alpha: 0.0),
        colors.first.withValues(alpha: 0.5),
        colors.first,
        colors.first.withValues(alpha: 0.5),
        colors.first.withValues(alpha: 0.0),
      ],
    );
    paint.shader = glowGradient.createShader(Rect.fromLTWH(scanPos - scanWidth, 0, scanWidth * 3, ledHeight));
    canvas.drawRect(Rect.fromLTWH(scanPos - scanWidth, 0, scanWidth * 3, ledHeight), paint);
    paint.shader = null;
  }

  void _paintFade(Canvas canvas, Size size, Paint paint) {
    // Smooth color fade between colors
    final colorCount = colors.length;
    final colorProgress = progress * colorCount;
    final currentIdx = colorProgress.floor() % colorCount;
    final nextIdx = (currentIdx + 1) % colorCount;
    final blendFactor = colorProgress - colorProgress.floor();

    final blendedColor = Color.lerp(colors[currentIdx], colors[nextIdx], blendFactor)!;
    paint.color = blendedColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  void _paintGradient(Canvas canvas, Size size, Paint paint) {
    // Flowing gradient
    final offset = progress * 2;
    final extendedColors = [...colors, ...colors];
    final stops = List.generate(extendedColors.length, (i) => (i / (extendedColors.length - 1) + offset) % 2 / 2);
    stops.sort();

    final gradient = LinearGradient(
      colors: extendedColors,
      stops: stops,
    );
    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    paint.shader = null;
  }

  void _paintTheater(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Theater chase - every 3rd LED lit, shifting
    final offset = (progress * 3).floor() % 3;

    for (int i = 0; i < ledCount; i++) {
      final isLit = (i + offset) % 3 == 0;
      final colorIdx = ((i + offset) ~/ 3) % colors.length;
      paint.color = isLit ? colors[colorIdx] : Colors.black.withValues(alpha: 0.3);
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintRunning(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Running lights - segments of color moving
    final segmentLength = ledCount ~/ colors.length;
    final offset = (progress * ledCount).floor();

    for (int i = 0; i < ledCount; i++) {
      final adjustedI = (i + offset) % ledCount;
      final colorIdx = (adjustedI ~/ segmentLength) % colors.length;
      paint.color = colors[colorIdx];
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintTwinkle(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Base gradient
    final gradient = LinearGradient(colors: colors);
    paint.shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    paint.shader = null;

    // Twinkle overlay - bright spots that fade in/out
    final twinkleCount = 6;
    for (int i = 0; i < twinkleCount; i++) {
      final seed = (i * 17 + 7) % ledCount;
      final phase = ((progress * 2 + i * 0.2) % 1.0);
      final brightness = (sin(phase * 2 * pi) + 1) / 2;

      paint.color = Colors.white.withValues(alpha: brightness * 0.7);
      final x = seed * ledWidth + ledWidth / 2;
      canvas.drawCircle(Offset(x, size.height / 2), ledWidth * 0.6, paint);
    }
  }

  void _paintFire(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Fire effect with orange/red/yellow flickering
    final fireColors = colors.isNotEmpty ? colors : [Colors.red, Colors.orange, Colors.yellow];

    for (int i = 0; i < ledCount; i++) {
      // Create pseudo-random flicker based on position and time
      final flicker = (sin(progress * 10 + i * 0.5) + sin(progress * 7 + i * 0.3)) / 4 + 0.5;
      final colorIdx = ((flicker * fireColors.length).floor()).clamp(0, fireColors.length - 1);
      final brightness = 0.5 + flicker * 0.5;

      paint.color = fireColors[colorIdx].withValues(alpha: brightness.clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  void _paintMeteor(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Background
    paint.color = Colors.black.withValues(alpha: 0.8);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Meteor with tail
    final meteorPos = (progress * (ledCount + 10)).floor() - 5;
    final tailLength = 8;

    for (int i = 0; i < tailLength; i++) {
      final pos = meteorPos - i;
      if (pos >= 0 && pos < ledCount) {
        final brightness = 1.0 - (i / tailLength);
        final colorIdx = i % colors.length;
        paint.color = colors[colorIdx].withValues(alpha: brightness);
        canvas.drawRect(Rect.fromLTWH(pos * ledWidth, 0, ledWidth + 1, ledHeight), paint);
      }
    }
  }

  void _paintWave(Canvas canvas, Size size, Paint paint, int ledCount, double ledWidth, double ledHeight) {
    // Smooth wave pattern
    for (int i = 0; i < ledCount; i++) {
      final waveOffset = sin(progress * 2 * pi + i * 0.3);
      final brightness = (waveOffset + 1) / 2;
      final colorIdx = (i * colors.length / ledCount).floor() % colors.length;
      paint.color = colors[colorIdx].withValues(alpha: 0.3 + brightness * 0.7);
      canvas.drawRect(Rect.fromLTWH(i * ledWidth, 0, ledWidth + 1, ledHeight), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EffectPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.effectId != effectId ||
        oldDelegate.colors != colors;
  }
}

enum _EffectType {
  solid,
  breathing,
  chase,
  wipe,
  sparkle,
  scan,
  fade,
  gradient,
  theater,
  running,
  twinkle,
  fire,
  meteor,
  wave,
}

List<Color> extractColorsFromItem(PatternItem item) {
  try {
    final seg = item.wledPayload['seg'];
    if (seg is List && seg.isNotEmpty) {
      final first = seg.first;
      if (first is Map) {
        final col = first['col'];
        if (col is List) {
          final result = <Color>[];
          for (final c in col) {
            if (c is List && c.length >= 3) {
              final r = (c[0] as num).toInt().clamp(0, 255);
              final g = (c[1] as num).toInt().clamp(0, 255);
              final b = (c[2] as num).toInt().clamp(0, 255);
              result.add(Color.fromARGB(255, r, g, b));
            }
          }
          if (result.isNotEmpty) return result;
        }
      }
    }
  } catch (e) {
    debugPrint('Failed to extract colors from PatternItem: $e');
  }
  return const [Colors.white, Colors.white];
}

class ErrorStateWidget extends StatelessWidget {
  final String error;
  const ErrorStateWidget({super.key, required this.error});
  @override
  Widget build(BuildContext context) => Center(child: Text(error));
}

class CenteredText extends StatelessWidget {
  final String text;
  const CenteredText(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Center(child: Text(text));
}
