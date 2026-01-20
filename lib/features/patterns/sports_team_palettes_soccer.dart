import 'package:flutter/material.dart';
import 'package:nexgen_command/features/patterns/canonical_palettes.dart';

/// MLS, USL, and NWSL Team colors with official HEX codes

class SoccerTeamPalettes {
  SoccerTeamPalettes._();

  /// MLS Teams (29 teams) - Official colors
  static final Map<String, CanonicalTheme> mlsTeams = {
    // EASTERN CONFERENCE
    'atlanta_united': CanonicalTheme(
      id: 'atlanta_united',
      displayName: 'Atlanta United FC',
      description: 'Official Atlanta United red, black & gold',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Atlanta Red', 0xFF80000A),
        ThemeColor.hex('Atlanta Black', 0xFF000000),
        ThemeColor.hex('Atlanta Gold', 0xFFA29061),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['atlanta united', 'atl utd', 'atlanta soccer', 'five stripes'],
    ),

    'cf_montreal': CanonicalTheme(
      id: 'cf_montreal',
      displayName: 'CF Montréal',
      description: 'Official CF Montréal blue & black',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Montreal Blue', 0xFF0033A1),
        ThemeColor.hex('Montreal Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['cf montreal', 'montreal impact', 'montreal soccer'],
    ),

    'charlotte_fc': CanonicalTheme(
      id: 'charlotte_fc',
      displayName: 'Charlotte FC',
      description: 'Official Charlotte FC blue & white',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Charlotte Blue', 0xFF1A85C8),
        ThemeColor.hex('Charlotte White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['charlotte fc', 'charlotte soccer', 'crown'],
    ),

    'chicago_fire': CanonicalTheme(
      id: 'chicago_fire',
      displayName: 'Chicago Fire FC',
      description: 'Official Chicago Fire red & blue',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Fire Red', 0xFFB81137),
        ThemeColor.hex('Fire Blue', 0xFF7CCDEF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['chicago fire', 'chicago fire fc', 'chicago soccer'],
    ),

    'fc_cincinnati': CanonicalTheme(
      id: 'fc_cincinnati',
      displayName: 'FC Cincinnati',
      description: 'Official FC Cincinnati orange & blue',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('FCC Orange', 0xFFFE5000),
        ThemeColor.hex('FCC Blue', 0xFF003087),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['fc cincinnati', 'fcc', 'cincinnati soccer'],
    ),

    'columbus_crew': CanonicalTheme(
      id: 'columbus_crew',
      displayName: 'Columbus Crew',
      description: 'Official Columbus Crew black & gold',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Crew Black', 0xFF000000),
        ThemeColor.hex('Crew Gold', 0xFFFEF200),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['columbus crew', 'crew', 'columbus soccer'],
    ),

    'dc_united': CanonicalTheme(
      id: 'dc_united',
      displayName: 'D.C. United',
      description: 'Official D.C. United black & red',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('DC Black', 0xFF000000),
        ThemeColor.hex('DC Red', 0xFFEF3E42),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['dc united', 'd.c. united', 'washington soccer', 'dc soccer'],
    ),

    'inter_miami': CanonicalTheme(
      id: 'inter_miami',
      displayName: 'Inter Miami CF',
      description: 'Official Inter Miami pink & black',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Miami Pink', 0xFFF5B5C8),
        ThemeColor.hex('Miami Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['inter miami', 'miami cf', 'miami soccer', 'herons'],
    ),

    'new_england_revolution': CanonicalTheme(
      id: 'new_england_revolution',
      displayName: 'New England Revolution',
      description: 'Official Revolution navy & red',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Revs Navy', 0xFF0A2240),
        ThemeColor.hex('Revs Red', 0xFFCE0E2D),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new england revolution', 'ne revolution', 'revs', 'boston soccer'],
    ),

    'nycfc': CanonicalTheme(
      id: 'nycfc',
      displayName: 'New York City FC',
      description: 'Official NYCFC sky blue & navy',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('NYCFC Blue', 0xFF6CACE4),
        ThemeColor.hex('NYCFC Navy', 0xFF041E42),
        ThemeColor.hex('NYCFC Orange', 0xFFF15524),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['nycfc', 'new york city fc', 'nyc fc', 'new york soccer'],
    ),

    'red_bulls': CanonicalTheme(
      id: 'red_bulls',
      displayName: 'New York Red Bulls',
      description: 'Official Red Bulls red, yellow & navy',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Red Bulls Red', 0xFFED1E36),
        ThemeColor.hex('Red Bulls Yellow', 0xFFFEDE00),
        ThemeColor.hex('Red Bulls Navy', 0xFF0A2141),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['new york red bulls', 'red bulls', 'nyrb', 'metrostars'],
    ),

    'orlando_city': CanonicalTheme(
      id: 'orlando_city',
      displayName: 'Orlando City SC',
      description: 'Official Orlando City purple & white',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Orlando Purple', 0xFF5B2B82),
        ThemeColor.hex('Orlando White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['orlando city', 'orlando city sc', 'orlando soccer', 'lions'],
    ),

    'philadelphia_union': CanonicalTheme(
      id: 'philadelphia_union',
      displayName: 'Philadelphia Union',
      description: 'Official Union navy & gold',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Union Navy', 0xFF071B2C),
        ThemeColor.hex('Union Gold', 0xFFB49759),
        ThemeColor.hex('Union Blue', 0xFF2592C6),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['philadelphia union', 'union', 'philly union', 'philadelphia soccer'],
    ),

    'toronto_fc': CanonicalTheme(
      id: 'toronto_fc',
      displayName: 'Toronto FC',
      description: 'Official Toronto FC red & grey',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('TFC Red', 0xFFB81137),
        ThemeColor.hex('TFC Grey', 0xFFA7A8AA),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['toronto fc', 'tfc', 'toronto soccer', 'reds soccer'],
    ),

    // WESTERN CONFERENCE
    'austin_fc': CanonicalTheme(
      id: 'austin_fc',
      displayName: 'Austin FC',
      description: 'Official Austin FC verde & black',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Austin Verde', 0xFF00B140),
        ThemeColor.hex('Austin Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['austin fc', 'austin soccer', 'verde'],
    ),

    'colorado_rapids': CanonicalTheme(
      id: 'colorado_rapids',
      displayName: 'Colorado Rapids',
      description: 'Official Rapids burgundy & sky blue',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Rapids Burgundy', 0xFF862633),
        ThemeColor.hex('Rapids Blue', 0xFF8BB8E8),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['colorado rapids', 'rapids', 'colorado soccer', 'denver soccer'],
    ),

    'fc_dallas': CanonicalTheme(
      id: 'fc_dallas',
      displayName: 'FC Dallas',
      description: 'Official FC Dallas red & blue',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('FCD Red', 0xFFE81F3E),
        ThemeColor.hex('FCD Blue', 0xFF1164B4),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['fc dallas', 'dallas soccer', 'fcd', 'hoops'],
    ),

    'houston_dynamo': CanonicalTheme(
      id: 'houston_dynamo',
      displayName: 'Houston Dynamo FC',
      description: 'Official Dynamo orange & white',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Dynamo Orange', 0xFFF68712),
        ThemeColor.hex('Dynamo White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['houston dynamo', 'dynamo', 'houston soccer'],
    ),

    'lafc': CanonicalTheme(
      id: 'lafc',
      displayName: 'Los Angeles FC',
      description: 'Official LAFC black & gold',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('LAFC Black', 0xFF000000),
        ThemeColor.hex('LAFC Gold', 0xFFC39E6D),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['lafc', 'los angeles fc', 'la fc', '3252'],
    ),

    'la_galaxy': CanonicalTheme(
      id: 'la_galaxy',
      displayName: 'LA Galaxy',
      description: 'Official Galaxy navy, gold & white',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Galaxy Navy', 0xFF00245D),
        ThemeColor.hex('Galaxy Gold', 0xFFFDB913),
        ThemeColor.hex('Galaxy White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['la galaxy', 'los angeles galaxy', 'galaxy', 'la soccer'],
    ),

    'minnesota_united': CanonicalTheme(
      id: 'minnesota_united',
      displayName: 'Minnesota United FC',
      description: 'Official Loons grey & light blue',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Loons Grey', 0xFF8CD2F4),
        ThemeColor.hex('Loons Dark', 0xFF231F20),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['minnesota united', 'mnufc', 'loons', 'minnesota soccer'],
    ),

    'nashville_sc': CanonicalTheme(
      id: 'nashville_sc',
      displayName: 'Nashville SC',
      description: 'Official Nashville SC gold & navy',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Nashville Gold', 0xFFECE83A),
        ThemeColor.hex('Nashville Navy', 0xFF1F1646),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['nashville sc', 'nashville soccer', 'boys in gold'],
    ),

    'portland_timbers': CanonicalTheme(
      id: 'portland_timbers',
      displayName: 'Portland Timbers',
      description: 'Official Timbers green & gold',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Timbers Green', 0xFF004812),
        ThemeColor.hex('Timbers Gold', 0xFFD69A00),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['portland timbers', 'timbers', 'portland soccer', 'rctid'],
    ),

    'real_salt_lake': CanonicalTheme(
      id: 'real_salt_lake',
      displayName: 'Real Salt Lake',
      description: 'Official RSL claret & cobalt',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('RSL Claret', 0xFFB30838),
        ThemeColor.hex('RSL Cobalt', 0xFF013A81),
        ThemeColor.hex('RSL Gold', 0xFFF1AA00),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['real salt lake', 'rsl', 'salt lake soccer', 'utah soccer'],
    ),

    'san_jose_earthquakes': CanonicalTheme(
      id: 'san_jose_earthquakes',
      displayName: 'San Jose Earthquakes',
      description: 'Official Quakes blue & black',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Quakes Blue', 0xFF0067B1),
        ThemeColor.hex('Quakes Black', 0xFF000000),
        ThemeColor.hex('Quakes Red', 0xFFE31837),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['san jose earthquakes', 'earthquakes', 'quakes', 'san jose soccer'],
    ),

    'seattle_sounders': CanonicalTheme(
      id: 'seattle_sounders',
      displayName: 'Seattle Sounders FC',
      description: 'Official Sounders rave green & blue',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Sounders Green', 0xFF5D9741),
        ThemeColor.hex('Sounders Blue', 0xFF005595),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['seattle sounders', 'sounders', 'seattle soccer', 'rave green'],
    ),

    'sporting_kc': CanonicalTheme(
      id: 'sporting_kc',
      displayName: 'Sporting Kansas City',
      description: 'Official Sporting KC blue & white',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('SKC Blue', 0xFF002F65),
        ThemeColor.hex('SKC Light Blue', 0xFF91B0D5),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['sporting kansas city', 'sporting kc', 'skc', 'kansas city soccer'],
    ),

    'st_louis_city': CanonicalTheme(
      id: 'st_louis_city',
      displayName: 'St. Louis CITY SC',
      description: 'Official CITY red & navy',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('CITY Red', 0xFFD52B1E),
        ThemeColor.hex('CITY Navy', 0xFF0F1E46),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['st louis city', 'city sc', 'st louis soccer', 'stl soccer'],
    ),

    'vancouver_whitecaps': CanonicalTheme(
      id: 'vancouver_whitecaps',
      displayName: 'Vancouver Whitecaps FC',
      description: 'Official Whitecaps blue & white',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Whitecaps Blue', 0xFF00245E),
        ThemeColor.hex('Whitecaps White', 0xFFFFFFFF),
        ThemeColor.hex('Whitecaps Grey', 0xFF97999B),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['vancouver whitecaps', 'whitecaps', 'vancouver soccer'],
    ),

    // New expansion teams
    'san_diego_fc': CanonicalTheme(
      id: 'san_diego_fc',
      displayName: 'San Diego FC',
      description: 'Official San Diego FC colors',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('SD Navy', 0xFF000033),
        ThemeColor.hex('SD Turquoise', 0xFF33CCCC),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['san diego fc', 'san diego soccer', 'sd fc'],
    ),
  };

  /// NWSL Teams
  static final Map<String, CanonicalTheme> nwslTeams = {
    'angel_city': CanonicalTheme(
      id: 'angel_city',
      displayName: 'Angel City FC',
      description: 'Official Angel City black, white & red',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Angel City Sol Rose', 0xFFFF5C5C),
        ThemeColor.hex('Angel City White', 0xFFFFFFFF),
        ThemeColor.hex('Angel City Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['angel city', 'angel city fc', 'acfc', 'la womens soccer'],
    ),

    'chicago_red_stars': CanonicalTheme(
      id: 'chicago_red_stars',
      displayName: 'Chicago Red Stars',
      description: 'Official Red Stars blue & red',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Red Stars Navy', 0xFF003366),
        ThemeColor.hex('Red Stars Red', 0xFFEF3E42),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['chicago red stars', 'red stars', 'chicago womens soccer'],
    ),

    'kansas_city_current': CanonicalTheme(
      id: 'kansas_city_current',
      displayName: 'Kansas City Current',
      description: 'Official Current teal & red',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Current Teal', 0xFF00A3AD),
        ThemeColor.hex('Current Red', 0xFFD7263D),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['kansas city current', 'kc current', 'current', 'kc womens soccer'],
    ),

    'nj_ny_gotham': CanonicalTheme(
      id: 'nj_ny_gotham',
      displayName: 'NJ/NY Gotham FC',
      description: 'Official Gotham black & gold',
      icon: Icons.sports_soccer,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Gotham Black', 0xFF000000),
        ThemeColor.hex('Gotham Gold', 0xFFF4C300),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['gotham fc', 'nj ny gotham', 'gotham', 'sky blue fc'],
    ),
  };

  /// Get all MLS teams
  static List<CanonicalTheme> get allMlsTeams => mlsTeams.values.toList();

  /// Get all NWSL teams
  static List<CanonicalTheme> get allNwslTeams => nwslTeams.values.toList();
}
