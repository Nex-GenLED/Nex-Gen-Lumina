// test/helpers/fake_lan_controller.dart
//
// A stateful loopback "controller" for tests that drive the REAL WledService:
// GET /json/state, /json/cfg, /json/info and POST /json/state. A provisioning
// POST re-binds the segments it names (a segment it creates comes up in the
// firmware's default amber unless the body carries a look), so a read-back
// shows what landed. Knobs: drop the first N POSTs (accepted, not applied),
// make the cfg unreadable. Synthetic addresses only: the host is a loopback
// alias or a LAN interface of the test machine, chosen at bind time, because
// WledService treats 127.0.0.1 / localhost as the simulated controller.

import 'dart:convert';
import 'dart:io';

const String kLoopbackProbePath = '/__loopback_probe';

Future<String?> reachableNonSimHost(int port) async {
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
      final req = await client
          .getUrl(Uri.parse('http://$host:$port$kLoopbackProbePath'));
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

/// A live segment entry as `/json/state` reports it.
Map<String, dynamic> lanSeg(int id, int start, int stop,
        {List<int>? col, int fx = 0, bool on = true, int bri = 255}) =>
    {
      'id': id,
      'start': start,
      'stop': stop,
      'len': stop - start,
      'on': on,
      'frz': false,
      'bri': bri,
      'fx': fx,
      'sx': 128,
      'ix': 128,
      'pal': 0,
      'col': [
        col ?? [227, 24, 55, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0]
      ],
    };

const List<int> kFirmwareDefaultAmber = [255, 160, 0, 0];

/// Two buses of 90: segments 0 [0,90) and 1 [90,180).
const Map<String, dynamic> kTwoBusCfg = {
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

class FakeLanController {
  FakeLanController({
    required this.segs,
    this.cfg = kTwoBusCfg,
    this.dropFirstPosts = 0,
    this.cfgReadable = true,
    this.uptime = 4242,
  });

  List<Map<String, dynamic>> segs;
  Map<String, dynamic> cfg;
  int dropFirstPosts;
  bool cfgReadable;
  int uptime;

  final List<Map<String, dynamic>> posted = [];
  int stateGets = 0;
  HttpServer? _server;

  /// `http://host:port`, or null when no non-simulation host is reachable.
  String? base;

  Future<void> start() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen(_handle);
    final host = await reachableNonSimHost(server.port);
    base = host == null ? null : 'http://$host:${server.port}';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void applyBody(Map<String, dynamic> body) {
    final seg = body['seg'];
    if (seg is! List) return;
    for (final s in seg.cast<Map<String, dynamic>>()) {
      if (s['id'] is! int) continue;
      final id = s['id'] as int;
      final idx = segs.indexWhere((l) => l['id'] == id);
      final hasBounds = s['start'] is int && s['stop'] is int;
      if (idx < 0 && !hasBounds) continue; // the firmware drops an unknown id
      final base = idx >= 0 ? segs[idx] : lanSeg(id, 0, 0, col: kFirmwareDefaultAmber);
      final merged = <String, dynamic>{...base, ...s};
      merged['len'] = (merged['stop'] as int) - (merged['start'] as int);
      if (idx >= 0) {
        segs[idx] = merged;
      } else {
        segs.add(merged);
      }
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    if (path == kLoopbackProbePath) {
      req.response.statusCode = 200;
      await req.response.close();
      return;
    }
    if (req.method == 'POST') {
      final body = jsonDecode(await utf8.decoder.bind(req).join())
          as Map<String, dynamic>;
      posted.add(body);
      if (dropFirstPosts > 0) {
        dropFirstPosts--;
      } else {
        applyBody(body);
      }
      req.response.statusCode = 200;
      req.response.write('{"success":true}');
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType.json;
    if (path == '/json/state') {
      stateGets++;
      req.response.write(jsonEncode({'on': true, 'bri': 200, 'seg': segs}));
    } else if (path == '/json/cfg') {
      if (!cfgReadable) {
        req.response.statusCode = 500;
      } else {
        req.response.write(jsonEncode(cfg));
      }
    } else if (path == '/json/info') {
      req.response.write(jsonEncode({
        'ver': '0.15.4',
        'uptime': uptime,
        'leds': {'count': 180, 'fps': 42},
        'mac': 'aa00000000a1',
      }));
    } else {
      req.response.write('{}');
    }
    await req.response.close();
  }
}
