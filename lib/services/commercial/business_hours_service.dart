import 'package:nexgen_command/models/commercial/business_hours.dart';
import 'package:nexgen_command/models/commercial/holiday_calendar.dart';

/// Service for evaluating business hours, holiday conflicts, and
/// determining the current operating state for autopilot awareness.
class BusinessHoursService {
  const BusinessHoursService();

  /// Whether the business is open right now, factoring in weekly schedule,
  /// standard holidays, and custom closures.
  ///
  /// Returns `false` if today is a closure date or observed holiday
  /// (unless a [SpecialEvent] overrides it).
  bool isBusinessOpen(BusinessHours hours, HolidayCalendar calendar) {
    final now = DateTime.now();

    // Custom closures take precedence.
    if (calendar.isCustomClosure(now)) return false;

    // Standard holidays — closed unless a special event overrides.
    if (calendar.isStandardHoliday(now)) {
      final evt = calendar.activeSpecialEvent(now);
      // If a special event is active it means the business explicitly chose
      // to stay open (e.g. holiday sale). Otherwise, honour the holiday.
      if (evt == null) return false;
    }

    return hours.isCurrentlyOpen();
  }

  /// Returns a human-readable label for the current operating period.
  ///
  /// Possible values: `'Pre-Open'`, `'Open'`, `'Wind-Down'`, `'Closed'`.
  String getCurrentDayPart(BusinessHours hours) {
    final sched = hours.todaySchedule;
    if (sched == null || !sched.isOpen) return 'Closed';

    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final openMin = sched.openTime.hour * 60 + sched.openTime.minute;
    final closeMin = sched.closeTime.hour * 60 + sched.closeTime.minute;
    final preOpenMin = openMin - hours.preOpenBufferMinutes;
    final postCloseMin = closeMin + hours.postCloseWindDownMinutes;

    // Handle overnight span by normalizing to a 0–1440 window.
    int norm(int m) => m < 0 ? m + 1440 : m % 1440;

    final normNow = norm(nowMin);
    final normPreOpen = norm(preOpenMin);
    final normOpen = norm(openMin);
    final normClose = norm(closeMin);
    final normPostClose = norm(postCloseMin);

    // Simple non-overnight case.
    if (closeMin > openMin) {
      if (normNow >= normPreOpen && normNow < normOpen) return 'Pre-Open';
      if (normNow >= normOpen && normNow < normClose) return 'Open';
      if (normNow >= normClose && normNow < normPostClose) return 'Wind-Down';
      return 'Closed';
    }

    // Overnight span (e.g. bar open 18:00 – 02:00).
    if (normNow >= normPreOpen && normNow < normOpen) return 'Pre-Open';
    if (normNow >= normOpen || normNow < normClose) return 'Open';
    if (normNow >= normClose && normNow < normPostClose) return 'Wind-Down';
    return 'Closed';
  }

  /// Returns the next open or close [DateTime] — whichever comes first.
  /// Scans up to 7 days ahead. Returns `null` if nothing is scheduled.
  DateTime? getNextTransition(BusinessHours hours) {
    final nextOpen = hours.nextOpenTime();
    final nextClose = hours.nextCloseTime();
    if (nextOpen == null) return nextClose;
    if (nextClose == null) return nextOpen;
    return nextOpen.isBefore(nextClose) ? nextOpen : nextClose;
  }

  /// Returns the first [SpecialEvent] (including standard-holiday entries
  /// mapped to events) occurring within the next 7 days, or `null`.
  SpecialEvent? upcomingHolidayConflict(HolidayCalendar calendar) {
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 7));

    // Check special events first.
    for (final evt in calendar.specialEvents) {
      if (evt.startDate.isBefore(horizon) && evt.endDate.isAfter(now)) {
        return evt;
      }
    }

    // Check observed standard holidays in the next 7 days.
    if (calendar.standardHolidaysEnabled) {
      for (var i = 0; i < 7; i++) {
        final date = now.add(Duration(days: i));
        if (calendar.isStandardHoliday(date)) {
          // Find the matching holiday name for a readable event.
          for (final key in calendar.observedHolidays) {
            final holiday = _matchHoliday(key);
            if (holiday == null) continue;
            final hDate = holiday.dateForYear(date.year);
            if (hDate.month == date.month && hDate.day == date.day) {
              return SpecialEvent(
                startDate: hDate,
                endDate: hDate,
                name: holiday.displayName,
              );
            }
          }
        }
      }
    }

    return null;
  }

  /// Try to resolve a holiday key string to [StandardHoliday].
  static StandardHoliday? _matchHoliday(String key) {
    for (final h in StandardHoliday.values) {
      if (h.name == key) return h;
    }
    return null;
  }
}
