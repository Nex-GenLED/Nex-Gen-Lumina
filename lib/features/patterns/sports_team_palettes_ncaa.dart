import 'package:flutter/material.dart';
import 'package:nexgen_command/features/patterns/canonical_palettes.dart';

/// NCAA Division 1 Football & Basketball team colors with official HEX codes
/// Includes Power 4 conferences and major programs

class NcaaTeamPalettes {
  NcaaTeamPalettes._();

  /// NCAA Football Teams - Major programs with official colors
  static final Map<String, CanonicalTheme> ncaaFootballTeams = {
    // SEC
    'alabama': CanonicalTheme(
      id: 'alabama',
      displayName: 'Alabama Crimson Tide',
      description: 'Official Alabama crimson & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Alabama Crimson', 0xFF9E1B32),
        ThemeColor.hex('Alabama White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['alabama', 'crimson tide', 'bama', 'roll tide', 'alabama football'],
    ),

    'auburn': CanonicalTheme(
      id: 'auburn',
      displayName: 'Auburn Tigers',
      description: 'Official Auburn orange & navy',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Auburn Orange', 0xFFDD550C),
        ThemeColor.hex('Auburn Navy', 0xFF03244D),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['auburn', 'auburn tigers', 'war eagle', 'auburn football'],
    ),

    'georgia': CanonicalTheme(
      id: 'georgia',
      displayName: 'Georgia Bulldogs',
      description: 'Official Georgia red & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Georgia Red', 0xFFBA0C2F),
        ThemeColor.hex('Georgia Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['georgia', 'georgia bulldogs', 'uga', 'dawgs', 'go dawgs'],
    ),

    'lsu': CanonicalTheme(
      id: 'lsu',
      displayName: 'LSU Tigers',
      description: 'Official LSU purple & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('LSU Purple', 0xFF461D7C),
        ThemeColor.hex('LSU Gold', 0xFFFDD023),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['lsu', 'lsu tigers', 'geaux tigers', 'louisiana state'],
    ),

    'florida': CanonicalTheme(
      id: 'florida',
      displayName: 'Florida Gators',
      description: 'Official Florida orange & blue',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Florida Orange', 0xFFFA4616),
        ThemeColor.hex('Florida Blue', 0xFF0021A5),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['florida', 'florida gators', 'uf', 'gators', 'go gators'],
    ),

    'tennessee': CanonicalTheme(
      id: 'tennessee_vols',
      displayName: 'Tennessee Volunteers',
      description: 'Official Tennessee orange & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Tennessee Orange', 0xFFFF8200),
        ThemeColor.hex('Tennessee White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['tennessee', 'tennessee vols', 'vols', 'volunteers', 'rocky top'],
    ),

    'texas_am': CanonicalTheme(
      id: 'texas_am',
      displayName: 'Texas A&M Aggies',
      description: 'Official A&M maroon & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Aggie Maroon', 0xFF500000),
        ThemeColor.hex('Aggie White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['texas a&m', 'aggies', 'tamu', 'gig em', 'texas am football'],
    ),

    'ole_miss': CanonicalTheme(
      id: 'ole_miss',
      displayName: 'Ole Miss Rebels',
      description: 'Official Ole Miss red & navy',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Ole Miss Red', 0xFFCE1126),
        ThemeColor.hex('Ole Miss Navy', 0xFF14213D),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['ole miss', 'rebels', 'mississippi', 'hotty toddy'],
    ),

    'mississippi_state': CanonicalTheme(
      id: 'mississippi_state',
      displayName: 'Mississippi State Bulldogs',
      description: 'Official MSU maroon & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('MSU Maroon', 0xFF660000),
        ThemeColor.hex('MSU White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['mississippi state', 'miss state', 'msu bulldogs', 'hail state'],
    ),

    'south_carolina': CanonicalTheme(
      id: 'south_carolina',
      displayName: 'South Carolina Gamecocks',
      description: 'Official South Carolina garnet & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('USC Garnet', 0xFF73000A),
        ThemeColor.hex('USC Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['south carolina', 'gamecocks', 'usc gamecocks', 'go cocks'],
    ),

    'kentucky': CanonicalTheme(
      id: 'kentucky',
      displayName: 'Kentucky Wildcats',
      description: 'Official Kentucky blue & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Kentucky Blue', 0xFF0033A0),
        ThemeColor.hex('Kentucky White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['kentucky', 'kentucky wildcats', 'uk', 'wildcats', 'big blue nation'],
    ),

    'arkansas': CanonicalTheme(
      id: 'arkansas',
      displayName: 'Arkansas Razorbacks',
      description: 'Official Arkansas cardinal & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Arkansas Cardinal', 0xFF9D2235),
        ThemeColor.hex('Arkansas White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['arkansas', 'razorbacks', 'hogs', 'woo pig', 'arkansas football'],
    ),

    'vanderbilt': CanonicalTheme(
      id: 'vanderbilt',
      displayName: 'Vanderbilt Commodores',
      description: 'Official Vanderbilt black & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Vandy Black', 0xFF000000),
        ThemeColor.hex('Vandy Gold', 0xFFCFAE70),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['vanderbilt', 'commodores', 'vandy', 'anchor down'],
    ),

    'missouri': CanonicalTheme(
      id: 'missouri',
      displayName: 'Missouri Tigers',
      description: 'Official Missouri black & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Mizzou Black', 0xFF000000),
        ThemeColor.hex('Mizzou Gold', 0xFFF1B82D),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['missouri', 'mizzou', 'missouri tigers', 'mizzou football'],
    ),

    // BIG TEN
    'ohio_state': CanonicalTheme(
      id: 'ohio_state',
      displayName: 'Ohio State Buckeyes',
      description: 'Official Ohio State scarlet & grey',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('OSU Scarlet', 0xFFBB0000),
        ThemeColor.hex('OSU Grey', 0xFF666666),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['ohio state', 'buckeyes', 'osu', 'the ohio state', 'go bucks'],
    ),

    'michigan': CanonicalTheme(
      id: 'michigan',
      displayName: 'Michigan Wolverines',
      description: 'Official Michigan maize & blue',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Michigan Maize', 0xFFFFCB05),
        ThemeColor.hex('Michigan Blue', 0xFF00274C),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['michigan', 'wolverines', 'umich', 'go blue', 'michigan football'],
    ),

    'penn_state': CanonicalTheme(
      id: 'penn_state',
      displayName: 'Penn State Nittany Lions',
      description: 'Official Penn State blue & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('PSU Blue', 0xFF041E42),
        ThemeColor.hex('PSU White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['penn state', 'nittany lions', 'psu', 'we are'],
    ),

    'michigan_state': CanonicalTheme(
      id: 'michigan_state',
      displayName: 'Michigan State Spartans',
      description: 'Official MSU green & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('MSU Green', 0xFF18453B),
        ThemeColor.hex('MSU White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['michigan state', 'spartans', 'msu', 'sparty', 'go green'],
    ),

    'wisconsin': CanonicalTheme(
      id: 'wisconsin',
      displayName: 'Wisconsin Badgers',
      description: 'Official Wisconsin red & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Wisconsin Red', 0xFFC5050C),
        ThemeColor.hex('Wisconsin White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['wisconsin', 'badgers', 'uw', 'on wisconsin'],
    ),

    'iowa': CanonicalTheme(
      id: 'iowa',
      displayName: 'Iowa Hawkeyes',
      description: 'Official Iowa black & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Iowa Black', 0xFF000000),
        ThemeColor.hex('Iowa Gold', 0xFFFFCD00),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['iowa', 'hawkeyes', 'iowa hawkeyes', 'go hawks'],
    ),

    'nebraska': CanonicalTheme(
      id: 'nebraska',
      displayName: 'Nebraska Cornhuskers',
      description: 'Official Nebraska scarlet & cream',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Nebraska Scarlet', 0xFFE41C38),
        ThemeColor.hex('Nebraska Cream', 0xFFF5F1E7),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['nebraska', 'cornhuskers', 'huskers', 'gbr', 'go big red'],
    ),

    'purdue': CanonicalTheme(
      id: 'purdue',
      displayName: 'Purdue Boilermakers',
      description: 'Official Purdue black & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Purdue Black', 0xFF000000),
        ThemeColor.hex('Purdue Gold', 0xFFCFB991),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['purdue', 'boilermakers', 'boilers', 'purdue football'],
    ),

    'indiana': CanonicalTheme(
      id: 'indiana',
      displayName: 'Indiana Hoosiers',
      description: 'Official Indiana crimson & cream',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Indiana Crimson', 0xFF990000),
        ThemeColor.hex('Indiana Cream', 0xFFF5F1E7),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['indiana', 'hoosiers', 'iu', 'indiana football'],
    ),

    'minnesota': CanonicalTheme(
      id: 'minnesota',
      displayName: 'Minnesota Golden Gophers',
      description: 'Official Minnesota maroon & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Minnesota Maroon', 0xFF7A0019),
        ThemeColor.hex('Minnesota Gold', 0xFFFFCC33),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['minnesota', 'gophers', 'golden gophers', 'ski u mah'],
    ),

