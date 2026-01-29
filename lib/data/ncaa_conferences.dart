import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';

/// NCAA D1 Football and Basketball conferences with all member schools.
/// Each school has official primary and secondary colors.
class NcaaConferences {
  // ==================== NCAA FOOTBALL CONFERENCES ====================

  /// SEC Football Conference
  static const List<_SchoolData> secFootball = [
    _SchoolData('Alabama', 'Crimson Tide', Color(0xFF9E1B32), Color(0xFFFFFFFF)),
    _SchoolData('Arkansas', 'Razorbacks', Color(0xFF9D2235), Color(0xFFFFFFFF)),
    _SchoolData('Auburn', 'Tigers', Color(0xFF0C2340), Color(0xFFFF6600)),
    _SchoolData('Florida', 'Gators', Color(0xFF0021A5), Color(0xFFFA4616)),
    _SchoolData('Georgia', 'Bulldogs', Color(0xFFBA0C2F), Color(0xFF000000)),
    _SchoolData('Kentucky', 'Wildcats', Color(0xFF0033A0), Color(0xFFFFFFFF)),
    _SchoolData('LSU', 'Tigers', Color(0xFF461D7C), Color(0xFFFDD023)),
    _SchoolData('Mississippi State', 'Bulldogs', Color(0xFF660000), Color(0xFFFFFFFF)),
    _SchoolData('Missouri', 'Tigers', Color(0xFFF1B82D), Color(0xFF000000)),
    _SchoolData('Oklahoma', 'Sooners', Color(0xFF841617), Color(0xFFFFFFFF)),
    _SchoolData('Ole Miss', 'Rebels', Color(0xFF14213D), Color(0xFFCE1126)),
    _SchoolData('South Carolina', 'Gamecocks', Color(0xFF73000A), Color(0xFF000000)),
    _SchoolData('Tennessee', 'Volunteers', Color(0xFFFF8200), Color(0xFFFFFFFF)),
    _SchoolData('Texas', 'Longhorns', Color(0xFFBF5700), Color(0xFFFFFFFF)),
    _SchoolData('Texas A&M', 'Aggies', Color(0xFF500000), Color(0xFFFFFFFF)),
    _SchoolData('Vanderbilt', 'Commodores', Color(0xFFCFAE70), Color(0xFF000000)),
  ];

  /// Big Ten Football Conference
  static const List<_SchoolData> bigTenFootball = [
    _SchoolData('Illinois', 'Fighting Illini', Color(0xFFE84A27), Color(0xFF13294B)),
    _SchoolData('Indiana', 'Hoosiers', Color(0xFF990000), Color(0xFFFFFFFF)),
    _SchoolData('Iowa', 'Hawkeyes', Color(0xFFFFCD00), Color(0xFF000000)),
    _SchoolData('Maryland', 'Terrapins', Color(0xFFE03A3E), Color(0xFFFFD200)),
    _SchoolData('Michigan', 'Wolverines', Color(0xFF00274C), Color(0xFFFFCB05)),
    _SchoolData('Michigan State', 'Spartans', Color(0xFF18453B), Color(0xFFFFFFFF)),
    _SchoolData('Minnesota', 'Golden Gophers', Color(0xFF7A0019), Color(0xFFFFCC33)),
    _SchoolData('Nebraska', 'Cornhuskers', Color(0xFFE41C38), Color(0xFFFFFFFF)),
    _SchoolData('Northwestern', 'Wildcats', Color(0xFF4E2A84), Color(0xFFFFFFFF)),
    _SchoolData('Ohio State', 'Buckeyes', Color(0xFFBB0000), Color(0xFF666666)),
    _SchoolData('Oregon', 'Ducks', Color(0xFF154733), Color(0xFFFEE123)),
    _SchoolData('Penn State', 'Nittany Lions', Color(0xFF041E42), Color(0xFFFFFFFF)),
    _SchoolData('Purdue', 'Boilermakers', Color(0xFFCFB991), Color(0xFF000000)),
    _SchoolData('Rutgers', 'Scarlet Knights', Color(0xFFCC0033), Color(0xFFFFFFFF)),
    _SchoolData('UCLA', 'Bruins', Color(0xFF2D68C4), Color(0xFFF2A900)),
    _SchoolData('USC', 'Trojans', Color(0xFF990000), Color(0xFFFFC72C)),
    _SchoolData('Washington', 'Huskies', Color(0xFF4B2E83), Color(0xFFB7A57A)),
    _SchoolData('Wisconsin', 'Badgers', Color(0xFFC5050C), Color(0xFFFFFFFF)),
  ];

