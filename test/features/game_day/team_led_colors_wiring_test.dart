// Controller-bound team colours are LED colours; UI team colours are brand.
//
// Every path that turns a team colour into a controller payload, pinned with
// the Packers (the owner's bug: brand #203731 lit reads teal). Each test also
// pins that the value the UI paints is still the brand hex — the fix must not
// leak into cards, dots or pickers.
//
// Paths not here, and why:
//   • calendar lease presets — calendar_entry_lease_manager_test.dart
//   • TeamDesignCatalog / selectDesign guard — base_design_team_colors_guard_test.dart
//   • server planner — functions/test/unit/teamLedColors.test.js

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/data/ncaa_conferences.dart';
import 'package:nexgen_command/data/team_color_database.dart';
import 'package:nexgen_command/data/team_led_colors.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_background_worker.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart';
import 'package:nexgen_command/features/autopilot/game_day_background_persistence.dart';
import 'package:nexgen_command/features/autopilot/team_design_catalog.dart';
import 'package:nexgen_command/features/game_day/game_day_apply.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/services/path1_complement_theme.dart';
import 'package:nexgen_command/features/neighborhood/services/path1_game_day_snapshot.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/game_schedule_service.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/sports_library_builder.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/autopilot_generation_service.dart';
import 'package:nexgen_command/services/calendar_event_service.dart';

const int _brandGreen = 0xFF203731; // Packers green, brand
const int _brandGold = 0xFFFFB612; // Packers gold, brand
const List<int> _ledGreen = [0, 255, 31, 0];
const List<int> _ledGold = [255, 180, 13, 0];
const List<int> _brandGreenRgbw = [32, 55, 49, 0];

GameDayAutopilotConfig _packers({
  AutopilotDesignMode designMode = AutopilotDesignMode.autoSelected,
}) {
  final now = DateTime.utc(2026, 9, 24);
  return GameDayAutopilotConfig(
    teamSlug: 'nfl_packers',
    teamName: 'Green Bay Packers',
    espnTeamId: '9',
    sport: SportType.nfl,
    primaryColorValue: _brandGreen,
    secondaryColorValue: _brandGold,
    designMode: designMode,
    createdAt: now,
    updatedAt: now,
  );
}

/// Every `col` array in a payload's design segs (exclusion segs have none).
List<List> _cols(Map<String, dynamic> payload) => [
      for (final s in (payload['seg'] as List).cast<Map>())
        if (s['col'] != null) (s['col'] as List),
    ];

