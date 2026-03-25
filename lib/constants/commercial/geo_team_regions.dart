import 'package:nexgen_command/models/commercial/commercial_team_profile.dart';

/// A geographic market region mapped to its local professional sports teams.
class GeoRegion {
  final String name;
  final double lat;
  final double lng;
  final double radiusKm;
  final List<CommercialTeamProfile> teams;

  const GeoRegion({
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusKm,
    required this.teams,
  });
}

/// Major US metro regions with their local professional teams.
///
/// Each region is centred on the metro area with a radius large enough to
/// cover the surrounding suburbs. The list covers 30+ markets across
/// NFL, NBA, MLB, NHL, and MLS.
const List<GeoRegion> kGeoTeamRegions = [
  // ── Northeast ──────────────────────────────────────────────────────────
  GeoRegion(name: 'New York', lat: 40.7128, lng: -74.0060, radiusKm: 60, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '24', teamName: 'New York Giants', sport: 'nfl', primaryColor: '0B2265', secondaryColor: 'A71930'),
    CommercialTeamProfile(priorityRank: 0, teamId: '20', teamName: 'New York Jets', sport: 'nfl', primaryColor: '125740', secondaryColor: 'FFFFFF'),
    CommercialTeamProfile(priorityRank: 0, teamId: '18', teamName: 'New York Knicks', sport: 'nba', primaryColor: '006BB6', secondaryColor: 'F58426'),
    CommercialTeamProfile(priorityRank: 0, teamId: '17', teamName: 'Brooklyn Nets', sport: 'nba', primaryColor: '000000', secondaryColor: 'FFFFFF'),
    CommercialTeamProfile(priorityRank: 0, teamId: '10', teamName: 'New York Yankees', sport: 'mlb', primaryColor: '003087', secondaryColor: 'E4002B'),
    CommercialTeamProfile(priorityRank: 0, teamId: '21', teamName: 'New York Mets', sport: 'mlb', primaryColor: '002D72', secondaryColor: 'FF5910'),
    CommercialTeamProfile(priorityRank: 0, teamId: '3', teamName: 'New York Rangers', sport: 'nhl', primaryColor: '0038A8', secondaryColor: 'CE1126'),
    CommercialTeamProfile(priorityRank: 0, teamId: '2', teamName: 'New York Islanders', sport: 'nhl', primaryColor: '00539B', secondaryColor: 'F47D30'),
    CommercialTeamProfile(priorityRank: 0, teamId: '9668', teamName: 'New York City FC', sport: 'mls', primaryColor: '6CACE4', secondaryColor: 'F15524'),
    CommercialTeamProfile(priorityRank: 0, teamId: '399', teamName: 'New York Red Bulls', sport: 'mls', primaryColor: 'ED1E36', secondaryColor: '23326A'),
  ]),

  GeoRegion(name: 'Boston', lat: 42.3601, lng: -71.0589, radiusKm: 50, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '17', teamName: 'New England Patriots', sport: 'nfl', primaryColor: '002244', secondaryColor: 'C60C30'),
    CommercialTeamProfile(priorityRank: 0, teamId: '2', teamName: 'Boston Celtics', sport: 'nba', primaryColor: '007A33', secondaryColor: 'BA9653'),
    CommercialTeamProfile(priorityRank: 0, teamId: '2', teamName: 'Boston Red Sox', sport: 'mlb', primaryColor: 'BD3039', secondaryColor: '0C2340'),
    CommercialTeamProfile(priorityRank: 0, teamId: '6', teamName: 'Boston Bruins', sport: 'nhl', primaryColor: 'FFB81C', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '928', teamName: 'New England Revolution', sport: 'mls', primaryColor: '0A2240', secondaryColor: 'CE0E2D'),
  ]),

  GeoRegion(name: 'Philadelphia', lat: 39.9526, lng: -75.1652, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '21', teamName: 'Philadelphia Eagles', sport: 'nfl', primaryColor: '004C54', secondaryColor: 'A5ACAF'),
    CommercialTeamProfile(priorityRank: 0, teamId: '20', teamName: 'Philadelphia 76ers', sport: 'nba', primaryColor: '006BB6', secondaryColor: 'ED174C'),
    CommercialTeamProfile(priorityRank: 0, teamId: '22', teamName: 'Philadelphia Phillies', sport: 'mlb', primaryColor: 'E81828', secondaryColor: '002D72'),
    CommercialTeamProfile(priorityRank: 0, teamId: '4', teamName: 'Philadelphia Flyers', sport: 'nhl', primaryColor: 'F74902', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '926', teamName: 'Philadelphia Union', sport: 'mls', primaryColor: '071B2C', secondaryColor: 'B19B69'),
  ]),

  GeoRegion(name: 'Pittsburgh', lat: 40.4406, lng: -79.9959, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '23', teamName: 'Pittsburgh Steelers', sport: 'nfl', primaryColor: 'FFB612', secondaryColor: '101820'),
    CommercialTeamProfile(priorityRank: 0, teamId: '23', teamName: 'Pittsburgh Pirates', sport: 'mlb', primaryColor: 'FDB827', secondaryColor: '27251F'),
    CommercialTeamProfile(priorityRank: 0, teamId: '5', teamName: 'Pittsburgh Penguins', sport: 'nhl', primaryColor: 'FCB514', secondaryColor: '000000'),
  ]),

  GeoRegion(name: 'Washington DC', lat: 38.9072, lng: -77.0369, radiusKm: 50, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '28', teamName: 'Washington Commanders', sport: 'nfl', primaryColor: '5A1414', secondaryColor: 'FFB612'),
    CommercialTeamProfile(priorityRank: 0, teamId: '27', teamName: 'Washington Wizards', sport: 'nba', primaryColor: '002B5C', secondaryColor: 'E31837'),
    CommercialTeamProfile(priorityRank: 0, teamId: '20', teamName: 'Washington Nationals', sport: 'mlb', primaryColor: 'AB0003', secondaryColor: '14225A'),
    CommercialTeamProfile(priorityRank: 0, teamId: '15', teamName: 'Washington Capitals', sport: 'nhl', primaryColor: 'C8102E', secondaryColor: '041E42'),
    CommercialTeamProfile(priorityRank: 0, teamId: '7918', teamName: 'D.C. United', sport: 'mls', primaryColor: '000000', secondaryColor: 'EF3E42'),
  ]),

  // ── Southeast ──────────────────────────────────────────────────────────
  GeoRegion(name: 'Miami', lat: 25.7617, lng: -80.1918, radiusKm: 50, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '15', teamName: 'Miami Dolphins', sport: 'nfl', primaryColor: '008E97', secondaryColor: 'FC4C02'),
    CommercialTeamProfile(priorityRank: 0, teamId: '14', teamName: 'Miami Heat', sport: 'nba', primaryColor: '98002E', secondaryColor: 'F9A01B'),
    CommercialTeamProfile(priorityRank: 0, teamId: '28', teamName: 'Miami Marlins', sport: 'mlb', primaryColor: '00A3E0', secondaryColor: 'EF3340'),
    CommercialTeamProfile(priorityRank: 0, teamId: '13', teamName: 'Florida Panthers', sport: 'nhl', primaryColor: 'C8102E', secondaryColor: '041E42'),
    CommercialTeamProfile(priorityRank: 0, teamId: '18261', teamName: 'Inter Miami CF', sport: 'mls', primaryColor: 'F7B5CD', secondaryColor: '231F20'),
  ]),

  GeoRegion(name: 'Atlanta', lat: 33.7490, lng: -84.3880, radiusKm: 50, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '1', teamName: 'Atlanta Falcons', sport: 'nfl', primaryColor: 'A71930', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '1', teamName: 'Atlanta Hawks', sport: 'nba', primaryColor: 'E03A3E', secondaryColor: 'C1D32F'),
    CommercialTeamProfile(priorityRank: 0, teamId: '15', teamName: 'Atlanta Braves', sport: 'mlb', primaryColor: 'CE1141', secondaryColor: '13274F'),
    CommercialTeamProfile(priorityRank: 0, teamId: '9674', teamName: 'Atlanta United FC', sport: 'mls', primaryColor: 'A29061', secondaryColor: '80000B'),
  ]),

  GeoRegion(name: 'Tampa Bay', lat: 27.9506, lng: -82.4572, radiusKm: 50, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '27', teamName: 'Tampa Bay Buccaneers', sport: 'nfl', primaryColor: 'D50A0A', secondaryColor: '34302B'),
    CommercialTeamProfile(priorityRank: 0, teamId: '30', teamName: 'Tampa Bay Rays', sport: 'mlb', primaryColor: '092C5C', secondaryColor: '8FBCE6'),
    CommercialTeamProfile(priorityRank: 0, teamId: '14', teamName: 'Tampa Bay Lightning', sport: 'nhl', primaryColor: '002868', secondaryColor: 'FFFFFF'),
  ]),

  GeoRegion(name: 'Charlotte', lat: 35.2271, lng: -80.8431, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '29', teamName: 'Carolina Panthers', sport: 'nfl', primaryColor: '0085CA', secondaryColor: '101820'),
    CommercialTeamProfile(priorityRank: 0, teamId: '30', teamName: 'Charlotte Hornets', sport: 'nba', primaryColor: '1D1160', secondaryColor: '00788C'),
    CommercialTeamProfile(priorityRank: 0, teamId: '26', teamName: 'Carolina Hurricanes', sport: 'nhl', primaryColor: 'CC0000', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '17372', teamName: 'Charlotte FC', sport: 'mls', primaryColor: '1A85C8', secondaryColor: '000000'),
  ]),

  // ── Midwest ────────────────────────────────────────────────────────────
  GeoRegion(name: 'Chicago', lat: 41.8781, lng: -87.6298, radiusKm: 50, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '3', teamName: 'Chicago Bears', sport: 'nfl', primaryColor: '0B162A', secondaryColor: 'C83803'),
    CommercialTeamProfile(priorityRank: 0, teamId: '4', teamName: 'Chicago Bulls', sport: 'nba', primaryColor: 'CE1141', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '16', teamName: 'Chicago Cubs', sport: 'mlb', primaryColor: '0E3386', secondaryColor: 'CC3433'),
    CommercialTeamProfile(priorityRank: 0, teamId: '4', teamName: 'Chicago White Sox', sport: 'mlb', primaryColor: '27251F', secondaryColor: 'C4CED4'),
    CommercialTeamProfile(priorityRank: 0, teamId: '16', teamName: 'Chicago Blackhawks', sport: 'nhl', primaryColor: 'CF0A2C', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '8', teamName: 'Chicago Fire FC', sport: 'mls', primaryColor: 'FF0000', secondaryColor: '0A174A'),
  ]),

  GeoRegion(name: 'Detroit', lat: 42.3314, lng: -83.0458, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '8', teamName: 'Detroit Lions', sport: 'nfl', primaryColor: '0076B6', secondaryColor: 'B0B7BC'),
    CommercialTeamProfile(priorityRank: 0, teamId: '8', teamName: 'Detroit Pistons', sport: 'nba', primaryColor: 'C8102E', secondaryColor: '1D42BA'),
    CommercialTeamProfile(priorityRank: 0, teamId: '6', teamName: 'Detroit Tigers', sport: 'mlb', primaryColor: '0C2340', secondaryColor: 'FA4616'),
    CommercialTeamProfile(priorityRank: 0, teamId: '17', teamName: 'Detroit Red Wings', sport: 'nhl', primaryColor: 'CE1126', secondaryColor: 'FFFFFF'),
  ]),

  GeoRegion(name: 'Cleveland', lat: 41.4993, lng: -81.6944, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '5', teamName: 'Cleveland Browns', sport: 'nfl', primaryColor: '311D00', secondaryColor: 'FF3C00'),
    CommercialTeamProfile(priorityRank: 0, teamId: '5', teamName: 'Cleveland Cavaliers', sport: 'nba', primaryColor: '860038', secondaryColor: '041E42'),
    CommercialTeamProfile(priorityRank: 0, teamId: '5', teamName: 'Cleveland Guardians', sport: 'mlb', primaryColor: '00385D', secondaryColor: 'E50022'),
  ]),

  GeoRegion(name: 'Minneapolis', lat: 44.9778, lng: -93.2650, radiusKm: 50, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '16', teamName: 'Minnesota Vikings', sport: 'nfl', primaryColor: '4F2683', secondaryColor: 'FFC62F'),
    CommercialTeamProfile(priorityRank: 0, teamId: '16', teamName: 'Minnesota Timberwolves', sport: 'nba', primaryColor: '0C2340', secondaryColor: '236192'),
    CommercialTeamProfile(priorityRank: 0, teamId: '9', teamName: 'Minnesota Twins', sport: 'mlb', primaryColor: '002B5C', secondaryColor: 'D31145'),
    CommercialTeamProfile(priorityRank: 0, teamId: '30', teamName: 'Minnesota Wild', sport: 'nhl', primaryColor: '154734', secondaryColor: 'A6192E'),
    CommercialTeamProfile(priorityRank: 0, teamId: '69', teamName: 'Minnesota United FC', sport: 'mls', primaryColor: '231F20', secondaryColor: '9BCBEB'),
  ]),

  GeoRegion(name: 'Milwaukee', lat: 43.0389, lng: -87.9065, radiusKm: 40, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '9', teamName: 'Green Bay Packers', sport: 'nfl', primaryColor: '203731', secondaryColor: 'FFB612'),
    CommercialTeamProfile(priorityRank: 0, teamId: '15', teamName: 'Milwaukee Bucks', sport: 'nba', primaryColor: '00471B', secondaryColor: 'EEE1C6'),
    CommercialTeamProfile(priorityRank: 0, teamId: '8', teamName: 'Milwaukee Brewers', sport: 'mlb', primaryColor: '12284B', secondaryColor: 'FFC52F'),
  ]),

  GeoRegion(name: 'Indianapolis', lat: 39.7684, lng: -86.1581, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '11', teamName: 'Indianapolis Colts', sport: 'nfl', primaryColor: '002C5F', secondaryColor: 'A2AAAD'),
    CommercialTeamProfile(priorityRank: 0, teamId: '11', teamName: 'Indiana Pacers', sport: 'nba', primaryColor: '002D62', secondaryColor: 'FDBB30'),
  ]),

  GeoRegion(name: 'Cincinnati', lat: 39.1031, lng: -84.5120, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '4', teamName: 'Cincinnati Bengals', sport: 'nfl', primaryColor: 'FB4F14', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '17', teamName: 'Cincinnati Reds', sport: 'mlb', primaryColor: 'C6011F', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '9726', teamName: 'FC Cincinnati', sport: 'mls', primaryColor: 'F05323', secondaryColor: '263B80'),
  ]),

  GeoRegion(name: 'Kansas City', lat: 39.0997, lng: -94.5786, radiusKm: 50, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '12', teamName: 'Kansas City Chiefs', sport: 'nfl', primaryColor: 'E31837', secondaryColor: 'FFB81C'),
    CommercialTeamProfile(priorityRank: 0, teamId: '7', teamName: 'Kansas City Royals', sport: 'mlb', primaryColor: '004687', secondaryColor: 'BD9B60'),
    CommercialTeamProfile(priorityRank: 0, teamId: '15154', teamName: 'Sporting Kansas City', sport: 'mls', primaryColor: '002F65', secondaryColor: 'A4AEB5'),
  ]),

  // ── South / Southwest ──────────────────────────────────────────────────
  GeoRegion(name: 'Dallas', lat: 32.7767, lng: -96.7970, radiusKm: 60, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '6', teamName: 'Dallas Cowboys', sport: 'nfl', primaryColor: '003594', secondaryColor: '869397'),
    CommercialTeamProfile(priorityRank: 0, teamId: '6', teamName: 'Dallas Mavericks', sport: 'nba', primaryColor: '00538C', secondaryColor: 'B8C4CA'),
    CommercialTeamProfile(priorityRank: 0, teamId: '13', teamName: 'Texas Rangers', sport: 'mlb', primaryColor: '003278', secondaryColor: 'C0111F'),
    CommercialTeamProfile(priorityRank: 0, teamId: '25', teamName: 'Dallas Stars', sport: 'nhl', primaryColor: '006847', secondaryColor: '8F8F8C'),
    CommercialTeamProfile(priorityRank: 0, teamId: '9726', teamName: 'FC Dallas', sport: 'mls', primaryColor: 'BF0D3E', secondaryColor: '002D72'),
  ]),

  GeoRegion(name: 'Houston', lat: 29.7604, lng: -95.3698, radiusKm: 55, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '34', teamName: 'Houston Texans', sport: 'nfl', primaryColor: '03202F', secondaryColor: 'A71930'),
    CommercialTeamProfile(priorityRank: 0, teamId: '10', teamName: 'Houston Rockets', sport: 'nba', primaryColor: 'CE1141', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '18', teamName: 'Houston Astros', sport: 'mlb', primaryColor: '002D62', secondaryColor: 'EB6E1F'),
    CommercialTeamProfile(priorityRank: 0, teamId: '9252', teamName: 'Houston Dynamo FC', sport: 'mls', primaryColor: 'F68712', secondaryColor: '101820'),
  ]),

  GeoRegion(name: 'Nashville', lat: 36.1627, lng: -86.7816, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '10', teamName: 'Tennessee Titans', sport: 'nfl', primaryColor: '0C2340', secondaryColor: '4B92DB'),
    CommercialTeamProfile(priorityRank: 0, teamId: '18', teamName: 'Nashville Predators', sport: 'nhl', primaryColor: 'FFB81C', secondaryColor: '041E42'),
    CommercialTeamProfile(priorityRank: 0, teamId: '7292', teamName: 'Nashville SC', sport: 'mls', primaryColor: 'ECE83A', secondaryColor: '1F1646'),
  ]),

  GeoRegion(name: 'San Antonio', lat: 29.4241, lng: -98.4936, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '24', teamName: 'San Antonio Spurs', sport: 'nba', primaryColor: 'C4CED4', secondaryColor: '000000'),
  ]),

  GeoRegion(name: 'New Orleans', lat: 29.9511, lng: -90.0715, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '18', teamName: 'New Orleans Saints', sport: 'nfl', primaryColor: 'D3BC8D', secondaryColor: '101820'),
    CommercialTeamProfile(priorityRank: 0, teamId: '3', teamName: 'New Orleans Pelicans', sport: 'nba', primaryColor: '0C2340', secondaryColor: 'C8102E'),
  ]),

  // ── West ───────────────────────────────────────────────────────────────
  GeoRegion(name: 'Los Angeles', lat: 34.0522, lng: -118.2437, radiusKm: 60, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '14', teamName: 'Los Angeles Rams', sport: 'nfl', primaryColor: '003594', secondaryColor: 'FFA300'),
    CommercialTeamProfile(priorityRank: 0, teamId: '24', teamName: 'Los Angeles Chargers', sport: 'nfl', primaryColor: '0080C6', secondaryColor: 'FFC20E'),
    CommercialTeamProfile(priorityRank: 0, teamId: '13', teamName: 'Los Angeles Lakers', sport: 'nba', primaryColor: '552583', secondaryColor: 'FDB927'),
    CommercialTeamProfile(priorityRank: 0, teamId: '12', teamName: 'LA Clippers', sport: 'nba', primaryColor: 'C8102E', secondaryColor: '1D428A'),
    CommercialTeamProfile(priorityRank: 0, teamId: '19', teamName: 'Los Angeles Dodgers', sport: 'mlb', primaryColor: '005A9C', secondaryColor: 'EF3E42'),
    CommercialTeamProfile(priorityRank: 0, teamId: '3', teamName: 'Los Angeles Angels', sport: 'mlb', primaryColor: 'BA0021', secondaryColor: '003263'),
    CommercialTeamProfile(priorityRank: 0, teamId: '26', teamName: 'Los Angeles Kings', sport: 'nhl', primaryColor: 'A2AAAD', secondaryColor: '111111'),
    CommercialTeamProfile(priorityRank: 0, teamId: '24', teamName: 'Anaheim Ducks', sport: 'nhl', primaryColor: 'F47A38', secondaryColor: 'B9975B'),
    CommercialTeamProfile(priorityRank: 0, teamId: '401', teamName: 'LA Galaxy', sport: 'mls', primaryColor: '00245D', secondaryColor: 'FFD200'),
    CommercialTeamProfile(priorityRank: 0, teamId: '5765', teamName: 'LAFC', sport: 'mls', primaryColor: '000000', secondaryColor: 'C39E6D'),
  ]),

  GeoRegion(name: 'San Francisco', lat: 37.7749, lng: -122.4194, radiusKm: 50, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '25', teamName: 'San Francisco 49ers', sport: 'nfl', primaryColor: 'AA0000', secondaryColor: 'B3995D'),
    CommercialTeamProfile(priorityRank: 0, teamId: '9', teamName: 'Golden State Warriors', sport: 'nba', primaryColor: '1D428A', secondaryColor: 'FFC72C'),
    CommercialTeamProfile(priorityRank: 0, teamId: '26', teamName: 'San Francisco Giants', sport: 'mlb', primaryColor: 'FD5A1E', secondaryColor: '27251F'),
    CommercialTeamProfile(priorityRank: 0, teamId: '28', teamName: 'Oakland Athletics', sport: 'mlb', primaryColor: '003831', secondaryColor: 'EFB21E'),
    CommercialTeamProfile(priorityRank: 0, teamId: '28', teamName: 'San Jose Sharks', sport: 'nhl', primaryColor: '006D75', secondaryColor: 'EA7200'),
    CommercialTeamProfile(priorityRank: 0, teamId: '12321', teamName: 'San Jose Earthquakes', sport: 'mls', primaryColor: '0067B1', secondaryColor: '000000'),
  ]),

  GeoRegion(name: 'Seattle', lat: 47.6062, lng: -122.3321, radiusKm: 50, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '26', teamName: 'Seattle Seahawks', sport: 'nfl', primaryColor: '002244', secondaryColor: '69BE28'),
    CommercialTeamProfile(priorityRank: 0, teamId: '11', teamName: 'Seattle Mariners', sport: 'mlb', primaryColor: '0C2C56', secondaryColor: '005C5C'),
    CommercialTeamProfile(priorityRank: 0, teamId: '31', teamName: 'Seattle Kraken', sport: 'nhl', primaryColor: '001628', secondaryColor: '99D9D9'),
    CommercialTeamProfile(priorityRank: 0, teamId: '9726', teamName: 'Seattle Sounders FC', sport: 'mls', primaryColor: '5D9741', secondaryColor: '005595'),
  ]),

  GeoRegion(name: 'Denver', lat: 39.7392, lng: -104.9903, radiusKm: 50, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '7', teamName: 'Denver Broncos', sport: 'nfl', primaryColor: 'FB4F14', secondaryColor: '002244'),
    CommercialTeamProfile(priorityRank: 0, teamId: '7', teamName: 'Denver Nuggets', sport: 'nba', primaryColor: '0E2240', secondaryColor: 'FEC524'),
    CommercialTeamProfile(priorityRank: 0, teamId: '27', teamName: 'Colorado Rockies', sport: 'mlb', primaryColor: '333366', secondaryColor: 'C4CED4'),
    CommercialTeamProfile(priorityRank: 0, teamId: '21', teamName: 'Colorado Avalanche', sport: 'nhl', primaryColor: '6F263D', secondaryColor: '236192'),
    CommercialTeamProfile(priorityRank: 0, teamId: '9242', teamName: 'Colorado Rapids', sport: 'mls', primaryColor: '862633', secondaryColor: '8BB8E8'),
  ]),

  GeoRegion(name: 'Phoenix', lat: 33.4484, lng: -111.9490, radiusKm: 55, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '22', teamName: 'Arizona Cardinals', sport: 'nfl', primaryColor: '97233F', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '21', teamName: 'Phoenix Suns', sport: 'nba', primaryColor: '1D1160', secondaryColor: 'E56020'),
    CommercialTeamProfile(priorityRank: 0, teamId: '29', teamName: 'Arizona Diamondbacks', sport: 'mlb', primaryColor: 'A71930', secondaryColor: 'E3D4AD'),
    CommercialTeamProfile(priorityRank: 0, teamId: '24', teamName: 'Arizona Coyotes', sport: 'nhl', primaryColor: '8C2633', secondaryColor: 'E2D6B5'),
  ]),

  GeoRegion(name: 'Portland', lat: 45.5051, lng: -122.6750, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '22', teamName: 'Portland Trail Blazers', sport: 'nba', primaryColor: 'E03A3E', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '20', teamName: 'Portland Timbers', sport: 'mls', primaryColor: '004812', secondaryColor: 'D69A00'),
  ]),

  GeoRegion(name: 'Salt Lake City', lat: 40.7608, lng: -111.8910, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '26', teamName: 'Utah Jazz', sport: 'nba', primaryColor: '002B5C', secondaryColor: 'F9A01B'),
    CommercialTeamProfile(priorityRank: 0, teamId: '32', teamName: 'Utah Hockey Club', sport: 'nhl', primaryColor: '71AFE5', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '9267', teamName: 'Real Salt Lake', sport: 'mls', primaryColor: '013A81', secondaryColor: 'B30838'),
  ]),

  GeoRegion(name: 'Las Vegas', lat: 36.1699, lng: -115.1398, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '13', teamName: 'Las Vegas Raiders', sport: 'nfl', primaryColor: '000000', secondaryColor: 'A5ACAF'),
    CommercialTeamProfile(priorityRank: 0, teamId: '33', teamName: 'Las Vegas Aces', sport: 'nba', primaryColor: 'A7A8AA', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '29', teamName: 'Vegas Golden Knights', sport: 'nhl', primaryColor: 'B4975A', secondaryColor: '333F42'),
  ]),

  // ── Additional markets ─────────────────────────────────────────────────
  GeoRegion(name: 'Baltimore', lat: 39.2904, lng: -76.6122, radiusKm: 40, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '33', teamName: 'Baltimore Ravens', sport: 'nfl', primaryColor: '241773', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '1', teamName: 'Baltimore Orioles', sport: 'mlb', primaryColor: 'DF4601', secondaryColor: '27251F'),
  ]),

  GeoRegion(name: 'St. Louis', lat: 38.6270, lng: -90.1994, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '24', teamName: 'St. Louis Cardinals', sport: 'mlb', primaryColor: 'C41E3A', secondaryColor: '0C2340'),
    CommercialTeamProfile(priorityRank: 0, teamId: '19', teamName: 'St. Louis Blues', sport: 'nhl', primaryColor: '002F87', secondaryColor: 'FCB514'),
    CommercialTeamProfile(priorityRank: 0, teamId: '17362', teamName: 'St. Louis CITY SC', sport: 'mls', primaryColor: 'D22630', secondaryColor: '0A2240'),
  ]),

  GeoRegion(name: 'Columbus', lat: 39.9612, lng: -82.9988, radiusKm: 40, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '9', teamName: 'Columbus Blue Jackets', sport: 'nhl', primaryColor: '002654', secondaryColor: 'CE1126'),
    CommercialTeamProfile(priorityRank: 0, teamId: '300', teamName: 'Columbus Crew', sport: 'mls', primaryColor: 'FEDD00', secondaryColor: '000000'),
  ]),

  GeoRegion(name: 'Sacramento', lat: 38.5816, lng: -121.4944, radiusKm: 40, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '23', teamName: 'Sacramento Kings', sport: 'nba', primaryColor: '5A2D81', secondaryColor: '63727A'),
  ]),

  GeoRegion(name: 'Memphis', lat: 35.1495, lng: -90.0490, radiusKm: 40, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '29', teamName: 'Memphis Grizzlies', sport: 'nba', primaryColor: '5D76A9', secondaryColor: '12173F'),
  ]),

  GeoRegion(name: 'Oklahoma City', lat: 35.4676, lng: -97.5164, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '25', teamName: 'Oklahoma City Thunder', sport: 'nba', primaryColor: '007AC1', secondaryColor: 'EF6020'),
  ]),

  GeoRegion(name: 'Orlando', lat: 28.5383, lng: -81.3792, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '19', teamName: 'Orlando Magic', sport: 'nba', primaryColor: '0077C0', secondaryColor: '000000'),
    CommercialTeamProfile(priorityRank: 0, teamId: '6901', teamName: 'Orlando City SC', sport: 'mls', primaryColor: '633492', secondaryColor: '000000'),
  ]),

  GeoRegion(name: 'Raleigh', lat: 35.7796, lng: -78.6382, radiusKm: 40, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '26', teamName: 'Carolina Hurricanes', sport: 'nhl', primaryColor: 'CC0000', secondaryColor: '000000'),
  ]),

  GeoRegion(name: 'Buffalo', lat: 42.8864, lng: -78.8784, radiusKm: 40, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '2', teamName: 'Buffalo Bills', sport: 'nfl', primaryColor: '00338D', secondaryColor: 'C60C30'),
    CommercialTeamProfile(priorityRank: 0, teamId: '7', teamName: 'Buffalo Sabres', sport: 'nhl', primaryColor: '002654', secondaryColor: 'FCB514'),
  ]),

  GeoRegion(name: 'Austin', lat: 30.2672, lng: -97.7431, radiusKm: 45, teams: [
    CommercialTeamProfile(priorityRank: 0, teamId: '17012', teamName: 'Austin FC', sport: 'mls', primaryColor: '00B140', secondaryColor: '000000'),
  ]),
];
