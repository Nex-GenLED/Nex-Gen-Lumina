import 'package:flutter/material.dart';
import 'package:nexgen_command/features/patterns/canonical_palettes.dart';

/// Comprehensive sports team color database with official HEX codes.
/// All colors sourced from official team brand guidelines.

class SportsTeamPalettes {
  SportsTeamPalettes._();

  /// NFL Teams (32 teams) - Official colors from NFL brand guidelines
  static final Map<String, CanonicalTheme> nflTeams = {
    // AFC EAST
    'bills': CanonicalTheme(
      id: 'bills',
      displayName: 'Buffalo Bills',
      description: 'Official Bills blue & red',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Bills Blue', 0xFF00338D),
        ThemeColor.hex('Bills Red', 0xFFC60C30),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['buffalo', 'buffalo bills', 'buf'],
    ),

    'dolphins': CanonicalTheme(
      id: 'dolphins',
      displayName: 'Miami Dolphins',
      description: 'Official Dolphins aqua & orange',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Dolphins Aqua', 0xFF008E97),
        ThemeColor.hex('Dolphins Orange', 0xFFF58220),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['miami', 'miami dolphins', 'mia', 'miami football'],
    ),

    'patriots': CanonicalTheme(
      id: 'patriots',
      displayName: 'New England Patriots',
      description: 'Official Patriots navy, red & silver',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Patriots Navy', 0xFF002244),
        ThemeColor.hex('Patriots Red', 0xFFC60C30),
        ThemeColor.hex('Patriots Silver', 0xFFB0B7BC),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new england', 'new england patriots', 'ne', 'pats', 'boston football'],
    ),

    'jets': CanonicalTheme(
      id: 'jets',
      displayName: 'New York Jets',
      description: 'Official Jets green & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Jets Green', 0xFF125740),
        ThemeColor.hex('Jets White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new york jets', 'ny jets', 'nyj'],
    ),

