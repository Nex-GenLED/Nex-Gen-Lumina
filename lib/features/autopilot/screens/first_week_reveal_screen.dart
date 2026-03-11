// lib/features/autopilot/screens/first_week_reveal_screen.dart
//
// "Your First Week" reveal screen shown immediately after a new user completes
// profile setup with Autopilot enabled.
//
// Features
//   - 7-day calendar grid showing what autopilot built
//   - Color-coded blocks by event type with ⚡ autopilot indicator
//   - "Why" explanation for key events ("Chiefs game Sunday — we've got
//     your lights ready 🏈")
//   - Tap any block to see detail + edit option
//   - "Looks Good! Activate Autopilot" CTA navigates to dashboard
//   - If not generated yet, shows a loading/placeholder state

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/autopilot/autopilot_schedule_generator.dart';
import 'package:nexgen_command/features/autopilot/services/autopilot_event_repository.dart';
import 'package:nexgen_command/models/autopilot_event.dart';
import 'package:nexgen_command/theme.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Loads autopilot events for the upcoming week on first run.
final _firstWeekEventsProvider =
    FutureProvider.autoDispose<List<AutopilotEvent>>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return [];
  final repo = ref.read(autopilotEventRepositoryProvider);
  final weekStart = upcomingWeekStart(DateTime.now());
  return repo.fetchWeekEvents(uid, weekStart);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class FirstWeekRevealScreen extends ConsumerStatefulWidget {
  const FirstWeekRevealScreen({super.key});

  @override
  ConsumerState<FirstWeekRevealScreen> createState() =>
      _FirstWeekRevealScreenState();
}

