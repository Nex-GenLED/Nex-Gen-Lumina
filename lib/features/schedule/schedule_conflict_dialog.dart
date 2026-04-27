// lib/features/schedule/schedule_conflict_dialog.dart
//
// Conflict resolution UI for overlapping schedules.
// Shows a modal bottom sheet listing conflicts and offering
// Replace Existing / Run Both / Cancel options.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/utils/time_format.dart';

// ─── Data types ──────────────────────────────────────────────────────────────

enum ConflictResolution { removeExisting, keepBoth, cancel }

/// Describes which existing schedules conflict with an incoming one.
class ScheduleConflictInfo {
  final List<ScheduleItem> conflictingItems;
  final List<String> conflictingEntryKeys;
  final Map<String, CalendarEntry> calendarEntries;

  int get totalConflicts =>
      conflictingItems.length + conflictingEntryKeys.length;
  bool get hasConflicts => totalConflicts > 0;

  const ScheduleConflictInfo({
    this.conflictingItems = const [],
    this.conflictingEntryKeys = const [],
    this.calendarEntries = const {},
  });
}

// ─── Public entry point ──────────────────────────────────────────────────────

/// Shows the conflict resolution bottom sheet and returns the user's choice.
/// Returns [ConflictResolution.cancel] if the sheet is dismissed.
Future<ConflictResolution> showScheduleConflictDialog(
  BuildContext context,
  ScheduleConflictInfo conflicts,
) async {
  final result = await showModalBottomSheet<ConflictResolution>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ConflictSheet(conflicts: conflicts),
  );
  return result ?? ConflictResolution.cancel;
}

// ─── Sheet widget ────────────────────────────────────────────────────────────

class _ConflictSheet extends StatelessWidget {
  final ScheduleConflictInfo conflicts;
  const _ConflictSheet({required this.conflicts});

  @override
  Widget build(BuildContext context) {
    final count = conflicts.totalConflicts;

    return Container(
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color:
                        NexGenPalette.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: NexGenPalette.amber, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    'Schedule Conflict',
                    style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                count == 1
                    ? 'This overlaps with 1 existing schedule:'
                    : 'This overlaps with $count existing schedules:',
                style: const TextStyle(
                  color: NexGenPalette.textMedium,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),

              // Conflict list
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final item in conflicts.conflictingItems)
                      _ItemConflictTile(item: item),
                    for (final key in conflicts.conflictingEntryKeys)
                      _EntryConflictTile(
                        dateKey: key,
                        entry: conflicts.calendarEntries[key],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Buttons (stacked, full width, 12px gap) ──────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: NexGenPalette.matteBlack,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(
                      context, ConflictResolution.removeExisting),
                  child: const Column(
                    children: [
                      Text('Replace Existing',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      SizedBox(height: 2),
                      Text(
                        'Delete the conflicting schedule(s) and save this one',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NexGenPalette.cyan,
                    side: BorderSide(
                        color: NexGenPalette.cyan.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () =>
                      Navigator.pop(context, ConflictResolution.keepBoth),
                  child: const Column(
                    children: [
                      Text('Run Both',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      SizedBox(height: 2),
                      Text(
                        'Keep all schedules \u2014 the most recently applied wins',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: NexGenPalette.textMedium,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () =>
                      Navigator.pop(context, ConflictResolution.cancel),
                  child:
                      const Text('Cancel', style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Conflict list tiles ─────────────────────────────────────────────────────

class _ItemConflictTile extends ConsumerWidget {
  final ScheduleItem item;
  const _ItemConflictTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeFormat = ref.watch(timeFormatPreferenceProvider);
    final days = item.repeatDays.join(', ');
    final timeRange = item.hasOffTime
        ? '${formatTimeLabel(item.timeLabel, timeFormat: timeFormat)} \u2013 '
            '${formatTimeLabel(item.offTimeLabel, timeFormat: timeFormat)}'
        : formatTimeLabel(item.timeLabel, timeFormat: timeFormat);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: NexGenPalette.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: NexGenPalette.amber.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.actionLabel,
              style: const TextStyle(
                color: NexGenPalette.textHigh,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$days \u2022 $timeRange',
              style: const TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryConflictTile extends ConsumerWidget {
  final String dateKey;
  final CalendarEntry? entry;
  const _EntryConflictTile({required this.dateKey, this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeFormat = ref.watch(timeFormatPreferenceProvider);
    final label = entry?.patternName ?? dateKey;
    final date = DateTime.tryParse(dateKey);
    final dateStr = date != null ? _formatDate(date) : dateKey;
    final timeRange = entry != null && entry!.onTime != null
        ? '${formatTimeLabel(entry!.onTime, timeFormat: timeFormat)} \u2013 '
            '${formatTimeLabel(entry!.offTime, timeFormat: timeFormat)}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: NexGenPalette.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: NexGenPalette.amber.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: NexGenPalette.textHigh,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            if (timeRange.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '$dateStr \u2022 $timeRange',
                style: const TextStyle(
                  color: NexGenPalette.textMedium,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${weekdays[date.weekday - 1]} ${months[date.month - 1]} ${date.day}';
  }

}
