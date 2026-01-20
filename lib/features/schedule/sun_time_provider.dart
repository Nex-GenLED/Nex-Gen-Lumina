import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/utils/sun_utils.dart';

/// Simple struct-like holder for formatted sunrise/sunset strings.
class SunTimeStrings {
  final String sunriseLabel; // e.g., "Sunrise (6:44 AM)"
  final String sunsetLabel;  // e.g., "Sunset (8:14 PM)"
  const SunTimeStrings({required this.sunriseLabel, required this.sunsetLabel});
}

/// Lightweight formatter to render local times in a user-friendly 12-hour format.
class SunTimeFormatter {
  static String _two(int v) => v < 10 ? '0$v' : '$v';

  /// Formats a DateTime to h:mm AM/PM (e.g., 8:14 PM) using local time.
  static String format12h(DateTime dt) {
    final local = dt.toLocal();
    int hour = local.hour % 12;
    if (hour == 0) hour = 12;
    final minute = _two(local.minute);
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $ampm';
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
    final now = DateTime.now();
    final sunset = SunUtils.sunsetLocal(coords.lat, coords.lon, now);
    final sunrise = SunUtils.sunriseLocal(coords.lat, coords.lon, now);

    String sunsetStr = 'Sunset (—)';
    String sunriseStr = 'Sunrise (—)';

    if (sunset != null) {
      sunsetStr = 'Sunset (${SunTimeFormatter.format12h(sunset)})';
    }
    if (sunrise != null) {
      sunriseStr = 'Sunrise (${SunTimeFormatter.format12h(sunrise)})';
    }

    return SunTimeStrings(sunriseLabel: sunriseStr, sunsetLabel: sunsetStr);
  } catch (e) {
    debugPrint('sunTimeProvider: failed to compute sun times: $e');
    return const SunTimeStrings(sunriseLabel: 'Sunrise (—)', sunsetLabel: 'Sunset (—)');
  }
});
