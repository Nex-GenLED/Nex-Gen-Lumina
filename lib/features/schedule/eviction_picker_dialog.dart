// lib/features/schedule/eviction_picker_dialog.dart
//
// Item #61 Workstream B — Option-C user-driven eviction picker.
//
// Surfaced by [CalendarScheduleNotifier.applyEntries] when the lease
// manager returns [LeaseOutcome.noFreeSlots]: presents a list of
// currently-enabled, non-evicted ScheduleItems annotated with their
// fire count during the proposed lease window. The user picks one to
// pause; the picker returns that ScheduleItem (or null on cancel).
// The pending-create flow then calls
// [CalendarEntryLeaseManager.applyEvictionAndLease] with the choice.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/utils/time_format.dart';

/// Show the eviction picker. Returns the ScheduleItem the user chose
/// to evict, or null if they cancelled.
///
/// The dialog reads [schedulesProvider] internally so it always
/// reflects the freshest schedule list. Pass [incomingEntry] for
/// header context and [leaseUntil] both as the "pause until" label
/// and the upper bound for fire-count annotations.
Future<ScheduleItem?> showEvictionPicker({
  required BuildContext context,
  required CalendarEntry incomingEntry,
  required DateTime leaseUntil,
}) {
  return showDialog<ScheduleItem?>(
    context: context,
    barrierDismissible: false, // Confirm-or-cancel only — no accidental dismiss.
    builder: (ctx) => _EvictionPickerDialog(
      incomingEntry: incomingEntry,
      leaseUntil: leaseUntil,
    ),
  );
}

class _EvictionPickerDialog extends ConsumerStatefulWidget {
  const _EvictionPickerDialog({
    required this.incomingEntry,
    required this.leaseUntil,
  });

  final CalendarEntry incomingEntry;
  final DateTime leaseUntil;

  @override
  ConsumerState<_EvictionPickerDialog> createState() =>
      _EvictionPickerDialogState();
}

