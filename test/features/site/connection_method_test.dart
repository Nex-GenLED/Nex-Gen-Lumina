import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/site/connection_method.dart';

void main() {
  group('ConnectionMethod round-trip', () {
    test('ethernet ↔ "ethernet"', () {
      expect(connectionMethodToJson(ConnectionMethod.ethernet), 'ethernet');
      expect(connectionMethodFromJson('ethernet'), ConnectionMethod.ethernet);
    });

    test('wifi ↔ "wifi"', () {
      expect(connectionMethodToJson(ConnectionMethod.wifi), 'wifi');
      expect(connectionMethodFromJson('wifi'), ConnectionMethod.wifi);
    });

    test('ethernetWifiActive ↔ "ethernet_wifi_active"', () {
      expect(connectionMethodToJson(ConnectionMethod.ethernetWifiActive),
          'ethernet_wifi_active');
      expect(connectionMethodFromJson('ethernet_wifi_active'),
          ConnectionMethod.ethernetWifiActive);
    });

    test('unknown ↔ "unknown"', () {
      expect(connectionMethodToJson(ConnectionMethod.unknown), 'unknown');
      expect(connectionMethodFromJson('unknown'), ConnectionMethod.unknown);
    });

    test('null / non-string / unrecognised string returns null', () {
      expect(connectionMethodFromJson(null), isNull);
      expect(connectionMethodFromJson(42), isNull);
      expect(connectionMethodFromJson('ethernet_wifi'), isNull,
          reason: 'legacy "ethernet_wifi" must not silently map to a new '
              'enum value — migration handles the rename');
      expect(connectionMethodFromJson(''), isNull);
    });
  });
}
