import 'package:flutter/material.dart';
import 'package:nexgen_command/features/patterns/canonical_palettes.dart';

/// UFL, WNBA, and other league team colors with official HEX codes

class OtherLeaguesPalettes {
  OtherLeaguesPalettes._();

  /// UFL Teams (8 teams) - United Football League
  static final Map<String, CanonicalTheme> uflTeams = {
    'birmingham_stallions': CanonicalTheme(
      id: 'birmingham_stallions',
      displayName: 'Birmingham Stallions',
      description: 'Official Stallions red & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Stallions Red', 0xFFD22630),
        ThemeColor.hex('Stallions Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['birmingham stallions', 'stallions', 'birmingham football'],
    ),

    'dc_defenders': CanonicalTheme(
      id: 'dc_defenders',
      displayName: 'DC Defenders',
      description: 'Official Defenders red & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Defenders Red', 0xFFED1B2F),
        ThemeColor.hex('Defenders Black', 0xFF000000),
        ThemeColor.hex('Defenders White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['dc defenders', 'defenders', 'dc football ufl'],
    ),

    'houston_roughnecks': CanonicalTheme(
      id: 'houston_roughnecks',
      displayName: 'Houston Roughnecks',
      description: 'Official Roughnecks navy & red',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Roughnecks Navy', 0xFF132448),
        ThemeColor.hex('Roughnecks Red', 0xFFD22630),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['houston roughnecks', 'roughnecks', 'houston football ufl'],
    ),

    'memphis_showboats': CanonicalTheme(
      id: 'memphis_showboats',
      displayName: 'Memphis Showboats',
      description: 'Official Showboats red, blue & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Showboats Red', 0xFFE31837),
        ThemeColor.hex('Showboats Blue', 0xFF00205B),
        ThemeColor.hex('Showboats Gold', 0xFFFFB81C),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['memphis showboats', 'showboats', 'memphis football'],
    ),

    'michigan_panthers': CanonicalTheme(
      id: 'michigan_panthers',
      displayName: 'Michigan Panthers',
      description: 'Official Panthers blue & red',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Panthers Blue', 0xFF00205B),
        ThemeColor.hex('Panthers Red', 0xFFE31837),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['michigan panthers', 'panthers ufl', 'michigan football'],
    ),

    'san_antonio_brahmas': CanonicalTheme(
      id: 'san_antonio_brahmas',
      displayName: 'San Antonio Brahmas',
      description: 'Official Brahmas black & red',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Brahmas Black', 0xFF000000),
        ThemeColor.hex('Brahmas Red', 0xFFE31837),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['san antonio brahmas', 'brahmas', 'san antonio football'],
    ),

    'seattle_sea_dragons': CanonicalTheme(
      id: 'seattle_sea_dragons',
      displayName: 'Seattle Sea Dragons',
      description: 'Official Sea Dragons blue & green',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Sea Dragons Blue', 0xFF00205B),
        ThemeColor.hex('Sea Dragons Green', 0xFF00A651),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['seattle sea dragons', 'sea dragons', 'seattle football ufl'],
    ),

