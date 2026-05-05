import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/commercial/commercial_event.dart';
import 'package:nexgen_command/services/commercial/commercial_events_providers.dart';

/// Sales & Events main screen.
///
/// Renders, in order:
///   1. Active-event banner (if any) with Apply Now / Deactivate.
///   2. Upcoming events list, ordered by start date.
///   3. Past events ExpansionTile (collapsed by default), gray-styled.
///
/// Empty state includes a "Create First Event" button. A FAB pushes
/// the create flow.
class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(commercialEventsProvider);
    final active = ref.watch(activeCommercialEventProvider);
    final upcoming = ref.watch(upcomingCommercialEventsProvider);
    final past = ref.watch(pastCommercialEventsProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: const Text('Sales & Events'),
        iconTheme: const IconThemeData(color: NexGenPalette.textHigh),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline,
                color: NexGenPalette.textMedium),
            tooltip:
                'Schedule lighting designs for sales, grand openings, '
                'holidays, and other events.',
            onPressed: () => _showFeatureInfo(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: NexGenPalette.cyan,
        foregroundColor: Colors.black,
        onPressed: () => context.push(AppRoutes.commercialEventsCreate),
        icon: const Icon(Icons.add),
        label: const Text('New Event'),
      ),
      body: eventsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Failed to load events: $e',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
        data: (all) {
          if (all.isEmpty) {
            return const _EmptyState();
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              if (active != null) ...[
                _ActiveEventBanner(event: active),
                const SizedBox(height: 20),
              ],
              if (upcoming.isNotEmpty) ...[
                Text('Upcoming Events',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...upcoming.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _EventCard(event: e),
                    )),
                const SizedBox(height: 20),
              ],
              if (past.isNotEmpty) _PastSection(events: past),
            ],
          );
        },
      ),
    );
  }

  void _showFeatureInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Sales & Events',
            style: TextStyle(color: NexGenPalette.textHigh)),
        content: const Text(
          'Create events to sync your lighting with your marketing '
          'calendar. Lights can automatically activate your event '
          'theme on the start date and revert when it ends.\n\n'
          'Lumina AI can suggest brand-aligned lighting designs based '
          'on your event description.',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it',
                style: TextStyle(color: NexGenPalette.cyan)),
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_available,
                size: 64, color: NexGenPalette.cyan),
            const SizedBox(height: 16),
            Text('No Events Yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Create events to sync your lighting with your marketing '
              'calendar. Lights will automatically activate your event '
              'theme and revert when it ends.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  context.push(AppRoutes.commercialEventsCreate),
              icon: const Icon(Icons.add),
              label: const Text('Create First Event'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Active event banner ──────────────────────────────────────────────────

class _ActiveEventBanner extends ConsumerWidget {
  const _ActiveEventBanner({required this.event});
  final CommercialEvent event;

  Future<void> _applyDesign(BuildContext context, WidgetRef ref) async {
    final payload = event.designPayload;
    if (payload == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No design attached to this event.'),
          backgroundColor: NexGenPalette.amber,
        ),
      );
      return;
    }
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No controller connected — apply unavailable.'),
          backgroundColor: NexGenPalette.amber,
        ),
      );
      return;
    }
    try {
      await repo.applyJson(payload);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Applied "${event.designName ?? event.name}".'),
          backgroundColor: NexGenPalette.cyan,
        ),
      );
    } catch (e) {
      debugPrint('Events: applyJson failed — $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Apply failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NexGenPalette.cyan.withValues(alpha: 0.18),
            NexGenPalette.gunmetal90,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: NexGenPalette.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '● ACTIVE NOW',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5),
                ),
              ),
              const Spacer(),
              Text(
                _eventDateRange(event),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(event.name,
              style: Theme.of(context).textTheme.titleLarge),
          if (event.designName != null && event.designName!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(event.designName!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: NexGenPalette.cyan)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _applyDesign(context, ref),
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('Apply Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Past section ─────────────────────────────────────────────────────────

class _PastSection extends StatelessWidget {
  const _PastSection({required this.events});
  final List<CommercialEvent> events;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Strip ExpansionTile's default divider above/below.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: ExpansionTile(
          iconColor: NexGenPalette.textMedium,
          collapsedIconColor: NexGenPalette.textMedium,
          title: Text('Past Events (${events.length})',
              style: Theme.of(context).textTheme.titleSmall),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: events
              .map((e) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _EventCard(event: e, isPast: true),
                  ))
              .toList(growable: false),
        ),
      ),
    );
  }
}

// ─── Single event card ────────────────────────────────────────────────────

class _EventCard extends ConsumerWidget {
  const _EventCard({required this.event, this.isPast = false});
  final CommercialEvent event;
  final bool isPast;

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Delete event?',
            style: TextStyle(color: NexGenPalette.textHigh)),
        content: Text(
          'This removes "${event.name}" and any schedules it created.',
          style: const TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Clean up associated ScheduleItems before deleting the event so we
    // don't orphan stale schedules. Remove failures are non-fatal —
    // the schedule may already have been deleted manually.
    final notifier = ref.read(schedulesProvider.notifier);
    if (event.scheduleItemId != null) {
      try {
        await notifier.remove(event.scheduleItemId!);
      } catch (e) {
        debugPrint('Events: cleanup activate schedule failed — $e');
      }
    }
    if (event.revertScheduleItemId != null) {
      try {
        await notifier.remove(event.revertScheduleItemId!);
      } catch (e) {
        debugPrint('Events: cleanup revert schedule failed — $e');
      }
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('commercial_events')
          .doc(event.eventId)
          .delete();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted "${event.name}".'),
          backgroundColor: NexGenPalette.amber,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = isPast ? NexGenPalette.textMedium : NexGenPalette.textHigh;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconFor(event.type),
                size: 20, color: NexGenPalette.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: color)),
                const SizedBox(height: 2),
                Text(_eventDateRange(event),
                    style: Theme.of(context).textTheme.bodySmall),
                if (event.designName != null &&
                    event.designName!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          size: 12, color: NexGenPalette.cyan),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(event.designName!,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: NexGenPalette.cyan)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!isPast)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 20),
              onPressed: () => _confirmAndDelete(context, ref),
            ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────

IconData _iconFor(EventType type) {
  switch (type) {
    case EventType.sale:
      return Icons.local_offer_outlined;
    case EventType.grandOpening:
      return Icons.celebration_outlined;
    case EventType.holiday:
      return Icons.cake_outlined;
    case EventType.corporate:
      return Icons.business_outlined;
    case EventType.community:
      return Icons.groups_outlined;
    case EventType.custom:
      return Icons.event_note_outlined;
  }
}

/// Compact date range for an event card. Same logical format as the
/// manual formatter on the brand-correction card.
String _eventDateRange(CommercialEvent e) {
  final s = e.startDate;
  final t = e.endDate;
  final sameDay = s.year == t.year && s.month == t.month && s.day == t.day;
  if (sameDay) return _formatDate(s);
  final sameYear = s.year == t.year;
  if (sameYear) {
    return '${_formatMonthDay(s)} – ${_formatMonthDay(t)}, ${t.year}';
  }
  return '${_formatDate(s)} – ${_formatDate(t)}';
}

String _formatDate(DateTime dt) =>
    '${_monthAbbr(dt.month)} ${dt.day}, ${dt.year}';

String _formatMonthDay(DateTime dt) =>
    '${_monthAbbr(dt.month)} ${dt.day}';

String _monthAbbr(int month) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return months[month - 1];
}
