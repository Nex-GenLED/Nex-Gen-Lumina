import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_event.dart';
import '../models/game_state.dart';
import '../models/sport_type.dart';
import 'espn_api_service.dart';

/// SharedPreferences key prefix for cached season schedules.
const _kSeasonCachePrefix = 'season_schedule_cache_';
const _kSeasonCacheTimestampPrefix = 'season_schedule_ts_';

/// Default cache TTL for season schedules: 24 hours.
const _kSeasonCacheTtl = Duration(hours: 24);

/// Tournament schedules (FIFA World Cup, Champions League) change more
/// frequently near match days — use a shorter 6-hour TTL.
const _kTournamentCacheTtl = Duration(hours: 6);

/// Returns the appropriate cache TTL for a given sport.
Duration _cacheTtlForSport(SportType sport) {
  if (sport.isSoccer && sport != SportType.mls) {
    return _kTournamentCacheTtl;
  }
  // NCAA tournament schedules change frequently during March Madness / bowls
  if (sport == SportType.ncaaMB || sport == SportType.ncaaFB) {
    return _kTournamentCacheTtl;
  }
  return _kSeasonCacheTtl;
}

/// Fetches upcoming game schedules from ESPN to determine when to wake
/// the background polling service.
class GameScheduleService {
  GameScheduleService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// In-memory cache for season schedules (avoids repeated disk reads).
  final Map<String, _CachedSeasonSchedule> _memoryCache = {};

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

  // ─────────────────────────────────────────────────────────────────────────
  // Season Schedule API
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch the full season schedule for a team.
  ///
  /// Returns a list of [GameEvent]s for the given [season] year.
  /// Results are cached for 24 hours (SharedPreferences + in-memory).
  ///
  /// If [homeGamesOnly] is true (default), only home games are returned.
  /// The ESPN API endpoint used:
  ///   `site.api.espn.com/apis/site/v2/sports/{sport}/teams/{teamId}/schedule?season={year}`
  Future<List<GameEvent>> fetchSeasonSchedule({
    required String espnTeamId,
    required SportType sport,
    required int season,
    bool homeGamesOnly = true,
  }) async {
    final cacheKey = '${sport.name}_${espnTeamId}_$season';

    // 1. Check in-memory cache
    final memCached = _memoryCache[cacheKey];
    if (memCached != null && !memCached.isExpired) {
      debugPrint('[GameSchedule] Memory cache hit for $cacheKey');
      return homeGamesOnly
          ? memCached.games.where((g) => g.isHome).toList()
          : memCached.games;
    }

    // 2. Check SharedPreferences cache
    final diskCached = await _loadFromDiskCache(cacheKey, sport);
    if (diskCached != null) {
      _memoryCache[cacheKey] = diskCached;
      debugPrint('[GameSchedule] Disk cache hit for $cacheKey');
      return homeGamesOnly
          ? diskCached.games.where((g) => g.isHome).toList()
          : diskCached.games;
    }

    // 3. Fetch from ESPN API
    debugPrint('[GameSchedule] Fetching season schedule for $cacheKey');
    final games = await _fetchFromEspn(espnTeamId, sport, season);
    if (games.isNotEmpty) {
      final cached = _CachedSeasonSchedule(
        games: games,
        fetchedAt: DateTime.now(),
        sport: sport,
      );
      _memoryCache[cacheKey] = cached;
      await _saveToDiskCache(cacheKey, cached);
    }

    return homeGamesOnly
        ? games.where((g) => g.isHome).toList()
        : games;
  }

  /// Compare a previously cached schedule with the latest from ESPN.
  /// Returns a [ScheduleDiff] describing added, removed, and rescheduled games.
  Future<ScheduleDiff> diffSeasonSchedule({
    required String espnTeamId,
    required SportType sport,
    required int season,
    required List<GameEvent> previousGames,
  }) async {
    // Force a fresh fetch by clearing the cache for this key
    final cacheKey = '${sport.name}_${espnTeamId}_$season';
    _memoryCache.remove(cacheKey);
    await _clearDiskCache(cacheKey);

    final latestGames = await fetchSeasonSchedule(
      espnTeamId: espnTeamId,
      sport: sport,
      season: season,
      homeGamesOnly: false,
    );

    final previousIds = {for (final g in previousGames) g.gameId};
    final latestIds = {for (final g in latestGames) g.gameId};
    final latestById = {for (final g in latestGames) g.gameId: g};
    final previousById = {for (final g in previousGames) g.gameId: g};

    final added = latestGames
        .where((g) => !previousIds.contains(g.gameId))
        .toList();

    final removed = previousGames
        .where((g) => !latestIds.contains(g.gameId))
        .toList();

    final rescheduled = <RescheduledGame>[];
    for (final gameId in previousIds.intersection(latestIds)) {
      final prev = previousById[gameId]!;
      final curr = latestById[gameId]!;
      final timeDiff = curr.scheduledDate.difference(prev.scheduledDate).abs();
      // Treat as rescheduled if time changed by more than 5 minutes
      if (timeDiff.inMinutes > 5) {
        rescheduled.add(RescheduledGame(
          gameId: gameId,
          oldDate: prev.scheduledDate,
          newDate: curr.scheduledDate,
          opponent: curr.isHome ? curr.awayTeam : curr.homeTeam,
        ));
      }
    }

    return ScheduleDiff(
      added: added,
      removed: removed,
      rescheduled: rescheduled,
      hasChanges:
          added.isNotEmpty || removed.isNotEmpty || rescheduled.isNotEmpty,
    );
  }

