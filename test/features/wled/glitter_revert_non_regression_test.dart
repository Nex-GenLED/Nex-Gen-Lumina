// Non-regression for the Glitter white-sparkle revert (fx 87 only).
//
// Reverting build 124's Glitter sparkle colour (2c43e550) must change nothing
// but Glitter. This file pins, as a short SHA-256 of the exact JSON the
// chokepoint emits (key order included, so it is the wire byte for byte):
//
//   - normalizeWledPayload for EVERY effect id 0..255 except 87, over a set
//     of segment shapes (no colour, one to three colours, a black second or
//     third slot, RGB triplets, a white-die colour, two segments, legacy
//     grp/spc keys, a per-pixel `i`);
//   - payloads that state no effect at all, and an API-command preset body;
//   - the team palette colours: the LED team table (lib/data/team_led_colors.dart,
//     commit 1c32e8e0), each team's LED primary and secondary, and every team
//     sent through the Game Day builder (applyGameDayConfigToDevice) and the
//     chokepoint on Solid, Breathe, Chase, Chase 2, Palette, Solid Pattern and
//     Solid Glitter.
//
// The digests were recorded on the commit before the revert, so this file
// passing before AND after it is the evidence that those payloads are
// byte-identical. Glitter itself is pinned in glitter_white_sparkle_test.dart.
//
// If a later, deliberate change moves one of these payloads, re-record only
// the entries it explains and say why in the commit.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/data/team_led_colors.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/game_day/game_day_apply.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

const _glitter = 87;

const _c1 = [128, 0, 128, 0];
const _c2 = [255, 140, 0, 0];
const _c3 = [0, 255, 0, 0];
const _black = [0, 0, 0, 0];

/// The effects every team is sent on through the Game Day builder.
const kTeamEffectsPinned = [0, 2, 28, 37, 65, 83, 103];

List<Map<String, dynamic>> glitterRevertShapesFor(int fx) => [
      {
        'on': true,
        'seg': [
          {'fx': fx}
        ],
      },
      {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'fx': fx,
            'col': [_c1],
          }
        ],
      },
      {
        'on': true,
        'seg': [
          {
            'fx': fx,
            'col': [_c1, _c2],
          }
        ],
      },
      {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': fx,
            'sx': 40,
            'ix': 128,
            'pal': 5,
            'col': [_c1, _c2],
          }
        ],
      },
      {
        'on': true,
        'seg': [
          {
            'fx': fx,
            'pal': 0,
            'col': [_c1, _c2, _black],
          }
        ],
      },
      {
        'on': true,
        'seg': [
          {
            'fx': fx,
            'col': [_c1, _c2, _c3],
          }
        ],
      },
      {
        'on': true,
        'seg': [
          {
            'fx': fx,
            'col': [_c1, _black],
          }
        ],
      },
      {
        'on': true,
        'seg': [
          {
            'fx': fx,
            'col': [
              [255, 0, 0],
              [0, 0, 255],
            ],
          }
        ],
      },
      {
        'on': true,
        'seg': [
          {
            'fx': fx,
            'col': [
              [0, 0, 0, 255],
              _c2,
            ],
          }
        ],
      },
      {
        'on': true,
        'seg': [
          {
            'id': 0,
            'fx': fx,
            'col': [_c1, _c2],
          },
          {
            'id': 1,
            'fx': fx,
            'sx': 200,
            'col': [_c2, _c1],
          },
        ],
      },
      {
        'on': true,
        'seg': [
          {
            'fx': fx,
            'gp': 2,
            'sp': 1,
            'col': [_c1, _c2],
          }
        ],
      },
      {
        'on': true,
        'seg': [
          {
            'fx': fx,
            'col': [_c1, _c2],
            'i': [
              0,
              [255, 0, 0],
            ],
          }
        ],
      },
    ];

List<Map<String, dynamic>> _noEffectShapes() => [
      {
        'on': true,
        'seg': [
          {
            'col': [_c1, _c2],
          }
        ],
      },
      {
        'seg': [
          {'sx': 200},
        ],
      },
      {
        'seg': [
          {
            'id': 0,
            'col': [_c1],
          }
        ],
      },
      {
        'on': true,
        'seg': [
          {
            'i': [
              0,
              [255, 0, 0],
              1,
              [0, 255, 0],
            ],
          }
        ],
      },
      {'on': false},
      {'on': true, 'seg': <Object>[]},
      {
        'o': true,
        'seg': [
          {
            'fx': _glitter,
            'col': [_c1, _c2, _black],
          }
        ],
      },
    ];

