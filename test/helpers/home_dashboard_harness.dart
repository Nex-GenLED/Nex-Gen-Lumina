// Hosts the REAL Home screen (WledDashboardPage) in a widget test, with the
// Firestore- and network-backed providers it reads replaced by plain values.
//
//   final h = await pumpHomeDashboard(tester, favorites: [...]);
//   await tester.tap(find.text('Warm White'));
//   expect(h.repo.applied.single, ...);
//
// Nothing here starts a poller or opens a Firestore listen; the controller is
// a RecordingWledRepository (see recording_wled_repository.dart).

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/dashboard/wled_dashboard_page.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart'
    as fav;
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/installer/media_access_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/schedule/day_timeline.dart';
import 'package:nexgen_command/features/schedule/day_timeline_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/connectivity_service.dart';

import 'recording_wled_repository.dart';

/// A WledNotifier that starts from [seed] and never polls.
class SeededWledNotifier extends WledNotifier {
  SeededWledNotifier(this.seed);
  final WledStateModel seed;

  @override
  WledStateModel build() => seed;
}

/// A connected house, lit, running Chase in red/blue.
const WledStateModel kHomeLitState = WledStateModel(
  isOn: true,
  brightness: 120,
  speed: 128,
  intensity: 128,
  color: Color(0xFFFF0000),
  connected: true,
  warmWhite: 0,
  supportsRgbw: false,
  effectId: 28,
  paletteId: 5,
  colorSequence: [Color(0xFFFF0000), Color(0xFF0000FF)],
);

class _NoZoneSegments extends ZoneSegmentsNotifier {
  @override
  Future<List<WledSegment>> build() async => const [];
}

const List<DeviceChannel> kHomeTwoChannels = [
  DeviceChannel(id: 0, name: 'Front', start: 0, stop: 30, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Garage', start: 30, stop: 60, gpioPin: 14),
];

ControllerInfo homeController() => ControllerInfo(
      id: 'ctrl-test',
      ip: '192.0.2.10',
      name: 'House',
    );

FavoritePattern homeWhite(String id, String name) => FavoritePattern(
      id: id,
      patternName: name,
      addedAt: DateTime(2024, 1, 1),
      usageCount: 0,
      patternData: const {
        'on': true,
        'bri': 220,
        'seg': [
          {
            'fx': 0,
            'col': [
              [255, 170, 90, 0]
            ]
          }
        ],
      },
      autoAdded: false,
    );

class HomeHarness {
  HomeHarness(this.container, this.repo);
  final ProviderContainer container;
  final RecordingWledRepository repo;
}

/// The overrides behind [pumpHomeDashboard], for tests that host Home in
/// their own app (the text-scale harness, a router).
List<Override> homeDashboardOverrides({
  required WledRepository? repo,
  WledStateModel state = kHomeLitState,
  List<ControllerInfo>? controllers,
  List<FavoritePattern>? whites,
  List<FavoritePattern> favorites = const [],
  List<SmartSuggestion> suggestions = const [],
  UserModel? profile,
  User? user,
  List<DeviceChannel> channels = kHomeTwoChannels,
  bool smartPresets = false,
  ConnectivityStatus connectivity = ConnectivityStatus.local,
}) =>
    [
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledStateProvider.overrideWith(() => SeededWledNotifier(state)),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(connectivity)),
      rooflineLegacyMigrationProvider.overrideWith((ref) async {}),
      activeUserProfileProvider.overrideWith((ref) => Stream.value(profile)),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(profile)),
      authStateProvider.overrideWith((ref) => Stream<User?>.value(user)),
      effectiveUserUidProvider.overrideWith((ref) => 'customer-test'),
      isViewingAsCustomerProvider.overrideWithValue(false),
      controllersStreamProvider.overrideWith(
          (ref) => Stream.value(controllers ?? [homeController()])),
      hasCustomHouseImageProvider.overrideWithValue(true),
      fav.allFavoritesProvider.overrideWith((ref) => Stream.value(const [])),
      fav.favoritedPatternIdsProvider
          .overrideWith((ref) => Stream.value(const <String>{})),
      zoneSegmentsProvider.overrideWith(() => _NoZoneSegments()),
      activePhaseSessionProvider.overrideWithValue(null),
      activeSuggestionsProvider.overrideWith((ref) => Stream.value(suggestions)),
      favoriteWhiteSlotsProvider.overrideWith((ref) =>
          whites ??
          [
            homeWhite('white_primary', 'Warm White'),
            homeWhite('white_complement', 'Bright White'),
          ]),
      userFavoritePatternsProvider.overrideWith((ref) => Stream.value(favorites)),
      todayTimelineProvider.overrideWithValue(DayTimeline.empty),
      deviceChannelsProvider.overrideWithValue(channels),
      participatingChannelIdsProvider.overrideWithValue(null),
      currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
      demoModeProvider.overrideWith((ref) => false),
      smartPresetsOnHomeProvider.overrideWithValue(smartPresets),
      userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
    ];

/// Pumps the real Home screen on a 390×844 phone and returns the container
/// and the recording controller.
Future<HomeHarness> pumpHomeDashboard(
  WidgetTester tester, {
  RecordingWledRepository? repo,
  WledStateModel state = kHomeLitState,
  List<ControllerInfo>? controllers,
  List<FavoritePattern>? whites,
  List<FavoritePattern> favorites = const [],
  List<SmartSuggestion> suggestions = const [],
  UserModel? profile,
  User? user,
  List<DeviceChannel> channels = kHomeTwoChannels,
  bool smartPresets = false,
  ConnectivityStatus connectivity = ConnectivityStatus.local,
  Size size = const Size(390, 1800),
}) async {
  final r = repo ?? RecordingWledRepository();
  final c = ProviderContainer(
    overrides: homeDashboardOverrides(
      repo: r,
      state: state,
      controllers: controllers,
      whites: whites,
      favorites: favorites,
      suggestions: suggestions,
      profile: profile,
      user: user,
      channels: channels,
      smartPresets: smartPresets,
      connectivity: connectivity,
    ),
  );
  addTearDown(c.dispose);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await c.read(wledConnectivityStatusProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: WledDashboardPage()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return HomeHarness(c, r);
}

/// Unmounts Home so its periodic sky timer and animations stop before the
/// test ends.
Future<void> unmountHome(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
