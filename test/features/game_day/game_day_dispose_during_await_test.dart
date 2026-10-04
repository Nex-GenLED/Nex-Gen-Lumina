// #166 — "Bad state: Cannot use "ref" after the widget was disposed."
//
// Crash on 2.5.10+114, 2026-10-02, seconds after a team was switched back on
// from the Game Day screen. The switch awaits the "No everyday schedule set"
// dialog and then read the card's `ref`; the team list can rebuild while the
// dialog is open, tearing the card down, so the read threw and the enable the
// customer had just confirmed was never written. The same shape sat behind
// Remove, Alerts and Light Up Now.
//
// Each test opens the dialog / sheet / slow read, removes the card from the
// list while it is open, finishes the flow, and expects no exception and the
// write still made.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/base_layer_gate.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart'
    show AutopilotSession;
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_screen.dart';
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart' show SeededWledNotifier, kHomeLitState;
import '../../helpers/recording_wled_repository.dart';

const _uid = 'test-user';
const _slug = 'nfl_packers';

class _FakeUser extends Fake implements User {
  @override
  String get uid => _uid;
}

GameDayAutopilotConfig _packers({required bool enabled}) =>
    GameDayAutopilotConfig(
      teamSlug: _slug,
      teamName: 'Green Bay Packers',
      espnTeamId: '9',
      sport: SportType.nfl,
      primaryColorValue: 0xFF203731,
      secondaryColorValue: 0xFFFFB612,
      enabled: enabled,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

/// Records the writes the card asks for; no timers, no Firebase.
class _RecordingGameDay extends GameDayAutopilotNotifier {
  final toggles = <(String, bool)>[];
  final removed = <String>[];
  final sensitivities = <AlertSensitivity>[];

  @override
  Map<String, AutopilotSession> build() => const {};

  @override
  Future<void> toggleAutopilot({
    required String teamSlug,
    required bool enabled,
    DateTime? untilDate,
  }) async =>
      toggles.add((teamSlug, enabled));

  @override
  Future<void> removeTeam({
    required String teamSlug,
    required String teamName,
  }) async =>
      removed.add(teamSlug);

  @override
  Future<void> setAlertSensitivity({
    required String teamSlug,
    required AlertSensitivity sensitivity,
  }) async =>
      sensitivities.add(sensitivity);
}

/// A controller whose state read waits until the test lets it answer.
class _SlowReadRepo extends RecordingWledRepository {
  final gate = Completer<void>();
  @override
  Future<Map<String, dynamic>?> getState() async {
    await gate.future;
    return const {'on': true, 'bri': 128};
  }
}

/// The lit house, with polling held still (no timer outlives a test).
class _NoPollNotifier extends SeededWledNotifier {
  _NoPollNotifier() : super(kHomeLitState);
  @override
  void pausePolling() {}
  @override
  void resumePolling() {}
}

/// The team list the screen shows; a test empties it to tear the card down.
final _entries = StateProvider<List<GameDayTeamEntry>>((_) => const []);

Future<(ProviderContainer, _RecordingGameDay)> _pump(
  WidgetTester tester, {
  required bool enabled,
  RecordingWledRepository? repo,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(390, 1400);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  resetBaseLayerPromptSession();

  final recorder = _RecordingGameDay();
  final db = FakeFirebaseFirestore();
  final container = ProviderContainer(overrides: [
    authStateProvider.overrideWith((_) => Stream.value(_FakeUser())),
    currentUserProfileProvider.overrideWith((_) => Stream.value(null)),
    favoritesFirestoreProvider.overrideWithValue(db),
    gameDayFirestoreProvider.overrideWithValue(db),
    ephemeralGameSessionServiceProvider.overrideWithValue(null),
    gameDayTeamsProvider.overrideWith((ref) => ref.watch(_entries)),
    gameDayAutopilotConfigsProvider.overrideWith(
        (_) => Stream.value([_packers(enabled: enabled)])),
    gameDayAutopilotNotifierProvider.overrideWith(() => recorder),
    gateStatusProvider.overrideWith((_) => Stream.value(GateStatus.unknown)),
    gameDayTeamPriorityProvider.overrideWithValue(const []),
    gameDayTeamPriorityHealProvider.overrideWithValue(null),
    upcomingGameProvider.overrideWith((ref, slug) => Stream.value(null)),
    // No everyday schedule → the base-layer dialog shows on enable.
    userSchedulesStreamProvider
        .overrideWith((_) => Stream.value(const <ScheduleItem>[])),
    wledRepositoryProvider.overrideWith((ref) => repo ?? RecordingWledRepository()),
    wledStateProvider.overrideWith(_NoPollNotifier.new),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    effectiveChannelIdsProvider.overrideWith((ref) => const [0]),
    demoModeProvider.overrideWith((ref) => false),
  ]);
  addTearDown(container.dispose);
  // Signed in before the screen opens, as on a phone (the gate reads the uid).
  final authSub = container.listen(authStateProvider, (_, __) {});
  addTearDown(authSub.close);
  await container.read(authStateProvider.future);
  container.read(_entries.notifier).state = [
    GameDayTeamEntry(config: _packers(enabled: enabled)),
  ];
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: GameDayScreen()),
  ));
  await _frames(tester);
  return (container, recorder);
}

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Removes the team from the list — the card is unmounted.
Future<void> _tearDownCard(WidgetTester tester, ProviderContainer c) async {
  c.read(_entries.notifier).state = const [];
  await _frames(tester, 3);
  expect(find.text('Light Up Now'), findsNothing,
      reason: 'sanity: the card is gone');
}