    'northwestern': CanonicalTheme(
      id: 'northwestern',
      displayName: 'Northwestern Wildcats',
      description: 'Official Northwestern purple & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Northwestern Purple', 0xFF4E2A84),
        ThemeColor.hex('Northwestern White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['northwestern', 'wildcats nu', 'northwestern wildcats'],
    ),

    'illinois': CanonicalTheme(
      id: 'illinois',
      displayName: 'Illinois Fighting Illini',
      description: 'Official Illinois orange & blue',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Illinois Orange', 0xFFE84A27),
        ThemeColor.hex('Illinois Blue', 0xFF13294B),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['illinois', 'illini', 'fighting illini', 'illinois football'],
    ),

    'rutgers': CanonicalTheme(
      id: 'rutgers',
      displayName: 'Rutgers Scarlet Knights',
      description: 'Official Rutgers scarlet & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Rutgers Scarlet', 0xFFCC0033),
        ThemeColor.hex('Rutgers White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['rutgers', 'scarlet knights', 'ru', 'rutgers football'],
    ),

    'maryland': CanonicalTheme(
      id: 'maryland',
      displayName: 'Maryland Terrapins',
      description: 'Official Maryland red, gold, black & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Maryland Red', 0xFFE03A3E),
        ThemeColor.hex('Maryland Gold', 0xFFFFD520),
        ThemeColor.hex('Maryland Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['maryland', 'terrapins', 'terps', 'fear the turtle'],
    ),

