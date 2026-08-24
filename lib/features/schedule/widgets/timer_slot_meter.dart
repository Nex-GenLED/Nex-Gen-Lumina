// lib/features/schedule/widgets/timer_slot_meter.dart
//
// Scheduling V3 D4 — "N of 8 timer slots used", before the save rather than
// after it.
//
// WHY THIS EXISTS. The pool has always been finite, and overflow has always
// been reported the same way: the schedule saves to Firestore, the sync refuses
// to arm it, and the user gets "Schedule saved but couldn't arm — controller
// timer slots are full (8/8). Delete an old schedule." That message arrives
// after the fact, names nothing, and leaves the user to guess which of their
// schedules is holding a slot.
//
// P4 decision: slot demand is PER EVENT, not per channel — a channel-scoped
// event costs exactly what an all-channel one costs, because it is still one
// timer firing one preset. So this meter counts events, and per-channel
// scheduling does not change the arithmetic.
//
// The accounting mirrors `ScheduleSyncService.splitByTimerCapacity` rather than
// re-deriving it: one general slot per CLOCK on-boundary, one per clock
// off-boundary, none for solar (those live in the dedicated slots 8/9), and the
// budget reduced by active calendar leases, which hold general slots too.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/theme.dart';

/// General (clock) timer slots on WLED 0.15.1. Mirrors
/// `ScheduleSyncService.kMaxWledTimers`; solar uses the dedicated slots 8/9 and
/// is out of this pool.
const int kGeneralTimerSlots = 8;

/// True for a label WLED fires from the solar slots rather than a general one.
bool _isSolar(String? label) {
  final l = label?.trim().toLowerCase();
  return l == 'sunrise' || l == 'sunset';
}

/// How many general slots one schedule consumes.
///
/// PURE + exported so the meter and its tests agree with the sync path without
/// either re-deriving it.
int slotsForSchedule(ScheduleItem s, {required bool solarEnabled}) {
  if (!s.enabled || s.isCurrentlyEvicted) return 0;
  final onSolar = solarEnabled && _isSolar(s.timeLabel);
  final offSolar = solarEnabled && _isSolar(s.offTimeLabel);
  var n = onSolar ? 0 : 1;
  if (s.hasOffTime && !offSolar) n += 1;
  return n;
}

/// A schedule that is currently holding at least one slot, with what it holds.
typedef SlotHolder = ({String id, String label, int slots});

/// The whole picture: demand, budget, and who is holding what.
({int used, int budget, List<SlotHolder> holders}) computeSlotUsage({
  required List<ScheduleItem> schedules,
  required int leaseCount,
  required bool solarEnabled,
  String? excludingId,
}) {
  final holders = <SlotHolder>[];
  var used = 0;
  for (final s in schedules) {
    if (excludingId != null && s.id == excludingId) continue;
    final n = slotsForSchedule(s, solarEnabled: solarEnabled);
    if (n == 0) continue;
    used += n;
    holders.add((id: s.id, label: s.displayActionLabel, slots: n));
  }
  // Leases hold GENERAL slots — macro 26-41 is a preset-id convention, not a
  // slot reservation (bench-proven, audit §4.2). The budget shrinks by them.
  final budget = (kGeneralTimerSlots - leaseCount).clamp(0, kGeneralTimerSlots);
  return (used: used, budget: budget, holders: holders);
}

/// Inline meter for the schedule editor.
class TimerSlotMeter extends ConsumerWidget {
  /// When editing, that schedule's own slots are excluded from "used" so the
  /// meter shows what the rest of the account holds.
  final String? editingId;

  const TimerSlotMeter({super.key, this.editingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulesProvider);
    final solarEnabled = ref.watch(solarSchedulingEnabledSyncProvider);
    final leaseCount = ref.watch(calendarLeaseEntriesProvider).length;

    final usage = computeSlotUsage(
      schedules: schedules,
      leaseCount: leaseCount,
      solarEnabled: solarEnabled,
      excludingId: editingId,
    );

    final full = usage.used >= usage.budget;
    final colour = full ? NexGenPalette.amber : NexGenPalette.textMedium;

    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 14, color: colour),
        const SizedBox(width: 6),
        Text(
          '${usage.used} of ${usage.budget} timer slots used',
          style: TextStyle(fontSize: 11, color: colour),
        ),
        if (leaseCount > 0) ...[
          const SizedBox(width: 6),
          Text(
            '($leaseCount held by calendar days)',
            style: TextStyle(fontSize: 10, color: NexGenPalette.textMedium),
          ),
        ],
      ],
    );
  }
}

/// The refusal dialog: the count AND the names of what is holding slots.
///
/// Returns true when there is room and the caller should proceed.
Future<bool> confirmSlotCapacity(
  BuildContext context,
  WidgetRef ref, {
  required ScheduleItem candidate,
  String? editingId,
}) async {
  final schedules = ref.read(schedulesProvider);
  final solarEnabled = ref.read(solarSchedulingEnabledSyncProvider);
  final leaseCount = ref.read(calendarLeaseEntriesProvider).length;

  final usage = computeSlotUsage(
    schedules: schedules,
    leaseCount: leaseCount,
    solarEnabled: solarEnabled,
    excludingId: editingId,
  );
  final want = slotsForSchedule(candidate, solarEnabled: solarEnabled);
  if (usage.used + want <= usage.budget) return true;

  if (!context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('No timer slots left'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This schedule needs $want '
            '${want == 1 ? 'slot' : 'slots'}, and '
            '${usage.used} of ${usage.budget} are already used'
            '${leaseCount > 0 ? ' ($leaseCount held by calendar days)' : ''}.',
          ),
          const SizedBox(height: 12),
          const Text('Holding slots now:',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          // Named, so the user does not have to guess which one to delete.
          for (final h in usage.holders)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• ${h.label} — ${h.slots} '
                  '${h.slots == 1 ? 'slot' : 'slots'}'),
            ),
          const SizedBox(height: 12),
          const Text(
            'Delete or disable one, then try again.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
      ],
    ),
  );
  return false;
}
