import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../models/sync_event.dart';
import '../neighborhood_providers.dart';
import '../providers/sync_event_providers.dart';
import '../services/sync_notification_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SYNC EVENT PARTICIPATION SETTINGS
// ═════════════════════════════════════════════════════════════════════════════

/// Settings panel for a member's Sync Event participation preferences.
///
/// Shows category opt-ins, post-event behavior preference, and per-event
/// skip toggles. Embedded in the Neighborhood Sync settings screen.
class SyncEventParticipationSettings extends ConsumerWidget {
  const SyncEventParticipationSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(myConsentProvider).valueOrNull;
    final events = ref.watch(enabledSyncEventsProvider);
    final notifier = ref.read(syncEventNotifierProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Sync Event Participation',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Choose which types of automated sync events your lights can join.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),

        // ── Category Opt-Ins ─────────────────────────────────────────
        _CategoryToggle(
          title: 'Game Day Syncs',
          subtitle: 'Automatically join when a scheduled game starts',
          icon: Icons.sports_football,
          isOptedIn: consent?.isOptedInTo(SyncEventCategory.gameDay) ?? false,
          onToggle: () => notifier.toggleCategoryOptIn(SyncEventCategory.gameDay),
        ),
        _CategoryToggle(
          title: 'Holiday Syncs',
          subtitle: 'Join coordinated holiday lighting events',
          icon: Icons.celebration,
          isOptedIn: consent?.isOptedInTo(SyncEventCategory.holiday) ?? false,
          onToggle: () => notifier.toggleCategoryOptIn(SyncEventCategory.holiday),
        ),
        _CategoryToggle(
          title: 'Custom Event Syncs',
          subtitle: 'Join any other group-coordinated events',
          icon: Icons.event,
          isOptedIn:
              consent?.isOptedInTo(SyncEventCategory.customEvent) ?? false,
          onToggle: () =>
              notifier.toggleCategoryOptIn(SyncEventCategory.customEvent),
        ),

        const Divider(color: Colors.white12, height: 32),

        // ── Post-Event Behavior ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.nights_stay, color: Colors.white38, size: 18),
              const SizedBox(width: 8),
              const Text(
                'After events end, my lights should:',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<PostEventBehavior>(
            segments: const [
              ButtonSegment(
                value: PostEventBehavior.returnToAutopilot,
                label: Text('Resume', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.auto_awesome, size: 14),
              ),
              ButtonSegment(
                value: PostEventBehavior.stayOn,
                label: Text('Stay On', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.lightbulb_outline, size: 14),
              ),
              ButtonSegment(
                value: PostEventBehavior.turnOff,
                label: Text('Turn Off', style: TextStyle(fontSize: 11)),
                icon: Icon(Icons.power_settings_new, size: 14),
              ),
            ],
            selected: {
              consent?.preferredPostBehavior ??
                  PostEventBehavior.returnToAutopilot
            },
            onSelectionChanged: (values) {
              notifier.setPostEventBehavior(values.first);
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return NexGenPalette.cyan.withOpacity(0.2);
                }
                return Colors.white10;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return NexGenPalette.cyan;
                }
                return Colors.white54;
              }),
            ),
          ),
        ),

        // ── Upcoming Events (Skip Toggle) ────────────────────────────
        if (events.isNotEmpty) ...[
          const Divider(color: Colors.white12, height: 32),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Upcoming Events',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ...events.map((event) => _UpcomingEventTile(
                event: event,
                isSkipping: consent?.isSkippingEvent(event.id) ?? false,
                onToggleSkip: (skip) {
                  notifier.toggleSkipNext(event.id, skip: skip);
                },
              )),
        ],

        // ── Notification Preferences ──────────────────────────────────
        const Divider(color: Colors.white12, height: 32),
        const _SyncNotificationSettings(),

        const SizedBox(height: 16),
      ],
    );
  }
}

/// Granular notification preference toggles for sync events.
class _SyncNotificationSettings extends ConsumerWidget {
  const _SyncNotificationSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(syncNotificationPrefsProvider);
    final prefs = prefsAsync.valueOrNull ?? const SyncNotificationPreferences();
    final service = ref.read(syncNotificationServiceProvider);
    final groupId = ref.watch(activeNeighborhoodIdProvider);