    'st_louis_battlehawks': CanonicalTheme(
      id: 'st_louis_battlehawks',
      displayName: 'St. Louis Battlehawks',
      description: 'Official Battlehawks blue & red',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Battlehawks Blue', 0xFF00539F),
        ThemeColor.hex('Battlehawks Red', 0xFFE31837),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['st louis battlehawks', 'battlehawks', 'st louis football', 'kakaw'],
    ),
  };

  /// WNBA Teams (12 teams)
  static final Map<String, CanonicalTheme> wnbaTeams = {
    'aces': CanonicalTheme(
      id: 'aces',
      displayName: 'Las Vegas Aces',
      description: 'Official Aces red, black & grey',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Aces Red', 0xFFC4032B),
        ThemeColor.hex('Aces Black', 0xFF000000),
        ThemeColor.hex('Aces Grey', 0xFF85714D),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['las vegas aces', 'aces', 'vegas aces', 'lv aces'],
    ),

    'dream': CanonicalTheme(
      id: 'dream',
      displayName: 'Atlanta Dream',
      description: 'Official Dream red, blue & white',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Dream Red', 0xFFE31837),
        ThemeColor.hex('Dream Navy', 0xFF0C2340),
        ThemeColor.hex('Dream Sky', 0xFF418FDE),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['atlanta dream', 'dream', 'atlanta wnba'],
    ),

    'sky': CanonicalTheme(
      id: 'sky',
      displayName: 'Chicago Sky',
      description: 'Official Sky blue & yellow',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Sky Blue', 0xFF418FDE),
        ThemeColor.hex('Sky Yellow', 0xFFFFCD00),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['chicago sky', 'sky', 'chicago wnba'],
    ),

    'sun': CanonicalTheme(
      id: 'sun',
      displayName: 'Connecticut Sun',
      description: 'Official Sun orange & blue',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Sun Orange', 0xFFF05123),
        ThemeColor.hex('Sun Blue', 0xFF0A2240),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['connecticut sun', 'sun', 'ct sun', 'connecticut wnba'],
    ),

    'wings': CanonicalTheme(
      id: 'wings',
      displayName: 'Dallas Wings',
      description: 'Official Wings navy & sky blue',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Wings Navy', 0xFF002B5C),
        ThemeColor.hex('Wings Sky', 0xFFC4D600),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['dallas wings', 'wings', 'dallas wnba'],
    ),

    'fever': CanonicalTheme(
      id: 'fever',
      displayName: 'Indiana Fever',
      description: 'Official Fever red & navy',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Fever Red', 0xFFE31837),
        ThemeColor.hex('Fever Navy', 0xFF002D62),
        ThemeColor.hex('Fever Gold', 0xFFFFCD00),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['indiana fever', 'fever', 'indiana wnba', 'caitlin clark'],
    ),

    'sparks': CanonicalTheme(
      id: 'sparks',
      displayName: 'Los Angeles Sparks',
      description: 'Official Sparks purple & gold',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Sparks Purple', 0xFF552583),
        ThemeColor.hex('Sparks Gold', 0xFFFDB927),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['los angeles sparks', 'sparks', 'la sparks', 'la wnba'],
    ),

    'lynx': CanonicalTheme(
      id: 'lynx',
      displayName: 'Minnesota Lynx',
      description: 'Official Lynx blue & green',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Lynx Blue', 0xFF0C2340),
        ThemeColor.hex('Lynx Green', 0xFF78BE21),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['minnesota lynx', 'lynx', 'minnesota wnba'],
    ),

    'liberty': CanonicalTheme(
      id: 'liberty',
      displayName: 'New York Liberty',
      description: 'Official Liberty seafoam & black',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Liberty Seafoam', 0xFF6ECEB2),
        ThemeColor.hex('Liberty Black', 0xFF000000),
        ThemeColor.hex('Liberty Orange', 0xFFF15A24),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new york liberty', 'liberty', 'ny liberty', 'new york wnba'],
    ),

    'mercury': CanonicalTheme(
      id: 'mercury',
      displayName: 'Phoenix Mercury',
      description: 'Official Mercury orange & purple',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Mercury Orange', 0xFFE56020),
        ThemeColor.hex('Mercury Purple', 0xFF201747),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['phoenix mercury', 'mercury', 'phoenix wnba'],
    ),

    'storm': CanonicalTheme(
      id: 'storm',
      displayName: 'Seattle Storm',
      description: 'Official Storm green & gold',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Storm Green', 0xFF2C5234),
        ThemeColor.hex('Storm Gold', 0xFFFFC72C),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['seattle storm', 'storm', 'seattle wnba'],
    ),

    'mystics': CanonicalTheme(
      id: 'mystics',
      displayName: 'Washington Mystics',
      description: 'Official Mystics red, blue & white',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Mystics Red', 0xFFE31837),
        ThemeColor.hex('Mystics Navy', 0xFF002B5C),
        ThemeColor.hex('Mystics White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['washington mystics', 'mystics', 'dc wnba', 'washington wnba'],
    ),

    // New expansion team
    'valkyries': CanonicalTheme(
      id: 'valkyries',
      displayName: 'Golden State Valkyries',
      description: 'Official Valkyries purple & gold',
      icon: Icons.sports_basketball,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Valkyries Purple', 0xFF582C83),
        ThemeColor.hex('Valkyries Gold', 0xFFDAA900),
        ThemeColor.hex('Valkyries Sea', 0xFF00B2A9),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['golden state valkyries', 'valkyries', 'gs valkyries', 'bay area wnba'],
    ),
  };

  /// Get all UFL teams
  static List<CanonicalTheme> get allUflTeams => uflTeams.values.toList();

  /// Get all WNBA teams
  static List<CanonicalTheme> get allWnbaTeams => wnbaTeams.values.toList();
}
