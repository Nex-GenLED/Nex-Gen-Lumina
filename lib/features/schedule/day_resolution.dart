// SHARED DAY RESOLUTION — audit/MULTI_ENTRY_DISPLAY.md §2 B1.
//
// FOUR surfaces open-coded this independently:
//   _DayHeroCard      my_schedule_page.dart:1190
//   _WeekDayCell      my_schedule_page.dart:2126, 2134, 2136
//   _CalDayCell       my_schedule_page.dart:2488   (recurring never passed — defect C)
//   _buildTonightCard wled_dashboard_page.dart:1350
//
// The B3 newest-wins change needed edits in four places and five expressions.
// Nothing was missed only because `.first` happened to be greppable. The next
// change to this logic will not have that property — that is why this exists.
//
// PURE. No widgets, no Riverpod, no rendering opinion: the three surfaces have
// irreconcilable layouts (a full-width card, a 1/7-width cell, a few-mm dot) but
// identical resolution logic. Each renders the result its own way.
//
// ⚠️ WHAT THIS DOES NOT DO. It does not make a multi-entry day DISPLAY all of
// its entries — it still returns one primary. Showing several is B2, which is a
// design question per surface (a `+N` chip, stacked rows, dot counts) and is not
// answered here. `others` and `totalCount` are exposed so that work needs no
// further resolution changes.

import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

/// Where a day's rendered content came from.
enum DaySource {
  /// A date-specific `CalendarEntry`. Masks every recurring schedule that day.
  dated,

  /// A recurring `ScheduleItem` matching this weekday.
  recurring,

  /// Nothing covers this day.
  none,
}

/// What a surface needs to render one day.
class DayResolution {
  /// Where [datedEntry] / [recurringPrimary] came from.
  final DaySource source;

  /// The dated entry, when [source] is [DaySource.dated].
  final CalendarEntry? datedEntry;

  /// The single recurring item a surface shows today — the NEWEST (see
  /// [resolveDay]). Null when [source] is not [DaySource.recurring].
  final ScheduleItem? recurringPrimary;

  /// Recurring items NOT shown, newest-first. Empty today on most days.
  /// Exposed for B2 (`+N more`); nothing renders it yet.
  final List<ScheduleItem> others;

  /// Everything covering this day — dated entry plus every matching recurring
  /// item. **This is what a "+N" badge counts**, and it is why the count is
  /// correct even though only one thing renders.
  final int totalCount;

  const DayResolution({
    required this.source,
    required this.datedEntry,
    required this.recurringPrimary,
    required this.others,
    required this.totalCount,
  });

  static const DayResolution empty = DayResolution(
    source: DaySource.none,
    datedEntry: null,
    recurringPrimary: null,
    others: <ScheduleItem>[],
    totalCount: 0,
  );

  bool get isEmpty => source == DaySource.none;

  /// True when more covers this day than is being shown. B2's trigger.
  bool get hasMore => totalCount > 1;
}

/// Resolve one day for display.
///
/// PRECEDENCE — UNCHANGED, deliberately. A dated entry masks every recurring
/// schedule that day, exactly as all four surfaces already did via
/// `calEntry?.x ?? recurring...`. Whether that is right is B2's question;
/// changing it here would mask the storage bug (a date still holds only ONE
/// dated entry — A1 is unbuilt).
///
/// ORDERING — newest-wins (B3). `sortKey` is stamped max+1 per insert and both
/// backends deliver ascending order, so the newest matching schedule is the
/// LAST element. `.first` showed the OLDEST, which meant adding a schedule to an
/// already-covered day changed nothing visible and read as a failed save.
///
/// [recurringForDay] must already be filtered to this weekday, in the order the
/// providers deliver it (ascending `sortKey`). Filtering preserves relative
/// order, so the last element is still the newest.
DayResolution resolveDay({
  required CalendarEntry? datedEntry,
  required List<ScheduleItem> recurringForDay,
}) {
  final armable = recurringForDay
      .where((s) => s.enabled && !s.isCurrentlyEvicted)
      .toList(growable: false);

  final total = armable.length + (datedEntry != null ? 1 : 0);

  if (datedEntry != null) {
    return DayResolution(
      source: DaySource.dated,
      datedEntry: datedEntry,
      recurringPrimary: null,
      // Masked, not discarded — a "+N" badge must be able to count them.
      others: armable.reversed.toList(growable: false),
      totalCount: total,
    );
  }

  if (armable.isEmpty) return DayResolution.empty;

  // Newest = LAST. Everything else, newest-first.
  final newest = armable.last;
  final rest = armable
      .sublist(0, armable.length - 1)
      .reversed
      .toList(growable: false);

  return DayResolution(
    source: DaySource.recurring,
    datedEntry: null,
    recurringPrimary: newest,
    others: rest,
    totalCount: total,
  );
}
