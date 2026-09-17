// Pins BridgeApiClient's endpoint paths to the bridge firmware's own route
// table.
//
// WHY THIS TEST EXISTS. `reset()` posted to `/api/bridge/reset` for the whole
// life of the client. The firmware registers `/api/reset` and answers
// everything else through `onNotFound` with `404 {"error":"Not found"}`, so
// the call returned false on every bridge ever shipped and the only way to
// release a bridge for a new owner silently did nothing. Nothing caught it:
// the client swallows the failure and returns false, which is
// indistinguishable from an offline bridge.
//
// A unit test of `reset()` alone would not have caught it either — it would
// have asserted whatever path the implementation happened to use. The only
// thing that catches this bug class is comparing the client against the
// firmware, which is what this does: it parses `server.on(...)` out of
// main.cpp and asserts every path the client builds is a route the firmware
// actually registers.
//
// If this test fails after a firmware change, fix the client (or the
// firmware) — do not relax the assertion.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `server.on("/api/x", HTTP_GET, handler);`
final _firmwareRoute = RegExp(r'server\.on\(\s*"([^"]+)"');

/// `Uri.parse('$baseUrl/api/x')`
final _clientPath = RegExp(r"Uri\.parse\(\s*'\$baseUrl(/[^']*)'");

File _repoFile(String relative) {
  // Tests run with the package root as cwd.
  final f = File(relative);
  if (!f.existsSync()) {
    fail('expected to find $relative relative to ${Directory.current.path}');
  }
  return f;
}

void main() {
  group('BridgeApiClient endpoints match the firmware route table', () {
    late Set<String> firmwareRoutes;
    late List<String> clientPaths;

    setUpAll(() {
      final firmware = _repoFile('esp32-bridge/src/main.cpp').readAsStringSync();
      firmwareRoutes = _firmwareRoute
          .allMatches(firmware)
          .map((m) => m.group(1)!)
          .toSet();

      final client =
          _repoFile('lib/services/bridge_api_client.dart').readAsStringSync();
      clientPaths = _clientPath
          .allMatches(client)
          .map((m) => m.group(1)!)
          .toList();
    });

    test('the parsers actually found something', () {
      // Guards against a silent pass if either file is refactored such that
      // the regexes stop matching — an empty set trivially satisfies every
      // containment check below.
      expect(firmwareRoutes, isNotEmpty,
          reason: 'no server.on() routes parsed out of main.cpp');
      expect(clientPaths, isNotEmpty,
          reason: 'no \$baseUrl paths parsed out of bridge_api_client.dart');
    });

    test('firmware still registers the six endpoints the client relies on', () {
      expect(
        firmwareRoutes,
        containsAll(<String>[
          '/api/info',
          '/api/bridge/status',
          '/api/bridge/pair',
          '/api/bridge/auth',
          '/api/reboot',
          '/api/reset',
        ]),
      );
    });

    test('every client path is a route the firmware serves', () {
      for (final path in clientPaths) {
        expect(
          firmwareRoutes,
          contains(path),
          reason: 'BridgeApiClient builds "$path", which the firmware does '
              'not register. The firmware 404s unknown paths, so this call '
              'can only ever fail. Firmware routes: '
              '${firmwareRoutes.toList()..sort()}',
        );
      }
    });

    test('the specific regression: reset targets /api/reset', () {
      // The historical bug, pinned by name so the intent survives a refactor.
      final client =
          _repoFile('lib/services/bridge_api_client.dart').readAsStringSync();
      expect(client, contains(r"Uri.parse('$baseUrl/api/reset')"));
      expect(client, isNot(contains(r'$baseUrl/api/bridge/reset')),
          reason: 'the /api/bridge/reset path is not served by any firmware '
              'build; it must not come back');
    });
  });
}
