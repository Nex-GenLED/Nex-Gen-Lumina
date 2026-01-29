import 'package:flutter/material.dart';

/// Represents a sports team with its name and official colors.
class SportsTeam {
  final String name;
  final String league;
  final String city;
  final List<Color> colors;
  final String? nickname; // e.g., "KC" for Kansas City

  const SportsTeam({
    required this.name,
    required this.league,
    required this.city,
    required this.colors,
    this.nickname,
  });

  /// Display name including city
  String get displayName => '$city $name';

  /// Search-friendly string
  String get searchKey => '$city $name ${nickname ?? ''} $league'.toLowerCase();
}

/// Database of popular sports teams with their official colors.
/// Organized by league for easy browsing.
class SportsTeamsDatabase {
  static const List<SportsTeam> allTeams = [
    // NFL Teams
    SportsTeam(name: 'Chiefs', league: 'NFL', city: 'Kansas City', colors: [Color(0xFFE31837), Color(0xFFFFB81C)], nickname: 'KC'),
    SportsTeam(name: '49ers', league: 'NFL', city: 'San Francisco', colors: [Color(0xFFAA0000), Color(0xFFB3995D)], nickname: 'SF'),
    SportsTeam(name: 'Cowboys', league: 'NFL', city: 'Dallas', colors: [Color(0xFF003594), Color(0xFF869397)]),
    SportsTeam(name: 'Eagles', league: 'NFL', city: 'Philadelphia', colors: [Color(0xFF004C54), Color(0xFFA5ACAF)]),
    SportsTeam(name: 'Bills', league: 'NFL', city: 'Buffalo', colors: [Color(0xFF00338D), Color(0xFFC60C30)]),
    SportsTeam(name: 'Dolphins', league: 'NFL', city: 'Miami', colors: [Color(0xFF008E97), Color(0xFFF58220)]),
    SportsTeam(name: 'Patriots', league: 'NFL', city: 'New England', colors: [Color(0xFF002244), Color(0xFFC60C30)]),
    SportsTeam(name: 'Jets', league: 'NFL', city: 'New York', colors: [Color(0xFF125740), Color(0xFFFFFFFF)], nickname: 'NY'),
    SportsTeam(name: 'Ravens', league: 'NFL', city: 'Baltimore', colors: [Color(0xFF241773), Color(0xFF9E7C0C)]),
    SportsTeam(name: 'Steelers', league: 'NFL', city: 'Pittsburgh', colors: [Color(0xFFFFB612), Color(0xFF101820)]),
    SportsTeam(name: 'Bengals', league: 'NFL', city: 'Cincinnati', colors: [Color(0xFFFB4F14), Color(0xFF000000)]),
    SportsTeam(name: 'Browns', league: 'NFL', city: 'Cleveland', colors: [Color(0xFF311D00), Color(0xFFFF3C00)]),
    SportsTeam(name: 'Texans', league: 'NFL', city: 'Houston', colors: [Color(0xFF03202F), Color(0xFFA71930)]),
    SportsTeam(name: 'Colts', league: 'NFL', city: 'Indianapolis', colors: [Color(0xFF002C5F), Color(0xFFFFFFFF)]),
    SportsTeam(name: 'Jaguars', league: 'NFL', city: 'Jacksonville', colors: [Color(0xFF101820), Color(0xFFD7A22A)]),
    SportsTeam(name: 'Titans', league: 'NFL', city: 'Tennessee', colors: [Color(0xFF0C2340), Color(0xFF4B92DB)]),
    SportsTeam(name: 'Broncos', league: 'NFL', city: 'Denver', colors: [Color(0xFFFB4F14), Color(0xFF002244)]),
    SportsTeam(name: 'Chargers', league: 'NFL', city: 'Los Angeles', colors: [Color(0xFF0080C6), Color(0xFFFFC20E)], nickname: 'LA'),
    SportsTeam(name: 'Raiders', league: 'NFL', city: 'Las Vegas', colors: [Color(0xFF000000), Color(0xFFA5ACAF)]),
    SportsTeam(name: 'Bears', league: 'NFL', city: 'Chicago', colors: [Color(0xFF0B162A), Color(0xFFC83803)]),
    SportsTeam(name: 'Lions', league: 'NFL', city: 'Detroit', colors: [Color(0xFF0076B6), Color(0xFFB0B7BC)]),
    SportsTeam(name: 'Packers', league: 'NFL', city: 'Green Bay', colors: [Color(0xFF203731), Color(0xFFFFB612)]),
    SportsTeam(name: 'Vikings', league: 'NFL', city: 'Minnesota', colors: [Color(0xFF4F2683), Color(0xFFFFC62F)]),
    SportsTeam(name: 'Falcons', league: 'NFL', city: 'Atlanta', colors: [Color(0xFFA71930), Color(0xFF000000)]),
    SportsTeam(name: 'Panthers', league: 'NFL', city: 'Carolina', colors: [Color(0xFF0085CA), Color(0xFF101820)]),
    SportsTeam(name: 'Saints', league: 'NFL', city: 'New Orleans', colors: [Color(0xFFD3BC8D), Color(0xFF101820)]),
    SportsTeam(name: 'Buccaneers', league: 'NFL', city: 'Tampa Bay', colors: [Color(0xFFD50A0A), Color(0xFF34302B)]),
    SportsTeam(name: 'Cardinals', league: 'NFL', city: 'Arizona', colors: [Color(0xFF97233F), Color(0xFFFFB612)]),
    SportsTeam(name: 'Rams', league: 'NFL', city: 'Los Angeles', colors: [Color(0xFF003594), Color(0xFFFFA300)]),
    SportsTeam(name: 'Seahawks', league: 'NFL', city: 'Seattle', colors: [Color(0xFF002244), Color(0xFF69BE28)]),
    SportsTeam(name: 'Commanders', league: 'NFL', city: 'Washington', colors: [Color(0xFF5A1414), Color(0xFFFFB612)]),
    SportsTeam(name: 'Giants', league: 'NFL', city: 'New York', colors: [Color(0xFF0B2265), Color(0xFFA71930)]),

    // NBA Teams
    SportsTeam(name: 'Lakers', league: 'NBA', city: 'Los Angeles', colors: [Color(0xFF552583), Color(0xFFFDB927)], nickname: 'LA'),
    SportsTeam(name: 'Celtics', league: 'NBA', city: 'Boston', colors: [Color(0xFF007A33), Color(0xFFBA9653)]),
    SportsTeam(name: 'Warriors', league: 'NBA', city: 'Golden State', colors: [Color(0xFF1D428A), Color(0xFFFFC72C)]),
    SportsTeam(name: 'Bulls', league: 'NBA', city: 'Chicago', colors: [Color(0xFFCE1141), Color(0xFF000000)]),
    SportsTeam(name: 'Heat', league: 'NBA', city: 'Miami', colors: [Color(0xFF98002E), Color(0xFFF9A01B)]),
    SportsTeam(name: 'Knicks', league: 'NBA', city: 'New York', colors: [Color(0xFF006BB6), Color(0xFFF58426)]),
    SportsTeam(name: 'Nets', league: 'NBA', city: 'Brooklyn', colors: [Color(0xFF000000), Color(0xFFFFFFFF)]),
    SportsTeam(name: 'Mavericks', league: 'NBA', city: 'Dallas', colors: [Color(0xFF00538C), Color(0xFF002B5E)]),
    SportsTeam(name: 'Spurs', league: 'NBA', city: 'San Antonio', colors: [Color(0xFFC4CED4), Color(0xFF000000)]),
    SportsTeam(name: 'Rockets', league: 'NBA', city: 'Houston', colors: [Color(0xFFCE1141), Color(0xFF000000)]),
    SportsTeam(name: 'Nuggets', league: 'NBA', city: 'Denver', colors: [Color(0xFF0E2240), Color(0xFFFEC524)]),
    SportsTeam(name: 'Suns', league: 'NBA', city: 'Phoenix', colors: [Color(0xFF1D1160), Color(0xFFE56020)]),
    SportsTeam(name: 'Bucks', league: 'NBA', city: 'Milwaukee', colors: [Color(0xFF00471B), Color(0xFFEEE1C6)]),
    SportsTeam(name: 'Sixers', league: 'NBA', city: 'Philadelphia', colors: [Color(0xFF006BB6), Color(0xFFED174C)]),
    SportsTeam(name: 'Raptors', league: 'NBA', city: 'Toronto', colors: [Color(0xFFCE1141), Color(0xFF000000)]),
    SportsTeam(name: 'Clippers', league: 'NBA', city: 'Los Angeles', colors: [Color(0xFFC8102E), Color(0xFF1D428A)]),
    SportsTeam(name: 'Thunder', league: 'NBA', city: 'Oklahoma City', colors: [Color(0xFF007AC1), Color(0xFFEF3B24)], nickname: 'OKC'),
    SportsTeam(name: 'Grizzlies', league: 'NBA', city: 'Memphis', colors: [Color(0xFF5D76A9), Color(0xFF12173F)]),
    SportsTeam(name: 'Pelicans', league: 'NBA', city: 'New Orleans', colors: [Color(0xFF0C2340), Color(0xFFC8102E)]),
    SportsTeam(name: 'Timberwolves', league: 'NBA', city: 'Minnesota', colors: [Color(0xFF0C2340), Color(0xFF236192)]),
    SportsTeam(name: 'Trail Blazers', league: 'NBA', city: 'Portland', colors: [Color(0xFFE03A3E), Color(0xFF000000)]),
    SportsTeam(name: 'Jazz', league: 'NBA', city: 'Utah', colors: [Color(0xFF002B5C), Color(0xFFF9A01B)]),
    SportsTeam(name: 'Kings', league: 'NBA', city: 'Sacramento', colors: [Color(0xFF5A2D81), Color(0xFF63727A)]),
    SportsTeam(name: 'Cavaliers', league: 'NBA', city: 'Cleveland', colors: [Color(0xFF860038), Color(0xFF041E42)]),
    SportsTeam(name: 'Pistons', league: 'NBA', city: 'Detroit', colors: [Color(0xFFC8102E), Color(0xFF1D42BA)]),
    SportsTeam(name: 'Pacers', league: 'NBA', city: 'Indiana', colors: [Color(0xFF002D62), Color(0xFFFDBC44)]),
    SportsTeam(name: 'Hawks', league: 'NBA', city: 'Atlanta', colors: [Color(0xFFE03A3E), Color(0xFFC1D32F)]),
    SportsTeam(name: 'Hornets', league: 'NBA', city: 'Charlotte', colors: [Color(0xFF1D1160), Color(0xFF00788C)]),
    SportsTeam(name: 'Magic', league: 'NBA', city: 'Orlando', colors: [Color(0xFF0077C0), Color(0xFF000000)]),
    SportsTeam(name: 'Wizards', league: 'NBA', city: 'Washington', colors: [Color(0xFF002B5C), Color(0xFFE31837)]),

    // WNBA Teams
    SportsTeam(name: 'Aces', league: 'WNBA', city: 'Las Vegas', colors: [Color(0xFFA7A8AA), Color(0xFF000000), Color(0xFFC8102E)]),
    SportsTeam(name: 'Dream', league: 'WNBA', city: 'Atlanta', colors: [Color(0xFFE31837), Color(0xFF418FDE), Color(0xFFC6D600)]),
    SportsTeam(name: 'Sky', league: 'WNBA', city: 'Chicago', colors: [Color(0xFF5091CD), Color(0xFFFFD520)]),
    SportsTeam(name: 'Sun', league: 'WNBA', city: 'Connecticut', colors: [Color(0xFFF05023), Color(0xFF0A2240)]),
    SportsTeam(name: 'Wings', league: 'WNBA', city: 'Dallas', colors: [Color(0xFF002B5C), Color(0xFFC4D600)]),
    SportsTeam(name: 'Fever', league: 'WNBA', city: 'Indiana', colors: [Color(0xFF002D62), Color(0xFFE03A3E), Color(0xFFFFC633)]),
    SportsTeam(name: 'Sparks', league: 'WNBA', city: 'Los Angeles', colors: [Color(0xFF552583), Color(0xFFFDB927)], nickname: 'LA'),
    SportsTeam(name: 'Lynx', league: 'WNBA', city: 'Minnesota', colors: [Color(0xFF0C2340), Color(0xFF236192), Color(0xFF78BE20)]),
    SportsTeam(name: 'Liberty', league: 'WNBA', city: 'New York', colors: [Color(0xFF6ECEB2), Color(0xFF000000), Color(0xFFFF6B00)], nickname: 'NY'),
    SportsTeam(name: 'Mercury', league: 'WNBA', city: 'Phoenix', colors: [Color(0xFF201747), Color(0xFFE56020), Color(0xFF1D1160)]),
    SportsTeam(name: 'Storm', league: 'WNBA', city: 'Seattle', colors: [Color(0xFF2C5234), Color(0xFFFFC222)]),
    SportsTeam(name: 'Mystics', league: 'WNBA', city: 'Washington', colors: [Color(0xFF002B5C), Color(0xFFE31837)]),
    SportsTeam(name: 'Valkyries', league: 'WNBA', city: 'Golden State', colors: [Color(0xFF552583), Color(0xFFFDB927), Color(0xFF1D428A)]),

    // MLB Teams
    SportsTeam(name: 'Royals', league: 'MLB', city: 'Kansas City', colors: [Color(0xFF004687), Color(0xFFC09A5B)], nickname: 'KC'),
    SportsTeam(name: 'Yankees', league: 'MLB', city: 'New York', colors: [Color(0xFF003087), Color(0xFFFFFFFF)], nickname: 'NY'),
    SportsTeam(name: 'Red Sox', league: 'MLB', city: 'Boston', colors: [Color(0xFFBD3039), Color(0xFF0C2340)]),
    SportsTeam(name: 'Dodgers', league: 'MLB', city: 'Los Angeles', colors: [Color(0xFF005A9C), Color(0xFFFFFFFF)], nickname: 'LA'),
    SportsTeam(name: 'Cubs', league: 'MLB', city: 'Chicago', colors: [Color(0xFF0E3386), Color(0xFFCC3433)]),
    SportsTeam(name: 'Cardinals', league: 'MLB', city: 'St. Louis', colors: [Color(0xFFC41E3A), Color(0xFF0C2340)]),
    SportsTeam(name: 'Giants', league: 'MLB', city: 'San Francisco', colors: [Color(0xFFFD5A1E), Color(0xFF27251F)], nickname: 'SF'),
    SportsTeam(name: 'Braves', league: 'MLB', city: 'Atlanta', colors: [Color(0xFFCE1141), Color(0xFF13274F)]),
    SportsTeam(name: 'Astros', league: 'MLB', city: 'Houston', colors: [Color(0xFF002D62), Color(0xFFEB6E1F)]),
    SportsTeam(name: 'Phillies', league: 'MLB', city: 'Philadelphia', colors: [Color(0xFFE81828), Color(0xFF002D72)]),
    SportsTeam(name: 'Mets', league: 'MLB', city: 'New York', colors: [Color(0xFF002D72), Color(0xFFFF5910)]),
    SportsTeam(name: 'Rangers', league: 'MLB', city: 'Texas', colors: [Color(0xFF003278), Color(0xFFC0111F)]),
    SportsTeam(name: 'Padres', league: 'MLB', city: 'San Diego', colors: [Color(0xFF2F241D), Color(0xFFFFC425)]),
    SportsTeam(name: 'Mariners', league: 'MLB', city: 'Seattle', colors: [Color(0xFF0C2C56), Color(0xFF005C5C)]),
    SportsTeam(name: 'White Sox', league: 'MLB', city: 'Chicago', colors: [Color(0xFF27251F), Color(0xFFC4CED4)]),
    SportsTeam(name: 'Tigers', league: 'MLB', city: 'Detroit', colors: [Color(0xFF0C2340), Color(0xFFFA4616)]),
    SportsTeam(name: 'Twins', league: 'MLB', city: 'Minnesota', colors: [Color(0xFF002B5C), Color(0xFFD31145)]),
    SportsTeam(name: 'Guardians', league: 'MLB', city: 'Cleveland', colors: [Color(0xFF00385D), Color(0xFFE50022)]),
    SportsTeam(name: 'Orioles', league: 'MLB', city: 'Baltimore', colors: [Color(0xFFDF4601), Color(0xFF000000)]),
    SportsTeam(name: 'Blue Jays', league: 'MLB', city: 'Toronto', colors: [Color(0xFF134A8E), Color(0xFF1D2D5C)]),
    SportsTeam(name: 'Rays', league: 'MLB', city: 'Tampa Bay', colors: [Color(0xFF092C5C), Color(0xFF8FBCE6)]),
    SportsTeam(name: 'Athletics', league: 'MLB', city: 'Oakland', colors: [Color(0xFF003831), Color(0xFFEFB21E)]),
    SportsTeam(name: 'Angels', league: 'MLB', city: 'Los Angeles', colors: [Color(0xFFBA0021), Color(0xFF003263)]),
    SportsTeam(name: 'Reds', league: 'MLB', city: 'Cincinnati', colors: [Color(0xFFC6011F), Color(0xFF000000)]),
    SportsTeam(name: 'Brewers', league: 'MLB', city: 'Milwaukee', colors: [Color(0xFF12284B), Color(0xFFB6922E)]),
    SportsTeam(name: 'Pirates', league: 'MLB', city: 'Pittsburgh', colors: [Color(0xFF27251F), Color(0xFFFDB827)]),
    SportsTeam(name: 'Rockies', league: 'MLB', city: 'Colorado', colors: [Color(0xFF33006F), Color(0xFFC4CED4)]),
    SportsTeam(name: 'Diamondbacks', league: 'MLB', city: 'Arizona', colors: [Color(0xFFA71930), Color(0xFFE3D4AD)]),
    SportsTeam(name: 'Marlins', league: 'MLB', city: 'Miami', colors: [Color(0xFF00A3E0), Color(0xFFEF3340)]),
    SportsTeam(name: 'Nationals', league: 'MLB', city: 'Washington', colors: [Color(0xFFAB0003), Color(0xFF14225A)]),

    // NHL Teams
    SportsTeam(name: 'Blackhawks', league: 'NHL', city: 'Chicago', colors: [Color(0xFFCF0A2C), Color(0xFF000000)]),
    SportsTeam(name: 'Bruins', league: 'NHL', city: 'Boston', colors: [Color(0xFFFFB81C), Color(0xFF000000)]),
    SportsTeam(name: 'Rangers', league: 'NHL', city: 'New York', colors: [Color(0xFF0038A8), Color(0xFFCE1126)]),
    SportsTeam(name: 'Maple Leafs', league: 'NHL', city: 'Toronto', colors: [Color(0xFF00205B), Color(0xFFFFFFFF)]),
    SportsTeam(name: 'Canadiens', league: 'NHL', city: 'Montreal', colors: [Color(0xFFAF1E2D), Color(0xFF192168)]),
    SportsTeam(name: 'Red Wings', league: 'NHL', city: 'Detroit', colors: [Color(0xFFCE1126), Color(0xFFFFFFFF)]),
    SportsTeam(name: 'Penguins', league: 'NHL', city: 'Pittsburgh', colors: [Color(0xFFFFB81C), Color(0xFF000000)]),
    SportsTeam(name: 'Flyers', league: 'NHL', city: 'Philadelphia', colors: [Color(0xFFF74902), Color(0xFF000000)]),
    SportsTeam(name: 'Avalanche', league: 'NHL', city: 'Colorado', colors: [Color(0xFF6F263D), Color(0xFF236192)]),
    SportsTeam(name: 'Lightning', league: 'NHL', city: 'Tampa Bay', colors: [Color(0xFF002868), Color(0xFFFFFFFF)]),
    SportsTeam(name: 'Golden Knights', league: 'NHL', city: 'Vegas', colors: [Color(0xFFB4975A), Color(0xFF333F42)]),
    SportsTeam(name: 'Capitals', league: 'NHL', city: 'Washington', colors: [Color(0xFFC8102E), Color(0xFF041E42)]),
    SportsTeam(name: 'Oilers', league: 'NHL', city: 'Edmonton', colors: [Color(0xFF041E42), Color(0xFFFF4C00)]),
    SportsTeam(name: 'Flames', league: 'NHL', city: 'Calgary', colors: [Color(0xFFD2001C), Color(0xFFFAA819)]),
    SportsTeam(name: 'Blues', league: 'NHL', city: 'St. Louis', colors: [Color(0xFF002F87), Color(0xFFFCB514)]),
    SportsTeam(name: 'Stars', league: 'NHL', city: 'Dallas', colors: [Color(0xFF006847), Color(0xFF8F8F8C)]),
    SportsTeam(name: 'Kings', league: 'NHL', city: 'Los Angeles', colors: [Color(0xFF111111), Color(0xFFA2AAAD)]),
    SportsTeam(name: 'Sharks', league: 'NHL', city: 'San Jose', colors: [Color(0xFF006D75), Color(0xFFEA7200)]),
    SportsTeam(name: 'Ducks', league: 'NHL', city: 'Anaheim', colors: [Color(0xFFF47A38), Color(0xFF000000)]),
    SportsTeam(name: 'Kraken', league: 'NHL', city: 'Seattle', colors: [Color(0xFF001628), Color(0xFF99D9D9)]),
    SportsTeam(name: 'Wild', league: 'NHL', city: 'Minnesota', colors: [Color(0xFF154734), Color(0xFFA6192E)]),
    SportsTeam(name: 'Predators', league: 'NHL', city: 'Nashville', colors: [Color(0xFFFFB81C), Color(0xFF041E42)]),
    SportsTeam(name: 'Panthers', league: 'NHL', city: 'Florida', colors: [Color(0xFF041E42), Color(0xFFC8102E)]),
    SportsTeam(name: 'Hurricanes', league: 'NHL', city: 'Carolina', colors: [Color(0xFFCC0000), Color(0xFF000000)]),
    SportsTeam(name: 'Blue Jackets', league: 'NHL', city: 'Columbus', colors: [Color(0xFF002654), Color(0xFFCE1126)]),
    SportsTeam(name: 'Devils', league: 'NHL', city: 'New Jersey', colors: [Color(0xFFCE1126), Color(0xFF000000)]),
    SportsTeam(name: 'Islanders', league: 'NHL', city: 'New York', colors: [Color(0xFF00539B), Color(0xFFF47D30)]),
    SportsTeam(name: 'Sabres', league: 'NHL', city: 'Buffalo', colors: [Color(0xFF002654), Color(0xFFFCB514)]),
    SportsTeam(name: 'Senators', league: 'NHL', city: 'Ottawa', colors: [Color(0xFFC52032), Color(0xFFC2912C)]),
    SportsTeam(name: 'Jets', league: 'NHL', city: 'Winnipeg', colors: [Color(0xFF041E42), Color(0xFF004C97)]),
    SportsTeam(name: 'Canucks', league: 'NHL', city: 'Vancouver', colors: [Color(0xFF00205B), Color(0xFF00843D)]),
    SportsTeam(name: 'Coyotes', league: 'NHL', city: 'Utah', colors: [Color(0xFF8C2633), Color(0xFFE2D6B5)]),

    // MLS Teams
    SportsTeam(name: 'Sporting KC', league: 'MLS', city: 'Kansas City', colors: [Color(0xFF0067B1), Color(0xFFA1A1A4)]),
    SportsTeam(name: 'Galaxy', league: 'MLS', city: 'Los Angeles', colors: [Color(0xFF00245D), Color(0xFFFFD200)]),
    SportsTeam(name: 'LAFC', league: 'MLS', city: 'Los Angeles', colors: [Color(0xFF000000), Color(0xFFC39E6D)]),
    SportsTeam(name: 'Sounders', league: 'MLS', city: 'Seattle', colors: [Color(0xFF5D9741), Color(0xFF005695)]),
    SportsTeam(name: 'Atlanta United', league: 'MLS', city: 'Atlanta', colors: [Color(0xFF80000A), Color(0xFFA19060)]),
    SportsTeam(name: 'Inter Miami', league: 'MLS', city: 'Miami', colors: [Color(0xFFF7B5CD), Color(0xFF231F20)]),
    SportsTeam(name: 'NYCFC', league: 'MLS', city: 'New York', colors: [Color(0xFF6CACE4), Color(0xFF041E42)]),
    SportsTeam(name: 'Red Bulls', league: 'MLS', city: 'New York', colors: [Color(0xFFED1E36), Color(0xFF1E255D)]),
    SportsTeam(name: 'FC Cincinnati', league: 'MLS', city: 'Cincinnati', colors: [Color(0xFFFC4C02), Color(0xFF263B80)]),
    SportsTeam(name: 'Austin FC', league: 'MLS', city: 'Austin', colors: [Color(0xFF00B140), Color(0xFF000000)]),

    // NWSL Teams
    SportsTeam(name: 'Angel City', league: 'NWSL', city: 'Los Angeles', colors: [Color(0xFF000000), Color(0xFFFFFFFF), Color(0xFFE65100)]),
    SportsTeam(name: 'Bay FC', league: 'NWSL', city: 'San Francisco', colors: [Color(0xFF00A6A6), Color(0xFF1E1E1E)]),
    SportsTeam(name: 'Red Stars', league: 'NWSL', city: 'Chicago', colors: [Color(0xFFDA291C), Color(0xFF0C2340)]),
    SportsTeam(name: 'Dash', league: 'NWSL', city: 'Houston', colors: [Color(0xFFFF6B00), Color(0xFF00B5E2)]),
    SportsTeam(name: 'Current', league: 'NWSL', city: 'Kansas City', colors: [Color(0xFFCF3339), Color(0xFF102A47)]),
    SportsTeam(name: 'Gotham FC', league: 'NWSL', city: 'New York/New Jersey', colors: [Color(0xFF000000), Color(0xFF00FF7F)]),
    SportsTeam(name: 'Courage', league: 'NWSL', city: 'North Carolina', colors: [Color(0xFF003153), Color(0xFF85C1E9)]),
    SportsTeam(name: 'Pride', league: 'NWSL', city: 'Orlando', colors: [Color(0xFF5E2B7E), Color(0xFFFFFFFF)]),
    SportsTeam(name: 'Thorns', league: 'NWSL', city: 'Portland', colors: [Color(0xFF004B28), Color(0xFFC5B783)]),
    SportsTeam(name: 'Racing Louisville', league: 'NWSL', city: 'Louisville', colors: [Color(0xFF6C2E8D), Color(0xFFFFD100)]),
    SportsTeam(name: 'Wave', league: 'NWSL', city: 'San Diego', colors: [Color(0xFF003DA5), Color(0xFFFF5733)]),
    SportsTeam(name: 'Reign', league: 'NWSL', city: 'Seattle', colors: [Color(0xFF0B3D91), Color(0xFFFFD700)]),
    SportsTeam(name: 'Royals', league: 'NWSL', city: 'Utah', colors: [Color(0xFFFFD700), Color(0xFF0B3D91)]),
    SportsTeam(name: 'Spirit', league: 'NWSL', city: 'Washington', colors: [Color(0xFF0A0A0A), Color(0xFFAD1831)]),

    // College Teams (Popular)
    SportsTeam(name: 'Jayhawks', league: 'NCAA', city: 'Kansas', colors: [Color(0xFF0051BA), Color(0xFFE8000D)], nickname: 'KU'),
    SportsTeam(name: 'Wildcats', league: 'NCAA', city: 'Kansas State', colors: [Color(0xFF512888), Color(0xFFFFFFFF)], nickname: 'K-State'),
    SportsTeam(name: 'Tigers', league: 'NCAA', city: 'Missouri', colors: [Color(0xFFF1B82D), Color(0xFF000000)], nickname: 'Mizzou'),
    SportsTeam(name: 'Crimson Tide', league: 'NCAA', city: 'Alabama', colors: [Color(0xFF9E1B32), Color(0xFFFFFFFF)]),
    SportsTeam(name: 'Buckeyes', league: 'NCAA', city: 'Ohio State', colors: [Color(0xFFBB0000), Color(0xFF666666)]),
    SportsTeam(name: 'Wolverines', league: 'NCAA', city: 'Michigan', colors: [Color(0xFF00274C), Color(0xFFFFCB05)]),
    SportsTeam(name: 'Fighting Irish', league: 'NCAA', city: 'Notre Dame', colors: [Color(0xFF0C2340), Color(0xFFC99700)]),
    SportsTeam(name: 'Longhorns', league: 'NCAA', city: 'Texas', colors: [Color(0xFFBF5700), Color(0xFFFFFFFF)]),
    SportsTeam(name: 'Bulldogs', league: 'NCAA', city: 'Georgia', colors: [Color(0xFFBA0C2F), Color(0xFF000000)]),
    SportsTeam(name: 'Tigers', league: 'NCAA', city: 'Clemson', colors: [Color(0xFFF56600), Color(0xFF522D80)]),
    SportsTeam(name: 'Sooners', league: 'NCAA', city: 'Oklahoma', colors: [Color(0xFF841617), Color(0xFFFDF9D8)]),
    SportsTeam(name: 'Nittany Lions', league: 'NCAA', city: 'Penn State', colors: [Color(0xFF041E42), Color(0xFFFFFFFF)]),
    SportsTeam(name: 'Seminoles', league: 'NCAA', city: 'Florida State', colors: [Color(0xFF782F40), Color(0xFFCEB888)]),
    SportsTeam(name: 'Gators', league: 'NCAA', city: 'Florida', colors: [Color(0xFF0021A5), Color(0xFFFA4616)]),
    SportsTeam(name: 'Cornhuskers', league: 'NCAA', city: 'Nebraska', colors: [Color(0xFFE41C38), Color(0xFFFFFFFF)]),
    SportsTeam(name: 'Hawkeyes', league: 'NCAA', city: 'Iowa', colors: [Color(0xFFFFCD00), Color(0xFF000000)]),
    SportsTeam(name: 'Trojans', league: 'NCAA', city: 'USC', colors: [Color(0xFF990000), Color(0xFFFFC72C)]),
    SportsTeam(name: 'Bruins', league: 'NCAA', city: 'UCLA', colors: [Color(0xFF2D68C4), Color(0xFFF2A900)]),
    SportsTeam(name: 'Ducks', league: 'NCAA', city: 'Oregon', colors: [Color(0xFF154733), Color(0xFFFEE11A)]),
    SportsTeam(name: 'Huskies', league: 'NCAA', city: 'Washington', colors: [Color(0xFF4B2E83), Color(0xFFB7A57A)]),
  ];

