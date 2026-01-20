import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/autopilot/autopilot_weekly_preview.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';
import 'package:nexgen_command/theme.dart';

/// A status badge showing the current autopilot state.
///
/// Displays on the dashboard when autopilot is active, showing
/// the next scheduled pattern and allowing quick access to the schedule.
class AutopilotStatusBadge extends ConsumerWidget {
  final VoidCallback? onTap;

  const AutopilotStatusBadge({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(autopilotEnabledProvider);
    final autonomyLevel = ref.watch(autonomyLevelProvider);

    if (!enabled) {
      return const SizedBox.shrink();
    }

    final scheduleAsync = ref.watch(weeklyScheduleProvider);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              NexGenPalette.cyan.withOpacity(0.15),
              NexGenPalette.blue.withOpacity(0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: NexGenPalette.cyan.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            // Autopilot icon with animated glow
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.smart_toy,
                color: NexGenPalette.cyan,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            // Status text
            Expanded(
              child: scheduleAsync.when(
                data: (schedule) => _buildStatusContent(
                  context,
                  schedule,
                  autonomyLevel,
                ),
                loading: () => const Text(
                  'Generating schedule...',
                  style: TextStyle(color: Colors.grey),
                ),
                error: (_, __) => const Text(
                  'Schedule unavailable',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
            // Arrow
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusContent(
    BuildContext context,
    List<AutopilotScheduleItem> schedule,
    int autonomyLevel,
  ) {
    final now = DateTime.now();
    final nextItem = schedule.where((s) => s.scheduledTime.isAfter(now)).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Autopilot ${autonomyLevel == 2 ? "Active" : "Suggesting"}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: NexGenPalette.cyan,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: autonomyLevel == 2 ? Colors.green : Colors.orange,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (nextItem != null)
          Text(
            'Next: ${nextItem.patternName} (${_formatRelativeTime(nextItem.scheduledTime)})',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[400],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        else
          Text(
            'No upcoming scheduled items',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[400],
            ),
          ),
      ],
    );
  }

  String _formatRelativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = time.difference(now);

    if (diff.isNegative) {
      return 'now';
    }

    if (diff.inMinutes < 60) {
      return 'in ${diff.inMinutes}m';
    }

    if (diff.inHours < 24) {
      return 'in ${diff.inHours}h';
    }

    if (diff.inDays == 1) {
      return 'tomorrow';
    }

    return 'in ${diff.inDays} days';
  }
}

/// Compact inline badge for dashboard header.
class AutopilotInlineBadge extends ConsumerWidget {
  const AutopilotInlineBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(autopilotEnabledProvider);

    if (!enabled) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: NexGenPalette.cyan.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.smart_toy,
            size: 14,
            color: NexGenPalette.cyan,
          ),
          SizedBox(width: 4),
          Text(
            'Autopilot',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: NexGenPalette.cyan,
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating action button for autopilot quick actions.
class AutopilotFAB extends ConsumerWidget {
  final VoidCallback? onTap;

  const AutopilotFAB({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(autopilotEnabledProvider);
    final pendingCount = ref.watch(pendingSuggestionsCountProvider);

    if (!enabled) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        FloatingActionButton.small(
          onPressed: onTap,
          backgroundColor: NexGenPalette.cyan.withOpacity(0.9),
          child: const Icon(Icons.smart_toy, color: Colors.black),
        ),
        if (pendingCount > 0)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                pendingCount.toString(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Current pattern info card for autopilot.
class AutopilotCurrentPatternCard extends ConsumerWidget {
  const AutopilotCurrentPatternCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(autopilotEnabledProvider);

    if (!enabled) {
      return const SizedBox.shrink();
    }

    final scheduleAsync = ref.watch(weeklyScheduleProvider);

    return scheduleAsync.when(
      data: (schedule) {
        // Find current active pattern
        final now = DateTime.now();
        final currentOrPast = schedule
            .where((s) => s.scheduledTime.isBefore(now))
            .toList();

        if (currentOrPast.isEmpty) {
          return const SizedBox.shrink();
        }

        // Get most recent
        currentOrPast.sort((a, b) => b.scheduledTime.compareTo(a.scheduledTime));
        final current = currentOrPast.first;

        return _CurrentPatternDisplay(item: current);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _CurrentPatternDisplay extends StatelessWidget {
  final AutopilotScheduleItem item;

  const _CurrentPatternDisplay({required this.item});

  @override
  Widget build(BuildContext context) {
    // Extract colors from payload
    final colors = item.wledPayload['seg']?[0]?['col'] as List?;
    final displayColors = <Color>[];

    if (colors != null) {
      for (final colorArray in colors.take(3)) {
        if (colorArray is List && colorArray.length >= 3) {
          displayColors.add(Color.fromRGBO(
            colorArray[0] as int,
            colorArray[1] as int,
            colorArray[2] as int,
            1.0,
          ));
        }
      }
    }

    if (displayColors.isEmpty) {
      displayColors.add(Colors.grey);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: displayColors.length > 1
              ? displayColors.map((c) => c.withOpacity(0.3)).toList()
              : [displayColors.first.withOpacity(0.3), displayColors.first.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.smart_toy,
            size: 16,
            color: NexGenPalette.cyan,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.patternName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            item.reason,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }
}
