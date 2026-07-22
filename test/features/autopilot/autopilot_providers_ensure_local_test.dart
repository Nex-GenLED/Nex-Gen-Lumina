// test/features/autopilot/autopilot_providers_ensure_local_test.dart
//
// Pins the Item #79 fix: ensureLocalTime must treat already-local DateTimes
// (e.g. the ones returned by SunUtils.sunsetLocal()) as no-ops instead of
// re-interpreting their wall-clock components as UTC. Before the fix, a
// local 20:31 was rebuilt as DateTime.utc(..., 20, 31) and then converted
// back to local, which subtracted the device's UTC offset and produced
// wrong display times like 15:31 in Central time.
//
// The unit under test is the top-level pure function `ensureLocalTime`
// extracted from lib/features/autopilot/autopilot_providers.dart and
// exposed via @visibleForTesting — same pattern as
// computeEnabledConfigsForTeam in Item #80.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';

void main() {
  group('ensureLocalTime', () {
    test('returns already-local DateTime unchanged (Item #79 fix)', () {
      final local = DateTime(2026, 5, 23, 20, 31);
      expect(local.isUtc, isFalse,
          reason: 'precondition: DateTime() defaults to local');

      final result = ensureLocalTime(local, 'America/Chicago');

      expect(result, equals(local));
      expect(result.isUtc, isFalse);
      expect(result.hour, 20);
      expect(result.minute, 31);
    });

    test('Item #79 regression: local 20:31 must NOT become 15:31', () {
      // The bug rebuilt local 20:31 as DateTime.utc(..., 20, 31) then
      // converted back to local — subtracting the UTC offset. In Central
      // time (UTC-5 CDT), that produced 15:31. Pin the correct behavior:
      // the wall-clock components stay intact.
      final local = DateTime(2026, 5, 23, 20, 31);

      final result = ensureLocalTime(local, 'America/Chicago');

      expect(result.hour, 20, reason: 'hour must not shift by UTC offset');
      expect(result.minute, 31);
      expect(result.year, 2026);
      expect(result.month, 5);
      expect(result.day, 23);
    });

    test('local DateTime returned unchanged when timezone is null', () {
      final local = DateTime(2026, 5, 23, 20, 31);

      final result = ensureLocalTime(local, null);

      expect(result, equals(local));
      expect(result.isUtc, isFalse);
    });

    test('local DateTime returned unchanged when timezone is empty string',
        () {
      final local = DateTime(2026, 5, 23, 20, 31);

      final result = ensureLocalTime(local, '');

      expect(result, equals(local));
      expect(result.isUtc, isFalse);
    });

    test('UTC DateTime is converted to local representation', () {
      final utc = DateTime.utc(2026, 5, 23, 20, 31);
      expect(utc.isUtc, isTrue, reason: 'precondition');

      final result = ensureLocalTime(utc, null);

      expect(result.isUtc, isFalse, reason: 'must be flipped to local');
      expect(result.millisecondsSinceEpoch, equals(utc.millisecondsSinceEpoch),
          reason: 'represents the same moment in time');
    });

    test('UTC DateTime with unrecognized IANA name falls back to toLocal()',
        () {
      final utc = DateTime.utc(2026, 5, 23, 20, 31);

      final result = ensureLocalTime(utc, 'Not/A_Real_Zone');

      expect(result.isUtc, isFalse);
      expect(result.millisecondsSinceEpoch, equals(utc.millisecondsSinceEpoch),
          reason: 'fallback path preserves the moment');
    });
  });
}
