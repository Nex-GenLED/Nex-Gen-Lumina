// test/features/autopilot/game_day_multi_team_test.dart
//
// Coverage for the multi-team Game Day calendar splice logic introduced
// in Item #80. The unit under test is the pure function
// `computeEnabledConfigsForTeam` extracted from
// lib/features/autopilot/game_day_autopilot_providers.dart — it
// captures the splice rule that lets a just-toggled team participate in
// the populate pass even when the Firestore stream hasn't yet propagated
// its config.
//
// The end-to-end clear-then-write loop in _doPopulateCalendars depends on
// providers (calendar notifier, Firestore, ESPN) that need a full
// container to exercise; the pure function is where the correctness of
// the multi-team semantics lives, so that's where the assertions are.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

GameDayAutopilotConfig _config({
  required String slug,
  bool enabled = true,
  SportType sport = SportType.mlb,
}) {
  final now = DateTime(2026, 5, 20, 12);
  return GameDayAutopilotConfig(
    teamSlug: slug,
    teamName: slug,
    espnTeamId: '0',
    sport: sport,
    primaryColorValue: 0xFF000000,
    secondaryColorValue: 0xFFFFFFFF,
    enabled: enabled,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('computeEnabledConfigsForTeam — single team', () {
    test('empty stream, no justWrittenConfig yields empty list', () {
      final result = computeEnabledConfigsForTeam(
        teamSlug: 'mlb_royals',
        streamConfigs: const [],
        justWrittenConfig: null,
      );
      expect(result, isEmpty);
    });

    test(
      'empty stream + enabled justWrittenConfig yields list with that one team '
      '(stream-lag scenario — the new team must still get populated)',
      () {
        final royals = _config(slug: 'mlb_royals');
        final result = computeEnabledConfigsForTeam(
          teamSlug: 'mlb_royals',
          streamConfigs: const [],
          justWrittenConfig: royals,
        );
        expect(result, [royals]);
      },
    );

    test('disabled justWrittenConfig is dropped (falls to stream fallback)',
        () {
      final royals = _config(slug: 'mlb_royals', enabled: false);
      final result = computeEnabledConfigsForTeam(
        teamSlug: 'mlb_royals',
        streamConfigs: const [],
        justWrittenConfig: royals,
      );
      expect(result, isEmpty);
    });
  });

  group('computeEnabledConfigsForTeam — multi-team', () {
    test(
      'enabling a second team (Royals after Fever) produces both teams in '
      'the populate set — Fever from stream, Royals via splice',
      () {
        final fever = _config(slug: 'wnba_fever');
        final royals = _config(slug: 'mlb_royals');
        // Stream still only knows about Fever; Royals was just written and
        // hasn't propagated yet.
        final result = computeEnabledConfigsForTeam(
          teamSlug: 'mlb_royals',
          streamConfigs: [fever],
          justWrittenConfig: royals,
        );
        expect(result, [fever, royals]);
      },
    );

    test(
      'stream already has both teams enabled — toggling Royals does NOT '
      'double-add Royals (EXCEPT-clause excludes the toggled team from '
      'the stream pass)',
      () {
        final fever = _config(slug: 'wnba_fever');
        final royalsInStream = _config(slug: 'mlb_royals');
        final royalsJustWritten = _config(slug: 'mlb_royals');
        final result = computeEnabledConfigsForTeam(
          teamSlug: 'mlb_royals',
          streamConfigs: [fever, royalsInStream],
          justWrittenConfig: royalsJustWritten,
        );
        expect(result, hasLength(2));
        expect(result, [fever, royalsJustWritten]);
      },
    );

    test(
      'just-written config takes precedence over the stale stream value for '
      'the same slug — e.g. user just flipped enabled from false to true',
      () {
        final staleRoyals = _config(slug: 'mlb_royals', enabled: false);
        // Stream still has the pre-toggle (disabled) value, but we just
        // wrote enabled=true. The splice should use the fresh one.
        final freshRoyals = _config(slug: 'mlb_royals', enabled: true);
        final result = computeEnabledConfigsForTeam(
          teamSlug: 'mlb_royals',
          streamConfigs: [staleRoyals],
          justWrittenConfig: freshRoyals,
        );
        expect(result, [freshRoyals]);
        expect(result.single.enabled, isTrue);
      },
    );

    test(
      'no justWrittenConfig — fall back to whatever the stream has for the '
      'target team (covers callers that don\'t hold the fresh config)',
      () {
        final fever = _config(slug: 'wnba_fever');
        final royals = _config(slug: 'mlb_royals');
        final result = computeEnabledConfigsForTeam(
          teamSlug: 'mlb_royals',
          streamConfigs: [fever, royals],
          justWrittenConfig: null,
        );
        expect(result, [fever, royals]);
      },
    );

    test('disabled teams in the stream are filtered out', () {
      final disabledFever = _config(slug: 'wnba_fever', enabled: false);
      final royals = _config(slug: 'mlb_royals');
      final result = computeEnabledConfigsForTeam(
        teamSlug: 'mlb_royals',
        streamConfigs: [disabledFever, royals],
        justWrittenConfig: null,
      );
      expect(result, [royals]);
    });
  });

  group('computeEnabledConfigsForTeam — ordering and stability', () {
    test(
      'three enabled teams produce three configs in iteration; toggled team '
      'goes last (stream-EXCEPT teams first, then the spliced one)',
      () {
        final fever = _config(slug: 'wnba_fever');
        final chiefs = _config(slug: 'nfl_chiefs', sport: SportType.nfl);
        final royals = _config(slug: 'mlb_royals');
        final result = computeEnabledConfigsForTeam(
          teamSlug: 'mlb_royals',
          streamConfigs: [fever, chiefs],
          justWrittenConfig: royals,
        );
        expect(result, hasLength(3));
        expect(result.last.teamSlug, 'mlb_royals');
        expect(
          result.map((c) => c.teamSlug).toSet(),
          {'wnba_fever', 'nfl_chiefs', 'mlb_royals'},
        );
      },
    );

    test(
      'toggling a team whose enabled state is still being written — stream '
      'shows the OLD value (disabled), justWritten is null because caller '
      'failed to splice. Result: target team is NOT populated (the bug we '
      'are fixing surfaces here). This documents the residual fallback risk '
      'when callers omit justWrittenConfig.',
      () {
        final staleRoyals = _config(slug: 'mlb_royals', enabled: false);
        final result = computeEnabledConfigsForTeam(
          teamSlug: 'mlb_royals',
          streamConfigs: [staleRoyals],
          justWrittenConfig: null,
        );
        expect(result, isEmpty);
      },
    );
  });
}
