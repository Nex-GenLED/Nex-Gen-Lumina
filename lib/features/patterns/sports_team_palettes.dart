import 'package:flutter/material.dart';
import 'package:nexgen_command/data/team_color_database.dart';
import 'package:nexgen_command/features/patterns/canonical_palettes.dart';

/// Thin adapter that converts [TeamColorDatabase] entries into
/// [CanonicalTheme] objects for the pattern / palette system.
///
/// **No hardcoded colour values live here.** Every RGB value is read from
/// [TeamColorDatabase], the single source of truth.
class SportsTeamPalettes {
  SportsTeamPalettes._();

  // ---------------------------------------------------------------------------
  // Public league-specific maps (backward-compatible with CanonicalPalettes)
  // ---------------------------------------------------------------------------

  static Map<String, CanonicalTheme>? _allCache;

  /// Every sports team as a CanonicalTheme, keyed by team id.
  static Map<String, CanonicalTheme> get allSportsTeams {
    if (_allCache != null) return _allCache!;
    _allCache = {
      for (final entry in TeamColorDatabase.allTeams)
        entry.id: _toCanonical(entry),
    };
    return _allCache!;
  }

  /// NFL teams only.
  static Map<String, CanonicalTheme> get nflTeams =>
      _filterByLeague('NFL');

  /// NBA teams only.
  static Map<String, CanonicalTheme> get nbaTeams =>
      _filterByLeague('NBA');

  /// NHL teams only.
  static Map<String, CanonicalTheme> get nhlTeams =>
      _filterByLeague('NHL');

  /// MLB teams only.
  static Map<String, CanonicalTheme> get mlbTeams =>
      _filterByLeague('MLB');

  /// MLS teams only.
  static Map<String, CanonicalTheme> get mlsTeams =>
      _filterByLeague('MLS');

  /// NWSL teams only.
  static Map<String, CanonicalTheme> get nwslTeams =>
      _filterByLeague('NWSL');

  /// UFL teams only.
  static Map<String, CanonicalTheme> get uflTeams =>
      _filterByLeague('UFL');

  /// WNBA teams only.
  static Map<String, CanonicalTheme> get wnbaTeams =>
      _filterByLeague('WNBA');

  /// NCAA teams only.
  static Map<String, CanonicalTheme> get ncaaFootballTeams =>
      _filterByLeague('NCAA');

  /// Convenience lists.
  static List<CanonicalTheme> get allNflTeams => nflTeams.values.toList();
  static List<CanonicalTheme> get allNbaTeams => nbaTeams.values.toList();

  // ---------------------------------------------------------------------------
  // Conversion helpers
  // ---------------------------------------------------------------------------

  static Map<String, CanonicalTheme> _filterByLeague(String league) {
    final all = allSportsTeams;
    final leagueIds =
        TeamColorDatabase.getByLeague(league).map((e) => e.id).toSet();
    return Map.fromEntries(
      all.entries.where((e) => leagueIds.contains(e.key)),
    );
  }

  /// Convert a [UnifiedTeamEntry] into a [CanonicalTheme].
  static CanonicalTheme _toCanonical(UnifiedTeamEntry entry) {
    return CanonicalTheme(
      id: entry.id,
      displayName: entry.officialName,
      description:
          'Official ${UnifiedTeamEntry.extractTeamName(entry.officialName, entry.city)} colors',
      icon: _iconForLeague(entry.league),
      category: ThemeCategory.sports,
      canonicalColors: entry.colors
          .map((c) => ThemeColor(c.name, Color.fromARGB(255, c.r, c.g, c.b)))
          .toList(),
      suggestedEffects: entry.suggestedEffects,
      defaultSpeed: entry.defaultSpeed,
      defaultIntensity: entry.defaultIntensity,
      aliases: entry.aliases,
    );
  }

  static IconData _iconForLeague(String league) {
    switch (league) {
      case 'NFL':
      case 'UFL':
      case 'NCAA':
        return Icons.sports_football;
      case 'NBA':
      case 'WNBA':
        return Icons.sports_basketball;
      case 'NHL':
        return Icons.sports_hockey;
      case 'MLB':
        return Icons.sports_baseball;
      case 'MLS':
      case 'NWSL':
      case 'EPL':
      case 'La Liga':
      case 'Bundesliga':
      case 'Serie A':
        return Icons.sports_soccer;
      default:
        return Icons.sports;
    }
  }
}