    // AFC NORTH
    'ravens': CanonicalTheme(
      id: 'ravens',
      displayName: 'Baltimore Ravens',
      description: 'Official Ravens purple & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Ravens Purple', 0xFF241773),
        ThemeColor.hex('Ravens Black', 0xFF000000),
        ThemeColor.hex('Ravens Gold', 0xFF9E7C0C),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['baltimore', 'baltimore ravens', 'bal'],
    ),

    'bengals': CanonicalTheme(
      id: 'bengals',
      displayName: 'Cincinnati Bengals',
      description: 'Official Bengals orange & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Bengals Orange', 0xFFFB4F14),
        ThemeColor.hex('Bengals Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['cincinnati', 'cincinnati bengals', 'cin', 'cincy'],
    ),

    'browns': CanonicalTheme(
      id: 'browns',
      displayName: 'Cleveland Browns',
      description: 'Official Browns orange & brown',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Browns Orange', 0xFFFF3C00),
        ThemeColor.hex('Browns Brown', 0xFF311D00),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['cleveland', 'cleveland browns', 'cle'],
    ),

    'steelers': CanonicalTheme(
      id: 'steelers',
      displayName: 'Pittsburgh Steelers',
      description: 'Official Steelers black & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Steelers Black', 0xFF101820),
        ThemeColor.hex('Steelers Gold', 0xFFFFB612),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['pittsburgh', 'pittsburgh steelers', 'pit', 'pitt'],
    ),

    // AFC SOUTH
    'texans': CanonicalTheme(
      id: 'texans',
      displayName: 'Houston Texans',
      description: 'Official Texans navy, red & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Texans Navy', 0xFF03202F),
        ThemeColor.hex('Texans Red', 0xFFA71930),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['houston', 'houston texans', 'hou', 'houston football'],
    ),

    'colts': CanonicalTheme(
      id: 'colts',
      displayName: 'Indianapolis Colts',
      description: 'Official Colts blue & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Colts Blue', 0xFF002C5F),
        ThemeColor.hex('Colts White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['indianapolis', 'indianapolis colts', 'ind', 'indy'],
    ),

    'jaguars': CanonicalTheme(
      id: 'jaguars',
      displayName: 'Jacksonville Jaguars',
      description: 'Official Jaguars teal, black & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Jaguars Teal', 0xFF006778),
        ThemeColor.hex('Jaguars Black', 0xFF101820),
        ThemeColor.hex('Jaguars Gold', 0xFFD7A22A),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['jacksonville', 'jacksonville jaguars', 'jax', 'jags'],
    ),

    'titans': CanonicalTheme(
      id: 'titans',
      displayName: 'Tennessee Titans',
      description: 'Official Titans navy, light blue & red',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Titans Navy', 0xFF0C2340),
        ThemeColor.hex('Titans Blue', 0xFF4B92DB),
        ThemeColor.hex('Titans Red', 0xFFC8102E),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['tennessee', 'tennessee titans', 'ten', 'nashville football'],
    ),

    // AFC WEST
    'broncos': CanonicalTheme(
      id: 'broncos',
      displayName: 'Denver Broncos',
      description: 'Official Broncos orange & navy',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Broncos Orange', 0xFFFB4F14),
        ThemeColor.hex('Broncos Navy', 0xFF002244),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['denver', 'denver broncos', 'den', 'denver football'],
    ),

    'chiefs': CanonicalTheme(
      id: 'chiefs',
      displayName: 'Kansas City Chiefs',
      description: 'Official Chiefs red & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        // Official colors - LED optimization applied automatically via _optimizeForLed()
        ThemeColor.hex('Chiefs Red', 0xFFE31837),
        ThemeColor.hex('Chiefs Gold', 0xFFFFB81C),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['kansas city', 'kansas city chiefs', 'kc', 'kc chiefs', 'mahomes'],
    ),

    'raiders': CanonicalTheme(
      id: 'raiders',
      displayName: 'Las Vegas Raiders',
      description: 'Official Raiders silver & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Raiders Silver', 0xFFA5ACAF),
        ThemeColor.hex('Raiders Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['las vegas', 'las vegas raiders', 'lv', 'oakland raiders', 'oakland'],
    ),

    'chargers': CanonicalTheme(
      id: 'chargers',
      displayName: 'Los Angeles Chargers',
      description: 'Official Chargers powder blue & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Chargers Blue', 0xFF0080C6),
        ThemeColor.hex('Chargers Gold', 0xFFFFC20E),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['la chargers', 'los angeles chargers', 'lac', 'san diego chargers'],
    ),

    // NFC EAST
    'cowboys': CanonicalTheme(
      id: 'cowboys',
      displayName: 'Dallas Cowboys',
      description: 'Official Cowboys navy, silver & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Cowboys Navy', 0xFF003594),
        ThemeColor.hex('Cowboys Silver', 0xFF869397),
        ThemeColor.hex('Cowboys White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['dallas', 'dallas cowboys', 'dal', 'americas team'],
    ),

    'giants': CanonicalTheme(
      id: 'giants_nfl',
      displayName: 'New York Giants',
      description: 'Official Giants blue, red & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Giants Blue', 0xFF0B2265),
        ThemeColor.hex('Giants Red', 0xFFA71930),
        ThemeColor.hex('Giants White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new york giants', 'ny giants', 'nyg', 'big blue'],
    ),

    'eagles': CanonicalTheme(
      id: 'eagles',
      displayName: 'Philadelphia Eagles',
      description: 'Official Eagles green, silver & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Eagles Green', 0xFF004C54),
        ThemeColor.hex('Eagles Silver', 0xFFA5ACAF),
        ThemeColor.hex('Eagles Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['philadelphia', 'philadelphia eagles', 'phi', 'philly', 'philly football'],
    ),

    'commanders': CanonicalTheme(
      id: 'commanders',
      displayName: 'Washington Commanders',
      description: 'Official Commanders burgundy & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Commanders Burgundy', 0xFF5A1414),
        ThemeColor.hex('Commanders Gold', 0xFFFFB612),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['washington', 'washington commanders', 'was', 'dc football', 'redskins'],
    ),

    // NFC NORTH
    'bears': CanonicalTheme(
      id: 'bears',
      displayName: 'Chicago Bears',
      description: 'Official Bears navy & orange',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Bears Navy', 0xFF0B162A),
        ThemeColor.hex('Bears Orange', 0xFFC83803),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['chicago', 'chicago bears', 'chi', 'da bears'],
    ),

    'lions': CanonicalTheme(
      id: 'lions',
      displayName: 'Detroit Lions',
      description: 'Official Lions blue & silver',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Lions Blue', 0xFF0076B6),
        ThemeColor.hex('Lions Silver', 0xFFB0B7BC),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['detroit', 'detroit lions', 'det'],
    ),

    'packers': CanonicalTheme(
      id: 'packers',
      displayName: 'Green Bay Packers',
      description: 'Official Packers green & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Packers Green', 0xFF203731),
        ThemeColor.hex('Packers Gold', 0xFFFFB612),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['green bay', 'green bay packers', 'gb', 'wisconsin football'],
    ),

    'vikings': CanonicalTheme(
      id: 'vikings',
      displayName: 'Minnesota Vikings',
      description: 'Official Vikings purple & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Vikings Purple', 0xFF4F2683),
        ThemeColor.hex('Vikings Gold', 0xFFFFC62F),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['minnesota', 'minnesota vikings', 'min', 'skol'],
    ),

    // NFC SOUTH
    'falcons': CanonicalTheme(
      id: 'falcons',
      displayName: 'Atlanta Falcons',
      description: 'Official Falcons red & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Falcons Red', 0xFFA71930),
        ThemeColor.hex('Falcons Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['atlanta', 'atlanta falcons', 'atl', 'dirty birds'],
    ),

    'panthers': CanonicalTheme(
      id: 'panthers_nfl',
      displayName: 'Carolina Panthers',
      description: 'Official Panthers blue, black & silver',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Panthers Blue', 0xFF0085CA),
        ThemeColor.hex('Panthers Black', 0xFF101820),
        ThemeColor.hex('Panthers Silver', 0xFFBFC0BF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['carolina', 'carolina panthers', 'car', 'charlotte football'],
    ),

    'saints': CanonicalTheme(
      id: 'saints',
      displayName: 'New Orleans Saints',
      description: 'Official Saints black & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Saints Gold', 0xFFD3BC8D),
        ThemeColor.hex('Saints Black', 0xFF101820),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new orleans', 'new orleans saints', 'no', 'nola', 'who dat'],
    ),

    'buccaneers': CanonicalTheme(
      id: 'buccaneers',
      displayName: 'Tampa Bay Buccaneers',
      description: 'Official Bucs red, pewter & orange',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Bucs Red', 0xFFD50A0A),
        ThemeColor.hex('Bucs Pewter', 0xFF34302B),
        ThemeColor.hex('Bucs Orange', 0xFFFF7900),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['tampa bay', 'tampa bay buccaneers', 'tb', 'bucs', 'tampa'],
    ),

    // NFC WEST
    'cardinals_nfl': CanonicalTheme(
      id: 'cardinals_nfl',
      displayName: 'Arizona Cardinals',
      description: 'Official Cardinals red, white & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Cardinals Red', 0xFF97233F),
        ThemeColor.hex('Cardinals White', 0xFFFFFFFF),
        ThemeColor.hex('Cardinals Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['arizona', 'arizona cardinals', 'ari', 'phoenix football'],
    ),

    'rams': CanonicalTheme(
      id: 'rams',
      displayName: 'Los Angeles Rams',
      description: 'Official Rams blue & yellow',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Rams Blue', 0xFF003594),
        ThemeColor.hex('Rams Yellow', 0xFFFFA300),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['la rams', 'los angeles rams', 'lar', 'st louis rams'],
    ),

    '49ers': CanonicalTheme(
      id: '49ers',
      displayName: 'San Francisco 49ers',
      description: 'Official 49ers red & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('49ers Red', 0xFFAA0000),
        ThemeColor.hex('49ers Gold', 0xFFB3995D),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['san francisco', 'san francisco 49ers', 'sf', 'niners', 'bay area football'],
    ),

    'seahawks': CanonicalTheme(
      id: 'seahawks',
      displayName: 'Seattle Seahawks',
      description: 'Official Seahawks blue, green & grey',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Seahawks Blue', 0xFF002244),
        ThemeColor.hex('Seahawks Green', 0xFF69BE28),
        ThemeColor.hex('Seahawks Grey', 0xFFA5ACAF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['seattle', 'seattle seahawks', 'sea', '12s', 'hawks'],
    ),
  };

  /// Get all NFL teams
  static List<CanonicalTheme> get allNflTeams => nflTeams.values.toList();

  /// NBA Teams (30 teams) - Official colors from NBA brand guidelines
  static final Map<String, CanonicalTheme> nbaTeams = {
    // ATLANTIC DIVISION
    'celtics': CanonicalTheme(
      id: 'celtics',
      displayName: 'Boston Celtics',
      description: 'Official Celtics green & white',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Celtics Green', 0xFF007A33),
        ThemeColor.hex('Celtics Gold', 0xFFBA9653),
        ThemeColor.hex('Celtics White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['boston', 'boston celtics', 'bos', 'boston basketball'],
    ),

    'nets': CanonicalTheme(
      id: 'nets',
      displayName: 'Brooklyn Nets',
      description: 'Official Nets black & white',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Nets Black', 0xFF000000),
        ThemeColor.hex('Nets White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['brooklyn', 'brooklyn nets', 'bkn', 'new jersey nets'],
    ),

    'knicks': CanonicalTheme(
      id: 'knicks',
      displayName: 'New York Knicks',
      description: 'Official Knicks blue & orange',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Knicks Blue', 0xFF006BB6),
        ThemeColor.hex('Knicks Orange', 0xFFF58426),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new york knicks', 'ny knicks', 'nyk', 'new york basketball'],
    ),

    '76ers': CanonicalTheme(
      id: '76ers',
      displayName: 'Philadelphia 76ers',
      description: 'Official 76ers red, blue & white',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('76ers Blue', 0xFF006BB6),
        ThemeColor.hex('76ers Red', 0xFFED174C),
        ThemeColor.hex('76ers White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['philadelphia 76ers', 'philly 76ers', 'phi', 'sixers', 'philadelphia basketball'],
    ),

    'raptors': CanonicalTheme(
      id: 'raptors',
      displayName: 'Toronto Raptors',
      description: 'Official Raptors red & black',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Raptors Red', 0xFFCE1141),
        ThemeColor.hex('Raptors Black', 0xFF000000),
        ThemeColor.hex('Raptors Silver', 0xFFA1A1A4),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['toronto', 'toronto raptors', 'tor', 'canada basketball'],
    ),

    // CENTRAL DIVISION
    'bulls': CanonicalTheme(
      id: 'bulls',
      displayName: 'Chicago Bulls',
      description: 'Official Bulls red & black',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Bulls Red', 0xFFCE1141),
        ThemeColor.hex('Bulls Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['chicago bulls', 'chi bulls', 'chicago basketball'],
    ),

    'cavaliers': CanonicalTheme(
      id: 'cavaliers',
      displayName: 'Cleveland Cavaliers',
      description: 'Official Cavs wine & gold',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Cavs Wine', 0xFF860038),
        ThemeColor.hex('Cavs Gold', 0xFFFFB81C),
        ThemeColor.hex('Cavs Navy', 0xFF041E42),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['cleveland', 'cleveland cavaliers', 'cle', 'cavs', 'cleveland basketball'],
    ),

    'pistons': CanonicalTheme(
      id: 'pistons',
      displayName: 'Detroit Pistons',
      description: 'Official Pistons red & blue',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Pistons Blue', 0xFF1D42BA),
        ThemeColor.hex('Pistons Red', 0xFFC8102E),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['detroit pistons', 'det', 'detroit basketball'],
    ),

    'pacers': CanonicalTheme(
      id: 'pacers',
      displayName: 'Indiana Pacers',
      description: 'Official Pacers navy & gold',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Pacers Navy', 0xFF002D62),
        ThemeColor.hex('Pacers Gold', 0xFFFDBA21),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['indiana', 'indiana pacers', 'ind', 'indy basketball'],
    ),

    'bucks': CanonicalTheme(
      id: 'bucks',
      displayName: 'Milwaukee Bucks',
      description: 'Official Bucks green & cream',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Bucks Green', 0xFF00471B),
        ThemeColor.hex('Bucks Cream', 0xFFEEE1C6),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['milwaukee', 'milwaukee bucks', 'mil', 'fear the deer'],
    ),

    // SOUTHEAST DIVISION
    'hawks': CanonicalTheme(
      id: 'hawks',
      displayName: 'Atlanta Hawks',
      description: 'Official Hawks red & white',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Hawks Red', 0xFFE03A3E),
        ThemeColor.hex('Hawks White', 0xFFFFFFFF),
        ThemeColor.hex('Hawks Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['atlanta hawks', 'atl hawks', 'atlanta basketball'],
    ),

    'hornets': CanonicalTheme(
      id: 'hornets',
      displayName: 'Charlotte Hornets',
      description: 'Official Hornets teal & purple',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Hornets Teal', 0xFF00788C),
        ThemeColor.hex('Hornets Purple', 0xFF1D1160),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['charlotte', 'charlotte hornets', 'cha', 'buzz city'],
    ),

    'heat': CanonicalTheme(
      id: 'heat',
      displayName: 'Miami Heat',
      description: 'Official Heat red, black & white',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Heat Red', 0xFF98002E),
        ThemeColor.hex('Heat Black', 0xFF000000),
        ThemeColor.hex('Heat Yellow', 0xFFF9A01B),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['miami heat', 'mia heat', 'miami basketball', 'heat culture'],
    ),

    'magic': CanonicalTheme(
      id: 'magic',
      displayName: 'Orlando Magic',
      description: 'Official Magic blue & black',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Magic Blue', 0xFF0077C0),
        ThemeColor.hex('Magic Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['orlando', 'orlando magic', 'orl'],
    ),

    'wizards': CanonicalTheme(
      id: 'wizards',
      displayName: 'Washington Wizards',
      description: 'Official Wizards red, navy & white',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Wizards Navy', 0xFF002B5C),
        ThemeColor.hex('Wizards Red', 0xFFE31837),
        ThemeColor.hex('Wizards Silver', 0xFFC4CED4),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['washington wizards', 'was', 'dc basketball', 'bullets'],
    ),

    // NORTHWEST DIVISION
    'nuggets': CanonicalTheme(
      id: 'nuggets',
      displayName: 'Denver Nuggets',
      description: 'Official Nuggets navy & gold',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Nuggets Navy', 0xFF0E2240),
        ThemeColor.hex('Nuggets Gold', 0xFFFEC524),
        ThemeColor.hex('Nuggets Red', 0xFF8B2131),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['denver nuggets', 'den', 'denver basketball', 'mile high basketball'],
    ),

    'timberwolves': CanonicalTheme(
      id: 'timberwolves',
      displayName: 'Minnesota Timberwolves',
      description: 'Official Wolves blue & green',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Wolves Blue', 0xFF0C2340),
        ThemeColor.hex('Wolves Green', 0xFF236192),
        ThemeColor.hex('Wolves Grey', 0xFF9EA2A2),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['minnesota timberwolves', 'min', 'wolves', 'twolves'],
    ),

    'thunder': CanonicalTheme(
      id: 'thunder',
      displayName: 'Oklahoma City Thunder',
      description: 'Official Thunder blue & orange',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Thunder Blue', 0xFF007AC1),
        ThemeColor.hex('Thunder Orange', 0xFFEF3B24),
        ThemeColor.hex('Thunder Navy', 0xFF002D62),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['oklahoma city', 'oklahoma city thunder', 'okc', 'okc thunder'],
    ),

    'blazers': CanonicalTheme(
      id: 'blazers',
      displayName: 'Portland Trail Blazers',
      description: 'Official Blazers red & black',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Blazers Red', 0xFFE03A3E),
        ThemeColor.hex('Blazers Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['portland', 'portland trail blazers', 'por', 'rip city'],
    ),

    'jazz': CanonicalTheme(
      id: 'jazz',
      displayName: 'Utah Jazz',
      description: 'Official Jazz navy, yellow & green',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Jazz Navy', 0xFF002B5C),
        ThemeColor.hex('Jazz Yellow', 0xFFF9A01B),
        ThemeColor.hex('Jazz Green', 0xFF00471B),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['utah', 'utah jazz', 'uta', 'salt lake basketball'],
    ),

    // PACIFIC DIVISION
    'warriors': CanonicalTheme(
      id: 'warriors',
      displayName: 'Golden State Warriors',
      description: 'Official Warriors blue & gold',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Warriors Blue', 0xFF1D428A),
        ThemeColor.hex('Warriors Gold', 0xFFFFC72C),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['golden state', 'golden state warriors', 'gsw', 'dubs', 'bay area basketball'],
    ),

    'clippers': CanonicalTheme(
      id: 'clippers',
      displayName: 'Los Angeles Clippers',
      description: 'Official Clippers red, blue & white',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Clippers Red', 0xFFC8102E),
        ThemeColor.hex('Clippers Blue', 0xFF1D428A),
        ThemeColor.hex('Clippers White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['la clippers', 'los angeles clippers', 'lac'],
    ),

    'lakers': CanonicalTheme(
      id: 'lakers',
      displayName: 'Los Angeles Lakers',
      description: 'Official Lakers purple & gold',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Lakers Purple', 0xFF552583),
        ThemeColor.hex('Lakers Gold', 0xFFFDB927),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['los angeles lakers', 'la lakers', 'lal', 'showtime', 'lake show'],
    ),

    'suns': CanonicalTheme(
      id: 'suns',
      displayName: 'Phoenix Suns',
      description: 'Official Suns purple & orange',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Suns Purple', 0xFF1D1160),
        ThemeColor.hex('Suns Orange', 0xFFE56020),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['phoenix', 'phoenix suns', 'phx', 'valley'],
    ),

    'kings': CanonicalTheme(
      id: 'kings',
      displayName: 'Sacramento Kings',
      description: 'Official Kings purple & silver',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Kings Purple', 0xFF5A2D81),
        ThemeColor.hex('Kings Silver', 0xFF63727A),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['sacramento', 'sacramento kings', 'sac', 'sactown'],
    ),

    // SOUTHWEST DIVISION
    'mavericks': CanonicalTheme(
      id: 'mavericks',
      displayName: 'Dallas Mavericks',
      description: 'Official Mavs blue & silver',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Mavs Blue', 0xFF00538C),
        ThemeColor.hex('Mavs Navy', 0xFF002B5E),
        ThemeColor.hex('Mavs Silver', 0xFFB8C4CA),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['dallas mavericks', 'dal', 'mavs', 'dallas basketball'],
    ),

    'rockets': CanonicalTheme(
      id: 'rockets',
      displayName: 'Houston Rockets',
      description: 'Official Rockets red & white',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Rockets Red', 0xFFCE1141),
        ThemeColor.hex('Rockets Silver', 0xFFC4CED4),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['houston rockets', 'hou', 'houston basketball', 'clutch city'],
    ),

    'grizzlies': CanonicalTheme(
      id: 'grizzlies',
      displayName: 'Memphis Grizzlies',
      description: 'Official Grizzlies navy & blue',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Grizzlies Navy', 0xFF12173F),
        ThemeColor.hex('Grizzlies Blue', 0xFF5D76A9),
        ThemeColor.hex('Grizzlies Gold', 0xFFF5B112),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['memphis', 'memphis grizzlies', 'mem', 'grit grind'],
    ),

    'pelicans': CanonicalTheme(
      id: 'pelicans',
      displayName: 'New Orleans Pelicans',
      description: 'Official Pelicans navy, red & gold',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Pelicans Navy', 0xFF0C2340),
        ThemeColor.hex('Pelicans Red', 0xFFC8102E),
        ThemeColor.hex('Pelicans Gold', 0xFF85714D),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new orleans pelicans', 'nop', 'nola basketball'],
    ),

    'spurs': CanonicalTheme(
      id: 'spurs',
      displayName: 'San Antonio Spurs',
      description: 'Official Spurs silver & black',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Spurs Silver', 0xFFC4CED4),
        ThemeColor.hex('Spurs Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['san antonio', 'san antonio spurs', 'sas', 'go spurs go'],
    ),
  };

  /// Get all NBA teams
  static List<CanonicalTheme> get allNbaTeams => nbaTeams.values.toList();
}