  /// Invalidate the cache for a specific team/season.
  Future<void> invalidateCache({
    required String espnTeamId,
    required SportType sport,
    required int season,
  }) async {
    final cacheKey = '${sport.name}_${espnTeamId}_$season';
    _memoryCache.remove(cacheKey);
    await _clearDiskCache(cacheKey);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ESPN API Fetch
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<GameEvent>> _fetchFromEspn(
    String espnTeamId,
    SportType sport,
    int season,
  ) async {
    final groups = sport.espnGroupsParam;
    final groupsQuery = groups != null ? '&groups=$groups' : '';
    final url = '$kEspnBaseUrl/${sport.espnSportPath}'
        '/teams/$espnTeamId/schedule?season=$season$groupsQuery';

    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('[GameSchedule] HTTP ${response.statusCode} for $url');
        return const [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final events = json['events'] as List<dynamic>?;
      if (events == null || events.isEmpty) return const [];

      final games = <GameEvent>[];
      for (final event in events) {
        final game = _parseScheduleEvent(
          event as Map<String, dynamic>,
          espnTeamId,
          sport,
          season,
        );
        if (game != null) games.add(game);
      }

      // Sort by date
      games.sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

      debugPrint('[GameSchedule] Parsed ${games.length} games for season $season');
      return games;
    } catch (e) {
      debugPrint('[GameSchedule] Error fetching season schedule: $e');
      return const [];
    }
  }

  GameEvent? _parseScheduleEvent(
    Map<String, dynamic> event,
    String queriedTeamId,
    SportType sport,
    int season,
  ) {
    try {
      final gameId = event['id']?.toString() ?? '';
      final dateStr = event['date']?.toString();
      if (dateStr == null) return null;
      final scheduledDate = DateTime.tryParse(dateStr);
      if (scheduledDate == null) return null;

      final competitions = event['competitions'] as List<dynamic>?;
      if (competitions == null || competitions.isEmpty) return null;

      final competition = competitions[0] as Map<String, dynamic>;
      final competitors = competition['competitors'] as List<dynamic>?;
      if (competitors == null || competitors.length < 2) return null;

      Map<String, dynamic>? home;
      Map<String, dynamic>? away;
      for (final c in competitors) {
        final comp = c as Map<String, dynamic>;
        if (comp['homeAway'] == 'home') {
          home = comp;
        } else {
          away = comp;
        }
      }
      if (home == null || away == null) return null;

      final homeTeamId = _extractTeamId(home);
      final awayTeamId = _extractTeamId(away);
      final homeTeamName = _extractTeamName(home);
      final awayTeamName = _extractTeamName(away);

      // Determine if this is a home game for the queried team
      final isHome = homeTeamId == queriedTeamId;

      // Parse venue
      final venueData = competition['venue'] as Map<String, dynamic>?;
      final venue = venueData?['fullName']?.toString();

      // Parse status
      final statusMap = competition['status'] as Map<String, dynamic>?;
      final statusType = statusMap?['type'] as Map<String, dynamic>?;
      final statusName = statusType?['name']?.toString() ?? '';
      final gameStatus = _mapEspnStatus(statusName);

      return GameEvent(
        gameId: gameId,
        homeTeam: homeTeamName,
        awayTeam: awayTeamName,
        homeTeamId: homeTeamId,
        awayTeamId: awayTeamId,
        scheduledDate: scheduledDate,
        isHome: isHome,
        sport: sport,
        season: season,
        venue: venue,
        status: gameStatus,
      );
    } catch (e) {
      debugPrint('[GameSchedule] Error parsing schedule event: $e');
      return null;
    }
  }

  static String _extractTeamName(Map<String, dynamic> competitor) {
    final team = competitor['team'] as Map<String, dynamic>?;
    return team?['displayName']?.toString() ??
        team?['shortDisplayName']?.toString() ??
        team?['abbreviation']?.toString() ??
        'Unknown';
  }

  static String _extractTeamId(Map<String, dynamic> competitor) {
    final team = competitor['team'] as Map<String, dynamic>?;
    return team?['id']?.toString() ?? '';
  }

  static GameStatus _mapEspnStatus(String espnStatus) => switch (espnStatus) {
        'STATUS_IN_PROGRESS' => GameStatus.inProgress,
        'STATUS_HALFTIME' => GameStatus.halftime,
        'STATUS_FINAL' || 'STATUS_FINAL_OT' => GameStatus.final_,
        _ => GameStatus.scheduled,
      };

  // ─────────────────────────────────────────────────────────────────────────
  // Disk Cache (SharedPreferences)
  // ─────────────────────────────────────────────────────────────────────────

  Future<_CachedSeasonSchedule?> _loadFromDiskCache(
    String cacheKey,
    SportType sport,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tsStr = prefs.getString('$_kSeasonCacheTimestampPrefix$cacheKey');
      if (tsStr == null) return null;

      final fetchedAt = DateTime.tryParse(tsStr);
      if (fetchedAt == null) return null;

      // Check TTL (tournament schedules use shorter 6h TTL)
      if (DateTime.now().difference(fetchedAt) > _cacheTtlForSport(sport)) {
        debugPrint('[GameSchedule] Disk cache expired for $cacheKey');
        return null;
      }

      final dataStr = prefs.getString('$_kSeasonCachePrefix$cacheKey');
      if (dataStr == null) return null;

      final list = jsonDecode(dataStr) as List<dynamic>;
      final games = list
          .map((e) => GameEvent.fromJson(e as Map<String, dynamic>))
          .toList();

      return _CachedSeasonSchedule(
        games: games,
        fetchedAt: fetchedAt,
        sport: sport,
      );
    } catch (e) {
      debugPrint('[GameSchedule] Error reading disk cache: $e');
      return null;
    }
  }

