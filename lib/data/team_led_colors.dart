// LED-calibrated team colours — the values SENT TO CONTROLLERS.
//
// Pure Dart (no flutter / dart:ui) so the bench CLI can import the real table:
// `dart run bench/bin/team_led_preview.dart`.
//
// ─── WHY THIS EXISTS ───────────────────────────────────────────────────────
// Team tables (kTeamColors, TeamColorDatabase, NcaaConferences, the commercial
// geo table) carry BRAND hex: the colour a team prints and a screen shows. Sent
// straight to a controller they read wrong, because brightness on a WLED
// controller is `bri` and the colour is lit at LED intensity. Green Bay's
// #203731 has B ≈ G; on a screen it is dark, so it reads "dark green". Lit, its
// literal hue (164°) is teal. The owner fixed it by hand by dragging to pure
// green and setting brightness separately. This table is that fix, for every
// team colour we ship.
//
// ─── THE RULE ──────────────────────────────────────────────────────────────
// Brand hex stays the UI colour (cards, logos, pickers). The LED colour is used
// ONLY where a team colour becomes a controller payload. Keep the team's hue
// true (the hue a fan names, not the literal hex hue of a dark colour), push
// saturation up, and use full value — `bri` owns brightness.
//
// Designed for the fleet's WLED colour gamma 2.8 (`kNglLightGammaConfig`),
// which maps these sRGB-style values onto the LEDs the way a screen would. On a
// controller whose colour gamma is OFF they will look paler than intended.
//
// Problem classes (trailing comment on each entry):
//   dark green→teal         blue-green hex rotated to the green fans name
//   navy→purple             red zeroed, hue held in blue
//   maroon→pink             blue stripped, full-saturation deep red
//   brown→orange            LEDs cannot emit brown (dark orange); closest amber
//   gold→green-yellow       hue held, blue dropped (gamma already darkens green)
//   silver/white→blue tint  all-dies-full white is bluish; warmed
//   purple→blue             blue die dominates a purple mix; red raised
//   black (unlit)           black is "off" on an LED; unchanged in effect
//   —                       saturation/value only
//
// ─── EDITING ───────────────────────────────────────────────────────────────
// Keyed by BRAND RGB (0xRRGGBB), not by team, so it covers every table and
// every Firestore config that stored a brand ARGB int — no migration. Teams
// that share a brand hex share an LED value. Tune values on the bench
// (`bench/bin/team_led_preview.dart`, spare controller only), then MIRROR the
// edit in functions/src/teamLedColors.ts — test/data/team_led_colors_test.dart
// fails if the two drift, and fails if a team colour has no entry here.

