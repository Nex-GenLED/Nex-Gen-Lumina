import 'dart:math';

/// Simple solar calculations for sunrise/sunset times.
/// Returns local times based on [date] (local) and [latitude]/[longitude].
/// Algorithm adapted from NOAA Solar Calculator (approximate, civil sunset, elevation 90.833 degrees).
class SunUtils {
  /// Calculate local sunrise time for a given date and lat/lon.
  /// Returns null if calculation is not possible at this latitude/date.
  static DateTime? sunriseLocal(double latitude, double longitude, DateTime date) {
    try {
      final DateTime day = DateTime(date.year, date.month, date.day);
      final tzOffsetHours = day.timeZoneOffset.inMinutes / 60.0;

      final n1 = (275 * day.month / 9).floor();
      final n2 = ((day.month + 9) / 12).floor();
      final n3 = (1 + ((day.year - 4 * (day.year / 4).floor() + 2) / 3)).floor();
      final N = n1 - (n2 * n3) + day.day - 30;

      final double lngHour = longitude / 15.0;
      double t = N + ((6 - lngHour) / 24); // approximate time for sunrise

      double M = (0.9856 * t) - 3.289;
      double L = M + (1.916 * sin(_deg2rad(M))) + (0.020 * sin(_deg2rad(2 * M))) + 282.634;
      L = _normalizeDegrees(L);

      double RA = _rad2deg(atan(0.91764 * tan(_deg2rad(L))));
      RA = _normalizeDegrees(RA);
      double Lquadrant = (L / 90.0).floor() * 90.0;
      double RAquadrant = (RA / 90.0).floor() * 90.0;
      RA = RA + (Lquadrant - RAquadrant);
      RA = RA / 15.0;

      double sinDec = 0.39782 * sin(_deg2rad(L));
      double cosDec = cos(asin(sinDec));

      double cosH = (cos(_deg2rad(90.833)) - (sinDec * sin(_deg2rad(latitude)))) / (cosDec * cos(_deg2rad(latitude)));
      if (cosH < -1 || cosH > 1) return null;

      double H = 360.0 - _rad2deg(acos(cosH));
      H = H / 15.0;

      double T = H + RA - (0.06571 * t) - 6.622;
      double UT = T - lngHour;
      UT = _normalizeHours(UT);

      final double localT = UT + tzOffsetHours;
      final int hour = localT.floor();
      final int minute = ((localT - hour) * 60).round();
      return DateTime(day.year, day.month, day.day, hour, minute);
    } catch (_) {
      return null;
    }
  }
  static DateTime? sunsetLocal(double latitude, double longitude, DateTime date) {
    try {
      // Convert to UTC midnight
      final DateTime day = DateTime(date.year, date.month, date.day);
      final tzOffsetHours = day.timeZoneOffset.inMinutes / 60.0;

      final n1 = (275 * day.month / 9).floor();
      final n2 = ((day.month + 9) / 12).floor();
      final n3 = (1 + ((day.year - 4 * (day.year / 4).floor() + 2) / 3)).floor();
      final N = n1 - (n2 * n3) + day.day - 30; // day of year approx.

      double lngHour = longitude / 15.0;
      double t = N + ((18 - lngHour) / 24); // approximate time for sunset

      double M = (0.9856 * t) - 3.289; // Sun's mean anomaly
      double L = M + (1.916 * sin(_deg2rad(M))) + (0.020 * sin(_deg2rad(2 * M))) + 282.634;
      L = _normalizeDegrees(L);

      double RA = _rad2deg(atan(0.91764 * tan(_deg2rad(L))));
      RA = _normalizeDegrees(RA);
      // Quadrant adjustment
      double Lquadrant = (L / 90.0).floor() * 90.0;
      double RAquadrant = (RA / 90.0).floor() * 90.0;
      RA = RA + (Lquadrant - RAquadrant);
      RA = RA / 15.0; // convert to hours

      double sinDec = 0.39782 * sin(_deg2rad(L));
      double cosDec = cos(asin(sinDec));

      double cosH = (cos(_deg2rad(90.833)) - (sinDec * sin(_deg2rad(latitude)))) / (cosDec * cos(_deg2rad(latitude)));
      if (cosH < -1 || cosH > 1) return null; // no sunset/sunrise on this date at this lat

      double H = _rad2deg(acos(cosH));
      H = H / 15.0; // hours

      double T = H + RA - (0.06571 * t) - 6.622;
      double UT = T - lngHour;
      UT = _normalizeHours(UT);

      final double localT = UT + tzOffsetHours;
      final int hour = localT.floor();
      final int minute = ((localT - hour) * 60).round();
      return DateTime(day.year, day.month, day.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  static double _deg2rad(double deg) => deg * pi / 180.0;
  static double _rad2deg(double rad) => rad * 180.0 / pi;
  static double _normalizeDegrees(double deg) {
    double d = deg % 360.0;
    if (d < 0) d += 360.0;
    return d;
    }
  static double _normalizeHours(double h) {
    double hh = h % 24.0;
    if (hh < 0) hh += 24.0;
    return hh;
  }
}

/// Returns a list of 7 percentages (0..1) for Sun..Sat representing how much
/// of the night (Sunset->Sunrise) is covered by the configured schedule.
///
/// mode:
/// - 'dusk_to_dawn' => 100% each day
/// - 'sunset_to_time' => from sunset to [fixedHour]:00 local time
///
/// If sunrise/sunset can't be computed, falls back to 0.
List<double> calculateNightSchedule({
  required double latitude,
  required double longitude,
  String mode = 'sunset_to_time',
  int fixedHour = 22,
  DateTime? weekAnchor,
}) {
  final now = weekAnchor ?? DateTime.now();
  // Compute the Sunday of the current week
  // DateTime.weekday: Mon=1..Sun=7, we want Sunday index 0
  final int daysFromSunday = now.weekday % 7; // Sun->0, Mon->1, ...
  final DateTime sunday = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysFromSunday));

  double computeFor(DateTime date) {
    if (mode == 'dusk_to_dawn') return 1.0;

    final sunset = SunUtils.sunsetLocal(latitude, longitude, date);
    final nextDay = date.add(const Duration(days: 1));
    final sunrise = SunUtils.sunriseLocal(latitude, longitude, nextDay);

    if (sunset == null || sunrise == null) return 0.0;

    final DateTime end = DateTime(date.year, date.month, date.day, fixedHour, 0);
    if (end.isBefore(sunset)) return 0.0;

    final totalNight = sunrise.difference(sunset).inMinutes;
    if (totalNight <= 0) return 0.0;

    final coveredEnd = end.isAfter(sunrise) ? sunrise : end;
    final covered = coveredEnd.difference(sunset).inMinutes;
    final pct = covered / totalNight;
    return pct.clamp(0.0, 1.0);
  }

  return List.generate(7, (i) => computeFor(sunday.add(Duration(days: i))));
}