  /// Search teams by query string
  static List<SportsTeam> search(String query) {
    if (query.isEmpty) return [];
    final lower = query.toLowerCase();
    return allTeams.where((t) => t.searchKey.contains(lower)).toList();
  }

  /// Get team by display name (exact match)
  static SportsTeam? getByName(String displayName) {
    try {
      return allTeams.firstWhere((t) => t.displayName == displayName);
    } catch (_) {
      return null;
    }
  }

  /// Get teams by league
  static List<SportsTeam> getByLeague(String league) {
    return allTeams.where((t) => t.league == league).toList();
  }

  /// Get all unique leagues
  static List<String> get leagues {
    return allTeams.map((t) => t.league).toSet().toList()..sort();
  }

  /// Searches for a sports team in a query string.
  /// Returns the first matching team or null.
  ///
  /// This method is more sophisticated than simple search() as it:
  /// - Handles multi-word team names ("Kansas City Royals", "Red Sox")
  /// - Handles city + team combinations
  /// - Handles nicknames ("KC Royals", "NY Yankees")
  /// - Prioritizes longer/more specific matches
  static SportsTeam? findTeamInQuery(String query) {
    if (query.isEmpty) return null;
    final lower = query.toLowerCase();

    // Build a list of potential matches with their specificity score
    final matches = <_TeamMatch>[];

    for (final team in allTeams) {
      int score = 0;

      // Check for full display name (e.g., "Kansas City Royals")
      final displayLower = team.displayName.toLowerCase();
      if (lower.contains(displayLower)) {
        score = 100 + displayLower.length; // Highest priority for full name
      }
      // Check for city + team name (e.g., "kansas city" + "royals")
      else if (lower.contains(team.city.toLowerCase()) &&
               lower.contains(team.name.toLowerCase())) {
        score = 80 + team.city.length + team.name.length;
      }
      // Check for nickname + team name (e.g., "kc royals")
      else if (team.nickname != null &&
               lower.contains(team.nickname!.toLowerCase()) &&
               lower.contains(team.name.toLowerCase())) {
        score = 70 + team.name.length;
      }
      // Check for just team name (e.g., "royals", "chiefs")
      // Use word boundaries to avoid partial matches
      else {
        final teamNameLower = team.name.toLowerCase();
        final pattern = RegExp('\\b${RegExp.escape(teamNameLower)}\\b');
        if (pattern.hasMatch(lower)) {
          score = 50 + teamNameLower.length;
        }
      }

      if (score > 0) {
        matches.add(_TeamMatch(team: team, score: score));
      }
    }

    if (matches.isEmpty) return null;

    // Sort by score (highest first) and return the best match
    matches.sort((a, b) => b.score.compareTo(a.score));
    return matches.first.team;
  }
}

/// Helper class for team matching with scoring
class _TeamMatch {
  final SportsTeam team;
  final int score;
  const _TeamMatch({required this.team, required this.score});
}
