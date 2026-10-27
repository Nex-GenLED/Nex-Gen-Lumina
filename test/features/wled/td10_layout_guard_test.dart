// TD-10 narrow fix (build 122): before a multi-segment apply on the LAN, a
// collapsed layout is re-provisioned from the controller's own buses, then the
// apply is sent. Two fixtures drive the REAL WledService against a loopback
// fake controller (the harness is the one apply_payload_size_cap_test uses):
//   • two-channel layout        → exactly one POST, the look, no bounds;
//   • one segment after restart → a bounds-only POST first, then the look.
// A single-segment apply on a collapsed controller is left alone (narrow).
// Synthetic addresses and ids only.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/segment_layout_guard.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kProbePath = '/__loopback_probe';

/// A host this environment can reach that WledService will not treat as a
/// simulation host (127.0.0.1 / localhost short-circuit to simulation).
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

Map<String, dynamic> _seg(int id, int start, int stop) => {
      'id': id,
      'start': start,
      'stop': stop,
      'len': stop - start,
      'on': false,
      'frz': false,
      'bri': 255,
      'fx': 0,
      'sx': 128,
      'ix': 128,
      'pal': 0,
      'col': [
        [255, 160, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0]
      ],
    };

/// The look a two-channel favorite sends: ids 0 and 1, no bounds.
Map<String, dynamic> _twoChannelLook() => {
      'on': true,
      'seg': [
        {
          'id': 0,
          'on': true,
          'fx': 0,
          'col': [
            [255, 255, 255, 0]
          ]
        },
        {
          'id': 1,
          'on': true,
          'fx': 0,
          'col': [
            [255, 255, 255, 0]
          ]
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the pure decisions', () {
    final expected = expectedBoundsFromChannels(const [
      DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 90, gpioPin: 2),
      DeviceChannel(id: 1, name: 'Channel 2', start: 90, stop: 180, gpioPin: 14),
    ]);

    test('addressed ids come only from seg entries that name an id', () {
      expect(addressedSegmentIds(_twoChannelLook()), [0, 1]);
      expect(
          addressedSegmentIds({
            'seg': [
              {'fx': 0}
            ]
          }),
          isEmpty);
      expect(addressedSegmentIds({'on': false}), isEmpty);
    });

    test('live ids are the segments that exist (stop > start); no seg list → '
        'unknown', () {
      expect(liveSegmentIds({'seg': [_seg(0, 0, 90), _seg(1, 90, 180)]}),
          {0, 1});
      expect(liveSegmentIds({'seg': [_seg(0, 0, 180)]}), {0});
      expect(liveSegmentIds({'on': false}), isNull);
      expect(liveSegmentIds(null), isNull);
    });

    test('two-channel layout → no repair; one segment after a restart → repair; '
        'unknown layout or a bus set without the segment → no repair', () {
      expect(
          needsLayoutRepairBeforeApply(
              addressed: [0, 1], live: {0, 1}, expected: expected),
          isFalse);
      expect(
          needsLayoutRepairBeforeApply(
              addressed: [0, 1], live: {0}, expected: expected),
          isTrue);
      expect(
          needsLayoutRepairBeforeApply(
              addressed: [0, 1], live: null, expected: expected),
          isFalse,
          reason: 'stood aside on ignorance');
      expect(
          needsLayoutRepairBeforeApply(
              addressed: [0, 1],
              live: {0},
              expected: expectedBoundsFromChannels(
                  const [DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 180, gpioPin: 2)])),
          isFalse,
          reason: 'the buses define one segment: the apply is wrong, not the layout');
      expect(
          needsLayoutRepairBeforeApply(
              addressed: [0], live: {0}, expected: expected),
          isFalse,
          reason: 'single-segment applies are not the guard\'s business');
    });

    test('the re-provision body is bounds only', () {
      expect(geometryPayload(expected), {
        'seg': [
          {'id': 0, 'start': 0, 'stop': 90},
          {'id': 1, 'start': 90, 'stop': 180},
        ]
      });
    });
  });

  group('the real service against a fake controller', () {
    late HttpServer server;
    late List<Map<String, dynamic>> posted;
    late Map<String, dynamic> stateFixture;
    late int stateGets;
    String? base;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      resetWledHttpClientsForTest();
      posted = [];
      stateGets = 0;
      stateFixture = {
        'on': false,
        'bri': 200,
        'ps': 2,
        'seg': [_seg(0, 0, 90), _seg(1, 90, 180)],
      };
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      server.listen((req) async {
        final path = req.uri.path;
        if (path == _kProbePath) {
          req.response.statusCode = 200;
          await req.response.close();
          return;
        }
        if (req.method == 'POST') {
          posted.add(jsonDecode(await utf8.decoder.bind(req).join())
              as Map<String, dynamic>);
          req.response.statusCode = 200;
          req.response.write('{"success":true}');
          await req.response.close();
          return;
        }
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        if (path == '/json/state') {
          stateGets++;
          req.response.write(jsonEncode(stateFixture));
        } else if (path == '/json/cfg') {
          req.response.write(jsonEncode({
            'hw': {
              'led': {
                'fps': 42,
                'ins': [
                  {
                    'start': 0,
                    'len': 90,
                    'pin': [2],
                    'type': 30
                  },
                  {
                    'start': 90,
                    'len': 90,
                    'pin': [14],
                    'type': 30
                  },
                ]
              }
            }
          }));
        } else if (path == '/json/info') {
          req.response.write(jsonEncode({
            'ver': '0.15.4',
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

    List<Map<String, dynamic>> segsOf(Map<String, dynamic> body) =>
        (body['seg'] as List).cast<Map<String, dynamic>>();

    test('two-channel layout: exactly one POST, the look, no bounds', () async {
      if (base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      final svc = WledService(base!);
      expect(await svc.applyJson(_twoChannelLook()), isTrue);
      expect(posted, hasLength(1));
      final segs = segsOf(posted.single);
      expect(segs.map((s) => s['id']), [0, 1]);
      for (final s in segs) {
        expect(s.containsKey('start'), isFalse);
        expect(s.containsKey('stop'), isFalse);
        expect(s['fx'], 0);
      }
    });

    test('one segment after a restart: a bounds-only POST from the buses, then '
        'the look addressing both segments', () async {
      if (base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      stateFixture['seg'] = [_seg(0, 0, 180)];
      final svc = WledService(base!);
      expect(await svc.applyJson(_twoChannelLook()), isTrue);
      expect(stateGets, 1, reason: 'no poll yet, so the guard read the layout itself');
      expect(posted, hasLength(2), reason: 'repair first, then the look');
      expect(posted.first, {
        'seg': [
          {'id': 0, 'start': 0, 'stop': 90},
          {'id': 1, 'start': 90, 'stop': 180},
        ]
      });
      final look = segsOf(posted.last);
      expect(look.map((s) => s['id']), [0, 1]);
      for (final s in look) {
        expect(s.containsKey('start'), isFalse);
        expect(s['fx'], 0);
      }
    });

    test('the poller\'s last state is the hint: a fresh read primes it and the '
        'guard adds no read of its own', () async {
      if (base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      stateFixture['seg'] = [_seg(0, 0, 180)];
      final svc = WledService(base!);
      expect(await svc.getState(), isNotNull); // what the dashboard poll does
      expect(stateGets, 1);
      expect(await svc.applyJson(_twoChannelLook()), isTrue);
      expect(stateGets, 1, reason: 'the guard used the poll\'s layout');
      expect(posted, hasLength(2));
      expect(posted.first.containsKey('seg'), isTrue);
      expect(segsOf(posted.first).first['stop'], 90);
    });

    test('a single-segment apply on a collapsed controller is left alone '
        '(narrow fix)', () async {
      if (base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      stateFixture['seg'] = [_seg(0, 0, 180)];
      final svc = WledService(base!);
      expect(
          await svc.applyJson({
            'on': true,
            'seg': [
              {
                'id': 0,
                'on': true,
                'fx': 0,
                'col': [
                  [255, 255, 255, 0]
                ]
              }
            ]
          }),
          isTrue);
      expect(posted, hasLength(1));
      expect(posted.single.containsKey('seg'), isTrue);
      expect(segsOf(posted.single).single.containsKey('start'), isFalse);
    });
  });
}
