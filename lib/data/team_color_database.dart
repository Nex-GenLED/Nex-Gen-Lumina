import 'package:flutter/material.dart';
import 'package:nexgen_command/features/patterns/canonical_palettes.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes_nhl.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes_mlb.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes_soccer.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes_other.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes_ncaa.dart';
import 'package:nexgen_command/data/sports_teams.dart';

// ---------------------------------------------------------------------------
// TeamColor -- lightweight named RGB color
// ---------------------------------------------------------------------------

/// A simple named color with integer RGB components.
class TeamColor {
  final String name;
  final int r;
  final int g;
  final int b;

  const TeamColor(this.name, this.r, this.g, this.b);

  /// Construct from a Flutter [Color].
  TeamColor.fromColor(this.name, Color c)
      : r = (c.r * 255.0).round().clamp(0, 255),
        g = (c.g * 255.0).round().clamp(0, 255),
        b = (c.b * 255.0).round().clamp(0, 255);

  /// Construct from a 0xAARRGGBB hex int (alpha is ignored).
  const TeamColor.hex(this.name, int hex)
      : r = (hex >> 16) & 0xFF,
        g = (hex >> 8) & 0xFF,
        b = hex & 0xFF;

  /// Convert to a Flutter [Color].
  Color toColor() => Color.fromARGB(255, r, g, b);

  Map<String, dynamic> toJson() => {
        'name': name,
        'r': r,
        'g': g,
        'b': b,
      };

  @override
  String toString() => 'TeamColor($name, #${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')})';
}

// ---------------------------------------------------------------------------
// UnifiedTeamEntry -- normalized representation of any sports team
// ---------------------------------------------------------------------------

/// A single normalised team entry that unifies data from CanonicalTheme
/// palette files and the legacy [SportsTeam] database.
class UnifiedTeamEntry {
  /// Machine-readable identifier (lowercase, underscores).
  final String id;

  /// Full official team name, e.g. "Kansas City Chiefs".
  final String officialName;

  /// City portion, e.g. "Kansas City".
  final String city;

  /// League identifier, e.g. "NFL", "EPL", "La Liga".
  final String league;

  /// US state abbreviation or full name (optional).
  final String? state;

  /// Country (optional -- defaults to USA for domestic leagues).
  final String? country;

  /// All search-friendly aliases (lowercased).
  final List<String> aliases;

  /// Official team colors.
  final List<TeamColor> colors;

  /// Suggested WLED effect IDs.
  final List<int> suggestedEffects;

  /// Default speed value for WLED (0-255).
  final int defaultSpeed;

  /// Default intensity value for WLED (0-255).
  final int defaultIntensity;

  /// Reference to the source [CanonicalTheme] if this entry was derived
  /// from a palette file. May be null for legacy-only entries.
  final CanonicalTheme? canonicalTheme;

  /// Reference to the legacy [SportsTeam] if one exists.
  final SportsTeam? legacyTeam;

  const UnifiedTeamEntry({
    required this.id,
    required this.officialName,
    required this.city,
    required this.league,
    this.state,
    this.country,
    this.aliases = const [],
    this.colors = const [],
    this.suggestedEffects = const [12, 41, 65, 0],
    this.defaultSpeed = 85,
    this.defaultIntensity = 180,
    this.canonicalTheme,
    this.legacyTeam,
  });

  /// LED-optimised RGB arrays.
  ///
  /// Delegates to [CanonicalTheme.canonicalRgb] when available (which applies
  /// LED colour-correction). Falls back to a raw conversion of [colors].
  List<List<int>> get ledOptimizedRgb {
    if (canonicalTheme != null) {
      return canonicalTheme!.canonicalRgb;
    }
    return colors.map((c) => [c.r, c.g, c.b]).toList();
  }

  /// Convert back to a legacy [SportsTeam] for backwards compatibility.
  SportsTeam toSportsTeam() {
    if (legacyTeam != null) return legacyTeam!;
    return SportsTeam(
      name: _extractTeamName(officialName, city),
      league: league,
      city: city,
      colors: colors.map((c) => c.toColor()).toList(),
    );
  }

  /// Extract the team-name portion from an official name by stripping the
  /// leading city. E.g. "Kansas City Chiefs" -> "Chiefs".
  static String _extractTeamName(String officialName, String city) {
    if (officialName.toLowerCase().startsWith(city.toLowerCase())) {
      final remainder = officialName.substring(city.length).trim();
      if (remainder.isNotEmpty) return remainder;
    }
    return officialName;
  }
}

// ---------------------------------------------------------------------------
// TeamColorDatabase -- unified static facade
// ---------------------------------------------------------------------------

/// Unified, lazily-built database of every sports team the app knows about.
///
/// Merges data from all existing CanonicalTheme palette files, the legacy
/// [SportsTeamsDatabase], and hardcoded international soccer teams.
class TeamColorDatabase {
  TeamColorDatabase._();

  // ---- cache fields ----
  static List<UnifiedTeamEntry>? _allTeamsCache;
  static Map<String, List<UnifiedTeamEntry>>? _aliasIndexCache;

  // -----------------------------------------------------------------------
  // Public API
  // -----------------------------------------------------------------------

  /// Every team, lazily built on first access.
  static List<UnifiedTeamEntry> get allTeams {
    _allTeamsCache ??= _buildAllTeams();
    return _allTeamsCache!;
  }

