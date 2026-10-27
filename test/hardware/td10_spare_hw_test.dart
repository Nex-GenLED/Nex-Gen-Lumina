// HARDWARE — the 0.15.4 spare ONLY. Runs nothing unless RUN_HW=true, and
// refuses any host other than the one the owner named. State posts only:
// the TD-10 guard's bounds write and the look. No cfg write, no preset save.
//
//   flutter test test/hardware/td10_spare_hw_test.dart -r expanded \
//     --dart-define=RUN_HW=true --dart-define=HW_IP=<the spare's address> \
//     [--dart-define=GUARD=off]
// The address is never written down here: it comes from the command line and
// must be a private (RFC 1918) address, which keeps this off any customer unit.
//
// Expected with the guard ON, from a one-segment (post-boot) layout:
//   wire  : POST 1 = bounds for every bus segment; POST 2 = the look (ids 0, 1)
//   strip : every bus segment present; segment 0 red, segment 1 blue
// Expected with the guard OFF, from a one-segment layout:
//   wire  : one POST, the look; the firmware drops id 1
//   strip : segment 0 (the whole strip) red; nothing blue

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const bool kRunHw = bool.fromEnvironment('RUN_HW', defaultValue: false);
const String kHwIp = String.fromEnvironment('HW_IP', defaultValue: '');
const String kGuard = String.fromEnvironment('GUARD', defaultValue: 'on');
final RegExp _kPrivateV4 = RegExp(
    r'^(10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+)$');

Future<Map<String, dynamic>> _get(String path) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse('http://$kHwIp$path'));
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await utf8.decoder.bind(res).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

String _segs(Map<String, dynamic> state) => [
      for (final s in (state['seg'] as List).cast<Map>())
        '{id ${s['id']} ${s['start']}-${s['stop']} on ${s['on']} fx ${s['fx']} col0 ${(s['col'] as List?)?.first}}'
    ].join(' ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TD-10 guard on the spare (guard $kGuard)', () async {
    if (!kRunHw) {
      markTestSkipped('RUN_HW not set');
      return;
    }
    expect(_kPrivateV4.hasMatch(kHwIp), isTrue,
        reason: "HW_IP must be the spare's private address, given on the command line");
    // flutter_test answers every real socket with a mock 400 unless cleared.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetWledHttpClientsForTest();
    WledService.layoutGuardEnabled = kGuard != 'off';

    final before = await _get('/json/state');
    debugPrint('BEFORE  : on ${before['on']} bri ${before['bri']} ps ${before['ps']} | ${_segs(before)}');
    final info = await _get('/json/info');
    debugPrint('INFO    : ver ${info['ver']} uptime ${info['uptime']} leds ${(info['leds'] as Map)['count']} fps ${(info['leds'] as Map)['fps']}');

    final look = <String, dynamic>{
      'on': true,
      'seg': [
        {
          'id': 0,
          'on': true,
          'fx': 0,
          'col': [
            [255, 0, 0, 0]
          ]
        },
        {
          'id': 1,
          'on': true,
          'fx': 0,
          'col': [
            [0, 0, 255, 0]
          ]
        },
      ],
    };
    final svc = WledService('http://$kHwIp');
    final ok = await svc.applyJson(look);
    debugPrint('APPLY   : returned $ok (guard ${WledService.layoutGuardEnabled ? 'on' : 'off'})');

    await Future<void>.delayed(const Duration(seconds: 2));
    final after = await _get('/json/state');
    debugPrint('AFTER   : on ${after['on']} bri ${after['bri']} ps ${after['ps']} | ${_segs(after)}');
    final info2 = await _get('/json/info');
    debugPrint('INFO2   : uptime ${info2['uptime']} fps ${(info2['leds'] as Map)['fps']}');
    expect(ok, isTrue);
    expect((info2['leds'] as Map)['fps'], isNot(0), reason: 'frame rate must never read 0 after a write');
  });
}