    // Big 12 (new expansion)
    'texas': CanonicalTheme(
      id: 'texas',
      displayName: 'Texas Longhorns',
      description: 'Official Texas burnt orange & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Texas Orange', 0xFFBF5700),
        ThemeColor.hex('Texas White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['texas', 'longhorns', 'ut', 'hook em', 'texas football'],
    ),

    'oklahoma': CanonicalTheme(
      id: 'oklahoma',
      displayName: 'Oklahoma Sooners',
      description: 'Official Oklahoma crimson & cream',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Oklahoma Crimson', 0xFF841617),
        ThemeColor.hex('Oklahoma Cream', 0xFFFDF9D8),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['oklahoma', 'sooners', 'ou', 'boomer sooner'],
    ),

    'oklahoma_state': CanonicalTheme(
      id: 'oklahoma_state',
      displayName: 'Oklahoma State Cowboys',
      description: 'Official OSU orange & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('OSU Orange', 0xFFFF6600),
        ThemeColor.hex('OSU Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['oklahoma state', 'cowboys osu', 'osu cowboys', 'go pokes'],
    ),

    'tcu': CanonicalTheme(
      id: 'tcu',
      displayName: 'TCU Horned Frogs',
      description: 'Official TCU purple & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('TCU Purple', 0xFF4D1979),
        ThemeColor.hex('TCU White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['tcu', 'horned frogs', 'texas christian', 'go frogs'],
    ),

    'baylor': CanonicalTheme(
      id: 'baylor',
      displayName: 'Baylor Bears',
      description: 'Official Baylor green & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Baylor Green', 0xFF154733),
        ThemeColor.hex('Baylor Gold', 0xFFFFB81C),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['baylor', 'bears', 'baylor bears', 'sic em'],
    ),

    'kansas_state': CanonicalTheme(
      id: 'kansas_state',
      displayName: 'Kansas State Wildcats',
      description: 'Official K-State purple & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('K-State Purple', 0xFF512888),
        ThemeColor.hex('K-State White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['kansas state', 'k-state', 'wildcats ksu', 'emaw'],
    ),

    'kansas': CanonicalTheme(
      id: 'kansas',
      displayName: 'Kansas Jayhawks',
      description: 'Official Kansas crimson & blue',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Kansas Blue', 0xFF0051BA),
        ThemeColor.hex('Kansas Crimson', 0xFFE8000D),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['kansas', 'jayhawks', 'ku', 'rock chalk'],
    ),

    'iowa_state': CanonicalTheme(
      id: 'iowa_state',
      displayName: 'Iowa State Cyclones',
      description: 'Official Iowa State cardinal & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('ISU Cardinal', 0xFFC8102E),
        ThemeColor.hex('ISU Gold', 0xFFF1BE48),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['iowa state', 'cyclones', 'isu', 'go cyclones'],
    ),

    'west_virginia': CanonicalTheme(
      id: 'west_virginia',
      displayName: 'West Virginia Mountaineers',
      description: 'Official WVU blue & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('WVU Blue', 0xFF002855),
        ThemeColor.hex('WVU Gold', 0xFFEAAA00),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['west virginia', 'mountaineers', 'wvu', 'lets go mountaineers'],
    ),

    'texas_tech': CanonicalTheme(
      id: 'texas_tech',
      displayName: 'Texas Tech Red Raiders',
      description: 'Official Texas Tech scarlet & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Tech Scarlet', 0xFFCC0000),
        ThemeColor.hex('Tech Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['texas tech', 'red raiders', 'ttu', 'wreck em'],
    ),

    // ACC (remaining)
    'clemson': CanonicalTheme(
      id: 'clemson',
      displayName: 'Clemson Tigers',
      description: 'Official Clemson orange & purple',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Clemson Orange', 0xFFF56600),
        ThemeColor.hex('Clemson Purple', 0xFF522D80),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['clemson', 'clemson tigers', 'go tigers', 'all in'],
    ),

    'florida_state': CanonicalTheme(
      id: 'florida_state',
      displayName: 'Florida State Seminoles',
      description: 'Official FSU garnet & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('FSU Garnet', 0xFF782F40),
        ThemeColor.hex('FSU Gold', 0xFFCEB888),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['florida state', 'seminoles', 'fsu', 'noles', 'go noles'],
    ),

    'miami': CanonicalTheme(
      id: 'miami_hurricanes',
      displayName: 'Miami Hurricanes',
      description: 'Official Miami orange, green & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Miami Orange', 0xFFF47321),
        ThemeColor.hex('Miami Green', 0xFF005030),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['miami hurricanes', 'hurricanes', 'the u', 'canes'],
    ),

    'notre_dame': CanonicalTheme(
      id: 'notre_dame',
      displayName: 'Notre Dame Fighting Irish',
      description: 'Official Notre Dame gold & blue',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('ND Gold', 0xFFC99700),
        ThemeColor.hex('ND Blue', 0xFF0C2340),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['notre dame', 'fighting irish', 'nd', 'irish', 'go irish'],
    ),

    'nc_state': CanonicalTheme(
      id: 'nc_state',
      displayName: 'NC State Wolfpack',
      description: 'Official NC State red & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('NC State Red', 0xFFCC0000),
        ThemeColor.hex('NC State White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['nc state', 'wolfpack', 'ncsu', 'go pack'],
    ),

    'unc': CanonicalTheme(
      id: 'unc',
      displayName: 'North Carolina Tar Heels',
      description: 'Official UNC carolina blue & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Carolina Blue', 0xFF7BAFD4),
        ThemeColor.hex('UNC White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['unc', 'tar heels', 'north carolina', 'carolina', 'go heels'],
    ),

    'duke': CanonicalTheme(
      id: 'duke',
      displayName: 'Duke Blue Devils',
      description: 'Official Duke blue & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Duke Blue', 0xFF003087),
        ThemeColor.hex('Duke White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['duke', 'blue devils', 'duke football'],
    ),

    'virginia_tech': CanonicalTheme(
      id: 'virginia_tech',
      displayName: 'Virginia Tech Hokies',
      description: 'Official VT maroon & orange',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('VT Maroon', 0xFF660000),
        ThemeColor.hex('VT Orange', 0xFFFF6600),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['virginia tech', 'hokies', 'vt', 'go hokies'],
    ),

    'virginia': CanonicalTheme(
      id: 'virginia',
      displayName: 'Virginia Cavaliers',
      description: 'Official UVA orange & navy',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('UVA Orange', 0xFFF84C1E),
        ThemeColor.hex('UVA Navy', 0xFF232D4B),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['virginia', 'cavaliers', 'uva', 'wahoos', 'hoos'],
    ),

    // PAC-12 Remnants / Big 12 additions
    'oregon': CanonicalTheme(
      id: 'oregon',
      displayName: 'Oregon Ducks',
      description: 'Official Oregon green & yellow',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Oregon Green', 0xFF154733),
        ThemeColor.hex('Oregon Yellow', 0xFFFEE123),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['oregon', 'ducks', 'oregon ducks', 'go ducks', 'sco ducks'],
    ),

    'usc': CanonicalTheme(
      id: 'usc',
      displayName: 'USC Trojans',
      description: 'Official USC cardinal & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('USC Cardinal', 0xFF990000),
        ThemeColor.hex('USC Gold', 0xFFFFC72C),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['usc', 'trojans', 'usc trojans', 'fight on', 'southern california'],
    ),

    'ucla': CanonicalTheme(
      id: 'ucla',
      displayName: 'UCLA Bruins',
      description: 'Official UCLA blue & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('UCLA Blue', 0xFF2D68C4),
        ThemeColor.hex('UCLA Gold', 0xFFF2A900),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['ucla', 'bruins', 'ucla bruins', 'go bruins'],
    ),

    'washington': CanonicalTheme(
      id: 'washington',
      displayName: 'Washington Huskies',
      description: 'Official UW purple & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('UW Purple', 0xFF4B2E83),
        ThemeColor.hex('UW Gold', 0xFFB7A57A),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['washington', 'huskies', 'uw', 'washington huskies', 'go dawgs uw'],
    ),

    'arizona': CanonicalTheme(
      id: 'arizona',
      displayName: 'Arizona Wildcats',
      description: 'Official Arizona red & navy',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Arizona Red', 0xFFCC0033),
        ThemeColor.hex('Arizona Navy', 0xFF003366),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['arizona', 'wildcats ua', 'arizona wildcats', 'bear down'],
    ),

    'arizona_state': CanonicalTheme(
      id: 'arizona_state',
      displayName: 'Arizona State Sun Devils',
      description: 'Official ASU maroon & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('ASU Maroon', 0xFF8C1D40),
        ThemeColor.hex('ASU Gold', 0xFFFFC627),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['arizona state', 'sun devils', 'asu', 'fork em'],
    ),

    'utah': CanonicalTheme(
      id: 'utah',
      displayName: 'Utah Utes',
      description: 'Official Utah red & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Utah Red', 0xFFCC0000),
        ThemeColor.hex('Utah White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['utah', 'utes', 'utah utes', 'go utes'],
    ),

    'colorado': CanonicalTheme(
      id: 'colorado',
      displayName: 'Colorado Buffaloes',
      description: 'Official Colorado black & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('CU Black', 0xFF000000),
        ThemeColor.hex('CU Gold', 0xFFCFB87C),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['colorado', 'buffaloes', 'buffs', 'cu', 'sko buffs'],
    ),

    // Other notable programs
    'byu': CanonicalTheme(
      id: 'byu',
      displayName: 'BYU Cougars',
      description: 'Official BYU blue & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('BYU Blue', 0xFF002E5D),
        ThemeColor.hex('BYU White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['byu', 'cougars byu', 'brigham young', 'rise and shout'],
    ),

    'cincinnati': CanonicalTheme(
      id: 'cincinnati_bearcats',
      displayName: 'Cincinnati Bearcats',
      description: 'Official Cincinnati red & black',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('UC Red', 0xFFE00122),
        ThemeColor.hex('UC Black', 0xFF000000),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['cincinnati bearcats', 'bearcats', 'uc', 'go bearcats'],
    ),

    'ucf': CanonicalTheme(
      id: 'ucf',
      displayName: 'UCF Knights',
      description: 'Official UCF black & gold',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('UCF Black', 0xFF000000),
        ThemeColor.hex('UCF Gold', 0xFFBA9B37),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['ucf', 'knights', 'ucf knights', 'charge on'],
    ),

    'houston': CanonicalTheme(
      id: 'houston_cougars',
      displayName: 'Houston Cougars',
      description: 'Official Houston red & white',
      icon: Icons.sports_football,
      category: ThemeCategory.sports,
      canonicalColors: [
        ThemeColor.hex('Houston Red', 0xFFC8102E),
        ThemeColor.hex('Houston White', 0xFFFFFFFF),
      ],
      suggestedEffects: [12, 41, 65, 0],
      defaultSpeed: 85,
      defaultIntensity: 180,
      aliases: ['houston cougars', 'cougars uh', 'uh', 'go coogs'],
    ),
  };

  /// Get all NCAA Football teams
  static List<CanonicalTheme> get allNcaaFootballTeams => ncaaFootballTeams.values.toList();
}
