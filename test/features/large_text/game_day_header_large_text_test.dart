// +120 large-text slice, group 4: the Game Day header. The pinned header
// delegate padded the glass app bar by the status-bar inset that the inner
// AppBar already applies, so the title sat an inset too low and was clipped
// at every text scale. The delegate now returns the bar as is.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart'
    show favoritesFirestoreProvider;
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_screen.dart';
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/large_text_matrix.dart';
import '../../helpers/recording_wled_repository.dart';
import '../../helpers/text_scale_harness.dart';

class _FakeUser extends Fake implements User {
  @override
  String get uid => 'customer-a';
}

GameDayAutopilotConfig _team(String slug, String name, int p, int s,
        {bool enabled = false}) =>
    GameDayAutopilotConfig(
      teamSlug: slug,
      teamName: name,
      espnTeamId: '9',
      sport: SportType.nfl,
      primaryColorValue: p,
      secondaryColorValue: s,
      enabled: enabled,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

List<GameDayTeamEntry> _teams() => [
      GameDayTeamEntry(
          config: _team('nfl_packers', 'Green Bay Packers', 0xFF203731, 0xFFFFB612,
              enabled: true)),
      GameDayTeamEntry(
          config: _team('nfl_chiefs', 'Kansas City Chiefs', 0xFFE31837, 0xFFFFB81C)),
    ];

List<Override> _gameDay(List<GameDayTeamEntry> entries) {
  final db = FakeFirebaseFirestore();
  return [
    authStateProvider.overrideWith((_) => Stream<User?>.value(_FakeUser())),
    currentUserProfileProvider.overrideWith((_) => Stream.value(null)),
    favoritesFirestoreProvider.overrideWithValue(db),
    gameDayFirestoreProvider.overrideWithValue(db),
    ephemeralGameSessionServiceProvider.overrideWithValue(null),
    gameDayTeamsProvider.overrideWithValue(entries),
    gameDayAutopilotConfigsProvider
        .overrideWith((_) => Stream.value([for (final e in entries) e.config])),
    gateStatusProvider.overrideWith((_) => Stream.value(GateStatus.unknown)),
    gameDayTeamPriorityProvider.overrideWithValue(const []),
    gameDayTeamPriorityHealProvider.overrideWithValue(null),
    upcomingGameProvider.overrideWith((ref, slug) => Stream.value(null)),
    wledRepositoryProvider.overrideWith((ref) => RecordingWledRepository()),
    wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    effectiveChannelIdsProvider.overrideWith((ref) => const [0]),
    demoModeProvider.overrideWith((ref) => false),
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Game Day with two teams: no overflow across the matrix',
      (tester) async {
    await expectNoOverflowAcrossLargeTextMatrix(
      tester,
      () => largeTextHost(
          overrides: _gameDay(_teams()), page: const GameDayScreen(), dock: 0),
      label: 'gameday/teams',
      frames: 6,
      settle: const Duration(milliseconds: 1800),
    );
  });

  testWidgets('Game Day with no teams: no overflow across the matrix',
      (tester) async {
    await expectNoOverflowAcrossLargeTextMatrix(
      tester,
      () => largeTextHost(
          overrides: _gameDay(const []), page: const GameDayScreen(), dock: 0),
      label: 'gameday/empty',
      frames: 6,
      settle: const Duration(milliseconds: 1800),
    );
  });

  testWidgets('the header title is fully inside the pinned header at 390x844',
      (tester) async {
    final profile = largeTextProfiles()
        .firstWhere((p) => p.$1 == '390x844@1.0')
        .$2;
    await pumpAtTextScale(
      tester,
      largeTextHost(
          overrides: _gameDay(_teams()), page: const GameDayScreen(), dock: 0),
      profile: profile,
      host: TextScaleHost.none,
      frames: 3,
    );
    expect(tester.takeException(), isNull);
    final title = find.descendant(
        of: find.byType(AppBar), matching: find.text('Game Day'));
    expect(title, findsOneWidget);
    final titleRect = tester.getRect(title);
    final headerRect = tester.getRect(find.byType(AppBar));
    // The title sits inside the toolbar, which sits below the 47 pt inset,
    // not an inset lower than that (the pre-fix double padding).
    expect(titleRect.top, greaterThanOrEqualTo(headerRect.top));
    expect(titleRect.bottom, lessThanOrEqualTo(headerRect.bottom));
    expect(titleRect.top, lessThan(47 + kToolbarHeight),
        reason: 'title must be within the first toolbar height below the inset');
  });
}
