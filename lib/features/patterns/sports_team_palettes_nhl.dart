import 'package:flutter/material.dart';
import 'package:nexgen_command/features/patterns/canonical_palettes.dart';

/// NHL Team colors with official HEX codes

class NhlTeamPalettes {
  NhlTeamPalettes._();

  /// NHL Teams (32 teams) - Official colors from NHL brand guidelines
  static final Map<String, CanonicalTheme> nhlTeams = {
    // ATLANTIC DIVISION
    'bruins': CanonicalTheme(
      id: 'bruins',
      displayName: 'Boston Bruins',
      description: 'Official Bruins black & gold',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Bruins Gold', 0xFFFFB81C),
        ThemeColor.hex('Bruins Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['boston bruins', 'bos bruins', 'boston hockey'],
    ),

    'sabres': CanonicalTheme(
      id: 'sabres',
      displayName: 'Buffalo Sabres',
      description: 'Official Sabres navy, gold & white',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Sabres Navy', 0xFF002654),
        ThemeColor.hex('Sabres Gold', 0xFFFCB514),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['buffalo sabres', 'buf sabres', 'buffalo hockey'],
    ),

    'red_wings': CanonicalTheme(
      id: 'red_wings',
      displayName: 'Detroit Red Wings',
      description: 'Official Red Wings red & white',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Red Wings Red', 0xFFCE1126),
        ThemeColor.hex('Red Wings White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['detroit red wings', 'det red wings', 'detroit hockey', 'wings'],
    ),

    'panthers_nhl': CanonicalTheme(
      id: 'panthers_nhl',
      displayName: 'Florida Panthers',
      description: 'Official Panthers red, navy & gold',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Panthers Red', 0xFFC8102E),
        ThemeColor.hex('Panthers Navy', 0xFF041E42),
        ThemeColor.hex('Panthers Gold', 0xFFB9975B),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['florida panthers', 'fla panthers', 'florida hockey'],
    ),

    'canadiens': CanonicalTheme(
      id: 'canadiens',
      displayName: 'Montreal Canadiens',
      description: 'Official Canadiens red, blue & white',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Canadiens Red', 0xFFAF1E2D),
        ThemeColor.hex('Canadiens Blue', 0xFF192168),
        ThemeColor.hex('Canadiens White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['montreal canadiens', 'mtl', 'habs', 'montreal hockey'],
    ),

    'senators': CanonicalTheme(
      id: 'senators',
      displayName: 'Ottawa Senators',
      description: 'Official Senators red, black & gold',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Senators Red', 0xFFC52032),
        ThemeColor.hex('Senators Black', 0xFF000000),
        ThemeColor.hex('Senators Gold', 0xFFC69214),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['ottawa senators', 'ott', 'sens', 'ottawa hockey'],
    ),

    'lightning': CanonicalTheme(
      id: 'lightning',
      displayName: 'Tampa Bay Lightning',
      description: 'Official Lightning blue & white',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Lightning Blue', 0xFF002868),
        ThemeColor.hex('Lightning White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['tampa bay lightning', 'tbl', 'bolts', 'tampa hockey'],
    ),

    'maple_leafs': CanonicalTheme(
      id: 'maple_leafs',
      displayName: 'Toronto Maple Leafs',
      description: 'Official Maple Leafs blue & white',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Leafs Blue', 0xFF00205B),
        ThemeColor.hex('Leafs White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['toronto maple leafs', 'tor', 'leafs', 'toronto hockey'],
    ),

    // METROPOLITAN DIVISION
    'hurricanes': CanonicalTheme(
      id: 'hurricanes',
      displayName: 'Carolina Hurricanes',
      description: 'Official Hurricanes red, black & white',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Hurricanes Red', 0xFFCC0000),
        ThemeColor.hex('Hurricanes Black', 0xFF000000),
        ThemeColor.hex('Hurricanes White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['carolina hurricanes', 'car', 'canes', 'carolina hockey'],
    ),

    'blue_jackets': CanonicalTheme(
      id: 'blue_jackets',
      displayName: 'Columbus Blue Jackets',
      description: 'Official Blue Jackets navy, red & silver',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Blue Jackets Navy', 0xFF002654),
        ThemeColor.hex('Blue Jackets Red', 0xFFCE1126),
        ThemeColor.hex('Blue Jackets Silver', 0xFFA4A9AD),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['columbus blue jackets', 'cbj', 'jackets', 'columbus hockey'],
    ),

    'devils': CanonicalTheme(
      id: 'devils',
      displayName: 'New Jersey Devils',
      description: 'Official Devils red & black',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Devils Red', 0xFFCE1126),
        ThemeColor.hex('Devils Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new jersey devils', 'njd', 'nj devils', 'jersey hockey'],
    ),

    'islanders': CanonicalTheme(
      id: 'islanders',
      displayName: 'New York Islanders',
      description: 'Official Islanders blue & orange',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Islanders Blue', 0xFF00539B),
        ThemeColor.hex('Islanders Orange', 0xFFF47D30),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new york islanders', 'nyi', 'isles', 'long island hockey'],
    ),

    'rangers': CanonicalTheme(
      id: 'rangers',
      displayName: 'New York Rangers',
      description: 'Official Rangers blue, red & white',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Rangers Blue', 0xFF0038A8),
        ThemeColor.hex('Rangers Red', 0xFFCE1126),
        ThemeColor.hex('Rangers White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new york rangers', 'nyr', 'broadway blueshirts', 'nyc hockey'],
    ),

    'flyers': CanonicalTheme(
      id: 'flyers',
      displayName: 'Philadelphia Flyers',
      description: 'Official Flyers orange & black',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Flyers Orange', 0xFFF74902),
        ThemeColor.hex('Flyers Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['philadelphia flyers', 'phi flyers', 'philly hockey'],
    ),

    'penguins': CanonicalTheme(
      id: 'penguins',
      displayName: 'Pittsburgh Penguins',
      description: 'Official Penguins black & gold',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Penguins Black', 0xFF000000),
        ThemeColor.hex('Penguins Gold', 0xFFFCB514),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['pittsburgh penguins', 'pit', 'pens', 'pittsburgh hockey'],
    ),

    'capitals': CanonicalTheme(
      id: 'capitals',
      displayName: 'Washington Capitals',
      description: 'Official Capitals red, navy & white',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Capitals Red', 0xFFC8102E),
        ThemeColor.hex('Capitals Navy', 0xFF041E42),
        ThemeColor.hex('Capitals White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['washington capitals', 'wsh', 'caps', 'dc hockey'],
    ),

    // CENTRAL DIVISION
    'coyotes': CanonicalTheme(
      id: 'coyotes',
      displayName: 'Arizona Coyotes',
      description: 'Official Coyotes brick red, sand & black',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Coyotes Brick', 0xFF8C2633),
        ThemeColor.hex('Coyotes Sand', 0xFFE2D6B5),
        ThemeColor.hex('Coyotes Black', 0xFF111111),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['arizona coyotes', 'ari coyotes', 'phoenix coyotes', 'arizona hockey'],
    ),

    'blackhawks': CanonicalTheme(
      id: 'blackhawks',
      displayName: 'Chicago Blackhawks',
      description: 'Official Blackhawks red & black',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Blackhawks Red', 0xFFCF0A2C),
        ThemeColor.hex('Blackhawks Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['chicago blackhawks', 'chi blackhawks', 'hawks hockey', 'chicago hockey'],
    ),

    'avalanche': CanonicalTheme(
      id: 'avalanche',
      displayName: 'Colorado Avalanche',
      description: 'Official Avalanche burgundy, blue & silver',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Avalanche Burgundy', 0xFF6F263D),
        ThemeColor.hex('Avalanche Blue', 0xFF236192),
        ThemeColor.hex('Avalanche Silver', 0xFFA2AAAD),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['colorado avalanche', 'col', 'avs', 'colorado hockey', 'denver hockey'],
    ),

    'stars': CanonicalTheme(
      id: 'stars',
      displayName: 'Dallas Stars',
      description: 'Official Stars victory green, black & silver',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Stars Green', 0xFF006847),
        ThemeColor.hex('Stars Black', 0xFF111111),
        ThemeColor.hex('Stars Silver', 0xFF8F8F8C),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['dallas stars', 'dal', 'dallas hockey'],
    ),

    'wild': CanonicalTheme(
      id: 'wild',
      displayName: 'Minnesota Wild',
      description: 'Official Wild forest green, red & wheat',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Wild Green', 0xFF154734),
        ThemeColor.hex('Wild Red', 0xFFA6192E),
        ThemeColor.hex('Wild Wheat', 0xFFEECB9E),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['minnesota wild', 'min wild', 'minnesota hockey'],
    ),

    'predators': CanonicalTheme(
      id: 'predators',
      displayName: 'Nashville Predators',
      description: 'Official Predators gold & navy',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Predators Gold', 0xFFFFB81C),
        ThemeColor.hex('Predators Navy', 0xFF041E42),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['nashville predators', 'nsh', 'preds', 'nashville hockey', 'smashville'],
    ),

    'blues': CanonicalTheme(
      id: 'blues',
      displayName: 'St. Louis Blues',
      description: 'Official Blues blue, gold & navy',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Blues Blue', 0xFF002F87),
        ThemeColor.hex('Blues Gold', 0xFFFCB514),
        ThemeColor.hex('Blues Navy', 0xFF041E42),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['st louis blues', 'stl', 'st louis hockey'],
    ),

    'jets': CanonicalTheme(
      id: 'jets_nhl',
      displayName: 'Winnipeg Jets',
      description: 'Official Jets navy, blue & white',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Jets Navy', 0xFF041E42),
        ThemeColor.hex('Jets Blue', 0xFF004C97),
        ThemeColor.hex('Jets Silver', 0xFFA2AAAD),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['winnipeg jets', 'wpg', 'winnipeg hockey'],
    ),

    // PACIFIC DIVISION
    'ducks': CanonicalTheme(
      id: 'ducks',
      displayName: 'Anaheim Ducks',
      description: 'Official Ducks black, gold & orange',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Ducks Black', 0xFF000000),
        ThemeColor.hex('Ducks Gold', 0xFFF47A38),
        ThemeColor.hex('Ducks Orange', 0xFFB5985A),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['anaheim ducks', 'ana', 'mighty ducks', 'anaheim hockey'],
    ),

    'flames': CanonicalTheme(
      id: 'flames',
      displayName: 'Calgary Flames',
      description: 'Official Flames red, gold & black',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Flames Red', 0xFFC8102E),
        ThemeColor.hex('Flames Gold', 0xFFF1BE48),
        ThemeColor.hex('Flames Black', 0xFF111111),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['calgary flames', 'cgy', 'calgary hockey'],
    ),

    'oilers': CanonicalTheme(
      id: 'oilers',
      displayName: 'Edmonton Oilers',
      description: 'Official Oilers navy & orange',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Oilers Navy', 0xFF041E42),
        ThemeColor.hex('Oilers Orange', 0xFFFF4C00),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['edmonton oilers', 'edm', 'edmonton hockey', 'oil country'],
    ),

    'kings_nhl': CanonicalTheme(
      id: 'kings_nhl',
      displayName: 'Los Angeles Kings',
      description: 'Official Kings black, silver & white',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Kings Black', 0xFF111111),
        ThemeColor.hex('Kings Silver', 0xFFA2AAAD),
        ThemeColor.hex('Kings White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['los angeles kings', 'lak', 'la kings', 'la hockey'],
    ),

    'sharks': CanonicalTheme(
      id: 'sharks',
      displayName: 'San Jose Sharks',
      description: 'Official Sharks teal, black & orange',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Sharks Teal', 0xFF006D75),
        ThemeColor.hex('Sharks Black', 0xFF000000),
        ThemeColor.hex('Sharks Orange', 0xFFE57200),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['san jose sharks', 'sjs', 'san jose hockey', 'shark tank'],
    ),

    'kraken': CanonicalTheme(
      id: 'kraken',
      displayName: 'Seattle Kraken',
      description: 'Official Kraken deep sea blue, ice blue & red',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Kraken Blue', 0xFF001628),
        ThemeColor.hex('Kraken Ice', 0xFF99D9D9),
        ThemeColor.hex('Kraken Red', 0xFFE9072B),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['seattle kraken', 'sea kraken', 'seattle hockey', 'release the kraken'],
    ),

    'canucks': CanonicalTheme(
      id: 'canucks',
      displayName: 'Vancouver Canucks',
      description: 'Official Canucks blue, green & white',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Canucks Blue', 0xFF00205B),
        ThemeColor.hex('Canucks Green', 0xFF00843D),
        ThemeColor.hex('Canucks White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['vancouver canucks', 'van', 'vancouver hockey'],
    ),

    'golden_knights': CanonicalTheme(
      id: 'golden_knights',
      displayName: 'Vegas Golden Knights',
      description: 'Official Golden Knights gold, steel grey & red',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Knights Gold', 0xFFB4975A),
        ThemeColor.hex('Knights Steel', 0xFF333F42),
        ThemeColor.hex('Knights Red', 0xFFC8102E),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['vegas golden knights', 'vgk', 'vegas hockey', 'golden knights', 'knights'],
    ),

    // Utah Hockey Club (formerly Coyotes)
    'utah_hockey': CanonicalTheme(
      id: 'utah_hockey',
      displayName: 'Utah Hockey Club',
      description: 'Official Utah Hockey Club colors',
      icon: Icons.sports_hockey,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Utah Blue', 0xFF6CACE4),
        ThemeColor.hex('Utah Black', 0xFF010101),
        ThemeColor.hex('Utah White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['utah hockey club', 'utah hockey', 'utah nhl', 'salt lake hockey'],
    ),
  };

  /// Get all NHL teams
  static List<CanonicalTheme> get allNhlTeams => nhlTeams.values.toList();
}