void main() {
  testWidgets('the ENABLE switch: the card is torn down while "No everyday '
      'schedule set" is open → "Enable anyway" still writes the enable, and '
      'nothing throws (the 10-02 crash)', (tester) async {
    final (c, recorder) = await _pump(tester, enabled: false);

    final autopilotRow = find.ancestor(
        of: find.text('Autopilot'), matching: find.byType(Row));
    await tester.tap(find.descendant(
        of: autopilotRow.first, matching: find.byType(Switch)));
    await _frames(tester);
    expect(find.text('No everyday schedule set'), findsOneWidget);

    await _tearDownCard(tester, c);
    await tester.tap(find.text('Enable anyway'));
    await _frames(tester);

    expect(tester.takeException(), isNull);
    expect(recorder.toggles, [(_slug, true)],
        reason: 'the customer confirmed the enable — it must be written');
  });

  testWidgets('REMOVE: the card is torn down while the confirm dialog is '
      'open → Remove still removes, and nothing throws', (tester) async {
    final (c, recorder) = await _pump(tester, enabled: true);
    await tester.tap(find.byTooltip('Remove team'));
    await _frames(tester);
    expect(find.text('Remove'), findsOneWidget);

    await _tearDownCard(tester, c);
    await tester.tap(find.text('Remove'));
    await _frames(tester);

    expect(tester.takeException(), isNull);
    expect(recorder.removed, [_slug]);
  });

  testWidgets('ALERTS: the card is torn down while the sensitivity sheet is '
      'open → the pick is still saved, and nothing throws', (tester) async {
    final (c, recorder) = await _pump(tester, enabled: true);
    await tester.tap(find.text('Alerts'));
    await _frames(tester);
    expect(find.text('Alert Sensitivity'), findsOneWidget);

    await _tearDownCard(tester, c);
    final pick = AlertSensitivity.values
        .firstWhere((s) => s != _packers(enabled: true).alertSensitivity);
    final tile = find.byType(ListTile).at(AlertSensitivity.values.indexOf(pick));
    await tester.tap(tile);
    await _frames(tester);

    expect(tester.takeException(), isNull);
    expect(recorder.sensitivities, [pick]);
  });

  testWidgets('LIGHT UP NOW: the card is torn down while the house is being '
      'read → the team look is still sent, and nothing throws', (tester) async {
    final repo = _SlowReadRepo();
    final (c, _) = await _pump(tester, enabled: true, repo: repo);
    await tester.tap(find.text('Light Up Now'));
    await _frames(tester, 2);

    await _tearDownCard(tester, c);
    repo.gate.complete();
    await _frames(tester);

    expect(tester.takeException(), isNull);
    expect(repo.applied, isNotEmpty,
        reason: 'the apply the customer asked for still goes out');
  });
}
