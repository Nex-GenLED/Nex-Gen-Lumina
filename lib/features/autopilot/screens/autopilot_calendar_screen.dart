// lib/features/autopilot/screens/autopilot_calendar_screen.dart
//
// Unified calendar view showing both autopilot-generated events (⚡) and
// user-created protected events (📌) in a single 7-day grid.
//
// Features
//   - Color-coded blocks by event type
//   - Tap autopilot event: detail sheet with "Edit" (converts to user event)
//   - Tap user event: detail sheet with "Remove Protection" option
//   - Pull-to-refresh triggers weekly regeneration on demand
//   - Week navigator (previous / current / next week)

import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_conflict_dialog.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/autopilot/autopilot_schedule_generator.dart';
import 'package:nexgen_command/features/autopilot/services/autopilot_event_repository.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/ai/pixel_strip_preview.dart';
import 'package:nexgen_command/models/autopilot_event.dart';
import 'package:nexgen_command/models/user_event.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/utils/time_format.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Currently viewed week start (always a Monday).
final _viewedWeekProvider = StateProvider<DateTime>(
    (ref) => upcomingWeekStart(DateTime.now()));

final _autopilotEventsProvider =
    StreamProvider.autoDispose.family<List<AutopilotEvent>, DateTime>(
        (ref, weekStart) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return ref
      .read(autopilotEventRepositoryProvider)
      .streamWeekEvents(uid, weekStart);
});

final _userEventsProvider =
    StreamProvider.autoDispose<List<UserEvent>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();
  return ref
      .read(autopilotEventRepositoryProvider)
      .streamUserEvents(uid);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class AutopilotCalendarScreen extends ConsumerStatefulWidget {
  const AutopilotCalendarScreen({super.key});

  @override
  ConsumerState<AutopilotCalendarScreen> createState() =>
      _AutopilotCalendarScreenState();
}