String _digest(String canonical) =>
    sha256.convert(utf8.encode(canonical)).toString().substring(0, 16);

String _wire(Map<String, dynamic> payload) =>
    jsonEncode(normalizeWledPayload(payload));

Future<String> glitterRevertTeamGameDayWire(
    String slug, TeamColors team, int fx) async {
  const oneChannel = [
    DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  ];
  final created = DateTime.utc(2026, 11, 21);
  late Map<String, dynamic> sent;
  await applyGameDayConfigToDevice(
    applyPayloadWithLabel: (payload, {required labelHint}) async {
      sent = payload;
      return true;
    },
    config: GameDayAutopilotConfig(
      teamSlug: slug,
      teamName: team.teamName,
      espnTeamId: team.espnTeamId,
      sport: team.sport,
      primaryColorValue: team.primary.toARGB32(),
      secondaryColorValue: team.secondary.toARGB32(),
      effectId: fx,
      speed: 128,
      intensity: 128,
      brightness: 200,
      createdAt: created,
      updatedAt: created,
    ),
    participatingChannels: const [0],
    deviceChannels: oneChannel,
  );
  return _wire(sent);
}

/// Every pinned case, label → the canonical text that is digested.
Future<Map<String, String>> glitterRevertCanonicals() async {
  final out = <String, String>{};
  for (var fx = 0; fx <= 255; fx++) {
    if (fx == _glitter) continue;
    out['fx $fx'] = glitterRevertShapesFor(fx).map(_wire).join('\n');
  }
  out['no effect'] = _noEffectShapes().map(_wire).join('\n');
  out['team LED table'] = kTeamLedRgb.entries
      .map((e) => '${e.key.toRadixString(16)} ${jsonEncode(e.value.toRgbw())}')
      .join('\n');
  out['team LED pairs'] = kTeamColors.entries
      .map((e) => '${e.key} ${jsonEncode(e.value.primaryLedRgb.toRgbw())} '
          '${jsonEncode(e.value.secondaryLedRgb.toRgbw())}')
      .join('\n');
  for (final fx in kTeamEffectsPinned) {
    final lines = <String>[];
    for (final e in kTeamColors.entries) {
      lines.add(
          '${e.key} ${await glitterRevertTeamGameDayWire(e.key, e.value, fx)}');
    }
    out['team Game Day fx $fx'] = lines.join('\n');
  }
  return out;
}

