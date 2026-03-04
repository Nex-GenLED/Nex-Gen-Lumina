import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/sport_type.dart';
import 'espn_api_service.dart';

/// Fetches upcoming game schedules from ESPN to determine when to wake
/// the background polling service.
class GameScheduleService {
  GameScheduleService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Returns the next game [DateTime] for the team identified by
  /// [espnTeamId] in the given [sport].
  ///
  /// Looks up to 14 days ahead. Returns `null` if no upcoming games
  /// are found or on network error.
  Future<DateTime?> fetchNextGameDate(
    String espnTeamId,
    SportType sport,
  ) async {
    // ESPN team schedule endpoint returns upcoming events for a team.
    final url = '$kEspnBaseUrl/${sport.espnSportPath}'
        '/teams/$espnTeamId/schedule';

    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
          '[GameSchedule] HTTP ${response.statusCode} for $url',
        );
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final events = json['events'] as List<dynamic>?;
      if (events == null || events.isEmpty) return null;

      final now = DateTime.now();
      final cutoff = now.add(const Duration(days: 14));

      for (final event in events) {
        final dateStr = (event as Map<String, dynamic>)['date']?.toString();
        if (dateStr == null) continue;

        final gameDate = DateTime.tryParse(dateStr);
        if (gameDate == null) continue;

        // Only consider future games within 14-day window.
        if (gameDate.isAfter(now) && gameDate.isBefore(cutoff)) {
          return gameDate;
        }
      }

      return null;
    } catch (e) {
      debugPrint('[GameSchedule] Error fetching schedule: $e');
      return null;
    }
  }

  /// Check whether any tracked team has a game starting within [minutes]
  /// from now.
  Future<bool> hasGameSoon(
    String espnTeamId,
    SportType sport, {
    int minutes = 30,
  }) async {
    final nextGame = await fetchNextGameDate(espnTeamId, sport);
    if (nextGame == null) return false;

    final diff = nextGame.difference(DateTime.now());
    return diff.inMinutes <= minutes && diff.inMinutes >= -120;
  }

  void dispose() {
    _client.close();
  }
}
