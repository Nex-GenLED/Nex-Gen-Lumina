import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../neighborhood_providers.dart';

/// Result of the sync warning dialog.
enum SyncWarningResult {
  /// User cancelled - don't make any changes.
  cancel,

  /// User wants to pause their sync participation and then make changes.
  pauseAndContinue,

  /// User wants to continue without pausing (will break their sync).
  continueAnyway,
}

/// A dialog that warns users when they're about to change their lights
/// during an active neighborhood sync.
///
/// Usage:
/// ```dart
/// final result = await SyncWarningDialog.show(context, ref);
/// if (result == SyncWarningResult.cancel) return;
/// if (result == SyncWarningResult.pauseAndContinue) {
///   await ref.read(neighborhoodNotifierProvider.notifier).pauseMySync();
/// }
/// // Proceed with the light change...
/// ```
class SyncWarningDialog extends ConsumerWidget {
  const SyncWarningDialog({super.key});

  /// Shows the sync warning dialog if the user is in an active sync.
  /// Returns null if no active sync (safe to proceed).
  /// Returns the user's choice if in active sync.
  static Future<SyncWarningResult?> showIfNeeded(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final syncStatus = ref.read(userSyncStatusProvider);

    // No warning needed if not in active sync
    if (!syncStatus.isInActiveSync) {
      return null;
    }

    // Already paused - no warning needed
    if (syncStatus.isPaused) {
      return null;
    }

    // Show the warning dialog
    return showDialog<SyncWarningResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SyncWarningDialog(),
    );
  }

  /// Helper method that handles the common pattern of checking sync
  /// and optionally pausing before executing an action.
  ///
  /// Returns true if the action should proceed, false if cancelled.
  static Future<bool> checkAndProceed(
    BuildContext context,
    WidgetRef ref, {
    VoidCallback? onPaused,
  }) async {
    final result = await showIfNeeded(context, ref);

    // No active sync - proceed
    if (result == null) return true;

    // User cancelled
    if (result == SyncWarningResult.cancel) return false;

    // User wants to pause first
    if (result == SyncWarningResult.pauseAndContinue) {
      await ref.read(neighborhoodNotifierProvider.notifier).pauseMySync();
      onPaused?.call();
    }

    // Either pauseAndContinue or continueAnyway - proceed
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(userSyncStatusProvider);
    final theme = Theme.of(context);

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.orange.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      title: Row(
        children: [
          Icon(
            Icons.sync,
            color: Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Active Neighborhood Sync',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current sync info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.home_outlined,
                  color: Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        syncStatus.activeGroup?.name ?? 'Neighborhood Sync',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (syncStatus.activePatternName != null)
                        Text(
                          'Running: ${syncStatus.activePatternName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'You are currently participating in a neighborhood sync. '
            'Changing your lights will disrupt the coordinated pattern.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Would you like to temporarily pause your participation?',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        // Cancel button
        TextButton(
          onPressed: () => Navigator.of(context).pop(SyncWarningResult.cancel),
          child: const Text('Cancel'),
        ),
        // Continue without pausing (breaks sync)
        TextButton(
          onPressed: () => Navigator.of(context).pop(SyncWarningResult.continueAnyway),
          child: Text(
            'Continue Anyway',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        // Pause and continue (recommended)
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(SyncWarningResult.pauseAndContinue),
          icon: const Icon(Icons.pause, size: 18),
          label: const Text('Pause & Continue'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.orange,
          ),
        ),
      ],
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    );
  }
}

/// A banner widget that can be shown at the top of screens to indicate
/// the user is in an active neighborhood sync.
class ActiveSyncBanner extends ConsumerWidget {
  final VoidCallback? onTap;

  const ActiveSyncBanner({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(userSyncStatusProvider);

    if (!syncStatus.isInActiveSync) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isPaused = syncStatus.isPaused;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isPaused
                ? [Colors.grey.shade700, Colors.grey.shade600]
                : [Colors.orange.shade700, Colors.orange.shade600],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              Icon(
                isPaused ? Icons.pause_circle : Icons.sync,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isPaused
                          ? 'Sync Paused'
                          : 'Neighborhood Sync Active',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      isPaused
                          ? 'Tap to resume participation'
                          : '${syncStatus.activeGroup?.name ?? "Group"} - ${syncStatus.activePatternName ?? "Pattern"}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.7),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small indicator chip that shows sync status.
class SyncStatusChip extends ConsumerWidget {
  const SyncStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(userSyncStatusProvider);

    if (!syncStatus.isInActiveSync) {
      return const SizedBox.shrink();
    }

    final isPaused = syncStatus.isPaused;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isPaused ? Colors.grey : Colors.orange,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPaused ? Icons.pause : Icons.sync,
            color: Colors.white,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            isPaused ? 'Paused' : 'Syncing',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
