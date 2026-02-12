import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// A single parameter row in the Lumina response card's parameter summary.
///
/// Displays a muted [label] on the left and a bright [value] on the right.
/// When [changed] is true, the value gets an accent-color highlight and a
/// subtle "changed" indicator to show what Lumina adjusted.
///
/// An optional [trailing] widget can be placed after the value — used for
/// inline indicators like the brightness bar.
class ParameterSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool changed;
  final Widget? trailing;

  const ParameterSummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.changed = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // Label
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
            ),
          ),
          // Value
          Flexible(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: changed
                              ? NexGenPalette.cyan
                              : NexGenPalette.textHigh,
                          fontWeight:
                              changed ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 12,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (changed) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: NexGenPalette.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'changed',
                      style: TextStyle(
                        color: NexGenPalette.cyan.withValues(alpha: 0.8),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact brightness bar indicator (inline, fixed width).
class BrightnessBarIndicator extends StatelessWidget {
  /// Brightness value 0.0–1.0.
  final double value;
  final double width;
  final double height;

  const BrightnessBarIndicator({
    super.key,
    required this.value,
    this.width = 48,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Stack(
          children: [
            // Track
            Container(
              color: NexGenPalette.line.withValues(alpha: 0.5),
            ),
            // Fill
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      NexGenPalette.cyan.withValues(alpha: 0.7),
                      NexGenPalette.cyan,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
