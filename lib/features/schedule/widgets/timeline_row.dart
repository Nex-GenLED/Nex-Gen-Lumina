// lib/features/schedule/widgets/timeline_row.dart
//
// Scheduling V3 A3 — the shared renderer for one [TimelineEntry].
//
// WHY A SHARED WIDGET. The three surfaces that show a day each open-coded their
// own field extraction and their own `calEntry?.x ?? recurring.x` fall-through
// (audit/SCHEDULING_V3_AUDIT.md §3.1-3.3). That is what made the B3
// newest-wins change need edits in four places. The resolution now lives in
// `day_timeline.dart` and the RENDERING of a row lives here, so a surface only
// decides layout.
//
// WHY NOT `NightTrackBar`. Evaluated as the day-hero renderer per the brief and
// rejected — see audit/SCHEDULE_V3_P2.md §"NightTrackBar evaluation". In short:
// it takes `List<ScheduleItem>` so it cannot render a CalendarEntry at all
// (every Game Day is invisible to it); its 6pm→6am axis clamps daytime to the
// edges, so a 13:05 matinee — which exists in production data — draws as if it
// were sunrise; and an entry with no off time is drawn running to sunrise,
// which asserts exactly the false end this work removes.

import 'package:flutter/material.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/day_timeline.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/utils/time_format.dart';

/// Formats a resolved [DateTime] in the user's preferred clock format.
String formatTimelineTime(DateTime? dt, {String timeFormat = '12h'}) {
  if (dt == null) return '—';
  final hhmm = '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
  return formatTimeLabel(hhmm, timeFormat: timeFormat);
}

/// The primary time string for a row: `"7:10 PM → until game ends (est. 10:15 PM)"`
/// for an open-ended entry, `"8:00 PM → 6:00 AM"` for a fixed one.
///
/// An open-ended row NEVER renders a bare clock time as its end. That is the
/// whole point of A1.
String timelineTimeRange(TimelineEntry e, {String timeFormat = '12h'}) {
  final start = e.startsAt == null
      ? _rawStartLabel(e)
      : formatTimelineTime(e.startsAt, timeFormat: timeFormat);

  if (e.isOpenEnded) {
    final dated = e.dated;
    final condition = dated != null
        ? dated.endConditionLabel(
            formatTime: (d) => formatTimelineTime(d, timeFormat: timeFormat))
        : 'until next event';
    return '$start → $condition';
  }
  if (e.endsAt == null) return start;
  return '$start → ${formatTimelineTime(e.endsAt, timeFormat: timeFormat)}';
}

/// What to show when a start time could not be resolved. Shows the raw label
/// rather than a guess — "Sunset" is more honest than a made-up clock time.
String _rawStartLabel(TimelineEntry e) =>
    e.recurring?.timeLabel ?? e.dated?.onTime ?? '—';

/// The secondary line: what today's firing layer will actually do to this row.
///
/// Returns null when there is nothing to say. Each branch corresponds to a
/// derivation in `day_timeline.dart`, and each states a CONSEQUENCE rather than
/// a status word — "Warm White takes over at 8:00 PM" tells the reader what
/// their house does; "superseded" does not.
String? timelineConsequence(TimelineEntry e, {String timeFormat = '12h'}) {
  if (e.conflict) {
    return 'Overlaps another schedule at the same time — '
        'which one runs is not predictable';
  }
  if (e.suppressed && e.suppressedUntil != null) {
    return 'Paused while the game runs — resumes at '
        '${formatTimelineTime(e.suppressedUntil, timeFormat: timeFormat)}';
  }
  if (e.takenOverAt != null) {
    final who = e.takenOverByLabel ?? 'the next schedule';
    return '$who takes over at '
        '${formatTimelineTime(e.takenOverAt, timeFormat: timeFormat)}';
  }
  if (e.timeUnresolved) {
    return 'Start time could not be resolved — check your location settings';
  }
  return null;
}

/// Accent colour for a row, by source.
Color timelineAccent(TimelineEntry e) {
  final c = e.dated?.color;
  if (c != null) return c;
  return switch (e.source) {
    TimelineSource.gameDay => NexGenPalette.cyan,
    TimelineSource.dated => NexGenPalette.amber,
    TimelineSource.recurring => NexGenPalette.violet,
  };
}

/// Short provenance chip text.
String timelineSourceLabel(TimelineEntry e) {
  if (e.source == TimelineSource.gameDay) return '⚡ Game Day';
  final dated = e.dated;
  if (dated != null) {
    return switch (dated.type) {
      CalendarEntryType.holiday => '🎉 Holiday',
      CalendarEntryType.user => '👤 You',
      CalendarEntryType.autopilot => '⚡ Autopilot',
      CalendarEntryType.auto => '⚡ Auto',
    };
  }
  return '🔁 Recurring';
}