  /// Alias index mapping every lowercase alias/name to the list of matching
  /// [UnifiedTeamEntry] objects.
  static Map<String, List<UnifiedTeamEntry>> get aliasIndex {
    if (_aliasIndexCache != null) return _aliasIndexCache!;
    _aliasIndexCache = _buildAliasIndex(allTeams);
    return _aliasIndexCache!;
  }

  /// Filter teams by league identifier (case-insensitive).
  static List<UnifiedTeamEntry> getByLeague(String league) {
    final lower = league.toLowerCase();
    return allTeams.where((t) => t.league.toLowerCase() == lower).toList();
  }

  /// Basic contains search across official name, city, league, and aliases.
  static List<UnifiedTeamEntry> search(String query) {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    return allTeams.where((t) {
      if (t.officialName.toLowerCase().contains(q)) return true;
      if (t.city.toLowerCase().contains(q)) return true;
      if (t.league.toLowerCase().contains(q)) return true;
      for (final alias in t.aliases) {
        if (alias.contains(q)) return true;
      }
      return false;
    }).toList();
  }

  /// All unique league identifiers, sorted alphabetically.
  static List<String> get leagues {
    return allTeams.map((t) => t.league).toSet().toList()..sort();
  }

  /// Merge overlay teams received from Firestore into the cached list.
  ///
  /// Called by [ColorDatabaseManagerNotifier] after syncing or loading cache.
  /// Duplicate IDs are replaced so corrections take effect.
  static void addOverlayTeams(List<UnifiedTeamEntry> overlay) {
    if (overlay.isEmpty) return;

    // Ensure the cache is populated first
    final current = allTeams;
    final existingIds = current.map((t) => t.id).toSet();

    for (final entry in overlay) {
      if (existingIds.contains(entry.id)) {
        // Replace existing entry (correction)
        final idx = current.indexWhere((t) => t.id == entry.id);
        if (idx >= 0) current[idx] = entry;
      } else {
        // New addition
        current.add(entry);
        existingIds.add(entry.id);
      }
    }

    // Rebuild alias index to include new/corrected entries
    _aliasIndexCache = null;
  }

  // -----------------------------------------------------------------------
  // Private builders
  // -----------------------------------------------------------------------

  /// Detect league from the palette map that a CanonicalTheme came from.
  static String _detectLeague(String sourceLabel) {
    switch (sourceLabel) {
      case 'nfl':
        return 'NFL';
      case 'nba':
        return 'NBA';
      case 'nhl':
        return 'NHL';
      case 'mlb':
        return 'MLB';
      case 'mls':
        return 'MLS';
      case 'nwsl':
        return 'NWSL';
      case 'ufl':
        return 'UFL';
      case 'wnba':
        return 'WNBA';
      case 'ncaa':
        return 'NCAA';
      default:
        return sourceLabel.toUpperCase();
    }
  }

  /// Extract the city portion from a displayName like "Kansas City Chiefs".
  /// Uses a simple heuristic: everything before the last word (or last two
  /// words for known multi-word team names).
  static String _extractCity(String displayName) {
    // Known multi-word team name suffixes
    const multiWordSuffixes = [
      'Red Sox',
      'White Sox',
      'Blue Jays',
      'Trail Blazers',
      'Red Wings',
      'Blue Jackets',
      'Golden Knights',
      'Maple Leafs',
      'Red Bulls',
      'Crimson Tide',
      'Fighting Irish',
      'Nittany Lions',
      'Horned Frogs',
      'Yellow Jackets',
      'Sun Devils',
      'Scarlet Knights',
      'Golden Gophers',
      'Boiler Makers',
      'Tar Heels',
      'Angel City',
      'Bay FC',
      'Red Stars',
      'Gotham FC',
      'Racing Louisville',
      'Inter Miami',
      'Atlanta United',
      'Sporting KC',
      'Real Salt Lake',
      'FC Cincinnati',
      'FC Dallas',
      'Austin FC',
      'Charlotte FC',
      'St. Louis City',
      'CF Montréal',
      'Nashville SC',
      'San Jose Earthquakes',
    ];

    for (final suffix in multiWordSuffixes) {
      if (displayName.endsWith(suffix)) {
        final city = displayName.substring(0, displayName.length - suffix.length).trim();
        return city.isEmpty ? displayName : city;
      }
    }

    // Special case: team names that end with "FC", "SC", "CF", "United"
    // where the team name IS the city
    if (displayName.endsWith(' FC') ||
        displayName.endsWith(' SC') ||
        displayName.endsWith(' CF')) {
      return displayName.substring(0, displayName.length - 3).trim();
    }

    // Default: drop the last word
    final parts = displayName.split(' ');
    if (parts.length <= 1) return displayName;
    return parts.sublist(0, parts.length - 1).join(' ');
  }

  /// Convert a single [CanonicalTheme] into a [UnifiedTeamEntry].
  static UnifiedTeamEntry _fromCanonical(
    CanonicalTheme theme,
    String leagueLabel,
  ) {
    final league = _detectLeague(leagueLabel);
    final city = _extractCity(theme.displayName);
    return UnifiedTeamEntry(
      id: theme.id,
      officialName: theme.displayName,
      city: city,
      league: league,
      country: 'USA',
      aliases: theme.aliases.map((a) => a.toLowerCase()).toList(),
      colors: theme.canonicalColors
          .map((tc) => TeamColor.fromColor(tc.name, tc.color))
          .toList(),
      suggestedEffects: theme.suggestedEffects,
      defaultSpeed: theme.defaultSpeed,
      defaultIntensity: theme.defaultIntensity,
      canonicalTheme: theme,
    );
  }

