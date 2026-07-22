// test/features/wled/clock_health_test.dart
//
// BUG-CLOCK-1 — pure clock-health evaluator coverage. A controller with NTP
// enabled but never synced (1970 epoch / 2106 overflow), a UTC timezone, or a
// 0,0 location silently breaks scheduling. These tests pin each classification,
// the legitimate-UTC-user false-positive bound, solar gating of LOCATION_UNSET,
// the /json/info time parser, and the real bench (.250) states.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';

void main() {
  // A phone in US Central (UTC-5) at a fixed instant, used across tests.
  final phoneCentral = DateTime(2026, 7, 6, 13, 49, 41);
  const centralOffset = Duration(hours: -5);

  ControllerClockInfo device({
    DateTime? time,
    int? tz,
    int? offset,
    double? lat,
    double? lon,
  }) =>
      ControllerClockInfo(
        deviceTime: time,
        tzIndex: tz,
        tzOffsetSeconds: offset,
        latitude: lat,
        longitude: lon,
      );

  ClockHealth evalCentral(ControllerClockInfo d) => evaluateClockHealth(
        device: d,
        phoneNow: phoneCentral,
        phoneUtcOffset: centralOffset,
      );

  group('CLOCK_UNSET', () {
    test('1970 epoch → clockUnset', () {
      final h = evalCentral(device(
          time: DateTime(1970, 1, 1, 4, 47, 57), tz: 5, lat: 39, lon: -94));
      expect(h.clockUnset, isTrue);
    });

    test('2106 uint32 overflow sentinel → clockUnset', () {
      final h = evalCentral(device(
          time: DateTime(2106, 2, 7, 0, 46, 28), tz: 5, lat: 39, lon: -94));
      expect(h.clockUnset, isTrue);
    });

    test('null device time → clockUnset', () {
      expect(evalCentral(device(time: null, tz: 5)).clockUnset, isTrue);
    });

    test('sub-hour drift beyond threshold (same tz) → clockUnset', () {
      // 12 minutes off, no whole-hour offset → genuine drift.
      final h = evalCentral(device(
          time: phoneCentral.add(const Duration(minutes: 12)),
          tz: 5,
          lat: 39,
          lon: -94));
      expect(h.clockUnset, isTrue);
    });

    test('small drift under threshold → NOT clockUnset', () {
      final h = evalCentral(device(
          time: phoneCentral.add(const Duration(minutes: 3)),
          tz: 5,
          lat: 39,
          lon: -94));
      expect(h.clockUnset, isFalse);
      expect(h.isHealthy, isTrue);
    });

    test('whole-hour offset (wrong tz, synced clock) is NOT clockUnset', () {
      // Device shows UTC time (5h ahead of Central phone) but the clock itself
      // is correct — that must classify as TZ_SUSPECT, never CLOCK_UNSET.
      final h = evalCentral(device(
          time: phoneCentral.add(const Duration(hours: 5)),
          tz: 0,
          offset: 0,
          lat: 39,
          lon: -94));
      expect(h.clockUnset, isFalse);
      expect(h.tzSuspect, isTrue);
    });
  });

  group('TZ_SUSPECT (heuristic, warn-only)', () {
    test('UTC device + non-UTC phone → tzSuspect', () {
      final h = evalCentral(device(
          time: phoneCentral.add(const Duration(hours: 5)),
          tz: 0,
          offset: 0,
          lat: 39,
          lon: -94));
      expect(h.tzSuspect, isTrue);
    });

    test('legitimate UTC user (phone also UTC) → NO tzSuspect', () {
      final phoneUtc = DateTime(2026, 7, 6, 18, 49, 41);
      final h = evaluateClockHealth(
        device: device(time: phoneUtc, tz: 0, offset: 0, lat: 51, lon: 0.1),
        phoneNow: phoneUtc,
        phoneUtcOffset: Duration.zero,
      );
      expect(h.tzSuspect, isFalse);
      expect(h.clockUnset, isFalse);
    });

    test('non-UTC device tz → NO tzSuspect', () {
      final h = evalCentral(
          device(time: phoneCentral, tz: 5, offset: 0, lat: 39, lon: -94));
      expect(h.tzSuspect, isFalse);
    });

    test('tzSuspect suppressed when clock is unset', () {
      // 1970 + tz 0: the dominant problem is the dead clock, not the tz.
      final h = evalCentral(
          device(time: DateTime(1970, 1, 1), tz: 0, offset: 0, lat: 39, lon: -94));
      expect(h.clockUnset, isTrue);
      expect(h.tzSuspect, isFalse);
    });
  });

  group('LOCATION_UNSET', () {
    test('lat/lon both 0 → locationUnset', () {
      final h = evalCentral(
          device(time: phoneCentral, tz: 5, lat: 0, lon: 0));
      expect(h.locationUnset, isTrue);
    });

    test('location set → NO locationUnset', () {
      final h = evalCentral(
          device(time: phoneCentral, tz: 5, lat: 38.99, lon: -94.25));
      expect(h.locationUnset, isFalse);
      expect(h.isHealthy, isTrue);
    });
  });

  group('relay mode (tz/location unknown)', () {
    test('only clock evaluated; tz/location never false-flagged', () {
      // Relay gives device time only; cfg (tz/lat/lon) is null → unknown.
      final relay = ControllerClockInfo(deviceTime: phoneCentral);
      expect(relay.timezoneKnown, isFalse);
      expect(relay.locationKnown, isFalse);
      final h = evalCentral(relay);
      expect(h.tzSuspect, isFalse);
      expect(h.locationUnset, isFalse);
      expect(h.isHealthy, isTrue);
    });

    test('relay with a dead clock still flags clockUnset', () {
      final relay = ControllerClockInfo(deviceTime: DateTime(1970, 1, 1));
      expect(evalCentral(relay).clockUnset, isTrue);
    });
  });

  group('primaryIssueToSurface — banner-trigger + solar gating', () {
    test('clockUnset outranks everything', () {
      final h = ClockHealth({
        ClockHealthIssue.clockUnset,
        ClockHealthIssue.locationUnset,
      });
      expect(primaryIssueToSurface(h, solarRelevant: true),
          ClockHealthIssue.clockUnset);
    });

    test('tzSuspect outranks locationUnset', () {
      final h = ClockHealth({
        ClockHealthIssue.tzSuspect,
        ClockHealthIssue.locationUnset,
      });
      expect(primaryIssueToSurface(h, solarRelevant: true),
          ClockHealthIssue.tzSuspect);
    });

    test('locationUnset is HIDDEN when no solar schedules are relevant', () {
      final h = ClockHealth({ClockHealthIssue.locationUnset});
      expect(primaryIssueToSurface(h, solarRelevant: false), isNull);
    });

    test('locationUnset is SHOWN when solar is relevant', () {
      final h = ClockHealth({ClockHealthIssue.locationUnset});
      expect(primaryIssueToSurface(h, solarRelevant: true),
          ClockHealthIssue.locationUnset);
    });

    test('healthy → nothing to surface', () {
      expect(primaryIssueToSurface(const ClockHealth.healthy(),
          solarRelevant: true), isNull);
    });
  });

  group('isSolarTimeLabel', () {
    test('sunrise/sunset (any case) are solar', () {
      expect(isSolarTimeLabel('Sunrise'), isTrue);
      expect(isSolarTimeLabel('sunset'), isTrue);
      expect(isSolarTimeLabel('  SUNSET '), isTrue);
    });
    test('clock times and null are not solar', () {
      expect(isSolarTimeLabel('7:00 PM'), isFalse);
      expect(isSolarTimeLabel(null), isFalse);
      expect(isSolarTimeLabel(''), isFalse);
    });
  });

  group('parseWledDeviceTime', () {
    test('parses non-zero-padded WLED format', () {
      final dt = parseWledDeviceTime('2026-7-6, 13:49:41');
      expect(dt, DateTime(2026, 7, 6, 13, 49, 41));
    });
    test('parses the 1970 epoch string', () {
      expect(parseWledDeviceTime('1970-1-1, 04:47:57'),
          DateTime(1970, 1, 1, 4, 47, 57));
    });
    test('null / non-string / garbage → null', () {
      expect(parseWledDeviceTime(null), isNull);
      expect(parseWledDeviceTime(42), isNull);
      expect(parseWledDeviceTime('not a time'), isNull);
    });
  });

  group('ControllerClockInfo.fromMaps', () {
    test('reads info.time + cfg.if.ntp fields', () {
      final info = {'time': '2026-7-6, 13:49:41'};
      final cfg = {
        'if': {
          'ntp': {'tz': 5, 'offset': 0, 'lt': 38.99, 'ln': -94.25}
        }
      };
      final c = ControllerClockInfo.fromMaps(info, cfg);
      expect(c.deviceTime, DateTime(2026, 7, 6, 13, 49, 41));
      expect(c.tzIndex, 5);
      expect(c.latitude, 38.99);
      expect(c.longitude, -94.25);
      expect(c.timezoneKnown, isTrue);
      expect(c.locationKnown, isTrue);
    });

    test('no cfg → time only, tz/location unknown (relay shape)', () {
      final c = ControllerClockInfo.fromMaps(
          {'time': '2026-7-6, 13:49:41'}, null);
      expect(c.deviceTime, isNotNull);
      expect(c.timezoneKnown, isFalse);
      expect(c.locationKnown, isFalse);
      expect(c.bootPresetId, isNull);
      expect(c.turnOnAtBoot, isNull);
    });

    test('reads cfg.def boot defaults (healer reboot gate)', () {
      // Shape from a live controller dump: "def":{"ps":0,"on":true,"bri":128}.
      final c = ControllerClockInfo.fromMaps(
        {'time': '2026-7-6, 13:49:41'},
        {
          'def': {'ps': 0, 'on': true, 'bri': 128},
        },
      );
      expect(c.bootPresetId, 0); // 0 = no boot preset
      expect(c.turnOnAtBoot, true);
    });

    test('missing/malformed cfg.def → boot defaults null (never throws)', () {
      expect(ControllerClockInfo.fromMaps({}, {}).turnOnAtBoot, isNull);
      expect(ControllerClockInfo.fromMaps({}, {'def': 'nope'}).bootPresetId,
          isNull);
      final c = ControllerClockInfo.fromMaps({}, {
        'def': {'ps': 'x', 'on': 1},
      });
      expect(c.bootPresetId, isNull);
      expect(c.turnOnAtBoot, isNull);
    });
  });

  group('user-facing copy is present for every issue', () {
    for (final issue in ClockHealthIssue.values) {
      test('${issue.name} has message + remediation', () {
        expect(clockHealthMessage(issue), isNotEmpty);
        expect(clockHealthRemediation(issue), isNotEmpty);
      });
    }
  });

  group('bench (.250) states — real dumps through the evaluator', () {
    test('pre-fix 1970 state reads CLOCK_UNSET', () {
      // The exact pre-fix bench: NTP enabled but never synced.
      final c = ControllerClockInfo.fromMaps(
        {'time': '1970-1-1, 04:47:57'},
        {'if': {'ntp': {'tz': 0, 'offset': 0, 'lt': 0.0, 'ln': 0.0}}},
      );
      final h = evalCentral(c);
      expect(h.clockUnset, isTrue);
      expect(primaryIssueToSurface(h, solarRelevant: true),
          ClockHealthIssue.clockUnset);
    });

    test('post-powercycle 2106 overflow (NTP still unsynced) reads CLOCK_UNSET',
        () {
      final c = ControllerClockInfo.fromMaps(
        {'time': '2106-2-7, 00:46:28'},
        {'if': {'ntp': {'tz': 5, 'offset': 0, 'lt': 38.99, 'ln': -94.25}}},
      );
      expect(evalCentral(c).clockUnset, isTrue);
    });

    test('simulated fixed bench (synced 2026, tz Central, KC location) reads HEALTHY',
        () {
      final c = ControllerClockInfo.fromMaps(
        {'time': '2026-7-6, 13:49:41'},
        {'if': {'ntp': {'tz': 5, 'offset': 0, 'lt': 38.99, 'ln': -94.25}}},
      );
      expect(evalCentral(c).isHealthy, isTrue);
    });
  });
}
