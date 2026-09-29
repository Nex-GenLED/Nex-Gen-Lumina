// +110 E1 — rows 44, 85, 86.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/dashboard/main_scaffold.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/wled/current_colors_editor_screen.dart';
import 'package:nexgen_command/features/wled/display_pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart' as usage;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

class _FakeUser extends Fake implements User {
  @override
  String get uid => 'customer-test';
}

class _RecordingDesignService implements DesignService {
  final saved = <CustomDesign>[];

  @override
  Future<String> saveDesign(String userId, CustomDesign design) async {
    saved.add(design);
    return 'new-id';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('row 44: Current Colours "Save As…" → Save SAVES ONLY — no '
      'controller write, and the design lands in My Designs', (tester) async {
    final repo = RecordingWledRepository(state: {
      'on': true,
      'bri': 150,
      'seg': [
        {
          'id': 0,
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'col': [
            [255, 0, 0],
            [0, 255, 0],
            [0, 0, 255],
          ],
        }
      ],
    });
    final designs = _RecordingDesignService();
    final c = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
      authStateProvider.overrideWith((ref) => Stream<User?>.value(_FakeUser())),
      designServiceProvider.overrideWithValue(designs),
    ]);
    addTearDown(c.dispose);
    await c.read(authStateProvider.future);
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The editor closes itself with context.pop() after a save.
    final router = GoRouter(initialLocation: '/colors', routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('SETTINGS')),
        routes: [
          GoRoute(
              path: 'colors',
              builder: (_, __) => const CurrentColorsEditorScreen()),
        ],
      ),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();
    await tester.pump();
    final writesBefore = repo.writeCount;

    await tester.tap(find.text('Save As...'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Porch Colours');
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    await tester.pumpAndSettle();
    expect(designs.saved.single.name, 'Porch Colours');
    expect(find.text('Pattern "Porch Colours" saved successfully'),
        findsOneWidget);
    expect(repo.writeCount, writesBefore,
        reason: 'Save As never writes to the lights (Apply does)');
  });

  test('row 85: Now Playing shows a favourite\'s name HUMANISED — exactly as '
      'its My Favorites card does', () async {
    final c = ProviderContainer(overrides: [
      wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
      allFavoritesProvider.overrideWith((ref) => Stream.value([
            FavoritePattern(
              patternId: 'f1',
              name: 'KC_Royals_Game_Day',
              usageCount: 1,
              lastUsed: DateTime(2026, 9, 1),
              wledPayload: const {},
            ),
          ])),
    ]);
    addTearDown(c.dispose);
    await c.read(allFavoritesProvider.future);
    c
        .read(activePresetLabelProvider.notifier)
        .setLabelWithFingerprint('kc_royals_game_day', c.read(wledStateProvider));

    final card = usage.FavoritePattern(
      id: 'f1',
      patternName: 'KC_Royals_Game_Day',
      addedAt: DateTime(2026, 9, 1),
      usageCount: 1,
      patternData: const {},
      autoAdded: false,
    );
    expect(c.read(displayPatternNameProvider), card.displayName);
    expect(c.read(displayPatternNameProvider), isNot('KC_Royals_Game_Day'));
  });

  group('row 86: system Back on a branch root', () {
    Future<List<String>> pressBack(WidgetTester tester, int shellIndex) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(MaterialApp(
        home: PopScope(
          // Exactly what MainScaffold passes.
          canPop: shellRootCanPop(shellIndex),
          child: const Scaffold(body: Text('shell')),
        ),
      ));
      await tester.binding.handlePopRoute();
      await tester.pump();
      return calls;
    }

    testWidgets('on Home it leaves the app', (tester) async {
      expect(await pressBack(tester, 0), contains('SystemNavigator.pop'));
    });

    testWidgets('on any other tab root it does not (it goes to Home)',
        (tester) async {
      for (final i in [1, 2, 3, 4]) {
        expect(await pressBack(tester, i), isNot(contains('SystemNavigator.pop')),
            reason: 'tab $i');
      }
    });
  });
}
