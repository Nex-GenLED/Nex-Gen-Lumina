// test/services/time_location_payload_td7_test.dart
//
// TD-7 — the install push and Manage Controllers "Re-sync" send the profile
// zone through pushTimeLocation. A zone that does not map used to go out as
// `tz:0` (UTC), which a later heal pinned to a fixed offset. It must now leave
// the device zone alone: neither `tz` nor `offset` in the payload.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

Map<String, dynamic> _ntp(String? zone) => (buildTimeLocationPayload(
      latitude: 39.1,
      longitude: -94.5,
      ianaTimezone: zone,
    )['if'] as Map)['ntp'] as Map<String, dynamic>;

void main() {
  test('mapped zone → tz index with offset 0', () {
    final ntp = _ntp('America/Chicago');
    expect(ntp['tz'], 5);
    expect(ntp['offset'], 0);
  });

  test('abbreviation ("CDT") → no tz, no offset', () {
    final ntp = _ntp('CDT');
    expect(ntp.containsKey('tz'), false);
    expect(ntp.containsKey('offset'), false);
  });

  test('unmapped zone → no tz, no offset', () {
    final ntp = _ntp('Europe/Paris');
    expect(ntp.containsKey('tz'), false);
    expect(ntp.containsKey('offset'), false);
  });

  test('coordinates ride either way', () {
    for (final zone in ['America/Chicago', 'CDT']) {
      final ntp = _ntp(zone);
      expect(ntp['lt'], 39.1);
      expect(ntp['ln'], -94.5);
    }
  });

  // Build +121 (owner wording 2026-10-25): the warning an unmapped zone
  // produces is plain words and never shows the raw value. The install-finish
  // "Details" list and the Manage Controllers re-sync notice display push
  // warnings verbatim, so the sentence checked here is the sentence shown.
  group('the warning never shows the raw zone', () {
    test('the sentence is the owner\'s, with no quote and no abbreviation', () {
      expect(kTimeZoneNotRecognizedWarning,
          "Time zone not changed: this profile's zone isn't recognized yet.");
      expect(kTimeZoneNotRecognizedWarning, isNot(contains('"')));
      for (final raw in ['CDT', 'CST', 'EDT', 'EST', 'MDT', 'MST', 'PDT', 'PST']) {
        expect(kTimeZoneNotRecognizedWarning, isNot(contains(raw)));
      }
    });

    test('the real push against a fake controller: an abbreviation and an '
        'unmapped zone warn in those words with no raw value; a mapped zone '
        'does not warn', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final posted = <Map<String, dynamic>>[];
      server.listen((req) async {
        if (req.method == 'POST') {
          posted.add(jsonDecode(await utf8.decoder.bind(req).join())
              as Map<String, dynamic>);
          req.response.statusCode = 200;
          req.response.write('{"success":true}');
        } else {
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({
            'if': {
              'ntp': {'tz': 5, 'offset': 0, 'lt': 39.1, 'ln': -94.5}
            },
            'hw': {
              'led': {'fps': 42}
            },
          }));
        }
        await req.response.close();
      });
      final ip = '127.0.0.1:${server.port}';

      for (final raw in ['CDT', 'Europe/Paris']) {
        final r = await pushTimeLocation(ip,
            latitude: 39.1, longitude: -94.5, ianaTimezone: raw);
        expect(r.success, isTrue, reason: raw);
        expect(r.warnings, [kTimeZoneNotRecognizedWarning], reason: raw);
        expect(r.warnings.single, isNot(contains(raw)));
        expect(r.warnings.single, isNot(contains('"')));
        final ntp = (posted.last['if'] as Map)['ntp'] as Map;
        expect(ntp.containsKey('tz'), isFalse, reason: raw);
        expect(ntp.containsKey('offset'), isFalse, reason: raw);
      }

      final ok = await pushTimeLocation(ip,
          latitude: 39.1, longitude: -94.5, ianaTimezone: 'America/Chicago');
      expect(ok.success, isTrue);
      expect(ok.warnings, isEmpty);
      final ntp = (posted.last['if'] as Map)['ntp'] as Map;
      expect(ntp['tz'], 5);
      expect(ntp['offset'], 0);
    });
  });
}
