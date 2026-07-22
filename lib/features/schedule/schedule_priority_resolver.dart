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
import 'package:nexgen_command/features/schedule/schedule_models.dart';

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

// ─── Phase 2: Night-segment composition ─────────────────────────────────────
//
// Pure derived view: at sync/render time, take the recurring baseline rule
// for a date plus any CalendarEntries on that date, and produce an ordered
// list of non-overlapping segments per the priority hierarchy. Higher tiers
// carve their window out of lower-tier segments; tiers 1 & 2 (user, holiday)
// short-circuit composition and own the night entirely.

/// Seven-tier hierarchy used by [composeNightSegments]. Lower numeric
/// index = higher priority. Tiers 1 and 2 short-circuit composition;
/// tiers 3–7 participate in sandwich composition.
enum SegmentTier {
  /// 1 — Manually-created CalendarEntry (`type=user`). Owns the full day.
  user,

  /// 2 — Holiday CalendarEntry (`type=holiday`). Owns the full day.
  holiday,

  /// 3 — Game Day individual (`sourceTag='game_day'`). Highest priority
  ///     among composing tiers.
  gameDay,

  /// 4 — Game Day Group (`sourceTag='game_day_group'`).
  gameDayGroup,

  /// 5 — Neighborhood Sync (`sourceTag='neighborhood_sync'`).
  neighborhoodSync,

  /// 6 — Personal Autopilot (autopilot CalendarEntry without a more
  ///     specific source tag).
  personalAutopilot,

  /// 7 — Recurring baseline ScheduleItem (e.g. Warm White sunset→sunrise).
  baselineRecurring;

  bool isHigherThan(SegmentTier other) => index < other.index;
}

/// One segment of a composed night. Non-overlapping with its siblings.
class NightSegment {
  /// Inclusive start of this segment.
  final DateTime start;

  /// Exclusive end of this segment.
  final DateTime end;

  /// Tier this segment came from.
  final SegmentTier tier;

  /// Source CalendarEntry, if this segment came from a calendar entry
  /// (tiers 1–6). Null for baseline (tier 7) segments.
  final CalendarEntry? entry;

  /// Source baseline ScheduleItem, if this segment came from the
  /// recurring baseline (tier 7). Null for entry-sourced segments.
  final ScheduleItem? baseline;

  const NightSegment({
    required this.start,
    required this.end,
    required this.tier,
    this.entry,
    this.baseline,
  });

  /// Display-friendly label suitable for debug logs.
  String get label => entry?.patternName ?? baseline?.actionLabel ?? '—';

  @override
  String toString() =>
      'NightSegment(${tier.name}, $start → $end, $label)';
}

/// Map a CalendarEntry to its [SegmentTier]. Used by [composeNightSegments].
///
/// Tier resolution rules:
/// 1. `type == user` → [SegmentTier.user] (regardless of sourceTag).
/// 2. `type == holiday` → [SegmentTier.holiday].
/// 3. Otherwise the `sourceTag` field disambiguates among the autopilot tiers.
/// 4. An autopilot-typed entry with a null/unknown sourceTag is treated as
///    [SegmentTier.personalAutopilot].
SegmentTier tierForEntry(CalendarEntry entry) {
  switch (entry.type) {
    case CalendarEntryType.user:
      return SegmentTier.user;
    case CalendarEntryType.holiday:
      return SegmentTier.holiday;
    case CalendarEntryType.auto:
    case CalendarEntryType.autopilot:
      switch (entry.sourceTag) {
        case CalendarEntrySourceTag.gameDay:
          return SegmentTier.gameDay;
        case CalendarEntrySourceTag.gameDayGroup:
          return SegmentTier.gameDayGroup;
        case CalendarEntrySourceTag.neighborhoodSync:
          return SegmentTier.neighborhoodSync;
        case CalendarEntrySourceTag.autopilot:
        default:
          return SegmentTier.personalAutopilot;
      }
  }
}