  /// ACC Football Conference
  static const List<_SchoolData> accFootball = [
    _SchoolData('Boston College', 'Eagles', Color(0xFF8A100B), Color(0xFFCDB87D)),
    _SchoolData('California', 'Golden Bears', Color(0xFF003262), Color(0xFFFDB515)),
    _SchoolData('Clemson', 'Tigers', Color(0xFFF56600), Color(0xFF522D80)),
    _SchoolData('Duke', 'Blue Devils', Color(0xFF003087), Color(0xFFFFFFFF)),
    _SchoolData('Florida State', 'Seminoles', Color(0xFF782F40), Color(0xFFCEB888)),
    _SchoolData('Georgia Tech', 'Yellow Jackets', Color(0xFFB3A369), Color(0xFF003057)),
    _SchoolData('Louisville', 'Cardinals', Color(0xFFAD0000), Color(0xFF000000)),
    _SchoolData('Miami', 'Hurricanes', Color(0xFFF47321), Color(0xFF005030)),
    _SchoolData('North Carolina', 'Tar Heels', Color(0xFF7BAFD4), Color(0xFF13294B)),
    _SchoolData('NC State', 'Wolfpack', Color(0xFFCC0000), Color(0xFFFFFFFF)),
    _SchoolData('Pittsburgh', 'Panthers', Color(0xFF003594), Color(0xFFFFB81C)),
    _SchoolData('SMU', 'Mustangs', Color(0xFF0033A0), Color(0xFFCC0035)),
    _SchoolData('Stanford', 'Cardinal', Color(0xFF8C1515), Color(0xFFFFFFFF)),
    _SchoolData('Syracuse', 'Orange', Color(0xFFD44500), Color(0xFF003F87)),
    _SchoolData('Virginia', 'Cavaliers', Color(0xFF232D4B), Color(0xFFF84C1E)),
    _SchoolData('Virginia Tech', 'Hokies', Color(0xFF630031), Color(0xFFFF6600)),
    _SchoolData('Wake Forest', 'Demon Deacons', Color(0xFF9E7E38), Color(0xFF000000)),
  ];

  /// Big 12 Football Conference
  static const List<_SchoolData> big12Football = [
    _SchoolData('Arizona', 'Wildcats', Color(0xFF003366), Color(0xFFCC0033)),
    _SchoolData('Arizona State', 'Sun Devils', Color(0xFF8C1D40), Color(0xFFFFC627)),
    _SchoolData('Baylor', 'Bears', Color(0xFF003015), Color(0xFFFFC72C)),
    _SchoolData('BYU', 'Cougars', Color(0xFF002E5D), Color(0xFFFFFFFF)),
    _SchoolData('Cincinnati', 'Bearcats', Color(0xFFE00122), Color(0xFF000000)),
    _SchoolData('Colorado', 'Buffaloes', Color(0xFFCFB87C), Color(0xFF000000)),
    _SchoolData('Houston', 'Cougars', Color(0xFFC8102E), Color(0xFFFFFFFF)),
    _SchoolData('Iowa State', 'Cyclones', Color(0xFFC8102E), Color(0xFFF1BE48)),
    _SchoolData('Kansas', 'Jayhawks', Color(0xFF0051BA), Color(0xFFE8000D)),
    _SchoolData('Kansas State', 'Wildcats', Color(0xFF512888), Color(0xFFFFFFFF)),
    _SchoolData('Oklahoma State', 'Cowboys', Color(0xFFFF6600), Color(0xFF000000)),
    _SchoolData('TCU', 'Horned Frogs', Color(0xFF4D1979), Color(0xFFFFFFFF)),
    _SchoolData('Texas Tech', 'Red Raiders', Color(0xFFCC0000), Color(0xFF000000)),
    _SchoolData('UCF', 'Knights', Color(0xFFBA9B37), Color(0xFF000000)),
    _SchoolData('Utah', 'Utes', Color(0xFFCC0000), Color(0xFFFFFFFF)),
    _SchoolData('West Virginia', 'Mountaineers', Color(0xFF002855), Color(0xFFEAAA00)),
  ];

