import 'package:flutter/material.dart';
import 'package:nexgen_command/models/commercial/business_hours.dart';
import 'package:nexgen_command/models/commercial/day_part.dart';

/// Generates standard day-part lists by business type.
///
/// Templates produce default [DayPart] lists whose times are derived from the
/// provided [BusinessHours] open/close window. All day-parts span every day
/// in the weekly schedule that is marked as open.
class DayPartTemplate {
  DayPartTemplate._();

  // ── Public factory ─────────────────────────────────────────────────────────

  /// Returns a default day-part list for [businessType] calculated against
  /// [hours]. Recognised type strings match [BusinessProfile.businessType].
  static List<DayPart> forBusinessType(
    String businessType,
    BusinessHours hours,
  ) {
    switch (businessType.toLowerCase().replaceAll(RegExp(r'[\s/]'), '_')) {
      case 'bar_nightclub':
      case 'bar':
      case 'nightclub':
        return _barNightclub(hours);
      case 'restaurant_casual':
      case 'casual_dining':
        return _restaurantCasual(hours);
      case 'restaurant_fine_dining':
      case 'fine_dining':
        return _restaurantFineDining(hours);
      case 'fast_casual':
      case 'fast_casual_qsr':
      case 'qsr':
        return _fastCasual(hours);
      case 'retail_boutique':
      case 'boutique':
        return _retailBoutique(hours);
      case 'retail_chain':
      case 'retail_chain_multi_unit':
      case 'chain':
        return _retailChain(hours);
      default:
        // Fallback: simple pre-open / open / post-close.
        return _generic(hours);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Collects all open days from the weekly schedule.
  static List<DayOfWeek> _openDays(BusinessHours hours) =>
      hours.weeklySchedule.entries
          .where((e) => e.value.isOpen)
          .map((e) => e.key)
          .toList();

  /// The earliest open time across all open days.
  static TimeOfDay _earliestOpen(BusinessHours hours) {
    TimeOfDay earliest = const TimeOfDay(hour: 23, minute: 59);
    for (final sched in hours.weeklySchedule.values) {
      if (!sched.isOpen) continue;
      final min = sched.openTime.hour * 60 + sched.openTime.minute;
      final eMin = earliest.hour * 60 + earliest.minute;
      if (min < eMin) earliest = sched.openTime;
    }
    return earliest;
  }

  /// The latest close time across all open days.
  static TimeOfDay _latestClose(BusinessHours hours) {
    TimeOfDay latest = const TimeOfDay(hour: 0, minute: 0);
    for (final sched in hours.weeklySchedule.values) {
      if (!sched.isOpen) continue;
      final min = sched.closeTime.hour * 60 + sched.closeTime.minute;
      final lMin = latest.hour * 60 + latest.minute;
      if (min > lMin) latest = sched.closeTime;
    }
    return latest;
  }

  /// Subtracts [minutes] from a [TimeOfDay], wrapping past midnight.
  static TimeOfDay _subtract(TimeOfDay t, int minutes) {
    var total = t.hour * 60 + t.minute - minutes;
    if (total < 0) total += 1440;
    return TimeOfDay(hour: total ~/ 60, minute: total % 60);
  }

  /// Adds [minutes] to a [TimeOfDay], wrapping past midnight.
  static TimeOfDay _add(TimeOfDay t, int minutes) {
    final total = (t.hour * 60 + t.minute + minutes) % 1440;
    return TimeOfDay(hour: total ~/ 60, minute: total % 60);
  }

  static int _counter = 0;
  static String _nextId() => 'dp_${++_counter}';

  // ── BAR / NIGHTCLUB ────────────────────────────────────────────────────────

  static List<DayPart> _barNightclub(BusinessHours hours) {
    final days = _openDays(hours);
    final open = _earliestOpen(hours);
    final close = _latestClose(hours);
    final preOpen = _subtract(open, hours.preOpenBufferMinutes);
    final postClose = _add(close, hours.postCloseWindDownMinutes);

    return [
      DayPart(id: _nextId(), name: 'Pre-Open', startTime: preOpen, endTime: open, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Afternoon Ambient', startTime: open, endTime: const TimeOfDay(hour: 17, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Happy Hour', startTime: const TimeOfDay(hour: 17, minute: 0), endTime: const TimeOfDay(hour: 19, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Dinner / Early Night', startTime: const TimeOfDay(hour: 19, minute: 0), endTime: const TimeOfDay(hour: 21, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Peak Night', startTime: const TimeOfDay(hour: 21, minute: 0), endTime: const TimeOfDay(hour: 23, minute: 30), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Late Night', startTime: const TimeOfDay(hour: 23, minute: 30), endTime: close, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Post-Close', startTime: close, endTime: postClose, daysOfWeek: days),
    ];
  }

  // ── RESTAURANT — CASUAL ────────────────────────────────────────────────────

  static List<DayPart> _restaurantCasual(BusinessHours hours) {
    final days = _openDays(hours);
    final open = _earliestOpen(hours);
    final close = _latestClose(hours);
    final preOpen = _subtract(open, hours.preOpenBufferMinutes);
    final postClose = _add(close, hours.postCloseWindDownMinutes);

    return [
      DayPart(id: _nextId(), name: 'Pre-Open', startTime: preOpen, endTime: open, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Breakfast / Brunch', startTime: open, endTime: const TimeOfDay(hour: 11, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Lunch Rush', startTime: const TimeOfDay(hour: 11, minute: 0), endTime: const TimeOfDay(hour: 14, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Afternoon', startTime: const TimeOfDay(hour: 14, minute: 0), endTime: const TimeOfDay(hour: 17, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Happy Hour', startTime: const TimeOfDay(hour: 17, minute: 0), endTime: const TimeOfDay(hour: 18, minute: 30), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Dinner Service', startTime: const TimeOfDay(hour: 18, minute: 30), endTime: close, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Post-Close', startTime: close, endTime: postClose, daysOfWeek: days),
    ];
  }

  // ── RESTAURANT — FINE DINING ───────────────────────────────────────────────

  static List<DayPart> _restaurantFineDining(BusinessHours hours) {
    final days = _openDays(hours);
    final open = _earliestOpen(hours);
    final close = _latestClose(hours);
    final preOpen = _subtract(open, hours.preOpenBufferMinutes);
    final postClose = _add(close, hours.postCloseWindDownMinutes);

    return [
      DayPart(id: _nextId(), name: 'Pre-Open', startTime: preOpen, endTime: open, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Lunch Service', startTime: open, endTime: const TimeOfDay(hour: 14, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Afternoon', startTime: const TimeOfDay(hour: 14, minute: 0), endTime: const TimeOfDay(hour: 17, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Dinner Prep', startTime: const TimeOfDay(hour: 17, minute: 0), endTime: const TimeOfDay(hour: 18, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Dinner Service', startTime: const TimeOfDay(hour: 18, minute: 0), endTime: close, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Post-Close', startTime: close, endTime: postClose, daysOfWeek: days),
    ];
  }

  // ── FAST CASUAL / QSR ─────────────────────────────────────────────────────

  static List<DayPart> _fastCasual(BusinessHours hours) {
    final days = _openDays(hours);
    final open = _earliestOpen(hours);
    final close = _latestClose(hours);
    final preOpen = _subtract(open, hours.preOpenBufferMinutes);
    final postClose = _add(close, hours.postCloseWindDownMinutes);

    return [
      DayPart(id: _nextId(), name: 'Pre-Open', startTime: preOpen, endTime: open, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Morning Rush', startTime: open, endTime: const TimeOfDay(hour: 10, minute: 30), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Midday Rush', startTime: const TimeOfDay(hour: 10, minute: 30), endTime: const TimeOfDay(hour: 14, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Afternoon Lull', startTime: const TimeOfDay(hour: 14, minute: 0), endTime: const TimeOfDay(hour: 17, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Evening', startTime: const TimeOfDay(hour: 17, minute: 0), endTime: close, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Post-Close', startTime: close, endTime: postClose, daysOfWeek: days),
    ];
  }

  // ── RETAIL — BOUTIQUE ──────────────────────────────────────────────────────

  static List<DayPart> _retailBoutique(BusinessHours hours) {
    final days = _openDays(hours);
    final open = _earliestOpen(hours);
    final close = _latestClose(hours);
    final preOpen = _subtract(open, hours.preOpenBufferMinutes);
    final postClose = _add(close, hours.postCloseWindDownMinutes);

    return [
      DayPart(id: _nextId(), name: 'Pre-Open', startTime: preOpen, endTime: open, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Morning Browse', startTime: open, endTime: const TimeOfDay(hour: 11, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Midday', startTime: const TimeOfDay(hour: 11, minute: 0), endTime: const TimeOfDay(hour: 14, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Afternoon', startTime: const TimeOfDay(hour: 14, minute: 0), endTime: const TimeOfDay(hour: 17, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Evening Wind-Down', startTime: const TimeOfDay(hour: 17, minute: 0), endTime: close, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Post-Close', startTime: close, endTime: postClose, daysOfWeek: days),
    ];
  }

  // ── RETAIL — CHAIN ─────────────────────────────────────────────────────────

  static List<DayPart> _retailChain(BusinessHours hours) {
    final days = _openDays(hours);
    final open = _earliestOpen(hours);
    final close = _latestClose(hours);
    final preOpen = _subtract(open, hours.preOpenBufferMinutes);
    final postClose = _add(close, hours.postCloseWindDownMinutes);

    return [
      DayPart(id: _nextId(), name: 'Pre-Open', startTime: preOpen, endTime: open, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Morning', startTime: open, endTime: const TimeOfDay(hour: 11, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Midday Peak', startTime: const TimeOfDay(hour: 11, minute: 0), endTime: const TimeOfDay(hour: 14, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Afternoon', startTime: const TimeOfDay(hour: 14, minute: 0), endTime: const TimeOfDay(hour: 17, minute: 0), daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Evening', startTime: const TimeOfDay(hour: 17, minute: 0), endTime: close, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Post-Close', startTime: close, endTime: postClose, daysOfWeek: days),
    ];
  }

  // ── GENERIC FALLBACK ──────────────────────────────────────────────────────

  static List<DayPart> _generic(BusinessHours hours) {
    final days = _openDays(hours);
    final open = _earliestOpen(hours);
    final close = _latestClose(hours);
    final preOpen = _subtract(open, hours.preOpenBufferMinutes);
    final postClose = _add(close, hours.postCloseWindDownMinutes);

    return [
      DayPart(id: _nextId(), name: 'Pre-Open', startTime: preOpen, endTime: open, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Open', startTime: open, endTime: close, daysOfWeek: days),
      DayPart(id: _nextId(), name: 'Post-Close', startTime: close, endTime: postClose, daysOfWeek: days),
    ];
  }
}
