// Glitter (fx 87) sparkles bright white again on a two-colour design, as it
// did up to build 123.
//
// WLED's Glitter sparkles in col[2], and in bright white when col[2] is black.
// normalizeWledPayload (the LAN and relay chokepoint, and the background
// worker's build-time normaliser) pads a missing third slot with black. Build
// 124 (2c43e550) replaced that black with the design's second colour, so a
// two-colour Glitter sparkled in its second colour. The owner wants the
// build-123 look back: the pad stays black for Glitter like every other
// effect. This file pins the build-123 wire for the bench Haunted House
// colours and the cases that must not move.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/game_day/game_day_apply.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

const _purple = [128, 0, 128, 0];
const _orange = [255, 140, 0, 0];
const _green = [0, 255, 0, 0];
const _black = [0, 0, 0, 0];

Map<String, dynamic> _seg(Map<String, dynamic> payload) =>
    ((payload['seg'] as List).single as Map).cast<String, dynamic>();

Map<String, dynamic> _wire(Map<String, dynamic> seg) =>
    _seg(normalizeWledPayload({'on': true, 'seg': [seg]}));

void main() {
  test('bench Haunted House, two colours: the build-123 wire exactly', () {
    final wire = normalizeWledPayload({
      'on': true,
      'bri': 255,
      'seg': [
        {
          'fx': 87,
          'sx': 40,
          'ix': 128,
          'pal': 5,
          'col': [_purple, _orange],
        }
      ],
    });
    expect(
      wire,
      {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': 87,
            'sx': 40,
            'ix': 128,
            'pal': 5,
            'grp': 1,
            'spc': 0,
            'o2': false,
            'bri': 255,
            'col': [_purple, _orange, _black],
            'frz': false,
          }
        ],
      },
      reason: 'col[2] is the black pad, so WLED sparkles bright white; every '
          'other field is the build-123 wire',
    );
  });

  test('a stated black third slot stays black', () {
    expect(_wire({'fx': 87, 'col': [_purple, _orange, _black]})['col'],
        [_purple, _orange, _black]);
  });

  test('every team Game Day Glitter: the team LED colours, then black', () async {
    const oneChannel = [
      DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
    ];
    final created = DateTime.utc(2026, 11, 21);
    expect(kTeamColors, isNotEmpty);
    for (final entry in kTeamColors.entries) {
      final team = entry.value;
      late Map<String, dynamic> sent;
      await applyGameDayConfigToDevice(
        applyPayloadWithLabel: (payload, {required labelHint}) async {
          sent = payload;
          return true;
        },
        config: GameDayAutopilotConfig(
          teamSlug: entry.key,
          teamName: team.teamName,
          espnTeamId: team.espnTeamId,
          sport: team.sport,
          primaryColorValue: team.primary.toARGB32(),
          secondaryColorValue: team.secondary.toARGB32(),
          effectId: 87,
          speed: 40,
          intensity: 128,
          brightness: 255,
          createdAt: created,
          updatedAt: created,
        ),
        participatingChannels: const [0],
        deviceChannels: oneChannel,
      );
      expect(
        _seg(normalizeWledPayload(sent))['col'],
        [team.primaryLedRgb.toRgbw(), team.secondaryLedRgb.toRgbw(), _black],
        reason: '${entry.key}: Glitter on the team colours sparkles white',
      );
    }
  });

  test('an explicit non-black third colour is kept: it is the sparkle colour',
      () {
    expect(_wire({'fx': 87, 'col': [_purple, _orange, _green]})['col'],
        [_purple, _orange, _green]);
    expect(_wire({'fx': 87, 'col': [_purple, _black, _orange]})['col'],
        [_purple, _black, _orange]);
  });

  test('Solid Glitter (103) and Palette (65): payloads unchanged', () {
    Map<String, dynamic> wire(int fx) => normalizeWledPayload({
          'on': true,
          'bri': 255,
          'seg': [
            {
              'fx': fx,
              'sx': 40,
              'ix': 128,
              'pal': 5,
              'col': [_purple, _orange],
            }
          ],
        });
    expect(wire(103), {
      'on': true,
      'bri': 255,
      'seg': [
        {
          'fx': 103,
          'sx': 40,
          'ix': 128,
          'pal': 5,
          'col': [_purple, _orange, _black],
          'grp': 1,
          'spc': 0,
          'bri': 255,
          'frz': false,
        }
      ],
    });
    expect(wire(65), {
      'on': true,
      'bri': 255,
      'seg': [
        {
          'fx': 65,
          'sx': 40,
          'ix': 128,
          'pal': 4,
          'col': [_purple, _orange, _black],
          'grp': 1,
          'spc': 0,
          'c1': 0,
          'o1': false,
          'o2': false,
          'o3': false,
          'bri': 255,
          'frz': false,
        }
      ],
    }, reason: 'the palette guard still turns pal 5 into 4 for Palette');
  });

  test('an API-command preset body (o:true) is never touched', () {
    final body = {
      'o': true,
      'seg': [
        {
          'fx': 87,
          'col': [_purple, _orange, _black],
        }
      ],
    };
    expect(normalizeWledPayload(body), body);
  });
}
