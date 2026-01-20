import 'package:flutter/material.dart';
import 'package:nexgen_command/features/patterns/canonical_palettes.dart';

/// MLB Team colors with official HEX codes

class MlbTeamPalettes {
  MlbTeamPalettes._();

  /// MLB Teams (30 teams) - Official colors from MLB brand guidelines
  static final Map<String, CanonicalTheme> mlbTeams = {
    // AL EAST
    'orioles': CanonicalTheme(
      id: 'orioles',
      displayName: 'Baltimore Orioles',
      description: 'Official Orioles orange & black',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Orioles Orange', 0xFFDF4601),
        ThemeColor.hex('Orioles Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['baltimore orioles', 'bal orioles', 'baltimore baseball', 'os'],
    ),

    'red_sox': CanonicalTheme(
      id: 'red_sox',
      displayName: 'Boston Red Sox',
      description: 'Official Red Sox red & navy',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Red Sox Red', 0xFFBD3039),
        ThemeColor.hex('Red Sox Navy', 0xFF0C2340),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['boston red sox', 'bos', 'red sox', 'boston baseball', 'sox'],
    ),

    'yankees': CanonicalTheme(
      id: 'yankees',
      displayName: 'New York Yankees',
      description: 'Official Yankees navy & white',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Yankees Navy', 0xFF003087),
        ThemeColor.hex('Yankees White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new york yankees', 'nyy', 'yankees', 'bronx bombers', 'ny baseball'],
    ),

    'rays': CanonicalTheme(
      id: 'rays',
      displayName: 'Tampa Bay Rays',
      description: 'Official Rays navy, light blue & gold',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Rays Navy', 0xFF092C5C),
        ThemeColor.hex('Rays Blue', 0xFF8FBCE6),
        ThemeColor.hex('Rays Gold', 0xFFF5D130),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['tampa bay rays', 'tb rays', 'rays', 'tampa baseball'],
    ),

    'blue_jays': CanonicalTheme(
      id: 'blue_jays',
      displayName: 'Toronto Blue Jays',
      description: 'Official Blue Jays blue & navy',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Blue Jays Blue', 0xFF134A8E),
        ThemeColor.hex('Blue Jays Navy', 0xFF1D2D5C),
        ThemeColor.hex('Blue Jays Red', 0xFFE8291C),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['toronto blue jays', 'tor', 'blue jays', 'jays', 'toronto baseball'],
    ),

    // AL CENTRAL
    'white_sox': CanonicalTheme(
      id: 'white_sox',
      displayName: 'Chicago White Sox',
      description: 'Official White Sox black & silver',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('White Sox Black', 0xFF27251F),
        ThemeColor.hex('White Sox Silver', 0xFFC4CED4),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['chicago white sox', 'cws', 'white sox', 'south side'],
    ),

    'guardians': CanonicalTheme(
      id: 'guardians',
      displayName: 'Cleveland Guardians',
      description: 'Official Guardians navy & red',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Guardians Navy', 0xFF00385D),
        ThemeColor.hex('Guardians Red', 0xFFE50022),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['cleveland guardians', 'cle', 'guardians', 'cleveland baseball', 'indians'],
    ),

    'tigers': CanonicalTheme(
      id: 'tigers',
      displayName: 'Detroit Tigers',
      description: 'Official Tigers navy & orange',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Tigers Navy', 0xFF0C2340),
        ThemeColor.hex('Tigers Orange', 0xFFFA4616),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['detroit tigers', 'det', 'tigers', 'detroit baseball'],
    ),

    'royals': CanonicalTheme(
      id: 'royals',
      displayName: 'Kansas City Royals',
      description: 'Official Royals blue & white',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Royals Blue', 0xFF004687),
        ThemeColor.hex('Royals Gold', 0xFFC09A5B),
        ThemeColor.hex('Royals White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['kansas city royals', 'kc royals', 'royals', 'kc baseball'],
    ),

    'twins': CanonicalTheme(
      id: 'twins',
      displayName: 'Minnesota Twins',
      description: 'Official Twins navy, red & white',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Twins Navy', 0xFF002B5C),
        ThemeColor.hex('Twins Red', 0xFFD31145),
        ThemeColor.hex('Twins White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['minnesota twins', 'min twins', 'twins', 'minnesota baseball'],
    ),

    // AL WEST
    'astros': CanonicalTheme(
      id: 'astros',
      displayName: 'Houston Astros',
      description: 'Official Astros navy & orange',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Astros Navy', 0xFF002D62),
        ThemeColor.hex('Astros Orange', 0xFFEB6E1F),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['houston astros', 'hou astros', 'astros', 'houston baseball', 'stros'],
    ),

    'angels': CanonicalTheme(
      id: 'angels',
      displayName: 'Los Angeles Angels',
      description: 'Official Angels red & white',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Angels Red', 0xFFBA0021),
        ThemeColor.hex('Angels White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['los angeles angels', 'laa', 'angels', 'anaheim angels', 'halos'],
    ),

    'athletics': CanonicalTheme(
      id: 'athletics',
      displayName: 'Oakland Athletics',
      description: 'Official Athletics green & gold',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Athletics Green', 0xFF003831),
        ThemeColor.hex('Athletics Gold', 0xFFEFB21E),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['oakland athletics', 'oak', 'athletics', 'oakland as', 'as'],
    ),

    'mariners': CanonicalTheme(
      id: 'mariners',
      displayName: 'Seattle Mariners',
      description: 'Official Mariners navy, teal & silver',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Mariners Navy', 0xFF0C2C56),
        ThemeColor.hex('Mariners Teal', 0xFF005C5C),
        ThemeColor.hex('Mariners Silver', 0xFFC4CED4),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['seattle mariners', 'sea mariners', 'mariners', 'seattle baseball', 'ms'],
    ),

    'rangers_mlb': CanonicalTheme(
      id: 'rangers_mlb',
      displayName: 'Texas Rangers',
      description: 'Official Rangers blue, red & white',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Rangers Blue', 0xFF003278),
        ThemeColor.hex('Rangers Red', 0xFFC0111F),
        ThemeColor.hex('Rangers White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['texas rangers', 'tex', 'rangers baseball', 'arlington baseball'],
    ),

    // NL EAST
    'braves': CanonicalTheme(
      id: 'braves',
      displayName: 'Atlanta Braves',
      description: 'Official Braves navy, red & white',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Braves Navy', 0xFF13274F),
        ThemeColor.hex('Braves Red', 0xFFCE1141),
        ThemeColor.hex('Braves White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['atlanta braves', 'atl braves', 'braves', 'atlanta baseball'],
    ),

    'marlins': CanonicalTheme(
      id: 'marlins',
      displayName: 'Miami Marlins',
      description: 'Official Marlins black, blue, red & yellow',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Marlins Black', 0xFF000000),
        ThemeColor.hex('Marlins Blue', 0xFF0077C8),
        ThemeColor.hex('Marlins Red', 0xFFEF3340),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['miami marlins', 'mia', 'marlins', 'miami baseball', 'florida marlins'],
    ),

    'mets': CanonicalTheme(
      id: 'mets',
      displayName: 'New York Mets',
      description: 'Official Mets blue & orange',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Mets Blue', 0xFF002D72),
        ThemeColor.hex('Mets Orange', 0xFFFF5910),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new york mets', 'nym', 'mets', 'queens baseball', 'amazins'],
    ),

    'phillies': CanonicalTheme(
      id: 'phillies',
      displayName: 'Philadelphia Phillies',
      description: 'Official Phillies red & blue',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Phillies Red', 0xFFE81828),
        ThemeColor.hex('Phillies Blue', 0xFF002D72),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['philadelphia phillies', 'phi phillies', 'phillies', 'philly baseball'],
    ),

    'nationals': CanonicalTheme(
      id: 'nationals',
      displayName: 'Washington Nationals',
      description: 'Official Nationals red, navy & white',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Nationals Red', 0xFFAB0003),
        ThemeColor.hex('Nationals Navy', 0xFF14225A),
        ThemeColor.hex('Nationals White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['washington nationals', 'wsh', 'nationals', 'nats', 'dc baseball'],
    ),

    // NL CENTRAL
    'cubs': CanonicalTheme(
      id: 'cubs',
      displayName: 'Chicago Cubs',
      description: 'Official Cubs blue & red',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Cubs Blue', 0xFF0E3386),
        ThemeColor.hex('Cubs Red', 0xFFCC3433),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['chicago cubs', 'chc', 'cubs', 'cubbies', 'north side'],
    ),

    'reds': CanonicalTheme(
      id: 'reds',
      displayName: 'Cincinnati Reds',
      description: 'Official Reds red & white',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Reds Red', 0xFFC6011F),
        ThemeColor.hex('Reds White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['cincinnati reds', 'cin', 'reds', 'redlegs', 'cincinnati baseball'],
    ),

    'brewers': CanonicalTheme(
      id: 'brewers',
      displayName: 'Milwaukee Brewers',
      description: 'Official Brewers navy & gold',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Brewers Navy', 0xFF12284B),
        ThemeColor.hex('Brewers Gold', 0xFFFFC52F),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['milwaukee brewers', 'mil brewers', 'brewers', 'brew crew', 'milwaukee baseball'],
    ),

    'pirates': CanonicalTheme(
      id: 'pirates',
      displayName: 'Pittsburgh Pirates',
      description: 'Official Pirates black & gold',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Pirates Black', 0xFF27251F),
        ThemeColor.hex('Pirates Gold', 0xFFFDB827),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['pittsburgh pirates', 'pit pirates', 'pirates', 'buccos', 'pittsburgh baseball'],
    ),

    'cardinals': CanonicalTheme(
      id: 'cardinals',
      displayName: 'St. Louis Cardinals',
      description: 'Official Cardinals red, navy & white',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Cardinals Red', 0xFFC41E3A),
        ThemeColor.hex('Cardinals Navy', 0xFF0C2340),
        ThemeColor.hex('Cardinals Yellow', 0xFFFEDB00),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['st louis cardinals', 'stl cardinals', 'cardinals', 'cards', 'redbirds'],
    ),

    // NL WEST
    'diamondbacks': CanonicalTheme(
      id: 'diamondbacks',
      displayName: 'Arizona Diamondbacks',
      description: 'Official D-backs red, sand & black',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('D-backs Red', 0xFFA71930),
        ThemeColor.hex('D-backs Sand', 0xFFE3D4AD),
        ThemeColor.hex('D-backs Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['arizona diamondbacks', 'ari', 'diamondbacks', 'dbacks', 'snakes'],
    ),

    'rockies': CanonicalTheme(
      id: 'rockies',
      displayName: 'Colorado Rockies',
      description: 'Official Rockies purple, black & silver',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Rockies Purple', 0xFF33006F),
        ThemeColor.hex('Rockies Black', 0xFF000000),
        ThemeColor.hex('Rockies Silver', 0xFFC4CED4),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['colorado rockies', 'col rockies', 'rockies', 'colorado baseball', 'rox'],
    ),

    'dodgers': CanonicalTheme(
      id: 'dodgers',
      displayName: 'Los Angeles Dodgers',
      description: 'Official Dodgers blue & white',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Dodgers Blue', 0xFF005A9C),
        ThemeColor.hex('Dodgers White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['los angeles dodgers', 'lad', 'dodgers', 'la baseball', 'boys in blue'],
    ),

    'padres': CanonicalTheme(
      id: 'padres',
      displayName: 'San Diego Padres',
      description: 'Official Padres brown & gold',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Padres Brown', 0xFF2F241D),
        ThemeColor.hex('Padres Gold', 0xFFFFC425),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['san diego padres', 'sd padres', 'padres', 'san diego baseball', 'friars'],
    ),

    'giants_mlb': CanonicalTheme(
      id: 'giants_mlb',
      displayName: 'San Francisco Giants',
      description: 'Official Giants orange & black',
      icon: Icons.sports_baseball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Giants Orange', 0xFFFD5A1E),
        ThemeColor.hex('Giants Black', 0xFF27251F),
        ThemeColor.hex('Giants Cream', 0xFFEFD19F),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['san francisco giants', 'sf giants', 'giants baseball', 'bay area baseball'],
    ),
  };

  /// Get all MLB teams
  static List<CanonicalTheme> get allMlbTeams => mlbTeams.values.toList();
}
