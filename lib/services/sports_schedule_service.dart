import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Represents a sports game.
class SportsGame {
  /// Name of the user's team.
  final String teamName;

  /// Name of the opponent.
  final String opponent;

  /// Date and time of the game.
  final DateTime gameTime;

  /// Whether this is a home game.
  final bool isHomeGame;

  /// League identifier (NFL, NBA, MLB, NHL, MLS, WNBA, NWSL, NCAA).
  final String league;

  /// Optional venue name.
  final String? venue;

  const SportsGame({
    required this.teamName,
    required this.opponent,
    required this.gameTime,
    required this.isHomeGame,
    required this.league,
    this.venue,
  });

  @override
  String toString() =>
      'SportsGame($teamName vs $opponent, ${gameTime.month}/${gameTime.day} ${gameTime.hour}:${gameTime.minute.toString().padLeft(2, '0')})';
}

/// Service for fetching sports schedules.
///
/// This service provides sports game data for autopilot scheduling.
/// It can use either:
/// - A live sports API (when configured)
/// - Simulated game data (for development/demo - DISABLED by default)
///
/// Supported leagues: NFL, NBA, MLB, NHL, MLS, WNBA, NWSL, NCAA
///
/// IMPORTANT: Simulated data is disabled by default because it generates
/// fake games that don't reflect real schedules. Only enable for explicit
/// demo/testing purposes. In production, integrate a real sports API.
class SportsScheduleService {
  final Ref _ref;

  /// API key for sports data service (optional).
  /// Can be configured via environment or Firebase Remote Config.
  String? _apiKey;

  /// Whether to use simulated data instead of live API.
  /// DISABLED by default - simulated games create misleading suggestions.
  bool _useSimulatedData = false;

  SportsScheduleService(this._ref);

  /// Get upcoming games for the specified teams within a date range.
  ///
  /// Returns an empty list if:
  /// - No teams are specified
  /// - No API is configured and simulated mode is disabled
  /// - Team's league is in off-season
  Future<List<SportsGame>> getGamesInRange(
    List<String> teamNames,
    DateTime start,
    DateTime end,
  ) async {
    if (teamNames.isEmpty) return [];

    // If no API configured and simulation disabled, return empty
    // This prevents showing fake game suggestions to users
    if (_apiKey == null && !_useSimulatedData) {
      debugPrint('SportsScheduleService: No API configured, sports suggestions disabled');
      return [];
    }

    // For now, use simulated data
    // In production, this would call a sports API
    if (_useSimulatedData || _apiKey == null) {
      return _getSimulatedGames(teamNames, start, end);
    }

    return _fetchLiveGames(teamNames, start, end);
  }

