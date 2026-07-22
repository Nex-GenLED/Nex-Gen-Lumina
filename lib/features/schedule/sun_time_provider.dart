import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/utils/sun_utils.dart';
import 'package:nexgen_command/utils/time_format.dart';

/// Simple struct-like holder for formatted sunrise/sunset strings.
class SunTimeStrings {
  final String sunriseLabel; // e.g., "Sunrise (6:44 AM)"
  final String sunsetLabel;  // e.g., "Sunset (8:14 PM)"
  const SunTimeStrings({required this.sunriseLabel, required this.sunsetLabel});
}

/// Lightweight formatter to render local times using the user's preferred format.
class SunTimeFormatter {
  /// Formats a DateTime to h:mm AM/PM (12h) or HH:mm (24h) using local time.
  static String format12h(DateTime dt, {String timeFormat = kTimeFormatDefault}) {
    return formatTime(dt, timeFormat: timeFormat);
  }
}

/// Riverpod provider that computes today's sunrise and sunset for given coordinates
/// and returns them as formatted strings, e.g., "Sunset (8:14 PM)".
///
/// Usage:
///   final res = ref.watch(sunTimeProvider((lat: 37.7749, lon: -122.4194)));
///   res.when(
///     data: (s) => Text(s.sunsetLabel),
///     loading: () => const CircularProgressIndicator(),
///     error: (e, st) => Text('Failed to load sun times'),
///   );
final sunTimeProvider = FutureProvider.family<SunTimeStrings, ({double lat, double lon})>((ref, coords) async {
  try {
    final timeFormat = ref.watch(timeFormatPreferenceProvider);
    final now = DateTime.now();
    final sunset = SunUtils.sunsetLocal(coords.lat, coords.lon, now);
    final sunrise = SunUtils.sunriseLocal(coords.lat, coords.lon, now);

    String sunsetStr = 'Sunset (—)';
    String sunriseStr = 'Sunrise (—)';

    if (sunset != null) {
      sunsetStr = 'Sunset (${SunTimeFormatter.format12h(sunset, timeFormat: timeFormat)})';
    }
    if (sunrise != null) {
      sunriseStr = 'Sunrise (${SunTimeFormatter.format12h(sunrise, timeFormat: timeFormat)})';
    }

    return SunTimeStrings(sunriseLabel: sunriseStr, sunsetLabel: sunsetStr);
  } catch (e) {
    debugPrint('sunTimeProvider: failed to compute sun times: $e');
    return const SunTimeStrings(sunriseLabel: 'Sunrise (—)', sunsetLabel: 'Sunset (—)');
  }
});