  /// Convert a legacy [SportsTeam] into a [UnifiedTeamEntry].
  static UnifiedTeamEntry _fromLegacy(SportsTeam team) {
    final fullName = team.displayName;
    return UnifiedTeamEntry(
      id: '${team.league.toLowerCase()}_${team.name.toLowerCase().replaceAll(' ', '_')}',
      officialName: fullName,
      city: team.city,
      league: team.league,
      country: 'USA',
      aliases: [
        fullName.toLowerCase(),
        team.name.toLowerCase(),
        team.city.toLowerCase(),
        if (team.nickname != null) team.nickname!.toLowerCase(),
      ],
      colors: team.colors
          .map((c) => TeamColor.fromColor('', c))
          .toList(),
      legacyTeam: team,
    );
  }

  /// Master builder -- runs once and caches.
  static List<UnifiedTeamEntry> _buildAllTeams() {
    final result = <UnifiedTeamEntry>[];
    final seenNames = <String>{};

    // (a) Iterate all CanonicalTheme palette maps
    void addPaletteMap(Map<String, CanonicalTheme> map, String leagueLabel) {
      for (final theme in map.values) {
        final entry = _fromCanonical(theme, leagueLabel);
        result.add(entry);
        seenNames.add(entry.officialName.toLowerCase());
      }
    }

    addPaletteMap(SportsTeamPalettes.nflTeams, 'nfl');
    addPaletteMap(SportsTeamPalettes.nbaTeams, 'nba');
    addPaletteMap(NhlTeamPalettes.nhlTeams, 'nhl');
    addPaletteMap(MlbTeamPalettes.mlbTeams, 'mlb');
    addPaletteMap(SoccerTeamPalettes.mlsTeams, 'mls');
    addPaletteMap(SoccerTeamPalettes.nwslTeams, 'nwsl');
    addPaletteMap(OtherLeaguesPalettes.uflTeams, 'ufl');
    addPaletteMap(OtherLeaguesPalettes.wnbaTeams, 'wnba');
    addPaletteMap(NcaaTeamPalettes.ncaaFootballTeams, 'ncaa');

    // (b) Add any legacy SportsTeamsDatabase entries not already covered
    for (final team in SportsTeamsDatabase.allTeams) {
      final displayLower = team.displayName.toLowerCase();
      if (!seenNames.contains(displayLower)) {
        result.add(_fromLegacy(team));
        seenNames.add(displayLower);
      }
    }

    // (c) International soccer leagues
    result.addAll(_eplTeams);
    result.addAll(_laLigaTeams);
    result.addAll(_bundesligaTeams);
    result.addAll(_serieATeams);

    return result;
  }

  /// Build the alias index.
  static Map<String, List<UnifiedTeamEntry>> _buildAliasIndex(
    List<UnifiedTeamEntry> teams,
  ) {
    final index = <String, List<UnifiedTeamEntry>>{};

    void add(String key, UnifiedTeamEntry entry) {
      final k = key.toLowerCase().trim();
      if (k.isEmpty) return;
      (index[k] ??= []).add(entry);
    }

    for (final team in teams) {
      // Official name
      add(team.officialName, team);
      // City
      add(team.city, team);
      // Team name portion (officialName minus city prefix)
      final teamName =
          UnifiedTeamEntry._extractTeamName(team.officialName, team.city);
      add(teamName, team);
      // All explicit aliases
      for (final alias in team.aliases) {
        add(alias, team);
      }
    }

    return index;
  }

  // =======================================================================
  //  International Soccer Data
  // =======================================================================

  // -- helpers --
  static UnifiedTeamEntry _intl({
    required String id,
    required String name,
    required String city,
    required String league,
    required String country,
    required List<TeamColor> colors,
    required List<String> aliases,
    List<int> suggestedEffects = const [12, 41, 65, 0],
  }) {
    return UnifiedTeamEntry(
      id: id,
      officialName: name,
      city: city,
      league: league,
      country: country,
      aliases: aliases.map((a) => a.toLowerCase()).toList(),
      colors: colors,
      suggestedEffects: suggestedEffects,
      defaultSpeed: 85,
      defaultIntensity: 180,
    );
  }

