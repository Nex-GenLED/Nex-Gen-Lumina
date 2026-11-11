// Build 124 — the Game Day default looks the owner chose on the spare
// controller (2026-11-10, WLED 0.15.4, colour gamma 2.8, the Chiefs pair
// 255,0,34 / 255,168,0, third slot black, pal 0):
//   moving — Chase 2 (fx 37, sx 60, ix 128)
//   still  — Solid Pattern (fx 83, sx 8, ix 8)
// Running Dual (fx 52, sx 160, ix 128), the old default, read orange.
//
// Pins: the config's default and read fallback (and that a stored doc is NOT
// migrated), catalog design 1 and the Stripe, and the style mapping.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart';
import 'package:nexgen_command/features/autopilot/team_design_catalog.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/game_schedule_service.dart';

const _chiefsRed = 0xFFE31837; // brand
const _chiefsGold = 0xFFFFB81C; // brand
const _ledRed = [255, 0, 34, 0];
const _ledGold = [255, 168, 0, 0];

GameDayAutopilotConfig _chiefs() {
  final t = DateTime.utc(2026, 11, 10);
  return GameDayAutopilotConfig(
    teamSlug: 'nfl_chiefs',
    teamName: 'Kansas City Chiefs',
    espnTeamId: '12',
    sport: SportType.nfl,
    primaryColorValue: _chiefsRed,
    secondaryColorValue: _chiefsGold,
    createdAt: t,
    updatedAt: t,
  );
}

Map<String, dynamic> _doc({Map<String, dynamic> extra = const {}}) {
  final d = Map<String, dynamic>.from(_chiefs().toFirestore())
    ..remove('effect_id')
    ..remove('speed')
    ..remove('intensity');
  return d..addAll(extra);
}

Map<String, dynamic> _seg(Map<String, dynamic> payload) =>
    ((payload['seg'] as List).single as Map).cast<String, dynamic>();

void main() {
  group('GameDayAutopilotConfig — the default look', () {
    test('a new config is Chase 2 at sx 60, ix 128', () {
      final c = _chiefs();
      expect(c.effectId, 37);
      expect(c.speed, 60);
      expect(c.intensity, 128);
      expect(c.designLabel, 'Kansas City Chiefs Chase 2');
    });

    test('a doc with no effect fields reads as the default look', () {
      final c = GameDayAutopilotConfig.fromFirestore(_doc());
      expect([c.effectId, c.speed, c.intensity], [37, 60, 128]);
    });

    test('a doc that stores fx 52 is NOT migrated — it keeps its look', () {
      final full = GameDayAutopilotConfig.fromFirestore(
          _doc(extra: {'effect_id': 52, 'speed': 160, 'intensity': 128}));
      expect([full.effectId, full.speed, full.intensity], [52, 160, 128]);

      // Partial doc: the stored effect keeps the PRE-124 fallbacks for the
      // fields it lacks, so the armed team still fires what it fired before.
      final partial =
          GameDayAutopilotConfig.fromFirestore(_doc(extra: {'effect_id': 52}));
      expect([partial.effectId, partial.speed, partial.intensity],
          [52, 160, 128]);
      expect(partial.designLabel, 'Kansas City Chiefs Running');
    });
  });

  group('TeamDesignCatalog — design 1 and the Stripe', () {
    final catalog = TeamDesignCatalog.build(
      teamName: 'Chiefs',
      primary: const Color(_chiefsRed),
      secondary: const Color(_chiefsGold),
    );

    test('design 1 is the default look in the team LED colours, pal 0', () {
      final d = catalog.first;
      expect([d.effectId, d.speed, d.intensity], [37, 60, 128]);
      final s = _seg(d.wledPayload);
      expect([s['fx'], s['sx'], s['ix'], s['pal'], s['grp'], s['spc']],
          [37, 60, 128, 0, 1, 0]);
      expect(s['col'], [_ledRed, _ledGold]);
    });

    test('the Stripe is Solid Pattern 9 / 9 — both colours, not the primary '
        'alone', () {
      final d = catalog.last;
      expect(d.name, 'Chiefs Stripe');
      expect([d.effectId, d.speed, d.intensity, d.colorGroupSize],
          [83, 8, 8, 1]);
      final s = _seg(d.wledPayload);
      expect([s['fx'], s['sx'], s['ix'], s['pal'], s['grp'], s['spc']],
          [83, 8, 8, 0, 1, 0],
          reason: 'pal 0: under pal 5 Solid Pattern takes its colours by '
              'position along the run');
      expect(s['col'], [_ledRed, _ledGold]);
    });

    test('the rotation is 37, 0, 28, 2, 12, 83', () {
      expect(catalog.map((d) => d.effectId).toList(), [37, 0, 28, 2, 12, 83]);
    });
  });

  group('GameDayAutopilotService.selectDesign — the style mapping', () {
    late GameDayAutopilotService svc;
    setUp(() {
      svc = GameDayAutopilotService(
        espnApi: EspnApiService(),
        scheduleService: GameScheduleService(),
      );
    });
    tearDown(() => svc.dispose());

    test('motion → Chase 2 (fx 37, sx 60, ix 128), pal 0', () {
      final d = svc.selectDesign(_chiefs(), preferredStyles: const ['animated']);
      expect([d.effectId, d.speed, d.intensity], [37, 60, 128]);
      expect(d.designName, 'Chase 2 in Kansas City Chiefs Colors');
      final s = _seg(d.wledPayload);
      expect([s['fx'], s['sx'], s['ix'], s['pal']], [37, 60, 128, 0]);
      expect(s['col'], [_ledRed, _ledGold]);
    });

    test('static → Solid Pattern (fx 83, sx 8, ix 8), pal 0', () {
      final d = svc.selectDesign(_chiefs(), preferredStyles: const ['static']);
      expect([d.effectId, d.speed, d.intensity], [83, 8, 8]);
      expect(d.designName, 'Solid Pattern in Kansas City Chiefs Colors');
      final s = _seg(d.wledPayload);
      expect([s['fx'], s['sx'], s['ix'], s['pal']], [83, 8, 8, 0]);
    });

    test('dynamic is unchanged: Fade at its catalog pace, ix 180', () {
      final d = svc.selectDesign(_chiefs(), preferredStyles: const ['twinkle']);
      expect([d.effectId, d.speed, d.intensity],
          [kBaseDesignFadeEffectId, kBaseDesignFadeSpeed, 180]);
    });
  });
}