/// Compose a night of lighting segments for [date] from a recurring
/// [baseline] schedule item plus any [entries] for that date.
///
/// The function is pure — no IO, no provider reads, no time-of-day "now"
/// dependency. Sunrise/sunset times must be supplied by the caller (via
/// [sunrise] / [sunset]) for baselines that use solar time labels; if a
/// baseline uses solar labels and the corresponding parameter is null,
/// the baseline is dropped from composition.
///
/// ## Behavior summary
///
/// * If any entry in [entries] is tier 1 (user) or tier 2 (holiday), a
///   single segment is returned for that entry and composition stops.
///   These tiers own the full day and are never split.
/// * Otherwise entries are placed into the timeline in priority order
///   (highest first), each carving its window out of any already-placed
///   lower-priority gaps. Lower-priority entries only fill spaces left
///   uncovered by higher-priority ones.
/// * The baseline (if present) fills the remaining gaps within its own
///   window — typically sunset→sunrise, but governed by its
///   `timeLabel` / `offTimeLabel`.
/// * Entries with no parseable `onTime` are skipped (can't place
///   something without a start). Entries with a null `offTime` are
///   treated as zero-length and dropped.
///
/// Returned segments are non-overlapping and sorted by start ascending.
/// Single-entry nights (where the user has only one autopilot entry and
/// no baseline) collapse to a single segment, preserving prior behavior.
List<NightSegment> composeNightSegments({
  required DateTime date,
  required List<CalendarEntry> entries,
  ScheduleItem? baseline,
  DateTime? sunrise,
  DateTime? sunset,
}) {
  // ── Step 1: Tier 1 / Tier 2 short-circuit ─────────────────────────
  for (final entry in entries) {
    final tier = tierForEntry(entry);
    if (tier == SegmentTier.user || tier == SegmentTier.holiday) {
      final window = _entryWindow(entry, date);
      if (window == null) return const [];
      return [
        NightSegment(
          start: window.$1,
          end: window.$2,
          tier: tier,
          entry: entry,
        ),
      ];
    }
  }

  // ── Step 2: Resolve composing entries to (start, end, tier) ───────
  final placed = <NightSegment>[];
  final composing = <(SegmentTier, CalendarEntry, DateTime, DateTime)>[];
  for (final entry in entries) {
    final tier = tierForEntry(entry);
    // Tiers 1/2 already handled; tier 7 isn't an entry tier.
    if (tier == SegmentTier.user ||
        tier == SegmentTier.holiday ||
        tier == SegmentTier.baselineRecurring) {
      continue;
    }
    final window = _entryWindow(entry, date);
    if (window == null) continue;
    composing.add((tier, entry, window.$1, window.$2));
  }

  // Sort highest priority first (tier ascending = priority descending).
  composing.sort((a, b) => a.$1.index.compareTo(b.$1.index));

  // ── Step 3: Carve each entry into the timeline ────────────────────
  for (final (tier, entry, start, end) in composing) {
    for (final piece in _subtract(start, end, placed)) {
      placed.add(NightSegment(
        start: piece.$1,
        end: piece.$2,
        tier: tier,
        entry: entry,
      ));
    }
  }

  // ── Step 4: Fill remaining gaps within the baseline window ────────
  if (baseline != null) {
    final baseWindow =
        _baselineWindow(baseline, date, sunrise: sunrise, sunset: sunset);
    if (baseWindow != null) {
      for (final gap in _subtract(baseWindow.$1, baseWindow.$2, placed)) {
        placed.add(NightSegment(
          start: gap.$1,
          end: gap.$2,
          tier: SegmentTier.baselineRecurring,
          baseline: baseline,
        ));
      }
    }
  }

  placed.sort((a, b) => a.start.compareTo(b.start));
  return placed;
}

// ─── Internal helpers ───────────────────────────────────────────────────

/// Compute `[start, end)` for an entry on [date]. Returns null if the
/// entry can't be placed (missing onTime, unparseable, or zero-length).
/// Overnight wraps (offTime <= onTime) carry the end into the next day.
(DateTime, DateTime)? _entryWindow(CalendarEntry entry, DateTime date) {
  final onTime = entry.onTime;
  if (onTime == null) return null;
  final start = _parseHHMM(onTime, date);
  if (start == null) return null;
  final off = entry.offTime;
  if (off == null) return null;
  var end = _parseHHMM(off, date);
  if (end == null) return null;
  if (!end.isAfter(start)) {
    end = end.add(const Duration(days: 1));
  }
  return (start, end);
}

/// Compute `[start, end)` for a baseline ScheduleItem on [date]. Returns
/// null if the baseline uses solar labels and the matching DateTime
/// wasn't supplied, or if the labels can't be parsed.
(DateTime, DateTime)? _baselineWindow(
  ScheduleItem baseline,
  DateTime date, {
  DateTime? sunrise,
  DateTime? sunset,
}) {
  final start = _parseScheduleLabel(baseline.timeLabel, date,
      sunrise: sunrise, sunset: sunset);
  if (start == null) return null;
  if (!baseline.hasOffTime) return null;
  var end = _parseScheduleLabel(baseline.offTimeLabel!, date,
      sunrise: sunrise, sunset: sunset);
  if (end == null) return null;
  if (!end.isAfter(start)) {
    end = end.add(const Duration(days: 1));
  }
  return (start, end);
}

/// Parse 'HH:mm' (24h) into a DateTime anchored on [date].
DateTime? _parseHHMM(String label, DateTime date) {
  final parts = label.trim().split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return DateTime(date.year, date.month, date.day, h, m);
}

/// Parse a ScheduleItem time label — accepts 'Sunrise', 'Sunset',
/// 'h:mm AM/PM' (12h), and 'HH:mm' (24h).
DateTime? _parseScheduleLabel(
  String label,
  DateTime date, {
  DateTime? sunrise,
  DateTime? sunset,
}) {
  final l = label.trim().toLowerCase();
  if (l == 'sunrise') return sunrise;
  if (l == 'sunset') return sunset;

  final ampm = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$', caseSensitive: false)
      .firstMatch(label.trim());
  if (ampm != null) {
    var h = int.tryParse(ampm.group(1)!) ?? -1;
    final m = int.tryParse(ampm.group(2)!) ?? -1;
    final ap = ampm.group(3)!.toLowerCase();
    if (h < 0 || m < 0 || m > 59) return null;
    if (ap == 'pm' && h != 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    if (h > 23) return null;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  return _parseHHMM(label, date);
}

/// Subtract a list of already-placed segments from `[start, end)`,
/// returning the remaining `(start, end)` pieces in order.
List<(DateTime, DateTime)> _subtract(
  DateTime start,
  DateTime end,
  List<NightSegment> existing,
) {
  // Sort blockers by start so the iteration is deterministic.
  final blockers = [...existing]
    ..sort((a, b) => a.start.compareTo(b.start));

  var pieces = <(DateTime, DateTime)>[(start, end)];
  for (final seg in blockers) {
    final next = <(DateTime, DateTime)>[];
    for (final (a, b) in pieces) {
      if (!b.isAfter(seg.start) || !a.isBefore(seg.end)) {
        next.add((a, b)); // No overlap.
        continue;
      }
      if (a.isBefore(seg.start)) {
        next.add((a, seg.start));
      }
      if (b.isAfter(seg.end)) {
        next.add((seg.end, b));
      }
    }
    pieces = next;
    if (pieces.isEmpty) break;
  }
  return pieces;
}
