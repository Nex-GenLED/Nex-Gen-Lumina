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

/// The probe request path. The stub server ignores it so it never lands in the
/// recorded request lists and skews an assertion.
const String _kProbePath = '/__loopback_probe';

/// Finds a host this environment can ACTUALLY reach that WledService will not
/// treat as a simulation host. Returns null when there is none.
///
/// WHY THIS IS DISCOVERED RATHER THAN HARDCODED. These tests originally used a
/// literal `127.0.0.2`, which works on Windows and Linux (the whole 127/8 is
/// loopback there) but NOT on macOS, where lo0 is assigned only 127.0.0.1 and
/// anything else in 127/8 is refused unless explicitly aliased. Codemagic's
/// ios-workflow runs on mac_mini_m2, so the literal passed locally and could
/// not connect in CI -- a local-passes-CI-fails gap in the test, not the code.
///
/// `127.0.0.1` / `localhost` are NOT candidates: WledService short-circuits
/// them as simulation hosts (wled_service.dart:325) and returns success with
/// no HTTP at all, which would make every assertion here vacuously pass.
Future<String?> _reachableNonSimHost(int port) async {
  final candidates = <String>['127.0.0.2'];
  try {
    for (final ni in await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false)) {
      for (final a in ni.addresses) {
        if (!a.isLoopback) candidates.add(a.address);
      }
    }
  } catch (_) {
    // Interface enumeration can be denied in a sandbox; fall through with the
    // literal candidate only.
  }

  for (final host in candidates) {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req = await client.getUrl(Uri.parse('http://$host:$port$_kProbePath'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      await res.drain<void>();
      return host;
    } catch (_) {
      // Not reachable here -- try the next candidate.
    } finally {
      client?.close(force: true);
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late List<String> bodies;
  String? base;  // null when no usable host exists in this environment

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetWledHttpClientsForTest();
    bodies = [];
    server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.listen((req) async {
      if (req.uri.path == _kProbePath) {
        req.response.statusCode = 200;
        await req.response.close();
        return;
      }
      bodies.add(await utf8.decoder.bind(req).join());
      req.response.statusCode = 200;
      req.response.write('{"success":true}');
      await req.response.close();
    });

    // Discover, do not assume. See _reachableNonSimHost.
    final host = await _reachableNonSimHost(server.port);
    base = host == null ? null : 'http://$host:${server.port}';
  });

  /// Skips CLEANLY (recorded as a skip with a reason, never a silent pass) when
  /// this environment offers no reachable non-simulation address.
  bool skipIfNoHost() {
    if (base != null) return false;
    markTestSkipped(
        'no reachable non-simulation loopback address in this environment. '
        'macOS assigns only 127.0.0.1 to lo0, and WledService treats '
        '127.0.0.1/localhost/mock as simulation hosts, so there is no address '
        'that both routes and exercises real HTTP here.');
    return true;
  }

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
      if (skipIfNoHost()) return;
      final big = _payloadOfRoughly(kMaxApplyPayloadBytes * 2);
      expect(jsonEncode(big).length, greaterThan(kMaxApplyPayloadBytes));

      final svc = WledService(base!);
      final ok = await svc.applyJson(big);

      expect(ok, isFalse, reason: 'an oversize apply must FAIL, not wedge');
      expect(bodies, isEmpty,
          reason: 'the controller must never see it — refusing after sending '
              'would defeat the entire point');
    });

    test('a payload UNDER the ceiling is posted normally', () async {
      if (skipIfNoHost()) return;
      final small = _payloadOfRoughly(500);
      expect(jsonEncode(small).length, lessThan(kMaxApplyPayloadBytes));

      final svc = WledService(base!);
      final ok = await svc.applyJson(small);

      expect(ok, isTrue);
      expect(bodies, hasLength(1), reason: 'normal applies are unaffected');
    });

    test('the largest payload that actually exists in the fleet still passes',
        () async {
      if (skipIfNoHost()) return;
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

      final svc = WledService(base!);
      expect(await svc.applyJson(real), isTrue,
          reason: 'the only real saved design in the fleet must still apply');
    });

    test('PROVISIONING is exempt — a re-provision may legitimately be large',
        () async {
      if (skipIfNoHost()) return;
      // applyGeometryJson states the FULL expected shape for the installation.
      // Capping it would break the repair path a big install depends on, which
      // is why the ceiling is scoped to !allowGeometry.
      final big = _payloadOfRoughly(kMaxApplyPayloadBytes * 2);

      final svc = WledService(base!);
      final ok = await svc.applyGeometryJson(big);

      expect(ok, isTrue, reason: 'provisioning is not subject to the cap');
      expect(bodies, hasLength(1),
          reason: 'and it really did reach the wire');
    });
  });
}
