import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design_studio/design_studio_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/theme.dart';

/// Live preview canvas showing the pattern on a roofline visualization.
///
/// Displays:
/// - Roofline silhouette with segments
/// - LED dots colored by the composed pattern
/// - Segment labels on tap
/// - Animation preview for motion effects
class LivePreviewCanvas extends ConsumerWidget {
  final bool enabled;

  const LivePreviewCanvas({
    super.key,
    this.enabled = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(currentRooflineConfigProvider);
    final composedPattern = ref.watch(composedPatternProvider);
    final colorGroups = composedPattern?.colorGroups ?? [];

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.indigo.shade900.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.5),
                  ],
                ),
              ),
            ),

            // Preview content
            configAsync.when(
              data: (config) {
                if (config == null) {
                  return _buildNoConfigState();
                }
                return _PreviewContent(
                  config: config,
                  colorGroups: colorGroups,
                  hasMotion: composedPattern?.hasMotion ?? false,
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: NexGenPalette.cyan),
              ),
              error: (_, __) => _buildNoConfigState(),
            ),

            // Live preview indicator
            Positioned(
              top: 12,
              right: 12,
              child: _LivePreviewBadge(enabled: enabled),
            ),

            // Empty state overlay
            if (colorGroups.isEmpty)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 48,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your design will appear here',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoConfigState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.roofing,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No Roofline Configuration',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Set up your roofline to see the preview',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Badge showing live preview status.
class _LivePreviewBadge extends StatelessWidget {
  final bool enabled;

  const _LivePreviewBadge({required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: enabled
            ? NexGenPalette.cyan.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled
              ? NexGenPalette.cyan.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: enabled ? NexGenPalette.cyan : Colors.white38,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            enabled ? 'LIVE' : 'Preview',
            style: TextStyle(
              color: enabled ? NexGenPalette.cyan : Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Main preview content widget.
class _PreviewContent extends StatelessWidget {
  final RooflineConfiguration config;
  final List<LedColorGroup> colorGroups;
  final bool hasMotion;

  const _PreviewContent({
    required this.config,
    required this.colorGroups,
    required this.hasMotion,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.roofing,
                    color: NexGenPalette.cyan,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    config.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${config.totalPixelCount} LEDs',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Compact LED strip visualization
              _CompactLedStrip(
                config: config,
                colorGroups: colorGroups,
              ),

              const SizedBox(height: 16),

              // Segment breakdown (if groups are shown)
              if (colorGroups.isNotEmpty)
                _SegmentBreakdown(
                  config: config,
                  colorGroups: colorGroups,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact LED strip showing all pixels in a horizontal scrollable view.
class _CompactLedStrip extends StatelessWidget {
  final RooflineConfiguration config;
  final List<LedColorGroup> colorGroups;

  const _CompactLedStrip({
    required this.config,
    required this.colorGroups,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: config.totalPixelCount,
        itemBuilder: (context, index) {
          final color = _getColorForLed(index);
          final isSegmentBoundary = _isSegmentBoundary(index);

          return Row(
            children: [
              if (isSegmentBoundary && index > 0)
                Container(
                  width: 2,
                  height: 24,
                  color: Colors.white.withValues(alpha: 0.2),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                ),
              Container(
                width: 6,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: color ?? Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: color != null
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Color? _getColorForLed(int index) {
    for (final group in colorGroups) {
      if (index >= group.startLed && index <= group.endLed) {
        return group.flutterColor;
      }
    }
    return null;
  }

  bool _isSegmentBoundary(int index) {
    for (final segment in config.segments) {
      if (segment.startPixel == index && index > 0) {
        return true;
      }
    }
    return false;
  }
}

/// Breakdown showing which segments have which colors.
class _SegmentBreakdown extends StatelessWidget {
  final RooflineConfiguration config;
  final List<LedColorGroup> colorGroups;

  const _SegmentBreakdown({
    required this.config,
    required this.colorGroups,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: config.segments.map((segment) {
        final colors = _getSegmentColors(segment);
        return _SegmentChip(
          segment: segment,
          colors: colors,
        );
      }).toList(),
    );
  }

  List<Color> _getSegmentColors(RooflineSegment segment) {
    final colors = <Color>{};
    for (final group in colorGroups) {
      if (group.endLed >= segment.startPixel && group.startLed <= segment.endPixel) {
        colors.add(group.flutterColor);
      }
    }
    return colors.toList();
  }
}

/// Chip showing a segment and its colors.
class _SegmentChip extends StatelessWidget {
  final RooflineSegment segment;
  final List<Color> colors;

  const _SegmentChip({
    required this.segment,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getSegmentIcon(segment.type),
            size: 14,
            color: _getSegmentColor(segment.type),
          ),
          const SizedBox(width: 6),
          Text(
            segment.name,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
          if (colors.isNotEmpty) ...[
            const SizedBox(width: 8),
            ...colors.take(3).map((c) => Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  IconData _getSegmentIcon(SegmentType type) {
    switch (type) {
      case SegmentType.run:
        return Icons.horizontal_rule;
      case SegmentType.corner:
        return Icons.turn_right;
      case SegmentType.peak:
        return Icons.change_history;
      case SegmentType.column:
        return Icons.height;
      case SegmentType.connector:
        return Icons.link;
    }
  }

  Color _getSegmentColor(SegmentType type) {
    switch (type) {
      case SegmentType.run:
        return NexGenPalette.cyan;
      case SegmentType.corner:
        return Colors.orange;
      case SegmentType.peak:
        return Colors.purple;
      case SegmentType.column:
        return Colors.green;
      case SegmentType.connector:
        return Colors.grey;
    }
  }
}
