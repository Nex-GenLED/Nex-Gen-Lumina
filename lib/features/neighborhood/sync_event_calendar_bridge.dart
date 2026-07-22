// lib/features/neighborhood/sync_event_calendar_bridge.dart
//
// Materializes Neighborhood Sync events into CalendarEntry form so the
// night composer can place them into the priority hierarchy alongside
// Game Day and personal autopilot entries.
//
// Today no production path automatically mirrors sync events into the
// user's CalendarEntry collection. Until that mirror is wired (e.g. via
// a Riverpod listener on `enabledSyncEventsProvider` that writes through
// `calendarScheduleProvider.notifier.applyEntries`), this extension is
// the canonical conversion: any future caller — session manager, sync
// notifier, or background trigger — should call `toCalendarEntry()` to
// produce a properly-tagged entry.

import 'package:nexgen_command/features/schedule/calendar_entry.dart';

import 'models/sync_event.dart';

extension SyncEventCalendarBridge on SyncEvent {
  /// Convert a sync event into a CalendarEntry tagged with
  /// [CalendarEntrySourceTag.neighborhoodSync] for a specific date.
  ///
  /// Returns null if the event has no scheduled time on [date] (e.g.
  /// recurring events that don't fall on the requested day, or events
  /// scheduled for a different date entirely).
  ///
  /// Game-day events default to a 3-hour window (matching the existing
  /// conflict-detection convention in `SyncEventService.findConflict`);
  /// other events use [defaultDurationMinutes].
  CalendarEntry? toCalendarEntry({
    required DateTime date,
    int defaultDurationMinutes = 60,
  }) {
    final start = scheduledTime;
    if (start == null) return null;

    final localStart = start.toLocal();
    if (localStart.year != date.year ||
        localStart.month != date.month ||
        localStart.day != date.day) {
      return null;
    }

    final end = localStart.add(
      isGameDay
          ? const Duration(hours: 3)
          : Duration(minutes: defaultDurationMinutes),
    );

    String hhmm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';

    final dateKey = '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    return CalendarEntry(
      dateKey: dateKey,
      patternName: name,
      onTime: hhmm(localStart),
      offTime: hhmm(end),
      type: CalendarEntryType.autopilot,
      autopilot: true,
      note: 'Neighborhood Sync — $name',
      sourceTag: CalendarEntrySourceTag.neighborhoodSync,
    );
  }
}