  /// Mountain West Football Conference
  static const List<_SchoolData> mountainWestFootball = [
    _SchoolData('Air Force', 'Falcons', Color(0xFF003087), Color(0xFFC0C0C0)),
    _SchoolData('Boise State', 'Broncos', Color(0xFF0033A0), Color(0xFFD64309)),
    _SchoolData('Colorado State', 'Rams', Color(0xFF1E4D2B), Color(0xFFC8C372)),
    _SchoolData('Fresno State', 'Bulldogs', Color(0xFFDB0032), Color(0xFF002E6D)),
    _SchoolData('Hawaii', 'Rainbow Warriors', Color(0xFF024731), Color(0xFFFFFFFF)),
    _SchoolData('Nevada', 'Wolf Pack', Color(0xFF003366), Color(0xFFC0C0C0)),
    _SchoolData('New Mexico', 'Lobos', Color(0xFFBA0C2F), Color(0xFF63666A)),
    _SchoolData('San Diego State', 'Aztecs', Color(0xFFA6192E), Color(0xFF000000)),
    _SchoolData('San Jose State', 'Spartans', Color(0xFF0055A2), Color(0xFFE5A823)),
    _SchoolData('UNLV', 'Rebels', Color(0xFFCF0A2C), Color(0xFF000000)),
    _SchoolData('Utah State', 'Aggies', Color(0xFF0F2439), Color(0xFFFFFFFF)),
    _SchoolData('Wyoming', 'Cowboys', Color(0xFF492F24), Color(0xFFFFC425)),
  ];

  /// Sun Belt Football Conference
  static const List<_SchoolData> sunBeltFootball = [
    _SchoolData('Appalachian State', 'Mountaineers', Color(0xFF000000), Color(0xFFFFCC00)),
    _SchoolData('Arkansas State', 'Red Wolves', Color(0xFFCC092F), Color(0xFF000000)),
    _SchoolData('Coastal Carolina', 'Chanticleers', Color(0xFF006F71), Color(0xFFB59A57)),
    _SchoolData('Georgia Southern', 'Eagles', Color(0xFF011E41), Color(0xFFFFFFFF)),
    _SchoolData('Georgia State', 'Panthers', Color(0xFF0039A6), Color(0xFFCC0000)),
    _SchoolData('James Madison', 'Dukes', Color(0xFF450084), Color(0xFFCBB677)),
    _SchoolData('Louisiana', 'Ragin\' Cajuns', Color(0xFFCE181E), Color(0xFFFFFFFF)),
    _SchoolData('Louisiana Monroe', 'Warhawks', Color(0xFF800029), Color(0xFFB59A57)),
    _SchoolData('Marshall', 'Thundering Herd', Color(0xFF00B140), Color(0xFFFFFFFF)),
    _SchoolData('Old Dominion', 'Monarchs', Color(0xFF003057), Color(0xFFC0C0C0)),
    _SchoolData('South Alabama', 'Jaguars', Color(0xFF00205B), Color(0xFFBF0D3E)),
    _SchoolData('Southern Miss', 'Golden Eagles', Color(0xFFFFAB00), Color(0xFF000000)),
    _SchoolData('Texas State', 'Bobcats', Color(0xFF501214), Color(0xFF8D734A)),
    _SchoolData('Troy', 'Trojans', Color(0xFF8A2432), Color(0xFFC0C0C0)),
  ];

  /// MAC Football Conference
  static const List<_SchoolData> macFootball = [
    _SchoolData('Akron', 'Zips', Color(0xFF041E42), Color(0xFFB59A57)),
    _SchoolData('Ball State', 'Cardinals', Color(0xFFBA0C2F), Color(0xFFFFFFFF)),
    _SchoolData('Bowling Green', 'Falcons', Color(0xFFFF7300), Color(0xFF4F2C1D)),
    _SchoolData('Buffalo', 'Bulls', Color(0xFF005BBB), Color(0xFFFFFFFF)),
    _SchoolData('Central Michigan', 'Chippewas', Color(0xFF6A0032), Color(0xFFFFC82E)),
    _SchoolData('Eastern Michigan', 'Eagles', Color(0xFF006633), Color(0xFFFFFFFF)),
    _SchoolData('Kent State', 'Golden Flashes', Color(0xFF002664), Color(0xFFF0AB00)),
    _SchoolData('Miami (OH)', 'RedHawks', Color(0xFFC3142D), Color(0xFFFFFFFF)),
    _SchoolData('Northern Illinois', 'Huskies', Color(0xFFBA0C2F), Color(0xFF000000)),
    _SchoolData('Ohio', 'Bobcats', Color(0xFF00694E), Color(0xFFFFFFFF)),
    _SchoolData('Toledo', 'Rockets', Color(0xFF15397F), Color(0xFFFFCD00)),
    _SchoolData('Western Michigan', 'Broncos', Color(0xFF6C4023), Color(0xFFFFAE00)),
  ];

