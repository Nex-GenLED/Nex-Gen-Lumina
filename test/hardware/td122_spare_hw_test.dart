// HARDWARE — the 0.15.4 spare ONLY. Runs nothing unless RUN_HW=true and
// refuses any host that is not a private address. Every scenario is state
// reads and state posts through the app's own code paths (the config read the
// app makes to learn the buses included); NO cfg write is sent by any
// scenario here — the LED-count save's hw.led write and the frame-rate write
// are bench steps for the owner, not tests.
//
//   flutter test test/hardware/td122_spare_hw_test.dart -r expanded \
//     --dart-define=RUN_HW=true --dart-define=HW_IP=<the spare's address> \
//     --dart-define=ITEM=reheal|watch|count|revert [--dart-define=WATCH_SECONDS=240]
//
// ITEM=reheal  one geometry re-heal: BEFORE, the result, the posted body, AFTER.
// ITEM=watch   the restart watch at a 10 s cadence for WATCH_SECONDS: the owner
//              power-cycles the spare meanwhile; on the uptime drop the
//              geometry re-heal runs and prints what it did.
// ITEM=count   the LED-count save's SEGMENT write only (bounds from the buses,
//              one POST, read-back, retry); the hw.led counts are not written.
// ITEM=revert  Light Up Now's revert capture against the live layout.
//
// Expected on a TWO-BUS spare from a one-segment (post-boot) layout:
//   reheal/watch : repaired; one POST with bounds for both and segment 0's
//                  look on segment 1; AFTER shows both, no amber anywhere.
//   count        : landed; one POST; AFTER = the bus bounds.
//   revert       : capturedAfterRepair; payload has both segments, no bounds.
// On a ONE-BUS spare every scenario stands aside / captures unchecked (the
// buses define one segment, so there is nothing to repair) — record that.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/revert_capture.dart';
import 'package:nexgen_command/features/wled/controller_restart_watch.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/segment_count_save.dart';
import 'package:nexgen_command/features/wled/segment_geometry_reheal.dart';
import 'package:nexgen_command/features/wled/segment_layout_guard.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const bool kRunHw = bool.fromEnvironment('RUN_HW', defaultValue: false);
const String kHwIp = String.fromEnvironment('HW_IP', defaultValue: '');
const String kItem = String.fromEnvironment('ITEM', defaultValue: 'reheal');
const int kWatchSeconds =
    int.fromEnvironment('WATCH_SECONDS', defaultValue: 240);
final RegExp _kPrivateV4 = RegExp(
    r'^(10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+)$');

Future<Map<String, dynamic>> _get(String path) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse('http://$kHwIp$path'));
    final res = await req.close().timeout(const Duration(seconds: 15));
    return jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

String _segs(Map<String, dynamic> state) => [
      for (final s in (state['seg'] as List).cast<Map>())
        '{id ${s['id']} ${s['start']}-${s['stop']} on ${s['on']} fx ${s['fx']} col0 ${(s['col'] as List?)?.first}}'
    ].join(' ');

Future<void> _snapshot(String label) async {
  final st = await _get('/json/state');
  final info = await _get('/json/info');
  debugPrint('$label: on ${st['on']} bri ${st['bri']} ps ${st['ps']} | ${_segs(st)}');
  debugPrint('$label info: uptime ${info['uptime']} fps ${(info['leds'] as Map)['fps']}');
  expect((info['leds'] as Map)['fps'], isNot(0),
      reason: 'frame rate must never read 0');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('+122 on the spare: $kItem', () async {
    if (!kRunHw) {
      markTestSkipped('RUN_HW not set');
      return;
    }
    expect(_kPrivateV4.hasMatch(kHwIp), isTrue,
        reason: "HW_IP must be the spare's private address, given on the command line");
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetWledHttpClientsForTest();
    final svc = WledService('http://$kHwIp');
    await _snapshot('BEFORE');

    switch (kItem) {
      case 'reheal':
        final r = await rehealSegmentGeometry(svc);
        debugPrint('REHEAL  : $r');
        debugPrint('POSTED  : ${r.posted}');
      case 'watch':
        var handled = false;
        final watch = ControllerRestartWatch(
          interval: const Duration(seconds: 10),
          readUptime: () async {
            final info = await svc.getInfo();
            final up = info?.raw['uptime'];
            if (up is! num) return null;
            debugPrint('TICK    : uptime ${up.toInt()}');
            return (endpoint: 'lan:${svc.baseUrl}', uptimeSeconds: up.toInt());
          },
          onRestart: (kind) async {
            debugPrint('RESTART : ${kind.name} observed — re-healing geometry');
            final r = await rehealSegmentGeometry(svc);
            debugPrint('REHEAL  : $r');
            debugPrint('POSTED  : ${r.posted}');
            handled = true;
          },
        );
        await watch.tickOnce(); // baseline
        debugPrint('WATCH   : baseline uptime ${watch.lastUptime}; power-cycle the spare now (up to $kWatchSeconds s)');
        watch.start();
        final deadline = DateTime.now().add(Duration(seconds: kWatchSeconds));
        while (!handled && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        watch.stop();
        debugPrint(handled
            ? 'WATCH   : restart handled after ${watch.ticks} ticks'
            : 'WATCH   : no restart observed in $kWatchSeconds s (${watch.ticks} ticks)');
      case 'count':
        final cfg = await svc.getConfig();
        final bounds = expectedBoundsFromChannels(deviceChannelsFromConfig(cfg));
        debugPrint('BOUNDS  : $bounds (from the buses; hw.led NOT written)');
        final r = await writeSegmentBoundsWithReadback(svc, bounds);
        debugPrint('COUNT   : $r');
      case 'revert':
        final cfg = await svc.getConfig();
        final c = await captureRevertLook(
            repo: svc, channels: deviceChannelsFromConfig(cfg));
        debugPrint('REVERT  : ${c.outcome.name} ${c.note}');
        debugPrint('PAYLOAD : ${jsonEncode(c.payload)}');
      default:
        fail('unknown ITEM $kItem');
    }

    await Future<void>.delayed(const Duration(seconds: 2));
    await _snapshot('AFTER');
  }, timeout: Timeout(Duration(seconds: kWatchSeconds + 120)));
}
