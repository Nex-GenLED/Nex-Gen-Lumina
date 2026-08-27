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
//
// #90 — WHAT "REDUCED BY ACTIVE LEASES" MEANS, AND WHAT IT USED TO MEAN.
// This file used to shrink the budget by `calendarLeaseEntriesProvider.length`
// — the number of DATES that have a calendar entry, account-wide, with no
// horizon filter, no expiry filter, and including the 12 holiday defaults that
// `CalendarScheduleNotifier` seeds before Firestore even loads. On a real
// account that was 55, so the budget computed as `8 - 55` and clamped to 0, and
// the save guard refused EVERY new schedule with "0 of 0 are already used".
//
// The firing path never used that number. `ScheduleSyncService` reduces its
// budget by `leaseTimers.length` — the leases actually reserved on the device,
// bounded by the 8-slot table and by the 48 h promotion window
// (`kLeaseWindow`). Both files called their variable `leaseCount`; they were
// two different quantities. This file now reads the SAME provider the sync
// merges, `calendarLeaseActiveTimersProvider`, so the claim above is true by
// construction instead of by coincidence.
//
// The ledger is TRI-STATE and that matters here (the P0-9 lesson): `loading`
// is UNKNOWN, not zero. Coercing it to 0 would invent a budget of 8 and could
// hand a schedule a slot a lease already owns. Coercing it to "full" would
// block saves for a reason the user cannot act on. So unknown neither blocks
// nor pretends: the guard allows the save and says capacity is still being
// checked.

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

/// Demand, budget, who is holding what, and whether the answer is trustworthy.
///
/// [budget] is the RAW arithmetic and may be zero or negative when leases have
/// over-committed the table. It is deliberately NOT clamped: clamping made an
/// over-commitment indistinguishable from a legitimately full pool, and the
/// guard then refused saves it had no business refusing. Callers that render it
/// should clamp for display; callers that decide should read [overCommitted].
typedef SlotUsage = ({
  int used,
  int budget,
  List<SlotHolder> holders,
  bool overCommitted,
  bool ledgerUnknown,
});

/// The reservation to subtract, or null when the lease ledger has not loaded.
///
/// `LeaseLedgerLoading` is UNKNOWN — never 0. See the header note.
int? leaseReservationOf(LeaseLedgerState ledger) =>
    ledger is LeaseLedgerLoading ? null : ledger.timers.length;

/// The whole picture: demand, budget, and who is holding what.
///
/// [leaseReservation] is the number of general slots calendar leases actually
/// hold on the device — `calendarLeaseActiveTimersProvider`'s timer count, the
/// same value `ScheduleSyncService` subtracts. Pass null when the ledger has
/// not loaded; the result is then flagged [ledgerUnknown] and must not be used
/// to refuse anything.
SlotUsage computeSlotUsage({
  required List<ScheduleItem> schedules,
  required int? leaseReservation,
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
  final budget = kGeneralTimerSlots - (leaseReservation ?? 0);
  return (
    used: used,
    budget: budget,
    holders: holders,
    overCommitted: budget <= 0,
    ledgerUnknown: leaseReservation == null,
  );
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
    // The SAME provider the sync path merges — not the calendar entry count.
    final reservation =
        leaseReservationOf(ref.watch(calendarLeaseActiveTimersProvider));

    final usage = computeSlotUsage(
      schedules: schedules,
      leaseReservation: reservation,
      solarEnabled: solarEnabled,
      excludingId: editingId,
    );

    // Display clamps; the decision does not (see [SlotUsage.budget]).
    final shownBudget = usage.budget.clamp(0, kGeneralTimerSlots);
    final full = usage.overCommitted || usage.used >= shownBudget;
    final colour = full ? NexGenPalette.amber : NexGenPalette.textMedium;

    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 14, color: colour),
        const SizedBox(width: 6),
        Text(
          usage.ledgerUnknown
              ? '${usage.used} timer slots used — checking capacity'
              : '${usage.used} of $shownBudget timer slots used',
          style: TextStyle(fontSize: 11, color: colour),
        ),
        if (!usage.ledgerUnknown && (reservation ?? 0) > 0) ...[
          const SizedBox(width: 6),
          Text(
            '($reservation held by calendar days)',
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
  final reservation =
      leaseReservationOf(ref.read(calendarLeaseActiveTimersProvider));

  final usage = computeSlotUsage(
    schedules: schedules,
    leaseReservation: reservation,
    solarEnabled: solarEnabled,
    excludingId: editingId,
  );
  final want = slotsForSchedule(candidate, solarEnabled: solarEnabled);

  // WARN, DO NOT BLOCK (#90). Saving writes Firestore and nothing else. The
  // sync layer independently refuses to arm what will not fit and reports it
  // honestly, so a save is never destructive — whereas refusing it strands the
  // user with no way forward and, when the arithmetic was wrong, no way to tell.
  // Two cases get a note instead of a refusal:
  //   • the lease ledger has not loaded — the budget is UNKNOWN, not zero;
  //   • the budget is <= 0 — leases have over-committed the table, which is a
  //     lease-side condition the user cannot fix by deleting a schedule.
  if (usage.ledgerUnknown || usage.overCommitted) {
    if (!context.mounted) return true;
    final msg = usage.ledgerUnknown
        ? 'Still checking how many timer slots your calendar days are '
            'holding. Your schedule will be saved; if there is no room on the '
            'controller it will say so when it syncs.'
        : 'Your calendar days are currently holding every timer slot. Your '
            'schedule will be saved, but it may not arm until one of those '
            'days passes.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
    );
    return true;
  }

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
            '${(reservation ?? 0) > 0 ? ' ($reservation held by calendar days)' : ''}.',
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
