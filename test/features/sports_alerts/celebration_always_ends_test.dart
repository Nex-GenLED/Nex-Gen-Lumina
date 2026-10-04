// #170 — a celebration must always end.
//
// If the app is suspended, killed or backgrounded mid-celebration, the next
// resume (or cold start) reverts to the state captured before it — or the base
// look when that was lost — and nothing of a celebration plays past its
// clamped length plus a small margin. A house that was off stays off. A team
// the server runs is left to the server (observe only).

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart'
    show AlertAnimationStep;
import 'package:nexgen_command/features/sports_alerts/services/celebration_marker.dart';
import 'package:nexgen_command/features/sports_alerts/services/foreground_celebration_coordinator.dart';
import 'package:nexgen_command/features/sports_alerts/services/foreground_celebration_providers.dart';
import 'package:nexgen_command/features/sports_alerts/services/score_monitor_service.dart';
import 'package:nexgen_command/features/wled/base_look.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/recording_wled_repository.dart';

class _Monitor implements ScoreMonitor {
  final _c = StreamController<ScoreAlertEvent>.broadcast();
  @override
  Stream<ScoreAlertEvent> get alertStream => _c.stream;
  @override
  Future<void> checkScores(List<ScoreAlertConfig> c) async {}
  @override
  void reset() {}
}

class _Delivery implements CelebrationDelivery {
  _Delivery({this.captured});
  Map<String, dynamic>? captured;
  final log = <String>[];
  final deadlines = <DateTime?>[];
  Map<String, dynamic>? revertedWith;
  Completer<void>? holdPlay;
  int failReverts = 0;

  @override
  Future<Map<String, dynamic>?> capture() async => captured;

  @override
  Future<void> play(List<AlertAnimationStep> steps, {DateTime? deadline}) async {
    deadlines.add(deadline);
    log.add('play');
    if (holdPlay != null) await holdPlay!.future;
  }

  @override
  Future<void> revert(Map<String, dynamic> c) async {
    if (failReverts > 0) {
      failReverts--;
      throw StateError('no controller to revert on yet');
    }
    revertedWith = c;
    log.add('revert');
  }

  @override
  Future<void> revertToBaseLook() async => log.add('baseLook');
}