class _EvictionPickerDialogState
    extends ConsumerState<_EvictionPickerDialog> {
  String? _selectedId;

  String _formatPauseUntil(DateTime dt, String timeFormat) {
    final local = dt.toLocal();
    final time = formatTime(dt, timeFormat: timeFormat);
    final today = DateTime.now();
    final isToday = local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
    final tomorrow = today.add(const Duration(days: 1));
    final isTomorrow = local.year == tomorrow.year &&
        local.month == tomorrow.month &&
        local.day == tomorrow.day;
    if (isToday) return 'today at $time';
    if (isTomorrow) return 'tomorrow at $time';
    return '${_monthShort(local.month)} ${local.day} at $time';
  }

  String _monthShort(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m];

  /// Approximate next-fire DateTime for an item, given [from]. Used
  /// to sort the picker list ascending — exact astronomical times
  /// for Sunrise/Sunset are deliberately not resolved (would require
  /// a lat/lon read and SunUtils call per item); rough hours (6:00
  /// for sunrise, 18:00 for sunset) keep the sort stable enough for
  /// a UX list.
  DateTime _nextFireApprox(ScheduleItem item, DateTime from) {
    final hm = _parseLabelToHourMin(item.timeLabel);
    final h = hm.$1 == 24 ? 6 : (hm.$1 == 25 ? 18 : hm.$1);
    final m = hm.$2;
    final days = item.repeatDays.map((d) => d.toLowerCase()).toList();
    final daily = days.any((d) => d.contains('daily'));
    bool fires(int weekday) {
      if (daily) return true;
      const labels = ['', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
      final target = labels[weekday];
      return days.any((d) => d.startsWith(target));
    }

    // Look forward up to 14 days; long enough to find the next fire
    // for any repeatDays mask. Beyond that an item with no matching
    // days is sorted to the back via `from + 14 days`.
    for (int i = 0; i < 14; i++) {
      final day = from.add(Duration(days: i));
      if (!fires(day.weekday)) continue;
      final candidate = DateTime(day.year, day.month, day.day, h, m);
      if (i == 0 && !candidate.isAfter(from)) continue; // today, already past
      return candidate;
    }
    return from.add(const Duration(days: 14));
  }

  /// Parse a timeLabel ("7:00 PM", "19:30", "Sunset"/"Sunrise") to
  /// (hour, min). hour=24 → sunrise, hour=25 → sunset.
  (int, int) _parseLabelToHourMin(String label) {
    final t = label.trim();
    final lower = t.toLowerCase();
    if (lower == 'sunrise') return (24, 0);
    if (lower == 'sunset') return (25, 0);
    final twelve = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(am|pm)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (twelve != null) {
      var h = int.parse(twelve.group(1)!);
      final m = int.parse(twelve.group(2)!);
      final pm = twelve.group(3)!.toUpperCase() == 'PM';
      if (h == 12) h = 0;
      if (pm) h += 12;
      return (h, m);
    }
    final tf = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
    if (tf != null) {
      return (int.parse(tf.group(1)!), int.parse(tf.group(2)!));
    }
    return (0, 0);
  }

  String _daysSummary(List<String> days) {
    if (days.isEmpty) return 'one-off';
    final lower = days.map((d) => d.toLowerCase()).toList();
    if (lower.any((d) => d.contains('daily'))) return 'Daily';
    if (lower.length == 7) return 'Daily';
    return days.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    // Reads via the testable indirection provider (same one the lease
    // manager uses for sweep). Production reads from schedulesProvider
    // unchanged; widget tests override this without constructing the
    // real SchedulesNotifier.
    final schedules = ref.watch(calendarLeaseSchedulesProvider);
    final timeFormat = ref.watch(timeFormatPreferenceProvider);

    final now = DateTime.now();
    final eligible = schedules
        .where((s) => s.enabled && !s.isCurrentlyEvicted)
        .toList()
      ..sort((a, b) =>
          _nextFireApprox(a, now).compareTo(_nextFireApprox(b, now)));

    final entry = widget.incomingEntry;
    final entryTimeRange = entry.timeRangeLabel;
    final pauseLabel = _formatPauseUntil(widget.leaseUntil, timeFormat);

    return AlertDialog(
      backgroundColor: NexGenPalette.matteBlack,
      surfaceTintColor: NexGenPalette.matteBlack,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Schedule slots full',
            style: TextStyle(
              color: NexGenPalette.textHigh,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'All 8 schedule slots are in use. Pause one recurring '
            'schedule until $pauseLabel to add this entry.',
            style: const TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NexGenPalette.line, width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.add_circle_outline,
                    size: 18, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Adding: ${entry.patternName} on ${entry.dateKey}'
                    '${entryTimeRange.isEmpty ? '' : ', $entryTimeRange'}',
                    style: const TextStyle(
                      color: NexGenPalette.textHigh,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        // Cap the list height so 8 items don't stretch the dialog off-screen.
        height: eligible.isEmpty
            ? 80.0
            : (eligible.length * 76).clamp(76, 380).toDouble(),
        child: eligible.isEmpty
            ? const Center(
                child: Text(
                  'No eligible schedules to pause.',
                  style: TextStyle(color: NexGenPalette.textMedium),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: eligible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final item = eligible[i];
                  final selected = _selectedId == item.id;
                  final pauses = fireCountDuringWindow(
                    item: item,
                    from: now,
                    until: widget.leaseUntil,
                  );
                  return _EvictionRow(
                    item: item,
                    pauseCount: pauses,
                    daysSummary: _daysSummary(item.repeatDays),
                    timeLabel: formatTimeLabel(item.timeLabel,
                        timeFormat: timeFormat),
                    selected: selected,
                    onTap: () => setState(() => _selectedId = item.id),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          style: TextButton.styleFrom(
            foregroundColor: NexGenPalette.textMedium,
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedId == null
              ? null
              : () {
                  final chosen =
                      schedules.firstWhere((s) => s.id == _selectedId);
                  Navigator.of(context).pop(chosen);
                },
          style: FilledButton.styleFrom(
            backgroundColor: NexGenPalette.violet,
            foregroundColor: NexGenPalette.textHigh,
            disabledBackgroundColor:
                NexGenPalette.violet.withValues(alpha: 0.3),
            disabledForegroundColor: NexGenPalette.textMedium,
          ),
          child: const Text('Pause & add entry'),
        ),
      ],
    );
  }
}

class _EvictionRow extends StatelessWidget {
  const _EvictionRow({
    required this.item,
    required this.pauseCount,
    required this.daysSummary,
    required this.timeLabel,
    required this.selected,
    required this.onTap,
  });

  final ScheduleItem item;
  final int pauseCount;
  final String daysSummary;
  final String timeLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? NexGenPalette.cyan : NexGenPalette.line;
    final bgColor = selected
        ? NexGenPalette.cyan.withValues(alpha: 0.08)
        : NexGenPalette.gunmetal;
    final pausesLabel =
        pauseCount == 1 ? '(pauses 1 fire)' : '(pauses $pauseCount fires)';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('eviction-row-${item.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected
                    ? NexGenPalette.cyan
                    : NexGenPalette.textMedium,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.actionLabel,
                      style: const TextStyle(
                        color: NexGenPalette.textHigh,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$timeLabel • $daysSummary  $pausesLabel',
                      style: const TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
