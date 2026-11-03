// +122 item 2 (TD-9): the geometry re-heal is deliberate, shared, and gives a
// re-created segment segment 0's look instead of the firmware's default amber.
//
// Fixtures throughout: the TWO-CHANNEL layout (segments 0 [0,90) and 1
// [90,180) from two buses) and the ONE-SEGMENT-AFTER-RESTART layout (segment 0
// re-bound over the whole strip [0,180), segment 1 gone). The loopback fake
// controller is stateful: a provisioning POST re-binds its segments, so the
// read-back after a repair shows what landed. Synthetic addresses only.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/controller_restart_watch.dart';
import 'package:nexgen_command/features/wled/segment_geometry_reheal.dart';
import 'package:nexgen_command/features/wled/segment_layout_guard.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';
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
  } catch (_) {}
  for (final host in candidates) {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final req =
          await client.getUrl(Uri.parse('http://$host:$port$_kProbePath'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      await res.drain<void>();
      return host;
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }
  return null;
}

/// A live segment carrying the look the house was showing: solid team red.
Map<String, dynamic> _seg(int id, int start, int stop,
        {List<List<int>>? col, int fx = 0, bool on = true}) =>
    {
      'id': id,
      'start': start,
      'stop': stop,
      'len': stop - start,
      'on': on,
      'frz': false,
      'bri': 255,
      'fx': fx,
      'sx': 128,
      'ix': 128,
      'pal': 0,
      'col': col ??
          [
            [227, 24, 55, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0]
          ],
    };

const _twoBusCfg = {
  'hw': {
    'led': {
      'fps': 42,
      'ins': [
        {'start': 0, 'len': 90, 'pin': [2], 'type': 30},
        {'start': 90, 'len': 90, 'pin': [14], 'type': 30},
      ]
    }
  }
};

const _twoChannel = <SegmentShape>[SegmentShape(0, 0, 90), SegmentShape(1, 90, 180)];
const _twoChannelBounds = <SegmentBounds>[
  (id: 0, start: 0, stop: 90),
  (id: 1, start: 90, stop: 180),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('geometryRepairPayload — the repair body', () {
    test('two-channel layout: bounds only, no look on either segment', () {
      final body = geometryRepairPayload(
        want: _twoChannelBounds,
        liveState: {'seg': [_seg(0, 0, 90), _seg(1, 90, 180)]},
      );
      expect(body, {
        'seg': [
          {'id': 0, 'start': 0, 'stop': 90},
          {'id': 1, 'start': 90, 'stop': 180},
        ]
      });
    });

    test('one segment after a restart: segment 1 is re-created WITH segment '
        '0\'s look; segment 0 keeps its own (bounds only)', () {
      final body = geometryRepairPayload(
        want: _twoChannelBounds,
        liveState: {'seg': [_seg(0, 0, 180, fx: 12)]},
      );
      final segs = (body['seg'] as List).cast<Map<String, dynamic>>();
      expect(segs[0], {'id': 0, 'start': 0, 'stop': 90});
      expect(segs[1]['id'], 1);
      expect(segs[1]['start'], 90);
      expect(segs[1]['stop'], 180);
      expect(segs[1]['fx'], 12);
      expect(segs[1]['on'], isTrue);
      expect(segs[1]['bri'], 255);
      expect(segs[1]['col'], [
        [227, 24, 55, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0]
      ]);
      expect(segs[1]['sx'], 128);
      expect(segs[1]['ix'], 128);
      expect(segs[1]['pal'], 0);
      expect(segs[1].keys, isNot(contains('rev')),
          reason: 'geometry fields never ride along');
      expect(segs[1].keys, isNot(contains('len')));
      expect(segs[1].keys, isNot(contains('frz')));
    });

    test('a partial segment 0 copies only the look keys it has', () {
      final body = geometryRepairPayload(
        want: _twoChannelBounds,
        liveState: {
          'seg': [
            {'id': 0, 'start': 0, 'stop': 180, 'fx': 3}
          ]
        },
      );
      final seg1 = (body['seg'] as List)[1] as Map;
      expect(seg1, {'id': 1, 'start': 90, 'stop': 180, 'fx': 3});
    });

    test('no readable segment 0 → bounds only (nothing invented)', () {
      final body = geometryRepairPayload(want: _twoChannelBounds, liveState: null);
      expect(body, {
        'seg': [
          {'id': 0, 'start': 0, 'stop': 90},
          {'id': 1, 'start': 90, 'stop': 180},
        ]
      });
    });

    test('the copied look is a copy, not the live list itself', () {
      final live = {'seg': [_seg(0, 0, 180)]};
      final body = geometryRepairPayload(want: _twoChannelBounds, liveState: live);
      ((body['seg'] as List)[1]['col'] as List)[0][0] = 1;
      expect((live['seg']![0]['col'] as List)[0][0], 227);
    });
  });

  group('classifyUptime — the trigger', () {
    const ep = 'lan:http://192.0.2.10';
    test('uptime lower than the last read on the same endpoint → DROP', () {
      expect(
          classifyUptime(
              previousEndpoint: ep,
              previousUptime: 282190,
              reading: (endpoint: ep, uptimeSeconds: 45)),
          RestartKind.uptimeDrop);
    });
    test('uptime rising → none', () {
      expect(
          classifyUptime(
              previousEndpoint: ep,
              previousUptime: 45,
              reading: (endpoint: ep, uptimeSeconds: 75)),
          RestartKind.none);
    });
    test('first readable uptime small → COLD START; large → none', () {
      expect(
          classifyUptime(
              previousEndpoint: null,
              previousUptime: null,
              reading: (endpoint: ep, uptimeSeconds: 20)),
          RestartKind.coldStart);
      expect(
          classifyUptime(
              previousEndpoint: null,
              previousUptime: null,
              reading: (endpoint: ep, uptimeSeconds: 9000)),
          RestartKind.none);
    });
    test('a new endpoint resets the baseline (no false drop when the user '
        'switches controllers)', () {
      expect(
          classifyUptime(
              previousEndpoint: 'lan:http://192.0.2.11',
              previousUptime: 282190,
              reading: (endpoint: ep, uptimeSeconds: 5000)),
          RestartKind.none);
    });
  });

  group('ControllerRestartWatch', () {
    test('a drop fires the heal once; rising uptime fires nothing', () async {
      final readings = <UptimeReading?>[
        (endpoint: 'lan:a', uptimeSeconds: 5000),
        (endpoint: 'lan:a', uptimeSeconds: 5030),
        (endpoint: 'lan:a', uptimeSeconds: 30),
        (endpoint: 'lan:a', uptimeSeconds: 60),
      ];
      var i = 0;
      final fired = <RestartKind>[];
      final watch = ControllerRestartWatch(
        readUptime: () async => readings[i++],
        onRestart: (k) async => fired.add(k),
      );
      for (var n = 0; n < readings.length; n++) {
        await watch.tickOnce();
      }
      expect(fired, [RestartKind.uptimeDrop]);
      expect(watch.restartsSeen, 1);
      expect(watch.lastUptime, 60);
    });

    test('an outage (null reads) keeps the baseline, so the reboot behind it '
        'is still seen', () async {
      final readings = <UptimeReading?>[
        (endpoint: 'lan:a', uptimeSeconds: 5000),
        null,
        null,
        (endpoint: 'lan:a', uptimeSeconds: 40),
      ];
      var i = 0;
      final fired = <RestartKind>[];
      final watch = ControllerRestartWatch(
        readUptime: () async => readings[i++],
        onRestart: (k) async => fired.add(k),
      );
      for (var n = 0; n < readings.length; n++) {
        await watch.tickOnce();
      }
      expect(fired, [RestartKind.uptimeDrop]);
    });

    test('first reading small → cold start, once', () async {
      final readings = <UptimeReading?>[
        (endpoint: 'lan:a', uptimeSeconds: 15),
        (endpoint: 'lan:a', uptimeSeconds: 45),
      ];
      var i = 0;
      final fired = <RestartKind>[];
      final watch = ControllerRestartWatch(
        readUptime: () async => readings[i++],
        onRestart: (k) async => fired.add(k),
      );
      await watch.tickOnce();
      await watch.tickOnce();
      expect(fired, [RestartKind.coldStart]);
    });

    test('a read that throws is swallowed and the baseline is kept', () async {
      var calls = 0;
      final fired = <RestartKind>[];
      final watch = ControllerRestartWatch(
        readUptime: () async {
          calls++;
          if (calls == 2) throw const SocketException('down');
          return (endpoint: 'lan:a', uptimeSeconds: calls == 1 ? 5000 : 10);
        },
        onRestart: (k) async => fired.add(k),
      );
      await watch.tickOnce();
      await watch.tickOnce();
      await watch.tickOnce();
      expect(fired, [RestartKind.uptimeDrop]);
    });

    test('the interval never goes below the floor', () {
      final w = ControllerRestartWatch(
        readUptime: () async => null,
        onRestart: (_) async {},
        interval: const Duration(seconds: 1),
      );
      expect(w.interval, kRestartWatchMinInterval);
    });
  });

  group('rehealSegmentGeometry against a stateful fake controller', () {
    late HttpServer server;
    late List<Map<String, dynamic>> posted;
    late List<Map<String, dynamic>> liveSegs;
    late bool cfgReadable;
    String? base;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      resetWledHttpClientsForTest();
      posted = [];
      cfgReadable = true;
      liveSegs = [_seg(0, 0, 90), _seg(1, 90, 180)];
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      server.listen((req) async {
        final path = req.uri.path;
        if (path == _kProbePath) {
          req.response.statusCode = 200;
          await req.response.close();
          return;
        }
        if (req.method == 'POST') {
          final body = jsonDecode(await utf8.decoder.bind(req).join())
              as Map<String, dynamic>;
          posted.add(body);
          // A provisioning body re-binds the segments it names, like WLED.
          final seg = body['seg'];
          if (seg is List) {
            for (final s in seg.cast<Map<String, dynamic>>()) {
              if (s['id'] is! int || s['start'] is! int || s['stop'] is! int) {
                continue;
              }
              final id = s['id'] as int;
              final idx = liveSegs.indexWhere((l) => l['id'] == id);
              final merged = <String, dynamic>{
                ...(idx >= 0 ? liveSegs[idx] : _seg(id, 0, 0, col: [[255, 160, 0, 0]])),
                ...s,
              };
              merged['len'] = (s['stop'] as int) - (s['start'] as int);
              if (idx >= 0) {
                liveSegs[idx] = merged;
              } else {
                liveSegs.add(merged);
              }
            }
          }
          req.response.statusCode = 200;
          req.response.write('{"success":true}');
          await req.response.close();
          return;
        }
        req.response.headers.contentType = ContentType.json;
        if (path == '/json/state') {
          req.response.write(jsonEncode({'on': true, 'bri': 200, 'seg': liveSegs}));
        } else if (path == '/json/cfg') {
          if (!cfgReadable) {
            req.response.statusCode = 500;
          } else {
            req.response.write(jsonEncode(_twoBusCfg));
          }
        } else if (path == '/json/info') {
          req.response.write(jsonEncode({
            'ver': '0.15.4',
            'uptime': 42,
            'leds': {'count': 180, 'fps': 42},
            'mac': 'aa00000000a1',
          }));
        } else {
          req.response.write('{}');
        }
        await req.response.close();
      });
      final host = await _reachableNonSimHost(server.port);
      base = host == null ? null : 'http://$host:${server.port}';
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('two-channel layout → healthy, zero writes', () async {
      if (base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      final r = await rehealSegmentGeometry(WledService(base!));
      expect(r.outcome, GeometryRehealOutcome.healthy);
      expect(posted, isEmpty);
    });

    test('one segment after a restart → ONE provisioning POST carrying both '
        'bounds and segment 0\'s look on the re-created segment; read-back '
        'shows the bus layout', () async {
      if (base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      liveSegs = [_seg(0, 0, 180, fx: 12)];
      final r = await rehealSegmentGeometry(WledService(base!));
      expect(r.outcome, GeometryRehealOutcome.repaired, reason: '$r');
      expect(r.before, [const SegmentShape(0, 0, 180)]);
      expect(r.after, _twoChannel);
      expect(r.lookCopiedTo, [1]);
      expect(posted, hasLength(1));
      final segs = (posted.single['seg'] as List).cast<Map<String, dynamic>>();
      expect(segs[0], {'id': 0, 'start': 0, 'stop': 90});
      expect(segs[1]['fx'], 12);
      expect(segs[1]['col'][0], [227, 24, 55, 0]);
      // The fake re-bound its segments: the strip is no longer amber anywhere.
      expect(liveSegs.map((s) => s['col'][0]).toList(), [
        [227, 24, 55, 0],
        [227, 24, 55, 0],
      ]);
    });

    test('buses unreadable → stand aside, zero writes', () async {
      if (base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      cfgReadable = false;
      liveSegs = [_seg(0, 0, 180)];
      final r = await rehealSegmentGeometry(WledService(base!));
      expect(r.outcome, GeometryRehealOutcome.standAside);
      expect(posted, isEmpty);
    });

    test('the healer\'s geometry-only run reports the repair and the copied '
        'look', () async {
      if (base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      liveSegs = [_seg(0, 0, 180)];
      final svc = WledService(base!);
      final healer = ControllerDefaultsHealer(
        repo: svc,
        isLan: true,
        controllerIp: Uri.parse(base!).host,
        ctx: ControllerHealContext(
          profileLat: null,
          profileLon: null,
          ianaTimezone: null,
          resolvePhonePosition: () async => null,
          now: DateTime.now,
          phoneUtcOffset: Duration.zero,
        ),
        gammaAction: (_) async => WledConfigPushResult.skipped('n/a'),
      );
      final report = await healer.runGeometryOnly(trigger: 'uptimeDrop');
      expect(report.geometryReprovisioned, isTrue, reason: report.log.join('; '));
      expect(report.log.join(' '), contains('uptimeDrop'));
      expect(report.log.join(' '), contains('look copied to [1]'));
      expect(posted, hasLength(1));
    });

    test('the healer\'s geometry-only run on a healthy layout writes nothing',
        () async {
      if (base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      final svc = WledService(base!);
      final healer = ControllerDefaultsHealer(
        repo: svc,
        isLan: true,
        controllerIp: Uri.parse(base!).host,
        ctx: ControllerHealContext(
          profileLat: null,
          profileLon: null,
          ianaTimezone: null,
          resolvePhonePosition: () async => null,
          now: DateTime.now,
          phoneUtcOffset: Duration.zero,
        ),
        gammaAction: (_) async => WledConfigPushResult.skipped('n/a'),
      );
      final report = await healer.runGeometryOnly(trigger: 'coldStart');
      expect(report.geometryReprovisioned, isFalse);
      expect(posted, isEmpty);
    });
  });
}
