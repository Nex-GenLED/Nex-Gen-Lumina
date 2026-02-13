import 'package:flutter/material.dart';
import 'package:nexgen_command/data/team_color_database.dart';

/// Represents a sports team with its name and official colors.
class SportsTeam {
  final String name;
  final String league;
  final String city;
  final List<Color> colors;
  final String? nickname; // e.g., "KC" for Kansas City

  const SportsTeam({
    required this.name,
    required this.league,
    required this.city,
    required this.colors,
    this.nickname,
  });

  /// Display name including city
  String get displayName => '$city $name';

  /// Search-friendly string
  String get searchKey => '$city $name ${nickname ?? ''} $league'.toLowerCase();
}

/// Database of popular sports teams with their official colors.
///
/// All data is derived from [TeamColorDatabase], the single source of truth.
/// This class provides a lightweight [SportsTeam] view for consumers that
/// don't need the full [UnifiedTeamEntry] model.
class SportsTeamsDatabase {
  static List<SportsTeam>? _cache;

  /// All teams, lazily derived from [TeamColorDatabase].
  static List<SportsTeam> get allTeams {
    if (_cache != null) return _cache!;
    _cache = TeamColorDatabase.allTeams.map(_fromEntry).toList();
    return _cache!;
  }

  /// Search teams by query string
  static List<SportsTeam> search(String query) {
    if (query.isEmpty) return [];
    final lower = query.toLowerCase();
    return allTeams.where((t) => t.searchKey.contains(lower)).toList();
  }

  /// Get team by display name (exact match)
  static SportsTeam? getByName(String displayName) {
    try {
      return allTeams.firstWhere((t) => t.displayName == displayName);
    } catch (_) {
      return null;
    }
  }

  /// Get teams by league
  static List<SportsTeam> getByLeague(String league) {
    return allTeams.where((t) => t.league == league).toList();
  }

  /// Get all unique leagues
  static List<String> get leagues {
    return allTeams.map((t) => t.league).toSet().toList()..sort();
  }

  /// Searches for a sports team in a query string.
  /// Returns the first matching team or null.
  ///
  /// This method is more sophisticated than simple search() as it:
  /// - Handles multi-word team names ("Kansas City Royals", "Red Sox")
  /// - Handles city + team combinations
  /// - Handles nicknames ("KC Royals", "NY Yankees")
  /// - Prioritizes longer/more specific matches
  static SportsTeam? findTeamInQuery(String query) {
    if (query.isEmpty) return null;
    final lower = query.toLowerCase();

    // Build a list of potential matches with their specificity score
    final matches = <_TeamMatch>[];

    for (final team in allTeams) {
      int score = 0;

      // Check for full display name (e.g., "Kansas City Royals")
      final displayLower = team.displayName.toLowerCase();
      if (lower.contains(displayLower)) {
        score = 100 + displayLower.length; // Highest priority for full name
      }
      // Check for city + team name (e.g., "kansas city" + "royals")
      else if (lower.contains(team.city.toLowerCase()) &&
               lower.contains(team.name.toLowerCase())) {
        score = 80 + team.city.length + team.name.length;
      }
      // Check for nickname + team name (e.g., "kc royals")
      else if (team.nickname != null &&
               lower.contains(team.nickname!.toLowerCase()) &&
               lower.contains(team.name.toLowerCase())) {
        score = 70 + team.name.length;
      }
      // Check for just team name (e.g., "royals", "chiefs")
      // Use word boundaries to avoid partial matches
      else {
        final teamNameLower = team.name.toLowerCase();
        final pattern = RegExp('\\b${RegExp.escape(teamNameLower)}\\b');
        if (pattern.hasMatch(lower)) {
          score = 50 + teamNameLower.length;
        }
      }

      if (score > 0) {
        matches.add(_TeamMatch(team: team, score: score));
      }
    }

    if (matches.isEmpty) return null;

    // Sort by score (highest first) and return the best match
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.first.team;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Derive a [SportsTeam] from a [UnifiedTeamEntry].
  static SportsTeam _fromEntry(UnifiedTeamEntry entry) {
    return SportsTeam(
      name: UnifiedTeamEntry.extractTeamName(entry.officialName, entry.city),
      league: entry.league,
      city: entry.city,
      colors: entry.colors
          .map((c) => Color.fromARGB(255, c.r, c.g, c.b))
          .toList(),
      nickname: _deriveNickname(entry),
    );
  }

  /// Pick the shortest alias (2-3 chars) as a nickname abbreviation.
  static String? _deriveNickname(UnifiedTeamEntry entry) {
    for (final alias in entry.aliases) {
      if (alias.length >= 2 && alias.length <= 4) {
        return alias.toUpperCase();
      }
    }
    return null;
  }
}

/// Helper class for team matching with scoring
class _TeamMatch {
  final SportsTeam team;
  final int score;
  const _TeamMatch({required this.team, required this.score});
}
