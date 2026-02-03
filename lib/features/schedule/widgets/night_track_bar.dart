import 'package:flutter/material.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/theme.dart';

/// Night timeline bar showing multiple schedule segments with time-based positioning.
///
/// The bar represents the night period:
/// - Left edge (0%) = Sunset (~6pm)
/// - Center (50%) = Midnight
/// - Right edge (100%) = Sunrise (~6am)
///
/// Each schedule segment is rendered at its correct time position with the pattern's color.
class NightTrackBar extends StatelessWidget {
  final String label;
  final List<ScheduleItem> items;
  const NightTrackBar({super.key, required this.label, required this.items});

  /// Converts a time label to a position on the bar (0.0 to 1.0).
  ///
  /// The bar represents roughly 12 hours from sunset to sunrise:
  /// - Sunset (6pm) = 0.0
  /// - Midnight (12am) = 0.5
  /// - Sunrise (6am) = 1.0
  double _timeToPosition(String timeLabel) {
    final lower = timeLabel.trim().toLowerCase();

    // Handle solar events
    if (lower == 'sunset' || lower == 'dusk') return 0.0;
    if (lower == 'sunrise' || lower == 'dawn') return 1.0;
    if (lower == 'midnight') return 0.5;

    // Parse specific time like "7:00 PM" or "11:00 PM"
    final reg = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$', caseSensitive: false);
    final match = reg.firstMatch(timeLabel.trim());
    if (match == null) return 0.0; // Default to sunset if unparseable

    var hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = int.tryParse(match.group(2)!) ?? 0;
    final ampm = match.group(3)!.toLowerCase();

    // Convert to 24-hour format
    if (ampm == 'pm' && hour != 12) hour += 12;
    if (ampm == 'am' && hour == 12) hour = 0;

    // Calculate position on the bar
    // Evening hours (6pm-midnight): map to 0.0-0.5
    // Morning hours (midnight-6am): map to 0.5-1.0
    if (hour >= 18) {
      // 6pm (18) = 0.0, midnight (24/0) = 0.5
      return (hour - 18 + minute / 60.0) / 12.0;
    } else if (hour < 6) {
      // midnight (0) = 0.5, 6am (6) = 1.0
      return 0.5 + (hour + minute / 60.0) / 12.0;
    } else {
      // Daytime hours (6am-6pm) - clamp to edges
      return hour < 12 ? 1.0 : 0.0;
    }
  }