/// An RGB triple calibrated for LED output. W is always sent as 0: a team
/// colour must never light the white die (it washes saturated colours out).
class LedRgb {
  const LedRgb(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  /// `[r, g, b, 0]` — the 4-slot WLED `col` entry the fleet sends.
  List<int> toRgbw() => <int>[r, g, b, 0];

  /// `[r, g, b]`.
  List<int> toRgb() => <int>[r, g, b];

  /// 0xRRGGBB.
  int get rgb => (r << 16) | (g << 8) | b;

  @override
  bool operator ==(Object other) =>
      other is LedRgb && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => 'LedRgb($r, $g, $b)';
}

/// The LED colour to SEND for a team brand colour.
///
/// Accepts 0xRRGGBB or 0xAARRGGBB (alpha ignored), so a stored
/// `primary_color` ARGB int or `Color.toARGB32()` can be passed directly. A
/// colour not in [kTeamLedRgb] — a custom team, a user-picked colour — is
/// returned unchanged, which is exactly what was sent before this table.
LedRgb teamLedRgb(int brandRgbOrArgb) {
  final rgb = brandRgbOrArgb & 0xFFFFFF;
  return kTeamLedRgb[rgb] ??
      LedRgb((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF);
}

/// True when [brandRgbOrArgb] is a calibrated team colour.
bool hasTeamLedRgb(int brandRgbOrArgb) =>
    kTeamLedRgb.containsKey(brandRgbOrArgb & 0xFFFFFF);

/// Brand RGB → LED RGB, for every colour of every team in every table.
const Map<int, LedRgb> kTeamLedRgb = <int, LedRgb>{
  0x000000: LedRgb(0, 0, 0), // black (unlit) · Aces Black, All Whites Black
  0x000033: LedRgb(0, 34, 255), // navy→purple · SD Navy
  0x000080: LedRgb(0, 21, 255), // — · Japan Blue
  0x000E2F: LedRgb(0, 76, 255), // navy→purple · UConn Huskies
  0x001628: LedRgb(0, 85, 255), // navy→purple · Kraken Blue
  0x001E62: LedRgb(0, 78, 255), // navy→purple · UIC Flames
  0x00205B: LedRgb(0, 85, 255), // navy→purple · Canucks Blue, Leafs Blue
  0x00205C: LedRgb(0, 85, 255), // navy→purple · Saint Mary's Gaels
  0x002144: LedRgb(0, 85, 255), // navy→purple · Murray State Racers
  0x002147: LedRgb(0, 85, 255), // navy→purple · Rhode Island Rams
  0x0021A5: LedRgb(0, 51, 255), // — · Florida Blue
  0x002244: LedRgb(0, 85, 255), // navy→purple · Broncos Navy, Patriots Navy
  0x002395: LedRgb(0, 60, 255), // — · France Blue
  0x00245D: LedRgb(0, 85, 255), // navy→purple · Galaxy Navy
  0x00245E: LedRgb(0, 85, 255), // navy→purple · Whitecaps Blue
  0x002649: LedRgb(0, 85, 255), // navy→purple · Toledo Rockets
  0x002654: LedRgb(0, 85, 255), // navy→purple · Blue Jackets Navy, PSG Navy
  0x002664: LedRgb(0, 85, 255), // navy→purple · Kent State Golden Flashes
  0x00274C: LedRgb(0, 85, 255), // navy→purple · Michigan Blue
  0x002776: LedRgb(0, 84, 255), // navy→purple · Brazil Blue
  0x002855: LedRgb(0, 85, 255), // navy→purple · WVU Blue
  0x002868: LedRgb(0, 85, 255), // navy→purple · Lightning Blue, Norway Blue
  0x002967: LedRgb(0, 85, 255), // navy→purple · Gonzaga Bulldogs
  0x002B5C: LedRgb(0, 85, 255), // navy→purple · Jazz Navy, Mystics Navy
  0x002B5E: LedRgb(0, 85, 255), // navy→purple · Mavs Navy
  0x002B7F: LedRgb(0, 85, 255), // navy→purple · Costa Rica Blue
  0x002C5F: LedRgb(0, 85, 255), // navy→purple · Colts Blue
  0x002D62: LedRgb(0, 85, 255), // navy→purple · Astros Navy, Fever Navy
  0x002D72: LedRgb(0, 85, 255), // navy→purple · Mets Blue, Phillies Blue
  0x002E5D: LedRgb(0, 85, 255), // navy→purple · BYU Blue
  0x002E6D: LedRgb(0, 85, 255), // navy→purple · Fresno State Bulldogs
  0x002F65: LedRgb(0, 85, 255), // navy→purple · SKC Blue
  0x002F87: LedRgb(0, 89, 255), // — · Blues Blue
  0x003015: LedRgb(0, 255, 12), // dark green→teal · Baylor Bears
  0x003057: LedRgb(0, 85, 255), // navy→purple · Georgia Tech Yellow Jackets, Old Dominion Monarchs
  0x003087: LedRgb(0, 91, 255), // — · Duke Blue, FCC Blue
  0x003153: LedRgb(0, 85, 255), // navy→purple · Courage Navy
  0x003171: LedRgb(0, 85, 255), // navy→purple · Bologna Blue
  0x003262: LedRgb(0, 85, 255), // navy→purple · California Golden Bears
  0x003263: LedRgb(0, 85, 255), // navy→purple · Los Angeles Angels
  0x003278: LedRgb(0, 85, 255), // navy→purple · Rangers Blue
  0x003366: LedRgb(0, 85, 255), // navy→purple · Arizona Navy, Red Stars Navy
  0x00338D: LedRgb(0, 92, 255), // — · Bills Blue
  0x003399: LedRgb(0, 85, 255), // — · Everton Blue, Scotland Blue
  0x0033A0: LedRgb(0, 81, 255), // — · Kentucky Blue
  0x0033A1: LedRgb(0, 81, 255), // — · Montreal Blue
  0x003478: LedRgb(0, 85, 255), // navy→purple · Korea Blue
  0x003594: LedRgb(0, 85, 255), // navy→purple · Cowboys Navy, Rams Blue
  0x003831: LedRgb(0, 255, 34), // dark green→teal · Athletics Green
  0x00385D: LedRgb(0, 85, 255), // navy→purple · Guardians Navy
  0x003893: LedRgb(0, 97, 255), // — · Colombia Blue
  0x0038A8: LedRgb(0, 85, 255), // — · Paraguay Blue, Rangers Blue
  0x0039A6: LedRgb(0, 88, 255), // — · Chile Blue
  0x003CA6: LedRgb(0, 92, 255), // — · Heidenheim Blue
  0x003D7D: LedRgb(0, 85, 255), // navy→purple · Rice Owls
  0x003DA5: LedRgb(0, 94, 255), // — · Alaves Blue, Las Palmas Blue
  0x003E7E: LedRgb(0, 85, 255), // navy→purple · South Alabama Jaguars
  0x003F87: LedRgb(0, 119, 255), // — · Syracuse Orange
  0x003F91: LedRgb(0, 111, 255), // — · Porto Blue
  0x004170: LedRgb(0, 85, 255), // navy→purple · Paris Saint-Germain
  0x00447C: LedRgb(0, 85, 255), // navy→purple · Indiana State Sycamores
  0x004488: LedRgb(0, 128, 255), // — · Seton Hall Pirates
  0x004687: LedRgb(0, 132, 255), // — · Royals Blue
  0x00471B: LedRgb(0, 255, 8), // dark green→teal · Bucks Green, Jazz Green
  0x004812: LedRgb(0, 255, 0), // dark green→teal · Timbers Green
  0x004A8D: LedRgb(0, 134, 255), // — · SSC Napoli
  0x004B28: LedRgb(0, 255, 18), // dark green→teal · Thorns Green
  0x004B87: LedRgb(0, 142, 255), // — · Frosinone Blue
  0x004B8D: LedRgb(0, 136, 255), // — · Dayton Flyers
  0x004C54: LedRgb(0, 255, 85), // dark green→teal · Eagles Green
  0x004C97: LedRgb(0, 128, 255), // — · Jets Blue
  0x004D98: LedRgb(0, 129, 255), // — · Barca Blue
  0x004E9E: LedRgb(0, 126, 255), // — · Darmstadt Blue
  0x004FA3: LedRgb(0, 124, 255), // — · Getafe Blue
  0x005030: LedRgb(0, 255, 22), // dark green→teal · Miami Green
  0x005187: LedRgb(0, 85, 255), // navy→purple · Villarreal Navy
  0x0051BA: LedRgb(0, 111, 255), // — · Kansas Blue
  0x00529F: LedRgb(0, 132, 255), // — · Cadiz Blue, Empoli Blue
  0x00538C: LedRgb(0, 151, 255), // — · Mavs Blue
  0x00539B: LedRgb(0, 137, 255), // — · Islanders Blue
  0x00539F: LedRgb(0, 133, 255), // — · Battlehawks Blue
  0x00543D: LedRgb(0, 255, 30), // dark green→teal · Augsburg Green
  0x0054A6: LedRgb(0, 129, 255), // — · Creighton Bluejays
  0x005595: LedRgb(0, 145, 255), // — · Sounders Blue
  0x0055A2: LedRgb(0, 134, 255), // — · San Jose State Spartans
  0x0057B8: LedRgb(0, 121, 255), // — · Brighton Blue
  0x005A9C: LedRgb(0, 147, 255), // — · Dodgers Blue
  0x005BA1: LedRgb(0, 144, 255), // — · Bochum Blue
  0x005BBB: LedRgb(0, 124, 255), // — · Ukraine Blue
  0x005C5C: LedRgb(0, 255, 255), // — · Mariners Teal
  0x005CA9: LedRgb(0, 139, 255), // — · Creighton Bluejays
  0x005DA4: LedRgb(0, 145, 255), // — · Slovenia Blue
  0x005EB8: LedRgb(0, 130, 255), // — · DePaul Blue Demons
  0x006233: LedRgb(0, 255, 17), // dark green→teal · Algeria Green, Morocco Green
  0x006600: LedRgb(0, 255, 0), // — · Portugal Green
  0x006633: LedRgb(0, 255, 16), // dark green→teal · Eastern Michigan Eagles, George Mason Patriots
  0x0066B2: LedRgb(0, 146, 255), // — · Bayern Munich
  0x0066CC: LedRgb(0, 128, 255), // — · Middle Tennessee Blue Raiders
  0x006747: LedRgb(0, 255, 28), // dark green→teal · South Florida Bulls, Tulane Green Wave
  0x006778: LedRgb(0, 219, 255), // — · Jaguars Teal
  0x0067B1: LedRgb(0, 148, 255), // — · Quakes Blue
  0x006838: LedRgb(0, 255, 18), // dark green→teal · Celtic Green, Sporting Green
  0x006847: LedRgb(0, 255, 28), // dark green→teal · Mexico Green, Stars Green
  0x00694E: LedRgb(0, 255, 31), // dark green→teal · Ohio Bobcats
  0x006AA7: LedRgb(0, 162, 255), // — · Sweden Blue
  0x006B3F: LedRgb(0, 255, 22), // dark green→teal · Ghana Green
  0x006BB6: LedRgb(0, 150, 255), // — · 76ers Blue, Knicks Blue
  0x006C35: LedRgb(0, 255, 15), // dark green→teal · Saudi Green
  0x006D75: LedRgb(0, 238, 255), // — · Sharks Teal
  0x006F71: LedRgb(0, 250, 255), // — · Coastal Carolina Chanticleers
  0x00703C: LedRgb(0, 255, 18), // dark green→teal · Charlotte 49ers
  0x0073CF: LedRgb(0, 142, 255), // — · Honduras Blue
  0x0076B6: LedRgb(0, 165, 255), // — · Lions Blue
  0x007749: LedRgb(0, 255, 23), // dark green→teal · Bafana Green
  0x0077C0: LedRgb(0, 158, 255), // — · Magic Blue
  0x0077C8: LedRgb(0, 152, 255), // — · Marlins Blue
  0x00788C: LedRgb(0, 219, 255), // — · Hornets Teal
  0x007A33: LedRgb(0, 255, 11), // dark green→teal · Bolivia Green, Celtics Green
  0x007A5E: LedRgb(0, 255, 33), // dark green→teal · Cameroon Green
  0x007AC1: LedRgb(0, 161, 255), // — · Thunder Blue
  0x007FFF: LedRgb(0, 127, 255), // — · Congo Blue
  0x0080C6: LedRgb(0, 165, 255), // — · Chargers Blue
  0x00843D: LedRgb(0, 255, 14), // dark green→teal · Canucks Green, Socceroos Green
  0x00853E: LedRgb(0, 255, 14), // dark green→teal · North Texas Mean Green
  0x00853F: LedRgb(0, 255, 14), // dark green→teal · Senegal Green
  0x0085CA: LedRgb(0, 168, 255), // — · Panthers Blue
  0x008751: LedRgb(0, 255, 22), // dark green→teal · Nigeria Green
  0x008E97: LedRgb(0, 240, 255), // — · Dolphins Aqua
  0x00954C: LedRgb(0, 255, 17), // dark green→teal · Betis Green
  0x009739: LedRgb(0, 255, 8), // dark green→teal · Brazil Green
  0x009A44: LedRgb(0, 255, 12), // dark green→teal · Ivory Coast Green
  0x009B3A: LedRgb(0, 255, 8), // dark green→teal · Jamaica Green
  0x009FE3: LedRgb(0, 179, 255), // — · Napoli Blue
  0x00A3AD: LedRgb(0, 240, 255), // — · Current Teal
  0x00A3E0: LedRgb(0, 186, 255), // — · Miami Marlins
  0x00A651: LedRgb(0, 255, 15), // dark green→teal · Sea Dragons Green
  0x00A6A6: LedRgb(0, 255, 255), // — · Bay Teal
  0x00A752: LedRgb(0, 255, 15), // dark green→teal · Sassuolo Green
  0x00AB39: LedRgb(0, 255, 5), // dark green→teal · Wales Green
  0x00B140: LedRgb(0, 255, 7), // dark green→teal · Austin Verde
  0x00B2A9: LedRgb(0, 255, 242), // — · Valkyries Sea
  0x00B5E2: LedRgb(0, 204, 255), // — · Dash Blue
  0x010101: LedRgb(0, 0, 0), // black (unlit) · Utah Black
  0x010E80: LedRgb(0, 26, 255), // — · Inter Blue
  0x011E41: LedRgb(0, 85, 255), // navy→purple · Georgia Southern Eagles
  0x013A81: LedRgb(0, 114, 255), // — · RSL Cobalt
  0x024731: LedRgb(0, 255, 27), // dark green→teal · Hawaii Rainbow Warriors
  0x03202F: LedRgb(0, 85, 255), // navy→purple · Texans Navy
  0x03244D: LedRgb(0, 85, 255), // navy→purple · Auburn Navy
  0x034694: LedRgb(1, 119, 255), // — · Chelsea Blue
  0x034EA2: LedRgb(1, 121, 255), // — · Ecuador Blue
  0x041E42: LedRgb(0, 85, 255), // navy→purple · Blues Navy, Capitals Navy
  0x046A38: LedRgb(0, 255, 17), // dark green→teal · Charlotte Niners
  0x071B2C: LedRgb(0, 85, 255), // navy→purple · Union Navy
  0x071B3C: LedRgb(0, 85, 255), // navy→purple · Liberty Flames
  0x081E3F: LedRgb(0, 85, 255), // navy→purple · FIU Panthers
  0x092C5C: LedRgb(0, 85, 255), // navy→purple · Rays Navy
  0x0A0A0A: LedRgb(0, 0, 0), // black (unlit) · Spirit Black
  0x0A174A: LedRgb(0, 52, 255), // navy→purple · Chicago Fire FC
  0x0A2141: LedRgb(0, 85, 255), // navy→purple · Red Bulls Navy
  0x0A2240: LedRgb(0, 85, 255), // navy→purple · Revs Navy, Sun Blue
  0x0B162A: LedRgb(0, 85, 255), // navy→purple · Bears Navy
  0x0B2265: LedRgb(0, 65, 255), // navy→purple · Giants Blue
  0x0B3D91: LedRgb(5, 98, 255), // — · Reign Blue, Royals Blue
  0x0C2340: LedRgb(0, 85, 255), // navy→purple · Cardinals Navy, Dream Navy
  0x0C2C56: LedRgb(0, 85, 255), // navy→purple · Mariners Navy
  0x0C4076: LedRgb(0, 85, 255), // navy→purple · Serbia Blue
  0x0E2240: LedRgb(0, 85, 255), // navy→purple · Boston Navy, Nuggets Navy
  0x0E3386: LedRgb(5, 82, 255), // — · Cubs Blue
  0x0F1E46: LedRgb(0, 70, 255), // navy→purple · CITY Navy
  0x0F2439: LedRgb(0, 85, 255), // navy→purple · Utah State Aggies
  0x101820: LedRgb(0, 0, 0), // black (unlit) · Jaguars Black, Panthers Black
  0x111111: LedRgb(0, 0, 0), // black (unlit) · Coyotes Black, Flames Black
  0x11457E: LedRgb(0, 85, 255), // navy→purple · Czech Blue
  0x1164B4: LedRgb(9, 134, 255), // — · FCD Blue
  0x12173F: LedRgb(0, 34, 255), // navy→purple · Grizzlies Navy
  0x12284B: LedRgb(0, 85, 255), // navy→purple · Brewers Navy
  0x125740: LedRgb(0, 255, 27), // dark green→teal · Jets Green
  0x12A0D7: LedRgb(11, 187, 255), // — · Napoli Blue
  0x132257: LedRgb(0, 56, 255), // navy→purple · Osasuna Navy, Spurs Navy
  0x132448: LedRgb(0, 82, 255), // navy→purple · Roughnecks Navy
  0x13274F: LedRgb(0, 85, 255), // navy→purple · Braves Navy
  0x13294B: LedRgb(0, 85, 255), // navy→purple · Illinois Blue
  0x134A8E: LedRgb(8, 118, 255), // — · Blue Jays Blue
  0x141B4D: LedRgb(0, 34, 255), // navy→purple · Chicago Fire FC
  0x14213D: LedRgb(0, 81, 255), // navy→purple · Ole Miss Navy
  0x14225A: LedRgb(0, 51, 255), // navy→purple · Nationals Navy
  0x14B53A: LedRgb(11, 255, 69), // — · Mali Green
  0x15397F: LedRgb(0, 85, 255), // navy→purple · Toledo Rockets
  0x154733: LedRgb(0, 255, 22), // dark green→teal · Baylor Green, Oregon Green
  0x154734: LedRgb(0, 255, 24), // dark green→teal · Wild Green
  0x171796: LedRgb(10, 30, 255), // — · Croatia Blue
  0x18453B: LedRgb(0, 255, 34), // dark green→teal · MSU Green
  0x184817: LedRgb(5, 255, 0), // — · Packers
  0x192168: LedRgb(0, 34, 255), // navy→purple · Canadiens Blue
  0x1961B5: LedRgb(14, 125, 255), // — · Hoffenheim Blue
  0x1A2857: LedRgb(0, 59, 255), // navy→purple · Genoa Navy
  0x1A85C8: LedRgb(16, 163, 255), // — · Charlotte Blue
  0x1B458F: LedRgb(11, 99, 255), // — · Palace Red
  0x1BB1E7: LedRgb(18, 192, 255), // — · West Ham Blue
  0x1C2C5B: LedRgb(0, 65, 255), // navy→purple · Manchester City
  0x1D1160: LedRgb(153, 0, 255), // purple→blue · Hornets Purple, Suns Purple
  0x1D1B4D: LedRgb(0, 34, 255), // navy→purple · St. Louis City SC
  0x1D2D5C: LedRgb(0, 65, 255), // navy→purple · Blue Jays Navy
  0x1D428A: LedRgb(11, 94, 255), // — · Clippers Blue, Warriors Blue
  0x1D42BA: LedRgb(16, 73, 255), // — · Pistons Blue
  0x1D9053: LedRgb(0, 255, 14), // dark green→teal · Bremen Green
  0x1E1E1E: LedRgb(0, 0, 0), // black (unlit) · Bay Black
  0x1E4D2B: LedRgb(0, 255, 2), // dark green→teal · Colorado State Rams
  0x1E6B52: LedRgb(0, 255, 27), // dark green→teal · UAB Blazers
  0x1E71B8: LedRgb(17, 145, 255), // — · Atalanta Blue
  0x1E9E51: LedRgb(0, 255, 9), // dark green→teal · Gladbach Green
  0x1F1646: LedRgb(0, 34, 255), // navy→purple · Nashville Navy
  0x1F3D7C: LedRgb(0, 82, 255), // navy→purple · Cagliari Blue
  0x201547: LedRgb(153, 0, 255), // purple→blue · San Diego FC
  0x201747: LedRgb(153, 0, 255), // purple→blue · Mercury Purple
  0x203731: LedRgb(0, 255, 31), // dark green→teal · Packers Green
  0x231F20: LedRgb(0, 0, 0), // black (unlit) · Loons Dark, Wolves Black
  0x232D4B: LedRgb(0, 64, 255), // navy→purple · UVA Navy
  0x23326A: LedRgb(0, 54, 255), // navy→purple · New York Red Bulls
  0x236192: LedRgb(15, 149, 255), // — · Avalanche Blue, Wolves Green
  0x239F40: LedRgb(17, 255, 72), // — · Iran Green
  0x241773: LedRgb(153, 0, 255), // purple→blue · Ravens Purple
  0x241F20: LedRgb(0, 0, 0), // black (unlit) · Newcastle Black
  0x2592C6: LedRgb(22, 180, 255), // — · Union Blue
  0x263B80: LedRgb(12, 69, 255), // — · FC Cincinnati
  0x27251F: LedRgb(0, 0, 0), // black (unlit) · Giants Black, Pirates Black
  0x272E61: LedRgb(0, 34, 255), // navy→purple · Atletico Blue
  0x2A4076: LedRgb(0, 74, 255), // navy→purple · FC Dallas
  0x2C5234: LedRgb(0, 255, 54), // — · Storm Green
  0x2D2926: LedRgb(0, 0, 0), // black (unlit) · Houston Dynamo FC
  0x2D68C4: LedRgb(26, 116, 255), // — · UCLA Blue
  0x2F241D: LedRgb(255, 102, 13), // brown→orange · Padres Brown
  0x311D00: LedRgb(255, 102, 13), // brown→orange · Browns Brown
  0x33006F: LedRgb(168, 0, 255), // purple→blue · Rockies Purple
  0x333366: LedRgb(153, 0, 255), // purple→blue · Colorado Rockies
  0x333F42: LedRgb(255, 246, 232), // silver/white→blue tint · Knights Steel
  0x33CCCC: LedRgb(31, 255, 255), // — · SD Turquoise
  0x34302B: LedRgb(255, 246, 232), // silver/white→blue tint · Bucs Pewter
  0x418FDE: LedRgb(42, 148, 255), // — · Dream Sky, Sky Blue
  0x450084: LedRgb(184, 0, 255), // purple→blue · James Madison Dukes
  0x455560: LedRgb(255, 246, 232), // silver/white→blue tint · Toronto FC
  0x461D7C: LedRgb(161, 0, 255), // purple→blue · LSU Purple
  0x482F8B: LedRgb(153, 0, 255), // purple→blue · Fiorentina Purple
  0x492F24: LedRgb(255, 102, 13), // brown→orange · Wyoming Cowboys
  0x4B116F: LedRgb(208, 0, 255), // purple→blue · Northern Iowa Panthers
  0x4B2E83: LedRgb(153, 0, 255), // purple→blue · UW Purple
  0x4B92DB: LedRgb(48, 150, 255), // — · Titans Blue
  0x4D1979: LedRgb(189, 0, 255), // purple→blue · TCU Purple
  0x4E148C: LedRgb(174, 0, 255), // purple→blue · Portland Pilots
  0x4E2A84: LedRgb(153, 0, 255), // purple→blue · Northwestern Purple
  0x4F2683: LedRgb(163, 0, 255), // purple→blue · Vikings Purple
  0x4F2C1D: LedRgb(255, 102, 13), // brown→orange · Bowling Green Falcons
  0x500000: LedRgb(255, 0, 21), // maroon→pink · Aggie Maroon
  0x501214: LedRgb(255, 0, 21), // maroon→pink · Texas State Bobcats
  0x512888: LedRgb(160, 0, 255), // purple→blue · K-State Purple
  0x522D80: LedRgb(165, 0, 255), // purple→blue · Clemson Purple
  0x552582: LedRgb(183, 0, 255), // purple→blue · Lakers
  0x552583: LedRgb(181, 0, 255), // purple→blue · Lakers Purple, Sparks Purple
  0x582C83: LedRgb(180, 0, 255), // purple→blue · Valkyries Purple
  0x592A8A: LedRgb(176, 0, 255), // purple→blue · East Carolina Pirates
  0x5A1414: LedRgb(255, 0, 21), // maroon→pink · Commanders Burgundy
  0x5A2D81: LedRgb(188, 0, 255), // purple→blue · Kings Purple
  0x5B2B82: LedRgb(192, 0, 255), // purple→blue · Orlando Purple
  0x5CBFEB: LedRgb(61, 195, 255), // — · Uruguay Blue
  0x5D76A9: LedRgb(47, 116, 255), // — · Grizzlies Blue
  0x5D9741: LedRgb(102, 255, 29), // — · Sounders Green
  0x5E2B7E: LedRgb(208, 0, 255), // purple→blue · Pride Purple
  0x5E6A71: LedRgb(255, 246, 232), // silver/white→blue tint · Rice Owls, Washington State Cougars
  0x5F259F: LedRgb(178, 17, 255), // purple→blue · Evansville Purple Aces
  0x613318: LedRgb(255, 102, 13), // brown→orange · Valparaiso Beacons, Western Michigan Broncos
  0x630031: LedRgb(255, 0, 21), // maroon→pink · Virginia Tech Hokies
  0x633492: LedRgb(179, 0, 255), // purple→blue · Orlando City SC
  0x63666A: LedRgb(255, 246, 232), // silver/white→blue tint · Georgetown Hoyas, New Mexico Lobos
  0x63727A: LedRgb(255, 246, 232), // silver/white→blue tint · Kings Silver
  0x658D1B: LedRgb(169, 255, 11), // — · Seattle Sounders FC
  0x65B32E: LedRgb(120, 255, 25), // — · Wolfsburg Green
  0x660000: LedRgb(255, 0, 21), // maroon→pink · MSU Maroon, VT Maroon
  0x666666: LedRgb(255, 246, 232), // silver/white→blue tint · OSU Grey
  0x670E36: LedRgb(255, 0, 21), // maroon→pink · Villa Claret
  0x69B3E7: LedRgb(69, 178, 255), // — · Tulane Green Wave
  0x69BE28: LedRgb(123, 255, 23), // — · Seahawks Green
  0x6A0032: LedRgb(255, 0, 21), // maroon→pink · Central Michigan Chippewas
  0x6C1D45: LedRgb(255, 0, 21), // maroon→pink · Burnley Claret
  0x6C2E8D: LedRgb(213, 0, 255), // purple→blue · Racing Purple
  0x6C4023: LedRgb(255, 102, 13), // brown→orange · Western Michigan Broncos
  0x6CABDD: LedRgb(69, 173, 255), // — · City Blue, City Sky Blue
  0x6CACE4: LedRgb(71, 169, 255), // — · NYCFC Blue, Utah Blue
  0x6ECEB2: LedRgb(67, 255, 200), // — · Liberty Seafoam
  0x6F263D: LedRgb(255, 0, 21), // maroon→pink · Avalanche Burgundy
  0x71AFE5: LedRgb(74, 171, 255), // — · Utah Hockey Club
  0x720000: LedRgb(255, 0, 21), // maroon→pink · Southern Illinois Salukis
  0x73000A: LedRgb(255, 0, 21), // maroon→pink · USC Garnet
  0x75AADB: LedRgb(75, 168, 255), // — · Argentina Blue
  0x75B2DD: LedRgb(75, 181, 255), // — · Rhode Island Rams
  0x782F40: LedRgb(255, 0, 21), // maroon→pink · FSU Garnet
  0x78BE21: LedRgb(150, 255, 19), // — · Lynx Green
  0x7A0019: LedRgb(255, 0, 21), // maroon→pink · Minnesota Maroon
  0x7A263A: LedRgb(255, 0, 21), // maroon→pink · West Ham Claret
  0x7B1818: LedRgb(255, 0, 21), // maroon→pink · Salernitana Maroon
  0x7BAFD4: LedRgb(77, 181, 255), // — · Carolina Blue
  0x7C0032: LedRgb(255, 0, 21), // maroon→pink · Loyola Chicago Ramblers
  0x7C2529: LedRgb(255, 0, 21), // maroon→pink · Fordham Rams
  0x7C3625: LedRgb(255, 102, 13), // brown→orange · St. Bonaventure Bonnies
  0x7CCDEF: LedRgb(84, 204, 255), // — · Fire Blue
  0x80000A: LedRgb(255, 0, 21), // maroon→pink · Atlanta Red
  0x80000B: LedRgb(255, 0, 21), // maroon→pink · Atlanta United FC
  0x800029: LedRgb(255, 0, 21), // maroon→pink · Louisiana Monroe Warhawks, Missouri State Bears
  0x840029: LedRgb(255, 0, 21), // maroon→pink · UL Monroe Warhawks
  0x841617: LedRgb(255, 0, 21), // maroon→pink · Oklahoma Crimson
  0x85714D: LedRgb(255, 246, 232), // silver/white→blue tint · Aces Grey, Pelicans Gold
  0x85C1E9: LedRgb(88, 188, 255), // — · Courage Blue
  0x860038: LedRgb(255, 0, 21), // maroon→pink · Cavs Wine
  0x862633: LedRgb(255, 0, 21), // maroon→pink · Rapids Burgundy
  0x866D4B: LedRgb(255, 171, 27), // gold→green-yellow · Vanderbilt Commodores
  0x869397: LedRgb(255, 246, 232), // silver/white→blue tint · Cowboys Silver
  0x87CEEB: LedRgb(90, 207, 255), // — · Tulane Green Wave
  0x87D8F7: LedRgb(93, 210, 255), // — · Lazio Blue
  0x881C1C: LedRgb(255, 0, 21), // maroon→pink · Massachusetts Minutemen, UMass Minutemen
  0x88D4F4: LedRgb(93, 207, 255), // — · San Diego Toreros
  0x8A100B: LedRgb(255, 0, 21), // maroon→pink · Boston College Eagles
  0x8A1538: LedRgb(255, 0, 21), // maroon→pink · Qatar Maroon
  0x8A2432: LedRgb(255, 0, 21), // maroon→pink · Troy Trojans
  0x8AC3EE: LedRgb(93, 185, 255), // — · Celta Blue
  0x8B0000: LedRgb(255, 0, 21), // maroon→pink · Torino Maroon, Venezuela Maroon
  0x8B2131: LedRgb(255, 0, 21), // maroon→pink · Nuggets Red
  0x8B2332: LedRgb(255, 0, 21), // maroon→pink · Troy Trojans
  0x8BB8E8: LedRgb(92, 171, 255), // — · Rapids Blue
  0x8C1515: LedRgb(255, 0, 21), // maroon→pink · Stanford Cardinal
  0x8C1D40: LedRgb(255, 0, 21), // maroon→pink · ASU Maroon
  0x8C2332: LedRgb(255, 0, 21), // maroon→pink · Boston College Eagles
  0x8C2633: LedRgb(255, 0, 21), // maroon→pink · Coyotes Brick
  0x8CD2F4: LedRgb(255, 246, 232), // silver/white→blue tint · Loons Grey
  0x8D734A: LedRgb(255, 172, 29), // gold→green-yellow · Texas State Bobcats
  0x8D817B: LedRgb(255, 246, 232), // silver/white→blue tint · Georgetown Hoyas
  0x8E1F2F: LedRgb(255, 0, 21), // maroon→pink · Roma Maroon
  0x8F8F8C: LedRgb(255, 246, 232), // silver/white→blue tint · Stars Silver
  0x8FBCE6: LedRgb(94, 177, 255), // — · Rays Blue
  0x91B0D5: LedRgb(91, 166, 255), // — · SKC Light Blue
  0x95BFE5: LedRgb(98, 180, 255), // — · Villa Blue
  0x960A2C: LedRgb(255, 0, 21), // maroon→pink · Colorado Rapids
  0x97233F: LedRgb(255, 0, 21), // maroon→pink · Cardinals Red
  0x97999B: LedRgb(255, 246, 232), // silver/white→blue tint · Whitecaps Grey
  0x98002E: LedRgb(255, 0, 21), // maroon→pink · Heat Red
  0x981E32: LedRgb(255, 0, 21), // maroon→pink · Washington State Cougars
  0x990000: LedRgb(255, 0, 21), // maroon→pink · Indiana Crimson, USC Cardinal
  0x99D6EA: LedRgb(102, 217, 255), // — · Burnley Blue
  0x99D9D9: LedRgb(97, 255, 255), // — · Kraken Ice
  0x9BCBEB: LedRgb(104, 194, 255), // — · Minnesota United FC
  0x9CC2EA: LedRgb(104, 178, 255), // — · Colorado Rapids
  0x9D2235: LedRgb(255, 0, 21), // maroon→pink · Arkansas Cardinal
  0x9DC3E6: LedRgb(103, 182, 255), // — · Vancouver Whitecaps FC
  0x9E1B32: LedRgb(255, 0, 21), // maroon→pink · Alabama Crimson
  0x9E7C0C: LedRgb(255, 197, 6), // gold→green-yellow · Ravens Gold
  0x9E7E38: LedRgb(255, 183, 26), // gold→green-yellow · Wake Forest Demon Deacons
  0x9EA2A2: LedRgb(255, 246, 232), // silver/white→blue tint · Wolves Grey
  0x9F792C: LedRgb(255, 178, 21), // gold→green-yellow · Jacksonville Jaguars
  0xA0A0A0: LedRgb(255, 246, 232), // silver/white→blue tint · Memphis Tigers
  0xA1A1A4: LedRgb(255, 246, 232), // silver/white→blue tint · Raptors Silver
  0xA1C1D6: LedRgb(101, 194, 255), // — · Old Dominion Monarchs
  0xA21C26: LedRgb(255, 0, 19), // — · Bologna Red
  0xA29061: LedRgb(255, 195, 38), // gold→green-yellow · Atlanta Gold
  0xA2AAAD: LedRgb(255, 246, 232), // silver/white→blue tint · Avalanche Silver, Jets Silver
  0xA3A9AC: LedRgb(255, 246, 232), // silver/white→blue tint · TCU Horned Frogs
  0xA4A9AD: LedRgb(255, 246, 232), // silver/white→blue tint · Blue Jackets Silver, Raiders Silver
  0xA4AEB5: LedRgb(255, 246, 232), // silver/white→blue tint · Sporting Kansas City
  0xA50044: LedRgb(255, 0, 34), // — · Barca Red
  0xA51E36: LedRgb(255, 0, 34), // — · Cagliari Red
  0xA5A5A5: LedRgb(255, 246, 232), // silver/white→blue tint · Air Force Falcons, Memphis Tigers
  0xA5ACAF: LedRgb(255, 246, 232), // silver/white→blue tint · Eagles Silver, Seahawks Grey
  0xA6192E: LedRgb(255, 0, 34), // — · Wild Red
  0xA71930: LedRgb(255, 0, 34), // — · D-backs Red, Falcons Red
  0xA7A8AA: LedRgb(255, 246, 232), // silver/white→blue tint · TFC Grey
  0xA7C1E2: LedRgb(109, 173, 255), // — · Sporting Kansas City
  0xAA0000: LedRgb(255, 0, 0), // — · 49ers Red
  0xAA151B: LedRgb(255, 0, 10), // — · Spain Red
  0xAB0003: LedRgb(255, 0, 4), // — · Nationals Red
  0xAD0000: LedRgb(255, 0, 0), // — · Louisville Cardinals
  0xAD1831: LedRgb(255, 0, 34), // — · Spirit Red
  0xAE9142: LedRgb(255, 196, 35), // gold→green-yellow · Coastal Carolina Chanticleers
  0xAF1E2D: LedRgb(255, 0, 26), // — · Canadiens Red
  0xB0B7BC: LedRgb(255, 246, 232), // silver/white→blue tint · Lions Silver, Patriots Silver
  0xB10202: LedRgb(255, 0, 0), // — · UNLV Rebels
  0xB19B69: LedRgb(255, 189, 38), // gold→green-yellow · Philadelphia Union
  0xB30838: LedRgb(255, 0, 21), // maroon→pink · RSL Claret
  0xB3995D: LedRgb(255, 189, 38), // gold→green-yellow · 49ers Gold
  0xB3A369: LedRgb(255, 208, 38), // gold→green-yellow · Georgia Tech Yellow Jackets
  0xB48B40: LedRgb(255, 177, 35), // gold→green-yellow · Philadelphia Union
  0xB49759: LedRgb(255, 186, 38), // gold→green-yellow · Union Gold
  0xB4975A: LedRgb(255, 185, 38), // gold→green-yellow · Knights Gold
  0xB5985A: LedRgb(255, 186, 38), // gold→green-yellow · Ducks Orange
  0xB59A57: LedRgb(255, 193, 38), // gold→green-yellow · Akron Zips, Coastal Carolina Chanticleers
  0xB6862C: LedRgb(255, 175, 24), // gold→green-yellow · FIU Panthers
  0xB7A57A: LedRgb(255, 191, 38), // gold→green-yellow · UW Gold
  0xB81137: LedRgb(255, 0, 34), // — · Fire Red, TFC Red
  0xB8C4CA: LedRgb(255, 246, 232), // silver/white→blue tint · Mavs Silver
  0xB9975B: LedRgb(255, 177, 38), // gold→green-yellow · Panthers Gold
  0xBA0021: LedRgb(255, 0, 34), // — · Angels Red
  0xBA0C2F: LedRgb(255, 0, 34), // — · Georgia Red
  0xBA3733: LedRgb(255, 8, 0), // — · Augsburg Red
  0xBA9653: LedRgb(255, 179, 38), // gold→green-yellow · Celtics Gold
  0xBA9B37: LedRgb(255, 202, 31), // gold→green-yellow · UCF Gold
  0xBB0000: LedRgb(255, 0, 0), // — · OSU Scarlet
  0xBC0031: LedRgb(255, 0, 34), // — · Gonzaga Bulldogs
  0xBD3039: LedRgb(255, 0, 16), // — · Red Sox Red
  0xBD9B60: LedRgb(255, 176, 38), // gold→green-yellow · Kansas City Royals
  0xBF0A30: LedRgb(255, 0, 34), // — · USA Red
  0xBF0D3E: LedRgb(255, 0, 34), // — · FC Dallas, South Alabama Jaguars
  0xBF5700: LedRgb(255, 116, 0), // — · Texas Orange
  0xBFC0BF: LedRgb(255, 246, 232), // silver/white→blue tint · Panthers Silver
  0xC0111F: LedRgb(255, 0, 20), // — · Rangers Red
  0xC09A5B: LedRgb(255, 176, 38), // gold→green-yellow · Royals Gold
  0xC0C0C0: LedRgb(255, 246, 232), // silver/white→blue tint · Air Force Falcons, Nevada Wolf Pack
  0xC10230: LedRgb(255, 0, 34), // — · Real Salt Lake
  0xC1272D: LedRgb(255, 0, 10), // — · Morocco Red
  0xC1D32F: LedRgb(230, 255, 29), // — · Atlanta Hawks
  0xC2912C: LedRgb(255, 180, 26), // gold→green-yellow · Ottawa Senators
  0xC2A14D: LedRgb(255, 194, 38), // gold→green-yellow · Texas State Bobcats
  0xC3142D: LedRgb(255, 0, 34), // — · Miami (OH) RedHawks
  0xC39E6D: LedRgb(255, 176, 38), // gold→green-yellow · LAFC Gold
  0xC4032B: LedRgb(255, 0, 34), // — · Aces Red
  0xC4122E: LedRgb(255, 0, 34), // — · Leverkusen Red, Palace Blue
  0xC41230: LedRgb(255, 0, 34), // — · Ajax Red, Benfica Red
  0xC4161C: LedRgb(255, 0, 9), // — · Genoa Red
  0xC41E3A: LedRgb(255, 0, 34), // — · Cardinals Red
  0xC4CED4: LedRgb(255, 246, 232), // silver/white→blue tint · Mariners Silver, Rockets Silver
  0xC4D600: LedRgb(234, 255, 0), // — · Wings Sky
  0xC5050C: LedRgb(255, 0, 9), // — · Wisconsin Red
  0xC52032: LedRgb(255, 0, 28), // — · Senators Red
  0xC5B783: LedRgb(255, 209, 38), // gold→green-yellow · Thorns Gold
  0xC6011F: LedRgb(255, 0, 34), // — · Reds Red
  0xC60C30: LedRgb(255, 0, 34), // — · Bills Red, Denmark Red
  0xC6363C: LedRgb(255, 0, 11), // — · Serbia Red
  0xC69214: LedRgb(255, 184, 12), // gold→green-yellow · Senators Gold
  0xC8102E: LedRgb(255, 0, 34), // — · Capitals Red, Clippers Red
  0xC83803: LedRgb(255, 70, 2), // — · Bears Orange
  0xC8A774: LedRgb(255, 176, 38), // gold→green-yellow · Tulsa Golden Hurricane
  0xC8C372: LedRgb(255, 226, 38), // gold→green-yellow · Colorado State Rams
  0xC99700: LedRgb(255, 192, 0), // gold→green-yellow · ND Gold
  0xCB0019: LedRgb(255, 0, 31), // — · Illinois State Redbirds
  0xCB3524: LedRgb(255, 26, 0), // — · Atletico Red
  0xCBB677: LedRgb(255, 201, 38), // gold→green-yellow · James Madison Dukes
  0xCC0000: LedRgb(255, 0, 0), // — · Hurricanes Red, NC State Red
  0xCC0033: LedRgb(255, 0, 34), // — · Arizona Red, Rutgers Scarlet
  0xCC0035: LedRgb(255, 0, 34), // — · SMU Mustangs
  0xCC092F: LedRgb(255, 0, 34), // — · Arkansas State Red Wolves
  0xCC3433: LedRgb(255, 2, 0), // — · Cubs Red
  0xCD2534: LedRgb(255, 0, 23), // — · Girona Red
  0xCD2E3A: LedRgb(255, 0, 19), // — · Korea Red
  0xCDB87D: LedRgb(255, 198, 38), // gold→green-yellow · Boston College Eagles
  0xCE0037: LedRgb(255, 0, 34), // — · New England Revolution
  0xCE0E2D: LedRgb(255, 0, 34), // — · Revs Red
  0xCE1126: LedRgb(255, 0, 28), // — · Blue Jackets Red, Cameroon Red
  0xCE1141: LedRgb(255, 0, 34), // — · Braves Red, Bulls Red
  0xCE181E: LedRgb(255, 0, 8), // — · Louisiana Ragin' Cajuns
  0xCEB888: LedRgb(255, 187, 38), // gold→green-yellow · FSU Gold
  0xCF081F: LedRgb(255, 0, 29), // — · England Red
  0xCF0A2C: LedRgb(255, 0, 34), // — · Blackhawks Red
  0xCFAE70: LedRgb(255, 180, 38), // gold→green-yellow · Vandy Gold
  0xCFB87C: LedRgb(255, 195, 38), // gold→green-yellow · CU Gold
  0xCFB991: LedRgb(255, 178, 38), // gold→green-yellow · Purdue Gold
  0xCFC493: LedRgb(255, 240, 215), // silver/white→blue tint · South Florida Bulls
  0xD22630: LedRgb(255, 0, 15), // — · Roughnecks Red, Stallions Red
  0xD2B569: LedRgb(255, 195, 38), // gold→green-yellow · Army Black Knights
  0xD31145: LedRgb(255, 0, 34), // — · Twins Red
  0xD3BC8D: LedRgb(255, 184, 38), // gold→green-yellow · Saints Gold
  0xD44500: LedRgb(255, 83, 0), // — · Syracuse Orange
  0xD4A843: LedRgb(255, 189, 38), // gold→green-yellow · Akron Zips, UL Monroe Warhawks
  0xD4AF37: LedRgb(255, 203, 34), // gold→green-yellow · George Washington Colonials
  0xD50A0A: LedRgb(255, 0, 0), // — · Bucs Red
  0xD52B1E: LedRgb(255, 18, 0), // — · Bolivia Red, CITY Red
  0xD64309: LedRgb(255, 76, 6), // — · Boise State Broncos
  0xD69A00: LedRgb(255, 184, 0), // gold→green-yellow · Timbers Gold
  0xD6A62C: LedRgb(255, 191, 28), // gold→green-yellow · Portland Timbers
  0xD7141A: LedRgb(255, 0, 8), // — · Czech Red
  0xD7263D: LedRgb(255, 0, 33), // — · Current Red
  0xD7282F: LedRgb(255, 0, 10), // — · Lecce Red
  0xD7A22A: LedRgb(255, 185, 26), // gold→green-yellow · Jaguars Gold
  0xD91023: LedRgb(255, 0, 24), // — · Peru Red
  0xD91A2A: LedRgb(255, 0, 21), // — · Osasuna Red
  0xDA0000: LedRgb(255, 0, 0), // — · Iran Red
  0xDA121A: LedRgb(255, 0, 10), // — · Panama Red, Paraguay Red
  0xDA291C: LedRgb(255, 17, 0), // — · Bournemouth Red, Sevilla Red
  0xDAA520: LedRgb(255, 188, 20), // gold→green-yellow · PSG Gold
  0xDAA900: LedRgb(255, 198, 0), // gold→green-yellow · Valkyries Gold
  0xDB0032: LedRgb(255, 0, 34), // — · Fresno State Bulldogs
  0xDC052D: LedRgb(255, 0, 34), // — · Bayern Red
  0xDC143C: LedRgb(255, 0, 34), // — · Poland Red
  0xDC4405: LedRgb(255, 77, 3), // — · Oregon State Beavers
  0xDD0000: LedRgb(255, 0, 0), // — · Forest Red, Germany Red
  0xDD0741: LedRgb(255, 0, 34), // — · Leipzig Red
  0xDD550C: LedRgb(255, 94, 8), // — · Auburn Orange
  0xDF4601: LedRgb(255, 80, 1), // — · Orioles Orange
  0xE00122: LedRgb(255, 0, 34), // — · UC Red
  0xE03A3E: LedRgb(255, 0, 6), // — · Blazers Red, Boston Red
  0xE1000F: LedRgb(255, 0, 17), // — · Frankfurt Red
  0xE2001A: LedRgb(255, 0, 29), // — · Heidenheim Red
  0xE20E17: LedRgb(255, 0, 11), // — · SL Benfica
  0xE2D6B5: LedRgb(255, 240, 215), // silver/white→blue tint · Coyotes Sand
  0xE3000B: LedRgb(255, 0, 12), // — · Freiburg Red
  0xE30613: LedRgb(255, 0, 15), // — · Brentford Red
  0xE30A17: LedRgb(255, 0, 15), // — · Turkey Red
  0xE31837: LedRgb(255, 0, 34), // — · Battlehawks Red, Brahmas Red
  0xE31937: LedRgb(255, 0, 34), // — · Toronto FC
  0xE32219: LedRgb(255, 11, 0), // — · Stuttgart Red
  0xE32221: LedRgb(255, 1, 0), // — · Leverkusen Red
  0xE3D4AD: LedRgb(255, 240, 215), // silver/white→blue tint · D-backs Sand
  0xE4002B: LedRgb(255, 0, 34), // — · DePaul Blue Demons, New York Yankees
  0xE4002C: LedRgb(255, 0, 34), // — · New York Yankees
  0xE41C38: LedRgb(255, 0, 34), // — · Nebraska Scarlet
  0xE50022: LedRgb(255, 0, 34), // — · Guardians Red
  0xE53027: LedRgb(255, 12, 0), // — · Rayo Red
  0xE56020: LedRgb(255, 91, 13), // — · Mercury Orange, Suns Orange
  0xE57200: LedRgb(255, 127, 0), // — · Sharks Orange
  0xE5A823: LedRgb(255, 182, 23), // gold→green-yellow · San Jose State Spartans
  0xE6007E: LedRgb(255, 0, 140), // — · San Diego FC
  0xE70013: LedRgb(255, 0, 21), // — · Tunisia Red
  0xE8000D: LedRgb(255, 0, 21), // maroon→pink · Kansas Crimson
  0xE81828: LedRgb(255, 0, 20), // — · Phillies Red
  0xE81F3E: LedRgb(255, 0, 34), // — · FCD Red
  0xE8291C: LedRgb(255, 16, 0), // — · Blue Jays Red
  0xE84A27: LedRgb(255, 34, 0), // — · Illinois Orange
  0xE87722: LedRgb(255, 117, 13), // — · Auburn Tigers, Virginia Tech Hokies
  0xE8D3A2: LedRgb(255, 190, 38), // gold→green-yellow · Washington Huskies
  0xE9072B: LedRgb(255, 0, 34), // — · Kraken Red
  0xEA7200: LedRgb(255, 124, 0), // — · San Jose Sharks
  0xEAAA00: LedRgb(255, 185, 0), // gold→green-yellow · WVU Gold
  0xEB1923: LedRgb(255, 0, 12), // — · Union Red
  0xEB6E1F: LedRgb(255, 107, 13), // — · Astros Orange
  0xECE83A: LedRgb(255, 226, 38), // gold→green-yellow · Nashville Gold
  0xED174C: LedRgb(255, 0, 34), // — · 76ers Red
  0xED1B2F: LedRgb(255, 0, 24), // — · Defenders Red
  0xED1C24: LedRgb(255, 0, 10), // — · Koln Red, Mainz Red
  0xED1E36: LedRgb(255, 0, 30), // — · Red Bulls Red
  0xED2939: LedRgb(255, 0, 21), // — · Austria Red, Belgium Red
  0xEDBC00: LedRgb(255, 202, 0), // gold→green-yellow · Barca Gold
  0xEE0000: LedRgb(255, 0, 0), // — · Monza Red
  0xEE1119: LedRgb(255, 0, 9), // — · Granada Red
  0xEE1C25: LedRgb(255, 0, 11), // — · Almeria Red
  0xEE2523: LedRgb(255, 3, 0), // — · Bilbao Red
  0xEE2737: LedRgb(255, 0, 21), // — · Sheffield Red
  0xEE3B3B: LedRgb(255, 0, 0), // — · St. Louis City SC
  0xEE8707: LedRgb(255, 163, 5), // gold→green-yellow · Valencia Orange
  0xEECB9E: LedRgb(255, 176, 38), // gold→green-yellow · Wild Wheat
  0xEEE1C6: LedRgb(255, 240, 215), // silver/white→blue tint · Bucks Cream
  0xEF0107: LedRgb(255, 0, 6), // — · Arsenal Red
  0xEF2B2D: LedRgb(255, 0, 3), // — · Norway Red
  0xEF3340: LedRgb(255, 0, 18), // — · Marlins Red
  0xEF3B24: LedRgb(255, 29, 0), // — · Thunder Orange
  0xEF3E42: LedRgb(255, 0, 6), // — · DC Red, Red Stars Red
  0xEF6020: LedRgb(255, 88, 13), // — · Oklahoma City Thunder
  0xEF6100: LedRgb(255, 103, 0), // — · Oklahoma City Thunder
  0xEFB21E: LedRgb(255, 186, 20), // gold→green-yellow · Athletics Gold
  0xEFD19F: LedRgb(255, 240, 215), // silver/white→blue tint · Giants Cream
  0xF05123: LedRgb(255, 67, 13), // — · Sun Orange
  0xF05323: LedRgb(255, 69, 13), // — · FC Cincinnati
  0xF0AB00: LedRgb(255, 182, 0), // gold→green-yellow · Kent State Golden Flashes
  0xF0B323: LedRgb(255, 186, 24), // gold→green-yellow · Kent State Golden Flashes
  0xF0BC42: LedRgb(255, 190, 38), // gold→green-yellow · Roma Orange
  0xF15524: LedRgb(255, 71, 13), // — · NYCFC Orange
  0xF15A24: LedRgb(255, 77, 13), // — · Liberty Orange
  0xF1AA00: LedRgb(255, 180, 0), // gold→green-yellow · RSL Gold
  0xF1B82D: LedRgb(255, 190, 31), // gold→green-yellow · Mizzou Gold
  0xF1BE48: LedRgb(255, 190, 38), // gold→green-yellow · Flames Gold, ISU Gold
  0xF1BF00: LedRgb(255, 202, 0), // gold→green-yellow · Spain Yellow
  0xF1C500: LedRgb(255, 208, 0), // gold→green-yellow · Toledo Rockets
  0xF2A900: LedRgb(255, 178, 0), // gold→green-yellow · UCLA Gold
  0xF47321: LedRgb(255, 107, 13), // — · Miami Orange
  0xF47A38: LedRgb(255, 98, 13), // — · Ducks Gold
  0xF47D30: LedRgb(255, 108, 13), // — · Islanders Orange
  0xF4C300: LedRgb(255, 204, 0), // gold→green-yellow · Gotham Gold
  0xF56600: LedRgb(255, 106, 0), // — · Clemson Orange
  0xF58025: LedRgb(255, 119, 13), // — · Sam Houston Bearkats
  0xF58220: LedRgb(255, 124, 13), // — · Dolphins Orange
  0xF58426: LedRgb(255, 123, 13), // — · Knicks Orange
  0xF5B112: LedRgb(255, 182, 12), // gold→green-yellow · Grizzlies Gold
  0xF5B5C8: LedRgb(255, 124, 163), // — · Miami Pink
  0xF5D130: LedRgb(255, 214, 33), // gold→green-yellow · Rays Gold
  0xF5F1E7: LedRgb(255, 240, 215), // silver/white→blue tint · Indiana Cream, Nebraska Cream
  0xF68712: LedRgb(255, 137, 12), // — · Dynamo Orange
  0xF74902: LedRgb(255, 75, 1), // — · Flyers Orange
  0xF76900: LedRgb(255, 108, 0), // — · Syracuse Orange
  0xF78F1E: LedRgb(255, 139, 13), // — · Luton Orange
  0xF7B5CD: LedRgb(255, 124, 172), // — · Inter Miami CF
  0xF84C1E: LedRgb(255, 64, 13), // — · UVA Orange
  0xF9A01B: LedRgb(255, 168, 19), // gold→green-yellow · Heat Yellow, Jazz Yellow
  0xFA4616: LedRgb(255, 64, 13), // — · Florida Orange, Tigers Orange
  0xFB090B: LedRgb(255, 0, 2), // — · Milan Red
  0xFB4F14: LedRgb(255, 75, 13), // — · Bengals Orange, Broncos Orange
  0xFC4C02: LedRgb(255, 76, 1), // — · Miami Dolphins
  0xFCB514: LedRgb(255, 181, 14), // gold→green-yellow · Blues Gold, Penguins Gold
  0xFCD116: LedRgb(255, 210, 15), // gold→green-yellow · Colombia Yellow, Mali Yellow
  0xFD5A1E: LedRgb(255, 78, 13), // — · Giants Orange
  0xFDB515: LedRgb(255, 180, 15), // gold→green-yellow · California Golden Bears
  0xFDB827: LedRgb(255, 182, 27), // gold→green-yellow · Pirates Gold
  0xFDB913: LedRgb(255, 185, 13), // gold→green-yellow · Galaxy Gold, Wolves Gold
  0xFDB927: LedRgb(255, 183, 27), // gold→green-yellow · Lakers Gold, Sparks Gold
  0xFDBA21: LedRgb(255, 184, 23), // gold→green-yellow · Pacers Gold
  0xFDBB30: LedRgb(255, 184, 33), // gold→green-yellow · Indiana Pacers
  0xFDD023: LedRgb(255, 207, 24), // gold→green-yellow · LSU Gold
  0xFDDA24: LedRgb(255, 218, 25), // gold→green-yellow · Belgium Yellow
  0xFDE100: LedRgb(255, 221, 0), // gold→green-yellow · BVB Yellow
  0xFDEF42: LedRgb(255, 226, 38), // gold→green-yellow · Senegal Yellow
  0xFDF9D8: LedRgb(255, 240, 215), // silver/white→blue tint · Oklahoma Cream
  0xFE5000: LedRgb(255, 80, 0), // — · FCC Orange
  0xFEBE10: LedRgb(255, 189, 11), // gold→green-yellow · Madrid Gold
  0xFEC524: LedRgb(255, 195, 25), // gold→green-yellow · Nuggets Gold
  0xFECC00: LedRgb(255, 205, 0), // gold→green-yellow · Sweden Yellow
  0xFED100: LedRgb(255, 210, 0), // gold→green-yellow · Jamaica Gold
  0xFEDB00: LedRgb(255, 220, 0), // gold→green-yellow · Cardinals Yellow
  0xFEDD00: LedRgb(255, 221, 0), // gold→green-yellow · Columbus Crew
  0xFEDE00: LedRgb(255, 221, 0), // gold→green-yellow · Red Bulls Yellow
  0xFEE123: LedRgb(255, 224, 24), // gold→green-yellow · Oregon Yellow
  0xFEE536: LedRgb(255, 226, 38), // gold→green-yellow · Cadiz Yellow
  0xFEF200: LedRgb(255, 221, 0), // gold→green-yellow · Crew Gold
  0xFF0000: LedRgb(255, 0, 0), // — · Canada Red, Croatia Red
  0xFF3C00: LedRgb(255, 60, 0), // — · Browns Orange
  0xFF4C00: LedRgb(255, 76, 0), // — · Oilers Orange
  0xFF5733: LedRgb(255, 34, 0), // — · Wave Red
  0xFF5910: LedRgb(255, 86, 11), // — · Mets Orange
  0xFF5C5C: LedRgb(255, 0, 0), // — · Angel City Sol Rose
  0xFF5F00: LedRgb(255, 95, 0), // — · Sam Houston Bearkats
  0xFF6600: LedRgb(255, 102, 0), // — · Netherlands Orange, OSU Orange
  0xFF6B00: LedRgb(255, 107, 0), // — · Dash Orange
  0xFF7300: LedRgb(255, 115, 0), // — · Bowling Green Falcons
  0xFF7900: LedRgb(255, 121, 0), // — · Bucs Orange
  0xFF8200: LedRgb(255, 130, 0), // — · Ivory Coast Orange, Tennessee Orange
  0xFFA300: LedRgb(255, 163, 0), // gold→green-yellow · Rams Yellow
  0xFFAB00: LedRgb(255, 171, 0), // gold→green-yellow · Southern Miss Golden Eagles
  0xFFAE00: LedRgb(255, 174, 0), // gold→green-yellow · Western Michigan Broncos
  0xFFB612: LedRgb(255, 180, 13), // gold→green-yellow · Commanders Gold, Packers Gold
  0xFFB81C: LedRgb(255, 181, 20), // gold→green-yellow · Bafana Gold, Baylor Gold
  0xFFBD00: LedRgb(255, 189, 0), // gold→green-yellow · Kennesaw State Owls
  0xFFC20E: LedRgb(255, 193, 10), // gold→green-yellow · Chargers Gold
  0xFFC300: LedRgb(255, 195, 0), // gold→green-yellow · Southern Miss Golden Eagles
  0xFFC425: LedRgb(255, 193, 26), // gold→green-yellow · Padres Gold
  0xFFC52F: LedRgb(255, 193, 33), // gold→green-yellow · Brewers Gold
  0xFFC627: LedRgb(255, 195, 27), // gold→green-yellow · ASU Gold
  0xFFC62F: LedRgb(255, 194, 33), // gold→green-yellow · Vikings Gold
  0xFFC72C: LedRgb(255, 195, 31), // gold→green-yellow · Storm Gold, USC Gold
  0xFFC82E: LedRgb(255, 196, 32), // gold→green-yellow · Central Michigan Chippewas
  0xFFC904: LedRgb(255, 201, 3), // gold→green-yellow · UCF Knights
  0xFFCB05: LedRgb(255, 203, 4), // gold→green-yellow · Michigan Maize
  0xFFCC00: LedRgb(255, 204, 0), // gold→green-yellow · Socceroos Gold
  0xFFCC33: LedRgb(255, 200, 36), // gold→green-yellow · Minnesota Gold
  0xFFCD00: LedRgb(255, 205, 0), // gold→green-yellow · Fever Gold, Iowa Gold
  0xFFCE00: LedRgb(255, 206, 0), // gold→green-yellow · Germany Gold
  0xFFD100: LedRgb(255, 209, 0), // gold→green-yellow · Ecuador Yellow, Racing Yellow
  0xFFD200: LedRgb(255, 210, 0), // gold→green-yellow · Boston College Eagles, Kennesaw State Owls
  0xFFD500: LedRgb(255, 213, 0), // gold→green-yellow · Ukraine Yellow
  0xFFD520: LedRgb(255, 211, 22), // gold→green-yellow · Maryland Gold
  0xFFD700: LedRgb(255, 215, 0), // gold→green-yellow · Bolivia Yellow, Ghana Gold
  0xFFDF00: LedRgb(255, 221, 0), // gold→green-yellow · Brazil Yellow
  0xFFE400: LedRgb(255, 221, 0), // gold→green-yellow · Las Palmas Yellow
  0xFFE667: LedRgb(255, 219, 38), // gold→green-yellow · Villarreal Yellow
  0xFFED00: LedRgb(255, 221, 0), // gold→green-yellow · Frosinone Yellow
  0xFFFFFF: LedRgb(255, 240, 215), // silver/white→blue tint · 76ers White, Aggie White
};
