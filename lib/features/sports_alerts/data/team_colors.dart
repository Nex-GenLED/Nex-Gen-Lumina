import 'package:flutter/material.dart';

import '../models/sport_type.dart';

/// Official team color pair and metadata for LED alert effects.
class TeamColors {
  final Color primary;
  final Color secondary;
  final String teamName;
  final SportType sport;
  final String espnTeamId;

  const TeamColors({
    required this.primary,
    required this.secondary,
    required this.teamName,
    required this.sport,
    required this.espnTeamId,
  });
}

/// Master lookup of every team, keyed by slug (e.g. 'nfl_chiefs').
const Map<String, TeamColors> kTeamColors = {
  // =========================================================================
  //  NFL — 32 teams
  // =========================================================================

  // AFC East
  'nfl_bills': TeamColors(
    primary: Color(0xFF00338D),
    secondary: Color(0xFFC60C30),
    teamName: 'Buffalo Bills',
    sport: SportType.nfl,
    espnTeamId: '2',
  ),
  'nfl_dolphins': TeamColors(
    primary: Color(0xFF008E97),
    secondary: Color(0xFFFC4C02),
    teamName: 'Miami Dolphins',
    sport: SportType.nfl,
    espnTeamId: '15',
  ),
  'nfl_patriots': TeamColors(
    primary: Color(0xFF002244),
    secondary: Color(0xFFC60C30),
    teamName: 'New England Patriots',
    sport: SportType.nfl,
    espnTeamId: '17',
  ),
  'nfl_jets': TeamColors(
    primary: Color(0xFF125740),
    secondary: Color(0xFFFFFFFF),
    teamName: 'New York Jets',
    sport: SportType.nfl,
    espnTeamId: '20',
  ),

  // AFC North
  'nfl_ravens': TeamColors(
    primary: Color(0xFF241773),
    secondary: Color(0xFF9E7C0C),
    teamName: 'Baltimore Ravens',
    sport: SportType.nfl,
    espnTeamId: '33',
  ),
  'nfl_bengals': TeamColors(
    primary: Color(0xFFFB4F14),
    secondary: Color(0xFF000000),
    teamName: 'Cincinnati Bengals',
    sport: SportType.nfl,
    espnTeamId: '4',
  ),
  'nfl_browns': TeamColors(
    primary: Color(0xFF311D00),
    secondary: Color(0xFFFF3C00),
    teamName: 'Cleveland Browns',
    sport: SportType.nfl,
    espnTeamId: '5',
  ),
  'nfl_steelers': TeamColors(
    primary: Color(0xFFFFB612),
    secondary: Color(0xFF101820),
    teamName: 'Pittsburgh Steelers',
    sport: SportType.nfl,
    espnTeamId: '23',
  ),

  // AFC South
  'nfl_texans': TeamColors(
    primary: Color(0xFF03202F),
    secondary: Color(0xFFA71930),
    teamName: 'Houston Texans',
    sport: SportType.nfl,
    espnTeamId: '34',
  ),
  'nfl_colts': TeamColors(
    primary: Color(0xFF002C5F),
    secondary: Color(0xFFA2AAAD),
    teamName: 'Indianapolis Colts',
    sport: SportType.nfl,
    espnTeamId: '11',
  ),
  'nfl_jaguars': TeamColors(
    primary: Color(0xFF006778),
    secondary: Color(0xFF9F792C),
    teamName: 'Jacksonville Jaguars',
    sport: SportType.nfl,
    espnTeamId: '30',
  ),
  'nfl_titans': TeamColors(
    primary: Color(0xFF0C2340),
    secondary: Color(0xFF4B92DB),
    teamName: 'Tennessee Titans',
    sport: SportType.nfl,
    espnTeamId: '10',
  ),

  // AFC West
  'nfl_broncos': TeamColors(
    primary: Color(0xFFFB4F14),
    secondary: Color(0xFF002244),
    teamName: 'Denver Broncos',
    sport: SportType.nfl,
    espnTeamId: '7',
  ),
  'nfl_chiefs': TeamColors(
    primary: Color(0xFFE31837),
    secondary: Color(0xFFFFB81C),
    teamName: 'Kansas City Chiefs',
    sport: SportType.nfl,
    espnTeamId: '12',
  ),
  'nfl_raiders': TeamColors(
    primary: Color(0xFFA5ACAF),
    secondary: Color(0xFF000000),
    teamName: 'Las Vegas Raiders',
    sport: SportType.nfl,
    espnTeamId: '13',
  ),
  'nfl_chargers': TeamColors(
    primary: Color(0xFF0080C6),
    secondary: Color(0xFFFFC20E),
    teamName: 'Los Angeles Chargers',
    sport: SportType.nfl,
    espnTeamId: '24',
  ),

  // NFC East
  'nfl_cowboys': TeamColors(
    primary: Color(0xFF003594),
    secondary: Color(0xFF869397),
    teamName: 'Dallas Cowboys',
    sport: SportType.nfl,
    espnTeamId: '6',
  ),
  'nfl_giants': TeamColors(
    primary: Color(0xFF0B2265),
    secondary: Color(0xFFA71930),
    teamName: 'New York Giants',
    sport: SportType.nfl,
    espnTeamId: '19',
  ),
  'nfl_eagles': TeamColors(
    primary: Color(0xFF004C54),
    secondary: Color(0xFFA5ACAF),
    teamName: 'Philadelphia Eagles',
    sport: SportType.nfl,
    espnTeamId: '21',
  ),
  'nfl_commanders': TeamColors(
    primary: Color(0xFF5A1414),
    secondary: Color(0xFFFFB612),
    teamName: 'Washington Commanders',
    sport: SportType.nfl,
    espnTeamId: '28',
  ),

  // NFC North
  'nfl_bears': TeamColors(
    primary: Color(0xFF0B162A),
    secondary: Color(0xFFC83803),
    teamName: 'Chicago Bears',
    sport: SportType.nfl,
    espnTeamId: '3',
  ),
  'nfl_lions': TeamColors(
    primary: Color(0xFF0076B6),
    secondary: Color(0xFFB0B7BC),
    teamName: 'Detroit Lions',
    sport: SportType.nfl,
    espnTeamId: '8',
  ),
  'nfl_packers': TeamColors(
    primary: Color(0xFF203731),
    secondary: Color(0xFFFFB612),
    teamName: 'Green Bay Packers',
    sport: SportType.nfl,
    espnTeamId: '9',
  ),
  'nfl_vikings': TeamColors(
    primary: Color(0xFF4F2683),
    secondary: Color(0xFFFFC62F),
    teamName: 'Minnesota Vikings',
    sport: SportType.nfl,
    espnTeamId: '16',
  ),

  // NFC South
  'nfl_falcons': TeamColors(
    primary: Color(0xFFA71930),
    secondary: Color(0xFF000000),
    teamName: 'Atlanta Falcons',
    sport: SportType.nfl,
    espnTeamId: '1',
  ),
  'nfl_panthers': TeamColors(
    primary: Color(0xFF0085CA),
    secondary: Color(0xFF101820),
    teamName: 'Carolina Panthers',
    sport: SportType.nfl,
    espnTeamId: '29',
  ),
  'nfl_saints': TeamColors(
    primary: Color(0xFFD3BC8D),
    secondary: Color(0xFF101820),
    teamName: 'New Orleans Saints',
    sport: SportType.nfl,
    espnTeamId: '18',
  ),
  'nfl_buccaneers': TeamColors(
    primary: Color(0xFFD50A0A),
    secondary: Color(0xFF34302B),
    teamName: 'Tampa Bay Buccaneers',
    sport: SportType.nfl,
    espnTeamId: '27',
  ),

  // NFC West
  'nfl_cardinals': TeamColors(
    primary: Color(0xFF97233F),
    secondary: Color(0xFF000000),
    teamName: 'Arizona Cardinals',
    sport: SportType.nfl,
    espnTeamId: '22',
  ),
  'nfl_rams': TeamColors(
    primary: Color(0xFF003594),
    secondary: Color(0xFFFFA300),
    teamName: 'Los Angeles Rams',
    sport: SportType.nfl,
    espnTeamId: '14',
  ),
  'nfl_49ers': TeamColors(
    primary: Color(0xFFAA0000),
    secondary: Color(0xFFB3995D),
    teamName: 'San Francisco 49ers',
    sport: SportType.nfl,
    espnTeamId: '25',
  ),
  'nfl_seahawks': TeamColors(
    primary: Color(0xFF002244),
    secondary: Color(0xFF69BE28),
    teamName: 'Seattle Seahawks',
    sport: SportType.nfl,
    espnTeamId: '26',
  ),

  // =========================================================================
  //  NBA — 30 teams
  // =========================================================================

  // Atlantic
  'nba_celtics': TeamColors(
    primary: Color(0xFF007A33),
    secondary: Color(0xFFBA9653),
    teamName: 'Boston Celtics',
    sport: SportType.nba,
    espnTeamId: '2',
  ),
  'nba_nets': TeamColors(
    primary: Color(0xFF000000),
    secondary: Color(0xFFFFFFFF),
    teamName: 'Brooklyn Nets',
    sport: SportType.nba,
    espnTeamId: '17',
  ),
  'nba_knicks': TeamColors(
    primary: Color(0xFF006BB6),
    secondary: Color(0xFFF58426),
    teamName: 'New York Knicks',
    sport: SportType.nba,
    espnTeamId: '18',
  ),
  'nba_76ers': TeamColors(
    primary: Color(0xFF006BB6),
    secondary: Color(0xFFED174C),
    teamName: 'Philadelphia 76ers',
    sport: SportType.nba,
    espnTeamId: '20',
  ),
  'nba_raptors': TeamColors(
    primary: Color(0xFFCE1141),
    secondary: Color(0xFF000000),
    teamName: 'Toronto Raptors',
    sport: SportType.nba,
    espnTeamId: '28',
  ),

  // Central
  'nba_bulls': TeamColors(
    primary: Color(0xFFCE1141),
    secondary: Color(0xFF000000),
    teamName: 'Chicago Bulls',
    sport: SportType.nba,
    espnTeamId: '4',
  ),
  'nba_cavaliers': TeamColors(
    primary: Color(0xFF860038),
    secondary: Color(0xFF041E42),
    teamName: 'Cleveland Cavaliers',
    sport: SportType.nba,
    espnTeamId: '5',
  ),
  'nba_pistons': TeamColors(
    primary: Color(0xFFC8102E),
    secondary: Color(0xFF1D42BA),
    teamName: 'Detroit Pistons',
    sport: SportType.nba,
    espnTeamId: '8',
  ),
  'nba_pacers': TeamColors(
    primary: Color(0xFF002D62),
    secondary: Color(0xFFFDBA21),
    teamName: 'Indiana Pacers',
    sport: SportType.nba,
    espnTeamId: '11',
  ),
  'nba_bucks': TeamColors(
    primary: Color(0xFF00471B),
    secondary: Color(0xFFEEE1C6),
    teamName: 'Milwaukee Bucks',
    sport: SportType.nba,
    espnTeamId: '15',
  ),

  // Southeast
  'nba_hawks': TeamColors(
    primary: Color(0xFFE03A3E),
    secondary: Color(0xFFC1D32F),
    teamName: 'Atlanta Hawks',
    sport: SportType.nba,
    espnTeamId: '1',
  ),
  'nba_hornets': TeamColors(
    primary: Color(0xFF1D1160),
    secondary: Color(0xFF00788C),
    teamName: 'Charlotte Hornets',
    sport: SportType.nba,
    espnTeamId: '30',
  ),
  'nba_heat': TeamColors(
    primary: Color(0xFF98002E),
    secondary: Color(0xFFF9A01B),
    teamName: 'Miami Heat',
    sport: SportType.nba,
    espnTeamId: '14',
  ),
  'nba_magic': TeamColors(
    primary: Color(0xFF0077C0),
    secondary: Color(0xFFC4CED4),
    teamName: 'Orlando Magic',
    sport: SportType.nba,
    espnTeamId: '19',
  ),
  'nba_wizards': TeamColors(
    primary: Color(0xFF002B5C),
    secondary: Color(0xFFE31837),
    teamName: 'Washington Wizards',
    sport: SportType.nba,
    espnTeamId: '27',
  ),

  // Northwest
  'nba_nuggets': TeamColors(
    primary: Color(0xFF0E2240),
    secondary: Color(0xFFFEC524),
    teamName: 'Denver Nuggets',
    sport: SportType.nba,
    espnTeamId: '7',
  ),
  'nba_timberwolves': TeamColors(
    primary: Color(0xFF0C2340),
    secondary: Color(0xFF236192),
    teamName: 'Minnesota Timberwolves',
    sport: SportType.nba,
    espnTeamId: '16',
  ),
  'nba_thunder': TeamColors(
    primary: Color(0xFF007AC1),
    secondary: Color(0xFFEF6100),
    teamName: 'Oklahoma City Thunder',
    sport: SportType.nba,
    espnTeamId: '25',
  ),
  'nba_trail_blazers': TeamColors(
    primary: Color(0xFFE03A3E),
    secondary: Color(0xFF000000),
    teamName: 'Portland Trail Blazers',
    sport: SportType.nba,
    espnTeamId: '22',
  ),
  'nba_jazz': TeamColors(
    primary: Color(0xFF002B5C),
    secondary: Color(0xFFF9A01B),
    teamName: 'Utah Jazz',
    sport: SportType.nba,
    espnTeamId: '26',
  ),

  // Pacific
  'nba_warriors': TeamColors(
    primary: Color(0xFF1D428A),
    secondary: Color(0xFFFFC72C),
    teamName: 'Golden State Warriors',
    sport: SportType.nba,
    espnTeamId: '9',
  ),
  'nba_clippers': TeamColors(
    primary: Color(0xFFC8102E),
    secondary: Color(0xFF1D428A),
    teamName: 'Los Angeles Clippers',
    sport: SportType.nba,
    espnTeamId: '12',
  ),
  'nba_lakers': TeamColors(
    primary: Color(0xFF552583),
    secondary: Color(0xFFFDB927),
    teamName: 'Los Angeles Lakers',
    sport: SportType.nba,
    espnTeamId: '13',
  ),
  'nba_suns': TeamColors(
    primary: Color(0xFF1D1160),
    secondary: Color(0xFFE56020),
    teamName: 'Phoenix Suns',
    sport: SportType.nba,
    espnTeamId: '21',
  ),
  'nba_kings': TeamColors(
    primary: Color(0xFF5A2D81),
    secondary: Color(0xFF63727A),
    teamName: 'Sacramento Kings',
    sport: SportType.nba,
    espnTeamId: '23',
  ),

  // Southwest
  'nba_mavericks': TeamColors(
    primary: Color(0xFF00538C),
    secondary: Color(0xFF002B5E),
    teamName: 'Dallas Mavericks',
    sport: SportType.nba,
    espnTeamId: '6',
  ),
  'nba_rockets': TeamColors(
    primary: Color(0xFFCE1141),
    secondary: Color(0xFF000000),
    teamName: 'Houston Rockets',
    sport: SportType.nba,
    espnTeamId: '10',
  ),
  'nba_grizzlies': TeamColors(
    primary: Color(0xFF5D76A9),
    secondary: Color(0xFF12173F),
    teamName: 'Memphis Grizzlies',
    sport: SportType.nba,
    espnTeamId: '29',
  ),
  'nba_pelicans': TeamColors(
    primary: Color(0xFF0C2340),
    secondary: Color(0xFFC8102E),
    teamName: 'New Orleans Pelicans',
    sport: SportType.nba,
    espnTeamId: '3',
  ),
  'nba_spurs': TeamColors(
    primary: Color(0xFFC4CED4),
    secondary: Color(0xFF000000),
    teamName: 'San Antonio Spurs',
    sport: SportType.nba,
    espnTeamId: '24',
  ),

  // =========================================================================
  //  MLB — 30 teams
  // =========================================================================

  // AL East
  'mlb_orioles': TeamColors(
    primary: Color(0xFFDF4601),
    secondary: Color(0xFF000000),
    teamName: 'Baltimore Orioles',
    sport: SportType.mlb,
    espnTeamId: '1',
  ),
  'mlb_red_sox': TeamColors(
    primary: Color(0xFFBD3039),
    secondary: Color(0xFF0C2340),
    teamName: 'Boston Red Sox',
    sport: SportType.mlb,
    espnTeamId: '2',
  ),
  'mlb_yankees': TeamColors(
    primary: Color(0xFF003087),
    secondary: Color(0xFFE4002C),
    teamName: 'New York Yankees',
    sport: SportType.mlb,
    espnTeamId: '10',
  ),
  'mlb_rays': TeamColors(
    primary: Color(0xFF092C5C),
    secondary: Color(0xFF8FBCE6),
    teamName: 'Tampa Bay Rays',
    sport: SportType.mlb,
    espnTeamId: '30',
  ),
  'mlb_blue_jays': TeamColors(
    primary: Color(0xFF134A8E),
    secondary: Color(0xFF1D2D5C),
    teamName: 'Toronto Blue Jays',
    sport: SportType.mlb,
    espnTeamId: '14',
  ),

  // AL Central
  'mlb_white_sox': TeamColors(
    primary: Color(0xFF27251F),
    secondary: Color(0xFFC4CED4),
    teamName: 'Chicago White Sox',
    sport: SportType.mlb,
    espnTeamId: '4',
  ),
  'mlb_guardians': TeamColors(
    primary: Color(0xFF00385D),
    secondary: Color(0xFFE50022),
    teamName: 'Cleveland Guardians',
    sport: SportType.mlb,
    espnTeamId: '5',
  ),
  'mlb_tigers': TeamColors(
    primary: Color(0xFF0C2340),
    secondary: Color(0xFFFA4616),
    teamName: 'Detroit Tigers',
    sport: SportType.mlb,
    espnTeamId: '6',
  ),
  'mlb_royals': TeamColors(
    primary: Color(0xFF004687),
    secondary: Color(0xFFC09A5B),
    teamName: 'Kansas City Royals',
    sport: SportType.mlb,
    espnTeamId: '7',
  ),
  'mlb_twins': TeamColors(
    primary: Color(0xFF002B5C),
    secondary: Color(0xFFD31145),
    teamName: 'Minnesota Twins',
    sport: SportType.mlb,
    espnTeamId: '9',
  ),

  // AL West
  'mlb_astros': TeamColors(
    primary: Color(0xFF002D62),
    secondary: Color(0xFFEB6E1F),
    teamName: 'Houston Astros',
    sport: SportType.mlb,
    espnTeamId: '18',
  ),
  'mlb_angels': TeamColors(
    primary: Color(0xFFBA0021),
    secondary: Color(0xFF003263),
    teamName: 'Los Angeles Angels',
    sport: SportType.mlb,
    espnTeamId: '3',
  ),
  'mlb_athletics': TeamColors(
    primary: Color(0xFF003831),
    secondary: Color(0xFFEFB21E),
    teamName: 'Oakland Athletics',
    sport: SportType.mlb,
    espnTeamId: '11',
  ),
  'mlb_mariners': TeamColors(
    primary: Color(0xFF0C2C56),
    secondary: Color(0xFF005C5C),
    teamName: 'Seattle Mariners',
    sport: SportType.mlb,
    espnTeamId: '12',
  ),
  'mlb_rangers': TeamColors(
    primary: Color(0xFF003278),
    secondary: Color(0xFFC0111F),
    teamName: 'Texas Rangers',
    sport: SportType.mlb,
    espnTeamId: '13',
  ),

  // NL East
  'mlb_braves': TeamColors(
    primary: Color(0xFFCE1141),
    secondary: Color(0xFF13274F),
    teamName: 'Atlanta Braves',
    sport: SportType.mlb,
    espnTeamId: '15',
  ),
  'mlb_marlins': TeamColors(
    primary: Color(0xFF00A3E0),
    secondary: Color(0xFFEF3340),
    teamName: 'Miami Marlins',
    sport: SportType.mlb,
    espnTeamId: '28',
  ),
  'mlb_mets': TeamColors(
    primary: Color(0xFF002D72),
    secondary: Color(0xFFFF5910),
    teamName: 'New York Mets',
    sport: SportType.mlb,
    espnTeamId: '21',
  ),
  'mlb_phillies': TeamColors(
    primary: Color(0xFFE81828),
    secondary: Color(0xFF002D72),
    teamName: 'Philadelphia Phillies',
    sport: SportType.mlb,
    espnTeamId: '22',
  ),
  'mlb_nationals': TeamColors(
    primary: Color(0xFFAB0003),
    secondary: Color(0xFF14225A),
    teamName: 'Washington Nationals',
    sport: SportType.mlb,
    espnTeamId: '24',
  ),

  // NL Central
  'mlb_cubs': TeamColors(
    primary: Color(0xFF0E3386),
    secondary: Color(0xFFCC3433),
    teamName: 'Chicago Cubs',
    sport: SportType.mlb,
    espnTeamId: '16',
  ),
  'mlb_reds': TeamColors(
    primary: Color(0xFFC6011F),
    secondary: Color(0xFF000000),
    teamName: 'Cincinnati Reds',
    sport: SportType.mlb,
    espnTeamId: '17',
  ),
  'mlb_brewers': TeamColors(
    primary: Color(0xFF12284B),
    secondary: Color(0xFFFFC52F),
    teamName: 'Milwaukee Brewers',
    sport: SportType.mlb,
    espnTeamId: '8',
  ),
  'mlb_pirates': TeamColors(
    primary: Color(0xFF27251F),
    secondary: Color(0xFFFDB827),
    teamName: 'Pittsburgh Pirates',
    sport: SportType.mlb,
    espnTeamId: '23',
  ),
  'mlb_cardinals': TeamColors(
    primary: Color(0xFFC41E3A),
    secondary: Color(0xFF0C2340),
    teamName: 'St. Louis Cardinals',
    sport: SportType.mlb,
    espnTeamId: '25',
  ),

  // NL West
  'mlb_diamondbacks': TeamColors(
    primary: Color(0xFFA71930),
    secondary: Color(0xFFE3D4AD),
    teamName: 'Arizona Diamondbacks',
    sport: SportType.mlb,
    espnTeamId: '29',
  ),
  'mlb_rockies': TeamColors(
    primary: Color(0xFF33006F),
    secondary: Color(0xFFC4CED4),
    teamName: 'Colorado Rockies',
    sport: SportType.mlb,
    espnTeamId: '27',
  ),
  'mlb_dodgers': TeamColors(
    primary: Color(0xFF005A9C),
    secondary: Color(0xFFEF3E42),
    teamName: 'Los Angeles Dodgers',
    sport: SportType.mlb,
    espnTeamId: '19',
  ),
  'mlb_padres': TeamColors(
    primary: Color(0xFF2F241D),
    secondary: Color(0xFFFFC425),
    teamName: 'San Diego Padres',
    sport: SportType.mlb,
    espnTeamId: '25',
  ),
  'mlb_giants': TeamColors(
    primary: Color(0xFFFD5A1E),
    secondary: Color(0xFF27251F),
    teamName: 'San Francisco Giants',
    sport: SportType.mlb,
    espnTeamId: '26',
  ),

  // =========================================================================
  //  NHL — 32 teams
  // =========================================================================

  // Atlantic
  'nhl_bruins': TeamColors(
    primary: Color(0xFFFFB81C),
    secondary: Color(0xFF000000),
    teamName: 'Boston Bruins',
    sport: SportType.nhl,
    espnTeamId: '1',
  ),
  'nhl_sabres': TeamColors(
    primary: Color(0xFF002654),
    secondary: Color(0xFFFCB514),
    teamName: 'Buffalo Sabres',
    sport: SportType.nhl,
    espnTeamId: '2',
  ),
  'nhl_red_wings': TeamColors(
    primary: Color(0xFFCE1126),
    secondary: Color(0xFFFFFFFF),
    teamName: 'Detroit Red Wings',
    sport: SportType.nhl,
    espnTeamId: '5',
  ),
  'nhl_panthers': TeamColors(
    primary: Color(0xFF041E42),
    secondary: Color(0xFFC8102E),
    teamName: 'Florida Panthers',
    sport: SportType.nhl,
    espnTeamId: '13',
  ),
  'nhl_canadiens': TeamColors(
    primary: Color(0xFFAF1E2D),
    secondary: Color(0xFF192168),
    teamName: 'Montreal Canadiens',
    sport: SportType.nhl,
    espnTeamId: '8',
  ),
  'nhl_senators': TeamColors(
    primary: Color(0xFFC52032),
    secondary: Color(0xFFC2912C),
    teamName: 'Ottawa Senators',
    sport: SportType.nhl,
    espnTeamId: '9',
  ),
  'nhl_lightning': TeamColors(
    primary: Color(0xFF002868),
    secondary: Color(0xFFFFFFFF),
    teamName: 'Tampa Bay Lightning',
    sport: SportType.nhl,
    espnTeamId: '14',
  ),
  'nhl_maple_leafs': TeamColors(
    primary: Color(0xFF00205B),
    secondary: Color(0xFFFFFFFF),
    teamName: 'Toronto Maple Leafs',
    sport: SportType.nhl,
    espnTeamId: '10',
  ),

  // Metropolitan
  'nhl_hurricanes': TeamColors(
    primary: Color(0xFFCC0000),
    secondary: Color(0xFF000000),
    teamName: 'Carolina Hurricanes',
    sport: SportType.nhl,
    espnTeamId: '7',
  ),
  'nhl_blue_jackets': TeamColors(
    primary: Color(0xFF002654),
    secondary: Color(0xFFCE1126),
    teamName: 'Columbus Blue Jackets',
    sport: SportType.nhl,
    espnTeamId: '29',
  ),
  'nhl_devils': TeamColors(
    primary: Color(0xFFCE1126),
    secondary: Color(0xFF000000),
    teamName: 'New Jersey Devils',
    sport: SportType.nhl,
    espnTeamId: '17',
  ),
  'nhl_islanders': TeamColors(
    primary: Color(0xFF00539B),
    secondary: Color(0xFFF47D30),
    teamName: 'New York Islanders',
    sport: SportType.nhl,
    espnTeamId: '18',
  ),
  'nhl_rangers': TeamColors(
    primary: Color(0xFF0038A8),
    secondary: Color(0xFFCE1126),
    teamName: 'New York Rangers',
    sport: SportType.nhl,
    espnTeamId: '19',
  ),
  'nhl_flyers': TeamColors(
    primary: Color(0xFFF74902),
    secondary: Color(0xFF000000),
    teamName: 'Philadelphia Flyers',
    sport: SportType.nhl,
    espnTeamId: '20',
  ),
  'nhl_penguins': TeamColors(
    primary: Color(0xFFFFB81C),
    secondary: Color(0xFF000000),
    teamName: 'Pittsburgh Penguins',
    sport: SportType.nhl,
    espnTeamId: '21',
  ),
  'nhl_capitals': TeamColors(
    primary: Color(0xFFC8102E),
    secondary: Color(0xFF041E42),
    teamName: 'Washington Capitals',
    sport: SportType.nhl,
    espnTeamId: '15',
  ),

  // Central
  'nhl_blackhawks': TeamColors(
    primary: Color(0xFFCF0A2C),
    secondary: Color(0xFF000000),
    teamName: 'Chicago Blackhawks',
    sport: SportType.nhl,
    espnTeamId: '4',
  ),
  'nhl_avalanche': TeamColors(
    primary: Color(0xFF6F263D),
    secondary: Color(0xFF236192),
    teamName: 'Colorado Avalanche',
    sport: SportType.nhl,
    espnTeamId: '28',
  ),
  'nhl_stars': TeamColors(
    primary: Color(0xFF006847),
    secondary: Color(0xFF8F8F8C),
    teamName: 'Dallas Stars',
    sport: SportType.nhl,
    espnTeamId: '25',
  ),
  'nhl_wild': TeamColors(
    primary: Color(0xFF154734),
    secondary: Color(0xFFA6192E),
    teamName: 'Minnesota Wild',
    sport: SportType.nhl,
    espnTeamId: '30',
  ),
  'nhl_predators': TeamColors(
    primary: Color(0xFFFFB81C),
    secondary: Color(0xFF041E42),
    teamName: 'Nashville Predators',
    sport: SportType.nhl,
    espnTeamId: '18',
  ),
  'nhl_blues': TeamColors(
    primary: Color(0xFF002F87),
    secondary: Color(0xFFFCB514),
    teamName: 'St. Louis Blues',
    sport: SportType.nhl,
    espnTeamId: '19',
  ),
  'nhl_jets': TeamColors(
    primary: Color(0xFF041E42),
    secondary: Color(0xFF004C97),
    teamName: 'Winnipeg Jets',
    sport: SportType.nhl,
    espnTeamId: '52',
  ),
  'nhl_utah': TeamColors(
    primary: Color(0xFF71AFE5),
    secondary: Color(0xFF000000),
    teamName: 'Utah Hockey Club',
    sport: SportType.nhl,
    espnTeamId: '53',
  ),

  // Pacific
  'nhl_ducks': TeamColors(
    primary: Color(0xFFF47A38),
    secondary: Color(0xFFB9975B),
    teamName: 'Anaheim Ducks',
    sport: SportType.nhl,
    espnTeamId: '24',
  ),
  'nhl_flames': TeamColors(
    primary: Color(0xFFC8102E),
    secondary: Color(0xFFF1BE48),
    teamName: 'Calgary Flames',
    sport: SportType.nhl,
    espnTeamId: '20',
  ),
  'nhl_oilers': TeamColors(
    primary: Color(0xFF041E42),
    secondary: Color(0xFFFF4C00),
    teamName: 'Edmonton Oilers',
    sport: SportType.nhl,
    espnTeamId: '22',
  ),
  'nhl_kings': TeamColors(
    primary: Color(0xFF111111),
    secondary: Color(0xFFA2AAAD),
    teamName: 'Los Angeles Kings',
    sport: SportType.nhl,
    espnTeamId: '26',
  ),
  'nhl_sharks': TeamColors(
    primary: Color(0xFF006D75),
    secondary: Color(0xFF000000),
    teamName: 'San Jose Sharks',
    sport: SportType.nhl,
    espnTeamId: '28',
  ),
  'nhl_kraken': TeamColors(
    primary: Color(0xFF001628),
    secondary: Color(0xFF99D9D9),
    teamName: 'Seattle Kraken',
    sport: SportType.nhl,
    espnTeamId: '55',
  ),
  'nhl_canucks': TeamColors(
    primary: Color(0xFF00205B),
    secondary: Color(0xFF00843D),
    teamName: 'Vancouver Canucks',
    sport: SportType.nhl,
    espnTeamId: '23',
  ),
  'nhl_golden_knights': TeamColors(
    primary: Color(0xFF333F42),
    secondary: Color(0xFFB4975A),
    teamName: 'Vegas Golden Knights',
    sport: SportType.nhl,
    espnTeamId: '54',
  ),

  // =========================================================================
  //  MLS — 29 active clubs (2025 season)
  // =========================================================================

  'mls_atlanta_united': TeamColors(
    primary: Color(0xFF80000A),
    secondary: Color(0xFFA29061),
    teamName: 'Atlanta United FC',
    sport: SportType.mls,
    espnTeamId: '18512',
  ),
  'mls_austin': TeamColors(
    primary: Color(0xFF00B140),
    secondary: Color(0xFF000000),
    teamName: 'Austin FC',
    sport: SportType.mls,
    espnTeamId: '20851',
  ),
  'mls_charlotte': TeamColors(
    primary: Color(0xFF1A85C8),
    secondary: Color(0xFF000000),
    teamName: 'Charlotte FC',
    sport: SportType.mls,
    espnTeamId: '21209',
  ),
  'mls_chicago_fire': TeamColors(
    primary: Color(0xFF141B4D),
    secondary: Color(0xFFFF0000),
    teamName: 'Chicago Fire FC',
    sport: SportType.mls,
    espnTeamId: '197',
  ),
  'mls_fc_cincinnati': TeamColors(
    primary: Color(0xFFF05323),
    secondary: Color(0xFF263B80),
    teamName: 'FC Cincinnati',
    sport: SportType.mls,
    espnTeamId: '18644',
  ),
  'mls_colorado_rapids': TeamColors(
    primary: Color(0xFF960A2C),
    secondary: Color(0xFF9CC2EA),
    teamName: 'Colorado Rapids',
    sport: SportType.mls,
    espnTeamId: '198',
  ),
  'mls_columbus_crew': TeamColors(
    primary: Color(0xFF000000),
    secondary: Color(0xFFFEDB00),
    teamName: 'Columbus Crew',
    sport: SportType.mls,
    espnTeamId: '199',
  ),
  'mls_fc_dallas': TeamColors(
    primary: Color(0xFFE81F3E),
    secondary: Color(0xFF2A4076),
    teamName: 'FC Dallas',
    sport: SportType.mls,
    espnTeamId: '201',
  ),
  'mls_dc_united': TeamColors(
    primary: Color(0xFF000000),
    secondary: Color(0xFFEF3E42),
    teamName: 'D.C. United',
    sport: SportType.mls,
    espnTeamId: '193',
  ),
  'mls_dynamo': TeamColors(
    primary: Color(0xFFF68712),
    secondary: Color(0xFF2D2926),
    teamName: 'Houston Dynamo FC',
    sport: SportType.mls,
    espnTeamId: '6977',
  ),
  'mls_inter_miami': TeamColors(
    primary: Color(0xFFF7B5CD),
    secondary: Color(0xFF231F20),
    teamName: 'Inter Miami CF',
    sport: SportType.mls,
    espnTeamId: '20852',
  ),
  'mls_sporting_kc': TeamColors(
    primary: Color(0xFF002F65),
    secondary: Color(0xFFA7C1E2),
    teamName: 'Sporting Kansas City',
    sport: SportType.mls,
    espnTeamId: '200',
  ),
  'mls_la_galaxy': TeamColors(
    primary: Color(0xFF00245D),
    secondary: Color(0xFFFFD200),
    teamName: 'LA Galaxy',
    sport: SportType.mls,
    espnTeamId: '194',
  ),
  'mls_lafc': TeamColors(
    primary: Color(0xFF000000),
    secondary: Color(0xFFC39E6D),
    teamName: 'Los Angeles FC',
    sport: SportType.mls,
    espnTeamId: '18543',
  ),
  'mls_minnesota_united': TeamColors(
    primary: Color(0xFF231F20),
    secondary: Color(0xFF9BCBEB),
    teamName: 'Minnesota United FC',
    sport: SportType.mls,
    espnTeamId: '18278',
  ),
  'mls_cf_montreal': TeamColors(
    primary: Color(0xFF000000),
    secondary: Color(0xFF0033A1),
    teamName: 'CF Montréal',
    sport: SportType.mls,
    espnTeamId: '6510',
  ),
  'mls_nashville': TeamColors(
    primary: Color(0xFFECE83A),
    secondary: Color(0xFF1F1646),
    teamName: 'Nashville SC',
    sport: SportType.mls,
    espnTeamId: '20853',
  ),
  'mls_revolution': TeamColors(
    primary: Color(0xFF0A2240),
    secondary: Color(0xFFCE0037),
    teamName: 'New England Revolution',
    sport: SportType.mls,
    espnTeamId: '196',
  ),
  'mls_nycfc': TeamColors(
    primary: Color(0xFF6CACE4),
    secondary: Color(0xFF041E42),
    teamName: 'New York City FC',
    sport: SportType.mls,
    espnTeamId: '17362',
  ),
  'mls_red_bulls': TeamColors(
    primary: Color(0xFFED1E36),
    secondary: Color(0xFF23326A),
    teamName: 'New York Red Bulls',
    sport: SportType.mls,
    espnTeamId: '11091',
  ),
  'mls_orlando_city': TeamColors(
    primary: Color(0xFF633492),
    secondary: Color(0xFFFFFFFF),
    teamName: 'Orlando City SC',
    sport: SportType.mls,
    espnTeamId: '17013',
  ),
  'mls_union': TeamColors(
    primary: Color(0xFF002B5C),
    secondary: Color(0xFFB48B40),
    teamName: 'Philadelphia Union',
    sport: SportType.mls,
    espnTeamId: '7933',
  ),
  'mls_timbers': TeamColors(
    primary: Color(0xFF004812),
    secondary: Color(0xFFD6A62C),
    teamName: 'Portland Timbers',
    sport: SportType.mls,
    espnTeamId: '7911',
  ),
  'mls_real_salt_lake': TeamColors(
    primary: Color(0xFFC10230),
    secondary: Color(0xFF013A81),
    teamName: 'Real Salt Lake',
    sport: SportType.mls,
    espnTeamId: '5513',
  ),
  'mls_san_jose': TeamColors(
    primary: Color(0xFF0067B1),
    secondary: Color(0xFF000000),
    teamName: 'San Jose Earthquakes',
    sport: SportType.mls,
    espnTeamId: '195',
  ),
  'mls_sounders': TeamColors(
    primary: Color(0xFF236192),
    secondary: Color(0xFF658D1B),
    teamName: 'Seattle Sounders FC',
    sport: SportType.mls,
    espnTeamId: '9726',
  ),
  'mls_st_louis': TeamColors(
    primary: Color(0xFF1D1B4D),
    secondary: Color(0xFFEE3B3B),
    teamName: 'St. Louis City SC',
    sport: SportType.mls,
    espnTeamId: '21210',
  ),
  'mls_toronto': TeamColors(
    primary: Color(0xFFE31937),
    secondary: Color(0xFF455560),
    teamName: 'Toronto FC',
    sport: SportType.mls,
    espnTeamId: '7695',
  ),
  'mls_whitecaps': TeamColors(
    primary: Color(0xFF00245E),
    secondary: Color(0xFF9DC3E6),
    teamName: 'Vancouver Whitecaps FC',
    sport: SportType.mls,
    espnTeamId: '9727',
  ),

  // San Diego FC (expansion 2025)
  'mls_san_diego': TeamColors(
    primary: Color(0xFF201547),
    secondary: Color(0xFFE6007E),
    teamName: 'San Diego FC',
    sport: SportType.mls,
    espnTeamId: '24816',
  ),
};