/// Recorded on 1985fb3d (before the revert).
const Map<String, String> kGlitterRevertPinned = {
  'fx 0': 'b75ea71905a18cb3',
  'fx 1': '11ed9de22f8e63ce',
  'fx 2': 'ec2cc8474535ea1f',
  'fx 3': 'c6df2939392982a3',
  'fx 4': '1087155106205d37',
  'fx 5': 'ed5e0fe51573de2d',
  'fx 6': 'aeb2dd7cf887f967',
  'fx 7': 'a028fe504825c556',
  'fx 8': 'c944d9185962b1ae',
  'fx 9': '6a0a142dc15f0635',
  'fx 10': 'b8e2918836e0de15',
  'fx 11': '097b1aedbdd71031',
  'fx 12': '0d02dc52519f5440',
  'fx 13': '9bc260807346b80f',
  'fx 14': 'a82d36916497620a',
  'fx 15': 'c04ae0c496af3153',
  'fx 16': 'ffd4fe8d2f805aa6',
  'fx 17': '36d088ad47e4777b',
  'fx 18': 'ddb263c753f4f4c4',
  'fx 19': '264d0e5ae91f68f1',
  'fx 20': 'ffddb1bf7607edbb',
  'fx 21': 'eacf47b72108d9b3',
  'fx 22': '210ee62a2ed6debe',
  'fx 23': '917d7672c9e2020d',
  'fx 24': '6115b42313b30286',
  'fx 25': '4d3a4c14c2cf989f',
  'fx 26': '36b9697173bc7fae',
  'fx 27': '7c1f1c24ab357e10',
  'fx 28': '3ca1778f2932d0f2',
  'fx 29': '3b576576d7ef7468',
  'fx 30': '884336e758b2a4be',
  'fx 31': '2a405d7b6ff0bd75',
  'fx 32': 'a07f9e40889172c7',
  'fx 33': '6c594065a83b4112',
  'fx 34': '83284ddee659644b',
  'fx 35': 'e76f5835fb0bfe42',
  'fx 36': '0f245290a55c3480',
  'fx 37': 'a004c35b83e2b02f',
  'fx 38': 'c89de19ed9174be1',
  'fx 39': 'ab4d90d35cbaeb8f',
  'fx 40': 'ef57978af040040b',
  'fx 41': '38fec1a93f5568e3',
  'fx 42': '0bcadafc46d3b397',
  'fx 43': 'bc5aca3581da3741',
  'fx 44': '029e66dadffe9093',
  'fx 45': 'c7b9d00386d6ea69',
  'fx 46': '006436f7342871d4',
  'fx 47': 'cc46a2d0bb35a948',
  'fx 48': 'd1f47cdf94fa455b',
  'fx 49': 'ae177538e0826a04',
  'fx 50': '1b7e481ceb37b885',
  'fx 51': '29536512c3f6afac',
  'fx 52': '756e290829e671b8',
  'fx 53': 'e4c40d77a9dca8fc',
  'fx 54': 'a4d2e7a830bd34f9',
  'fx 55': '74057e55b51cc181',
  'fx 56': 'ef86b4d6e98b37e7',
  'fx 57': '6bfeeb342e910d6e',
  'fx 58': 'd4b3806c910c2544',
  'fx 59': 'f9b8ae53df7a4843',
  'fx 60': '80d6394ee8acb535',
  'fx 61': 'c14afafb77f50477',
  'fx 62': '3e56d220b6ac9fce',
  'fx 63': '0687d329014b05b6',
  'fx 64': 'dcea7b04d98240e1',
  'fx 65': '3ef30c404ace3c1a',
  'fx 66': 'abf9a1ab22f7fc9e',
  'fx 67': '6ae80bc04e419295',
  'fx 68': '93876c4b82ad4eb2',
  'fx 69': '3f662e13a771a1d6',
  'fx 70': '149fd25bd4b92a38',
  'fx 71': 'ad830cc62bbe704f',
  'fx 72': '9b202b5afbc3f71f',
  'fx 73': '338b660ab60bf4dc',
  'fx 74': '948e10eb3a5bd82d',
  'fx 75': '1245ad1ea62e914d',
  'fx 76': 'ad74348bf0e845e9',
  'fx 77': 'dd5bae33533cd8d0',
  'fx 78': '23fcff04e5826d81',
  'fx 79': '8792d489c0867de8',
  'fx 80': '150e8658f37616c4',
  'fx 81': '528045e35fcdb737',
  'fx 82': 'ea01d3f9cd8a1536',
  'fx 83': 'a2dcb50e2b510514',
  'fx 84': '90ed5b43fd2f0495',
  'fx 85': '0e8c94aacfbb102f',
  'fx 86': 'cd5c4e070bb8aad2',
  'fx 88': '966f5c4f9ffaab3e',
  'fx 89': '16e33a11831b50e0',
  'fx 90': '2ed27532da1dfda1',
  'fx 91': '3a0b91d8201e4377',
  'fx 92': '84bf04d561508c0d',
  'fx 93': 'eb4e050ab49d88a0',
  'fx 94': '1933b928b749b2f8',
  'fx 95': '8a96fb4ba8c8ea33',
  'fx 96': '1d1fb669e8bc0d5c',
  'fx 97': '5c0e68414da77950',
  'fx 98': 'e602b5b7f180f34d',
  'fx 99': 'b18445ee161a099b',
  'fx 100': '43ec2c5dd9b9dc52',
  'fx 101': '7f0dce85942c201d',
  'fx 102': 'afe6c8a027841a1e',
  'fx 103': '021d6d86f44e870c',
  'fx 104': 'e67f9d319594fd24',
  'fx 105': 'c3daa91b69e8f998',
  'fx 106': '6b891c43663a9221',
  'fx 107': '355f0a2cfd55cbe8',
  'fx 108': 'e90b197d5754366c',
  'fx 109': '4fb3f641f749dc03',
  'fx 110': '2e3c34346231fb38',
  'fx 111': '0f04374bd295afeb',
  'fx 112': '1a8aad0fee7e7fcc',
  'fx 113': '436612204f1113d0',
  'fx 114': 'ad5485f863f72423',
  'fx 115': 'f8484981911246ea',
  'fx 116': '19be684d6a6f0124',
  'fx 117': 'e06f1c168fb63899',
  'fx 118': 'c8c5f79c158bdc9f',
  'fx 119': 'd88099adbd888e18',
  'fx 120': 'ce8971ef247b5f73',
  'fx 121': 'bfc7d633ca8424c5',
  'fx 122': '98ca69d7ae90ec5b',
  'fx 123': '8017e773620a58c9',
  'fx 124': 'aa12d4b3bccb9af2',
  'fx 125': '32f455e4d986bea3',
  'fx 126': '6d03154c35614d87',
  'fx 127': 'a866dff26af0871c',
  'fx 128': 'e99990cfcb178228',
  'fx 129': 'eafe3e7b6ad8b534',
  'fx 130': '64bca7adf251ef48',
  'fx 131': '4a30c9b2a42d3e3e',
  'fx 132': 'e787180078dc4735',
  'fx 133': '85d401789b361e2d',
  'fx 134': '9649b2d34d40d26c',
  'fx 135': 'ec705b6d1dd181d9',
  'fx 136': '49fc3ca4fe8a6409',
  'fx 137': '91be419e87c95276',
  'fx 138': '91a44a90e4120b4e',
  'fx 139': '8549663f81d1c88d',
  'fx 140': '5b4d84df1069a272',
  'fx 141': '87375717236a1e8d',
  'fx 142': '6d253c430d6b6859',
  'fx 143': '4e52405f0679bbd1',
  'fx 144': 'acfc432441f0eafa',
  'fx 145': 'c3e9fe037fa77ae1',
  'fx 146': '8b6ae8c40499b4bf',
  'fx 147': 'baf6d8d0d4ca71b6',
  'fx 148': 'c650923b2b7cbf46',
  'fx 149': '359d3359ba958d2b',
  'fx 150': '7d8bda7174b146d5',
  'fx 151': '03fee070e8c13444',
  'fx 152': 'd0cba7e49620ece0',
  'fx 153': '1b54fa3e20a3c442',
  'fx 154': 'ba0e274852ceda9c',
  'fx 155': '35ebe6159ddc84d0',
  'fx 156': '3213d1785839dff6',
  'fx 157': '2504867d72f3c216',
  'fx 158': 'c493890d02697e17',
  'fx 159': '0b4bc29680caa7e5',
  'fx 160': 'c6ad9bd1e1955dc6',
  'fx 161': '9285827363d88111',
  'fx 162': '5c94f15840b2e9a8',
  'fx 163': '10746c4fadf25e33',
  'fx 164': '4d40778af6fa4987',
  'fx 165': '0d380b3e4470cc95',
  'fx 166': 'df85d9eac516e224',
  'fx 167': '6d2a054b85b2d49f',
  'fx 168': '6692b27fafac17e4',
  'fx 169': '1091de80f8660e63',
  'fx 170': '5b5700cd5e15d6b3',
  'fx 171': '7bfcf23b500d0c79',
  'fx 172': '6ff9399b5bb4b40f',
  'fx 173': '3b30dec820d8e9d8',
  'fx 174': '7a341df850d1020c',
  'fx 175': 'f32c987494f471a3',
  'fx 176': 'ebea7604cad708d6',
  'fx 177': 'a05319222e08c4b6',
  'fx 178': '2116cf20d0215bc8',
  'fx 179': '5f25880689373eb9',
  'fx 180': 'cce01f154bf97b16',
  'fx 181': 'eac2a8a0be667d13',
  'fx 182': 'b652dca1bdf7cea1',
  'fx 183': '8bf5e77b40a2f671',
  'fx 184': 'dc1e2434beb30c32',
  'fx 185': '99008d036b76ec2f',
  'fx 186': 'dc53e524608cc013',
  'fx 187': '12b3d1769116cda4',
  'fx 188': 'db087e12c98beb2c',
  'fx 189': '9760c6c1bccc5cb0',
  'fx 190': 'dcc115f2b966cc23',
  'fx 191': '483d9ba2391e0770',
  'fx 192': '4eca8bc02077959a',
  'fx 193': '9444d072d6c97ab7',
  'fx 194': '7d82c2065644452b',
  'fx 195': 'd0010c7d068136a9',
  'fx 196': 'ee2c3c367bf6d33e',
  'fx 197': '818831ec65c88993',
  'fx 198': 'a79177cd8652405b',
  'fx 199': '139a84d62adf6625',
  'fx 200': '9622c658cfcd0dc4',
  'fx 201': '22bf3b29571bf53e',
  'fx 202': '007052c638fb81e5',
  'fx 203': '9764c1d86911b3eb',
  'fx 204': '4c2476bc452cad00',
  'fx 205': 'e0eaed82f1ffcda2',
  'fx 206': '58e3a817ec6b0282',
  'fx 207': '7b288c234b3a08fd',
  'fx 208': 'ea56034aa3c61f1d',
  'fx 209': '6c5f9a818f2974d1',
  'fx 210': '55fcd472bcb99e65',
  'fx 211': 'c38290c1370284fe',
  'fx 212': '4c550c8bb04141c7',
  'fx 213': 'a477ca59f3e9acef',
  'fx 214': 'b0b962c36684b362',
  'fx 215': '86057c5f7f44d63b',
  'fx 216': '098b653c86782a88',
  'fx 217': '0f38b104913eca32',
  'fx 218': 'e0c5e26d1f1c6c8c',
  'fx 219': 'bf01746cf7c03451',
  'fx 220': '7464c9e7dc46313b',
  'fx 221': 'd1552772fd3fbded',
  'fx 222': 'bb736b1f4ee4a70e',
  'fx 223': 'a351b3a72a8bcf81',
  'fx 224': '7afeb7ff09f24517',
  'fx 225': '4e27fa64184fdac2',
  'fx 226': '4460c2301e5a87c1',
  'fx 227': 'b8dd230293c00a6e',
  'fx 228': '8663c45d8110b6cc',
  'fx 229': '2e1937f706fde37f',
  'fx 230': '32efefe1e4917e3f',
  'fx 231': 'd4515b6f858a86ed',
  'fx 232': 'b8925e2c4904a5b2',
  'fx 233': '55e1a292ef2c6e83',
  'fx 234': 'e0c34cd34fd32115',
  'fx 235': '7271f9868b834b31',
  'fx 236': '193fde4256d34db8',
  'fx 237': 'a4c9884e4c5e1d72',
  'fx 238': 'fd579b014dd5a307',
  'fx 239': '8563133d1cf945b6',
  'fx 240': '82b8c133f9d40ff5',
  'fx 241': 'ae8392753e37064b',
  'fx 242': '5c12d36dd717f6a4',
  'fx 243': '9b9f4b3b20d1bcea',
  'fx 244': '41a1be8c4bdcb942',
  'fx 245': 'c62e06d46efbeeae',
  'fx 246': '3db305112beee39e',
  'fx 247': '60e595da86991ae4',
  'fx 248': 'df9df943651bb1a4',
  'fx 249': 'ae44cf872ec59d3f',
  'fx 250': '0f8c019033a87256',
  'fx 251': 'a954627f13a7e5c0',
  'fx 252': '71b4c25a458751bb',
  'fx 253': 'ac1e56096f5fc1a2',
  'fx 254': '964ef728775f92db',
  'fx 255': '2c0c1a8961b135db',
  'no effect': '9d9a4840272646ee',
  'team LED table': '6c10b7ee761fa5f3',
  'team LED pairs': 'dec5adf998fef8c7',
  'team Game Day fx 0': 'a7a08c8ff110f6d4',
  'team Game Day fx 2': '52c284bb38b51ffb',
  'team Game Day fx 28': '4cabc2dff91ac519',
  'team Game Day fx 37': '7a091a7cc19bc3a7',
  'team Game Day fx 65': '4bba4acdd4857218',
  'team Game Day fx 83': '48aa74453ea2d1ad',
  'team Game Day fx 103': '9a7776cba1a3d4a0',
};

void main() {
  test('every pinned payload is byte-identical to the pre-revert recording',
      () async {
    final canonicals = await glitterRevertCanonicals();
    expect(canonicals.keys.toSet(), kGlitterRevertPinned.keys.toSet(),
        reason: 'the set of pinned cases is fixed');
    expect(canonicals.containsKey('fx $_glitter'), isFalse);
    final moved = <String>[];
    canonicals.forEach((label, text) {
      if (_digest(text) != kGlitterRevertPinned[label]) moved.add(label);
    });
    final detail = moved.take(3).map((l) {
      final t = canonicals[l]!;
      return '$l:\n${t.length > 3000 ? '${t.substring(0, 3000)}…' : t}';
    }).join('\n\n');
    expect(moved, isEmpty, reason: 'payloads moved:\n$detail');
  });

  test('the team table and the team list are not empty', () {
    expect(kTeamLedRgb, isNotEmpty);
    expect(kTeamColors, isNotEmpty);
  });
}