  Color _idealTextOn(Color bg) => bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  _PatternStyle _styleForPattern(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('candy') || lower.contains('cane')) {
      return const _PatternStyle(
        gradient: LinearGradient(colors: [Colors.red, Colors.white, Colors.red, Colors.white, Colors.red], stops: [0.0, 0.25, 0.5, 0.75, 1.0]),
        textColor: Colors.white,
      );
    }
    if (lower.contains('chiefs')) {
      return const _PatternStyle(gradient: LinearGradient(colors: [Colors.red, Colors.amber]), textColor: Colors.white);
    }
    if (lower.contains('warm white') || lower.contains('warm')) {
      final c = Colors.amber;
      return _PatternStyle(color: c, textColor: _idealTextOn(c));
    }
    if (lower.contains('holiday')) {
      return const _PatternStyle(gradient: LinearGradient(colors: [Colors.red, Colors.green]), textColor: Colors.white);
    }
    if (lower.contains('off') || lower.contains('turn off')) {
      return const _PatternStyle(color: NexGenPalette.trackDark, textColor: NexGenPalette.textHigh);
    }
    if (lower.contains('brightness')) {
      // Brightness schedules - show as a warm amber tone
      return _PatternStyle(color: Colors.amber.shade700, textColor: Colors.white);
    }
    // Default to app accent gradient
    return _PatternStyle(gradient: LinearGradient(colors: [NexGenPalette.violet, NexGenPalette.cyan]), textColor: Colors.white);
  }

  String _patternNameFromAction(String actionLabel) {
    final a = actionLabel.trim();
    if (a.toLowerCase().startsWith('pattern')) {
      final idx = a.indexOf(':');
      return idx != -1 && idx + 1 < a.length ? a.substring(idx + 1).trim() : a;
    }
    return a;
  }

  /// Builds a list of segments with their start/end positions and styles.
  List<_ScheduleSegment> _buildSegments() {
    if (items.isEmpty) return [];

    final segments = <_ScheduleSegment>[];

    for (final item in items) {
      final startPos = _timeToPosition(item.timeLabel);
      final endPos = item.hasOffTime
          ? _timeToPosition(item.offTimeLabel!)
          : 1.0; // Default to sunrise if no end time

      final patternName = _patternNameFromAction(item.actionLabel);
      final style = _styleForPattern(patternName);

      segments.add(_ScheduleSegment(
        startPosition: startPos,
        endPosition: endPos,
        style: style,
        label: patternName,
      ));
    }

    // Sort by start position
    segments.sort((a, b) => a.startPosition.compareTo(b.startPosition));

    return segments;
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = items.isNotEmpty;
    final segments = _buildSegments();

    // For single item with full coverage, use simple centered label
    final showCenteredLabel = segments.length <= 1;
    final singleStyle = hasItems && segments.isNotEmpty
        ? segments.first.style
        : const _PatternStyle(color: NexGenPalette.trackDark, textColor: NexGenPalette.textHigh);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: NexGenPalette.trackDark,
          border: Border.all(color: NexGenPalette.line),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(children: [
          // Midnight grid line at 50%
          Align(
            alignment: Alignment.center,
            child: Container(width: 1, color: NexGenPalette.textMedium.withValues(alpha: 0.18)),
          ),

          // Render segments
          if (hasItems && segments.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return Stack(
                  children: segments.map((seg) {
                    // Handle wrap-around (e.g., start=0.8, end=0.2 means it wraps past sunrise)
                    final startPos = seg.startPosition;
                    var endPos = seg.endPosition;

                    // If end is before start, it means the segment wraps around
                    // For now, clamp to the bar boundaries
                    if (endPos <= startPos) {
                      endPos = 1.0; // Extend to sunrise
                    }

                    final left = startPos * width;
                    final segWidth = (endPos - startPos) * width;

                    // Determine border radius based on position
                    BorderRadius borderRadius;
                    if (startPos <= 0.01 && endPos >= 0.99) {
                      // Full width - round both sides
                      borderRadius = BorderRadius.circular(14);
                    } else if (startPos <= 0.01) {
                      // Starts at left edge
                      borderRadius = const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      );
                    } else if (endPos >= 0.99) {
                      // Ends at right edge
                      borderRadius = const BorderRadius.only(
                        topRight: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      );
                    } else {
                      // Middle segment - no rounding
                      borderRadius = BorderRadius.zero;
                    }

                    return Positioned(
                      left: left,
                      top: 0,
                      bottom: 0,
                      width: segWidth.clamp(0, width - left),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: seg.style.color,
                          gradient: seg.style.gradient,
                          borderRadius: borderRadius,
                        ),
                        child: segments.length > 1 && segWidth > 60
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    seg.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: seg.style.textColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                );
              },
            ),

          // Centered label (for single item or empty)
          if (showCenteredLabel)
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: hasItems ? singleStyle.textColor : NexGenPalette.textMedium,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _PatternStyle {
  final Gradient? gradient;
  final Color? color;
  final Color textColor;
  const _PatternStyle({this.gradient, this.color, required this.textColor});
}

class _ScheduleSegment {
  final double startPosition;
  final double endPosition;
  final _PatternStyle style;
  final String label;

  const _ScheduleSegment({
    required this.startPosition,
    required this.endPosition,
    required this.style,
    required this.label,
  });
}