  Future<void> _saveToDiskCache(
    String cacheKey,
    _CachedSeasonSchedule cached,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataStr = jsonEncode(cached.games.map((g) => g.toJson()).toList());
      await prefs.setString('$_kSeasonCachePrefix$cacheKey', dataStr);
      await prefs.setString(
        '$_kSeasonCacheTimestampPrefix$cacheKey',
        cached.fetchedAt.toIso8601String(),
      );
    } catch (e) {
      debugPrint('[GameSchedule] Error writing disk cache: $e');
    }
  }

  Future<void> _clearDiskCache(String cacheKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_kSeasonCachePrefix$cacheKey');
      await prefs.remove('$_kSeasonCacheTimestampPrefix$cacheKey');
    } catch (e) {
      debugPrint('[GameSchedule] Error clearing disk cache: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NCAA Season Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Determine the correct ESPN season year for NCAA sports.
  ///
  /// NCAA football: season year = year the season starts (fall).
  ///   e.g. the 2025-26 bowl season → season=2025.
  /// NCAA basketball: season year = year the season ends (spring).
  ///   e.g. the 2025-26 season (March Madness in 2026) → season=2026.
  static int ncaaSeasonYear(SportType sport, [DateTime? now]) {
    final date = now ?? DateTime.now();
    if (sport == SportType.ncaaFB) {
      // Football: if we're in Jan-Feb watching bowl games, use previous year
      return date.month <= 2 ? date.year - 1 : date.year;
    }
    if (sport == SportType.ncaaMB) {
      // Basketball: season spans Nov-Apr, ESPN keys on ending year
      return date.month >= 11 ? date.year + 1 : date.year;
    }
    return date.year;
  }

  /// Whether March Madness is currently active (mid-March through early April).
  static bool isMarchMadnessWindow([DateTime? now]) {
    final date = now ?? DateTime.now();
    // Selection Sunday is typically mid-March; Final Four is first week of April
    return (date.month == 3 && date.day >= 14) ||
        (date.month == 4 && date.day <= 8);
  }

  /// Whether the college football bowl / CFP season is active
  /// (mid-December through mid-January).
  static bool isBowlSeasonWindow([DateTime? now]) {
    final date = now ?? DateTime.now();
    return (date.month == 12 && date.day >= 14) ||
        (date.month == 1 && date.day <= 20);
  }

  void dispose() {
    _client.close();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Cache & Diff Models
// ═════════════════════════════════════════════════════════════════════════════

class _CachedSeasonSchedule {
  final List<GameEvent> games;
  final DateTime fetchedAt;
  final SportType sport;

  const _CachedSeasonSchedule({
    required this.games,
    required this.fetchedAt,
    required this.sport,
  });

  bool get isExpired =>
      DateTime.now().difference(fetchedAt) > _cacheTtlForSport(sport);
}

/// Describes changes between two season schedule snapshots.
class ScheduleDiff {
  /// Games that were added since the last check.
  final List<GameEvent> added;

  /// Games that were removed since the last check.
  final List<GameEvent> removed;

  /// Games whose scheduled time changed.
  final List<RescheduledGame> rescheduled;

  /// Whether any changes were detected.
  final bool hasChanges;

  const ScheduleDiff({
    this.added = const [],
    this.removed = const [],
    this.rescheduled = const [],
    this.hasChanges = false,
  });
}

/// A game whose schedule date changed.
class RescheduledGame {
  final String gameId;
  final DateTime oldDate;
  final DateTime newDate;
  final String opponent;

  const RescheduledGame({
    required this.gameId,
    required this.oldDate,
    required this.newDate,
    required this.opponent,
  });
}