class _AutopilotCalendarScreenState
    extends ConsumerState<AutopilotCalendarScreen> {
  _SelectedItem? _selected;
  bool _regenerating = false;

  @override
  Widget build(BuildContext context) {
    final weekStart = ref.watch(_viewedWeekProvider);
    final autopilotAsync =
        ref.watch(_autopilotEventsProvider(weekStart));
    final userEventsAsync = ref.watch(_userEventsProvider);

    final autopilotEvents =
        autopilotAsync.maybeWhen(data: (d) => d, orElse: () => <AutopilotEvent>[]);
    final allUserEvents =
        userEventsAsync.maybeWhen(data: (d) => d, orElse: () => <UserEvent>[]);

    // Filter user events to the displayed week.
    final weekEnd = weekEndFor(weekStart);
    final userEventsThisWeek = allUserEvents
        .where((e) => e.isOnDay(weekStart) || _isInRange(e, weekStart, weekEnd))
        .toList();

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Autopilot Calendar'),
        actions: [
          // Week navigation
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous week',
            onPressed: () => ref.read(_viewedWeekProvider.notifier).state =
                weekStart.subtract(const Duration(days: 7)),
          ),
          TextButton(
            onPressed: () => ref.read(_viewedWeekProvider.notifier).state =
                upcomingWeekStart(DateTime.now()),
            child: const Text('This Week',
                style: TextStyle(color: NexGenPalette.cyan, fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next week',
            onPressed: () => ref.read(_viewedWeekProvider.notifier).state =
                weekStart.add(const Duration(days: 7)),
          ),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            color: NexGenPalette.cyan,
            onRefresh: () => _runManualRegen(weekStart),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Legend
                SliverToBoxAdapter(child: _buildLegend()),

                // 7-day grid
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final day = weekStart.add(Duration(days: i));
                        final dow = day.weekday;

                        final dayAuto = autopilotEvents
                            .where((e) => e.dayOfWeek == dow)
                            .toList()
                          ..sort((a, b) =>
                              a.startTime.compareTo(b.startTime));

                        final dayUser = userEventsThisWeek
                            .where((e) => e.isOnDay(day))
                            .toList()
                          ..sort((a, b) =>
                              a.startTime.compareTo(b.startTime));

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _CalendarDayCard(
                            day: day,
                            autopilotEvents: dayAuto,
                            userEvents: dayUser,
                            onAutopilotTap: (e) =>
                                setState(() => _selected = _SelectedItem.autopilot(e)),
                            onUserTap: (e) =>
                                setState(() => _selected = _SelectedItem.user(e)),
                          ),
                        );
                      },
                      childCount: 7,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Regenerating overlay
          if (_regenerating)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black45,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: NexGenPalette.cyan),
                      SizedBox(height: 12),
                      Text('Regenerating schedule…',
                          style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),

          // Event detail sheet
          if (_selected != null)
            _DetailSheet(
              selected: _selected!,
              onDismiss: () => setState(() => _selected = null),
              onConvertToUserEvent: (autopilotEvent) =>
                  _convertToUserEvent(autopilotEvent),
              onRemoveProtection: (userEvent) =>
                  _removeProtection(userEvent),
            ),
        ],
      ),
    );
  }

  bool _isInRange(UserEvent e, DateTime start, DateTime end) =>
      e.startTime.isBefore(end) && e.endTime.isAfter(start);

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          _LegendDot(
              color: NexGenPalette.cyan.withValues(alpha: 0.8),
              label: '⚡ Autopilot'),
          const SizedBox(width: 16),
          _LegendDot(color: const Color(0xFF4CAF50), label: '🏈 Game'),
          const SizedBox(width: 16),
          _LegendDot(
              color: const Color(0xFFE91E63), label: '🎉 Holiday'),
          const SizedBox(width: 16),
          _LegendDot(color: Colors.white54, label: '📌 Yours'),
        ],
      ),
    );
  }

  Future<void> _runManualRegen(DateTime weekStart) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final profile = ref.read(currentUserProfileProvider).maybeWhen(
          data: (p) => p,
          orElse: () => null,
        );
    if (profile == null) return;

    setState(() => _regenerating = true);
    try {
      final repo = ref.read(autopilotEventRepositoryProvider);
      final calEntries = ref.read(calendarScheduleProvider);
      final result = await repo.runWeeklyRegeneration(
        uid: uid,
        profile: profile,
        sportingEvents: const [],
        holidays: const [],
        weekGeneration:
            DateTime.now().millisecondsSinceEpoch ~/ (7 * 86400000),
        calendarEntries: calEntries,
      );

      // Show conflict dialog if policy is 'ask' and conflicts were found
      if (result.hasConflicts && mounted) {
        final resolution =
            await showAutopilotConflictDialog(context, result.conflicts);

        if (resolution.choice != AutopilotConflictChoice.cancel) {
          final conflictDateKeys =
              result.conflicts.map((c) => c.dateKey).toSet();

          if (resolution.choice == AutopilotConflictChoice.keepMine) {
            // Remove autopilot events that conflict
            for (final dk in conflictDateKeys) {
              for (final event in result.events) {
                final eDk =
                    '${event.startTime.year}-${event.startTime.month.toString().padLeft(2, '0')}-${event.startTime.day.toString().padLeft(2, '0')}';
                if (eDk == dk) {
                  await repo.deleteEvent(uid, event.id);
                }
              }
            }
          }
          // useAutopilot and merge are already handled by the diff

          // Persist the policy if user checked "Remember"
          if (resolution.remember) {
            final policy = resolution.choice == AutopilotConflictChoice.keepMine
                ? AutopilotConflictPolicy.keepMine
                : AutopilotConflictPolicy.trustAutopilot;
            await saveConflictPolicy(ref, policy);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Regeneration failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _convertToUserEvent(AutopilotEvent event) async {
    setState(() => _selected = null);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final repo = ref.read(autopilotEventRepositoryProvider);
    final result = await repo.convertToUserEvent(uid, event);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result != null
            ? '📌 "${event.patternName}" is now protected'
            : 'Could not convert event'),
      ));
    }
  }

  Future<void> _removeProtection(UserEvent event) async {
    setState(() => _selected = null);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final repo = ref.read(autopilotEventRepositoryProvider);
    await repo.deleteUserEvent(uid, event.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '"${event.patternName}" returned to autopilot control')),
      );
    }
  }

}

// ---------------------------------------------------------------------------
// _CalendarDayCard
// ---------------------------------------------------------------------------

class _CalendarDayCard extends StatelessWidget {
  final DateTime day;
  final List<AutopilotEvent> autopilotEvents;
  final List<UserEvent> userEvents;
  final ValueChanged<AutopilotEvent> onAutopilotTap;
  final ValueChanged<UserEvent> onUserTap;