  /// Conference USA Football
  static const List<_SchoolData> cusaFootball = [
    _SchoolData('FIU', 'Panthers', Color(0xFF002F65), Color(0xFFB6862C)),
    _SchoolData('Jacksonville State', 'Gamecocks', Color(0xFFCC0000), Color(0xFFFFFFFF)),
    _SchoolData('Kennesaw State', 'Owls', Color(0xFFFFBD00), Color(0xFF000000)),
    _SchoolData('Liberty', 'Flames', Color(0xFF071B3C), Color(0xFFC41230)),
    _SchoolData('Middle Tennessee', 'Blue Raiders', Color(0xFF0066CC), Color(0xFFFFFFFF)),
    _SchoolData('New Mexico State', 'Aggies', Color(0xFF8B0000), Color(0xFFFFFFFF)),
    _SchoolData('Sam Houston', 'Bearkats', Color(0xFFFF5F00), Color(0xFFFFFFFF)),
    _SchoolData('UTEP', 'Miners', Color(0xFFFF8200), Color(0xFF041E42)),
    _SchoolData('Western Kentucky', 'Hilltoppers', Color(0xFFCC0000), Color(0xFFFFFFFF)),
  ];

  /// American Athletic Conference Football
  static const List<_SchoolData> aacFootball = [
    _SchoolData('Army', 'Black Knights', Color(0xFFD2B569), Color(0xFF000000)),
    _SchoolData('Charlotte', 'Niners', Color(0xFF046A38), Color(0xFFFFFFFF)),
    _SchoolData('East Carolina', 'Pirates', Color(0xFF592A8A), Color(0xFFFFC72C)),
    _SchoolData('FAU', 'Owls', Color(0xFF003366), Color(0xFFCC0000)),
    _SchoolData('Memphis', 'Tigers', Color(0xFF003087), Color(0xFFA0A0A0)),
    _SchoolData('Navy', 'Midshipmen', Color(0xFF00205B), Color(0xFFB59A57)),
    _SchoolData('North Texas', 'Mean Green', Color(0xFF00853E), Color(0xFFFFFFFF)),
    _SchoolData('Rice', 'Owls', Color(0xFF003D7D), Color(0xFF5E6A71)),
    _SchoolData('South Florida', 'Bulls', Color(0xFF006747), Color(0xFFCFC493)),
    _SchoolData('Temple', 'Owls', Color(0xFF9D2235), Color(0xFFFFFFFF)),
    _SchoolData('Tulane', 'Green Wave', Color(0xFF006747), Color(0xFF87CEEB)),
    _SchoolData('Tulsa', 'Golden Hurricane', Color(0xFF002D62), Color(0xFFC8A774)),
    _SchoolData('UAB', 'Blazers', Color(0xFF1E6B52), Color(0xFFFFD200)),
    _SchoolData('UTSA', 'Roadrunners', Color(0xFF0C2340), Color(0xFFF47321)),
  ];

  // ==================== NCAA BASKETBALL CONFERENCES ====================

  /// Big East Basketball Conference
  static const List<_SchoolData> bigEastBasketball = [
    _SchoolData('Butler', 'Bulldogs', Color(0xFF13294B), Color(0xFFFFFFFF)),
    _SchoolData('Creighton', 'Bluejays', Color(0xFF005CA9), Color(0xFFFFFFFF)),
    _SchoolData('DePaul', 'Blue Demons', Color(0xFF005EB8), Color(0xFFE4002B)),
    _SchoolData('Georgetown', 'Hoyas', Color(0xFF041E42), Color(0xFF8D817B)),
    _SchoolData('Marquette', 'Golden Eagles', Color(0xFF003366), Color(0xFFFFC72C)),
    _SchoolData('Providence', 'Friars', Color(0xFF000000), Color(0xFFFFFFFF)),
    _SchoolData('Seton Hall', 'Pirates', Color(0xFF004488), Color(0xFFFFFFFF)),
    _SchoolData('St. John\'s', 'Red Storm', Color(0xFFCC0033), Color(0xFFFFFFFF)),
    _SchoolData('UConn', 'Huskies', Color(0xFF000E2F), Color(0xFFFFFFFF)),
    _SchoolData('Villanova', 'Wildcats', Color(0xFF003366), Color(0xFFFFFFFF)),
    _SchoolData('Xavier', 'Musketeers', Color(0xFF0C2340), Color(0xFFFFFFFF)),
  ];

