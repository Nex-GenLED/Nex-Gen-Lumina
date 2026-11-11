// Build 124, item 3 — what Light Up Now and the background worker put on the
// wire for the third colour slot and the segment brightness.
//
// Light Up Now (`applyGameDayConfigToDevice`) builds TWO colour slots and no
// segment `bri`. That is safe only because every apply crosses the LAN
// chokepoint — `WledService.applyJson`, and the relay's
// `CloudRelayRepository.applyJson`, both run `normalizeWledPayload` — which
// pads `col` to three slots with black and states the segment's own
// brightness (255). A stale non-black third slot is what turns Chase (fx 28)
// into a white-led block and can change any effect that reads `col[2]`
// (bench 2026-11-10, step 7c). These tests pin that the wire shape carries
// both, for the build-124 default look.
//
// The background worker reaches no chokepoint at apply time (it POSTs to
// applySyncPattern from an isolate), so it normalises at build time; the last
// group pins that too.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_background_worker.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_background_persistence.dart';
import 'package:nexgen_command/features/game_day/game_day_apply.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

const _chiefsRed = 0xFFE31837; // brand
const _chiefsGold = 0xFFFFB81C; // brand
const _ledRed = [255, 0, 34, 0]; // what the controller gets (team LED table)
const _ledGold = [255, 168, 0, 0];
const _black = [0, 0, 0, 0];

GameDayAutopilotConfig _chiefs() {
  final created = DateTime.utc(2026, 11, 10);
  // No effect / speed / intensity given: the build-124 default look.
  return GameDayAutopilotConfig(
    teamSlug: 'nfl_chiefs',
    teamName: 'Kansas City Chiefs',
    espnTeamId: '12',
    sport: SportType.nfl,
    primaryColorValue: _chiefsRed,
    secondaryColorValue: _chiefsGold,
    createdAt: created,
    updatedAt: created,
  );
}

final _twoChannels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
];

Future<Map<String, dynamic>> _lightUpNowBuilderPayload() async {
  late Map<String, dynamic> captured;
  final ok = await applyGameDayConfigToDevice(
    applyPayloadWithLabel: (payload, {required labelHint}) async {
      captured = payload;
      return true;
    },
    config: _chiefs(),
    participatingChannels: const [0, 1],
    deviceChannels: _twoChannels,
  );
  expect(ok, isTrue);
  return captured;
}

List<Map<String, dynamic>> _segs(Map<String, dynamic> p) =>
    [for (final s in p['seg'] as List) Map<String, dynamic>.from(s as Map)];

void main() {
  group('Light Up Now — the builder states two slots, the chokepoint the rest',
      () {
    test('builder: the default look, pal 0, two LED colour slots, no seg bri',
        () async {
      final segs = _segs(await _lightUpNowBuilderPayload());
      expect(segs, hasLength(2));
      for (final s in segs) {
        expect(s['fx'], 37, reason: 'Chase 2 — the build-124 default');
        expect(s['sx'], 60);
        expect(s['ix'], 128);
        expect(s['pal'], 0);
        expect(s['col'], [_ledRed, _ledGold],
            reason: 'two slots, LED colours, never the brand hex');
        expect(s.containsKey('bri'), isFalse,
            reason: 'the builder leaves segment brightness to the chokepoint');
      }
    });

    test(
        'on the wire (normalizeWledPayload, the LAN and relay chokepoint): '
        'third slot black, segment brightness 255, look unchanged', () async {
      final wire = normalizeWledPayload(await _lightUpNowBuilderPayload());
      for (final s in _segs(wire)) {
        expect(s['col'], [_ledRed, _ledGold, _black],
            reason: 'col padded to three slots; the third is black, so a '
                'stale white third slot on the controller is overwritten');
        expect(s['bri'], 255, reason: 'the segment states its own brightness');
        expect(s['fx'], 37);
        expect(s['sx'], 60);
        expect(s['ix'], 128);
        expect(s['pal'], 0, reason: 'a stated pal is never refilled');
      }
      expect(wire['bri'], 200, reason: 'master brightness from the config');
    });
  });

  group('background worker — normalised at build time', () {
    BackgroundGameDayAutopilotConfig workerConfig(String variety) =>
        BackgroundGameDayAutopilotConfig(
          teamSlug: 'nfl_chiefs',
          teamName: 'Chiefs',
          espnTeamId: '12',
          sport: 'nfl',
          primaryColorValue: _chiefsRed,
          secondaryColorValue: _chiefsGold,
          enabled: true,
          designMode: 'fallback',
          effectId: 37,
          speed: 60,
          intensity: 128,
          brightness: 200,
          skipDayGames: false,
          designVariety: variety,
          scoreCelebrationEnabled: true,
        );

    test('the fixed design (catalog design 1) carries three slots and seg bri',
        () {
      final p = GameDayAutopilotBackgroundWorker.buildBasePayloadForTest(
          workerConfig('fixed'));
      for (final s in _segs(p)) {
        expect(s['fx'], 37);
        expect(s['sx'], 60);
        expect(s['ix'], 128);
        expect(s['pal'], 0);
        expect(s['col'], [_ledRed, _ledGold, _black]);
        expect(s['bri'], 255);
      }
    });
  });
}
