import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/theme.dart';

/// A segment-aware LED canvas that displays LEDs organized by roofline segments.
///
/// Features:
/// - Shows segment boundaries with labels and dividers
/// - Highlights anchor zones distinctly
/// - Supports displaying generated pattern colors
/// - Click on segment name to select all LEDs in segment
class SegmentLedCanvas extends ConsumerWidget {
  /// Optional list of color groups to display (from pattern generation)
  final List<LedColorGroup>? colorGroups;

  /// Callback when an LED is tapped
  final void Function(int globalIndex, String segmentId)? onLedTap;

  /// Callback when a segment header is tapped
  final void Function(String segmentId)? onSegmentTap;

  /// Whether to show anchor highlights
  final bool showAnchors;

  /// Maximum LEDs per row within a segment
  final int ledsPerRow;

  const SegmentLedCanvas({
    super.key,
    this.colorGroups,
    this.onLedTap,
    this.onSegmentTap,
    this.showAnchors = true,
    this.ledsPerRow = 25,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(currentRooflineConfigProvider);

    return config.when(
      data: (rooflineConfig) {
        if (rooflineConfig == null || rooflineConfig.segments.isEmpty) {
          return _buildEmptyState(context);
        }
        return _buildCanvas(context, rooflineConfig);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _buildEmptyState(context),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
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
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Configure your roofline segments to use segment mode',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(BuildContext context, RooflineConfiguration config) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.roofing, color: NexGenPalette.cyan, size: 20),
                const SizedBox(width: 8),
                Text(
                  config.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${config.totalPixelCount} pixels',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Segments
            for (final segment in config.segments) ...[
              _SegmentSection(
                segment: segment,
                colorGroups: colorGroups,
                showAnchors: showAnchors,
                ledsPerRow: ledsPerRow,
                onLedTap: onLedTap,
                onSegmentTap: onSegmentTap,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

/// Section widget for a single segment.
class _SegmentSection extends StatelessWidget {
  final RooflineSegment segment;
  final List<LedColorGroup>? colorGroups;
  final bool showAnchors;
  final int ledsPerRow;
  final void Function(int globalIndex, String segmentId)? onLedTap;
  final void Function(String segmentId)? onSegmentTap;

  const _SegmentSection({
    required this.segment,
    this.colorGroups,
    required this.showAnchors,
    required this.ledsPerRow,
    this.onLedTap,
    this.onSegmentTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Segment header
        GestureDetector(
          onTap: onSegmentTap != null ? () => onSegmentTap!(segment.id) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getSegmentTypeColor(segment.type).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getSegmentTypeIcon(segment.type),
                  size: 14,
                  color: _getSegmentTypeColor(segment.type),
                ),
                const SizedBox(width: 6),
                Text(
                  segment.name,
                  style: TextStyle(
                    color: _getSegmentTypeColor(segment.type),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${segment.pixelCount}px',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
                ),
                if (showAnchors && segment.anchorPixels.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.anchor, size: 10, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          '${segment.anchorPixels.length}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),

        // LED strip
        Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            for (int i = 0; i < segment.pixelCount; i++)
              _LedDot(
                globalIndex: segment.startPixel + i,
                localIndex: i,
                segment: segment,
                colorGroups: colorGroups,
                showAnchors: showAnchors,
                onTap: onLedTap != null
                    ? () => onLedTap!(segment.startPixel + i, segment.id)
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  IconData _getSegmentTypeIcon(SegmentType type) {
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

  Color _getSegmentTypeColor(SegmentType type) {
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

/// Individual LED dot widget.
class _LedDot extends StatelessWidget {
  final int globalIndex;
  final int localIndex;
  final RooflineSegment segment;
  final List<LedColorGroup>? colorGroups;
  final bool showAnchors;
  final VoidCallback? onTap;

  const _LedDot({
    required this.globalIndex,
    required this.localIndex,
    required this.segment,
    this.colorGroups,
    required this.showAnchors,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAnchor = showAnchors && segment.isAnchorPixel(localIndex);
    final color = _getColorForLed(globalIndex);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color ?? Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isAnchor
                ? Colors.amber
                : color != null
                    ? color.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.1),
            width: isAnchor ? 2 : 1,
          ),
          boxShadow: color != null
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  Color? _getColorForLed(int globalIndex) {
    if (colorGroups == null || colorGroups!.isEmpty) return null;

    for (final group in colorGroups!) {
      if (globalIndex >= group.startLed && globalIndex <= group.endLed) {
        return group.flutterColor;
      }
    }

    return null;
  }
}

/// Preview widget that shows the pattern applied to the roofline configuration.
class SegmentPatternPreview extends ConsumerWidget {
  final List<LedColorGroup> colorGroups;

  const SegmentPatternPreview({
    super.key,
    required this.colorGroups,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(currentRooflineConfigProvider);

    return config.when(
      data: (rooflineConfig) {
        if (rooflineConfig == null) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.preview, color: NexGenPalette.cyan, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Pattern Preview',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${colorGroups.length} groups',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Compact LED strip preview
              _CompactLedPreview(
                config: rooflineConfig,
                colorGroups: colorGroups,
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Compact LED preview showing entire roofline in a single row (or wrapped).
class _CompactLedPreview extends StatelessWidget {
  final RooflineConfiguration config;
  final List<LedColorGroup> colorGroups;

  const _CompactLedPreview({
    required this.config,
    required this.colorGroups,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: config.totalPixelCount,
        separatorBuilder: (_, i) {
          // Add a small gap at segment boundaries
          final nextPixel = i + 1;
          for (final segment in config.segments) {
            if (segment.startPixel == nextPixel && segment.startPixel != 0) {
              return Container(
                width: 4,
                color: Colors.white.withValues(alpha: 0.2),
              );
            }
          }
          return const SizedBox(width: 1);
        },
        itemBuilder: (context, index) {
          final color = _getColorForLed(index);
          final isAnchor = config.isAnchorPixel(index);

          return Container(
            width: 8,
            height: 20,
            decoration: BoxDecoration(
              color: color ?? Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(2),
              border: isAnchor
                  ? Border.all(color: Colors.amber, width: 1)
                  : null,
            ),
          );
        },
      ),
    );
  }

  Color? _getColorForLed(int globalIndex) {
    for (final group in colorGroups) {
      if (globalIndex >= group.startLed && globalIndex <= group.endLed) {
        return group.flutterColor;
      }
    }
    return null;
  }
}
