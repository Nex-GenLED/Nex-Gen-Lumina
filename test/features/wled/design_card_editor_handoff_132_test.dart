// Build 132, fix 4 — the card page tells the Pattern Editor which saved
// design it was opened on.
//
// Opening the Pattern Editor from a saved design's card page handed it only
// an EditablePattern, so the editor's SAVE could not know the design it came
// from and saved a copy named "Name 2". The card page now hands over the
// design too. From an Explore card nothing changes: the editor still gets the
// bare pattern.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_router.dart' show AppRoutes;
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

CustomDesign _design() => CustomDesign(
      id: 'd1',
      name: 'Blue Chase',
      createdAt: DateTime(2026, 9, 29),
      updatedAt: DateTime(2026, 9, 29),
      ownerId: 'u',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 0, color: [0, 0, 255, 0]),
          ],
          effectId: 28,
          speed: 44,
          intensity: 90,
        ),
      ],
      brightness: 150,
      brightnessStated: true,
    );

Future<Object?> _tapTuneAndCapture(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  Object? captured;
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => Scaffold(body: page)),
    GoRoute(
      path: AppRoutes.editPattern,
      builder: (_, s) {
        captured = s.extra;
        return const Scaffold(body: Text('EDITOR'));
      },
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
      designsStreamProvider.overrideWith((ref) => Stream.value([_design()])),
      wledRepositoryProvider.overrideWith((ref) => RecordingWledRepository()),
      wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
      deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
      participatingChannelIdsProvider.overrideWithValue(null),
      demoModeProvider.overrideWith((ref) => false),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(find.byTooltip('Open in Pattern Editor'));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.text('EDITOR'), findsOneWidget);
  return captured;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('from a saved design: the editor is handed the pattern AND the '
      'design it came from', (tester) async {
    final extra = await _tapTuneAndCapture(
        tester, ColorwayEffectSelectorPage.forDesign(design: _design()));

    final launch = extra as dynamic;
    final CustomDesign source = launch.sourceDesign as CustomDesign;
    final EditablePattern pattern = launch.pattern as EditablePattern;
    expect(source.id, 'd1');
    expect(source.name, 'Blue Chase');
    expect(pattern.name, 'Blue Chase',
        reason: 'the name field opens on the design\'s own name');
    expect(pattern.effectId, 28);
    expect(pattern.speed, 44);
    expect(pattern.intensity, 90);
  });

  testWidgets('from an Explore card: the editor still gets the bare pattern',
      (tester) async {
    final extra = await _tapTuneAndCapture(
      tester,
      const ColorwayEffectSelectorPage(
        paletteNode: LibraryNode(
          id: 'pal_blue',
          name: 'Blue',
          nodeType: LibraryNodeType.palette,
          themeColors: [Color(0xFF0000FF)],
        ),
      ),
    );
    expect(extra, isA<EditablePattern>());
    expect((extra as EditablePattern).name, 'Blue');
  });
}