  /// Get today's games for the specified teams.
  Future<List<SportsGame>> getTodaysGames(List<String> teamNames) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    return getGamesInRange(teamNames, start, end);
  }

  /// Get next game for a specific team.
  Future<SportsGame?> getNextGame(String teamName) async {
    final now = DateTime.now();
    final end = now.add(const Duration(days: 30)); // Look 30 days ahead

    final games = await getGamesInRange([teamName], now, end);
    return games.isNotEmpty ? games.first : null;
  }

  /// Determine the league for a team based on its name.
  String _detectLeague(String teamName) {
    // NFL teams
    const nflTeams = [
      'Chiefs', 'Bills', 'Ravens', 'Bengals', 'Browns', 'Steelers',
      'Texans', 'Colts', 'Jaguars', 'Titans', 'Broncos', 'Raiders',
      'Chargers', 'Cowboys', 'Giants', 'Eagles', 'Commanders', 'Bears',
      'Lions', 'Packers', 'Vikings', 'Falcons', 'Panthers', 'Saints',
      'Buccaneers', 'Cardinals', 'Rams', 'Seahawks', '49ers', 'Jets',
      'Patriots', 'Dolphins',
    ];

    // NBA teams
    const nbaTeams = [
      'Lakers', 'Celtics', 'Warriors', 'Heat', 'Bulls', 'Knicks',
      'Nets', 'Bucks', 'Nuggets', 'Suns', 'Mavericks', 'Clippers',
      'Thunder', 'Grizzlies', 'Pelicans', 'Hawks', 'Cavaliers', 'Magic',
      'Pistons', 'Pacers', 'Hornets', 'Wizards', 'Raptors', 'Spurs',
      'Kings', 'Timberwolves', 'Jazz', 'Trail Blazers', 'Rockets', '76ers',
    ];

    // MLB teams
    const mlbTeams = [
      'Yankees', 'Red Sox', 'Dodgers', 'Giants', 'Cubs', 'Cardinals',
      'Mets', 'Phillies', 'Braves', 'Astros', 'Rangers', 'Angels',
      'Padres', 'Mariners', 'Royals', 'Tigers', 'Twins', 'White Sox',
      'Guardians', 'Reds', 'Brewers', 'Pirates', 'Marlins', 'Nationals',
      'Rockies', 'Diamondbacks', 'Athletics', 'Rays', 'Blue Jays', 'Orioles',
    ];

    // NHL teams
    const nhlTeams = [
      'Bruins', 'Maple Leafs', 'Canadiens', 'Red Wings', 'Blackhawks',
      'Rangers', 'Flyers', 'Penguins', 'Capitals', 'Lightning', 'Panthers',
      'Hurricanes', 'Blue Jackets', 'Devils', 'Islanders', 'Sabres',
      'Senators', 'Oilers', 'Flames', 'Canucks', 'Avalanche', 'Stars',
      'Blues', 'Wild', 'Jets', 'Predators', 'Coyotes', 'Golden Knights',
      'Kraken', 'Sharks', 'Kings', 'Ducks',
    ];

    // MLS teams
    const mlsTeams = [
      'Sporting KC', 'LA Galaxy', 'LAFC', 'Seattle Sounders', 'Atlanta United',
      'Portland Timbers', 'Columbus Crew', 'Inter Miami', 'NYC FC',
      'Philadelphia Union', 'Nashville SC', 'Austin FC', 'FC Cincinnati',
      'St. Louis CITY SC', 'Charlotte FC', 'Houston Dynamo', 'Real Salt Lake',
      'Minnesota United', 'FC Dallas', 'Chicago Fire', 'New England Revolution',
      'Orlando City', 'DC United', 'Toronto FC', 'CF Montreal', 'Vancouver Whitecaps',
      'Colorado Rapids', 'San Jose Earthquakes',
    ];

    // WNBA teams
    const wnbaTeams = [
      'Sparks', 'Lynx', 'Storm', 'Sun', 'Aces', 'Mercury', 'Sky', 'Fever',
      'Wings', 'Mystics', 'Liberty', 'Dream', 'Caitlin Clark', 'Indiana Fever',
    ];

    // NWSL teams
    const nwslTeams = [
      'Kansas City Current', 'Portland Thorns', 'Orlando Pride', 'NC Courage',
      'Chicago Red Stars', 'Racing Louisville', 'Washington Spirit',
      'Gotham FC', 'Houston Dash', 'San Diego Wave', 'Angel City',
      'Seattle Reign', 'Utah Royals', 'Bay FC',
    ];

    final name = teamName.toLowerCase();

    if (nflTeams.any((t) => name.contains(t.toLowerCase()))) return 'NFL';
    if (nbaTeams.any((t) => name.contains(t.toLowerCase()))) return 'NBA';
    if (mlbTeams.any((t) => name.contains(t.toLowerCase()))) return 'MLB';
    if (nhlTeams.any((t) => name.contains(t.toLowerCase()))) return 'NHL';
    if (mlsTeams.any((t) => name.contains(t.toLowerCase()))) return 'MLS';
    if (wnbaTeams.any((t) => name.contains(t.toLowerCase()))) return 'WNBA';
    if (nwslTeams.any((t) => name.contains(t.toLowerCase()))) return 'NWSL';

    // Check for college keywords
    if (name.contains('jayhawks') ||
        name.contains('wildcats') ||
        name.contains('tigers') ||
        name.contains('crimson') ||
        name.contains('buckeyes') ||
        name.contains('wolverines') ||
        name.contains('bulldogs') ||
        name.contains('longhorns')) {
      return 'NCAA';
    }

    return 'Unknown';
  }

  /// Check if a league is currently in season.
  bool _isLeagueInSeason(String league, DateTime date) {
    final month = date.month;

    switch (league) {
      case 'NFL':
        // NFL: September through early February (Super Bowl)
        // Regular season: Sept-Dec, Playoffs: Jan, Super Bowl: early Feb
        return month >= 9 || month <= 2;
      case 'NBA':
        // NBA: October through June
        return month >= 10 || month <= 6;
      case 'MLB':
        // MLB: Late March through October (World Series)
        return month >= 3 && month <= 10;
      case 'NHL':
        // NHL: October through June
        return month >= 10 || month <= 6;
      case 'MLS':
        // MLS: Late February through December
        return month >= 2 && month <= 12;
      case 'WNBA':
        // WNBA: May through October
        return month >= 5 && month <= 10;
      case 'NWSL':
        // NWSL: March through November
        return month >= 3 && month <= 11;
      case 'NCAA':
        // NCAA varies by sport, most active Sept-March
        return month >= 9 || month <= 3;
      default:
        return false;
    }
  }

  /// Check if a league plays on a given day of week.
  bool _leaguePlaysOnDay(String league, int weekday) {
    switch (league) {
      case 'NFL':
        // NFL: Sunday (primary), Monday, Thursday, occasional Saturday
        return weekday == DateTime.sunday ||
               weekday == DateTime.monday ||
               weekday == DateTime.thursday ||
               weekday == DateTime.saturday;
      case 'NBA':
      case 'NHL':
        // NBA/NHL play most days during season
        return true;
      case 'MLB':
        // MLB plays almost every day during season
        return true;
      case 'MLS':
      case 'NWSL':
        // Soccer: primarily weekends, occasional weeknight
        return weekday == DateTime.saturday ||
               weekday == DateTime.sunday ||
               weekday == DateTime.wednesday;
      case 'WNBA':
        // WNBA plays several days a week
        return true;
      case 'NCAA':
        // College: weekends and some weeknights
        return weekday == DateTime.saturday ||
               weekday == DateTime.sunday ||
               weekday == DateTime.thursday ||
               weekday == DateTime.friday;
      default:
        return false;
    }
  }

  /// Generate simulated games for development/demo purposes.
  ///
  /// Creates realistic game schedules based on the current date and
  /// typical game patterns for each league.
  ///
  /// NOTE: This generates FAKE data and should only be used for testing.
  /// Simulated games respect:
  /// - League seasons (no NFL games in July, etc.)
  /// - Typical game days (NFL on Sundays, etc.)
  /// - Realistic game times
  List<SportsGame> _getSimulatedGames(
    List<String> teamNames,
    DateTime start,
    DateTime end,
  ) {
    final games = <SportsGame>[];
    final random = DateTime.now().millisecondsSinceEpoch;

    for (final teamName in teamNames) {
      final league = _detectLeague(teamName);

      // Skip if league is not in season
      if (!_isLeagueInSeason(league, start)) {
        debugPrint('SportsScheduleService: $league not in season, skipping $teamName');
        continue;
      }

      // For NFL, limit games (teams play once per week max)
      final maxGames = league == 'NFL' ? 1 : 3;
      int gamesAdded = 0;

      // Try each day in the range
      for (var day = start; day.isBefore(end) && gamesAdded < maxGames; day = day.add(const Duration(days: 1))) {
        // Check if this league plays on this day of week
        if (!_leaguePlaysOnDay(league, day.weekday)) continue;

        // Use deterministic selection based on team + date (not truly random)
        final shouldHaveGame = (teamName.hashCode + day.day) % 7 == 0;
        if (!shouldHaveGame && league != 'NFL') continue;

        // For NFL, only add game on first valid game day found
        if (league == 'NFL' && gamesAdded > 0) continue;

        final gameTime = _getTypicalGameTime(day, league);

        // Skip if outside range
        if (gameTime.isBefore(start) || gameTime.isAfter(end)) continue;

        // Generate opponent
        final opponent = _getRandomOpponent(teamName, league, gamesAdded);

        // Determine home/away
        final isHome = (random + gamesAdded) % 2 == 0;

        games.add(SportsGame(
          teamName: teamName,
          opponent: opponent,
          gameTime: gameTime,
          isHomeGame: isHome,
          league: league,
        ));
        gamesAdded++;
      }
    }

    // Sort by game time
    games.sort((a, b) => a.gameTime.compareTo(b.gameTime));

    return games;
  }

  /// Get typical game time for a league.
  DateTime _getTypicalGameTime(DateTime day, String league) {
    // Typical start times by league
    switch (league) {
      case 'NFL':
        // Sunday 12:00 PM or 3:25 PM, Monday 7:15 PM, Thursday 7:20 PM
        if (day.weekday == DateTime.sunday) {
          return DateTime(day.year, day.month, day.day, 12, 0);
        } else if (day.weekday == DateTime.monday) {
          return DateTime(day.year, day.month, day.day, 19, 15);
        } else if (day.weekday == DateTime.thursday) {
          return DateTime(day.year, day.month, day.day, 19, 20);
        }
        return DateTime(day.year, day.month, day.day, 15, 25);

      case 'NBA':
      case 'NHL':
        // Typically 7:00 PM or 9:30 PM
        return DateTime(day.year, day.month, day.day, 19, 0);

      case 'MLB':
        // Typically 7:10 PM, day games on weekends
        if (day.weekday == DateTime.sunday) {
          return DateTime(day.year, day.month, day.day, 13, 10);
        }
        return DateTime(day.year, day.month, day.day, 19, 10);

      case 'MLS':
      case 'NWSL':
        // Typically Saturday 7:30 PM
        return DateTime(day.year, day.month, day.day, 19, 30);

      case 'WNBA':
        // Typically 7:00 PM
        return DateTime(day.year, day.month, day.day, 19, 0);

      case 'NCAA':
        // Varies widely, default to Saturday afternoon
        if (day.weekday == DateTime.saturday) {
          return DateTime(day.year, day.month, day.day, 14, 30);
        }
        return DateTime(day.year, day.month, day.day, 18, 0);

      default:
        return DateTime(day.year, day.month, day.day, 19, 0);
    }
  }

  /// Get a random opponent for simulated games.
  String _getRandomOpponent(String teamName, String league, int seed) {
    final opponents = <String>[];

    switch (league) {
      case 'NFL':
        opponents.addAll([
          'Ravens', 'Bills', 'Cowboys', 'Eagles', '49ers', 'Chiefs',
          'Dolphins', 'Bengals', 'Lions', 'Packers', 'Broncos', 'Raiders',
        ]);
        break;
      case 'NBA':
        opponents.addAll([
          'Lakers', 'Celtics', 'Warriors', 'Heat', 'Bucks', 'Nuggets',
          'Suns', 'Mavericks', 'Grizzlies', '76ers', 'Nets', 'Bulls',
        ]);
        break;
      case 'MLB':
        opponents.addAll([
          'Yankees', 'Dodgers', 'Braves', 'Astros', 'Phillies', 'Padres',
          'Cardinals', 'Mets', 'Rangers', 'Mariners', 'Orioles', 'Twins',
        ]);
        break;
      case 'NHL':
        opponents.addAll([
          'Bruins', 'Avalanche', 'Oilers', 'Rangers', 'Lightning', 'Panthers',
          'Stars', 'Golden Knights', 'Maple Leafs', 'Devils', 'Hurricanes',
        ]);
        break;
      case 'MLS':
        opponents.addAll([
          'LA Galaxy', 'LAFC', 'Inter Miami', 'Atlanta United', 'Seattle Sounders',
          'Columbus Crew', 'Portland Timbers', 'NYC FC', 'Austin FC',
        ]);
        break;
      case 'WNBA':
        opponents.addAll([
          'Aces', 'Storm', 'Sun', 'Lynx', 'Sky', 'Liberty', 'Fever', 'Mercury',
        ]);
        break;
      case 'NWSL':
        opponents.addAll([
          'Portland Thorns', 'Orlando Pride', 'KC Current', 'San Diego Wave',
          'Angel City', 'Gotham FC', 'NC Courage', 'Chicago Red Stars',
        ]);
        break;
      default:
        opponents.addAll([
          'Wildcats', 'Tigers', 'Bulldogs', 'Bears', 'Eagles', 'Hurricanes',
        ]);
    }

    // Remove own team from opponents
    opponents.removeWhere((o) => teamName.toLowerCase().contains(o.toLowerCase()));

    if (opponents.isEmpty) return 'TBD';

    // Pick based on seed for consistency
    return opponents[seed % opponents.length];
  }

  /// Fetch live games from sports API.
  /// This is a placeholder for actual API integration.
  Future<List<SportsGame>> _fetchLiveGames(
    List<String> teamNames,
    DateTime start,
    DateTime end,
  ) async {
    // In a production implementation, this would call a real sports API
    // Options include:
    // - ESPN API (unofficial)
    // - SportsData.io (paid)
    // - TheSportsDB (free tier)
    // - Ball Don't Lie (NBA only, free)

    debugPrint('SportsScheduleService: Live API not configured, using simulated data');
    return _getSimulatedGames(teamNames, start, end);
  }

  /// Configure the service with an API key for live data.
  void setApiKey(String apiKey) {
    _apiKey = apiKey;
    _useSimulatedData = false;
  }

  /// Enable or disable simulated data mode.
  void setSimulatedMode(bool enabled) {
    _useSimulatedData = enabled;
  }
}

/// Provider for the sports schedule service.
final sportsScheduleServiceProvider = Provider<SportsScheduleService>(
  (ref) => SportsScheduleService(ref),
);
