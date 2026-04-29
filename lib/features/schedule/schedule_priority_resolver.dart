// lib/features/schedule/schedule_priority_resolver.dart
//
// Phase 1 schedule priority resolver. Routes autopilot-vs-autopilot
// CalendarEntry conflicts silently using a 5-tier priority hierarchy.
// Higher-priority entries win; lower-priority incoming entries are
// dropped without prompting the user.
//
// User-vs-user conflicts continue to flow through the existing
// `schedule_conflict_dialog.dart` UI — this resolver does NOT touch
// that path.

import 'package:nexgen_command/features/schedule/calendar_entry.dart';

/// 5-tier priority hierarchy for schedule entry conflicts.
///
/// Lower numeric index = higher priority. When two entries collide on the
/// same `dateKey`, the higher-priority one wins; the lower-priority one is
/// silently dropped without prompting the user.
///
/// The hierarchy is fixed and intentionally narrow — autopilot sources
/// must not accidentally overwrite user-set entries, holidays must win
/// over Game Day on the rare overlap (e.g. Christmas Day NBA game), and
/// the recurring baseline is always the implicit fallback when no
/// CalendarEntry exists.
enum SchedulePriority {
  /// 1 — User-manually-created CalendarEntries (the calendar editor or
  /// schedule editor). NEVER overwritten by any autopilot source.
  user,

  /// 2 — Holiday autopilot CalendarEntries (Christmas, July 4th, etc).
  /// Overwrites Game Day if both fall on the same date.
  holidayAutopilot,

  /// 3 — Game Day autopilot CalendarEntries (team game-day designs).
  gameDayAutopilot,

  /// 4 — Neighborhood Sync entries. Reserved for future use when sync
  /// events flow through the CalendarEntry model. Today, Neighborhood
  /// Sync writes through a separate path (sync_event_service) and does
  /// not produce CalendarEntries — this tier is here so the hierarchy
  /// is documented end-to-end without requiring a model change later.
  neighborhoodSync,

  /// 5 — Baseline recurring schedules. Lowest priority. Lives in
  /// [ScheduleItem] (recurring rules), not [CalendarEntry]. Phase 1
  /// handles only CalendarEntry-vs-CalendarEntry conflicts; recurring
  /// rules are the implicit fallback when no CalendarEntry exists for
  /// a given date. Phase 2 will introduce segment composition so a
  /// recurring rule can run *around* a higher-priority entry.
  baselineRecurring;

  /// True iff `this` is strictly higher priority than [other].
  bool isHigherThan(SchedulePriority other) => index < other.index;
}

/// Phase-1 resolver for CalendarEntry-vs-CalendarEntry conflicts.
///
/// ## What this resolver does (Phase 1)
///
/// Filters a list of incoming CalendarEntries against current state.
/// For each incoming entry it compares the priority to any existing
/// entry on the same `dateKey`:
///
/// * **higher or equal** priority → kept (overwrites existing on write)
/// * **lower** priority           → silently dropped
///
/// Called by autopilot writers (Game Day, Holiday, Lumina AI) before
/// invoking `CalendarScheduleNotifier.applyEntries` so an autopilot
/// source can't accidentally clobber a higher-priority entry the user
/// or another autopilot has already written.
///
/// ## What this resolver does NOT do (deferred to Phase 2)
///
/// **Whole-night replacement is the v1 behavior.** When a Game Day
/// entry is written to a date where a Warm White recurring rule
/// (sunset→sunrise) is active, the Game Day entry takes the entire
/// night — Warm White does NOT run before or after the game on that
/// date. The "Warm White → Game → Warm White sandwich" UX described
/// in the original spec requires multi-segment support per `dateKey`,
/// which the current [CalendarEntry] model doesn't have.
///
/// **Phase 2 handoff:** introduce segment composition. The lightest
/// option is a derived view at schedule-sync time (no storage shape
/// change) — when emitting WLED timers for a date that has both a
/// recurring baseline rule AND a higher-priority CalendarEntry,
/// generate timer-pairs covering `[recurringStart, entryStart]`,
/// `[entryStart, entryEnd]`, and `[entryEnd, recurringEnd]` instead
/// of a single replacement window.
///
/// ## Intentional non-goals
///
/// * Doesn't handle [ScheduleItem] (recurring rules) directly. Recurring
///   rules are the implicit fallback when no CalendarEntry exists.
/// * Doesn't surface user-facing conflict dialogs. User-vs-anything
///   conflicts continue to flow through `schedule_conflict_dialog.dart`
///   unchanged. This resolver fires *before* that dialog ever runs and
///   is for autopilot sources only.
/// * Doesn't modify or split existing entries. Phase 1 is filter-only:
///   incoming entries are kept or dropped, never mutated.
class SchedulePriorityResolver {
  const SchedulePriorityResolver._();