  const _CalendarDayCard({
    required this.day,
    required this.autopilotEvents,
    required this.userEvents,
    required this.onAutopilotTap,
    required this.onUserTap,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;
    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final label = dayLabels[day.weekday - 1];

    final hasEvents =
        autopilotEvents.isNotEmpty || userEvents.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isToday
              ? NexGenPalette.cyan.withValues(alpha: 0.5)
              : NexGenPalette.line.withValues(alpha: 0.4),
          width: isToday ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isToday
                        ? NexGenPalette.cyan.withValues(alpha: 0.2)
                        : Colors.transparent,
                    border: isToday
                        ? Border.all(
                            color: NexGenPalette.cyan.withValues(alpha: 0.6))
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isToday
                              ? NexGenPalette.cyan
                              : NexGenPalette.textMedium,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isToday ? NexGenPalette.cyan : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (!hasEvents)
                  const Text(
                    'No events',
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 12),
                  ),
              ],
            ),

            // Events
            if (hasEvents) ...[
              const SizedBox(height: 10),

              // Autopilot events
              ...autopilotEvents.map((e) => _AutopilotEventTile(
                    event: e,
                    onTap: () => onAutopilotTap(e),
                  )),

              // User events
              ...userEvents.map((e) => _UserEventTile(
                    event: e,
                    onTap: () => onUserTap(e),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Event tiles
// ---------------------------------------------------------------------------

/// Extract [Color]s from a WLED payload's seg→col arrays.
/// Falls back to [fallback] wrapped in a single-element list.
List<Color> _colorsFromPayload(Map<String, dynamic>? payload, Color fallback) {
  if (payload != null) {
    final seg = payload['seg'];
    if (seg is List && seg.isNotEmpty) {
      final col = (seg[0] as Map<String, dynamic>?)?['col'];
      if (col is List && col.isNotEmpty) {
        final parsed = col
            .whereType<List>()
            .where((c) => c.length >= 3)
            .map<Color>((c) => Color.fromARGB(
                  255,
                  (c[0] as num).toInt().clamp(0, 255),
                  (c[1] as num).toInt().clamp(0, 255),
                  (c[2] as num).toInt().clamp(0, 255),
                ))
            .where((c) => c != const Color(0xFF000000)) // skip black/off
            .toList();
        if (parsed.isNotEmpty) return parsed;
      }
    }
  }
  return [fallback];
}

class _AutopilotEventTile extends ConsumerWidget {
  final AutopilotEvent event;
  final VoidCallback onTap;

  const _AutopilotEventTile({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = event.displayColor ?? event.eventType.accentColor;
    final timeFormat = ref.watch(timeFormatPreferenceProvider);
    final start = formatTime(event.startTime, timeFormat: timeFormat);
    final end = formatTime(event.endTime, timeFormat: timeFormat);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: PixelStripPreview(
                colors: _colorsFromPayload(event.wledPayload, color),
                pixelCount: 8,
                height: 24,
                borderRadius: 6,
                animate: false,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.patternName,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$start – $end  •  ${event.eventType.displayLabel}',
                    style: TextStyle(
                        color: color.withValues(alpha: 0.65), fontSize: 11),
                  ),
                ],
              ),
            ),
            Text('⚡',
                style:
                    TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

class _UserEventTile extends ConsumerWidget {
  final UserEvent event;
  final VoidCallback onTap;

  const _UserEventTile({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const color = NexGenPalette.cyan;
    final timeFormat = ref.watch(timeFormatPreferenceProvider);
    final start = formatTime(event.startTime, timeFormat: timeFormat);
    final end = formatTime(event.endTime, timeFormat: timeFormat);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: PixelStripPreview(
                colors: _colorsFromPayload(event.patternData, color),
                pixelCount: 8,
                height: 24,
                borderRadius: 6,
                animate: false,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.patternName,
                    style: const TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$start – $end  •  Protected',
                    style:
                        TextStyle(color: color.withValues(alpha: 0.65), fontSize: 11),
                  ),
                ],
              ),
            ),
            Text('📌',
                style: TextStyle(
                    fontSize: 10, color: color.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SelectedItem — discriminated union for autopilot vs user event
// ---------------------------------------------------------------------------

class _SelectedItem {
  final AutopilotEvent? autopilotEvent;
  final UserEvent? userEvent;

  const _SelectedItem._({this.autopilotEvent, this.userEvent});

  factory _SelectedItem.autopilot(AutopilotEvent e) =>
      _SelectedItem._(autopilotEvent: e);
  factory _SelectedItem.user(UserEvent e) =>
      _SelectedItem._(userEvent: e);

  bool get isAutopilot => autopilotEvent != null;
}

// ---------------------------------------------------------------------------
// _DetailSheet
// ---------------------------------------------------------------------------

class _DetailSheet extends StatelessWidget {
  final _SelectedItem selected;
  final VoidCallback onDismiss;
  final ValueChanged<AutopilotEvent> onConvertToUserEvent;
  final ValueChanged<UserEvent> onRemoveProtection;

  const _DetailSheet({
    required this.selected,
    required this.onDismiss,
    required this.onConvertToUserEvent,
    required this.onRemoveProtection,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: NexGenPalette.gunmetal90.withValues(alpha: 0.95),
                    border: Border(
                      top: BorderSide(
                        color: selected.isAutopilot
                            ? (selected.autopilotEvent!.displayColor ??
                                    NexGenPalette.cyan)
                                .withValues(alpha: 0.4)
                            : NexGenPalette.cyan.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: selected.isAutopilot
                        ? _AutopilotDetail(
                            event: selected.autopilotEvent!,
                            onDismiss: onDismiss,
                            onEdit: () =>
                                onConvertToUserEvent(selected.autopilotEvent!),
                          )
                        : _UserDetail(
                            event: selected.userEvent!,
                            onDismiss: onDismiss,
                            onRemoveProtection: () =>
                                onRemoveProtection(selected.userEvent!),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AutopilotDetail extends ConsumerWidget {
  final AutopilotEvent event;
  final VoidCallback onDismiss;
  final VoidCallback onEdit;

  const _AutopilotDetail(
      {required this.event,
      required this.onDismiss,
      required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = event.displayColor ?? event.eventType.accentColor;
    final timeFormat = ref.watch(timeFormatPreferenceProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetHandle(),
        Row(children: [
          Icon(event.eventType.icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(event.eventType.displayLabel,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const Spacer(),
          const Text('⚡ Autopilot',
              style: TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 11)),
        ]),
        const SizedBox(height: 12),
        Text(event.patternName,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        if (event.sourceDetail.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(event.sourceDetail,
              style: const TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 14)),
        ],
        const SizedBox(height: 6),
        Text(
          '${formatTime(event.startTime, timeFormat: timeFormat)} → '
          '${formatTime(event.endTime, timeFormat: timeFormat)}',
          style: const TextStyle(
              color: NexGenPalette.textMedium, fontSize: 13),
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onDismiss,
              style: OutlinedButton.styleFrom(
                foregroundColor: NexGenPalette.textMedium,
                side: const BorderSide(color: NexGenPalette.line),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Close'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.push_pin_rounded, size: 16),
              label: const Text('Protect & Edit'),
              style: FilledButton.styleFrom(
                backgroundColor: color.withValues(alpha: 0.85),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),
      ],
    );
  }
}

class _UserDetail extends ConsumerWidget {
  final UserEvent event;
  final VoidCallback onDismiss;
  final VoidCallback onRemoveProtection;

  const _UserDetail(
      {required this.event,
      required this.onDismiss,
      required this.onRemoveProtection});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeFormat = ref.watch(timeFormatPreferenceProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sheetHandle(),
        Row(children: [
          const Icon(Icons.push_pin_rounded,
              color: NexGenPalette.cyan, size: 18),
          const SizedBox(width: 8),
          const Text('Your Event',
              style: TextStyle(
                  color: NexGenPalette.cyan, fontWeight: FontWeight.w600)),
          const Spacer(),
          const Text('📌 Protected',
              style: TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 11)),
        ]),
        const SizedBox(height: 12),
        Text(event.patternName,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        if (event.note != null) ...[
          const SizedBox(height: 4),
          Text(event.note!,
              style: const TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 13)),
        ],
        const SizedBox(height: 6),
        Text(
          '${formatTime(event.startTime, timeFormat: timeFormat)} → '
          '${formatTime(event.endTime, timeFormat: timeFormat)}',
          style: const TextStyle(
              color: NexGenPalette.textMedium, fontSize: 13),
        ),
        if (event.convertedFromAutopilot) ...[
          const SizedBox(height: 4),
          const Text(
            'Converted from autopilot — protected from regeneration.',
            style:
                TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
          ),
        ],
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onDismiss,
              style: OutlinedButton.styleFrom(
                foregroundColor: NexGenPalette.textMedium,
                side: const BorderSide(color: NexGenPalette.line),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Close'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRemoveProtection,
              icon: const Icon(Icons.lock_open_rounded, size: 16),
              label: const Text('Remove Protection'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

Widget _sheetHandle() => Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: NexGenPalette.textMedium, fontSize: 10)),
      ],
    );
  }
}