/// One row on a day timeline.
class TimelineRowTile extends StatelessWidget {
  final TimelineEntry entry;
  final String timeFormat;
  final VoidCallback? onTap;

  /// Compact mode drops the provenance chip and tightens padding — used by the
  /// dashboard card, where vertical space is scarce.
  final bool compact;

  const TimelineRowTile({
    super.key,
    required this.entry,
    this.timeFormat = '12h',
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = timelineAccent(entry);
    final consequence = timelineConsequence(entry, timeFormat: timeFormat);
    // A suppressed row is shown, but dimmed — it is not what the house will do.
    final dim = entry.suppressed;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: compact ? 0 : 10, vertical: compact ? 5 : 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Accent rail
            Container(
              width: 3,
              height: compact ? 26 : 34,
              margin: const EdgeInsets.only(top: 2, right: 10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: dim ? 0.35 : 1.0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 13 : 14,
                            fontWeight: FontWeight.w600,
                            color: dim
                                ? NexGenPalette.textMedium
                                : NexGenPalette.textHigh,
                          ),
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 8),
                        Text(
                          timelineSourceLabel(entry),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: accent.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timelineTimeRange(entry, timeFormat: timeFormat),
                    style: TextStyle(
                      fontSize: compact ? 11 : 12,
                      color: NexGenPalette.textMedium,
                    ),
                  ),
                  if (consequence != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      consequence,
                      style: TextStyle(
                        fontSize: compact ? 10 : 11,
                        fontStyle: FontStyle.italic,
                        color: entry.conflict
                            ? NexGenPalette.amber
                            : NexGenPalette.textMedium.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "+N more" affordance shown when a surface truncates the timeline.
class TimelineMoreRow extends StatelessWidget {
  final int hiddenCount;
  final VoidCallback? onTap;

  const TimelineMoreRow({super.key, required this.hiddenCount, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            const SizedBox(width: 13),
            Text(
              '+$hiddenCount more ${hiddenCount == 1 ? 'schedule' : 'schedules'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: NexGenPalette.cyan,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 14, color: NexGenPalette.cyan),
          ],
        ),
      ),
    );
  }
}

/// Accent colour for a day surface, taken from the date's PRIMARY dated entry.
///
/// Recurring schedules carry no colour, so a recurring-only day has none — the
/// same as before V3. Returns null when the date has no dated entry.
Color? timelineLeadColor(List<CalendarEntry> datedEntries) =>
    datedEntries.isEmpty ? null : datedEntries.last.color;

/// The day's rows, optionally truncated with a "+N more" tail.
///
/// SHARED BY THE DASHBOARD CARD AND THE DAY HERO. Both surfaces render the same
/// component with different budgets — the card takes two rows, the hero takes
/// all of them — so "what a timeline looks like" has one definition and the
/// widget tests exercise the real thing rather than a copy of its logic.
class DayTimelineList extends StatelessWidget {
  final DayTimeline timeline;

  /// Show at most this many rows, with the remainder behind a "+N more".
  /// Null shows every row.
  final int? maxRows;

  final String timeFormat;
  final bool compact;

  /// Tapping a row. Both surfaces currently route to the same place as
  /// [onMoreTap]; the split exists so a row can gain its own target later.
  final VoidCallback? onRowTap;
  final VoidCallback? onMoreTap;

  const DayTimelineList({
    super.key,
    required this.timeline,
    this.maxRows,
    this.timeFormat = '12h',
    this.compact = false,
    this.onRowTap,
    this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final all = timeline.entries;
    final limit = maxRows;
    final shown = (limit == null || all.length <= limit) ? all : all.take(limit).toList();
    final hidden = all.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in shown)
          TimelineRowTile(
            entry: e,
            timeFormat: timeFormat,
            compact: compact,
            onTap: onRowTap,
          ),
        if (hidden > 0) TimelineMoreRow(hiddenCount: hidden, onTap: onMoreTap),
      ],
    );
  }
}

/// The multi-entry count badge shown on a week cell.
///
/// Renders nothing for a day with 0 or 1 entries — a badge reading "1" is
/// noise. Turns amber when the day holds an unresolvable same-minute overlap,
/// because that is the case a reader most needs to notice.
class TimelineCountBadge extends StatelessWidget {
  final int count;
  final bool hasConflict;

  const TimelineCountBadge({
    super.key,
    required this.count,
    this.hasConflict = false,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    final c = hasConflict ? NexGenPalette.amber : NexGenPalette.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: hasConflict ? 0.22 : 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: c,
        ),
      ),
    );
  }
}
