// lib/features/wled/wled_dow.dart
//
// Canonical helper for translating a weekday to the bit value WLED
// firmware expects in cfg.timers.ins[].dow.
//
// WLED CONVENTION (verified empirically against firmware 0.14+ on
// 2026-05-19 via cfg.timers readback): WLED's dow bitmask uses
// Monday=bit 0 through Sunday=bit 6.
//
//   Monday    = 1   (1 << 0)
//   Tuesday   = 2   (1 << 1)
//   Wednesday = 4   (1 << 2)
//   Thursday  = 8   (1 << 3)
//   Friday    = 16  (1 << 4)
//   Saturday  = 32  (1 << 5)
//   Sunday    = 64  (1 << 6)
//   Daily     = 127 (all bits)
//
// PRIOR BUG: Lumina previously assumed Sun=bit 0 based on out-of-date
// WLED documentation. This caused every non-Daily schedule to fire
// one weekday LATER than the user intended (Monday schedules fired
// on Tuesday, etc). Bug existed in two places (_computeDowMask in
// schedule_sync.dart and _singleDateDowMask in
// calendar_entry_lease_manager.dart). Fixed and centralized here on
// 2026-05-19 per Item #72.
//
// Daily masks (127) worked under both conventions because all bits
// are set, which is why this went undetected in production for
// months — most dealer schedules are Daily.
library;

/// WLED bit values per weekday. Public so tests can reference
/// symbolically — never hardcode the integers in callers or tests.
const int kWledDowMonday = 1;
const int kWledDowTuesday = 2;
const int kWledDowWednesday = 4;
const int kWledDowThursday = 8;
const int kWledDowFriday = 16;
const int kWledDowSaturday = 32;
const int kWledDowSunday = 64;
const int kWledDowDaily = 127;

/// Convert a Dart `DateTime.weekday` (1=Mon..7=Sun) to the WLED dow
/// bit value. Returns 0 for any out-of-range input.
int wledDowMaskForWeekday(int dartWeekday) {
  switch (dartWeekday) {
    case DateTime.monday:
      return kWledDowMonday;
    case DateTime.tuesday:
      return kWledDowTuesday;
    case DateTime.wednesday:
      return kWledDowWednesday;
    case DateTime.thursday:
      return kWledDowThursday;
    case DateTime.friday:
      return kWledDowFriday;
    case DateTime.saturday:
      return kWledDowSaturday;
    case DateTime.sunday:
      return kWledDowSunday;
    default:
      return 0;
  }
}

/// Convert a weekday name to the WLED dow bit value. Accepts full
/// names ("Monday") or three-letter prefixes ("Mon", "Tue"). Returns
/// 0 for "daily" callers — use [kWledDowDaily] directly — or any
/// unrecognized input.
int wledDowMaskForDayName(String day) {
  final d = day.toLowerCase().trim();
  if (d == 'monday' || d == 'mon') return kWledDowMonday;
  if (d == 'tuesday' || d == 'tue' || d == 'tues') return kWledDowTuesday;
  if (d == 'wednesday' || d == 'wed') return kWledDowWednesday;
  if (d == 'thursday' || d == 'thu' || d == 'thurs') return kWledDowThursday;
  if (d == 'friday' || d == 'fri') return kWledDowFriday;
  if (d == 'saturday' || d == 'sat') return kWledDowSaturday;
  if (d == 'sunday' || d == 'sun') return kWledDowSunday;
  return 0;
}

/// Build a WLED dow bitmask from a list of day names. Returns
/// [kWledDowDaily] when any element contains "daily" (case-insensitive,
/// substring). Otherwise OR-s the bits for each recognized day name.
int wledDowMaskForDayList(List<String> days) {
  if (days.any((d) => d.toLowerCase().contains('daily'))) {
    return kWledDowDaily;
  }
  int mask = 0;
  for (final d in days) {
    mask |= wledDowMaskForDayName(d);
  }
  return mask;
}