void main() {
  group('Game Day config (Firestore game_day_autopilot doc)', () {
    test('brand for UI, LED for payloads — no migration: the stored int is '
        'translated at read', () {
      final c = _packers();
      expect(c.primaryColor, const Color(_brandGreen), reason: 'UI');
      expect(c.secondaryColor, const Color(_brandGold), reason: 'UI');
      expect(c.primaryLedRgb.toRgbw(), _ledGreen);
      expect(c.secondaryLedRgb.toRgbw(), _ledGold);
    });

    test('Light it up now / Activate / ephemeral go-live '
        '(applyGameDayConfigToDevice) send LED', () async {
      late Map<String, dynamic> sent;
      await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (p, {required labelHint}) async {
          sent = p;
          return true;
        },
        config: _packers(),
        participatingChannels: const [0],
        deviceChannels: const [
          DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 120, gpioPin: 2),
        ],
      );
      for (final col in _cols(sent)) {
        expect(col[0], _ledGreen);
        expect(col[1], _ledGold);
        expect(col, isNot(contains(_brandGreenRgbw)));
      }
    });

    test('foreground autopilot selectDesign sends LED on every branch', () {
      final svc = GameDayAutopilotService(
        espnApi: EspnApiService(),
        scheduleService: GameScheduleService(),
      );
      addTearDown(svc.dispose);
      for (final styles in const [
        <String>[],
        ['static'],
        ['chase'],
        ['twinkle'],
      ]) {
        final d = svc.selectDesign(_packers(), preferredStyles: styles);
        expect(d.colors.first, _ledGreen.take(3).toList(), reason: '$styles');
        for (final col in _cols(d.wledPayload)) {
          expect(col.first, _ledGreen, reason: '$styles');
        }
      }
    });

    test('rotation catalog (base design, background isolate) sends LED', () {
      final catalog = TeamDesignCatalog.build(
        teamName: 'Green Bay Packers',
        primary: const Color(_brandGreen),
        secondary: const Color(_brandGold),
      );
      for (final d in catalog) {
        final wire = {
          for (final col in _cols(d.wledPayload))
            for (final c in col.take(2)) (c as List).join(','),
        };
        expect(wire, {_ledGreen.join(','), _ledGold.join(',')},
            reason: d.name);
      }
    });

    test('background celebration sends LED', () {
      final payload =
          GameDayAutopilotBackgroundWorker.buildCelebrationPayloadForTest(
        BackgroundGameDayAutopilotConfig.fromConfig(_packers()),
      );
      for (final col in _cols(payload)) {
        expect(col[0], _ledGreen);
        expect(col[1], _ledGold);
      }
    });
  });

  group('kTeamColors consumers', () {
    test('score celebrations lead with the LED primary on every stage', () {
      final team = kTeamColors['nfl_packers']!;
      expect(team.primary, const Color(_brandGreen), reason: 'UI keeps brand');
      for (final type in AlertEventType.values) {
        for (final step in AlertTriggerService.buildAnimationSteps(type, team)) {
          for (final col in _cols(step.payload)) {
            expect(col.first, _ledGreen, reason: type.name);
          }
        }
      }
    });

    test('teamLedRgbw is the LED colour, not the brand', () {
      expect(AlertTriggerService.teamLedRgbw(const Color(_brandGreen)),
          _ledGreen);
    });
  });

  group('Explore library / Game Day celebration picker (the tuner)', () {
    test('team nodes are flagged and keep brand swatches', () {
      final packers = SportsLibraryBuilder.getTeamPaletteNodes()
          .firstWhere((n) => n.name.contains('Packers'));
      expect(packers.teamColors, isTrue);
      expect(packers.themeColors!.first.toARGB32(), _brandGreen,
          reason: 'the card paints brand');
      final ncaa = NcaaConferences.getAllSchoolNodes();
      expect(ncaa.every((n) => n.teamColors), isTrue);
    });

    test('a team palette goes on the wire as LED; any other palette ships '
        'as picked', () {
      const argb = [_brandGreen, _brandGold];
      expect(selectorPaletteCols(argb, teamColors: true),
          [_ledGreen, _ledGold]);
      expect(selectorPaletteCols(argb, teamColors: false),
          [_brandGreenRgbw, [255, 182, 18, 0]]);
    });
  });

  group('Lumina AI (TeamColorDatabase.ledOptimizedRgb)', () {
    test('Packers: calibrated LED, brand kept for UI', () {
      final packers =
          TeamColorDatabase.allTeams.firstWhere((t) => t.id == 'packers');
      expect(packers.colors.first.toColor(), const Color(_brandGreen));
      expect(packers.ledOptimizedRgb.first, _ledGreen);
    });

    test('Lakers purple is no longer sent as pure blue', () {
      final lakers =
          TeamColorDatabase.allTeams.firstWhere((t) => t.id == 'lakers');
      final purple = lakers.ledOptimizedRgb.first;
      expect(purple[0], greaterThanOrEqualTo(128), reason: 'red kept');
      expect(purple[2], 255);
    });
  });

  group('Neighborhood complement mode (Path 2 Game Day theme)', () {
    test('swatches brand, homes sent LED', () {
      final theme = path1ToComplementTheme(
          Path1GameDaySnapshot.fromConfig(_packers()));
      expect(theme.colorObjects.first, const Color(_brandGreen));
      expect(theme.sendColors, [0x00FF1F, 0xFFB40D]);
      final overrides = theme.buildMemberColorOverrides([
        NeighborhoodMember(
          oderId: 'a',
          displayName: 'A',
          positionIndex: 0,
          lastSeen: DateTime.utc(2026, 9, 24),
        ),
      ]);
      expect(overrides['a'], [0x00FF1F]);
    });
  });

  group('Autopilot calendar fallback / AI prompt', () {
    test('a game sends the team LED colours; other events ship as picked', () {
      final game = CalendarEvent(
        name: 'Packers vs Bears',
        date: DateTime(2026, 10, 4),
        type: CalendarEventType.sportGame,
        suggestedColors: const [Color(_brandGreen), Color(_brandGold)],
        teamName: 'Packers',
      );
      expect(AutopilotGenerationService.sendRgbForTest(game), [
        _ledGreen.take(3).toList(),
        _ledGold.take(3).toList(),
      ]);
      final party = CalendarEvent(
        name: 'Party',
        date: DateTime(2026, 10, 4),
        type: CalendarEventType.custom,
        suggestedColors: const [Color(_brandGreen)],
      );
      expect(AutopilotGenerationService.sendRgbForTest(party), [
        _brandGreenRgbw.take(3).toList(),
      ]);
    });
  });

  test('LedRgb.rgb round-trips the packed int the sync models store', () {
    expect(teamLedRgb(_brandGreen).rgb, 0x00FF1F);
  });
}
