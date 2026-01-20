import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/autopilot_generation_service.dart';
import 'package:nexgen_command/services/calendar_event_service.dart';

/// Service responsible for weekly Autopilot schedule preview notifications.
///
/// Sends notifications on Sunday evenings with the upcoming Monday-Sunday schedule.
/// Only sends notifications when there are special events (games, holidays) that
/// differ from the standard evening schedule.
class AutopilotNotificationService {
  final Ref _ref;

  /// Cache of the last notified week to avoid duplicate notifications.
  DateTime? _lastNotifiedWeekStart;

  AutopilotNotificationService(this._ref);

  /// Check if it's time to send the weekly preview notification.
  ///
  /// Returns true on Sunday evenings (after 5 PM local time).
  bool shouldSendWeeklyPreview() {
    final now = DateTime.now();
    final isSunday = now.weekday == DateTime.sunday;
    final isEvening = now.hour >= 17; // After 5 PM

    if (!isSunday || !isEvening) return false;

    // Check if we already sent notification for this week
    final weekStart = _getNextMondayStart(now);
    if (_lastNotifiedWeekStart == weekStart) return false;

    return true;
  }

  /// Generate and send the weekly schedule preview.
  ///
  /// Returns a [WeeklySchedulePreview] with the upcoming schedule,
  /// or null if there are no special events to notify about.
  Future<WeeklySchedulePreview?> generateWeeklyPreview() async {
    final profile = _getCurrentProfile();
    if (profile == null || !profile.autopilotEnabled) {
      debugPrint('AutopilotNotification: Autopilot disabled or no profile');
      return null;
    }

    final now = DateTime.now();
    final weekStart = _getNextMondayStart(now);
    final weekEnd = weekStart.add(const Duration(days: 7));

    // Generate the schedule for the upcoming week
    final generationService = _ref.read(autopilotGenerationServiceProvider);
    final schedule = await generationService.generateWeeklySchedule(
      profile: profile,
      weekStart: weekStart,
    );

    // Filter to only special events (games, holidays, custom)
    final specialEvents = schedule.where((item) => _isSpecialEvent(item)).toList();

    // If no special events, don't send notification
    if (specialEvents.isEmpty) {
      debugPrint('AutopilotNotification: No special events this week');
      return null;
    }

    // Mark this week as notified
    _lastNotifiedWeekStart = weekStart;

    // Build the preview
    return WeeklySchedulePreview(
      weekStart: weekStart,
      weekEnd: weekEnd,
      specialEvents: specialEvents,
      allScheduleItems: schedule,
      userName: profile.displayName,
      generatedAt: now,
    );
  }

  /// Check if a schedule item is a "special" event worth notifying about.
  ///
  /// Returns true for holidays, game days, and custom events.
  /// Returns false for standard daily patterns (weeknight, weekend, sunrise, sunset).
  bool _isSpecialEvent(AutopilotScheduleItem item) {
    switch (item.trigger) {
      case AutopilotTrigger.holiday:
      case AutopilotTrigger.gameDay:
      case AutopilotTrigger.seasonal:
      case AutopilotTrigger.custom:
        return true;
      case AutopilotTrigger.weeknight:
      case AutopilotTrigger.weekend:
      case AutopilotTrigger.sunrise:
      case AutopilotTrigger.sunset:
      case AutopilotTrigger.learned:
        return false;
    }
  }

  /// Get the start of next Monday (or today if it's Monday and before 5 PM).
  DateTime _getNextMondayStart(DateTime from) {
    var daysUntilMonday = DateTime.monday - from.weekday;
    if (daysUntilMonday <= 0) daysUntilMonday += 7;
    final monday = from.add(Duration(days: daysUntilMonday));
    return DateTime(monday.year, monday.month, monday.day);
  }

  /// Format the preview for email/notification content.
  String formatPreviewForNotification(WeeklySchedulePreview preview) {
    final buffer = StringBuffer();
    buffer.writeln('Hi ${preview.userName ?? "there"},');
    buffer.writeln();
    buffer.writeln("Here's your lighting schedule preview for the upcoming week:");
    buffer.writeln();

    // Group events by day
    final eventsByDay = <String, List<AutopilotScheduleItem>>{};
    for (final item in preview.specialEvents) {
      final dayName = _formatDayName(item.scheduledTime);
      eventsByDay.putIfAbsent(dayName, () => []).add(item);
    }

    // Format each day
    final dayOrder = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    for (final day in dayOrder) {
      final events = eventsByDay[day];
      if (events != null && events.isNotEmpty) {
        buffer.writeln('$day:');
        for (final event in events) {
          final timeStr = _formatTime(event.scheduledTime);
          buffer.writeln('  • $timeStr - ${event.patternName}');
          if (event.reason.isNotEmpty) {
            buffer.writeln('    ${event.reason}');
          }
        }
        buffer.writeln();
      }
    }

    buffer.writeln('---');
    buffer.writeln('You can review and adjust this schedule in the Lumina app.');
    buffer.writeln();
    buffer.writeln('To stop receiving these previews, disable "Weekly Schedule Preview"');
    buffer.writeln('in your Autopilot settings.');

    return buffer.toString();
  }