  /// Maps a [CalendarEntry] to its [SchedulePriority] tier.
  ///
  /// `auto`-typed entries (the default for entries without an explicit
  /// type — typically Lumina-AI generated suggestions) are treated as
  /// Game Day–tier. Phase 1 doesn't differentiate Lumina AI from Game
  /// Day at the priority layer; both win over the recurring baseline
  /// and lose to user/holiday writes.
  static SchedulePriority priorityOf(CalendarEntry entry) {
    switch (entry.type) {
      case CalendarEntryType.user:
        return SchedulePriority.user;
      case CalendarEntryType.holiday:
        return SchedulePriority.holidayAutopilot;
      case CalendarEntryType.autopilot:
        return SchedulePriority.gameDayAutopilot;
      case CalendarEntryType.auto:
        return SchedulePriority.gameDayAutopilot;
    }
  }

  /// Filter [incoming] entries against [existing] state. Drops incoming
  /// entries that would overwrite a strictly higher-priority existing
  /// entry. Equal-priority overwrites are kept (idempotent re-writes
  /// of the same source).
  ///
  /// Returns a [PriorityFilterResult] containing the kept entries and
  /// the dropped ones with reasons. Callers typically log the dropped
  /// list for telemetry/debug visibility and pass `result.kept`
  /// straight into `applyEntries`.
  static PriorityFilterResult filterIncoming({
    required List<CalendarEntry> incoming,
    required Map<String, CalendarEntry> existing,
  }) {
    final kept = <CalendarEntry>[];
    final dropped = <DroppedEntry>[];

    for (final entry in incoming) {
      final existingEntry = existing[entry.dateKey];
      if (existingEntry == null) {
        kept.add(entry);
        continue;
      }
      final incomingPriority = priorityOf(entry);
      final existingPriority = priorityOf(existingEntry);
      if (existingPriority.isHigherThan(incomingPriority)) {
        dropped.add(DroppedEntry(
          entry: entry,
          existingEntry: existingEntry,
          reason: 'Existing ${existingPriority.name} entry on '
              '${entry.dateKey} has higher priority than incoming '
              '${incomingPriority.name}',
        ));
        continue;
      }
      kept.add(entry);
    }

    return PriorityFilterResult(kept: kept, dropped: dropped);
  }
}

/// Outcome of [SchedulePriorityResolver.filterIncoming].
class PriorityFilterResult {
  /// Entries that should be written through to `applyEntries`.
  final List<CalendarEntry> kept;

  /// Entries that were dropped because a strictly higher-priority
  /// entry already exists on the same `dateKey`. Useful for debug
  /// logging — never surfaced to the user.
  final List<DroppedEntry> dropped;

  const PriorityFilterResult({required this.kept, required this.dropped});
}

/// Record of an incoming entry that was dropped due to priority conflict.
class DroppedEntry {
  /// The incoming entry that was dropped.
  final CalendarEntry entry;

  /// The existing higher-priority entry that caused the drop.
  final CalendarEntry existingEntry;

  /// Human-readable explanation suitable for `debugPrint`.
  final String reason;

  const DroppedEntry({
    required this.entry,
    required this.existingEntry,
    required this.reason,
  });
}
