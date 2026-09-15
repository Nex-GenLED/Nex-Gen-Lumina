// #114: LAN requests are recorded as `direct` — but ONLY on the WledService
// instance the repository provider hands out (recordsRouting: true). The
// installer / site-sync / config-pusher helpers build their own instances and
// talk to the LAN whatever the routing is; they must not paint the badge.
//
// Uses a REAL HttpServer. Host discovery is copied from
// post_json_pooled_client_test.dart: WledService treats 127.0.0.1 / localhost
// / mock as simulation hosts and sends no HTTP at all, so a non-simulation
// address that actually routes has to be found, and the test skips cleanly
// (never silently passes) when there is none.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/routing_diagnostics.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kProbePath = '/__loopback_probe';

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
    // Interface enumeration can be denied in a sandbox.
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
      // Try the next candidate.
    } finally {
      client?.close(force: true);
    }
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  String? base;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    resetWledHttpClientsForTest();
    RoutingDiagnostics.resetForTest();

    server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.listen((req) async {
      req.response.statusCode = 200;
      if (req.uri.path != _kProbePath) {
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"on":true,"bri":128,"seg":[]}');
      }
      await req.response.close();
    });
    final host = await _reachableNonSimHost(server.port);
    base = host == null ? null : 'http://$host:${server.port}';
  });

  tearDown(() async {
    await server.close(force: true);
    resetWledHttpClientsForTest();
  });

  bool skipIfNoHost() {
    if (base != null) return false;
    markTestSkipped('no reachable non-simulation address in this environment '
        '(see post_json_pooled_client_test.dart).');
    return true;
  }

  test('the routed instance records each LAN request as direct', () async {
    if (skipIfNoHost()) return;

    final state = await WledService(base!, recordsRouting: true).getState();
    expect(state, isNotNull, reason: 'the request must really reach the server');

    final recent = RoutingDiagnostics.instance.recent;
    expect(recent, isNotEmpty);
    expect(recent.first.path, RoutePath.direct);
    expect(recent.first.command, '/json/state');
  });

  test('a helper instance (default) records nothing', () async {
    if (skipIfNoHost()) return;

    final state = await WledService(base!).getState();
    expect(state, isNotNull);
    expect(RoutingDiagnostics.instance.recent, isEmpty);
  });
}
