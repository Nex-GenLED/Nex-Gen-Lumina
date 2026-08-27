// PART D — a single /json/state apply has a SIZE CEILING.
//
// audit/GAMEDAY_WEDGE_U1_U6.md §1. `applyJson` had no size bound at all. That
// mattered because the project already knows the device ceiling: applyPerPixel
// exists precisely because WLED's JSON buffer chokes above roughly 6.0 KB /
// ~337 entries and answers HTTP 400 {"error":9} (per_pixel.dart:20-25,
// bench-measured on WLED 0.15.4/ESP32). A design big enough to need that
// chunker was nonetheless posted by applyJson as one unbounded body.
//
// CALIBRATION, from real data rather than a guess: a client-credentialed census
// of all 43 game_day_autopilot docs (2026-08-26) found exactly ONE carrying a
// saved_design_payload, at 389 bytes, with no seg[].i anywhere in the fleet.
// The 4 KB ceiling is ~10x the largest payload that actually exists — so these
// tests also pin that no realistic design trips it.
//
// See post_json_pooled_client_test.dart for why the host is 127.0.0.2 and why
// HttpOverrides is cleared; both silently void the suite if got wrong.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A payload whose encoded size lands near [targetBytes], built from realistic
/// segments rather than filler so the shape stays representative.
Map<String, dynamic> _payloadOfRoughly(int targetBytes) {
  final segs = <Map<String, dynamic>>[];
  var i = 0;
  while (jsonEncode({'on': true, 'bri': 200, 'seg': segs}).length < targetBytes) {
    segs.add({
      'id': i++,
      'fx': 27,
      'sx': 99,
      'ix': 128,
      'col': [
        [0, 70, 135, 0],
        [192, 154, 91, 0]
      ],
    });
  }
  return {'on': true, 'bri': 200, 'seg': segs};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late List<String> bodies;
  late String base;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetWledHttpClientsForTest();
    bodies = [];
    server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    base = 'http://127.0.0.2:${server.port}';
    server.listen((req) async {
      bodies.add(await utf8.decoder.bind(req).join());
      req.response.statusCode = 200;
      req.response.write('{"success":true}');
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    resetWledHttpClientsForTest();
  });

  group('Part D — oversize applies are refused, not posted', () {
    test('the ceiling sits below the bench-measured device limit', () {
      // 6.0 KB is where the controller starts answering 400 error:9. The cap
      // must leave headroom under that, not sit on it.
      expect(kMaxApplyPayloadBytes, lessThan(6000),
          reason: 'must refuse BEFORE the device does');
      expect(kMaxApplyPayloadBytes, greaterThan(2000),
          reason: 'but not so low it rejects a legitimate multi-channel design');
    });

    test('an OVERSIZE payload is refused and never reaches the wire', () async {
      final big = _payloadOfRoughly(kMaxApplyPayloadBytes * 2);
      expect(jsonEncode(big).length, greaterThan(kMaxApplyPayloadBytes));

      final svc = WledService(base);
      final ok = await svc.applyJson(big);

      expect(ok, isFalse, reason: 'an oversize apply must FAIL, not wedge');
      expect(bodies, isEmpty,
          reason: 'the controller must never see it — refusing after sending '
              'would defeat the entire point');
    });

    test('a payload UNDER the ceiling is posted normally', () async {
      final small = _payloadOfRoughly(500);
      expect(jsonEncode(small).length, lessThan(kMaxApplyPayloadBytes));

      final svc = WledService(base);
      final ok = await svc.applyJson(small);

      expect(ok, isTrue);
      expect(bodies, hasLength(1), reason: 'normal applies are unaffected');
    });

    test('the largest payload that actually exists in the fleet still passes',
        () async {
      // The real saved_design_payload measured in U1: 3 segments, 3 colours
      // each, 389 bytes. If the cap ever rejects this, it is miscalibrated.
      final real = {
        'on': true,
        'bri': 255,
        'seg': [
          for (var i = 0; i < 3; i++)
            {
              'id': i,
              'fx': 27,
              'sx': 99,
              'ix': 128,
              'pal': 5,
              'grp': 1,
              'spc': 0,
              'col': [
                [0, 70, 135, 0],
                [192, 154, 91, 0],
                [255, 255, 255, 0]
              ],
              'on': true,
            }
        ],
      };
      expect(jsonEncode(real).length, lessThan(kMaxApplyPayloadBytes));

      final svc = WledService(base);
      expect(await svc.applyJson(real), isTrue,
          reason: 'the only real saved design in the fleet must still apply');
    });

    test('PROVISIONING is exempt — a re-provision may legitimately be large',
        () async {
      // applyGeometryJson states the FULL expected shape for the installation.
      // Capping it would break the repair path a big install depends on, which
      // is why the ceiling is scoped to !allowGeometry.
      final big = _payloadOfRoughly(kMaxApplyPayloadBytes * 2);

      final svc = WledService(base);
      final ok = await svc.applyGeometryJson(big);

      expect(ok, isTrue, reason: 'provisioning is not subject to the cap');
      expect(bodies, hasLength(1),
          reason: 'and it really did reach the wire');
    });
  });
}
