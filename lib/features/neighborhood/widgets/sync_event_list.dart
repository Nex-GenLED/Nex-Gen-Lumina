import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../models/sync_event.dart';
import '../providers/sync_event_providers.dart';
import '../services/season_boundary_service.dart';
import 'season_renewal_dialog.dart';
import 'sync_event_setup_screen.dart';

/// Displays all sync events for the active neighborhood group.
/// Used in both the Neighborhood Sync screen and Autopilot schedule view.
class SyncEventList extends ConsumerWidget {
  const SyncEventList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(syncEventsProvider);

    return eventsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: NexGenPalette.cyan),
      ),
      error: (e, _) => Center(
        child: Text('Error: $e', style: const TextStyle(color: Colors.white38)),
      ),
      data: (events) {
        if (events.isEmpty) {
          return _buildEmptyState(context);
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: events.length,
          itemBuilder: (context, index) => _SyncEventCard(event: events[index]),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.event_note, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          const Text(
            'No sync events scheduled',
            style: TextStyle(color: Colors.white38),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showSyncEventSetup(context),
            icon: const Icon(Icons.add),
            label: const Text('Create Sync Event'),
            style: OutlinedButton.styleFrom(
              foregroundColor: NexGenPalette.cyan,
              side: const BorderSide(color: NexGenPalette.cyan),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncEventCard extends ConsumerWidget {
  final SyncEvent event;

  const _SyncEventCard({required this.event});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(syncEventNotifierProvider.notifier);

    return Dismissible(
      key: Key(event.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.withOpacity(0.2),
        child: const Icon(Icons.delete, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Sync Event'),
            content: Text('Delete "${event.name}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => notifier.deleteSyncEvent(event.id),
      child: Card(
        color: event.isEnabled
            ? Colors.white.withOpacity(0.06)
            : Colors.white.withOpacity(0.03),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Icon(
            event.isGameDay ? Icons.sports_football : Icons.event,
            color: event.isEnabled ? NexGenPalette.cyan : Colors.white24,
          ),
          title: Text(
            event.name,
            style: TextStyle(
              color: event.isEnabled ? Colors.white : Colors.white38,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            _buildSubtitle(),
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (event.triggerType == SyncEventTriggerType.manual)
                IconButton(
                  icon: const Icon(Icons.play_arrow, size: 20),
                  color: NexGenPalette.cyan,
                  onPressed: () => notifier.manuallyStartEvent(event.id),
                  tooltip: 'Start Now',
                ),
              Switch(
                value: event.isEnabled,
                activeColor: NexGenPalette.cyan,
                onChanged: (_) => notifier.toggleSyncEvent(event.id),
              ),
            ],
          ),
          onTap: () => showSyncEventSetup(context, existingEvent: event),
        ),
      ),
    );
  }

  String _buildSubtitle() {
    final parts = <String>[];
    parts.add(event.triggerType.displayName);
    if (event.isSeasonSchedule) {
      parts.add('Season ${event.seasonYear ?? ''}');
      if (event.excludedGameIds.isNotEmpty) {
        parts.add('${event.excludedGameIds.length} skipped');
      }
    } else if (event.isRecurring) {
      parts.add('Recurring');
    }
    if (event.scheduledTime != null) {
      final t = event.scheduledTime!;
      final hour = t.hour > 12 ? t.hour - 12 : t.hour;
      final ampm = t.hour >= 12 ? 'PM' : 'AM';
      parts.add('$hour:${t.minute.toString().padLeft(2, '0')} $ampm');
    }
    return parts.join(' · ');
  }
}

/// Banner shown when a season schedule event needs renewal.
class SeasonRenewalBanner extends ConsumerWidget {
  const SeasonRenewalBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasonEvents = ref.watch(seasonScheduleSyncEventsProvider);
    if (seasonEvents.isEmpty) return const SizedBox.shrink();

    // Check the first season event for boundary status
    // (typically there's only one active season schedule per group)
    final event = seasonEvents.first;
    final boundaryAsync = ref.watch(seasonBoundaryProvider(event));

    return boundaryAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (info) {
        if (!info.needsRenewal) return const SizedBox.shrink();

        return Card(
          color: NexGenPalette.cyan.withValues(alpha: 0.1),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: NexGenPalette.cyan.withValues(alpha: 0.3),
            ),
          ),
          child: InkWell(
            onTap: () => showSeasonRenewalDialog(
              context,
              event: event,
              boundaryInfo: info,
            ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.autorenew,
                      color: NexGenPalette.cyan, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.status == SeasonStatus.ended
                              ? 'Season Complete'
                              : 'Season Ending Soon',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          info.status == SeasonStatus.ended
                              ? 'Tap to renew for next season'
                              : '${info.remainingGames} games left — renew for next season',
                          style:
                              TextStyle(color: Colors.grey.shade500, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: Colors.white38, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
