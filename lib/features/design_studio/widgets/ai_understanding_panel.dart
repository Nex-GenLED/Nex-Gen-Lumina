import 'package:flutter/material.dart';
import 'package:nexgen_command/features/design_studio/models/design_intent.dart';
import 'package:nexgen_command/theme.dart';

/// Panel that shows what the AI understood from the user's input.
///
/// Displays a friendly breakdown of:
/// - Colors identified
/// - Zones/areas targeted
/// - Motion/effects detected
/// - Spacing rules parsed
class AIUnderstandingPanel extends StatelessWidget {
  final DesignIntent intent;
  final void Function(String layerId)? onEditLayer;
  final VoidCallback? onOpenManual;

  const AIUnderstandingPanel({
    super.key,
    required this.intent,
    this.onEditLayer,
    this.onOpenManual,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: NexGenPalette.cyan,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'I understood:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              // Confidence indicator
              _ConfidenceIndicator(confidence: intent.confidence),
              const SizedBox(width: 8),
              // Manual controls button
              if (onOpenManual != null)
                IconButton(
                  icon: const Icon(Icons.tune, size: 20),
                  color: Colors.white54,
                  onPressed: onOpenManual,
                  tooltip: 'Open manual controls',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Layer summaries
          ...intent.layers.map((layer) => _LayerSummary(
                layer: layer,
                onEdit: onEditLayer != null ? () => onEditLayer!(layer.id) : null,
              )),

          // Global settings if customized
          if (intent.globalSettings.brightness != 200)
            _UnderstandingItem(
              icon: Icons.brightness_6,
              label: 'Brightness',
              value: '${(intent.globalSettings.brightness / 255 * 100).round()}%',
            ),
        ],
      ),
    );
  }
}

/// Confidence indicator dot.
class _ConfidenceIndicator extends StatelessWidget {
  final double confidence;

  const _ConfidenceIndicator({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final color = confidence >= 0.8
        ? Colors.green
        : confidence >= 0.5
            ? Colors.orange
            : Colors.red;

    return Tooltip(
      message: 'Confidence: ${(confidence * 100).round()}%',
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Summary of a single layer.
class _LayerSummary extends StatelessWidget {
  final DesignLayer layer;
  final VoidCallback? onEdit;

  const _LayerSummary({
    required this.layer,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Color swatch
              _ColorSwatch(color: layer.colors.primaryColor),
              if (layer.colors.secondaryColor != null) ...[
                const SizedBox(width: 4),
                _ColorSwatch(color: layer.colors.secondaryColor!),
              ],
              if (layer.colors.accentColor != null) ...[
                const SizedBox(width: 4),
                _ColorSwatch(color: layer.colors.accentColor!, isAccent: true),
              ],
              const SizedBox(width: 12),

              // Layer name
              Expanded(
                child: Text(
                  layer.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              // Edit button
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  color: Colors.white38,
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Details
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              // Zone
              if (layer.targetZone.type != ZoneSelectorType.all)
                _DetailChip(
                  icon: Icons.location_on,
                  label: layer.targetZone.description,
                ),

              // Motion
              if (layer.motion != null)
                _DetailChip(
                  icon: _getMotionIcon(layer.motion!.motionType),
                  label: '${layer.motion!.motionType.name} ${layer.motion!.direction.displayName}',
                ),

              // Spacing
              if (layer.colors.spacingRule != null)
                _DetailChip(
                  icon: Icons.straighten,
                  label: layer.colors.spacingRule!.description,
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getMotionIcon(MotionType type) {
    switch (type) {
      case MotionType.chase:
        return Icons.directions_run;
      case MotionType.wave:
        return Icons.waves;
      case MotionType.flow:
        return Icons.water;
      case MotionType.pulse:
        return Icons.favorite;
      case MotionType.twinkle:
        return Icons.auto_awesome;
      case MotionType.scan:
        return Icons.radar;
      case MotionType.none:
        return Icons.stop;
    }
  }
}

/// Color swatch widget.
class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool isAccent;

  const _ColorSwatch({
    required this.color,
    this.isAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: isAccent
            ? Border.all(color: Colors.white, width: 2)
            : Border.all(color: color.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            spreadRadius: 0,
          ),
        ],
      ),
    );
  }
}

/// Small detail chip.
class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Colors.white54,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// Understanding item (icon + label + value).
class _UnderstandingItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _UnderstandingItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
