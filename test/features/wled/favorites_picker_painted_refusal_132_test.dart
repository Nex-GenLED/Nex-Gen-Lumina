// Build 132, fix 5 — the Favorites "+" picker's refusal of a painted design
// says the real reason.
//
// It used to give the schedule's sentence ("your controller's timers can only
// replay colours and effects …"), which has nothing to do with Favorites. The
// real reason: this list hands Favorites a design as one colour-and-effect
// message, which cannot hold a painted picture. Only the WORDS change — the
// same designs are refused, and the schedule and Game Day sentences are
// pinned unchanged.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/per_pixel_payload_guard.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/pattern_theme_selection.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

const _favoritesDetail = 'Favorites added from this list store colours and '
    "effects, not a painted picture, so this one can't be added here yet. "
    'You can still apply it any time from My Designs.';

const _favoritesSentence = '"Painted" is a per-pixel design. Favorites added '
    'from this list store colours and effects, not a painted picture, so '
    "this one can't be added here yet.";

/// The card's sentence before build 132 — still what every destination but
/// Favorites shows.
const _timerDetail = "Your controller's timers can replay colours and effects, "
    "not a painted picture, so this one can't be chosen here. You can still "
    'apply it any time from My Designs.';

CustomDesign _painted() => CustomDesign(
      id: 'p1',
      name: 'Painted',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      ownerId: 'u',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          ledCount: 6,
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 2, color: [255, 0, 0, 0]),
            LedColorGroup(startLed: 3, endLed: 5, color: [0, 0, 255, 0]),
          ],
        ),
      ],
      perPixel: true,
    );

CustomDesign _effect() => CustomDesign(
      id: 'e1',
      name: 'Chase',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      ownerId: 'u',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 34, 0]),
          ],
          effectId: 28,
        ),
      ],
      brightness: 150,
      brightnessStated: true,
    );

Future<List<LibraryDesignSelection>> _openInPicker(
    WidgetTester tester, CustomDesign design, String destination) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final handedBack = <LibraryDesignSelection>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
      designsStreamProvider.overrideWith((ref) => Stream.value([design])),
      wledRepositoryProvider.overrideWith((ref) => RecordingWledRepository()),
      wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
      deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
      participatingChannelIdsProvider.overrideWithValue(null),
      demoModeProvider.overrideWith((ref) => false),
      userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
    ],
    child: MaterialApp(
      home: LibraryBrowserScreen(
        nodeId: 'design_${design.id}',
        saveDestinationLabel: destination,
        onDesignSelected: handedBack.add,
      ),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return handedBack;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the Favorites picker', () {
    testWidgets('a painted design is refused with the real reason — no timer '
        'wording', (tester) async {
      final handedBack = await _openInPicker(tester, _painted(), 'Favorites');

      expect(find.text('"Painted" is a per-pixel design'), findsOneWidget);
      expect(find.text(_favoritesDetail), findsOneWidget);
      expect(find.textContaining('timers'), findsNothing);
      expect(find.byKey(const ValueKey('per-pixel-choose-another')),
          findsOneWidget);
      expect(handedBack, isEmpty, reason: 'still refused');
    });

    testWidgets('an effect design is still handed back, its payload as before',
        (tester) async {
      final handedBack = await _openInPicker(tester, _effect(), 'Favorites');
      expect(handedBack, hasLength(1));
      expect(handedBack.single.wledPayload, _effect().toWledPayload());
    });

    test('the snackbar sentence names the real reason too', () {
      expect(perPixelPickerRefusalMessage('Painted', 'Favorites'),
          _favoritesSentence);
      expect(perPixelPickerRefusalMessage('Painted', 'favorites'),
          _favoritesSentence);
    });
  });

  group('every other destination, unchanged', () {
    testWidgets('Game Day: the card keeps its sentence', (tester) async {
      final handedBack = await _openInPicker(tester, _painted(), 'Game Day');
      expect(find.text(_timerDetail), findsOneWidget);
      expect(handedBack, isEmpty);
    });

    test('the schedule and Game Day sentences', () {
      expect(
          perPixelPickerRefusalMessage('Painted', 'schedule'),
          '"Painted" is a per-pixel design. Those can\'t be scheduled yet — '
          'your controller\'s timers can only replay colours and effects, not '
          'a painted picture. You can still apply it any time from My Designs.');
      expect(perPixelPickerRefusalMessage('Painted', 'Game Day'),
          perPixelGameDayRefusedMessage('Painted'));
      expect(perPixelPickerRefusalMessage('Painted', null),
          perPixelPickerRefusalMessage('Painted', 'schedule'));
    });
  });
}
