import 'package:flutter/material.dart';
import 'package:nexgen_command/features/ai/pixel_renderer.dart';
import 'package:nexgen_command/theme.dart';

/// Horizontal row of discrete LED pixels for the Lumina bottom sheet.
///
/// Each pixel is a distinct filled circle with its own glow — no continuous
/// gradients or blurring between adjacent pixels.
///
/// Wraps [PixelRenderer] with a dark background container and an optional
/// zone label below.
class PixelStripPreview extends PixelRenderer {
  /// Container height (including background). Default 48.
  final double height;

  /// Pixel radius override. If null, auto-calculated from width and count.
  final double? pixelRadius;

  /// Background color behind the strip.
  final Color backgroundColor;

  /// Border radius for the background container.
  final double borderRadius;

  /// Optional zone label displayed below the strip.
  final String? zoneName;

  /// Optional pixel count label (e.g. "48 lights").
  final int? lightCount;

  const PixelStripPreview({
    super.key,
    required super.colors,
    super.effectType,
    super.speed,
    super.brightness,
    super.pixelCount = 20,
    super.animate,
    super.specular,
    this.height = 48,
    this.pixelRadius,
    this.backgroundColor = const Color(0xFF0A0E14),
    this.borderRadius = 12.0,
    this.zoneName,
    this.lightCount,
  });

  @override
  State<PixelStripPreview> createState() => _PixelStripPreviewState();
}

class _PixelStripPreviewState extends PixelRendererState<PixelStripPreview> {
  @override
  List<Offset> computePixelPositions(Size canvasSize) {
    final count = widget.pixelCount;
    if (count <= 0) return [];

    final radius = getPixelRadius(canvasSize);
    // Horizontal padding so glow doesn't clip
    final hPad = radius * 3;
    final usableWidth = canvasSize.width - hPad * 2;
    final centerY = canvasSize.height / 2;

    return List.generate(count, (i) {
      final t = count > 1 ? i / (count - 1) : 0.5;
      return Offset(hPad + t * usableWidth, centerY);
    });
  }

  @override
  double getPixelRadius(Size canvasSize) {
    if (widget.pixelRadius != null) return widget.pixelRadius!;
    // Auto-size: fill ~55% of width with spacing = diameter * 1.4
    final spacing = canvasSize.width * 0.55 / widget.pixelCount;
    final diameter = spacing / 1.4;
    return (diameter / 2).clamp(3.0, 9.0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LED strip container
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: NexGenPalette.line.withValues(alpha: 0.3),
              width: 0.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: buildPixelCanvas(height: widget.height),
        ),

        // Zone label
        if (widget.zoneName != null || widget.lightCount != null) ...[
          const SizedBox(height: 4),
          Text(
            _buildLabel(),
            style: TextStyle(
              color: NexGenPalette.textMedium.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }

  String _buildLabel() {
    final parts = <String>[];
    if (widget.zoneName != null) parts.add(widget.zoneName!);
    if (widget.lightCount != null) {
      parts.add('${widget.lightCount} lights');
    }
    return parts.join(' · ');
  }
}
