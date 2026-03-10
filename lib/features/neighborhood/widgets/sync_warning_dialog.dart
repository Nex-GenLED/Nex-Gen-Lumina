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

/// Handles Neighborhood Sync override behavior.
///
/// RULE: Any direct user action on their own system (power toggle, pattern
/// change, color change, brightness adjustment, etc.) immediately overrides
/// the current sync — no dialog, no blocking. The device executes the user's
/// command first, then the sync state is updated silently.
class SyncWarningDialog extends ConsumerWidget {
  const SyncWarningDialog({super.key});

  /// Shows the sync warning dialog if the user is in an active sync.
  /// Returns null if no active sync (safe to proceed).
  /// Returns the user's choice if in active sync.
  ///
  /// NOTE: In most cases prefer [checkAndProceed] which auto-pauses silently.
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

    // Auto-pause silently and return pauseAndContinue — no dialog shown.
    // User's lights, user's control.
    await ref.read(neighborhoodNotifierProvider.notifier).pauseMySync();
    debugPrint('Auto-paused Neighborhood Sync for local user action');
    return SyncWarningResult.pauseAndContinue;
  }

  /// Non-blocking sync check. Always returns true (user action always proceeds).
  ///
  /// If the user is actively participating in a Neighborhood Sync, this
  /// silently pauses their participation so the local action takes effect
  /// immediately. Other houses continue their sync unaffected.
  static Future<bool> checkAndProceed(
    BuildContext context,
    WidgetRef ref, {
    VoidCallback? onPaused,
  }) async {
    final syncStatus = ref.read(userSyncStatusProvider);

    // Not in sync or already paused — just proceed
    if (!syncStatus.isInActiveSync || syncStatus.isPaused) {
      return true;
    }

    // Auto-pause silently — no dialog, no blocking
    try {
      await ref.read(neighborhoodNotifierProvider.notifier).pauseMySync();
      debugPrint('Auto-paused Neighborhood Sync for local user action');
      onPaused?.call();
    } catch (e) {
      debugPrint('Failed to auto-pause sync: $e');
      // Still proceed — user action always takes priority
    }

    return true;
  }

  /// Standalone function to auto-pause sync from non-widget contexts (e.g., WledNotifier).
  /// Call this from providers/services that don't have BuildContext.
  static Future<void> autoPauseIfInSync(Ref ref) async {
    try {
      final syncStatus = ref.read(userSyncStatusProvider);
      if (!syncStatus.isInActiveSync || syncStatus.isPaused) return;

      await ref.read(neighborhoodNotifierProvider.notifier).pauseMySync();
      debugPrint('Auto-paused Neighborhood Sync (provider-level override)');
    } catch (e) {
      // Silent fail — never block the user's action
      debugPrint('Auto-pause sync failed (non-critical): $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // This dialog is kept for backward compatibility but is no longer shown
    // by checkAndProceed. It can still be used for explicit confirmation flows.
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
          const Icon(Icons.sync, color: Colors.orange, size: 28),
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
                const Icon(Icons.home_outlined, color: Colors.orange, size: 20),
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
            'Your sync participation has been paused so your '
            'local changes can take effect. Other homes in your '
            'group will continue their sync.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(SyncWarningResult.continueAnyway),
          child: const Text('OK'),
        ),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    );
  }
}

/// A banner widget shown at the top of screens indicating sync status.
///
/// When the user is actively syncing: shows status info.
/// When the user has paused (via local override): shows a one-tap "Rejoin" button.
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
      onTap: isPaused
          ? () async {
              // One-tap rejoin
              await ref.read(neighborhoodNotifierProvider.notifier).resumeMySync();
            }
          : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isPaused
                ? [Colors.cyan.shade700, Colors.cyan.shade600]
                : [Colors.orange.shade700, Colors.orange.shade600],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              Icon(
                isPaused ? Icons.sync_disabled : Icons.sync,
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
                          ? 'Neighborhood Sync is active'
                          : 'Neighborhood Sync Active',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      isPaused
                          ? 'You left sync — Tap to rejoin'
                          : '${syncStatus.activeGroup?.name ?? "Group"} - ${syncStatus.activePatternName ?? "Pattern"}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isPaused)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Rejoin',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
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

    return GestureDetector(
      onTap: isPaused
          ? () async {
              await ref.read(neighborhoodNotifierProvider.notifier).resumeMySync();
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isPaused ? Colors.cyan.shade700 : Colors.orange,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPaused ? Icons.sync_disabled : Icons.sync,
              color: Colors.white,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              isPaused ? 'Rejoin Sync' : 'Syncing',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