  /// Format the preview as HTML for email.
  String formatPreviewAsHtml(WeeklySchedulePreview preview) {
    final buffer = StringBuffer();
    buffer.writeln('''
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: #333; line-height: 1.6; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #00E5FF, #7C4DFF); color: white; padding: 20px; border-radius: 12px 12px 0 0; }
    .content { background: #f8f9fa; padding: 20px; border-radius: 0 0 12px 12px; }
    .day { margin-bottom: 16px; }
    .day-name { font-weight: bold; color: #00BCD4; margin-bottom: 8px; }
    .event { background: white; padding: 12px; border-radius: 8px; margin-bottom: 8px; border-left: 4px solid #00E5FF; }
    .event-time { color: #666; font-size: 14px; }
    .event-pattern { font-weight: 600; color: #333; }
    .event-reason { color: #888; font-size: 13px; }
    .footer { text-align: center; color: #888; font-size: 12px; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1 style="margin: 0;">✨ Your Weekly Lighting Preview</h1>
      <p style="margin: 8px 0 0 0; opacity: 0.9;">Week of ${_formatDateRange(preview.weekStart, preview.weekEnd)}</p>
    </div>
    <div class="content">
      <p>Hi ${preview.userName ?? 'there'},</p>
      <p>Here's what Lumina has planned for your lights this week:</p>
''');

    // Group events by day
    final eventsByDay = <String, List<AutopilotScheduleItem>>{};
    for (final item in preview.specialEvents) {
      final dayName = _formatDayName(item.scheduledTime);
      eventsByDay.putIfAbsent(dayName, () => []).add(item);
    }

    // Format each day
    final dayOrder = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    for (final day in dayOrder) {
      final events = eventsByDay[day];
      if (events != null && events.isNotEmpty) {
        buffer.writeln('<div class="day">');
        buffer.writeln('  <div class="day-name">$day</div>');
        for (final event in events) {
          final timeStr = _formatTime(event.scheduledTime);
          buffer.writeln('''
          <div class="event">
            <div class="event-time">$timeStr</div>
            <div class="event-pattern">${event.patternName}</div>
            ${event.reason.isNotEmpty ? '<div class="event-reason">${event.reason}</div>' : ''}
          </div>
''');
        }
        buffer.writeln('</div>');
      }
    }

    buffer.writeln('''
      <p style="margin-top: 20px;">
        <a href="lumina://schedule" style="background: #00E5FF; color: #000; padding: 12px 24px; border-radius: 8px; text-decoration: none; font-weight: 600;">
          Review in App
        </a>
      </p>
    </div>
    <div class="footer">
      <p>Lumina Autopilot • Set it and forget it</p>
      <p>To stop receiving these emails, disable "Weekly Schedule Preview" in your Autopilot settings.</p>
    </div>
  </div>
</body>
</html>
''');

    return buffer.toString();
  }

  /// Format day name from DateTime.
  String _formatDayName(DateTime date) {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return days[date.weekday - 1];
  }

  /// Format time as "7:00 PM".
  String _formatTime(DateTime date) {
    final hour = date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  /// Format date range as "Jan 20 - Jan 26".
  String _formatDateRange(DateTime start, DateTime end) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final startMonth = months[start.month - 1];
    final endMonth = months[end.month - 1];
    if (startMonth == endMonth) {
      return '$startMonth ${start.day} - ${end.day}';
    }
    return '$startMonth ${start.day} - $endMonth ${end.day}';
  }

  UserModel? _getCurrentProfile() {
    final profileAsync = _ref.read(currentUserProfileProvider);
    return profileAsync.maybeWhen(
      data: (p) => p,
      orElse: () => null,
    );
  }
}

/// Data class representing a weekly schedule preview.
class WeeklySchedulePreview {
  /// Start of the week (Monday).
  final DateTime weekStart;

  /// End of the week (Sunday).
  final DateTime weekEnd;

  /// Special events that differ from the standard schedule.
  final List<AutopilotScheduleItem> specialEvents;

  /// All schedule items for the week.
  final List<AutopilotScheduleItem> allScheduleItems;

  /// User's display name for personalization.
  final String? userName;

  /// When the preview was generated.
  final DateTime generatedAt;

  const WeeklySchedulePreview({
    required this.weekStart,
    required this.weekEnd,
    required this.specialEvents,
    required this.allScheduleItems,
    this.userName,
    required this.generatedAt,
  });

  /// Number of special events this week.
  int get specialEventCount => specialEvents.length;

  /// Whether this week has any special events.
  bool get hasSpecialEvents => specialEvents.isNotEmpty;

  /// Get events for a specific day (1=Monday, 7=Sunday).
  List<AutopilotScheduleItem> eventsForDay(int weekday) {
    return allScheduleItems.where((item) =>
      item.scheduledTime.weekday == weekday &&
      item.scheduledTime.isAfter(weekStart) &&
      item.scheduledTime.isBefore(weekEnd.add(const Duration(days: 1)))
    ).toList();
  }
}

/// Provider for the autopilot notification service.
final autopilotNotificationServiceProvider = Provider<AutopilotNotificationService>(
  (ref) => AutopilotNotificationService(ref),
);

/// Provider to check if weekly preview should be sent.
final shouldSendWeeklyPreviewProvider = Provider<bool>((ref) {
  final service = ref.watch(autopilotNotificationServiceProvider);
  final enabled = ref.watch(autopilotEnabledProvider);
  final weeklyPreviewEnabled = ref.watch(weeklySchedulePreviewEnabledProvider);

  return enabled && weeklyPreviewEnabled && service.shouldSendWeeklyPreview();
});

/// Provider for user preference on weekly preview notifications.
/// Defaults to true when autopilot is enabled.
final weeklySchedulePreviewEnabledProvider = Provider<bool>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.weeklySchedulePreviewEnabled ?? true,
    orElse: () => true,
  );
});
