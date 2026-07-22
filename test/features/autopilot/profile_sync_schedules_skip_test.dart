// test/features/autopilot/profile_sync_schedules_skip_test.dart
//
// A-5 coherence pin: AutopilotSettingsService's profile sync must NEVER fold
// the `schedules` field into a user-doc update. SchedulesNotifier owns schedule
// writes; while array↔subcollection dual-write is live, the profile snapshot's
// array can lag the latest schedule writes, so including it would clobber them.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';

void main() {
  group('computeChangedProfileFields — schedules skip', () {
    test('drops schedules even when it changed, keeps other changed fields', () {
      final oldJson = {
        'change_tolerance_level': 1,
        'schedules': [
          {'id': 'a', 'sortKey': 0}
        ],
      };
      final newJson = {
        'change_tolerance_level': 2,
        // A different schedules array — WOULD be diffed in without the skip.
        'schedules': [
          {'id': 'b', 'sortKey': 5}
        ],
      };

      final changed =
          AutopilotSettingsService.computeChangedProfileFields(oldJson, newJson);

      expect(changed.containsKey('schedules'), isFalse,
          reason: 'profile sync must never clobber the schedules array');
      expect(changed['change_tolerance_level'], 2);
    });

    test('unchanged non-schedule fields are excluded', () {
      final oldJson = {'a': 1, 'b': 1, 'schedules': <dynamic>[]};
      final newJson = {
        'a': 1,
        'b': 2,
        'schedules': [
          {'id': 'x'}
        ],
      };
      final changed =
          AutopilotSettingsService.computeChangedProfileFields(oldJson, newJson);
      expect(changed, {'b': 2});
    });

    test('a pure schedules change yields NO write (empty diff)', () {
      final oldJson = {
        'a': 1,
        'schedules': [
          {'id': 'a'}
        ]
      };
      final newJson = {
        'a': 1,
        'schedules': [
          {'id': 'a'},
          {'id': 'b'}
        ]
      };
      final changed =
          AutopilotSettingsService.computeChangedProfileFields(oldJson, newJson);
      expect(changed, isEmpty,
          reason: 'schedules-only delta must not trigger a profile update');
    });
  });
}
