import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/demo/demo_wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// #112 — the segment poller was a flat 3.0 s `Timer.periodic`; over the relay
/// every tick is a bridge command. It now runs every 15 s Direct, every 60 s
/// Via Bridge, and not at all while the app is backgrounded or the dashboard is
/// not on screen. What a tick does (`fetchSegments`) is unchanged.
class _CountingRepo extends DemoWledRepository {
  int fetches = 0;

  @override
  Future<List<WledSegment>> fetchSegments() async {
    fetches++;
    return const <WledSegment>[];
  }
}

final _remote = StateProvider<bool>((ref) => false);

void main() {
  group('ZoneSegmentsPollPolicy', () {
    test('Direct, foreground, dashboard visible → 15 s', () {
      expect(
        ZoneSegmentsPollPolicy.intervalFor(
            foreground: true, dashboardVisible: true, isRemote: false),
        const Duration(seconds: 15),
      );
    });

    test('Via Bridge, foreground, dashboard visible → 60 s', () {
      expect(
        ZoneSegmentsPollPolicy.intervalFor(
            foreground: true, dashboardVisible: true, isRemote: true),
        const Duration(seconds: 60),
      );
    });

    test('backgrounded → no polling, either route', () {
      for (final remote in [true, false]) {
        expect(
          ZoneSegmentsPollPolicy.intervalFor(
              foreground: false, dashboardVisible: true, isRemote: remote),
          isNull,
        );
      }
    });

    test('dashboard not on screen → no polling, either route', () {
      for (final remote in [true, false]) {
        expect(
          ZoneSegmentsPollPolicy.intervalFor(
              foreground: true, dashboardVisible: false, isRemote: remote),
          isNull,
        );
      }
    });

    test('both intervals are far slower than the old 3 s', () {
      expect(ZoneSegmentsPollPolicy.direct.inSeconds, greaterThanOrEqualTo(15));
      expect(ZoneSegmentsPollPolicy.viaBridge.inSeconds, greaterThanOrEqualTo(60));
    });
  });

  group('ZoneSegmentsNotifier timing (real timers, fake clock)', () {
    late _CountingRepo repo;
    late ProviderContainer container;
    late ProviderSubscription<AsyncValue<List<WledSegment>>> sub;

    Future<void> start(WidgetTester tester, {required bool remote}) async {
      repo = _CountingRepo();
      container = ProviderContainer(overrides: [
        wledRepositoryProvider.overrideWithValue(repo),
        isRemoteModeProvider.overrideWith((ref) => ref.watch(_remote)),
      ]);
      container.read(_remote.notifier).state = remote;
      sub = container.listen(zoneSegmentsProvider, (_, __) {});
      await tester.pump(); // initial fetch
      expect(repo.fetches, 1, reason: 'initial fetch on build');
    }

    Future<void> stop(WidgetTester tester) async {
      sub.close();
      container.dispose();
      await tester.pump();
    }

    testWidgets('Direct: one fetch per 15 s', (tester) async {
      await start(tester, remote: false);
      await tester.pump(const Duration(seconds: 14));
      expect(repo.fetches, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(repo.fetches, 2);
      await tester.pump(const Duration(seconds: 15));
      expect(repo.fetches, 3);
      await stop(tester);
    });

    testWidgets('Via Bridge: one fetch per 60 s (was one per 3 s)',
        (tester) async {
      await start(tester, remote: true);
      await tester.pump(const Duration(seconds: 59));
      expect(repo.fetches, 1, reason: 'the old poller would have fetched ~19 times');
      await tester.pump(const Duration(seconds: 1));
      expect(repo.fetches, 2);
      await stop(tester);
    });

    testWidgets('BACKGROUNDED: stops, and resumes on foreground',
        (tester) async {
      await start(tester, remote: false);
      container.read(appForegroundProvider.notifier).state = false;
      await tester.pump(const Duration(minutes: 10));
      expect(repo.fetches, 1, reason: 'no fetches while backgrounded');

      container.read(appForegroundProvider.notifier).state = true;
      await tester.pump(const Duration(seconds: 15));
      expect(repo.fetches, 2);
      await stop(tester);
    });

    testWidgets('DASHBOARD NOT VISIBLE (tab switched): stops, resumes when shown',
        (tester) async {
      await start(tester, remote: true);
      container.read(dashboardVisibleProvider.notifier).state = false;
      await tester.pump(const Duration(minutes: 10));
      expect(repo.fetches, 1, reason: 'no fetches while Home is not on screen');

      container.read(dashboardVisibleProvider.notifier).state = true;
      await tester.pump(const Duration(seconds: 60));
      expect(repo.fetches, 2);
      await stop(tester);
    });

    testWidgets('route flip Via Bridge → Direct reschedules at the Direct rate',
        (tester) async {
      await start(tester, remote: true);
      await tester.pump(const Duration(seconds: 10));
      container.read(_remote.notifier).state = false; // now Direct
      await tester.pump(const Duration(seconds: 15));
      expect(repo.fetches, 2, reason: 'fires 15 s after the flip, not 60 s after start');
      await stop(tester);
    });

    testWidgets('dispose cancels the pending refresh', (tester) async {
      await start(tester, remote: false);
      await stop(tester);
      await tester.pump(const Duration(minutes: 5));
      expect(repo.fetches, 1);
    });
  });
}
