// Live score-badge refresh (Game Day card). The badge WAS fed by a one-shot
// FutureProvider that snapshotted the score at card build and never refreshed
// ("never showed 1-0"). upcomingGameProvider is now a self-polling stream that
// refreshes every interval WHILE the game is live AND the app is foregrounded,
// and stops otherwise.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_providers.dart';
import 'package:nexgen_command/features/sports_alerts/models/game_state.dart';

GameState _game(int home, GameStatus status) => GameState(
      gameId: 'g1',
      homeTeam: 'H',
      awayTeam: 'A',
      homeTeamId: '1',
      awayTeamId: '2',
      homeScore: home,
      awayScore: 0,
      status: status,
      period: '2',
      lastUpdated: DateTime(2026, 1, 1),
    );

void main() {
  group('liveScoreRefreshInterval (pure)', () {
    test('live + foreground → poll', () {
      expect(
        liveScoreRefreshInterval(
            game: _game(0, GameStatus.inProgress), appForeground: true),
        kLiveScoreRefreshInterval,
      );
      expect(
        liveScoreRefreshInterval(
            game: _game(0, GameStatus.halftime), appForeground: true),
        kLiveScoreRefreshInterval,
      );
    });

    test('live but BACKGROUND → stop', () {
      expect(
        liveScoreRefreshInterval(
            game: _game(0, GameStatus.inProgress), appForeground: false),
        isNull,
      );
    });

    test('not live (scheduled / final) + foreground → stop', () {
      expect(
        liveScoreRefreshInterval(
            game: _game(0, GameStatus.scheduled), appForeground: true),
        isNull,
      );
      expect(
        liveScoreRefreshInterval(
            game: _game(3, GameStatus.final_), appForeground: true),
        isNull,
      );
    });

    test('null game → stop', () {
      expect(
        liveScoreRefreshInterval(game: null, appForeground: true),
        isNull,
      );
    });
  });

  group('upcomingGameProvider (self-polling stream)', () {
    // A fetcher that walks a queue, holding the last value once exhausted.
    Future<GameState?> Function(String) queueFetcher(List<GameState?> q) {
      var i = 0;
      return (_) async => q[i < q.length ? i++ : q.length - 1];
    }

    ProviderContainer containerWith({
      required Future<GameState?> Function(String) fetch,
      bool foreground = true,
    }) {
      final c = ProviderContainer(overrides: [
        liveScoreFetcherProvider.overrideWithValue(fetch),
        liveScorePollIntervalProvider
            .overrideWithValue(const Duration(milliseconds: 5)),
        appForegroundProvider.overrideWith((ref) => foreground),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    List<GameState?> listen(ProviderContainer c) {
      final got = <GameState?>[];
      c.listen<AsyncValue<GameState?>>(
        upcomingGameProvider('mlb_mets'),
        (_, next) => next.whenData(got.add),
        fireImmediately: true,
      );
      return got;
    }

    test('UPDATES on a score change while live (0 → 1)', () async {
      final c = containerWith(
        fetch: queueFetcher([
          _game(0, GameStatus.inProgress),
          _game(1, GameStatus.inProgress),
        ]),
      );
      final got = listen(c);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // The badge saw the score advance live — the whole point.
      expect(got.map((g) => g?.homeScore), containsAllInOrder([0, 1]));
    });

    test('STOPS polling when the game is not live (final → one emit)', () async {
      final c = containerWith(
        fetch: queueFetcher([_game(2, GameStatus.final_)]),
      );
      final got = listen(c);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Final is not live → fetched once, emitted once, then stopped.
      expect(got.map((g) => g?.homeScore), [2]);
    });

    test('STOPS when backgrounded from the start (one emit, no polling)',
        () async {
      final c = containerWith(
        fetch: queueFetcher([
          _game(0, GameStatus.inProgress),
          _game(1, GameStatus.inProgress),
        ]),
        foreground: false,
      );
      final got = listen(c);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Backgrounded → no repeat polling; never advances to score 1.
      expect(got.map((g) => g?.homeScore), [0]);
    });

    test('a background flip STOPS an in-flight live poll', () async {
      final c = containerWith(
        fetch: queueFetcher([
          for (var s = 0; s < 20; s++) _game(s, GameStatus.inProgress),
        ]),
      );
      final got = listen(c);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final countAtFlip = got.length;
      expect(countAtFlip, greaterThan(1), reason: 'was polling while live');

      // Background the app — the provider re-runs and the loop ends.
      c.read(appForegroundProvider.notifier).state = false;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // At most one more emission (the re-run's single fetch), then frozen.
      expect(got.length, lessThanOrEqualTo(countAtFlip + 1));
    });
  });
}
