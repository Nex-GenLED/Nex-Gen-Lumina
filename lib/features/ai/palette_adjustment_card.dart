import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';

/// Color palette adjustment card with swatches and quick-transform chips.
///
/// Provides one-tap adjustments (Warmer, Cooler, Vibrant, Muted) that
/// shift all palette colors using HSL transformations, plus a "Change Colors"
/// placeholder for a future dedicated picker.
class PaletteAdjustmentCard extends ConsumerWidget {
  const PaletteAdjustmentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adjState = ref.watch(adjustmentStateProvider);
    if (adjState == null) return const SizedBox.shrink();

    final colors = adjState.currentSuggestion.colors;
    final palette = adjState.currentSuggestion.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Color swatches
        Row(
          children: [
            ...colors.take(5).map((c) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: NexGenPalette.line.withValues(alpha: 0.6),
                        width: 0.5,
                      ),
                    ),
                  ),
                )),
            if (palette.colorNames.isNotEmpty) ...[
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  palette.colorNames.join(', '),
                  style: TextStyle(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // Quick transform chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _TransformChip(
                label: 'Warmer',
                onTap: () => _applyTransform(ref, colors, palette, _warmer),
              ),
              const SizedBox(width: 8),
              _TransformChip(
                label: 'Cooler',
                onTap: () => _applyTransform(ref, colors, palette, _cooler),
              ),
              const SizedBox(width: 8),
              _TransformChip(
                label: 'Vibrant',
                onTap: () => _applyTransform(ref, colors, palette, _vibrant),
              ),
              const SizedBox(width: 8),
              _TransformChip(
                label: 'Muted',
                onTap: () => _applyTransform(ref, colors, palette, _muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Transform helpers
  // -------------------------------------------------------------------------

  void _applyTransform(
    WidgetRef ref,
    List<Color> colors,
    PaletteInfo palette,
    Color Function(Color) transform,
  ) {
    final newColors = colors.map(transform).toList();
    final newPalette = PaletteInfo(
      name: 'Custom',
      colorNames: palette.colorNames,
    );
    ref.read(adjustmentStateProvider.notifier).updateColors(
          newColors,
          newPalette,
        );
  }

  /// Shift hue toward warm (orange ~30°), clamp shift to ±30°.
  static Color _warmer(Color c) {
    final hsl = HSLColor.fromColor(c);
    // Move hue toward 30° (warm orange)
    final target = 30.0;
    final hue = hsl.hue;
    final diff = (target - hue + 540) % 360 - 180;
    final newHue = (hue + diff * 0.25) % 360;
    return hsl
        .withHue(newHue < 0 ? newHue + 360 : newHue)
        .withSaturation((hsl.saturation + 0.05).clamp(0.0, 1.0))
        .toColor();
  }

  /// Shift hue toward cool (blue ~210°).
  static Color _cooler(Color c) {
    final hsl = HSLColor.fromColor(c);
    final target = 210.0;
    final hue = hsl.hue;
    final diff = (target - hue + 540) % 360 - 180;
    final newHue = (hue + diff * 0.25) % 360;
    return hsl
        .withHue(newHue < 0 ? newHue + 360 : newHue)
        .withSaturation((hsl.saturation + 0.05).clamp(0.0, 1.0))
        .toColor();
  }

  /// Boost saturation by 20%.
  static Color _vibrant(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation + 0.20).clamp(0.0, 1.0))
        .withLightness((hsl.lightness + 0.03).clamp(0.0, 0.85))
        .toColor();
  }

  /// Reduce saturation by 25%.
  static Color _muted(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation - 0.25).clamp(0.0, 1.0))
        .toColor();
  }
}

// ---------------------------------------------------------------------------
// Private chip widget
// ---------------------------------------------------------------------------

class _TransformChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TransformChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: NexGenPalette.textMedium,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