  // -----------------------------------------------------------------------
  // EPL (Premier League) -- 20 teams
  // -----------------------------------------------------------------------
  static final List<UnifiedTeamEntry> _eplTeams = [
    _intl(
      id: 'arsenal',
      name: 'Arsenal',
      city: 'London',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Arsenal Red', 0xFFEF0107),
        TeamColor.hex('Arsenal White', 0xFFFFFFFF),
      ],
      aliases: ['arsenal', 'arsenal fc', 'gunners', 'the gunners', 'afc'],
    ),
    _intl(
      id: 'aston_villa',
      name: 'Aston Villa',
      city: 'Birmingham',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Villa Claret', 0xFF670E36),
        TeamColor.hex('Villa Blue', 0xFF95BFE5),
      ],
      aliases: ['aston villa', 'aston villa fc', 'villa', 'the villans', 'avfc'],
    ),
    _intl(
      id: 'bournemouth',
      name: 'AFC Bournemouth',
      city: 'Bournemouth',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Bournemouth Red', 0xFFDA291C),
        TeamColor.hex('Bournemouth Black', 0xFF000000),
      ],
      aliases: ['bournemouth', 'afc bournemouth', 'cherries', 'the cherries'],
    ),
    _intl(
      id: 'brentford',
      name: 'Brentford',
      city: 'London',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Brentford Red', 0xFFE30613),
        TeamColor.hex('Brentford White', 0xFFFFFFFF),
      ],
      aliases: ['brentford', 'brentford fc', 'bees', 'the bees'],
    ),
    _intl(
      id: 'brighton',
      name: 'Brighton & Hove Albion',
      city: 'Brighton',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Brighton Blue', 0xFF0057B8),
        TeamColor.hex('Brighton White', 0xFFFFFFFF),
      ],
      aliases: ['brighton', 'brighton fc', 'seagulls', 'the seagulls', 'bhafc'],
    ),
    _intl(
      id: 'burnley',
      name: 'Burnley',
      city: 'Burnley',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Burnley Claret', 0xFF6C1D45),
        TeamColor.hex('Burnley Blue', 0xFF99D6EA),
      ],
      aliases: ['burnley', 'burnley fc', 'clarets', 'the clarets'],
    ),
    _intl(
      id: 'chelsea',
      name: 'Chelsea',
      city: 'London',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Chelsea Blue', 0xFF034694),
        TeamColor.hex('Chelsea White', 0xFFFFFFFF),
      ],
      aliases: ['chelsea', 'chelsea fc', 'blues', 'the blues', 'cfc'],
    ),
    _intl(
      id: 'crystal_palace',
      name: 'Crystal Palace',
      city: 'London',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Palace Red', 0xFF1B458F),
        TeamColor.hex('Palace Blue', 0xFFC4122E),
      ],
      aliases: ['crystal palace', 'crystal palace fc', 'palace', 'eagles', 'cpfc'],
    ),
    _intl(
      id: 'everton',
      name: 'Everton',
      city: 'Liverpool',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Everton Blue', 0xFF003399),
        TeamColor.hex('Everton White', 0xFFFFFFFF),
      ],
      aliases: ['everton', 'everton fc', 'toffees', 'the toffees', 'efc'],
    ),
    _intl(
      id: 'fulham',
      name: 'Fulham',
      city: 'London',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Fulham White', 0xFFFFFFFF),
        TeamColor.hex('Fulham Black', 0xFF000000),
      ],
      aliases: ['fulham', 'fulham fc', 'cottagers', 'the cottagers', 'ffc'],
    ),
    _intl(
      id: 'liverpool',
      name: 'Liverpool',
      city: 'Liverpool',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Liverpool Red', 0xFFC8102E),
        TeamColor.hex('Liverpool White', 0xFFFFFFFF),
      ],
      aliases: ['liverpool', 'liverpool fc', 'reds', 'the reds', 'lfc', 'ynwa'],
    ),
    _intl(
      id: 'luton_town',
      name: 'Luton Town',
      city: 'Luton',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Luton Orange', 0xFFF78F1E),
        TeamColor.hex('Luton Navy', 0xFF002D62),
      ],
      aliases: ['luton town', 'luton', 'luton fc', 'hatters', 'the hatters'],
    ),
    _intl(
      id: 'man_city',
      name: 'Manchester City',
      city: 'Manchester',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('City Blue', 0xFF6CABDD),
        TeamColor.hex('City White', 0xFFFFFFFF),
      ],
      aliases: ['man city', 'manchester city', 'mcfc', 'city', 'citizens', 'the citizens'],
    ),
    _intl(
      id: 'man_united',
      name: 'Manchester United',
      city: 'Manchester',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('United Red', 0xFFDA291C),
        TeamColor.hex('United White', 0xFFFFFFFF),
        TeamColor.hex('United Black', 0xFF000000),
      ],
      aliases: ['man united', 'manchester united', 'man utd', 'mufc', 'red devils', 'united'],
    ),
    _intl(
      id: 'newcastle',
      name: 'Newcastle United',
      city: 'Newcastle',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Newcastle Black', 0xFF241F20),
        TeamColor.hex('Newcastle White', 0xFFFFFFFF),
      ],
      aliases: ['newcastle', 'newcastle united', 'nufc', 'magpies', 'the magpies', 'toon'],
    ),
    _intl(
      id: 'nottingham_forest',
      name: 'Nottingham Forest',
      city: 'Nottingham',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Forest Red', 0xFFDD0000),
        TeamColor.hex('Forest White', 0xFFFFFFFF),
      ],
      aliases: ['nottingham forest', 'forest', 'nffc', 'the tricky trees'],
    ),
    _intl(
      id: 'sheffield_united',
      name: 'Sheffield United',
      city: 'Sheffield',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Sheffield Red', 0xFFEE2737),
        TeamColor.hex('Sheffield White', 0xFFFFFFFF),
      ],
      aliases: ['sheffield united', 'sheffield utd', 'blades', 'the blades', 'sufc'],
    ),
    _intl(
      id: 'tottenham',
      name: 'Tottenham Hotspur',
      city: 'London',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Spurs White', 0xFFFFFFFF),
        TeamColor.hex('Spurs Navy', 0xFF132257),
      ],
      aliases: ['tottenham', 'tottenham hotspur', 'spurs', 'thfc', 'coys'],
    ),
    _intl(
      id: 'west_ham',
      name: 'West Ham United',
      city: 'London',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('West Ham Claret', 0xFF7A263A),
        TeamColor.hex('West Ham Blue', 0xFF1BB1E7),
      ],
      aliases: ['west ham', 'west ham united', 'hammers', 'the hammers', 'whufc', 'irons'],
    ),
    _intl(
      id: 'wolverhampton',
      name: 'Wolverhampton Wanderers',
      city: 'Wolverhampton',
      league: 'EPL',
      country: 'England',
      colors: [
        TeamColor.hex('Wolves Gold', 0xFFFDB913),
        TeamColor.hex('Wolves Black', 0xFF231F20),
      ],
      aliases: ['wolves', 'wolverhampton', 'wolverhampton wanderers', 'wwfc'],
    ),
  ];

  // -----------------------------------------------------------------------
  // La Liga -- 20 teams
  // -----------------------------------------------------------------------
  static final List<UnifiedTeamEntry> _laLigaTeams = [
    _intl(
      id: 'real_madrid',
      name: 'Real Madrid',
      city: 'Madrid',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Madrid White', 0xFFFFFFFF),
        TeamColor.hex('Madrid Gold', 0xFFFEBE10),
      ],
      aliases: ['real madrid', 'real madrid cf', 'los blancos', 'rmfc', 'madrid'],
    ),
    _intl(
      id: 'barcelona',
      name: 'FC Barcelona',
      city: 'Barcelona',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Barca Blue', 0xFF004D98),
        TeamColor.hex('Barca Red', 0xFFA50044),
        TeamColor.hex('Barca Gold', 0xFFEDBC00),
      ],
      aliases: ['barcelona', 'fc barcelona', 'barca', 'blaugrana', 'fcb'],
    ),
    _intl(
      id: 'atletico_madrid',
      name: 'Atletico Madrid',
      city: 'Madrid',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Atletico Red', 0xFFCB3524),
        TeamColor.hex('Atletico White', 0xFFFFFFFF),
        TeamColor.hex('Atletico Blue', 0xFF272E61),
      ],
      aliases: ['atletico madrid', 'atletico', 'atleti', 'colchoneros', 'atm'],
    ),
    _intl(
      id: 'real_sociedad',
      name: 'Real Sociedad',
      city: 'San Sebastian',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Sociedad Blue', 0xFF003DA5),
        TeamColor.hex('Sociedad White', 0xFFFFFFFF),
      ],
      aliases: ['real sociedad', 'sociedad', 'la real', 'txuri urdin'],
    ),
    _intl(
      id: 'athletic_bilbao',
      name: 'Athletic Bilbao',
      city: 'Bilbao',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Bilbao Red', 0xFFEE2523),
        TeamColor.hex('Bilbao White', 0xFFFFFFFF),
      ],
      aliases: ['athletic bilbao', 'athletic club', 'bilbao', 'los leones'],
    ),
    _intl(
      id: 'real_betis',
      name: 'Real Betis',
      city: 'Seville',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Betis Green', 0xFF00954C),
        TeamColor.hex('Betis White', 0xFFFFFFFF),
      ],
      aliases: ['real betis', 'betis', 'los verdiblancos', 'beticos'],
    ),
    _intl(
      id: 'villarreal',
      name: 'Villarreal',
      city: 'Villarreal',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Villarreal Yellow', 0xFFFFE667),
        TeamColor.hex('Villarreal Navy', 0xFF005187),
      ],
      aliases: ['villarreal', 'villarreal cf', 'yellow submarine', 'el submarino amarillo'],
    ),
    _intl(
      id: 'sevilla',
      name: 'Sevilla FC',
      city: 'Seville',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Sevilla White', 0xFFFFFFFF),
        TeamColor.hex('Sevilla Red', 0xFFDA291C),
      ],
      aliases: ['sevilla', 'sevilla fc', 'sevillistas', 'los nervionenses'],
    ),
    _intl(
      id: 'valencia',
      name: 'Valencia CF',
      city: 'Valencia',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Valencia White', 0xFFFFFFFF),
        TeamColor.hex('Valencia Orange', 0xFFEE8707),
        TeamColor.hex('Valencia Black', 0xFF000000),
      ],
      aliases: ['valencia', 'valencia cf', 'los che', 'murcielagos'],
    ),
    _intl(
      id: 'girona',
      name: 'Girona FC',
      city: 'Girona',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Girona Red', 0xFFCD2534),
        TeamColor.hex('Girona White', 0xFFFFFFFF),
      ],
      aliases: ['girona', 'girona fc', 'blanquivermells'],
    ),
    _intl(
      id: 'osasuna',
      name: 'CA Osasuna',
      city: 'Pamplona',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Osasuna Red', 0xFFD91A2A),
        TeamColor.hex('Osasuna Navy', 0xFF132257),
      ],
      aliases: ['osasuna', 'ca osasuna', 'los rojillos', 'pamplona'],
    ),
    _intl(
      id: 'celta_vigo',
      name: 'Celta Vigo',
      city: 'Vigo',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Celta Blue', 0xFF8AC3EE),
        TeamColor.hex('Celta White', 0xFFFFFFFF),
      ],
      aliases: ['celta vigo', 'celta', 'rc celta', 'celestes'],
    ),
    _intl(
      id: 'mallorca',
      name: 'RCD Mallorca',
      city: 'Palma',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Mallorca Red', 0xFFCE1126),
        TeamColor.hex('Mallorca Black', 0xFF000000),
      ],
      aliases: ['mallorca', 'rcd mallorca', 'bermellones', 'palma'],
    ),
    _intl(
      id: 'rayo_vallecano',
      name: 'Rayo Vallecano',
      city: 'Madrid',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Rayo White', 0xFFFFFFFF),
        TeamColor.hex('Rayo Red', 0xFFE53027),
      ],
      aliases: ['rayo vallecano', 'rayo', 'franjirrojos', 'vallecas'],
    ),
    _intl(
      id: 'getafe',
      name: 'Getafe CF',
      city: 'Getafe',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Getafe Blue', 0xFF004FA3),
        TeamColor.hex('Getafe White', 0xFFFFFFFF),
      ],
      aliases: ['getafe', 'getafe cf', 'azulones'],
    ),
    _intl(
      id: 'alaves',
      name: 'Deportivo Alaves',
      city: 'Vitoria-Gasteiz',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Alaves Blue', 0xFF003DA5),
        TeamColor.hex('Alaves White', 0xFFFFFFFF),
      ],
      aliases: ['alaves', 'deportivo alaves', 'babazorros', 'glorioso'],
    ),
    _intl(
      id: 'las_palmas',
      name: 'UD Las Palmas',
      city: 'Las Palmas',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Las Palmas Yellow', 0xFFFFE400),
        TeamColor.hex('Las Palmas Blue', 0xFF003DA5),
      ],
      aliases: ['las palmas', 'ud las palmas', 'amarillos', 'canarios'],
    ),
    _intl(
      id: 'cadiz',
      name: 'Cadiz CF',
      city: 'Cadiz',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Cadiz Yellow', 0xFFFEE536),
        TeamColor.hex('Cadiz Blue', 0xFF00529F),
      ],
      aliases: ['cadiz', 'cadiz cf', 'submarino amarillo'],
    ),
    _intl(
      id: 'granada',
      name: 'Granada CF',
      city: 'Granada',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Granada Red', 0xFFEE1119),
        TeamColor.hex('Granada White', 0xFFFFFFFF),
      ],
      aliases: ['granada', 'granada cf', 'nazaries', 'rojiblancos'],
    ),
    _intl(
      id: 'almeria',
      name: 'UD Almeria',
      city: 'Almeria',
      league: 'La Liga',
      country: 'Spain',
      colors: [
        TeamColor.hex('Almeria Red', 0xFFEE1C25),
        TeamColor.hex('Almeria White', 0xFFFFFFFF),
      ],
      aliases: ['almeria', 'ud almeria', 'indaliticos', 'rojiblancos almeria'],
    ),
  ];

  // -----------------------------------------------------------------------
  // Bundesliga -- 18 teams
  // -----------------------------------------------------------------------
  static final List<UnifiedTeamEntry> _bundesligaTeams = [
    _intl(
      id: 'bayern_munich',
      name: 'Bayern Munich',
      city: 'Munich',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Bayern Red', 0xFFDC052D),
        TeamColor.hex('Bayern White', 0xFFFFFFFF),
      ],
      aliases: ['bayern munich', 'bayern', 'fc bayern', 'fcb munich', 'die roten'],
    ),
    _intl(
      id: 'borussia_dortmund',
      name: 'Borussia Dortmund',
      city: 'Dortmund',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('BVB Yellow', 0xFFFDE100),
        TeamColor.hex('BVB Black', 0xFF000000),
      ],
      aliases: ['borussia dortmund', 'dortmund', 'bvb', 'die schwarzgelben'],
    ),
    _intl(
      id: 'rb_leipzig',
      name: 'RB Leipzig',
      city: 'Leipzig',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Leipzig Red', 0xFFDD0741),
        TeamColor.hex('Leipzig White', 0xFFFFFFFF),
      ],
      aliases: ['rb leipzig', 'leipzig', 'rbl', 'die roten bullen'],
    ),
    _intl(
      id: 'bayer_leverkusen',
      name: 'Bayer Leverkusen',
      city: 'Leverkusen',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Leverkusen Red', 0xFFE32221),
        TeamColor.hex('Leverkusen Black', 0xFF000000),
      ],
      aliases: ['bayer leverkusen', 'leverkusen', 'werkself', 'b04'],
    ),
    _intl(
      id: 'union_berlin',
      name: 'Union Berlin',
      city: 'Berlin',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Union Red', 0xFFEB1923),
        TeamColor.hex('Union White', 0xFFFFFFFF),
      ],
      aliases: ['union berlin', 'fc union berlin', 'eisern union', 'die eisernen'],
    ),
    _intl(
      id: 'freiburg',
      name: 'SC Freiburg',
      city: 'Freiburg',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Freiburg Red', 0xFFE3000B),
        TeamColor.hex('Freiburg White', 0xFFFFFFFF),
        TeamColor.hex('Freiburg Black', 0xFF000000),
      ],
      aliases: ['freiburg', 'sc freiburg', 'breisgau-brasilianer'],
    ),
    _intl(
      id: 'eintracht_frankfurt',
      name: 'Eintracht Frankfurt',
      city: 'Frankfurt',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Frankfurt Black', 0xFF000000),
        TeamColor.hex('Frankfurt Red', 0xFFE1000F),
        TeamColor.hex('Frankfurt White', 0xFFFFFFFF),
      ],
      aliases: ['eintracht frankfurt', 'frankfurt', 'sge', 'die adler'],
    ),
    _intl(
      id: 'wolfsburg',
      name: 'VfL Wolfsburg',
      city: 'Wolfsburg',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Wolfsburg Green', 0xFF65B32E),
        TeamColor.hex('Wolfsburg White', 0xFFFFFFFF),
      ],
      aliases: ['wolfsburg', 'vfl wolfsburg', 'die wolfe', 'wolves wolfsburg'],
    ),
    _intl(
      id: 'mainz_05',
      name: 'Mainz 05',
      city: 'Mainz',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Mainz Red', 0xFFED1C24),
        TeamColor.hex('Mainz White', 0xFFFFFFFF),
      ],
      aliases: ['mainz 05', 'mainz', 'fsv mainz', 'nullfunfer', 'karnevalsverein'],
    ),
    _intl(
      id: 'monchengladbach',
      name: 'Borussia Monchengladbach',
      city: 'Monchengladbach',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Gladbach Black', 0xFF000000),
        TeamColor.hex('Gladbach White', 0xFFFFFFFF),
        TeamColor.hex('Gladbach Green', 0xFF1E9E51),
      ],
      aliases: ['monchengladbach', 'borussia monchengladbach', 'gladbach', 'bmg', 'die fohlen'],
    ),
    _intl(
      id: 'hoffenheim',
      name: 'TSG Hoffenheim',
      city: 'Sinsheim',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Hoffenheim Blue', 0xFF1961B5),
        TeamColor.hex('Hoffenheim White', 0xFFFFFFFF),
      ],
      aliases: ['hoffenheim', 'tsg hoffenheim', 'hoffe', 'tsg'],
    ),
    _intl(
      id: 'werder_bremen',
      name: 'Werder Bremen',
      city: 'Bremen',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Bremen Green', 0xFF1D9053),
        TeamColor.hex('Bremen White', 0xFFFFFFFF),
      ],
      aliases: ['werder bremen', 'bremen', 'werder', 'die gruen-weissen'],
    ),
    _intl(
      id: 'augsburg',
      name: 'FC Augsburg',
      city: 'Augsburg',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Augsburg Red', 0xFFBA3733),
        TeamColor.hex('Augsburg Green', 0xFF00543D),
        TeamColor.hex('Augsburg White', 0xFFFFFFFF),
      ],
      aliases: ['augsburg', 'fc augsburg', 'fca', 'fuggerstadter'],
    ),
    _intl(
      id: 'stuttgart',
      name: 'VfB Stuttgart',
      city: 'Stuttgart',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Stuttgart White', 0xFFFFFFFF),
        TeamColor.hex('Stuttgart Red', 0xFFE32219),
      ],
      aliases: ['stuttgart', 'vfb stuttgart', 'vfb', 'die schwaben'],
    ),
    _intl(
      id: 'heidenheim',
      name: '1. FC Heidenheim',
      city: 'Heidenheim',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Heidenheim Red', 0xFFE2001A),
        TeamColor.hex('Heidenheim Blue', 0xFF003CA6),
      ],
      aliases: ['heidenheim', 'fc heidenheim', 'fch'],
    ),
    _intl(
      id: 'darmstadt_98',
      name: 'Darmstadt 98',
      city: 'Darmstadt',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Darmstadt Blue', 0xFF004E9E),
        TeamColor.hex('Darmstadt White', 0xFFFFFFFF),
      ],
      aliases: ['darmstadt 98', 'darmstadt', 'sv darmstadt', 'die lilien'],
    ),
    _intl(
      id: 'cologne',
      name: '1. FC Koln',
      city: 'Cologne',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Koln Red', 0xFFED1C24),
        TeamColor.hex('Koln White', 0xFFFFFFFF),
      ],
      aliases: ['cologne', 'koln', 'fc koln', '1 fc koln', 'die geissboecke', 'effzeh'],
    ),
    _intl(
      id: 'bochum',
      name: 'VfL Bochum',
      city: 'Bochum',
      league: 'Bundesliga',
      country: 'Germany',
      colors: [
        TeamColor.hex('Bochum Blue', 0xFF005BA1),
        TeamColor.hex('Bochum White', 0xFFFFFFFF),
      ],
      aliases: ['bochum', 'vfl bochum', 'die unabsteigbaren'],
    ),
  ];

  // -----------------------------------------------------------------------
  // Serie A -- 20 teams
  // -----------------------------------------------------------------------
  static final List<UnifiedTeamEntry> _serieATeams = [
    _intl(
      id: 'inter_milan',
      name: 'Inter Milan',
      city: 'Milan',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Inter Blue', 0xFF010E80),
        TeamColor.hex('Inter Black', 0xFF000000),
      ],
      aliases: ['inter milan', 'inter', 'internazionale', 'nerazzurri', 'inter fc'],
    ),
    _intl(
      id: 'ac_milan',
      name: 'AC Milan',
      city: 'Milan',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Milan Red', 0xFFFB090B),
        TeamColor.hex('Milan Black', 0xFF000000),
      ],
      aliases: ['ac milan', 'milan', 'rossoneri', 'il diavolo'],
    ),
    _intl(
      id: 'juventus',
      name: 'Juventus',
      city: 'Turin',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Juve Black', 0xFF000000),
        TeamColor.hex('Juve White', 0xFFFFFFFF),
      ],
      aliases: ['juventus', 'juventus fc', 'juve', 'bianconeri', 'la vecchia signora'],
    ),
    _intl(
      id: 'napoli',
      name: 'SSC Napoli',
      city: 'Naples',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Napoli Blue', 0xFF12A0D7),
        TeamColor.hex('Napoli White', 0xFFFFFFFF),
      ],
      aliases: ['napoli', 'ssc napoli', 'partenopei', 'gli azzurri', 'naples'],
    ),
    _intl(
      id: 'roma',
      name: 'AS Roma',
      city: 'Rome',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Roma Maroon', 0xFF8E1F2F),
        TeamColor.hex('Roma Orange', 0xFFF0BC42),
      ],
      aliases: ['roma', 'as roma', 'giallorossi', 'la magica', 'rome'],
    ),
    _intl(
      id: 'lazio',
      name: 'SS Lazio',
      city: 'Rome',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Lazio Blue', 0xFF87D8F7),
        TeamColor.hex('Lazio White', 0xFFFFFFFF),
      ],
      aliases: ['lazio', 'ss lazio', 'biancocelesti', 'le aquile'],
    ),
    _intl(
      id: 'atalanta',
      name: 'Atalanta',
      city: 'Bergamo',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Atalanta Blue', 0xFF1E71B8),
        TeamColor.hex('Atalanta Black', 0xFF000000),
      ],
      aliases: ['atalanta', 'atalanta bc', 'la dea', 'orobici', 'bergamo'],
    ),
    _intl(
      id: 'fiorentina',
      name: 'ACF Fiorentina',
      city: 'Florence',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Fiorentina Purple', 0xFF482F8B),
        TeamColor.hex('Fiorentina White', 0xFFFFFFFF),
      ],
      aliases: ['fiorentina', 'acf fiorentina', 'la viola', 'gigliati', 'florence'],
    ),
    _intl(
      id: 'bologna',
      name: 'Bologna FC',
      city: 'Bologna',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Bologna Red', 0xFFA21C26),
        TeamColor.hex('Bologna Blue', 0xFF003171),
      ],
      aliases: ['bologna', 'bologna fc', 'rossoblù', 'felsinei'],
    ),
    _intl(
      id: 'torino',
      name: 'Torino FC',
      city: 'Turin',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Torino Maroon', 0xFF8B0000),
        TeamColor.hex('Torino White', 0xFFFFFFFF),
      ],
      aliases: ['torino', 'torino fc', 'il toro', 'granata'],
    ),
    _intl(
      id: 'monza',
      name: 'AC Monza',
      city: 'Monza',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Monza Red', 0xFFEE0000),
        TeamColor.hex('Monza White', 0xFFFFFFFF),
      ],
      aliases: ['monza', 'ac monza', 'biancorossi'],
    ),
    _intl(
      id: 'genoa',
      name: 'Genoa CFC',
      city: 'Genoa',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Genoa Red', 0xFFC4161C),
        TeamColor.hex('Genoa Navy', 0xFF1A2857),
      ],
      aliases: ['genoa', 'genoa cfc', 'grifone', 'il vecchio balordo'],
    ),
    _intl(
      id: 'cagliari',
      name: 'Cagliari Calcio',
      city: 'Cagliari',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Cagliari Red', 0xFFA51E36),
        TeamColor.hex('Cagliari Blue', 0xFF1F3D7C),
      ],
      aliases: ['cagliari', 'cagliari calcio', 'rossoblù cagliari', 'isolani'],
    ),
    _intl(
      id: 'empoli',
      name: 'Empoli FC',
      city: 'Empoli',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Empoli Blue', 0xFF00529F),
        TeamColor.hex('Empoli White', 0xFFFFFFFF),
      ],
      aliases: ['empoli', 'empoli fc', 'azzurri empoli'],
    ),
    _intl(
      id: 'verona',
      name: 'Hellas Verona',
      city: 'Verona',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Verona Blue', 0xFF003DA5),
        TeamColor.hex('Verona Yellow', 0xFFFFD100),
      ],
      aliases: ['verona', 'hellas verona', 'gialloblu', 'mastini'],
    ),
    _intl(
      id: 'udinese',
      name: 'Udinese Calcio',
      city: 'Udine',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Udinese Black', 0xFF000000),
        TeamColor.hex('Udinese White', 0xFFFFFFFF),
      ],
      aliases: ['udinese', 'udinese calcio', 'zebrette', 'friulani'],
    ),
    _intl(
      id: 'sassuolo',
      name: 'US Sassuolo',
      city: 'Sassuolo',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Sassuolo Green', 0xFF00A752),
        TeamColor.hex('Sassuolo Black', 0xFF000000),
      ],
      aliases: ['sassuolo', 'us sassuolo', 'neroverdi'],
    ),
    _intl(
      id: 'lecce',
      name: 'US Lecce',
      city: 'Lecce',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Lecce Yellow', 0xFFFFD700),
        TeamColor.hex('Lecce Red', 0xFFD7282F),
      ],
      aliases: ['lecce', 'us lecce', 'giallorossi lecce', 'salentini'],
    ),
    _intl(
      id: 'salernitana',
      name: 'US Salernitana',
      city: 'Salerno',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Salernitana Maroon', 0xFF7B1818),
        TeamColor.hex('Salernitana White', 0xFFFFFFFF),
      ],
      aliases: ['salernitana', 'us salernitana', 'granata salerno', 'ippocampi'],
    ),
    _intl(
      id: 'frosinone',
      name: 'Frosinone Calcio',
      city: 'Frosinone',
      league: 'Serie A',
      country: 'Italy',
      colors: [
        TeamColor.hex('Frosinone Yellow', 0xFFFFED00),
        TeamColor.hex('Frosinone Blue', 0xFF004B87),
      ],
      aliases: ['frosinone', 'frosinone calcio', 'canarini', 'ciociari'],
    ),
  ];
}
