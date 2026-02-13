import 'package:flutter/material.dart';

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
  });

  /// LED-optimised RGB arrays with colour-correction for LED strips.
  List<List<int>> get ledOptimizedRgb {
    return colors.map((c) => _optimizeForLed(c.r, c.g, c.b)).toList();
  }

  /// Extract the team-name portion from an official name by stripping the
  /// leading city. E.g. "Kansas City Chiefs" -> "Chiefs".
  static String extractTeamName(String officialName, String city) {
    if (officialName.toLowerCase().startsWith(city.toLowerCase())) {
      final remainder = officialName.substring(city.length).trim();
      if (remainder.isNotEmpty) return remainder;
    }
    return officialName;
  }

  /// Optimize a color for LED display.
  ///
  /// LEDs display colors differently than monitors. Key adjustments:
  /// 1. Reds with blue → appear pink/magenta, so strip blue
  /// 2. Blues with red → appear purple, so strip red
  /// 3. Dark blues → washed out, so boost
  /// 4. Whites → keep pure
  static List<int> _optimizeForLed(int r, int g, int b) {
    if (r > 240 && g > 240 && b > 240) return [255, 255, 255];

    if (b > 50 && r < 30 && g < 80 && b > r && b > g) {
      final boostFactor = 255.0 / b;
      return [0, (g * boostFactor * 0.3).round().clamp(0, 80), 255];
    }

    const dominantThreshold = 150;
    const noiseThreshold = 50;

    if (r > dominantThreshold && g < r * 0.6 && b < r * 0.6) {
      return [r, g > noiseThreshold ? g : 0, 0];
    }

    if (r > dominantThreshold && g > 60 && g < 220 && b < noiseThreshold) {
      return [r, g, 0];
    }

    if (b > 80 && b > r && b > g) {
      final cleanG = (g > b * 0.5) ? g : (g > noiseThreshold ? (g * 0.5).round() : 0);
      return [0, cleanG, b < 150 ? (b * 1.7).round().clamp(0, 255) : b];
    }

    if (g > dominantThreshold && r < g * 0.5 && b < g * 0.5) {
      return [0, g, 0];
    }

    return [r, g, b];
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

  /// Helper to create a US team entry compactly.
  static UnifiedTeamEntry _team({
    required String id,
    required String name,
    required String city,
    required String league,
    required List<TeamColor> colors,
    List<String> aliases = const [],
    List<int> suggestedEffects = const [12, 41, 65, 0],
    int defaultSpeed = 85,
    int defaultIntensity = 180,
  }) {
    return UnifiedTeamEntry(
      id: id,
      officialName: name,
      city: city,
      league: league,
      country: 'USA',
      aliases: aliases.map((a) => a.toLowerCase()).toList(),
      colors: colors,
      suggestedEffects: suggestedEffects,
      defaultSpeed: defaultSpeed,
      defaultIntensity: defaultIntensity,
    );
  }

  /// Master builder -- runs once and caches.
  static List<UnifiedTeamEntry> _buildAllTeams() {
    return [
      ..._nflTeams,
      ..._nbaTeams,
      ..._nhlTeams,
      ..._mlbTeams,
      ..._mlsTeams,
      ..._nwslTeams,
      ..._wnbaTeams,
      ..._uflTeams,
      ..._ncaaTeams,
      ..._eplTeams,
      ..._laLigaTeams,
      ..._bundesligaTeams,
      ..._serieATeams,
    ];
  }

  // =======================================================================
  //  NFL (32 teams)
  // =======================================================================
  static final List<UnifiedTeamEntry> _nflTeams = [
    // AFC EAST
    _team(id: 'bills', name: 'Buffalo Bills', city: 'Buffalo', league: 'NFL', colors: [TeamColor.hex('Bills Blue', 0xFF00338D), TeamColor.hex('Bills Red', 0xFFC60C30)], aliases: ['buffalo', 'buffalo bills', 'buf']),
    _team(id: 'dolphins', name: 'Miami Dolphins', city: 'Miami', league: 'NFL', colors: [TeamColor.hex('Dolphins Aqua', 0xFF008E97), TeamColor.hex('Dolphins Orange', 0xFFF58220)], aliases: ['miami', 'miami dolphins', 'mia', 'miami football']),
    _team(id: 'patriots', name: 'New England Patriots', city: 'New England', league: 'NFL', colors: [TeamColor.hex('Patriots Navy', 0xFF002244), TeamColor.hex('Patriots Red', 0xFFC60C30), TeamColor.hex('Patriots Silver', 0xFFB0B7BC)], aliases: ['new england', 'new england patriots', 'ne', 'pats', 'boston football']),
    _team(id: 'jets', name: 'New York Jets', city: 'New York', league: 'NFL', colors: [TeamColor.hex('Jets Green', 0xFF125740), TeamColor.hex('Jets White', 0xFFFFFFFF)], aliases: ['new york jets', 'ny jets', 'nyj']),
    // AFC NORTH
    _team(id: 'ravens', name: 'Baltimore Ravens', city: 'Baltimore', league: 'NFL', colors: [TeamColor.hex('Ravens Purple', 0xFF241773), TeamColor.hex('Ravens Black', 0xFF000000), TeamColor.hex('Ravens Gold', 0xFF9E7C0C)], aliases: ['baltimore', 'baltimore ravens', 'bal']),
    _team(id: 'bengals', name: 'Cincinnati Bengals', city: 'Cincinnati', league: 'NFL', colors: [TeamColor.hex('Bengals Orange', 0xFFFB4F14), TeamColor.hex('Bengals Black', 0xFF000000)], aliases: ['cincinnati', 'cincinnati bengals', 'cin', 'cincy']),
    _team(id: 'browns', name: 'Cleveland Browns', city: 'Cleveland', league: 'NFL', colors: [TeamColor.hex('Browns Orange', 0xFFFF3C00), TeamColor.hex('Browns Brown', 0xFF311D00)], aliases: ['cleveland', 'cleveland browns', 'cle']),
    _team(id: 'steelers', name: 'Pittsburgh Steelers', city: 'Pittsburgh', league: 'NFL', colors: [TeamColor.hex('Steelers Black', 0xFF101820), TeamColor.hex('Steelers Gold', 0xFFFFB612)], aliases: ['pittsburgh', 'pittsburgh steelers', 'pit', 'pitt']),
    // AFC SOUTH
    _team(id: 'texans', name: 'Houston Texans', city: 'Houston', league: 'NFL', colors: [TeamColor.hex('Texans Navy', 0xFF03202F), TeamColor.hex('Texans Red', 0xFFA71930)], aliases: ['houston', 'houston texans', 'hou', 'houston football']),
    _team(id: 'colts', name: 'Indianapolis Colts', city: 'Indianapolis', league: 'NFL', colors: [TeamColor.hex('Colts Blue', 0xFF002C5F), TeamColor.hex('Colts White', 0xFFFFFFFF)], aliases: ['indianapolis', 'indianapolis colts', 'ind', 'indy']),
    _team(id: 'jaguars', name: 'Jacksonville Jaguars', city: 'Jacksonville', league: 'NFL', colors: [TeamColor.hex('Jaguars Teal', 0xFF006778), TeamColor.hex('Jaguars Black', 0xFF101820), TeamColor.hex('Jaguars Gold', 0xFFD7A22A)], aliases: ['jacksonville', 'jacksonville jaguars', 'jax', 'jags']),
    _team(id: 'titans', name: 'Tennessee Titans', city: 'Tennessee', league: 'NFL', colors: [TeamColor.hex('Titans Navy', 0xFF0C2340), TeamColor.hex('Titans Blue', 0xFF4B92DB), TeamColor.hex('Titans Red', 0xFFC8102E)], aliases: ['tennessee', 'tennessee titans', 'ten', 'nashville football']),
    // AFC WEST
    _team(id: 'broncos', name: 'Denver Broncos', city: 'Denver', league: 'NFL', colors: [TeamColor.hex('Broncos Orange', 0xFFFB4F14), TeamColor.hex('Broncos Navy', 0xFF002244)], aliases: ['denver', 'denver broncos', 'den', 'denver football']),
    _team(id: 'chiefs', name: 'Kansas City Chiefs', city: 'Kansas City', league: 'NFL', colors: [TeamColor.hex('Chiefs Red', 0xFFE31837), TeamColor.hex('Chiefs Gold', 0xFFFFB81C)], aliases: ['kansas city', 'kansas city chiefs', 'kc', 'kc chiefs', 'mahomes']),
    _team(id: 'raiders', name: 'Las Vegas Raiders', city: 'Las Vegas', league: 'NFL', colors: [TeamColor.hex('Raiders Silver', 0xFFA5ACAF), TeamColor.hex('Raiders Black', 0xFF000000)], aliases: ['las vegas', 'las vegas raiders', 'lv', 'oakland raiders', 'oakland']),
    _team(id: 'chargers', name: 'Los Angeles Chargers', city: 'Los Angeles', league: 'NFL', colors: [TeamColor.hex('Chargers Blue', 0xFF0080C6), TeamColor.hex('Chargers Gold', 0xFFFFC20E)], aliases: ['la chargers', 'los angeles chargers', 'lac', 'san diego chargers']),
    // NFC EAST
    _team(id: 'cowboys', name: 'Dallas Cowboys', city: 'Dallas', league: 'NFL', colors: [TeamColor.hex('Cowboys Navy', 0xFF003594), TeamColor.hex('Cowboys Silver', 0xFF869397), TeamColor.hex('Cowboys White', 0xFFFFFFFF)], aliases: ['dallas', 'dallas cowboys', 'dal', 'americas team']),
    _team(id: 'giants_nfl', name: 'New York Giants', city: 'New York', league: 'NFL', colors: [TeamColor.hex('Giants Blue', 0xFF0B2265), TeamColor.hex('Giants Red', 0xFFA71930), TeamColor.hex('Giants White', 0xFFFFFFFF)], aliases: ['new york giants', 'ny giants', 'nyg', 'big blue']),
    _team(id: 'eagles', name: 'Philadelphia Eagles', city: 'Philadelphia', league: 'NFL', colors: [TeamColor.hex('Eagles Green', 0xFF004C54), TeamColor.hex('Eagles Silver', 0xFFA5ACAF), TeamColor.hex('Eagles Black', 0xFF000000)], aliases: ['philadelphia', 'philadelphia eagles', 'phi', 'philly', 'philly football']),
    _team(id: 'commanders', name: 'Washington Commanders', city: 'Washington', league: 'NFL', colors: [TeamColor.hex('Commanders Burgundy', 0xFF5A1414), TeamColor.hex('Commanders Gold', 0xFFFFB612)], aliases: ['washington', 'washington commanders', 'was', 'dc football', 'redskins']),
    // NFC NORTH
    _team(id: 'bears', name: 'Chicago Bears', city: 'Chicago', league: 'NFL', colors: [TeamColor.hex('Bears Navy', 0xFF0B162A), TeamColor.hex('Bears Orange', 0xFFC83803)], aliases: ['chicago', 'chicago bears', 'chi', 'da bears']),
    _team(id: 'lions', name: 'Detroit Lions', city: 'Detroit', league: 'NFL', colors: [TeamColor.hex('Lions Blue', 0xFF0076B6), TeamColor.hex('Lions Silver', 0xFFB0B7BC)], aliases: ['detroit', 'detroit lions', 'det']),
    _team(id: 'packers', name: 'Green Bay Packers', city: 'Green Bay', league: 'NFL', colors: [TeamColor.hex('Packers Green', 0xFF203731), TeamColor.hex('Packers Gold', 0xFFFFB612)], aliases: ['green bay', 'green bay packers', 'gb', 'wisconsin football']),
    _team(id: 'vikings', name: 'Minnesota Vikings', city: 'Minnesota', league: 'NFL', colors: [TeamColor.hex('Vikings Purple', 0xFF4F2683), TeamColor.hex('Vikings Gold', 0xFFFFC62F)], aliases: ['minnesota', 'minnesota vikings', 'min', 'skol']),
    // NFC SOUTH
    _team(id: 'falcons', name: 'Atlanta Falcons', city: 'Atlanta', league: 'NFL', colors: [TeamColor.hex('Falcons Red', 0xFFA71930), TeamColor.hex('Falcons Black', 0xFF000000)], aliases: ['atlanta', 'atlanta falcons', 'atl', 'dirty birds']),
    _team(id: 'panthers_nfl', name: 'Carolina Panthers', city: 'Carolina', league: 'NFL', colors: [TeamColor.hex('Panthers Blue', 0xFF0085CA), TeamColor.hex('Panthers Black', 0xFF101820), TeamColor.hex('Panthers Silver', 0xFFBFC0BF)], aliases: ['carolina', 'carolina panthers', 'car', 'charlotte football']),
    _team(id: 'saints', name: 'New Orleans Saints', city: 'New Orleans', league: 'NFL', colors: [TeamColor.hex('Saints Gold', 0xFFD3BC8D), TeamColor.hex('Saints Black', 0xFF101820)], aliases: ['new orleans', 'new orleans saints', 'no', 'nola', 'who dat']),
    _team(id: 'buccaneers', name: 'Tampa Bay Buccaneers', city: 'Tampa Bay', league: 'NFL', colors: [TeamColor.hex('Bucs Red', 0xFFD50A0A), TeamColor.hex('Bucs Pewter', 0xFF34302B), TeamColor.hex('Bucs Orange', 0xFFFF7900)], aliases: ['tampa bay', 'tampa bay buccaneers', 'tb', 'bucs', 'tampa']),
    // NFC WEST
    _team(id: 'cardinals_nfl', name: 'Arizona Cardinals', city: 'Arizona', league: 'NFL', colors: [TeamColor.hex('Cardinals Red', 0xFF97233F), TeamColor.hex('Cardinals White', 0xFFFFFFFF), TeamColor.hex('Cardinals Black', 0xFF000000)], aliases: ['arizona', 'arizona cardinals', 'ari', 'phoenix football']),
    _team(id: 'rams', name: 'Los Angeles Rams', city: 'Los Angeles', league: 'NFL', colors: [TeamColor.hex('Rams Blue', 0xFF003594), TeamColor.hex('Rams Yellow', 0xFFFFA300)], aliases: ['la rams', 'los angeles rams', 'lar', 'st louis rams']),
    _team(id: '49ers', name: 'San Francisco 49ers', city: 'San Francisco', league: 'NFL', colors: [TeamColor.hex('49ers Red', 0xFFAA0000), TeamColor.hex('49ers Gold', 0xFFB3995D)], aliases: ['san francisco', 'san francisco 49ers', 'sf', 'niners', 'bay area football']),
    _team(id: 'seahawks', name: 'Seattle Seahawks', city: 'Seattle', league: 'NFL', colors: [TeamColor.hex('Seahawks Blue', 0xFF002244), TeamColor.hex('Seahawks Green', 0xFF69BE28), TeamColor.hex('Seahawks Grey', 0xFFA5ACAF)], aliases: ['seattle', 'seattle seahawks', 'sea', '12s', 'hawks']),
  ];

  // =======================================================================
  //  NBA (30 teams)
  // =======================================================================
  static final List<UnifiedTeamEntry> _nbaTeams = [
    _team(id: 'celtics', name: 'Boston Celtics', city: 'Boston', league: 'NBA', colors: [TeamColor.hex('Celtics Green', 0xFF007A33), TeamColor.hex('Celtics Gold', 0xFFBA9653), TeamColor.hex('Celtics White', 0xFFFFFFFF)], aliases: ['boston', 'boston celtics', 'bos', 'boston basketball']),
    _team(id: 'nets', name: 'Brooklyn Nets', city: 'Brooklyn', league: 'NBA', colors: [TeamColor.hex('Nets Black', 0xFF000000), TeamColor.hex('Nets White', 0xFFFFFFFF)], aliases: ['brooklyn', 'brooklyn nets', 'bkn', 'new jersey nets']),
    _team(id: 'knicks', name: 'New York Knicks', city: 'New York', league: 'NBA', colors: [TeamColor.hex('Knicks Blue', 0xFF006BB6), TeamColor.hex('Knicks Orange', 0xFFF58426)], aliases: ['new york knicks', 'ny knicks', 'nyk', 'new york basketball']),
    _team(id: '76ers', name: 'Philadelphia 76ers', city: 'Philadelphia', league: 'NBA', colors: [TeamColor.hex('76ers Blue', 0xFF006BB6), TeamColor.hex('76ers Red', 0xFFED174C), TeamColor.hex('76ers White', 0xFFFFFFFF)], aliases: ['philadelphia 76ers', 'philly 76ers', 'phi', 'sixers', 'philadelphia basketball']),
    _team(id: 'raptors', name: 'Toronto Raptors', city: 'Toronto', league: 'NBA', colors: [TeamColor.hex('Raptors Red', 0xFFCE1141), TeamColor.hex('Raptors Black', 0xFF000000), TeamColor.hex('Raptors Silver', 0xFFA1A1A4)], aliases: ['toronto', 'toronto raptors', 'tor', 'canada basketball']),
    _team(id: 'bulls', name: 'Chicago Bulls', city: 'Chicago', league: 'NBA', colors: [TeamColor.hex('Bulls Red', 0xFFCE1141), TeamColor.hex('Bulls Black', 0xFF000000)], aliases: ['chicago bulls', 'chi bulls', 'chicago basketball']),
    _team(id: 'cavaliers', name: 'Cleveland Cavaliers', city: 'Cleveland', league: 'NBA', colors: [TeamColor.hex('Cavs Wine', 0xFF860038), TeamColor.hex('Cavs Gold', 0xFFFFB81C), TeamColor.hex('Cavs Navy', 0xFF041E42)], aliases: ['cleveland', 'cleveland cavaliers', 'cle', 'cavs', 'cleveland basketball']),
    _team(id: 'pistons', name: 'Detroit Pistons', city: 'Detroit', league: 'NBA', colors: [TeamColor.hex('Pistons Blue', 0xFF1D42BA), TeamColor.hex('Pistons Red', 0xFFC8102E)], aliases: ['detroit pistons', 'det', 'detroit basketball']),
    _team(id: 'pacers', name: 'Indiana Pacers', city: 'Indiana', league: 'NBA', colors: [TeamColor.hex('Pacers Navy', 0xFF002D62), TeamColor.hex('Pacers Gold', 0xFFFDBA21)], aliases: ['indiana', 'indiana pacers', 'ind', 'indy basketball']),
    _team(id: 'bucks', name: 'Milwaukee Bucks', city: 'Milwaukee', league: 'NBA', colors: [TeamColor.hex('Bucks Green', 0xFF00471B), TeamColor.hex('Bucks Cream', 0xFFEEE1C6)], aliases: ['milwaukee', 'milwaukee bucks', 'mil', 'fear the deer']),
    _team(id: 'hawks', name: 'Atlanta Hawks', city: 'Atlanta', league: 'NBA', colors: [TeamColor.hex('Hawks Red', 0xFFE03A3E), TeamColor.hex('Hawks White', 0xFFFFFFFF), TeamColor.hex('Hawks Black', 0xFF000000)], aliases: ['atlanta hawks', 'atl hawks', 'atlanta basketball']),
    _team(id: 'hornets', name: 'Charlotte Hornets', city: 'Charlotte', league: 'NBA', colors: [TeamColor.hex('Hornets Teal', 0xFF00788C), TeamColor.hex('Hornets Purple', 0xFF1D1160)], aliases: ['charlotte', 'charlotte hornets', 'cha', 'buzz city']),
    _team(id: 'heat', name: 'Miami Heat', city: 'Miami', league: 'NBA', colors: [TeamColor.hex('Heat Red', 0xFF98002E), TeamColor.hex('Heat Black', 0xFF000000), TeamColor.hex('Heat Yellow', 0xFFF9A01B)], aliases: ['miami heat', 'mia heat', 'miami basketball', 'heat culture']),
    _team(id: 'magic', name: 'Orlando Magic', city: 'Orlando', league: 'NBA', colors: [TeamColor.hex('Magic Blue', 0xFF0077C0), TeamColor.hex('Magic Black', 0xFF000000)], aliases: ['orlando', 'orlando magic', 'orl']),
    _team(id: 'wizards', name: 'Washington Wizards', city: 'Washington', league: 'NBA', colors: [TeamColor.hex('Wizards Navy', 0xFF002B5C), TeamColor.hex('Wizards Red', 0xFFE31837), TeamColor.hex('Wizards Silver', 0xFFC4CED4)], aliases: ['washington wizards', 'was', 'dc basketball', 'bullets']),
    _team(id: 'nuggets', name: 'Denver Nuggets', city: 'Denver', league: 'NBA', colors: [TeamColor.hex('Nuggets Navy', 0xFF0E2240), TeamColor.hex('Nuggets Gold', 0xFFFEC524), TeamColor.hex('Nuggets Red', 0xFF8B2131)], aliases: ['denver nuggets', 'den', 'denver basketball', 'mile high basketball']),
    _team(id: 'timberwolves', name: 'Minnesota Timberwolves', city: 'Minnesota', league: 'NBA', colors: [TeamColor.hex('Wolves Blue', 0xFF0C2340), TeamColor.hex('Wolves Green', 0xFF236192), TeamColor.hex('Wolves Grey', 0xFF9EA2A2)], aliases: ['minnesota timberwolves', 'min', 'wolves', 'twolves']),
    _team(id: 'thunder', name: 'Oklahoma City Thunder', city: 'Oklahoma City', league: 'NBA', colors: [TeamColor.hex('Thunder Blue', 0xFF007AC1), TeamColor.hex('Thunder Orange', 0xFFEF3B24), TeamColor.hex('Thunder Navy', 0xFF002D62)], aliases: ['oklahoma city', 'oklahoma city thunder', 'okc', 'okc thunder']),
    _team(id: 'blazers', name: 'Portland Trail Blazers', city: 'Portland', league: 'NBA', colors: [TeamColor.hex('Blazers Red', 0xFFE03A3E), TeamColor.hex('Blazers Black', 0xFF000000)], aliases: ['portland', 'portland trail blazers', 'por', 'rip city']),
    _team(id: 'jazz', name: 'Utah Jazz', city: 'Utah', league: 'NBA', colors: [TeamColor.hex('Jazz Navy', 0xFF002B5C), TeamColor.hex('Jazz Yellow', 0xFFF9A01B), TeamColor.hex('Jazz Green', 0xFF00471B)], aliases: ['utah', 'utah jazz', 'uta', 'salt lake basketball']),
    _team(id: 'warriors', name: 'Golden State Warriors', city: 'Golden State', league: 'NBA', colors: [TeamColor.hex('Warriors Blue', 0xFF1D428A), TeamColor.hex('Warriors Gold', 0xFFFFC72C)], aliases: ['golden state', 'golden state warriors', 'gsw', 'dubs', 'bay area basketball']),
    _team(id: 'clippers', name: 'Los Angeles Clippers', city: 'Los Angeles', league: 'NBA', colors: [TeamColor.hex('Clippers Red', 0xFFC8102E), TeamColor.hex('Clippers Blue', 0xFF1D428A), TeamColor.hex('Clippers White', 0xFFFFFFFF)], aliases: ['la clippers', 'los angeles clippers', 'lac']),
    _team(id: 'lakers', name: 'Los Angeles Lakers', city: 'Los Angeles', league: 'NBA', colors: [TeamColor.hex('Lakers Purple', 0xFF552583), TeamColor.hex('Lakers Gold', 0xFFFDB927)], aliases: ['los angeles lakers', 'la lakers', 'lal', 'showtime', 'lake show']),
    _team(id: 'suns', name: 'Phoenix Suns', city: 'Phoenix', league: 'NBA', colors: [TeamColor.hex('Suns Purple', 0xFF1D1160), TeamColor.hex('Suns Orange', 0xFFE56020)], aliases: ['phoenix', 'phoenix suns', 'phx', 'valley']),
    _team(id: 'kings', name: 'Sacramento Kings', city: 'Sacramento', league: 'NBA', colors: [TeamColor.hex('Kings Purple', 0xFF5A2D81), TeamColor.hex('Kings Silver', 0xFF63727A)], aliases: ['sacramento', 'sacramento kings', 'sac', 'sactown']),
    _team(id: 'mavericks', name: 'Dallas Mavericks', city: 'Dallas', league: 'NBA', colors: [TeamColor.hex('Mavs Blue', 0xFF00538C), TeamColor.hex('Mavs Navy', 0xFF002B5E), TeamColor.hex('Mavs Silver', 0xFFB8C4CA)], aliases: ['dallas mavericks', 'dal', 'mavs', 'dallas basketball']),
    _team(id: 'rockets', name: 'Houston Rockets', city: 'Houston', league: 'NBA', colors: [TeamColor.hex('Rockets Red', 0xFFCE1141), TeamColor.hex('Rockets Silver', 0xFFC4CED4)], aliases: ['houston rockets', 'hou', 'houston basketball', 'clutch city']),
    _team(id: 'grizzlies', name: 'Memphis Grizzlies', city: 'Memphis', league: 'NBA', colors: [TeamColor.hex('Grizzlies Navy', 0xFF12173F), TeamColor.hex('Grizzlies Blue', 0xFF5D76A9), TeamColor.hex('Grizzlies Gold', 0xFFF5B112)], aliases: ['memphis', 'memphis grizzlies', 'mem', 'grit grind']),
    _team(id: 'pelicans', name: 'New Orleans Pelicans', city: 'New Orleans', league: 'NBA', colors: [TeamColor.hex('Pelicans Navy', 0xFF0C2340), TeamColor.hex('Pelicans Red', 0xFFC8102E), TeamColor.hex('Pelicans Gold', 0xFF85714D)], aliases: ['new orleans pelicans', 'nop', 'nola basketball']),
    _team(id: 'spurs', name: 'San Antonio Spurs', city: 'San Antonio', league: 'NBA', colors: [TeamColor.hex('Spurs Silver', 0xFFC4CED4), TeamColor.hex('Spurs Black', 0xFF000000)], aliases: ['san antonio', 'san antonio spurs', 'sas', 'go spurs go']),
  ];

  // =======================================================================
  //  NHL (33 teams)
  // =======================================================================
  static final List<UnifiedTeamEntry> _nhlTeams = [
    _team(id: 'bruins', name: 'Boston Bruins', city: 'Boston', league: 'NHL', colors: [TeamColor.hex('Bruins Gold', 0xFFFFB81C), TeamColor.hex('Bruins Black', 0xFF000000)], aliases: ['boston bruins', 'bos bruins', 'boston hockey']),
    _team(id: 'sabres', name: 'Buffalo Sabres', city: 'Buffalo', league: 'NHL', colors: [TeamColor.hex('Sabres Navy', 0xFF002654), TeamColor.hex('Sabres Gold', 0xFFFCB514)], aliases: ['buffalo sabres', 'buf sabres', 'buffalo hockey']),
    _team(id: 'red_wings', name: 'Detroit Red Wings', city: 'Detroit', league: 'NHL', colors: [TeamColor.hex('Red Wings Red', 0xFFCE1126), TeamColor.hex('Red Wings White', 0xFFFFFFFF)], aliases: ['detroit red wings', 'det red wings', 'detroit hockey', 'wings']),
    _team(id: 'panthers_nhl', name: 'Florida Panthers', city: 'Florida', league: 'NHL', colors: [TeamColor.hex('Panthers Red', 0xFFC8102E), TeamColor.hex('Panthers Navy', 0xFF041E42), TeamColor.hex('Panthers Gold', 0xFFB9975B)], aliases: ['florida panthers', 'fla panthers', 'florida hockey']),
    _team(id: 'canadiens', name: 'Montreal Canadiens', city: 'Montreal', league: 'NHL', colors: [TeamColor.hex('Canadiens Red', 0xFFAF1E2D), TeamColor.hex('Canadiens Blue', 0xFF192168), TeamColor.hex('Canadiens White', 0xFFFFFFFF)], aliases: ['montreal canadiens', 'mtl', 'habs', 'montreal hockey']),
    _team(id: 'senators', name: 'Ottawa Senators', city: 'Ottawa', league: 'NHL', colors: [TeamColor.hex('Senators Red', 0xFFC52032), TeamColor.hex('Senators Black', 0xFF000000), TeamColor.hex('Senators Gold', 0xFFC69214)], aliases: ['ottawa senators', 'ott', 'sens', 'ottawa hockey']),
    _team(id: 'lightning', name: 'Tampa Bay Lightning', city: 'Tampa Bay', league: 'NHL', colors: [TeamColor.hex('Lightning Blue', 0xFF002868), TeamColor.hex('Lightning White', 0xFFFFFFFF)], aliases: ['tampa bay lightning', 'tbl', 'bolts', 'tampa hockey']),
    _team(id: 'maple_leafs', name: 'Toronto Maple Leafs', city: 'Toronto', league: 'NHL', colors: [TeamColor.hex('Leafs Blue', 0xFF00205B), TeamColor.hex('Leafs White', 0xFFFFFFFF)], aliases: ['toronto maple leafs', 'tor', 'leafs', 'toronto hockey']),
    _team(id: 'hurricanes', name: 'Carolina Hurricanes', city: 'Carolina', league: 'NHL', colors: [TeamColor.hex('Hurricanes Red', 0xFFCC0000), TeamColor.hex('Hurricanes Black', 0xFF000000), TeamColor.hex('Hurricanes White', 0xFFFFFFFF)], aliases: ['carolina hurricanes', 'car', 'canes', 'carolina hockey']),
    _team(id: 'blue_jackets', name: 'Columbus Blue Jackets', city: 'Columbus', league: 'NHL', colors: [TeamColor.hex('Blue Jackets Navy', 0xFF002654), TeamColor.hex('Blue Jackets Red', 0xFFCE1126), TeamColor.hex('Blue Jackets Silver', 0xFFA4A9AD)], aliases: ['columbus blue jackets', 'cbj', 'jackets', 'columbus hockey']),
    _team(id: 'devils', name: 'New Jersey Devils', city: 'New Jersey', league: 'NHL', colors: [TeamColor.hex('Devils Red', 0xFFCE1126), TeamColor.hex('Devils Black', 0xFF000000)], aliases: ['new jersey devils', 'njd', 'nj devils', 'jersey hockey']),
    _team(id: 'islanders', name: 'New York Islanders', city: 'New York', league: 'NHL', colors: [TeamColor.hex('Islanders Blue', 0xFF00539B), TeamColor.hex('Islanders Orange', 0xFFF47D30)], aliases: ['new york islanders', 'nyi', 'isles', 'long island hockey']),
    _team(id: 'rangers', name: 'New York Rangers', city: 'New York', league: 'NHL', colors: [TeamColor.hex('Rangers Blue', 0xFF0038A8), TeamColor.hex('Rangers Red', 0xFFCE1126), TeamColor.hex('Rangers White', 0xFFFFFFFF)], aliases: ['new york rangers', 'nyr', 'broadway blueshirts', 'nyc hockey']),
    _team(id: 'flyers', name: 'Philadelphia Flyers', city: 'Philadelphia', league: 'NHL', colors: [TeamColor.hex('Flyers Orange', 0xFFF74902), TeamColor.hex('Flyers Black', 0xFF000000)], aliases: ['philadelphia flyers', 'phi flyers', 'philly hockey']),
    _team(id: 'penguins', name: 'Pittsburgh Penguins', city: 'Pittsburgh', league: 'NHL', colors: [TeamColor.hex('Penguins Black', 0xFF000000), TeamColor.hex('Penguins Gold', 0xFFFCB514)], aliases: ['pittsburgh penguins', 'pit', 'pens', 'pittsburgh hockey']),
    _team(id: 'capitals', name: 'Washington Capitals', city: 'Washington', league: 'NHL', colors: [TeamColor.hex('Capitals Red', 0xFFC8102E), TeamColor.hex('Capitals Navy', 0xFF041E42), TeamColor.hex('Capitals White', 0xFFFFFFFF)], aliases: ['washington capitals', 'wsh', 'caps', 'dc hockey']),
    _team(id: 'coyotes', name: 'Arizona Coyotes', city: 'Arizona', league: 'NHL', colors: [TeamColor.hex('Coyotes Brick', 0xFF8C2633), TeamColor.hex('Coyotes Sand', 0xFFE2D6B5), TeamColor.hex('Coyotes Black', 0xFF111111)], aliases: ['arizona coyotes', 'ari coyotes', 'phoenix coyotes', 'arizona hockey']),
    _team(id: 'blackhawks', name: 'Chicago Blackhawks', city: 'Chicago', league: 'NHL', colors: [TeamColor.hex('Blackhawks Red', 0xFFCF0A2C), TeamColor.hex('Blackhawks Black', 0xFF000000)], aliases: ['chicago blackhawks', 'chi blackhawks', 'hawks hockey', 'chicago hockey']),
    _team(id: 'avalanche', name: 'Colorado Avalanche', city: 'Colorado', league: 'NHL', colors: [TeamColor.hex('Avalanche Burgundy', 0xFF6F263D), TeamColor.hex('Avalanche Blue', 0xFF236192), TeamColor.hex('Avalanche Silver', 0xFFA2AAAD)], aliases: ['colorado avalanche', 'col', 'avs', 'colorado hockey', 'denver hockey']),
    _team(id: 'stars', name: 'Dallas Stars', city: 'Dallas', league: 'NHL', colors: [TeamColor.hex('Stars Green', 0xFF006847), TeamColor.hex('Stars Black', 0xFF111111), TeamColor.hex('Stars Silver', 0xFF8F8F8C)], aliases: ['dallas stars', 'dal', 'dallas hockey']),
    _team(id: 'wild', name: 'Minnesota Wild', city: 'Minnesota', league: 'NHL', colors: [TeamColor.hex('Wild Green', 0xFF154734), TeamColor.hex('Wild Red', 0xFFA6192E), TeamColor.hex('Wild Wheat', 0xFFEECB9E)], aliases: ['minnesota wild', 'min wild', 'minnesota hockey']),
    _team(id: 'predators', name: 'Nashville Predators', city: 'Nashville', league: 'NHL', colors: [TeamColor.hex('Predators Gold', 0xFFFFB81C), TeamColor.hex('Predators Navy', 0xFF041E42)], aliases: ['nashville predators', 'nsh', 'preds', 'nashville hockey', 'smashville']),
    _team(id: 'blues', name: 'St. Louis Blues', city: 'St. Louis', league: 'NHL', colors: [TeamColor.hex('Blues Blue', 0xFF002F87), TeamColor.hex('Blues Gold', 0xFFFCB514), TeamColor.hex('Blues Navy', 0xFF041E42)], aliases: ['st louis blues', 'stl', 'st louis hockey']),
    _team(id: 'jets_nhl', name: 'Winnipeg Jets', city: 'Winnipeg', league: 'NHL', colors: [TeamColor.hex('Jets Navy', 0xFF041E42), TeamColor.hex('Jets Blue', 0xFF004C97), TeamColor.hex('Jets Silver', 0xFFA2AAAD)], aliases: ['winnipeg jets', 'wpg', 'winnipeg hockey']),
    _team(id: 'ducks', name: 'Anaheim Ducks', city: 'Anaheim', league: 'NHL', colors: [TeamColor.hex('Ducks Black', 0xFF000000), TeamColor.hex('Ducks Gold', 0xFFF47A38), TeamColor.hex('Ducks Orange', 0xFFB5985A)], aliases: ['anaheim ducks', 'ana', 'mighty ducks', 'anaheim hockey']),
    _team(id: 'flames', name: 'Calgary Flames', city: 'Calgary', league: 'NHL', colors: [TeamColor.hex('Flames Red', 0xFFC8102E), TeamColor.hex('Flames Gold', 0xFFF1BE48), TeamColor.hex('Flames Black', 0xFF111111)], aliases: ['calgary flames', 'cgy', 'calgary hockey']),
    _team(id: 'oilers', name: 'Edmonton Oilers', city: 'Edmonton', league: 'NHL', colors: [TeamColor.hex('Oilers Navy', 0xFF041E42), TeamColor.hex('Oilers Orange', 0xFFFF4C00)], aliases: ['edmonton oilers', 'edm', 'edmonton hockey', 'oil country']),
    _team(id: 'kings_nhl', name: 'Los Angeles Kings', city: 'Los Angeles', league: 'NHL', colors: [TeamColor.hex('Kings Black', 0xFF111111), TeamColor.hex('Kings Silver', 0xFFA2AAAD), TeamColor.hex('Kings White', 0xFFFFFFFF)], aliases: ['los angeles kings', 'lak', 'la kings', 'la hockey']),
    _team(id: 'sharks', name: 'San Jose Sharks', city: 'San Jose', league: 'NHL', colors: [TeamColor.hex('Sharks Teal', 0xFF006D75), TeamColor.hex('Sharks Black', 0xFF000000), TeamColor.hex('Sharks Orange', 0xFFE57200)], aliases: ['san jose sharks', 'sjs', 'san jose hockey', 'shark tank']),
    _team(id: 'kraken', name: 'Seattle Kraken', city: 'Seattle', league: 'NHL', colors: [TeamColor.hex('Kraken Blue', 0xFF001628), TeamColor.hex('Kraken Ice', 0xFF99D9D9), TeamColor.hex('Kraken Red', 0xFFE9072B)], aliases: ['seattle kraken', 'sea kraken', 'seattle hockey', 'release the kraken']),
    _team(id: 'canucks', name: 'Vancouver Canucks', city: 'Vancouver', league: 'NHL', colors: [TeamColor.hex('Canucks Blue', 0xFF00205B), TeamColor.hex('Canucks Green', 0xFF00843D), TeamColor.hex('Canucks White', 0xFFFFFFFF)], aliases: ['vancouver canucks', 'van', 'vancouver hockey']),
    _team(id: 'golden_knights', name: 'Vegas Golden Knights', city: 'Vegas', league: 'NHL', colors: [TeamColor.hex('Knights Gold', 0xFFB4975A), TeamColor.hex('Knights Steel', 0xFF333F42), TeamColor.hex('Knights Red', 0xFFC8102E)], aliases: ['vegas golden knights', 'vgk', 'vegas hockey', 'golden knights', 'knights']),
    _team(id: 'utah_hockey', name: 'Utah Hockey Club', city: 'Utah', league: 'NHL', colors: [TeamColor.hex('Utah Blue', 0xFF6CACE4), TeamColor.hex('Utah Black', 0xFF010101), TeamColor.hex('Utah White', 0xFFFFFFFF)], aliases: ['utah hockey club', 'utah hockey', 'utah nhl', 'salt lake hockey']),
  ];

  // =======================================================================
  //  MLB (30 teams)
  // =======================================================================
  static final List<UnifiedTeamEntry> _mlbTeams = [
    _team(id: 'orioles', name: 'Baltimore Orioles', city: 'Baltimore', league: 'MLB', colors: [TeamColor.hex('Orioles Orange', 0xFFDF4601), TeamColor.hex('Orioles Black', 0xFF000000)], aliases: ['baltimore orioles', 'bal orioles', 'baltimore baseball', 'os']),
    _team(id: 'red_sox', name: 'Boston Red Sox', city: 'Boston', league: 'MLB', colors: [TeamColor.hex('Red Sox Red', 0xFFBD3039), TeamColor.hex('Red Sox Navy', 0xFF0C2340)], aliases: ['boston red sox', 'bos', 'red sox', 'boston baseball', 'sox']),
    _team(id: 'yankees', name: 'New York Yankees', city: 'New York', league: 'MLB', colors: [TeamColor.hex('Yankees Navy', 0xFF003087), TeamColor.hex('Yankees White', 0xFFFFFFFF)], aliases: ['new york yankees', 'nyy', 'yankees', 'bronx bombers', 'ny baseball']),
    _team(id: 'rays', name: 'Tampa Bay Rays', city: 'Tampa Bay', league: 'MLB', colors: [TeamColor.hex('Rays Navy', 0xFF092C5C), TeamColor.hex('Rays Blue', 0xFF8FBCE6), TeamColor.hex('Rays Gold', 0xFFF5D130)], aliases: ['tampa bay rays', 'tb rays', 'rays', 'tampa baseball']),
    _team(id: 'blue_jays', name: 'Toronto Blue Jays', city: 'Toronto', league: 'MLB', colors: [TeamColor.hex('Blue Jays Blue', 0xFF134A8E), TeamColor.hex('Blue Jays Navy', 0xFF1D2D5C), TeamColor.hex('Blue Jays Red', 0xFFE8291C)], aliases: ['toronto blue jays', 'tor', 'blue jays', 'jays', 'toronto baseball']),
    _team(id: 'white_sox', name: 'Chicago White Sox', city: 'Chicago', league: 'MLB', colors: [TeamColor.hex('White Sox Black', 0xFF27251F), TeamColor.hex('White Sox Silver', 0xFFC4CED4)], aliases: ['chicago white sox', 'cws', 'white sox', 'south side']),
    _team(id: 'guardians', name: 'Cleveland Guardians', city: 'Cleveland', league: 'MLB', colors: [TeamColor.hex('Guardians Navy', 0xFF00385D), TeamColor.hex('Guardians Red', 0xFFE50022)], aliases: ['cleveland guardians', 'cle', 'guardians', 'cleveland baseball', 'indians']),
    _team(id: 'tigers', name: 'Detroit Tigers', city: 'Detroit', league: 'MLB', colors: [TeamColor.hex('Tigers Navy', 0xFF0C2340), TeamColor.hex('Tigers Orange', 0xFFFA4616)], aliases: ['detroit tigers', 'det', 'tigers', 'detroit baseball']),
    _team(id: 'royals', name: 'Kansas City Royals', city: 'Kansas City', league: 'MLB', colors: [TeamColor.hex('Royals Blue', 0xFF004687), TeamColor.hex('Royals Gold', 0xFFC09A5B), TeamColor.hex('Royals White', 0xFFFFFFFF)], aliases: ['kansas city royals', 'kc royals', 'royals', 'kc baseball']),
    _team(id: 'twins', name: 'Minnesota Twins', city: 'Minnesota', league: 'MLB', colors: [TeamColor.hex('Twins Navy', 0xFF002B5C), TeamColor.hex('Twins Red', 0xFFD31145), TeamColor.hex('Twins White', 0xFFFFFFFF)], aliases: ['minnesota twins', 'min twins', 'twins', 'minnesota baseball']),
    _team(id: 'astros', name: 'Houston Astros', city: 'Houston', league: 'MLB', colors: [TeamColor.hex('Astros Navy', 0xFF002D62), TeamColor.hex('Astros Orange', 0xFFEB6E1F)], aliases: ['houston astros', 'hou astros', 'astros', 'houston baseball', 'stros']),
    _team(id: 'angels', name: 'Los Angeles Angels', city: 'Los Angeles', league: 'MLB', colors: [TeamColor.hex('Angels Red', 0xFFBA0021), TeamColor.hex('Angels White', 0xFFFFFFFF)], aliases: ['los angeles angels', 'laa', 'angels', 'anaheim angels', 'halos']),
    _team(id: 'athletics', name: 'Oakland Athletics', city: 'Oakland', league: 'MLB', colors: [TeamColor.hex('Athletics Green', 0xFF003831), TeamColor.hex('Athletics Gold', 0xFFEFB21E)], aliases: ['oakland athletics', 'oak', 'athletics', 'oakland as', 'as']),
    _team(id: 'mariners', name: 'Seattle Mariners', city: 'Seattle', league: 'MLB', colors: [TeamColor.hex('Mariners Navy', 0xFF0C2C56), TeamColor.hex('Mariners Teal', 0xFF005C5C), TeamColor.hex('Mariners Silver', 0xFFC4CED4)], aliases: ['seattle mariners', 'sea mariners', 'mariners', 'seattle baseball', 'ms']),
    _team(id: 'rangers_mlb', name: 'Texas Rangers', city: 'Texas', league: 'MLB', colors: [TeamColor.hex('Rangers Blue', 0xFF003278), TeamColor.hex('Rangers Red', 0xFFC0111F), TeamColor.hex('Rangers White', 0xFFFFFFFF)], aliases: ['texas rangers', 'tex', 'rangers baseball', 'arlington baseball']),
    _team(id: 'braves', name: 'Atlanta Braves', city: 'Atlanta', league: 'MLB', colors: [TeamColor.hex('Braves Navy', 0xFF13274F), TeamColor.hex('Braves Red', 0xFFCE1141), TeamColor.hex('Braves White', 0xFFFFFFFF)], aliases: ['atlanta braves', 'atl braves', 'braves', 'atlanta baseball']),
    _team(id: 'marlins', name: 'Miami Marlins', city: 'Miami', league: 'MLB', colors: [TeamColor.hex('Marlins Black', 0xFF000000), TeamColor.hex('Marlins Blue', 0xFF0077C8), TeamColor.hex('Marlins Red', 0xFFEF3340)], aliases: ['miami marlins', 'mia', 'marlins', 'miami baseball', 'florida marlins']),
    _team(id: 'mets', name: 'New York Mets', city: 'New York', league: 'MLB', colors: [TeamColor.hex('Mets Blue', 0xFF002D72), TeamColor.hex('Mets Orange', 0xFFFF5910)], aliases: ['new york mets', 'nym', 'mets', 'queens baseball', 'amazins']),
    _team(id: 'phillies', name: 'Philadelphia Phillies', city: 'Philadelphia', league: 'MLB', colors: [TeamColor.hex('Phillies Red', 0xFFE81828), TeamColor.hex('Phillies Blue', 0xFF002D72)], aliases: ['philadelphia phillies', 'phi phillies', 'phillies', 'philly baseball']),
    _team(id: 'nationals', name: 'Washington Nationals', city: 'Washington', league: 'MLB', colors: [TeamColor.hex('Nationals Red', 0xFFAB0003), TeamColor.hex('Nationals Navy', 0xFF14225A), TeamColor.hex('Nationals White', 0xFFFFFFFF)], aliases: ['washington nationals', 'wsh', 'nationals', 'nats', 'dc baseball']),
    _team(id: 'cubs', name: 'Chicago Cubs', city: 'Chicago', league: 'MLB', colors: [TeamColor.hex('Cubs Blue', 0xFF0E3386), TeamColor.hex('Cubs Red', 0xFFCC3433)], aliases: ['chicago cubs', 'chc', 'cubs', 'cubbies', 'north side']),
    _team(id: 'reds', name: 'Cincinnati Reds', city: 'Cincinnati', league: 'MLB', colors: [TeamColor.hex('Reds Red', 0xFFC6011F), TeamColor.hex('Reds White', 0xFFFFFFFF)], aliases: ['cincinnati reds', 'cin', 'reds', 'redlegs', 'cincinnati baseball']),
    _team(id: 'brewers', name: 'Milwaukee Brewers', city: 'Milwaukee', league: 'MLB', colors: [TeamColor.hex('Brewers Navy', 0xFF12284B), TeamColor.hex('Brewers Gold', 0xFFFFC52F)], aliases: ['milwaukee brewers', 'mil brewers', 'brewers', 'brew crew', 'milwaukee baseball']),
    _team(id: 'pirates', name: 'Pittsburgh Pirates', city: 'Pittsburgh', league: 'MLB', colors: [TeamColor.hex('Pirates Black', 0xFF27251F), TeamColor.hex('Pirates Gold', 0xFFFDB827)], aliases: ['pittsburgh pirates', 'pit pirates', 'pirates', 'buccos', 'pittsburgh baseball']),
    _team(id: 'cardinals', name: 'St. Louis Cardinals', city: 'St. Louis', league: 'MLB', colors: [TeamColor.hex('Cardinals Red', 0xFFC41E3A), TeamColor.hex('Cardinals Navy', 0xFF0C2340), TeamColor.hex('Cardinals Yellow', 0xFFFEDB00)], aliases: ['st louis cardinals', 'stl cardinals', 'cardinals', 'cards', 'redbirds']),
    _team(id: 'diamondbacks', name: 'Arizona Diamondbacks', city: 'Arizona', league: 'MLB', colors: [TeamColor.hex('D-backs Red', 0xFFA71930), TeamColor.hex('D-backs Sand', 0xFFE3D4AD), TeamColor.hex('D-backs Black', 0xFF000000)], aliases: ['arizona diamondbacks', 'ari', 'diamondbacks', 'dbacks', 'snakes']),
    _team(id: 'rockies', name: 'Colorado Rockies', city: 'Colorado', league: 'MLB', colors: [TeamColor.hex('Rockies Purple', 0xFF33006F), TeamColor.hex('Rockies Black', 0xFF000000), TeamColor.hex('Rockies Silver', 0xFFC4CED4)], aliases: ['colorado rockies', 'col rockies', 'rockies', 'colorado baseball', 'rox']),
    _team(id: 'dodgers', name: 'Los Angeles Dodgers', city: 'Los Angeles', league: 'MLB', colors: [TeamColor.hex('Dodgers Blue', 0xFF005A9C), TeamColor.hex('Dodgers White', 0xFFFFFFFF)], aliases: ['los angeles dodgers', 'lad', 'dodgers', 'la baseball', 'boys in blue']),
    _team(id: 'padres', name: 'San Diego Padres', city: 'San Diego', league: 'MLB', colors: [TeamColor.hex('Padres Brown', 0xFF2F241D), TeamColor.hex('Padres Gold', 0xFFFFC425)], aliases: ['san diego padres', 'sd padres', 'padres', 'san diego baseball', 'friars']),
    _team(id: 'giants_mlb', name: 'San Francisco Giants', city: 'San Francisco', league: 'MLB', colors: [TeamColor.hex('Giants Orange', 0xFFFD5A1E), TeamColor.hex('Giants Black', 0xFF27251F), TeamColor.hex('Giants Cream', 0xFFEFD19F)], aliases: ['san francisco giants', 'sf giants', 'giants baseball', 'bay area baseball']),
  ];

  // =======================================================================
  //  MLS (30 teams)
  // =======================================================================
  static final List<UnifiedTeamEntry> _mlsTeams = [
    _team(id: 'atlanta_united', name: 'Atlanta United FC', city: 'Atlanta', league: 'MLS', colors: [TeamColor.hex('Atlanta Red', 0xFF80000A), TeamColor.hex('Atlanta Black', 0xFF000000), TeamColor.hex('Atlanta Gold', 0xFFA29061)], aliases: ['atlanta united', 'atl utd', 'atlanta soccer', 'five stripes']),
    _team(id: 'cf_montreal', name: 'CF Montréal', city: 'Montreal', league: 'MLS', colors: [TeamColor.hex('Montreal Blue', 0xFF0033A1), TeamColor.hex('Montreal Black', 0xFF000000)], aliases: ['cf montreal', 'montreal impact', 'montreal soccer']),
    _team(id: 'charlotte_fc', name: 'Charlotte FC', city: 'Charlotte', league: 'MLS', colors: [TeamColor.hex('Charlotte Blue', 0xFF1A85C8), TeamColor.hex('Charlotte White', 0xFFFFFFFF)], aliases: ['charlotte fc', 'charlotte soccer', 'crown']),
    _team(id: 'chicago_fire', name: 'Chicago Fire FC', city: 'Chicago', league: 'MLS', colors: [TeamColor.hex('Fire Red', 0xFFB81137), TeamColor.hex('Fire Blue', 0xFF7CCDEF)], aliases: ['chicago fire', 'chicago fire fc', 'chicago soccer']),
    _team(id: 'fc_cincinnati', name: 'FC Cincinnati', city: 'Cincinnati', league: 'MLS', colors: [TeamColor.hex('FCC Orange', 0xFFFE5000), TeamColor.hex('FCC Blue', 0xFF003087)], aliases: ['fc cincinnati', 'fcc', 'cincinnati soccer']),
    _team(id: 'columbus_crew', name: 'Columbus Crew', city: 'Columbus', league: 'MLS', colors: [TeamColor.hex('Crew Black', 0xFF000000), TeamColor.hex('Crew Gold', 0xFFFEF200)], aliases: ['columbus crew', 'crew', 'columbus soccer']),
    _team(id: 'dc_united', name: 'D.C. United', city: 'Washington', league: 'MLS', colors: [TeamColor.hex('DC Black', 0xFF000000), TeamColor.hex('DC Red', 0xFFEF3E42)], aliases: ['dc united', 'd.c. united', 'washington soccer', 'dc soccer']),
    _team(id: 'inter_miami', name: 'Inter Miami CF', city: 'Miami', league: 'MLS', colors: [TeamColor.hex('Miami Pink', 0xFFF5B5C8), TeamColor.hex('Miami Black', 0xFF000000)], aliases: ['inter miami', 'miami cf', 'miami soccer', 'herons']),
    _team(id: 'new_england_revolution', name: 'New England Revolution', city: 'New England', league: 'MLS', colors: [TeamColor.hex('Revs Navy', 0xFF0A2240), TeamColor.hex('Revs Red', 0xFFCE0E2D)], aliases: ['new england revolution', 'ne revolution', 'revs', 'boston soccer']),
    _team(id: 'nycfc', name: 'New York City FC', city: 'New York', league: 'MLS', colors: [TeamColor.hex('NYCFC Blue', 0xFF6CACE4), TeamColor.hex('NYCFC Navy', 0xFF041E42), TeamColor.hex('NYCFC Orange', 0xFFF15524)], aliases: ['nycfc', 'new york city fc', 'nyc fc', 'new york soccer']),
    _team(id: 'red_bulls', name: 'New York Red Bulls', city: 'New York', league: 'MLS', colors: [TeamColor.hex('Red Bulls Red', 0xFFED1E36), TeamColor.hex('Red Bulls Yellow', 0xFFFEDE00), TeamColor.hex('Red Bulls Navy', 0xFF0A2141)], aliases: ['new york red bulls', 'red bulls', 'nyrb', 'metrostars']),
    _team(id: 'orlando_city', name: 'Orlando City SC', city: 'Orlando', league: 'MLS', colors: [TeamColor.hex('Orlando Purple', 0xFF5B2B82), TeamColor.hex('Orlando White', 0xFFFFFFFF)], aliases: ['orlando city', 'orlando city sc', 'orlando soccer', 'lions']),
    _team(id: 'philadelphia_union', name: 'Philadelphia Union', city: 'Philadelphia', league: 'MLS', colors: [TeamColor.hex('Union Navy', 0xFF071B2C), TeamColor.hex('Union Gold', 0xFFB49759), TeamColor.hex('Union Blue', 0xFF2592C6)], aliases: ['philadelphia union', 'union', 'philly union', 'philadelphia soccer']),
    _team(id: 'toronto_fc', name: 'Toronto FC', city: 'Toronto', league: 'MLS', colors: [TeamColor.hex('TFC Red', 0xFFB81137), TeamColor.hex('TFC Grey', 0xFFA7A8AA)], aliases: ['toronto fc', 'tfc', 'toronto soccer', 'reds soccer']),
    _team(id: 'austin_fc', name: 'Austin FC', city: 'Austin', league: 'MLS', colors: [TeamColor.hex('Austin Verde', 0xFF00B140), TeamColor.hex('Austin Black', 0xFF000000)], aliases: ['austin fc', 'austin soccer', 'verde']),
    _team(id: 'colorado_rapids', name: 'Colorado Rapids', city: 'Colorado', league: 'MLS', colors: [TeamColor.hex('Rapids Burgundy', 0xFF862633), TeamColor.hex('Rapids Blue', 0xFF8BB8E8)], aliases: ['colorado rapids', 'rapids', 'colorado soccer', 'denver soccer']),
    _team(id: 'fc_dallas', name: 'FC Dallas', city: 'Dallas', league: 'MLS', colors: [TeamColor.hex('FCD Red', 0xFFE81F3E), TeamColor.hex('FCD Blue', 0xFF1164B4)], aliases: ['fc dallas', 'dallas soccer', 'fcd', 'hoops']),
    _team(id: 'houston_dynamo', name: 'Houston Dynamo FC', city: 'Houston', league: 'MLS', colors: [TeamColor.hex('Dynamo Orange', 0xFFF68712), TeamColor.hex('Dynamo White', 0xFFFFFFFF)], aliases: ['houston dynamo', 'dynamo', 'houston soccer']),
    _team(id: 'lafc', name: 'Los Angeles FC', city: 'Los Angeles', league: 'MLS', colors: [TeamColor.hex('LAFC Black', 0xFF000000), TeamColor.hex('LAFC Gold', 0xFFC39E6D)], aliases: ['lafc', 'los angeles fc', 'la fc', '3252']),
    _team(id: 'la_galaxy', name: 'LA Galaxy', city: 'Los Angeles', league: 'MLS', colors: [TeamColor.hex('Galaxy Navy', 0xFF00245D), TeamColor.hex('Galaxy Gold', 0xFFFDB913), TeamColor.hex('Galaxy White', 0xFFFFFFFF)], aliases: ['la galaxy', 'los angeles galaxy', 'galaxy', 'la soccer']),
    _team(id: 'minnesota_united', name: 'Minnesota United FC', city: 'Minnesota', league: 'MLS', colors: [TeamColor.hex('Loons Grey', 0xFF8CD2F4), TeamColor.hex('Loons Dark', 0xFF231F20)], aliases: ['minnesota united', 'mnufc', 'loons', 'minnesota soccer']),
    _team(id: 'nashville_sc', name: 'Nashville SC', city: 'Nashville', league: 'MLS', colors: [TeamColor.hex('Nashville Gold', 0xFFECE83A), TeamColor.hex('Nashville Navy', 0xFF1F1646)], aliases: ['nashville sc', 'nashville soccer', 'boys in gold']),
    _team(id: 'portland_timbers', name: 'Portland Timbers', city: 'Portland', league: 'MLS', colors: [TeamColor.hex('Timbers Green', 0xFF004812), TeamColor.hex('Timbers Gold', 0xFFD69A00)], aliases: ['portland timbers', 'timbers', 'portland soccer', 'rctid']),
    _team(id: 'real_salt_lake', name: 'Real Salt Lake', city: 'Salt Lake City', league: 'MLS', colors: [TeamColor.hex('RSL Claret', 0xFFB30838), TeamColor.hex('RSL Cobalt', 0xFF013A81), TeamColor.hex('RSL Gold', 0xFFF1AA00)], aliases: ['real salt lake', 'rsl', 'salt lake soccer', 'utah soccer']),
    _team(id: 'san_jose_earthquakes', name: 'San Jose Earthquakes', city: 'San Jose', league: 'MLS', colors: [TeamColor.hex('Quakes Blue', 0xFF0067B1), TeamColor.hex('Quakes Black', 0xFF000000), TeamColor.hex('Quakes Red', 0xFFE31837)], aliases: ['san jose earthquakes', 'earthquakes', 'quakes', 'san jose soccer']),
    _team(id: 'seattle_sounders', name: 'Seattle Sounders FC', city: 'Seattle', league: 'MLS', colors: [TeamColor.hex('Sounders Green', 0xFF5D9741), TeamColor.hex('Sounders Blue', 0xFF005595)], aliases: ['seattle sounders', 'sounders', 'seattle soccer', 'rave green']),
    _team(id: 'sporting_kc', name: 'Sporting Kansas City', city: 'Kansas City', league: 'MLS', colors: [TeamColor.hex('SKC Blue', 0xFF002F65), TeamColor.hex('SKC Light Blue', 0xFF91B0D5)], aliases: ['sporting kansas city', 'sporting kc', 'skc', 'kansas city soccer']),
    _team(id: 'st_louis_city', name: 'St. Louis CITY SC', city: 'St. Louis', league: 'MLS', colors: [TeamColor.hex('CITY Red', 0xFFD52B1E), TeamColor.hex('CITY Navy', 0xFF0F1E46)], aliases: ['st louis city', 'city sc', 'st louis soccer', 'stl soccer']),
    _team(id: 'vancouver_whitecaps', name: 'Vancouver Whitecaps FC', city: 'Vancouver', league: 'MLS', colors: [TeamColor.hex('Whitecaps Blue', 0xFF00245E), TeamColor.hex('Whitecaps White', 0xFFFFFFFF), TeamColor.hex('Whitecaps Grey', 0xFF97999B)], aliases: ['vancouver whitecaps', 'whitecaps', 'vancouver soccer']),
    _team(id: 'san_diego_fc', name: 'San Diego FC', city: 'San Diego', league: 'MLS', colors: [TeamColor.hex('SD Navy', 0xFF000033), TeamColor.hex('SD Turquoise', 0xFF33CCCC)], aliases: ['san diego fc', 'san diego soccer', 'sd fc']),
  ];

  // =======================================================================
  //  NWSL (14 teams)
  // =======================================================================
  static final List<UnifiedTeamEntry> _nwslTeams = [
    _team(id: 'angel_city', name: 'Angel City FC', city: 'Los Angeles', league: 'NWSL', colors: [TeamColor.hex('Angel City Sol Rose', 0xFFFF5C5C), TeamColor.hex('Angel City White', 0xFFFFFFFF), TeamColor.hex('Angel City Black', 0xFF000000)], aliases: ['angel city', 'angel city fc', 'acfc', 'la womens soccer']),
    _team(id: 'bay_fc', name: 'Bay FC', city: 'San Francisco', league: 'NWSL', colors: [TeamColor.hex('Bay Teal', 0xFF00A6A6), TeamColor.hex('Bay Black', 0xFF1E1E1E)], aliases: ['bay fc', 'san francisco nwsl', 'bay area womens soccer']),
    _team(id: 'chicago_red_stars', name: 'Chicago Red Stars', city: 'Chicago', league: 'NWSL', colors: [TeamColor.hex('Red Stars Navy', 0xFF003366), TeamColor.hex('Red Stars Red', 0xFFEF3E42)], aliases: ['chicago red stars', 'red stars', 'chicago womens soccer']),
    _team(id: 'houston_dash', name: 'Houston Dash', city: 'Houston', league: 'NWSL', colors: [TeamColor.hex('Dash Orange', 0xFFFF6B00), TeamColor.hex('Dash Blue', 0xFF00B5E2)], aliases: ['houston dash', 'dash', 'houston womens soccer']),
    _team(id: 'kansas_city_current', name: 'Kansas City Current', city: 'Kansas City', league: 'NWSL', colors: [TeamColor.hex('Current Teal', 0xFF00A3AD), TeamColor.hex('Current Red', 0xFFD7263D)], aliases: ['kansas city current', 'kc current', 'current', 'kc womens soccer']),
    _team(id: 'nj_ny_gotham', name: 'NJ/NY Gotham FC', city: 'New York', league: 'NWSL', colors: [TeamColor.hex('Gotham Black', 0xFF000000), TeamColor.hex('Gotham Gold', 0xFFF4C300)], aliases: ['gotham fc', 'nj ny gotham', 'gotham', 'sky blue fc']),
    _team(id: 'nc_courage', name: 'North Carolina Courage', city: 'North Carolina', league: 'NWSL', colors: [TeamColor.hex('Courage Navy', 0xFF003153), TeamColor.hex('Courage Blue', 0xFF85C1E9)], aliases: ['nc courage', 'courage', 'north carolina nwsl']),
    _team(id: 'orlando_pride', name: 'Orlando Pride', city: 'Orlando', league: 'NWSL', colors: [TeamColor.hex('Pride Purple', 0xFF5E2B7E), TeamColor.hex('Pride White', 0xFFFFFFFF)], aliases: ['orlando pride', 'pride', 'orlando nwsl']),
    _team(id: 'portland_thorns', name: 'Portland Thorns FC', city: 'Portland', league: 'NWSL', colors: [TeamColor.hex('Thorns Green', 0xFF004B28), TeamColor.hex('Thorns Gold', 0xFFC5B783)], aliases: ['portland thorns', 'thorns', 'portland nwsl']),
    _team(id: 'racing_louisville', name: 'Racing Louisville FC', city: 'Louisville', league: 'NWSL', colors: [TeamColor.hex('Racing Purple', 0xFF6C2E8D), TeamColor.hex('Racing Yellow', 0xFFFFD100)], aliases: ['racing louisville', 'racing', 'louisville nwsl']),
    _team(id: 'san_diego_wave', name: 'San Diego Wave FC', city: 'San Diego', league: 'NWSL', colors: [TeamColor.hex('Wave Blue', 0xFF003DA5), TeamColor.hex('Wave Red', 0xFFFF5733)], aliases: ['san diego wave', 'wave', 'san diego nwsl']),
    _team(id: 'seattle_reign', name: 'Seattle Reign FC', city: 'Seattle', league: 'NWSL', colors: [TeamColor.hex('Reign Blue', 0xFF0B3D91), TeamColor.hex('Reign Gold', 0xFFFFD700)], aliases: ['seattle reign', 'reign', 'seattle nwsl']),
    _team(id: 'utah_royals', name: 'Utah Royals FC', city: 'Utah', league: 'NWSL', colors: [TeamColor.hex('Royals Gold', 0xFFFFD700), TeamColor.hex('Royals Blue', 0xFF0B3D91)], aliases: ['utah royals', 'royals nwsl', 'utah nwsl']),
    _team(id: 'washington_spirit', name: 'Washington Spirit', city: 'Washington', league: 'NWSL', colors: [TeamColor.hex('Spirit Black', 0xFF0A0A0A), TeamColor.hex('Spirit Red', 0xFFAD1831)], aliases: ['washington spirit', 'spirit', 'dc nwsl']),
  ];

  // =======================================================================
  //  WNBA (13 teams)
  // =======================================================================
  static final List<UnifiedTeamEntry> _wnbaTeams = [
    _team(id: 'aces', name: 'Las Vegas Aces', city: 'Las Vegas', league: 'WNBA', colors: [TeamColor.hex('Aces Red', 0xFFC4032B), TeamColor.hex('Aces Black', 0xFF000000), TeamColor.hex('Aces Grey', 0xFF85714D)], aliases: ['las vegas aces', 'aces', 'vegas aces', 'lv aces']),
    _team(id: 'dream', name: 'Atlanta Dream', city: 'Atlanta', league: 'WNBA', colors: [TeamColor.hex('Dream Red', 0xFFE31837), TeamColor.hex('Dream Navy', 0xFF0C2340), TeamColor.hex('Dream Sky', 0xFF418FDE)], aliases: ['atlanta dream', 'dream', 'atlanta wnba']),
    _team(id: 'sky', name: 'Chicago Sky', city: 'Chicago', league: 'WNBA', colors: [TeamColor.hex('Sky Blue', 0xFF418FDE), TeamColor.hex('Sky Yellow', 0xFFFFCD00)], aliases: ['chicago sky', 'sky', 'chicago wnba']),
    _team(id: 'sun', name: 'Connecticut Sun', city: 'Connecticut', league: 'WNBA', colors: [TeamColor.hex('Sun Orange', 0xFFF05123), TeamColor.hex('Sun Blue', 0xFF0A2240)], aliases: ['connecticut sun', 'sun', 'ct sun', 'connecticut wnba']),
    _team(id: 'wings', name: 'Dallas Wings', city: 'Dallas', league: 'WNBA', colors: [TeamColor.hex('Wings Navy', 0xFF002B5C), TeamColor.hex('Wings Sky', 0xFFC4D600)], aliases: ['dallas wings', 'wings', 'dallas wnba']),
    _team(id: 'fever', name: 'Indiana Fever', city: 'Indiana', league: 'WNBA', colors: [TeamColor.hex('Fever Red', 0xFFE31837), TeamColor.hex('Fever Navy', 0xFF002D62), TeamColor.hex('Fever Gold', 0xFFFFCD00)], aliases: ['indiana fever', 'fever', 'indiana wnba', 'caitlin clark']),
    _team(id: 'sparks', name: 'Los Angeles Sparks', city: 'Los Angeles', league: 'WNBA', colors: [TeamColor.hex('Sparks Purple', 0xFF552583), TeamColor.hex('Sparks Gold', 0xFFFDB927)], aliases: ['los angeles sparks', 'sparks', 'la sparks', 'la wnba']),
    _team(id: 'lynx', name: 'Minnesota Lynx', city: 'Minnesota', league: 'WNBA', colors: [TeamColor.hex('Lynx Blue', 0xFF0C2340), TeamColor.hex('Lynx Green', 0xFF78BE21)], aliases: ['minnesota lynx', 'lynx', 'minnesota wnba']),
    _team(id: 'liberty', name: 'New York Liberty', city: 'New York', league: 'WNBA', colors: [TeamColor.hex('Liberty Seafoam', 0xFF6ECEB2), TeamColor.hex('Liberty Black', 0xFF000000), TeamColor.hex('Liberty Orange', 0xFFF15A24)], aliases: ['new york liberty', 'liberty', 'ny liberty', 'new york wnba']),
    _team(id: 'mercury', name: 'Phoenix Mercury', city: 'Phoenix', league: 'WNBA', colors: [TeamColor.hex('Mercury Orange', 0xFFE56020), TeamColor.hex('Mercury Purple', 0xFF201747)], aliases: ['phoenix mercury', 'mercury', 'phoenix wnba']),
    _team(id: 'storm', name: 'Seattle Storm', city: 'Seattle', league: 'WNBA', colors: [TeamColor.hex('Storm Green', 0xFF2C5234), TeamColor.hex('Storm Gold', 0xFFFFC72C)], aliases: ['seattle storm', 'storm', 'seattle wnba']),
    _team(id: 'mystics', name: 'Washington Mystics', city: 'Washington', league: 'WNBA', colors: [TeamColor.hex('Mystics Red', 0xFFE31837), TeamColor.hex('Mystics Navy', 0xFF002B5C), TeamColor.hex('Mystics White', 0xFFFFFFFF)], aliases: ['washington mystics', 'mystics', 'dc wnba', 'washington wnba']),
    _team(id: 'valkyries', name: 'Golden State Valkyries', city: 'Golden State', league: 'WNBA', colors: [TeamColor.hex('Valkyries Purple', 0xFF582C83), TeamColor.hex('Valkyries Gold', 0xFFDAA900), TeamColor.hex('Valkyries Sea', 0xFF00B2A9)], aliases: ['golden state valkyries', 'valkyries', 'gs valkyries', 'bay area wnba']),
  ];

  // =======================================================================
  //  UFL (8 teams)
  // =======================================================================
  static final List<UnifiedTeamEntry> _uflTeams = [
    _team(id: 'birmingham_stallions', name: 'Birmingham Stallions', city: 'Birmingham', league: 'UFL', colors: [TeamColor.hex('Stallions Red', 0xFFD22630), TeamColor.hex('Stallions Black', 0xFF000000)], aliases: ['birmingham stallions', 'stallions', 'birmingham football']),
    _team(id: 'dc_defenders', name: 'DC Defenders', city: 'Washington', league: 'UFL', colors: [TeamColor.hex('Defenders Red', 0xFFED1B2F), TeamColor.hex('Defenders Black', 0xFF000000), TeamColor.hex('Defenders White', 0xFFFFFFFF)], aliases: ['dc defenders', 'defenders', 'dc football ufl']),
    _team(id: 'houston_roughnecks', name: 'Houston Roughnecks', city: 'Houston', league: 'UFL', colors: [TeamColor.hex('Roughnecks Navy', 0xFF132448), TeamColor.hex('Roughnecks Red', 0xFFD22630)], aliases: ['houston roughnecks', 'roughnecks', 'houston football ufl']),
    _team(id: 'memphis_showboats', name: 'Memphis Showboats', city: 'Memphis', league: 'UFL', colors: [TeamColor.hex('Showboats Red', 0xFFE31837), TeamColor.hex('Showboats Blue', 0xFF00205B), TeamColor.hex('Showboats Gold', 0xFFFFB81C)], aliases: ['memphis showboats', 'showboats', 'memphis football']),
    _team(id: 'michigan_panthers', name: 'Michigan Panthers', city: 'Michigan', league: 'UFL', colors: [TeamColor.hex('Panthers Blue', 0xFF00205B), TeamColor.hex('Panthers Red', 0xFFE31837)], aliases: ['michigan panthers', 'panthers ufl', 'michigan football']),
    _team(id: 'san_antonio_brahmas', name: 'San Antonio Brahmas', city: 'San Antonio', league: 'UFL', colors: [TeamColor.hex('Brahmas Black', 0xFF000000), TeamColor.hex('Brahmas Red', 0xFFE31837)], aliases: ['san antonio brahmas', 'brahmas', 'san antonio football']),
    _team(id: 'seattle_sea_dragons', name: 'Seattle Sea Dragons', city: 'Seattle', league: 'UFL', colors: [TeamColor.hex('Sea Dragons Blue', 0xFF00205B), TeamColor.hex('Sea Dragons Green', 0xFF00A651)], aliases: ['seattle sea dragons', 'sea dragons', 'seattle football ufl']),
    _team(id: 'st_louis_battlehawks', name: 'St. Louis Battlehawks', city: 'St. Louis', league: 'UFL', colors: [TeamColor.hex('Battlehawks Blue', 0xFF00539F), TeamColor.hex('Battlehawks Red', 0xFFE31837)], aliases: ['st louis battlehawks', 'battlehawks', 'st louis football', 'kakaw']),
  ];

  // =======================================================================
  //  NCAA (50+ teams)
  // =======================================================================
  static final List<UnifiedTeamEntry> _ncaaTeams = [
    // SEC
    _team(id: 'alabama', name: 'Alabama Crimson Tide', city: 'Alabama', league: 'NCAA', colors: [TeamColor.hex('Alabama Crimson', 0xFF9E1B32), TeamColor.hex('Alabama White', 0xFFFFFFFF)], aliases: ['alabama', 'crimson tide', 'bama', 'roll tide', 'alabama football']),
    _team(id: 'auburn', name: 'Auburn Tigers', city: 'Auburn', league: 'NCAA', colors: [TeamColor.hex('Auburn Orange', 0xFFDD550C), TeamColor.hex('Auburn Navy', 0xFF03244D)], aliases: ['auburn', 'auburn tigers', 'war eagle', 'auburn football']),
    _team(id: 'georgia', name: 'Georgia Bulldogs', city: 'Georgia', league: 'NCAA', colors: [TeamColor.hex('Georgia Red', 0xFFBA0C2F), TeamColor.hex('Georgia Black', 0xFF000000)], aliases: ['georgia', 'georgia bulldogs', 'uga', 'dawgs', 'go dawgs']),
    _team(id: 'lsu', name: 'LSU Tigers', city: 'LSU', league: 'NCAA', colors: [TeamColor.hex('LSU Purple', 0xFF461D7C), TeamColor.hex('LSU Gold', 0xFFFDD023)], aliases: ['lsu', 'lsu tigers', 'geaux tigers', 'louisiana state']),
    _team(id: 'florida', name: 'Florida Gators', city: 'Florida', league: 'NCAA', colors: [TeamColor.hex('Florida Orange', 0xFFFA4616), TeamColor.hex('Florida Blue', 0xFF0021A5)], aliases: ['florida', 'florida gators', 'uf', 'gators', 'go gators']),
    _team(id: 'tennessee_vols', name: 'Tennessee Volunteers', city: 'Tennessee', league: 'NCAA', colors: [TeamColor.hex('Tennessee Orange', 0xFFFF8200), TeamColor.hex('Tennessee White', 0xFFFFFFFF)], aliases: ['tennessee', 'tennessee vols', 'vols', 'volunteers', 'rocky top']),
    _team(id: 'texas_am', name: 'Texas A&M Aggies', city: 'Texas A&M', league: 'NCAA', colors: [TeamColor.hex('Aggie Maroon', 0xFF500000), TeamColor.hex('Aggie White', 0xFFFFFFFF)], aliases: ['texas a&m', 'aggies', 'tamu', 'gig em', 'texas am football']),
    _team(id: 'ole_miss', name: 'Ole Miss Rebels', city: 'Ole Miss', league: 'NCAA', colors: [TeamColor.hex('Ole Miss Red', 0xFFCE1126), TeamColor.hex('Ole Miss Navy', 0xFF14213D)], aliases: ['ole miss', 'rebels', 'mississippi', 'hotty toddy']),
    _team(id: 'mississippi_state', name: 'Mississippi State Bulldogs', city: 'Mississippi State', league: 'NCAA', colors: [TeamColor.hex('MSU Maroon', 0xFF660000), TeamColor.hex('MSU White', 0xFFFFFFFF)], aliases: ['mississippi state', 'miss state', 'msu bulldogs', 'hail state']),
    _team(id: 'south_carolina', name: 'South Carolina Gamecocks', city: 'South Carolina', league: 'NCAA', colors: [TeamColor.hex('USC Garnet', 0xFF73000A), TeamColor.hex('USC Black', 0xFF000000)], aliases: ['south carolina', 'gamecocks', 'usc gamecocks', 'go cocks']),
    _team(id: 'kentucky', name: 'Kentucky Wildcats', city: 'Kentucky', league: 'NCAA', colors: [TeamColor.hex('Kentucky Blue', 0xFF0033A0), TeamColor.hex('Kentucky White', 0xFFFFFFFF)], aliases: ['kentucky', 'kentucky wildcats', 'uk', 'wildcats', 'big blue nation']),
    _team(id: 'arkansas', name: 'Arkansas Razorbacks', city: 'Arkansas', league: 'NCAA', colors: [TeamColor.hex('Arkansas Cardinal', 0xFF9D2235), TeamColor.hex('Arkansas White', 0xFFFFFFFF)], aliases: ['arkansas', 'razorbacks', 'hogs', 'woo pig', 'arkansas football']),
    _team(id: 'vanderbilt', name: 'Vanderbilt Commodores', city: 'Vanderbilt', league: 'NCAA', colors: [TeamColor.hex('Vandy Black', 0xFF000000), TeamColor.hex('Vandy Gold', 0xFFCFAE70)], aliases: ['vanderbilt', 'commodores', 'vandy', 'anchor down']),
    _team(id: 'missouri', name: 'Missouri Tigers', city: 'Missouri', league: 'NCAA', colors: [TeamColor.hex('Mizzou Black', 0xFF000000), TeamColor.hex('Mizzou Gold', 0xFFF1B82D)], aliases: ['missouri', 'mizzou', 'missouri tigers', 'mizzou football']),
    // BIG TEN
    _team(id: 'ohio_state', name: 'Ohio State Buckeyes', city: 'Ohio State', league: 'NCAA', colors: [TeamColor.hex('OSU Scarlet', 0xFFBB0000), TeamColor.hex('OSU Grey', 0xFF666666)], aliases: ['ohio state', 'buckeyes', 'osu', 'the ohio state', 'go bucks']),
    _team(id: 'michigan', name: 'Michigan Wolverines', city: 'Michigan', league: 'NCAA', colors: [TeamColor.hex('Michigan Maize', 0xFFFFCB05), TeamColor.hex('Michigan Blue', 0xFF00274C)], aliases: ['michigan', 'wolverines', 'umich', 'go blue', 'michigan football']),
    _team(id: 'penn_state', name: 'Penn State Nittany Lions', city: 'Penn State', league: 'NCAA', colors: [TeamColor.hex('PSU Blue', 0xFF041E42), TeamColor.hex('PSU White', 0xFFFFFFFF)], aliases: ['penn state', 'nittany lions', 'psu', 'we are']),
    _team(id: 'michigan_state', name: 'Michigan State Spartans', city: 'Michigan State', league: 'NCAA', colors: [TeamColor.hex('MSU Green', 0xFF18453B), TeamColor.hex('MSU White', 0xFFFFFFFF)], aliases: ['michigan state', 'spartans', 'msu', 'sparty', 'go green']),
    _team(id: 'wisconsin', name: 'Wisconsin Badgers', city: 'Wisconsin', league: 'NCAA', colors: [TeamColor.hex('Wisconsin Red', 0xFFC5050C), TeamColor.hex('Wisconsin White', 0xFFFFFFFF)], aliases: ['wisconsin', 'badgers', 'uw', 'on wisconsin']),
    _team(id: 'iowa', name: 'Iowa Hawkeyes', city: 'Iowa', league: 'NCAA', colors: [TeamColor.hex('Iowa Black', 0xFF000000), TeamColor.hex('Iowa Gold', 0xFFFFCD00)], aliases: ['iowa', 'hawkeyes', 'iowa hawkeyes', 'go hawks']),
    _team(id: 'nebraska', name: 'Nebraska Cornhuskers', city: 'Nebraska', league: 'NCAA', colors: [TeamColor.hex('Nebraska Scarlet', 0xFFE41C38), TeamColor.hex('Nebraska Cream', 0xFFF5F1E7)], aliases: ['nebraska', 'cornhuskers', 'huskers', 'gbr', 'go big red']),
    _team(id: 'purdue', name: 'Purdue Boilermakers', city: 'Purdue', league: 'NCAA', colors: [TeamColor.hex('Purdue Black', 0xFF000000), TeamColor.hex('Purdue Gold', 0xFFCFB991)], aliases: ['purdue', 'boilermakers', 'boilers', 'purdue football']),
    _team(id: 'indiana', name: 'Indiana Hoosiers', city: 'Indiana', league: 'NCAA', colors: [TeamColor.hex('Indiana Crimson', 0xFF990000), TeamColor.hex('Indiana Cream', 0xFFF5F1E7)], aliases: ['indiana', 'hoosiers', 'iu', 'indiana football']),
    _team(id: 'minnesota_gophers', name: 'Minnesota Golden Gophers', city: 'Minnesota', league: 'NCAA', colors: [TeamColor.hex('Minnesota Maroon', 0xFF7A0019), TeamColor.hex('Minnesota Gold', 0xFFFFCC33)], aliases: ['minnesota', 'gophers', 'golden gophers', 'ski u mah']),
    _team(id: 'northwestern', name: 'Northwestern Wildcats', city: 'Northwestern', league: 'NCAA', colors: [TeamColor.hex('Northwestern Purple', 0xFF4E2A84), TeamColor.hex('Northwestern White', 0xFFFFFFFF)], aliases: ['northwestern', 'wildcats nu', 'northwestern wildcats']),
    _team(id: 'illinois', name: 'Illinois Fighting Illini', city: 'Illinois', league: 'NCAA', colors: [TeamColor.hex('Illinois Orange', 0xFFE84A27), TeamColor.hex('Illinois Blue', 0xFF13294B)], aliases: ['illinois', 'illini', 'fighting illini', 'illinois football']),
    _team(id: 'rutgers', name: 'Rutgers Scarlet Knights', city: 'Rutgers', league: 'NCAA', colors: [TeamColor.hex('Rutgers Scarlet', 0xFFCC0033), TeamColor.hex('Rutgers White', 0xFFFFFFFF)], aliases: ['rutgers', 'scarlet knights', 'ru', 'rutgers football']),
    _team(id: 'maryland', name: 'Maryland Terrapins', city: 'Maryland', league: 'NCAA', colors: [TeamColor.hex('Maryland Red', 0xFFE03A3E), TeamColor.hex('Maryland Gold', 0xFFFFD520), TeamColor.hex('Maryland Black', 0xFF000000)], aliases: ['maryland', 'terrapins', 'terps', 'fear the turtle']),
    // BIG 12
    _team(id: 'texas', name: 'Texas Longhorns', city: 'Texas', league: 'NCAA', colors: [TeamColor.hex('Texas Orange', 0xFFBF5700), TeamColor.hex('Texas White', 0xFFFFFFFF)], aliases: ['texas', 'longhorns', 'ut', 'hook em', 'texas football']),
    _team(id: 'oklahoma', name: 'Oklahoma Sooners', city: 'Oklahoma', league: 'NCAA', colors: [TeamColor.hex('Oklahoma Crimson', 0xFF841617), TeamColor.hex('Oklahoma Cream', 0xFFFDF9D8)], aliases: ['oklahoma', 'sooners', 'ou', 'boomer sooner']),
    _team(id: 'oklahoma_state', name: 'Oklahoma State Cowboys', city: 'Oklahoma State', league: 'NCAA', colors: [TeamColor.hex('OSU Orange', 0xFFFF6600), TeamColor.hex('OSU Black', 0xFF000000)], aliases: ['oklahoma state', 'cowboys osu', 'osu cowboys', 'go pokes']),
    _team(id: 'tcu', name: 'TCU Horned Frogs', city: 'TCU', league: 'NCAA', colors: [TeamColor.hex('TCU Purple', 0xFF4D1979), TeamColor.hex('TCU White', 0xFFFFFFFF)], aliases: ['tcu', 'horned frogs', 'texas christian', 'go frogs']),
    _team(id: 'baylor', name: 'Baylor Bears', city: 'Baylor', league: 'NCAA', colors: [TeamColor.hex('Baylor Green', 0xFF154733), TeamColor.hex('Baylor Gold', 0xFFFFB81C)], aliases: ['baylor', 'bears', 'baylor bears', 'sic em']),
    _team(id: 'kansas_state', name: 'Kansas State Wildcats', city: 'Kansas State', league: 'NCAA', colors: [TeamColor.hex('K-State Purple', 0xFF512888), TeamColor.hex('K-State White', 0xFFFFFFFF)], aliases: ['kansas state', 'k-state', 'wildcats ksu', 'emaw']),
    _team(id: 'kansas', name: 'Kansas Jayhawks', city: 'Kansas', league: 'NCAA', colors: [TeamColor.hex('Kansas Blue', 0xFF0051BA), TeamColor.hex('Kansas Crimson', 0xFFE8000D)], aliases: ['kansas', 'jayhawks', 'ku', 'rock chalk']),
    _team(id: 'iowa_state', name: 'Iowa State Cyclones', city: 'Iowa State', league: 'NCAA', colors: [TeamColor.hex('ISU Cardinal', 0xFFC8102E), TeamColor.hex('ISU Gold', 0xFFF1BE48)], aliases: ['iowa state', 'cyclones', 'isu', 'go cyclones']),
    _team(id: 'west_virginia', name: 'West Virginia Mountaineers', city: 'West Virginia', league: 'NCAA', colors: [TeamColor.hex('WVU Blue', 0xFF002855), TeamColor.hex('WVU Gold', 0xFFEAAA00)], aliases: ['west virginia', 'mountaineers', 'wvu', 'lets go mountaineers']),
    _team(id: 'texas_tech', name: 'Texas Tech Red Raiders', city: 'Texas Tech', league: 'NCAA', colors: [TeamColor.hex('Tech Scarlet', 0xFFCC0000), TeamColor.hex('Tech Black', 0xFF000000)], aliases: ['texas tech', 'red raiders', 'ttu', 'wreck em']),
    // ACC
    _team(id: 'clemson', name: 'Clemson Tigers', city: 'Clemson', league: 'NCAA', colors: [TeamColor.hex('Clemson Orange', 0xFFF56600), TeamColor.hex('Clemson Purple', 0xFF522D80)], aliases: ['clemson', 'clemson tigers', 'go tigers', 'all in']),
    _team(id: 'florida_state', name: 'Florida State Seminoles', city: 'Florida State', league: 'NCAA', colors: [TeamColor.hex('FSU Garnet', 0xFF782F40), TeamColor.hex('FSU Gold', 0xFFCEB888)], aliases: ['florida state', 'seminoles', 'fsu', 'noles', 'go noles']),
    _team(id: 'miami_hurricanes', name: 'Miami Hurricanes', city: 'Miami', league: 'NCAA', colors: [TeamColor.hex('Miami Orange', 0xFFF47321), TeamColor.hex('Miami Green', 0xFF005030)], aliases: ['miami hurricanes', 'hurricanes', 'the u', 'canes']),
    _team(id: 'notre_dame', name: 'Notre Dame Fighting Irish', city: 'Notre Dame', league: 'NCAA', colors: [TeamColor.hex('ND Gold', 0xFFC99700), TeamColor.hex('ND Blue', 0xFF0C2340)], aliases: ['notre dame', 'fighting irish', 'nd', 'irish', 'go irish']),
    _team(id: 'nc_state', name: 'NC State Wolfpack', city: 'NC State', league: 'NCAA', colors: [TeamColor.hex('NC State Red', 0xFFCC0000), TeamColor.hex('NC State White', 0xFFFFFFFF)], aliases: ['nc state', 'wolfpack', 'ncsu', 'go pack']),
    _team(id: 'unc', name: 'North Carolina Tar Heels', city: 'North Carolina', league: 'NCAA', colors: [TeamColor.hex('Carolina Blue', 0xFF7BAFD4), TeamColor.hex('UNC White', 0xFFFFFFFF)], aliases: ['unc', 'tar heels', 'north carolina', 'carolina', 'go heels']),
    _team(id: 'duke', name: 'Duke Blue Devils', city: 'Duke', league: 'NCAA', colors: [TeamColor.hex('Duke Blue', 0xFF003087), TeamColor.hex('Duke White', 0xFFFFFFFF)], aliases: ['duke', 'blue devils', 'duke football']),
    _team(id: 'virginia_tech', name: 'Virginia Tech Hokies', city: 'Virginia Tech', league: 'NCAA', colors: [TeamColor.hex('VT Maroon', 0xFF660000), TeamColor.hex('VT Orange', 0xFFFF6600)], aliases: ['virginia tech', 'hokies', 'vt', 'go hokies']),
    _team(id: 'virginia', name: 'Virginia Cavaliers', city: 'Virginia', league: 'NCAA', colors: [TeamColor.hex('UVA Orange', 0xFFF84C1E), TeamColor.hex('UVA Navy', 0xFF232D4B)], aliases: ['virginia', 'cavaliers', 'uva', 'wahoos', 'hoos']),
    // PAC-12 / BIG 12
    _team(id: 'oregon', name: 'Oregon Ducks', city: 'Oregon', league: 'NCAA', colors: [TeamColor.hex('Oregon Green', 0xFF154733), TeamColor.hex('Oregon Yellow', 0xFFFEE123)], aliases: ['oregon', 'ducks', 'oregon ducks', 'go ducks', 'sco ducks']),
    _team(id: 'usc', name: 'USC Trojans', city: 'USC', league: 'NCAA', colors: [TeamColor.hex('USC Cardinal', 0xFF990000), TeamColor.hex('USC Gold', 0xFFFFC72C)], aliases: ['usc', 'trojans', 'usc trojans', 'fight on', 'southern california']),
    _team(id: 'ucla', name: 'UCLA Bruins', city: 'UCLA', league: 'NCAA', colors: [TeamColor.hex('UCLA Blue', 0xFF2D68C4), TeamColor.hex('UCLA Gold', 0xFFF2A900)], aliases: ['ucla', 'bruins', 'ucla bruins', 'go bruins']),
    _team(id: 'washington_huskies', name: 'Washington Huskies', city: 'Washington', league: 'NCAA', colors: [TeamColor.hex('UW Purple', 0xFF4B2E83), TeamColor.hex('UW Gold', 0xFFB7A57A)], aliases: ['washington', 'huskies', 'uw', 'washington huskies', 'go dawgs uw']),
    _team(id: 'arizona_wildcats', name: 'Arizona Wildcats', city: 'Arizona', league: 'NCAA', colors: [TeamColor.hex('Arizona Red', 0xFFCC0033), TeamColor.hex('Arizona Navy', 0xFF003366)], aliases: ['arizona', 'wildcats ua', 'arizona wildcats', 'bear down']),
    _team(id: 'arizona_state', name: 'Arizona State Sun Devils', city: 'Arizona State', league: 'NCAA', colors: [TeamColor.hex('ASU Maroon', 0xFF8C1D40), TeamColor.hex('ASU Gold', 0xFFFFC627)], aliases: ['arizona state', 'sun devils', 'asu', 'fork em']),
    _team(id: 'utah_utes', name: 'Utah Utes', city: 'Utah', league: 'NCAA', colors: [TeamColor.hex('Utah Red', 0xFFCC0000), TeamColor.hex('Utah White', 0xFFFFFFFF)], aliases: ['utah', 'utes', 'utah utes', 'go utes']),
    _team(id: 'colorado', name: 'Colorado Buffaloes', city: 'Colorado', league: 'NCAA', colors: [TeamColor.hex('CU Black', 0xFF000000), TeamColor.hex('CU Gold', 0xFFCFB87C)], aliases: ['colorado', 'buffaloes', 'buffs', 'cu', 'sko buffs']),
    _team(id: 'byu', name: 'BYU Cougars', city: 'BYU', league: 'NCAA', colors: [TeamColor.hex('BYU Blue', 0xFF002E5D), TeamColor.hex('BYU White', 0xFFFFFFFF)], aliases: ['byu', 'cougars byu', 'brigham young', 'rise and shout']),
    _team(id: 'cincinnati_bearcats', name: 'Cincinnati Bearcats', city: 'Cincinnati', league: 'NCAA', colors: [TeamColor.hex('UC Red', 0xFFE00122), TeamColor.hex('UC Black', 0xFF000000)], aliases: ['cincinnati bearcats', 'bearcats', 'uc', 'go bearcats']),
    _team(id: 'ucf', name: 'UCF Knights', city: 'UCF', league: 'NCAA', colors: [TeamColor.hex('UCF Black', 0xFF000000), TeamColor.hex('UCF Gold', 0xFFBA9B37)], aliases: ['ucf', 'knights', 'ucf knights', 'charge on']),
    _team(id: 'houston_cougars', name: 'Houston Cougars', city: 'Houston', league: 'NCAA', colors: [TeamColor.hex('Houston Red', 0xFFC8102E), TeamColor.hex('Houston White', 0xFFFFFFFF)], aliases: ['houston cougars', 'cougars uh', 'uh', 'go coogs']),
  ];

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
          UnifiedTeamEntry.extractTeamName(team.officialName, team.city);
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
