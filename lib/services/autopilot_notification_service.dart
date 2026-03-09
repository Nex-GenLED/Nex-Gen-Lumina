import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:nexgen_command/models/autopilot_schedule_item.dart';
import 'package:nexgen_command/models/user_model.dart';

/// Notification ID reserved for the weekly autopilot brief.
const _kWeeklyBriefNotificationId = 7700;

/// Day names used for formatting schedule highlights.
const _kDayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

class AutopilotNotificationService {
  final FlutterLocalNotificationsPlugin _plugin;

  AutopilotNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Schedule a weekly brief notification for the coming Sunday at 19:00
  /// in the user's IANA timezone (falls back to device local).
  ///
  /// If today is Sunday and it's before 19:00, schedules for today.
  /// Cancels any previously scheduled weekly brief before rescheduling.
  Future<void> scheduleWeeklyBrief({
    required UserModel profile,
    required List<AutopilotScheduleItem> schedule,
  }) async {
    try {
      // Cancel existing before rescheduling
      await cancelWeeklyBrief();

      final location = _resolveLocation(profile.timeZone);
      final now = tz.TZDateTime.now(location);
      final targetTime = _nextSunday7pm(now, location);

      final body = generateBriefBody(schedule: schedule);
      if (body.isEmpty) return;

      const androidDetails = AndroidNotificationDetails(
        'autopilot_weekly',
        'Autopilot Weekly Brief',
        channelDescription: 'Weekly preview of your upcoming autopilot schedule',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(''),
      );

      const iosDetails = DarwinNotificationDetails(
        interruptionLevel: InterruptionLevel.active,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Payload is next Monday's ISO date so the deep-link opens that week.
      final nextMonday = _nextMonday(targetTime);
      final payload = nextMonday.toIso8601String().split('T').first; // e.g. "2026-03-16"

      await _plugin.zonedSchedule(
        _kWeeklyBriefNotificationId,
        'Your Week in Lights',
        body,
        targetTime,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: null, // One-shot; re-scheduled each generation
        payload: payload,
      );

      debugPrint(
        'AutopilotNotificationService: Weekly brief scheduled for $targetTime',
      );
    } catch (e) {
      debugPrint('AutopilotNotificationService: scheduleWeeklyBrief failed: $e');
    }
  }

  /// Cancel the weekly brief notification.
  Future<void> cancelWeeklyBrief() async {
    try {
      await _plugin.cancel(_kWeeklyBriefNotificationId);
    } catch (e) {
      debugPrint('AutopilotNotificationService: cancelWeeklyBrief failed: $e');
    }
  }

  /// Generate a 2–3 sentence push notification body summarising the week.
  ///
  /// Counts events by type, names the top 2 highlights with their day name,
  /// and ends with an encouraging line.
  String generateBriefBody({required List<AutopilotScheduleItem> schedule}) {
    if (schedule.isEmpty) return '';

    // Count events by trigger type
    final typeCounts = <AutopilotTrigger, int>{};
    for (final item in schedule) {
      typeCounts[item.trigger] = (typeCounts[item.trigger] ?? 0) + 1;
    }

    // Pick top 2 highlights (prefer holidays & game days, then by confidence)
    final ranked = List<AutopilotScheduleItem>.from(schedule)
      ..sort((a, b) {
        const priorityOrder = {
          AutopilotTrigger.holiday: 0,
          AutopilotTrigger.gameDay: 1,
          AutopilotTrigger.seasonal: 2,
          AutopilotTrigger.sportsScoreAlert: 3,
          AutopilotTrigger.custom: 4,
          AutopilotTrigger.learned: 5,
          AutopilotTrigger.sunset: 6,
          AutopilotTrigger.sunrise: 7,
          AutopilotTrigger.weeknight: 8,
          AutopilotTrigger.weekend: 9,
        };
        final pa = priorityOrder[a.trigger] ?? 10;
        final pb = priorityOrder[b.trigger] ?? 10;
        if (pa != pb) return pa.compareTo(pb);
        return b.confidenceScore.compareTo(a.confidenceScore);
      });

    final highlights = ranked.take(2).toList();

    // Build highlight phrases: "Chiefs game Monday", "St. Patrick's Day Wednesday"
    final highlightPhrases = highlights.map((item) {
      final dayName = _dayNameFor(item.scheduledTime);
      final name = item.eventName ?? item.patternName;
      return '$name $dayName';
    }).toList();

    // Build type summary tokens like "2 holiday", "1 gameDay"
    final typeTokens = <String>[];
    for (final trigger in [
      AutopilotTrigger.holiday,
      AutopilotTrigger.gameDay,
      AutopilotTrigger.seasonal,
    ]) {
      final count = typeCounts[trigger];
      if (count != null && count > 0) {
        typeTokens.add('$count ${_triggerLabel(trigger)}');
      }
    }

    // Assemble body
    final buffer = StringBuffer();

    // Sentence 1: highlights
    if (highlightPhrases.length == 2) {
      buffer.write('${highlightPhrases[0]}, ${highlightPhrases[1]}');
    } else if (highlightPhrases.length == 1) {
      buffer.write(highlightPhrases[0]);
    }

    // Sentence 2: total count
    final totalEvents = schedule.length;
    if (totalEvents > 0) {
      final noun = totalEvents == 1 ? 'event' : 'events';
      buffer.write(' \u2014 $totalEvents $noun lined up.');
    }

    // Sentence 3: encouraging CTA
    buffer.write(' Tap to preview or adjust any day.');

    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Resolve a [tz.Location] from an IANA timezone string, falling back to [tz.local].
  tz.Location _resolveLocation(String? ianaTimezone) {
    if (ianaTimezone == null || ianaTimezone.isEmpty) return tz.local;
    try {
      return tz.getLocation(ianaTimezone);
    } catch (_) {
      return tz.local;
    }
  }

  /// Returns the next Sunday at 19:00 in [location].
  /// If today is Sunday before 19:00, returns today at 19:00.
  tz.TZDateTime _nextSunday7pm(tz.TZDateTime now, tz.Location location) {
    // DateTime.weekday: Monday=1 … Sunday=7
    int daysUntilSunday;
    if (now.weekday == DateTime.sunday) {
      // Today is Sunday
      final todayAt7 = tz.TZDateTime(
        location,
        now.year,
        now.month,
        now.day,
        19,
      );
      if (now.isBefore(todayAt7)) {
        return todayAt7;
      }
      daysUntilSunday = 7; // Next Sunday
    } else {
      daysUntilSunday = DateTime.sunday - now.weekday;
    }

    final sunday = now.add(Duration(days: daysUntilSunday));
    return tz.TZDateTime(
      location,
      sunday.year,
      sunday.month,
      sunday.day,
      19,
    );
  }

  /// Returns the Monday after [from] (the day the weekly brief previews).
  DateTime _nextMonday(DateTime from) {
    // from is Sunday 7pm → Monday is 1 day later
    final daysUntilMonday = (DateTime.monday - from.weekday + 7) % 7;
    return from.add(Duration(days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
  }

  /// Returns the day-of-week name for a DateTime (e.g. "Monday").
  String _dayNameFor(DateTime dt) {
    // DateTime.weekday: Monday=1 … Sunday=7
    return _kDayNames[dt.weekday - 1];
  }

  /// Human-readable label for a trigger type.
  String _triggerLabel(AutopilotTrigger trigger) {
    switch (trigger) {
      case AutopilotTrigger.holiday:
        return 'holiday';
      case AutopilotTrigger.gameDay:
        return 'game day';
      case AutopilotTrigger.seasonal:
        return 'seasonal';
      case AutopilotTrigger.sportsScoreAlert:
        return 'score alert';
      case AutopilotTrigger.custom:
        return 'custom';
      case AutopilotTrigger.learned:
        return 'learned';
      case AutopilotTrigger.sunset:
        return 'sunset';
      case AutopilotTrigger.sunrise:
        return 'sunrise';
      case AutopilotTrigger.weeknight:
        return 'weeknight';
      case AutopilotTrigger.weekend:
        return 'weekend';
    }
  }
}

/// Riverpod provider for the autopilot notification service.
final autopilotNotificationServiceProvider =
    Provider<AutopilotNotificationService>(
  (ref) => AutopilotNotificationService(),
);
