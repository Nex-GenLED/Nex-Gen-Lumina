// Tests for [path1GameDaySnapshotResolutionProvider] — the 3-state
// Riverpod provider that replaced the original 2-state
// path1GameDaySnapshotProvider. The new shape distinguishes
// AsyncLoading from "no config" so callers can never collapse the
// two (the 1b configure-twice regression sentinel).
//
// Strategy: override the upstream [gameDayAutopilotConfigsProvider]
// (a StreamProvider) with controlled streams — never-emitting (stays
// loading), Stream.value (data), Stream.error (errored).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/neighborhood/services/path1_game_day_snapshot.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

GameDayAutopilotConfig _configFor({
  String teamSlug = 'mlb_royals',
  String teamName = 'Kansas City Royals',
}) {
  final created = DateTime.utc(2026, 5, 1);
  return GameDayAutopilotConfig(
    teamSlug: teamSlug,
    teamName: teamName,
    espnTeamId: '7',
    sport: SportType.mlb,
    primaryColorValue: 0xFF004687,
    secondaryColorValue: 0xFFBD9B60,
    effectId: 52,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  group('path1GameDaySnapshotResolutionProvider', () {
    test(
        'Loading: returns Path1SnapshotLoading while the configs stream '
        'has not emitted yet (1b regression sentinel — must NOT collapse '
        'to Absent here)', () async {
      final controller =
          StreamController<List<GameDayAutopilotConfig>>();
      addTearDown(controller.close);

      final container = ProviderContainer(overrides: [
        gameDayAutopilotConfigsProvider
            .overrideWith((ref) => controller.stream),
      ]);
      addTearDown(container.dispose);

      final result = container
          .read(path1GameDaySnapshotResolutionProvider('mlb_royals'));

      expect(result, isA<Path1SnapshotLoading>());
      expect(result, isNot(isA<Path1SnapshotAbsent>()),
          reason: 'collapsing loading to Absent is the bug that caused '
              'tapping a configured team mid-stream-load to deep-link to '
              'the Fan Zone builder on Pulla');
    });

    test(
        'Ready: returns Path1SnapshotReady with the snapshot when the '
        'configs stream emits a matching team', () async {
      final container = ProviderContainer(overrides: [
        gameDayAutopilotConfigsProvider.overrideWith(
          (ref) => Stream.value([_configFor(teamSlug: 'mlb_royals')]),
        ),
      ]);
      addTearDown(container.dispose);

      // Settle the stream so AsyncValue moves from Loading → Data.
      await container.read(gameDayAutopilotConfigsProvider.future);

      final result = container
          .read(path1GameDaySnapshotResolutionProvider('mlb_royals'));

      expect(result, isA<Path1SnapshotReady>());
      expect(
        (result as Path1SnapshotReady).snapshot.teamSlug,
        'mlb_royals',
      );
      expect(result.snapshot.teamName, 'Kansas City Royals');
    });

    test(
        'Absent: returns Path1SnapshotAbsent (carrying the slug) when '
        'the stream emits but the requested team is not in the list',
        () async {
      final container = ProviderContainer(overrides: [
        gameDayAutopilotConfigsProvider.overrideWith(
          (ref) => Stream.value([_configFor(teamSlug: 'nhl_avalanche')]),
        ),
      ]);
      addTearDown(container.dispose);

      await container.read(gameDayAutopilotConfigsProvider.future);

      final result = container
          .read(path1GameDaySnapshotResolutionProvider('mlb_royals'));

      expect(result, isA<Path1SnapshotAbsent>());
      expect((result as Path1SnapshotAbsent).teamSlug, 'mlb_royals',
          reason: 'team slug carried through for deep-link target');
    });

    test(
        'Absent: errored stream folds to Path1SnapshotAbsent — the user '
        'can re-attempt setup rather than be stuck on a spinner',
        () async {
      final container = ProviderContainer(overrides: [
        gameDayAutopilotConfigsProvider.overrideWith(
          (ref) => Stream.error(StateError('boom')),
        ),
      ]);
      addTearDown(container.dispose);

      // Settle the error. .future throws on AsyncError; swallow it.
      try {
        await container.read(gameDayAutopilotConfigsProvider.future);
      } catch (_) {/* expected */}

      final result = container
          .read(path1GameDaySnapshotResolutionProvider('mlb_royals'));

      expect(result, isA<Path1SnapshotAbsent>());
    });

    test(
        'transitions through Loading → Ready as the stream emits — the '
        'shared upstream means badge + tap derive from the same signal',
        () async {
      final controller =
          StreamController<List<GameDayAutopilotConfig>>();
      addTearDown(controller.close);

      final container = ProviderContainer(overrides: [
        gameDayAutopilotConfigsProvider
            .overrideWith((ref) => controller.stream),
      ]);
      addTearDown(container.dispose);

      // Subscribe so the provider stays alive across the transition.
      container.listen(
        path1GameDaySnapshotResolutionProvider('mlb_royals'),
        (_, __) {},
      );

      // Before emission: Loading.
      expect(
        container.read(path1GameDaySnapshotResolutionProvider('mlb_royals')),
        isA<Path1SnapshotLoading>(),
      );

      // Emit configs containing the team.
      controller.add([_configFor(teamSlug: 'mlb_royals')]);
      // Give the StreamProvider a microtask to absorb the emission.
      await Future.delayed(Duration.zero);

      expect(
        container.read(path1GameDaySnapshotResolutionProvider('mlb_royals')),
        isA<Path1SnapshotReady>(),
      );
    });
  });
}
