// PART C — the design-apply POST is unchunked, Content-Length'd, and pooled.
//
// audit/GAMEDAY_DIRECT_APPLY_WEDGE_AUDIT.md §3. `_postJson` was the LAST
// /json/state writer still on `package:http`'s top-level `post`. Its three
// siblings — `_postConfig` (Item #61 Workstream B), `savePreset` (P1-53 /
// `7ad46ac`) and `_postPerPixelChunk` — were each deliberately migrated to a
// pooled HttpClient with an explicit Content-Length after bench-verified
// failures, and each carries a "Do NOT swap this back to http.post" comment.
// The main design-apply path, which every Game Day fire goes through, was the
// one left behind.
//
// These tests stand up a REAL HttpServer and inspect the request as it arrives
// on the wire. That is deliberately stronger than asserting which Dart API was
// called: it settles U2 from the wedge audit ("does this request actually
// chunk?") by measurement rather than by reading package docs.
//
// NOTE ON THE HOST — this is load-bearing. WledService treats `127.0.0.1`,
// `localhost` and `mock` as SIMULATION hosts (wled_service.dart:325) and
// returns success WITHOUT any HTTP at all, which would make every assertion
// here vacuously pass. The check is a literal string compare, so the server
// binds anyIPv4 and is addressed as `127.0.0.2`: still loopback, still a real
// socket, but not a simulation host. (`0.0.0.0` is not a valid destination on
// Windows and silently never connects.)

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _payload({int fx = 0}) => {
      'on': true,
      'bri': 200,
      'seg': [
        {
          'id': 0,
          'fx': fx,
          'col': [
            [255, 0, 0, 0]
          ],
        }
      ],
    };

void main() {
  // applyJson reads the participation cache (SharedPreferences) before it
  // posts, so the binding and a mock store are required to reach _postJson.
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late List<HttpHeaders> seen;
  late List<String> bodies;
  late String base;

  Future<void> startServer({int status = 200}) async {
    seen = [];
    bodies = [];
    server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    base = 'http://127.0.0.2:${server.port}';
    server.listen((req) async {
      seen.add(req.headers);
      bodies.add(await utf8.decoder.bind(req).join());
      req.response.statusCode = status;
      req.response.write('{"success":true}');
      await req.response.close();
    });
  }

  setUp(() async {
    // TestWidgetsFlutterBinding installs an HttpOverrides that stubs every
    // real request (that is what makes widget tests hermetic). These tests
    // need the ACTUAL socket, because the whole assertion is about what
    // reaches the wire — so the override is cleared for this file only.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetWledHttpClientsForTest();
    await startServer();
  });

  tearDown(() async {
    await server.close(force: true);
    resetWledHttpClientsForTest();
  });

  group('Part C — the apply POST on the wire', () {
    test('sets an explicit Content-Length matching the body', () async {
      final svc = WledService(base);
      final ok = await svc.applyJson(_payload());

      expect(ok, isTrue, reason: 'the stub server answers 200');
      expect(seen, hasLength(1), reason: 'exactly one request on the wire');
      expect(seen.single.contentLength, greaterThan(0),
          reason: 'Content-Length must be explicit — the point of Part C');
      expect(seen.single.contentLength, bodies.single.length,
          reason: 'and it must match the body actually sent');
    });

    test('is NOT chunked — settles U2 by measurement', () async {
      // WLED 0.15.x silently drops chunked POSTs to /json/state: 200 OK,
      // nothing applied. This is what the sibling migrations guarantee.
      final svc = WledService(base);
      await svc.applyJson(_payload());

      final te = seen.single.value(HttpHeaders.transferEncodingHeader);
      expect(te, anyOf(isNull, isNot(contains('chunked'))),
          reason: 'transfer-encoding must not be chunked');
    });

    test('a LARGE payload is still unchunked — the size case that matters',
        () async {
      // The wedge symptom was size-dependent, so the small-body case alone
      // would not be reassuring. This body is far larger than any real Game
      // Day payload measured in U1 (max 389 bytes fleetwide).
      final big = <String, dynamic>{
        'on': true,
        'bri': 200,
        'seg': [
          for (var i = 0; i < 200; i++)
            {
              'id': i,
              'fx': 27,
              'col': [
                [0, 70, 135, 0],
                [192, 154, 91, 0]
              ],
            }
        ],
      };

      final svc = WledService(base);
      await svc.applyJson(big);

      expect(bodies.single.length, greaterThan(6000),
          reason: 'past the ~6KB region the per-pixel chunker exists to '
              'respect');
      final te = seen.single.value(HttpHeaders.transferEncodingHeader);
      expect(te, anyOf(isNull, isNot(contains('chunked'))),
          reason: 'a large body must NOT fall into chunked encoding');
      expect(seen.single.contentLength, bodies.single.length);
    });

    test('uses the POOLED client — http.post would leave the pool empty',
        () async {
      expect(wledHttpClientCacheSize(), 0, reason: 'baseline: pool empty');

      final svc = WledService(base);
      await svc.applyJson(_payload());

      expect(wledHttpClientCacheSize(), 1,
          reason: 'the pooled client was resolved. `http.post` creates and '
              'discards its own client and never touches this pool');
    });

    test('repeated applies REUSE the one client rather than stacking',
        () async {
      final svc = WledService(base);
      await svc.applyJson(_payload());
      await svc.applyJson(_payload(fx: 1));
      await svc.applyJson(_payload(fx: 2));

      expect(seen, hasLength(3));
      expect(wledHttpClientCacheSize(), 1,
          reason: 'one client per connect-timeout, reused across applies');
    });

    test('behaviour unchanged: exactly ONE attempt, no retry on failure',
        () async {
      // The wedge audit (§3) found the single-shot, no-backoff behaviour
      // gap-free and explicitly in scope to PRESERVE. A 500 must produce one
      // request and one `false`, never a retry.
      await server.close(force: true);
      await startServer(status: 500);

      final svc = WledService(base);
      final ok = await svc.applyJson(_payload());

      expect(ok, isFalse, reason: 'a 500 is a failed write');
      expect(seen, hasLength(1),
          reason: 'ONE attempt — no retry, no backoff loop');
    });
  });
}