  /// Atlantic 10 Basketball Conference
  static const List<_SchoolData> atlantic10Basketball = [
    _SchoolData('Dayton', 'Flyers', Color(0xFFCE1141), Color(0xFF004B8D)),
    _SchoolData('Davidson', 'Wildcats', Color(0xFFCC0000), Color(0xFF000000)),
    _SchoolData('Duquesne', 'Dukes', Color(0xFF003366), Color(0xFFCC0000)),
    _SchoolData('Fordham', 'Rams', Color(0xFF7C2529), Color(0xFFFFFFFF)),
    _SchoolData('George Mason', 'Patriots', Color(0xFF006633), Color(0xFFFFCC00)),
    _SchoolData('George Washington', 'Colonials', Color(0xFF004C97), Color(0xFFD4AF37)),
    _SchoolData('La Salle', 'Explorers', Color(0xFF003366), Color(0xFFB59A57)),
    _SchoolData('Loyola Chicago', 'Ramblers', Color(0xFF7C0032), Color(0xFFFFD700)),
    _SchoolData('Massachusetts', 'Minutemen', Color(0xFF881C1C), Color(0xFFFFFFFF)),
    _SchoolData('Rhode Island', 'Rams', Color(0xFF75B2DD), Color(0xFF002147)),
    _SchoolData('Richmond', 'Spiders', Color(0xFF990000), Color(0xFF00205B)),
    _SchoolData('Saint Joseph\'s', 'Hawks', Color(0xFF9E1B32), Color(0xFFFFFFFF)),
    _SchoolData('Saint Louis', 'Billikens', Color(0xFF003DA5), Color(0xFFFFFFFF)),
    _SchoolData('St. Bonaventure', 'Bonnies', Color(0xFF7C3625), Color(0xFFFFFFFF)),
    _SchoolData('VCU', 'Rams', Color(0xFF000000), Color(0xFFFFCC00)),
  ];

  /// West Coast Conference Basketball
  static const List<_SchoolData> wccBasketball = [
    _SchoolData('BYU', 'Cougars', Color(0xFF002E5D), Color(0xFFFFFFFF)),
    _SchoolData('Gonzaga', 'Bulldogs', Color(0xFF002967), Color(0xFFBC0031)),
    _SchoolData('Loyola Marymount', 'Lions', Color(0xFF00205B), Color(0xFF8B0000)),
    _SchoolData('Pacific', 'Tigers', Color(0xFFFF6600), Color(0xFF000000)),
    _SchoolData('Pepperdine', 'Waves', Color(0xFF00205B), Color(0xFFFF6600)),
    _SchoolData('Portland', 'Pilots', Color(0xFF4E148C), Color(0xFFFFFFFF)),
    _SchoolData('Saint Mary\'s', 'Gaels', Color(0xFF003366), Color(0xFFCC0000)),
    _SchoolData('San Diego', 'Toreros', Color(0xFF002B5C), Color(0xFF88D4F4)),
    _SchoolData('San Francisco', 'Dons', Color(0xFF006633), Color(0xFFFFCC00)),
    _SchoolData('Santa Clara', 'Broncos', Color(0xFF862633), Color(0xFFFFFFFF)),
  ];

  /// Missouri Valley Conference Basketball
  static const List<_SchoolData> mvcBasketball = [
    _SchoolData('Belmont', 'Bruins', Color(0xFF002D62), Color(0xFFCC0000)),
    _SchoolData('Bradley', 'Braves', Color(0xFFCC0000), Color(0xFFFFFFFF)),
    _SchoolData('Drake', 'Bulldogs', Color(0xFF002D62), Color(0xFFFFFFFF)),
    _SchoolData('Evansville', 'Purple Aces', Color(0xFF5F259F), Color(0xFFFF6600)),
    _SchoolData('Illinois State', 'Redbirds', Color(0xFFCB0019), Color(0xFFFFFFFF)),
    _SchoolData('Indiana State', 'Sycamores', Color(0xFF00447C), Color(0xFFFFFFFF)),
    _SchoolData('Missouri State', 'Bears', Color(0xFF800029), Color(0xFFFFFFFF)),
    _SchoolData('Murray State', 'Racers', Color(0xFF002144), Color(0xFFFFD200)),
    _SchoolData('Northern Iowa', 'Panthers', Color(0xFF4B116F), Color(0xFFFFCC00)),
    _SchoolData('Southern Illinois', 'Salukis', Color(0xFF720000), Color(0xFFFFFFFF)),
    _SchoolData('UIC', 'Flames', Color(0xFF001E62), Color(0xFFCC0000)),
    _SchoolData('Valparaiso', 'Beacons', Color(0xFF613318), Color(0xFFFFCC00)),
  ];

