// +126 (c) — the two homeowner-facing surfaces of the persisted sync status:
// the status row on My Schedule and the chip on Home. Both read
// scheduleSyncStatusProvider and both offer the same Retry (runSyncNow).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_sync_status.dart';
import 'package:nexgen_command/theme.dart';

/// Icon and colour per state. Neutral states are cyan, never red; only a
/// real failure is red; an armed-but-unconfirmed pattern is amber.
({IconData icon, Color color}) scheduleSyncStateLook(ScheduleSyncState s) {
  switch (s) {
    case ScheduleSyncState.synced:
      return (icon: Icons.check_circle_rounded, color: Colors.green.shade400);
    case ScheduleSyncState.queued:
      return (icon: Icons.sync_rounded, color: NexGenPalette.cyan);
    case ScheduleSyncState.deferredOffLan:
      return (icon: Icons.home_outlined, color: NexGenPalette.cyan);
    case ScheduleSyncState.failed:
      return (icon: Icons.cloud_off_rounded, color: Colors.red.shade400);
    case ScheduleSyncState.writtenNotVerified:
      return (
        icon: Icons.warning_amber_rounded,
        color: Colors.orange.shade400
      );
    case ScheduleSyncState.drifted:
      // Something changed on the controller: amber, like an unconfirmed
      // pattern — the lights still work, the schedule is what is off.
      return (icon: Icons.sync_problem_rounded, color: Colors.orange.shade400);
  }
}

/// "just now" / "5m ago" / "2h ago" / "3d ago".
String scheduleSyncRelativeTime(DateTime t, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(t);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// The Retry every surface shares: a manual sync, always allowed.
Future<void> retryScheduleSync(WidgetRef ref) =>
    ref.read(schedulesProvider.notifier).runSyncNow();

/// The status row on My Schedule. Renders nothing until the account has ever
/// synced. Wraps freely (no ellipsis) and scrolls inside itself above a third
/// of the screen, like the row it replaces.
class ScheduleSyncStatusRow extends ConsumerWidget {
  const ScheduleSyncStatusRow({super.key, this.onRetry});

  /// Defaults to [retryScheduleSync]; tests pass a recorder.
  final Future<void> Function(WidgetRef ref)? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(scheduleSyncStatusProvider);
    if (status == null) return const SizedBox.shrink();
    final copy = ScheduleSyncCopy.forState(status.state);
    final look = scheduleSyncStateLook(status.state);
    final when = scheduleSyncRelativeTime(status.at);
    final text = copy.detail.isEmpty
        ? '${copy.headline} · $when'
        : '${copy.headline} ${copy.detail} · $when';

    final maxRowHeight = MediaQuery.sizeOf(context).height / 3;
    return Container(
      key: const ValueKey('schedule-sync-status-row'),
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxRowHeight),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(look.icon, size: 16, color: look.color),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 12, color: look.color),
                softWrap: true,
              ),
            ),
            if (copy.showsRetry) ...[
              const SizedBox(width: 6),
              TextButton(
                key: const ValueKey('schedule-sync-retry'),
                style: TextButton.styleFrom(
                  foregroundColor: look.color,
                  minimumSize: const Size(44, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => (onRetry ?? retryScheduleSync)(ref),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The chip on Home: one line and, where it helps, a Retry. Renders nothing
/// until the account has ever synced.
class ScheduleSyncHomeChip extends ConsumerWidget {
  const ScheduleSyncHomeChip({super.key, this.onRetry});

  final Future<void> Function(WidgetRef ref)? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(scheduleSyncStatusProvider);
    if (status == null) return const SizedBox.shrink();
    final copy = ScheduleSyncCopy.forState(status.state);
    final look = scheduleSyncStateLook(status.state);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        key: const ValueKey('schedule-sync-home-chip'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: look.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: look.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(look.icon, size: 16, color: look.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                copy.headline,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: look.color,
                ),
                softWrap: true,
              ),
            ),
            if (copy.showsRetry) ...[
              const SizedBox(width: 6),
              TextButton(
                key: const ValueKey('schedule-sync-chip-retry'),
                style: TextButton.styleFrom(
                  foregroundColor: look.color,
                  minimumSize: const Size(44, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => (onRetry ?? retryScheduleSync)(ref),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
