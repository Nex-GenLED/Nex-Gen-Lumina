// test/services/time_location_payload_td7_test.dart
//
// TD-7 — the install push and Manage Controllers "Re-sync" send the profile
// zone through pushTimeLocation. A zone that does not map used to go out as
// `tz:0` (UTC), which a later heal pinned to a fixed offset. It must now leave
// the device zone alone: neither `tz` nor `offset` in the payload.

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
}