    void save(SyncNotificationPreferences updated) {
      if (groupId == null) return;
      service.savePreferences(groupId, updated);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Sync Notifications',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            'Control which push notifications you receive during sync events.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Card(
            color: Colors.white.withOpacity(0.04),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Enable Sync Notifications',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  value: prefs.enabled,
                  activeColor: NexGenPalette.cyan,
                  onChanged: (v) => save(prefs.copyWith(enabled: v)),
                ),
                if (prefs.enabled) ...[
                  const Divider(color: Colors.white12, height: 1, indent: 16),
                  SwitchListTile(
                    title: const Text(
                      'Session Start',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    subtitle: const Text(
                      'When a sync session kicks off',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    value: prefs.sessionStart,
                    activeColor: NexGenPalette.cyan,
                    onChanged: (v) => save(prefs.copyWith(sessionStart: v)),
                  ),
                  const Divider(color: Colors.white12, height: 1, indent: 16),
                  SwitchListTile(
                    title: const Text(
                      'Score Celebrations',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    subtitle: const Text(
                      'Your lights are the celebration — notifications optional',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    value: prefs.scoreCelebrations,
                    activeColor: NexGenPalette.cyan,
                    onChanged: (v) =>
                        save(prefs.copyWith(scoreCelebrations: v)),
                  ),
                  const Divider(color: Colors.white12, height: 1, indent: 16),
                  SwitchListTile(
                    title: const Text(
                      'Session End',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    subtitle: const Text(
                      'When the sync session wraps up',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    value: prefs.sessionEnd,
                    activeColor: NexGenPalette.cyan,
                    onChanged: (v) => save(prefs.copyWith(sessionEnd: v)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Toggle tile for a participation category.
class _CategoryToggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isOptedIn;
  final VoidCallback onToggle;

  const _CategoryToggle({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isOptedIn,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Card(
        color: isOptedIn
            ? NexGenPalette.cyan.withOpacity(0.08)
            : Colors.white.withOpacity(0.04),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SwitchListTile(
          secondary: Icon(
            icon,
            color: isOptedIn ? NexGenPalette.cyan : Colors.white38,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: isOptedIn ? Colors.white : Colors.white70,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          value: isOptedIn,
          activeColor: NexGenPalette.cyan,
          onChanged: (_) => onToggle(),
        ),
      ),
    );
  }
}

/// Tile showing an upcoming event with "Skip Next" toggle.
class _UpcomingEventTile extends StatelessWidget {
  final SyncEvent event;
  final bool isSkipping;
  final ValueChanged<bool> onToggleSkip;

  const _UpcomingEventTile({
    required this.event,
    required this.isSkipping,
    required this.onToggleSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Card(
        color: Colors.white.withOpacity(0.04),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Icon(
            event.isGameDay ? Icons.sports : Icons.event,
            color: isSkipping ? Colors.white24 : NexGenPalette.cyan,
          ),
          title: Text(
            event.name,
            style: TextStyle(
              color: isSkipping ? Colors.white38 : Colors.white,
              fontSize: 14,
              decoration: isSkipping ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Text(
            event.triggerType.displayName,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          trailing: TextButton(
            onPressed: () => onToggleSkip(!isSkipping),
            child: Text(
              isSkipping ? 'Rejoin' : 'Skip Next',
              style: TextStyle(
                color: isSkipping ? NexGenPalette.cyan : Colors.orange,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Active sync session banner with "Not Tonight" opt-out.
class ActiveSyncSessionBanner extends ConsumerWidget {
  const ActiveSyncSessionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeSyncEventSessionProvider).valueOrNull;
    final isParticipating = ref.watch(isParticipatingInSyncProvider);
    final isCelebrating = ref.watch(isCelebratingProvider);

    if (session == null) return const SizedBox.shrink();

    final notifier = ref.read(syncEventNotifierProvider.notifier);

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCelebrating
              ? [Colors.orange.withOpacity(0.3), Colors.red.withOpacity(0.3)]
              : [
                  NexGenPalette.cyan.withOpacity(0.2),
                  NexGenPalette.cyan.withOpacity(0.1),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCelebrating
              ? Colors.orange.withOpacity(0.5)
              : NexGenPalette.cyan.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCelebrating ? Icons.celebration : Icons.sync,
            color: isCelebrating ? Colors.orange : NexGenPalette.cyan,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCelebrating ? 'Score!' : 'Neighborhood Sync Active',
                  style: TextStyle(
                    color: isCelebrating ? Colors.orange : NexGenPalette.cyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  isParticipating
                      ? 'Your lights are synced with ${session.activeParticipantUids.length} homes'
                      : 'Tap to join the sync session',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          if (isParticipating)
            TextButton(
              onPressed: () => notifier.declineCurrentSession(),
              child: const Text(
                'Not tonight',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            )
          else
            TextButton(
              onPressed: () => notifier.joinCurrentSession(),
              child: const Text(
                'Join',
                style: TextStyle(color: NexGenPalette.cyan, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