class _FirstWeekRevealScreenState
    extends ConsumerState<FirstWeekRevealScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heroAnim;
  AutopilotEvent? _selectedEvent;

  @override
  void initState() {
    super.initState();
    _heroAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _heroAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(_firstWeekEventsProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: SafeArea(
        child: Stack(
          children: [
            // Cyan radial glow behind hero text
            Positioned(
              top: -60,
              left: 0,
              right: 0,
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      NexGenPalette.cyan.withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                    radius: 0.8,
                  ),
                ),
              ),
            ),

            Column(
              children: [
                // ── Header ──────────────────────────────────────────────────
                FadeTransition(
                  opacity: _heroAnim,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: NexGenPalette.cyan.withValues(alpha: 0.15),
                                border: Border.all(
                                    color: NexGenPalette.cyan.withValues(alpha: 0.4)),
                              ),
                              child: const Icon(Icons.auto_awesome,
                                  size: 22, color: NexGenPalette.cyan),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Your First Week',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Here\'s what Lumina built for you. '
                          'Tap any block to review or edit it.',
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Calendar grid ────────────────────────────────────────────
                Expanded(
                  child: eventsAsync.when(
                    loading: () => const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: NexGenPalette.cyan),
                          SizedBox(height: 16),
                          Text(
                            'Building your schedule…',
                            style: TextStyle(
                                color: NexGenPalette.textMedium, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    error: (_, __) => const Center(
                      child: Text(
                        'Could not load schedule.\nTap "Activate" to continue.',
                        style: TextStyle(
                            color: NexGenPalette.textMedium, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    data: (events) => _buildCalendar(context, events),
                  ),
                ),

                // ── Bottom CTA ───────────────────────────────────────────────
                _buildCta(context),
              ],
            ),

            // ── Event detail sheet ─────────────────────────────────────────
            if (_selectedEvent != null)
              _EventDetailOverlay(
                event: _selectedEvent!,
                onDismiss: () => setState(() => _selectedEvent = null),
                onEdit: (event) {
                  // Editing converts the autopilot event to a user event.
                  // For the reveal screen we just dismiss and navigate to calendar.
                  setState(() => _selectedEvent = null);
                  context.push(AppRoutes.autopilotCalendar);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Calendar ──────────────────────────────────────────────────────────────

  Widget _buildCalendar(BuildContext context, List<AutopilotEvent> events) {
    // Group events by day of week.
    final byDay = <int, List<AutopilotEvent>>{};
    for (final e in events) {
      byDay.putIfAbsent(e.dayOfWeek, () => []).add(e);
    }

    final dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekStart = upcomingWeekStart(DateTime.now());

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: 7,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final dow = i + 1; // 1=Mon…7=Sun
        final day = weekStart.add(Duration(days: i));
        final dayEvents = byDay[dow] ?? [];

        // Build a "notable" reason string for highlight events.
        String? highlightReason;
        if (dayEvents.isNotEmpty) {
          final notable = dayEvents.firstWhere(
            (e) =>
                e.eventType == AutopilotEventType.game ||
                e.eventType == AutopilotEventType.holiday,
            orElse: () => dayEvents.first,
          );
          highlightReason = _reasonFor(notable);
        }

        return _DayRow(
          dayLabel: dayLabels[i],
          date: day,
          events: dayEvents,
          highlightReason: highlightReason,
          onEventTap: (event) => setState(() => _selectedEvent = event),
        );
      },
    );
  }

  String _reasonFor(AutopilotEvent event) {
    switch (event.eventType) {
      case AutopilotEventType.game:
        return '🏈 ${event.sourceDetail} — team colors ready';
      case AutopilotEventType.holiday:
        return '🎉 ${event.sourceDetail} — festive display';
      case AutopilotEventType.seasonal:
        return '🍂 ${event.sourceDetail} — seasonal palette';
      case AutopilotEventType.preferredWhite:
        return '💡 Your preferred evening glow';
      case AutopilotEventType.weather:
        return '🌤 Weather-inspired palette';
    }
  }

  Widget _buildCta(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack,
        border: Border(
            top: BorderSide(color: NexGenPalette.line.withValues(alpha: 0.5))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.go(AppRoutes.dashboard),
              icon: const Icon(Icons.bolt, color: Colors.black),
              label: const Text(
                'Looks Good! Activate Autopilot',
                style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => context.push(AppRoutes.autopilotCalendar),
            child: const Text(
              'Make adjustments first',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DayRow
// ---------------------------------------------------------------------------

class _DayRow extends StatelessWidget {
  final String dayLabel;
  final DateTime date;
  final List<AutopilotEvent> events;
  final String? highlightReason;
  final ValueChanged<AutopilotEvent> onEventTap;

  const _DayRow({
    required this.dayLabel,
    required this.date,
    required this.events,
    this.highlightReason,
    required this.onEventTap,
  });

  @override
  Widget build(BuildContext context) {
    final isToday = _isToday(date);

    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isToday
              ? NexGenPalette.cyan.withValues(alpha: 0.4)
              : NexGenPalette.line.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day header
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
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
                        dayLabel,
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
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isToday ? NexGenPalette.cyan : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (highlightReason != null)
                  Expanded(
                    child: Text(
                      highlightReason!,
                      style: const TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else if (events.isEmpty)
                  const Expanded(
                    child: Text(
                      'No events scheduled',
                      style: TextStyle(
                          color: NexGenPalette.textMedium, fontSize: 12),
                    ),
                  ),
              ],
            ),
            if (events.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: events
                    .map((e) => _EventChip(event: e, onTap: () => onEventTap(e)))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

// ---------------------------------------------------------------------------
// _EventChip
// ---------------------------------------------------------------------------

class _EventChip extends StatelessWidget {
  final AutopilotEvent event;
  final VoidCallback onTap;

  const _EventChip({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = event.displayColor ?? event.eventType.accentColor;
    final startH = event.startTime.hour.toString().padLeft(2, '0');
    final startM = event.startTime.minute.toString().padLeft(2, '0');
    final endH = event.endTime.hour.toString().padLeft(2, '0');
    final endM = event.endTime.minute.toString().padLeft(2, '0');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(event.eventType.icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              event.patternName,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Text(
              '$startH:$startM–$endH:$endM',
              style: TextStyle(
                  color: color.withValues(alpha: 0.7), fontSize: 10),
            ),
            const SizedBox(width: 4),
            Text(
              '⚡',
              style: TextStyle(
                  fontSize: 9, color: color.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _EventDetailOverlay — glass sheet sliding up from bottom
// ---------------------------------------------------------------------------

class _EventDetailOverlay extends StatelessWidget {
  final AutopilotEvent event;
  final VoidCallback onDismiss;
  final ValueChanged<AutopilotEvent> onEdit;

  const _EventDetailOverlay({
    required this.event,
    required this.onDismiss,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final color = event.displayColor ?? event.eventType.accentColor;
    final startFmt = _fmtTime(event.startTime);
    final endFmt = _fmtTime(event.endTime);

    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // prevent dismiss on card tap
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
                      top: BorderSide(color: color.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Handle
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        // Event type badge
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: color.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(event.eventType.icon,
                                      size: 13, color: color),
                                  const SizedBox(width: 5),
                                  Text(
                                    event.eventType.displayLabel,
                                    style: TextStyle(
                                        color: color,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '⚡ Autopilot',
                              style: TextStyle(
                                  color: NexGenPalette.textMedium,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Pattern name
                        Text(
                          event.patternName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Source detail
                        if (event.sourceDetail.isNotEmpty)
                          Text(
                            event.sourceDetail,
                            style: const TextStyle(
                                color: NexGenPalette.textMedium,
                                fontSize: 14),
                          ),
                        const SizedBox(height: 8),

                        // Time range
                        Row(
                          children: [
                            const Icon(Icons.schedule,
                                size: 14,
                                color: NexGenPalette.textMedium),
                            const SizedBox(width: 6),
                            Text(
                              '$startFmt → $endFmt',
                              style: const TextStyle(
                                  color: NexGenPalette.textMedium,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Actions
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: onDismiss,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: NexGenPalette.textMedium,
                                  side: const BorderSide(
                                      color: NexGenPalette.line),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                ),
                                child: const Text('Looks good'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => onEdit(event),
                                style: FilledButton.styleFrom(
                                  backgroundColor: color.withValues(alpha: 0.85),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                ),
                                child: const Text('Edit'),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
