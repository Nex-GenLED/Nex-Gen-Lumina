// A staging build must not change a bridge (lib/services/bridge_api_client.dart).
//
// Every Lumina Bridge is flashed for the PRODUCTION Firebase project. Pairing
// one from a staging build would write a staging uid into a real bridge's NVS
// and break that home's remote access. The block sits in the client, so no
// screen can get around it.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexgen_command/services/bridge_api_client.dart';

void main() {
  late List<http.Request> sent;
  late MockClient mock;

  setUp(() {
    sent = [];
    mock = MockClient((req) async {
      sent.add(req);
      return http.Response('{}', 200);
    });
  });

  test('default in a production build: writes allowed', () {
    expect(BridgeApiClient('http://192.0.2.20').allowsDeviceWrites, isTrue);
    expect(BridgeApiClient.fromIp('192.0.2.20').allowsDeviceWrites, isTrue);
  });

  test('production client still sends pair / reboot / reset', () async {
    await http.runWithClient(() async {
      final c = BridgeApiClient('http://192.0.2.20');
      expect(await c.pair(userId: 'u1', wledIp: '192.0.2.30'), isTrue);
      expect(await c.reboot(), isTrue);
      expect(await c.reset(), isTrue);
    }, () => mock);
    expect(sent.map((r) => r.url.path),
        ['/api/bridge/pair', '/api/reboot', '/api/reset']);
  });

  test('staging client sends NOTHING for pair / reboot / reset', () async {
    await http.runWithClient(() async {
      final c = BridgeApiClient('http://192.0.2.20', allowsDeviceWrites: false);
      expect(await c.pair(userId: 'u1', wledIp: '192.0.2.30'), isFalse);
      expect(await c.reboot(), isFalse);
      expect(await c.reset(), isFalse);
    }, () => mock);
    expect(sent, isEmpty);
  });

  test('staging client can still read (info, status, auth check)', () async {
    await http.runWithClient(() async {
      final c = BridgeApiClient('http://192.0.2.20', allowsDeviceWrites: false);
      await c.getInfo();
      await c.getStatus();
      await c.authenticate(userId: 'u1');
    }, () => mock);
    expect(sent.map((r) => r.url.path),
        ['/api/info', '/api/bridge/status', '/api/bridge/auth']);
  });
}