  /// Get football conference data
  static List<_SchoolData> getFootballConference(String conferenceId) {
    switch (conferenceId) {
      case 'ncaafb_sec':
        return secFootball;
      case 'ncaafb_bigten':
        return bigTenFootball;
      case 'ncaafb_acc':
        return accFootball;
      case 'ncaafb_big12':
        return big12Football;
      case 'ncaafb_mw':
        return mountainWestFootball;
      case 'ncaafb_sunbelt':
        return sunBeltFootball;
      case 'ncaafb_mac':
        return macFootball;
      case 'ncaafb_cusa':
        return cusaFootball;
      case 'ncaafb_aac':
        return aacFootball;
      default:
        return [];
    }
  }

  /// Get basketball conference data
  static List<_SchoolData> getBasketballConference(String conferenceId) {
    switch (conferenceId) {
      case 'ncaabb_sec':
        return secFootball; // Same schools
      case 'ncaabb_bigten':
        return bigTenFootball;
      case 'ncaabb_acc':
        return accFootball;
      case 'ncaabb_big12':
        return big12Football;
      case 'ncaabb_bigeast':
        return bigEastBasketball;
      case 'ncaabb_a10':
        return atlantic10Basketball;
      case 'ncaabb_wcc':
        return wccBasketball;
      case 'ncaabb_mvc':
        return mvcBasketball;
      case 'ncaabb_mw':
        return mountainWestFootball;
      case 'ncaabb_aac':
        return aacFootball;
      default:
        return [];
    }
  }

  /// Get all NCAA folder nodes
  static List<LibraryNode> getNcaaFolders() {
    return const [
      // NCAA Football parent
      LibraryNode(
        id: 'ncaa_football',
        name: 'NCAA Football',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_sports',
        sortOrder: 6,
      ),
      // Football conferences
      LibraryNode(id: 'ncaafb_sec', name: 'SEC', nodeType: LibraryNodeType.folder, parentId: 'ncaa_football', sortOrder: 0),
      LibraryNode(id: 'ncaafb_bigten', name: 'Big Ten', nodeType: LibraryNodeType.folder, parentId: 'ncaa_football', sortOrder: 1),
      LibraryNode(id: 'ncaafb_acc', name: 'ACC', nodeType: LibraryNodeType.folder, parentId: 'ncaa_football', sortOrder: 2),
      LibraryNode(id: 'ncaafb_big12', name: 'Big 12', nodeType: LibraryNodeType.folder, parentId: 'ncaa_football', sortOrder: 3),
      LibraryNode(id: 'ncaafb_mw', name: 'Mountain West', nodeType: LibraryNodeType.folder, parentId: 'ncaa_football', sortOrder: 4),
      LibraryNode(id: 'ncaafb_sunbelt', name: 'Sun Belt', nodeType: LibraryNodeType.folder, parentId: 'ncaa_football', sortOrder: 5),
      LibraryNode(id: 'ncaafb_mac', name: 'MAC', nodeType: LibraryNodeType.folder, parentId: 'ncaa_football', sortOrder: 6),
      LibraryNode(id: 'ncaafb_cusa', name: 'Conference USA', nodeType: LibraryNodeType.folder, parentId: 'ncaa_football', sortOrder: 7),
      LibraryNode(id: 'ncaafb_aac', name: 'American', nodeType: LibraryNodeType.folder, parentId: 'ncaa_football', sortOrder: 8),

      // NCAA Basketball parent
      LibraryNode(
        id: 'ncaa_basketball',
        name: 'NCAA Basketball',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_sports',
        sortOrder: 7,
      ),
      // Basketball conferences
      LibraryNode(id: 'ncaabb_sec', name: 'SEC', nodeType: LibraryNodeType.folder, parentId: 'ncaa_basketball', sortOrder: 0),
      LibraryNode(id: 'ncaabb_bigten', name: 'Big Ten', nodeType: LibraryNodeType.folder, parentId: 'ncaa_basketball', sortOrder: 1),
      LibraryNode(id: 'ncaabb_acc', name: 'ACC', nodeType: LibraryNodeType.folder, parentId: 'ncaa_basketball', sortOrder: 2),
      LibraryNode(id: 'ncaabb_big12', name: 'Big 12', nodeType: LibraryNodeType.folder, parentId: 'ncaa_basketball', sortOrder: 3),
      LibraryNode(id: 'ncaabb_bigeast', name: 'Big East', nodeType: LibraryNodeType.folder, parentId: 'ncaa_basketball', sortOrder: 4),
      LibraryNode(id: 'ncaabb_a10', name: 'Atlantic 10', nodeType: LibraryNodeType.folder, parentId: 'ncaa_basketball', sortOrder: 5),
      LibraryNode(id: 'ncaabb_wcc', name: 'West Coast', nodeType: LibraryNodeType.folder, parentId: 'ncaa_basketball', sortOrder: 6),
      LibraryNode(id: 'ncaabb_mvc', name: 'Missouri Valley', nodeType: LibraryNodeType.folder, parentId: 'ncaa_basketball', sortOrder: 7),
      LibraryNode(id: 'ncaabb_mw', name: 'Mountain West', nodeType: LibraryNodeType.folder, parentId: 'ncaa_basketball', sortOrder: 8),
      LibraryNode(id: 'ncaabb_aac', name: 'American', nodeType: LibraryNodeType.folder, parentId: 'ncaa_basketball', sortOrder: 9),
    ];
  }