ScoreAlertEvent _td(String slug) => ScoreAlertEvent(
      teamSlug: slug,
      sport: SportType.nfl,
      eventType: AlertEventType.touchdown,
      pointsScored: 6,
      gameId: 'g1',
      timestamp: DateTime(2026, 10, 4, 15),
    );

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final _t0 = DateTime(2026, 10, 4, 15, 0, 0);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('the coordinator', () {
    test('records the marker before playing, gives play a deadline of length '
        '+ margin, and clears the marker once reverted', () async {
      final store = InMemoryCelebrationMarkerStore();
      final d = _Delivery(captured: {'on': true, 'ps': 7})
        ..holdPlay = Completer<void>();
      final c = ForegroundCelebrationCoordinator(
          monitor: _Monitor(), delivery: d, markers: store, now: () => _t0);
      addTearDown(c.dispose);

      c.handleAlert(_td('nfl_chiefs'));
      await _settle();
      // Mid-celebration (the app could be suspended right here).
      expect(store.marker, isNotNull);
      expect(store.marker!.revertTo, {'on': true, 'ps': 7});
      expect(store.marker!.endBy,
          _t0.add(const Duration(seconds: 15) + kCelebrationRevertMargin),
          reason: 'a Medium touchdown is 15 s; the margin is small');
      expect(d.deadlines.single, store.marker!.endBy);

      d.holdPlay!.complete(); // resumed
      await _settle();
      expect(d.log, ['play', 'revert']);
      expect(store.marker, isNull);
    });

    test('SUSPENDED mid-celebration, then resumed: the stalled play is '
        'stopped and the house reverted; a resume while it still plays does '
        'not revert twice', () async {
      final store = InMemoryCelebrationMarkerStore();
      final d = _Delivery(captured: {'on': true, 'ps': 3})
        ..holdPlay = Completer<void>();
      final c = ForegroundCelebrationCoordinator(
          monitor: _Monitor(), delivery: d, markers: store, now: () => _t0);
      addTearDown(c.dispose);

      c.handleAlert(_td('nfl_chiefs'));
      await _settle();
      c.setForeground(false);
      c.setForeground(true); // resume while this process still owns it
      await _settle();
      expect(d.log, ['play'], reason: 'the running celebration ends itself');

      d.holdPlay!.complete();
      await _settle();
      expect(d.log, ['play', 'revert']);
      expect(store.marker, isNull);
    });

    test('KILLED, then a cold start: the marker left behind is finished — '
        'reverted to what was captured', () async {
      final store = InMemoryCelebrationMarkerStore()
        ..marker = CelebrationMarker(
          teamSlug: 'nfl_chiefs',
          revertTo: {'on': true, 'bri': 140, 'ps': 12},
          startedAt: _t0,
          endBy: _t0.add(const Duration(seconds: 25)),
        );
      final d = _Delivery();
      final c = ForegroundCelebrationCoordinator(
          monitor: _Monitor(), delivery: d, markers: store);
      addTearDown(c.dispose);

      await c.recoverInterruptedCelebration();
      expect(d.revertedWith, {'on': true, 'bri': 140, 'ps': 12});
      expect(store.marker, isNull);
    });

    test('a lost capture ends on the base look', () async {
      final store = InMemoryCelebrationMarkerStore()
        ..marker = CelebrationMarker(
            teamSlug: 'nfl_chiefs',
            revertTo: null,
            startedAt: _t0,
            endBy: _t0);
      final d = _Delivery();
      final c = ForegroundCelebrationCoordinator(
          monitor: _Monitor(), delivery: d, markers: store);
      addTearDown(c.dispose);
      await c.recoverInterruptedCelebration();
      expect(d.log, ['baseLook']);
      expect(store.marker, isNull);
    });

    test('NEVER during a server-run Game Day: a served team is left to the '
        'server — nothing is written, the marker is cleared', () async {
      final store = InMemoryCelebrationMarkerStore()
        ..marker = CelebrationMarker(
            teamSlug: 'nfl_chiefs',
            revertTo: {'on': true, 'ps': 3},
            startedAt: _t0,
            endBy: _t0);
      final d = _Delivery();
      final c = ForegroundCelebrationCoordinator(
          monitor: _Monitor(),
          delivery: d,
          markers: store,
          isServedTeam: (slug) => slug == 'nfl_chiefs');
      addTearDown(c.dispose);
      await c.recoverInterruptedCelebration();
      expect(d.log, isEmpty);
      expect(store.marker, isNull);
    });

    test('a revert that cannot be sent keeps the marker; the next resume '
        'finishes it', () async {
      final store = InMemoryCelebrationMarkerStore()
        ..marker = CelebrationMarker(
            teamSlug: 'nfl_chiefs',
            revertTo: {'on': true, 'ps': 3},
            startedAt: _t0,
            endBy: _t0);
      final d = _Delivery()..failReverts = 1;
      final c = ForegroundCelebrationCoordinator(
          monitor: _Monitor(), delivery: d, markers: store);
      addTearDown(c.dispose);
      await c.recoverInterruptedCelebration();
      expect(store.marker, isNotNull, reason: 'kept for the next try');
      c.setForeground(false);
      c.setForeground(true);
      await _settle();
      expect(d.log, ['revert']);
      expect(store.marker, isNull);
    });
  });

  group('the real delivery', () {
    const channels = [
      DeviceChannel(id: 0, name: 'A', start: 0, stop: 10, gpioPin: 2),
      DeviceChannel(id: 1, name: 'B', start: 10, stop: 20, gpioPin: 14),
      DeviceChannel(id: 2, name: 'C', start: 20, stop: 30, gpioPin: 16),
    ];

    (WledCelebrationDelivery, RecordingWledRepository) rig(
        {DateTime Function()? now}) {
      final repo = RecordingWledRepository();
      final c = ProviderContainer(overrides: [
        wledRepositoryProvider.overrideWith((ref) => repo as WledRepository),
        deviceChannelsProvider.overrideWithValue(channels),
      ]);
      addTearDown(c.dispose);
      final p = Provider((ref) => WledCelebrationDelivery(ref, now: now));
      return (c.read(p), repo);
    }

    test('a house that was OFF stays off — its preset is not reloaded', () async {
      final (d, repo) = rig();
      await d.revert({
        'on': false,
        'bri': 80,
        'ps': 1,
        'seg': [
          {'id': 0, 'fx': 0}
        ],
      });
      expect(repo.applied, [
        {'on': false}
      ]);
    });

    test('the base look goes to every channel', () async {
      final (d, repo) = rig();
      await d.revertToBaseLook();
      final seg = (repo.applied.single['seg'] as List).cast<Map>();
      expect(seg.map((s) => s['id']), [0, 1, 2]);
      for (final s in seg) {
        expect(s['fx'], kBaseLookEffectId);
        expect(jsonEncode(s['col']), jsonEncode(baseLookColSlots()));
        expect(s['on'], isTrue);
      }
    });

    test('nothing plays past the deadline: a stage due after it never starts',
        () async {
      var now = _t0;
      final (d, repo) = rig(now: () => now);
      final steps = [
        AlertAnimationStep({'seg': [{'fx': 2}]}, Duration.zero),
        AlertAnimationStep({'seg': [{'fx': 3}]}, Duration.zero),
      ];
      // The first stage lands, then the clock is past the deadline (a slow
      // relay write, a suspended app) — the second never starts.
      final played = d.play(steps, deadline: _t0.add(const Duration(seconds: 5)));
      now = _t0.add(const Duration(seconds: 6));
      await played;
      expect(repo.applied, hasLength(1));
    });

    test('no controller yet → the revert throws (so the marker is kept)',
        () async {
      final c = ProviderContainer(overrides: [
        wledRepositoryProvider.overrideWith((ref) => null),
        deviceChannelsProvider.overrideWithValue(channels),
      ]);
      addTearDown(c.dispose);
      final d = c.read(Provider((ref) => WledCelebrationDelivery(ref)));
      expect(() => d.revert({'on': true, 'ps': 3}), throwsStateError);
      expect(d.revertToBaseLook, throwsStateError);
    });
  });

  group('the stored marker', () {
    test('survives a round trip through the phone store', () async {
      final store = SharedPrefsCelebrationMarkerStore();
      await store.save(CelebrationMarker(
        teamSlug: 'nfl_chiefs',
        revertTo: {'on': true, 'ps': 3},
        startedAt: _t0,
        endBy: _t0.add(const Duration(seconds: 25)),
      ));
      final back = await SharedPrefsCelebrationMarkerStore().load();
      expect(back?.teamSlug, 'nfl_chiefs');
      expect(back?.revertTo, {'on': true, 'ps': 3});
      expect(back?.endBy.toUtc(),
          _t0.add(const Duration(seconds: 25)).toUtc());
      await store.clear();
      expect(await store.load(), isNull);
    });

    test('a corrupt marker is dropped rather than blocking recovery',
        () async {
      SharedPreferences.setMockInitialValues(
          {SharedPrefsCelebrationMarkerStore.key: '{not json'});
      expect(await SharedPrefsCelebrationMarkerStore().load(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SharedPrefsCelebrationMarkerStore.key), isNull);
    });
  });
}
