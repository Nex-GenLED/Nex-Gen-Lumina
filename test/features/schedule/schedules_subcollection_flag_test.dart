// test/features/schedule/schedules_subcollection_flag_test.dart
//
// A-7 — staged-rollout gating for schedules_subcollection. Covers the pure
// resolution (global / allowlist / percentage), the stable bucket, and the
// defensive-false parse for every degraded field/shape.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedules_subcollection_feature_flag.dart';

void main() {
  group('schedulesSubcollectionBucket — stable + in range', () {
    test('always in [0, 100)', () {
      for (final uid in ['a', 'founder-uid', 'x' * 40, '0', 'ünïcodé']) {
        final b = schedulesSubcollectionBucket(uid);
        expect(b, inInclusiveRange(0, 99));
      }
    });

    test('same uid → same bucket across calls (stable)', () {
      const uid = 'stable-uid-123';
      expect(schedulesSubcollectionBucket(uid), schedulesSubcollectionBucket(uid));
    });
  });

  group('resolveSchedulesSubcollectionEnabled', () {
    test('global enabled → true for every uid, including null', () {
      const cfg = SchedulesSubcollectionConfig(enabled: true);
      expect(resolveSchedulesSubcollectionEnabled(cfg, 'anyone'), isTrue);
      expect(resolveSchedulesSubcollectionEnabled(cfg, null), isTrue);
      expect(resolveSchedulesSubcollectionEnabled(cfg, ''), isTrue);
    });

    test('allowlist → true only for listed uid', () {
      const cfg = SchedulesSubcollectionConfig(allowlistUids: ['founder', 'canary']);
      expect(resolveSchedulesSubcollectionEnabled(cfg, 'founder'), isTrue);
      expect(resolveSchedulesSubcollectionEnabled(cfg, 'canary'), isTrue);
      expect(resolveSchedulesSubcollectionEnabled(cfg, 'someone-else'), isFalse);
      expect(resolveSchedulesSubcollectionEnabled(cfg, null), isFalse);
    });

    test('percentage boundary — < threshold in, == threshold out', () {
      const uid = 'percent-boundary-uid';
      final bucket = schedulesSubcollectionBucket(uid);
      // rolloutPercent == bucket → bucket < bucket is FALSE → excluded.
      expect(
          resolveSchedulesSubcollectionEnabled(
              SchedulesSubcollectionConfig(rolloutPercent: bucket), uid),
          isFalse);
      // rolloutPercent == bucket + 1 → bucket < bucket+1 is TRUE → included.
      expect(
          resolveSchedulesSubcollectionEnabled(
              SchedulesSubcollectionConfig(rolloutPercent: bucket + 1), uid),
          isTrue);
    });

    test('percentage is stable for the same uid across calls', () {
      const uid = 'percent-stable-uid';
      final cfg = SchedulesSubcollectionConfig(
          rolloutPercent: schedulesSubcollectionBucket(uid) + 1);
      expect(resolveSchedulesSubcollectionEnabled(cfg, uid), isTrue);
      expect(resolveSchedulesSubcollectionEnabled(cfg, uid), isTrue);
    });

    test('rolloutPercent 100 → every uid in; 0 → none via percentage', () {
      for (final uid in ['a', 'b', 'c', 'zzz', 'founder']) {
        expect(
            resolveSchedulesSubcollectionEnabled(
                const SchedulesSubcollectionConfig(rolloutPercent: 100), uid),
            isTrue);
        expect(
            resolveSchedulesSubcollectionEnabled(
                const SchedulesSubcollectionConfig(rolloutPercent: 0), uid),
            isFalse);
      }
    });

    test('percentage needs a uid — null/empty never in via percent', () {
      const cfg = SchedulesSubcollectionConfig(rolloutPercent: 100);
      expect(resolveSchedulesSubcollectionEnabled(cfg, null), isFalse);
      expect(resolveSchedulesSubcollectionEnabled(cfg, ''), isFalse);
    });

    test('empty config → false for any uid (stream-error / loading posture)', () {
      // A stream error / loading window yields SchedulesSubcollectionConfig.empty.
      expect(resolveSchedulesSubcollectionEnabled(
          SchedulesSubcollectionConfig.empty, 'anyone'), isFalse);
      expect(resolveSchedulesSubcollectionEnabled(
          SchedulesSubcollectionConfig.empty, null), isFalse);
    });
  });

  group('parseSchedulesSubcollectionConfig — defensive-false', () {
    test('whole doc missing (null data) → empty → false', () {
      final cfg = parseSchedulesSubcollectionConfig(null);
      expect(cfg.enabled, isFalse);
      expect(cfg.allowlistUids, isEmpty);
      expect(cfg.rolloutPercent, 0);
      expect(resolveSchedulesSubcollectionEnabled(cfg, 'u'), isFalse);
    });

    test('all-empty doc → false', () {
      final cfg = parseSchedulesSubcollectionConfig(
          {'enabled': false, 'allowlistUids': <String>[], 'rolloutPercent': 0});
      expect(resolveSchedulesSubcollectionEnabled(cfg, 'u'), isFalse);
    });

    test('non-bool enabled → false', () {
      expect(parseSchedulesSubcollectionConfig({'enabled': 'true'}).enabled, isFalse);
      expect(parseSchedulesSubcollectionConfig({'enabled': 1}).enabled, isFalse);
      expect(parseSchedulesSubcollectionConfig({'enabled': null}).enabled, isFalse);
    });

    test('non-list allowlistUids → empty; non-string entries filtered', () {
      expect(parseSchedulesSubcollectionConfig({'allowlistUids': 'nope'}).allowlistUids,
          isEmpty);
      expect(
          parseSchedulesSubcollectionConfig({'allowlistUids': ['a', 1, null, 'b']})
              .allowlistUids,
          ['a', 'b']);
    });

    test('non-int / out-of-range rolloutPercent → 0 / clamped', () {
      expect(parseSchedulesSubcollectionConfig({'rolloutPercent': '50'}).rolloutPercent, 0);
      expect(parseSchedulesSubcollectionConfig({'rolloutPercent': 3.5}).rolloutPercent, 0);
      expect(parseSchedulesSubcollectionConfig({'rolloutPercent': 150}).rolloutPercent, 100);
      expect(parseSchedulesSubcollectionConfig({'rolloutPercent': -5}).rolloutPercent, 0);
      expect(parseSchedulesSubcollectionConfig({'rolloutPercent': 42}).rolloutPercent, 42);
    });

    test('parsed valid staged config resolves as expected', () {
      final cfg = parseSchedulesSubcollectionConfig({
        'enabled': false,
        'allowlistUids': ['founder'],
        'rolloutPercent': 100,
      });
      expect(resolveSchedulesSubcollectionEnabled(cfg, 'founder'), isTrue); // allowlist
      expect(resolveSchedulesSubcollectionEnabled(cfg, 'random'), isTrue); // 100%
      expect(resolveSchedulesSubcollectionEnabled(cfg, null), isFalse); // needs uid
    });
  });
}
