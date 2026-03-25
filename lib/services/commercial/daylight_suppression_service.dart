import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sunrise/sunset window for a single calendar day.
class DaylightWindow {
  final DateTime sunrise;
  final DateTime sunset;
  final DateTime fetchedDate;

  const DaylightWindow({
    required this.sunrise,
    required this.sunset,
    required this.fetchedDate,
  });

  /// Whether the current moment falls between sunrise and sunset.
  bool isDaylightHours() {
    final now = DateTime.now();
    return now.isAfter(sunrise) && now.isBefore(sunset);
  }
}

/// Fetches sunrise/sunset data from the Open-Meteo API and caches the result
/// for the calendar day. Does not re-fetch until the date rolls over.
class DaylightSuppressionService {
  final http.Client _client;

  DaylightWindow? _cached;

  DaylightSuppressionService({http.Client? client})
      : _client = client ?? http.Client();

  /// Returns the current [DaylightWindow] for the given coordinates.
  /// Caches results per calendar day — only fetches once per day.
  Future<DaylightWindow?> getDaylightWindow(double lat, double lng) async {
    final today = DateTime.now();

    // Return cached value if it was fetched today.
    if (_cached != null &&
        _cached!.fetchedDate.year == today.year &&
        _cached!.fetchedDate.month == today.month &&
        _cached!.fetchedDate.day == today.day) {
      return _cached;
    }

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat'
        '&longitude=$lng'
        '&daily=sunrise,sunset'
        '&timezone=auto'
        '&forecast_days=1',
      );

      final response = await _client.get(uri).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode != 200) {
        debugPrint(
            'DaylightSuppressionService: API returned ${response.statusCode}');
        return _cached; // stale is better than nothing
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final daily = json['daily'] as Map<String, dynamic>?;
      if (daily == null) return _cached;

      final sunriseList = daily['sunrise'] as List?;
      final sunsetList = daily['sunset'] as List?;
      if (sunriseList == null ||
          sunriseList.isEmpty ||
          sunsetList == null ||
          sunsetList.isEmpty) {
        return _cached;
      }

      final sunrise = DateTime.parse(sunriseList[0] as String);
      final sunset = DateTime.parse(sunsetList[0] as String);

      _cached = DaylightWindow(
        sunrise: sunrise,
        sunset: sunset,
        fetchedDate: today,
      );
      return _cached;
    } catch (e) {
      debugPrint('DaylightSuppressionService: fetch error: $e');
      return _cached; // return stale cache on error
    }
  }

  /// Convenience: is it currently daylight at the given coordinates?
  /// Returns false if no data is available (fail-open: lights stay on).
  Future<bool> isDaylightHours(double lat, double lng) async {
    final window = await getDaylightWindow(lat, lng);
    return window?.isDaylightHours() ?? false;
  }

  /// Clear the day cache (useful for testing or forced refresh).
  void clearCache() {
    _cached = null;
  }
}
