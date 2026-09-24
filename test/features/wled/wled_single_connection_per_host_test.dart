// Bench 2026-09-23 (controller-reachability-2026-09-23.md §4): WLED 0.15.x
// accepts connections through a listen backlog of 5 and silently DROPS every
// SYN that arrives while the backlog is full — no RST, so the phone keeps
// retransmitting (1 s, 3 s, 7 s …) until its 15 s connect timeout, which the
// app reports as "controller offline". The app's repository-rebuild cascade
// and its resume burst open 6–9 controller connections in the same frame.
// Spaced by 80 ms the same requests were all answered in < 1 s.
//
// Fix: the pooled controller clients allow ONE live connection per host, so
// requests to the same controller are serialised by dart:io instead of
// racing the backlog. This test pins that: three requests against a server
// that never answers must reach it one at a time.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

void main() {
  late ServerSocket server;
  final accepted = <Socket>[];

  setUp(() async {
    accepted.clear();
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((sock) {
      accepted.add(sock);
      sock.listen((_) {}, onDone: () {}, onError: (_) {});
    });
  });

  tearDown(() async {
    for (final s in accepted) {
      s.destroy();
    }
    await server.close();
    resetWledHttpClientsForTest();
  });

  test('pooled clients allow one live connection per host', () {
    for (final t in const [5, 10, 15]) {
      expect(wledClientForTest(Duration(seconds: t)).maxConnectionsPerHost, 1,
          reason: '${t}s client');
    }
  });

  test('three concurrent requests reach the controller one at a time',
      () async {
    final client = wledClientForTest(const Duration(seconds: 5));
    final uri = Uri.parse('http://127.0.0.1:${server.port}/json/state');

    Future<void> one() async {
      final req = await client.getUrl(uri);
      req.persistentConnection = false;
      try {
        await closeOrAbort(req, const Duration(milliseconds: 300));
      } on TimeoutException {
        // expected: the server never answers
      }
    }

    final all = Future.wait([one(), one(), one()]);

    // While the first request is pending, the other two must NOT have opened
    // a socket (the old behaviour: three SYNs in the same instant).
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(accepted, hasLength(1),
        reason: 'only one connection may be live per host');

    await all;
    // Each request got its turn after the previous one was aborted.
    expect(accepted, hasLength(3));
  });
}
