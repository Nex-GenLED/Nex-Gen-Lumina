import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../providers/sync_handoff_providers.dart';
import '../services/sync_handoff_manager.dart';

/// Overlay widget that modifies a group card's appearance based on
/// its handoff state (paused, active shortForm, transitioning, etc.).
///
/// Wrap any group card with this widget. It reads handoff providers
/// to determine what badge/overlay to show.
class HandoffCardOverlay extends ConsumerWidget {
  /// The group ID this card represents.
  final String groupId;

  /// The group's display name.
  final String groupName;

  /// Colors associated with this group's pattern (for preview strip).
  final List<Color> patternColors;

  /// The child widget (the group card itself).
  final Widget child;

  const HandoffCardOverlay({
    super.key,
    required this.groupId,
    required this.groupName,
    this.patternColors = const [],
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPausedByHandoff = ref.watch(isGroupPausedByHandoffProvider(groupId));
    final isActiveShortForm =
        ref.watch(isGroupActiveShortFormProvider(groupId));
    final handoffPhase = ref.watch(handoffPhaseProvider);
    final estimatedResume = ref.watch(estimatedResumeTimeStringProvider);
    final activeShortFormId = ref.watch(activeShortFormGroupIdProvider);

    // No handoff affecting this card — render normally
    if (!isPausedByHandoff && !isActiveShortForm) {
      return child;
    }

    // ── Paused longForm card (e.g. Christmas Squad during Chiefs game) ──
    if (isPausedByHandoff) {
      return _PausedLongFormCard(
        groupName: groupName,
        activeShortFormGroupId: activeShortFormId,
        estimatedResumeTime: estimatedResume,
        patternColors: patternColors,
        handoffPhase: handoffPhase,
        child: child,
      );
    }

    // ── Active shortForm card (e.g. Chiefs Crew during handoff) ──
    if (isActiveShortForm) {
      return _ActiveShortFormCard(
        groupName: groupName,
        handoffPhase: handoffPhase,
        child: child,
      );
    }

    return child;
  }
}

/// Card overlay when this group's longForm session is paused by a shortForm event.
class _PausedLongFormCard extends StatelessWidget {
  final String groupName;
  final String? activeShortFormGroupId;
  final String? estimatedResumeTime;
  final List<Color> patternColors;
  final HandoffPhase handoffPhase;
  final Widget child;

  const _PausedLongFormCard({
    required this.groupName,
    this.activeShortFormGroupId,
    this.estimatedResumeTime,
    this.patternColors = const [],
    required this.handoffPhase,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Muted version of the original card
        Opacity(
          opacity: 0.6,
          child: child,
        ),

        // Paused status badge
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: NexGenPalette.accent.withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.pause_circle_outline,
                  size: 14,
                  color: NexGenPalette.accent.withOpacity(0.8),
                ),
                const SizedBox(width: 4),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Estimated resume time
        if (estimatedResumeTime != null)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Resumes $estimatedResumeTime',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ),
          ),

        // Pattern color preview strip at the bottom
        if (patternColors.isNotEmpty)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: patternColors),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String get _statusText {
    switch (handoffPhase) {
      case HandoffPhase.transitioning:
      case HandoffPhase.resumingLongForm:
        return 'Resuming...';
      case HandoffPhase.celebratingVictory:
        return 'Celebrating!';
      default:
        return 'Paused — game active';
    }
  }
}

/// Card overlay for the active shortForm group during a handoff.
class _ActiveShortFormCard extends StatelessWidget {
  final String groupName;
  final HandoffPhase handoffPhase;
  final Widget child;

  const _ActiveShortFormCard({
    required this.groupName,
    required this.handoffPhase,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,

        // "Syncing Now" active indicator with handoff context
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: NexGenPalette.accent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: NexGenPalette.accent.withOpacity(0.6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: NexGenPalette.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: NexGenPalette.accent.withOpacity(0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Syncing Now',
                  style: TextStyle(
                    color: NexGenPalette.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A banner widget shown when the user takes manual control during a handoff.
/// Informs them that Neighborhood Sync is paused.
class ManualOverrideBanner extends StatelessWidget {
  final VoidCallback? onDismiss;

  const ManualOverrideBanner({super.key, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.front_hand, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "You've taken manual control — Neighborhood Sync is paused for now",
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onDismiss != null)
            GestureDetector(
              onTap: onDismiss,
              child: const Icon(Icons.close, color: Colors.white54, size: 18),
            ),
        ],
      ),
    );
  }
}

/// Indicator shown when the longForm host is offline during resume.
class HostOfflineIndicator extends StatelessWidget {
  final String groupName;

  const HostOfflineIndicator({super.key, required this.groupName});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.grey.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, color: Colors.grey[400], size: 14),
          const SizedBox(width: 6),
          Text(
            'Running last known $groupName pattern — host is offline',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
