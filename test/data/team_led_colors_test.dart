// The team LED colour table — lib/data/team_led_colors.dart.
//
// Brand hex is what a team prints and a screen shows; sent straight to a
// controller it reads wrong (Green Bay's #203731 has B ≈ G and lights teal).
// Every team colour in every table has a calibrated LED value, and the server
// planner's mirror (functions/src/teamLedColors.ts) is identical.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/constants/commercial/geo_team_regions.dart';
import 'package:nexgen_command/data/ncaa_conferences.dart';
import 'package:nexgen_command/data/team_color_database.dart';
import 'package:nexgen_command/data/team_led_colors.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';

void main() {
  group('Packers green goes first', () {
    test('#203731 → more green, much less blue, full value', () {
      final led = teamLedRgb(0x203731);
      expect(led.g, 255, reason: 'full value: bri owns brightness');
      // Brand B/G is 49/55 ≈ 0.89 — the teal. The LED colour is green.
      expect(led.b / led.g, lessThan(0.15));
      expect(led.r, lessThanOrEqualTo(led.b));
      expect(led, const LedRgb(0, 255, 31));
    });

    test('kTeamColors Packers: UI keeps the brand hex, payloads get LED', () {
      final packers = kTeamColors['nfl_packers']!;
      expect(packers.primary.toARGB32(), 0xFF203731, reason: 'brand for UI');
      expect(packers.primaryLedRgb, const LedRgb(0, 255, 31));
      expect(packers.secondary.toARGB32(), 0xFFFFB612);
      expect(packers.secondaryLedRgb, const LedRgb(255, 180, 13));
    });
  });

  group('lookup contract', () {
    test('alpha is ignored — a stored ARGB int resolves like its RGB', () {
      expect(teamLedRgb(0xFF203731), teamLedRgb(0x203731));
      expect(hasTeamLedRgb(0xFF203731), isTrue);
    });

    test('a colour that is not a team colour passes through unchanged', () {
      expect(hasTeamLedRgb(0x123457), isFalse);
      expect(teamLedRgb(0xFF123457), const LedRgb(0x12, 0x34, 0x57));
    });

    test('toRgbw sends W = 0 (a team colour never lights the white die)', () {
      for (final led in kTeamLedRgb.values) {
        expect(led.toRgbw(), [led.r, led.g, led.b, 0]);
      }
    });
  });

  group('every entry', () {
    test('is full value (bri owns brightness) — except black, which is off',
        () {
      kTeamLedRgb.forEach((brand, led) {
        final max = [led.r, led.g, led.b].reduce((a, b) => a > b ? a : b);
        if (led == const LedRgb(0, 0, 0)) return;
        expect(max, 255, reason: '0x${brand.toRadixString(16)} → $led');
      });
    });

    test('is a valid 8-bit triple keyed by a 24-bit brand colour', () {
      kTeamLedRgb.forEach((brand, led) {
        expect(brand, inInclusiveRange(0, 0xFFFFFF));
        for (final c in [led.r, led.g, led.b]) {
          expect(c, inInclusiveRange(0, 255));
        }
      });
    });
  });

  group('problem classes', () {
    test('dark green → teal: every dark blue-green lights green', () {
      // Packers, Jets, Celtics, Bucks, A's, Wild, Stars.
      for (final hex in [
        0x203731, 0x125740, 0x007A33, 0x00471B, 0x003831, 0x154734, 0x006847
      ]) {
        final led = teamLedRgb(hex);
        expect(led.g, 255, reason: hex.toRadixString(16));
        expect(led.b, lessThan(64), reason: hex.toRadixString(16));
      }
    });

    test('navy → purple: navy carries no red', () {
      // Patriots, Titans, Giants, Bears, Wizards, Kraken.
      for (final hex in [0x002244, 0x0C2340, 0x0B2265, 0x0B162A, 0x002B5C,
          0x001628]) {
        final led = teamLedRgb(hex);
        expect(led.r, 0, reason: hex.toRadixString(16));
        expect(led.b, 255, reason: hex.toRadixString(16));
      }
    });

    test('maroon → pink: maroon is a deep red, blue stripped', () {
      // Commanders, Avalanche, Cavaliers wine, Cardinals.
      for (final hex in [0x5A1414, 0x6F263D, 0x860038, 0x97233F]) {
        final led = teamLedRgb(hex);
        expect(led.r, 255, reason: hex.toRadixString(16));
        expect(led.g, 0, reason: hex.toRadixString(16));
        expect(led.b, lessThan(40), reason: hex.toRadixString(16));
      }
    });

    test('silver/white → blue tint: whites are warmed (b < g < r)', () {
      for (final hex in [0xFFFFFF, 0xA5ACAF, 0xC4CED4]) {
        final led = teamLedRgb(hex);
        expect(led.r, 255, reason: hex.toRadixString(16));
        expect(led.b, lessThan(led.g), reason: hex.toRadixString(16));
      }
    });

    test('purple stays purple — the old heuristic sent Lakers/Vikings as '
        'pure blue', () {
      for (final hex in [0x552583, 0x4F2683, 0x241773]) {
        final led = teamLedRgb(hex);
        expect(led.r, greaterThanOrEqualTo(128), reason: hex.toRadixString(16));
        expect(led.b, 255, reason: hex.toRadixString(16));
        expect(led.g, 0, reason: hex.toRadixString(16));
      }
    });

    test('brown → orange is flagged, and Browns orange stays distinct', () {
      final brown = teamLedRgb(0x311D00);
      final orange = teamLedRgb(0xFF3C00);
      expect(brown, isNot(orange));
      expect(brown.g, greaterThan(orange.g), reason: 'brown reads amber');
    });

    test('gold holds its hue and drops the blue', () {
      final gold = teamLedRgb(0xFFB612);
      expect(gold.r, 255);
      expect(gold.g, inInclusiveRange(150, 210));
      expect(gold.b, lessThan(gold.g ~/ 4));
    });
  });

  group('coverage: every team colour in every table has an LED value', () {
    void expectCovered(String where, int argb) {
      expect(hasTeamLedRgb(argb), isTrue,
          reason: '$where #${(argb & 0xFFFFFF).toRadixString(16)} has no '
              'entry in kTeamLedRgb — add one (lib/data/team_led_colors.dart) '
              'and mirror it in functions/src/teamLedColors.ts');
    }

    test('kTeamColors (Game Day, alerts, celebrations)', () {
      expect(kTeamColors.length, greaterThan(400));
      kTeamColors.forEach((slug, t) {
        expectCovered('$slug primary', t.primary.toARGB32());
        expectCovered('$slug secondary', t.secondary.toARGB32());
      });
    });

    test('TeamColorDatabase (Explore library, Lumina AI)', () {
      for (final team in TeamColorDatabase.allTeams) {
        for (final c in team.colors) {
          expectCovered('${team.id} ${c.name}', (c.r << 16) | (c.g << 8) | c.b);
        }
      }
    });

    test('NcaaConferences (Explore NCAA)', () {
      final nodes = NcaaConferences.getAllSchoolNodes();
      expect(nodes, isNotEmpty);
      for (final node in nodes) {
        for (final c in node.themeColors ?? const []) {
          expectCovered(node.id, c.toARGB32());
        }
      }
    });

    test('commercial geo team table', () {
      for (final region in kGeoTeamRegions) {
        for (final t in region.teams) {
          expectCovered('${t.teamName} primary', int.parse(t.primaryColor, radix: 16));
          expectCovered('${t.teamName} secondary', int.parse(t.secondaryColor, radix: 16));
        }
      }
    });
  });

  group('server mirror (functions/src/teamLedColors.ts)', () {
    test('is entry-for-entry identical to the Dart table', () {
      final ts = File('functions/src/teamLedColors.ts').readAsStringSync();
      final rx = RegExp(r'\[0x([0-9A-Fa-f]{6}), \[(\d+), (\d+), (\d+)\]\]');
      final mirror = <int, LedRgb>{
        for (final m in rx.allMatches(ts))
          int.parse(m.group(1)!, radix: 16): LedRgb(int.parse(m.group(2)!),
              int.parse(m.group(3)!), int.parse(m.group(4)!)),
      };
      expect(mirror.length, kTeamLedRgb.length,
          reason: 'entry count drifted — edit both files together');
      kTeamLedRgb.forEach((brand, led) {
        expect(mirror[brand], led,
            reason: '0x${brand.toRadixString(16)} differs on the server');
      });
    });
  });
}
