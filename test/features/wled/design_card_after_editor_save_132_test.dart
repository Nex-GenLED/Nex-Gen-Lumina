// Build 132, fix 4 follow-up — the card page after the Pattern Editor saved
// its design in place.
//
// The Pattern Editor, opened from a saved design's card page, now updates
// that design in place. The card page underneath still holds the design as
// it was and its controls as they were seeded: its "Save to design" would
// write the old look back over the editor's save, and leaving it would put
// the house back to the look from before the card page opened. So when the
// editor saved the design in place, the card page closes the way its own
// successful "Save to design" does — the lights keep what they show, nothing
// is written to them. A save under a new name, or no save, leaves the card
// page open, as before.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_router.dart' show AppRoutes;
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/edit_pattern_screen.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

class _RecordingDesignService implements DesignService {
  _RecordingDesignService(this.existing);
  final List<CustomDesign> existing;
  final saved = <CustomDesign>[];

  @override
  Future<List<CustomDesign>> getDesigns(String userId) async => existing;

  @override
  Future<String> saveDesign(String userId, CustomDesign design) async {
    saved.add(design);
    return design.id.isEmpty ? 'auto-${saved.length}' : design.id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CustomDesign _design() => CustomDesign(
      id: 'd1',
      name: 'Blue Chase',
      createdAt: DateTime(2026, 9, 29),
      updatedAt: DateTime(2026, 9, 29),
      ownerId: 'u1',
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

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Home → the card page for [_design] → the Pattern Editor (the real route
/// builder).
Future<({_RecordingDesignService service, RecordingWledRepository repo})>
    _openEditorFromCard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final service = _RecordingDesignService([_design()]);
  final repo = RecordingWledRepository();
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, __) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.push('/card'),
            child: const Text('HOME'),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/card',
      builder: (_, __) => Scaffold(
          body: ColorwayEffectSelectorPage.forDesign(design: _design())),
    ),
    GoRoute(
      path: AppRoutes.editPattern,
      builder: (_, s) => editPatternScreenForExtra(s.extra),
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      designServiceProvider.overrideWithValue(service),
      designsStreamProvider.overrideWith((ref) => Stream.value([_design()])),
      effectiveUserUidProvider.overrideWithValue('u1'),
      authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
      favoritedPatternIdsProvider
          .overrideWith((ref) => Stream.value(const <String>{})),
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
      deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
      participatingChannelIdsProvider.overrideWithValue(null),
      demoModeProvider.overrideWith((ref) => false),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await _frames(tester);
  await tester.tap(find.text('HOME'));
  await _frames(tester);
  expect(find.byType(ColorwayEffectSelectorPage), findsOneWidget);
  await tester.tap(find.byTooltip('Open in Pattern Editor'));
  await _frames(tester);
  expect(find.byType(EditPatternScreen), findsOneWidget);
  return (service: service, repo: repo);
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('SAVE'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _backFromEditor(WidgetTester tester) async {
  await tester.tap(find.descendant(
      of: find.byType(EditPatternScreen),
      matching: find.byIcon(Icons.arrow_back)));
  await _frames(tester, 8);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('saved in place: back from the editor closes the out-of-date '
      'card page, and nothing is sent to the lights', (tester) async {
    final rig = await _openEditorFromCard(tester);
    await _save(tester);
    expect(rig.service.saved.single.id, 'd1');

    await _backFromEditor(tester);

    expect(find.byType(EditPatternScreen), findsNothing);
    expect(find.byType(ColorwayEffectSelectorPage), findsNothing,
        reason: 'its Save to design would write the old look back');
    expect(find.text('HOME'), findsOneWidget);
    expect(rig.repo.applied, isEmpty,
        reason: 'no restore of the look from before the card page opened');
    expect(rig.service.saved, hasLength(1),
        reason: 'closing writes nothing to the design');
  });

  testWidgets('saved under a new name: the card page stays — its design is '
      'untouched', (tester) async {
    final rig = await _openEditorFromCard(tester);
    await tester.enterText(find.byType(TextField).first, 'Ocean');
    await _save(tester);
    expect(rig.service.saved.single.id, isEmpty);

    await _backFromEditor(tester);

    expect(find.byType(ColorwayEffectSelectorPage), findsOneWidget);
  });

  testWidgets('not saved: the card page stays', (tester) async {
    await _openEditorFromCard(tester);
    await _backFromEditor(tester);
    expect(find.byType(ColorwayEffectSelectorPage), findsOneWidget);
  });
}
