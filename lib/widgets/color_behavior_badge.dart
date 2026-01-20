import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/theme.dart';

/// A badge widget that displays the color behavior of a WLED effect.
///
/// Shows an icon and text indicating whether the effect uses the user's
/// selected colors, blends them, generates its own colors, or uses a palette.
class ColorBehaviorBadge extends StatelessWidget {
  /// The effect ID to display the color behavior for.
  final int effectId;

  /// Whether to show a compact version (icon only with tooltip).
  final bool compact;

  /// Optional override for the badge color.
  final Color? backgroundColor;

  const ColorBehaviorBadge({
    super.key,
    required this.effectId,
    this.compact = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final effect = WledEffectsCatalog.getById(effectId);
    final behavior = effect?.colorBehavior ?? ColorBehavior.usesSelectedColors;
    final icon = _iconForBehavior(behavior);
    final color = _colorForBehavior(behavior);
    final label = compact ? behavior.shortName : behavior.displayName;

    final badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 4 : 3,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: color),
          if (!compact) ...[
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );

    if (compact) {
      return Tooltip(
        message: '${behavior.displayName}\n${behavior.description}',
        child: badge,
      );
    }

    return badge;
  }

  IconData _iconForBehavior(ColorBehavior behavior) {
    switch (behavior) {
      case ColorBehavior.usesSelectedColors:
        return Icons.palette_outlined;
      case ColorBehavior.blendsSelectedColors:
        return Icons.gradient;
      case ColorBehavior.generatesOwnColors:
        return Icons.auto_awesome;
      case ColorBehavior.usesPalette:
        return Icons.color_lens_outlined;
    }
  }

  Color _colorForBehavior(ColorBehavior behavior) {
    switch (behavior) {
      case ColorBehavior.usesSelectedColors:
        return NexGenPalette.cyan; // User's colors are used
      case ColorBehavior.blendsSelectedColors:
        return const Color(0xFF64B5F6); // Light blue for blending
      case ColorBehavior.generatesOwnColors:
        return const Color(0xFFFFB74D); // Amber/orange for auto colors
      case ColorBehavior.usesPalette:
        return const Color(0xFFBA68C8); // Purple for palettes
    }
  }
}

/// A combined badge showing both effect name and color behavior.
class EffectWithColorBehaviorBadge extends StatelessWidget {
  /// The effect ID to display.
  final int effectId;

  /// Optional effect name override.
  final String? effectName;

  /// Whether the effect is static (no motion).
  final bool isStatic;

  const EffectWithColorBehaviorBadge({
    super.key,
    required this.effectId,
    this.effectName,
    this.isStatic = false,
  });

  @override
  Widget build(BuildContext context) {
    final effect = WledEffectsCatalog.getById(effectId);
    final name = effectName ?? effect?.name ?? 'Unknown';
    final behavior = effect?.colorBehavior ?? ColorBehavior.usesSelectedColors;
    final behaviorColor = _colorForBehavior(behavior);
    final motionIcon = isStatic ? Icons.pause_circle_outline : Icons.motion_photos_on;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Motion indicator
          Icon(motionIcon, color: NexGenPalette.cyan, size: 14),
          const SizedBox(width: 4),
          // Effect name
          Flexible(
            child: Text(
              name,
              style: const TextStyle(color: Colors.white, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Divider
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 1,
            height: 12,
            color: Colors.white24,
          ),
          // Color behavior indicator
          Icon(_iconForBehavior(behavior), size: 12, color: behaviorColor),
          const SizedBox(width: 3),
          Text(
            behavior.shortName,
            style: TextStyle(color: behaviorColor, fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  IconData _iconForBehavior(ColorBehavior behavior) {
    switch (behavior) {
      case ColorBehavior.usesSelectedColors:
        return Icons.palette_outlined;
      case ColorBehavior.blendsSelectedColors:
        return Icons.gradient;
      case ColorBehavior.generatesOwnColors:
        return Icons.auto_awesome;
      case ColorBehavior.usesPalette:
        return Icons.color_lens_outlined;
    }
  }

  Color _colorForBehavior(ColorBehavior behavior) {
    switch (behavior) {
      case ColorBehavior.usesSelectedColors:
        return NexGenPalette.cyan;
      case ColorBehavior.blendsSelectedColors:
        return const Color(0xFF64B5F6);
      case ColorBehavior.generatesOwnColors:
        return const Color(0xFFFFB74D);
      case ColorBehavior.usesPalette:
        return const Color(0xFFBA68C8);
    }
  }
}

/// A legend widget explaining what each color behavior means.
/// Useful for display in settings or help screens.
class ColorBehaviorLegend extends StatelessWidget {
  const ColorBehaviorLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Effect Color Behaviors',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ...ColorBehavior.values.map((behavior) => _LegendItem(behavior: behavior)),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final ColorBehavior behavior;
  const _LegendItem({required this.behavior});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ColorBehaviorBadge(effectId: _sampleEffectId(behavior), compact: false),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              behavior.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // Return a sample effect ID for each behavior to show correct badge
  int _sampleEffectId(ColorBehavior behavior) {
    switch (behavior) {
      case ColorBehavior.usesSelectedColors:
        return 0; // Solid
      case ColorBehavior.blendsSelectedColors:
        return 2; // Breathe
      case ColorBehavior.generatesOwnColors:
        return 9; // Rainbow
      case ColorBehavior.usesPalette:
        return 65; // Palette
    }
  }
}