  /// Convert all schools to LibraryNodes
  static List<LibraryNode> getAllSchoolNodes() {
    final nodes = <LibraryNode>[];

    void addSchools(String parentId, List<_SchoolData> schools, String sport) {
      for (var i = 0; i < schools.length; i++) {
        final school = schools[i];
        nodes.add(LibraryNode(
          id: '${parentId}_${school.name.toLowerCase().replaceAll(' ', '_').replaceAll('\'', '').replaceAll('(', '').replaceAll(')', '')}',
          name: '${school.name} ${school.mascot}',
          nodeType: LibraryNodeType.palette,
          parentId: parentId,
          themeColors: [school.primaryColor, school.secondaryColor],
          sortOrder: i,
          metadata: {
            'school': school.name,
            'mascot': school.mascot,
            'sport': sport,
            'suggestedEffects': [12, 41, 0], // Theater Chase, Running, Solid
          },
        ));
      }
    }

    // Football conferences
    addSchools('ncaafb_sec', secFootball, 'football');
    addSchools('ncaafb_bigten', bigTenFootball, 'football');
    addSchools('ncaafb_acc', accFootball, 'football');
    addSchools('ncaafb_big12', big12Football, 'football');
    addSchools('ncaafb_mw', mountainWestFootball, 'football');
    addSchools('ncaafb_sunbelt', sunBeltFootball, 'football');
    addSchools('ncaafb_mac', macFootball, 'football');
    addSchools('ncaafb_cusa', cusaFootball, 'football');
    addSchools('ncaafb_aac', aacFootball, 'football');

    // Basketball conferences
    addSchools('ncaabb_sec', secFootball, 'basketball');
    addSchools('ncaabb_bigten', bigTenFootball, 'basketball');
    addSchools('ncaabb_acc', accFootball, 'basketball');
    addSchools('ncaabb_big12', big12Football, 'basketball');
    addSchools('ncaabb_bigeast', bigEastBasketball, 'basketball');
    addSchools('ncaabb_a10', atlantic10Basketball, 'basketball');
    addSchools('ncaabb_wcc', wccBasketball, 'basketball');
    addSchools('ncaabb_mvc', mvcBasketball, 'basketball');
    addSchools('ncaabb_mw', mountainWestFootball, 'basketball');
    addSchools('ncaabb_aac', aacFootball, 'basketball');

    return nodes;
  }
}

/// Internal helper class for school data
class _SchoolData {
  final String name;
  final String mascot;
  final Color primaryColor;
  final Color secondaryColor;

  const _SchoolData(this.name, this.mascot, this.primaryColor, this.secondaryColor);
}
