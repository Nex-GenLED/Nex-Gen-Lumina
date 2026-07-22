// Time-aware header word for the dashboard upcoming-schedule card
// (BUG-SCHED-UX-3).
//
// The card used to hardcode "TONIGHT", so a morning event (e.g. an 11:40 AM
// schedule) still read "TONIGHT". The header now follows the shown event's ON
// time: morning/afternoon → "TODAY", evening/night → "TONIGHT". This fixes the
// selection of the label, not the copy.

/// Local hour at/after which the upcoming event is labeled "TONIGHT" rather
/// than "TODAY". Tunable.
const int kEveningLabelThresholdHour = 17; // 5 PM

/// Coarse hours used to classify solar tokens into morning vs evening for the
/// header word only.
const int kSolarSunriseHour = 6;
const int kSolarSunsetHour = 19;

/// Returns 'TODAY' or 'TONIGHT' for the upcoming-schedule header, from the shown
/// event's [onTimeLabel]. Accepts solar tokens ('Sunset'/'Sunrise'), 12-hour
/// ('7:00 PM') and 24-hour ('19:30') labels. When the label is null or
/// unparseable (e.g. no schedule yet), falls back to the current time of day so
/// the header still reads sensibly.
String upcomingScheduleHeaderLabel(String? onTimeLabel, DateTime now) {
  final hour = _labelHour(onTimeLabel) ?? now.hour;
  return hour < kEveningLabelThresholdHour ? 'TODAY' : 'TONIGHT';
}

/// The local hour a time label resolves to, or null if unparseable.
int? _labelHour(String? label) {
  if (label == null) return null;
  final l = label.trim().toLowerCase();
  if (l.isEmpty) return null;
  if (l == 'sunrise') return kSolarSunriseHour;
  if (l == 'sunset') return kSolarSunsetHour;

  final ampm = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$').firstMatch(l);
  if (ampm != null) {
    var h = int.parse(ampm.group(1)!);
    final pm = ampm.group(3) == 'pm';
    if (h < 1 || h > 12) return null;
    if (h == 12) h = 0;
    if (pm) h += 12;
    return h;
  }

  final h24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(l);
  if (h24 != null) {
    final h = int.parse(h24.group(1)!);
    return h <= 23 ? h : null;
  }
  return null;
}
