// Build 132, fix 2 — which screen a saved design opens on.
//
// Until build 131 only a design saved from the Pattern Editor opened the card
// page (the live tuner with Apply and "Save to design"); every other saved
// design opened the detail screen, even when it was a plain effect that the
// card page shows perfectly well. Now any saved design that is not painted,
// not an AI design and not a Solid colour opens the card page — but only when
// every channel shows the SAME look, because the card page's "Save to design"
// writes one look to every channel and would flatten a design whose channels
// differ.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/screens/design_detail_screen.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_theme_selection.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

List<Override> _base(List<CustomDesign> designs) => [
      authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
      designsStreamProvider.overrideWith((ref) => Stream.value(designs)),
      wledRepositoryProvider.overrideWith((ref) => RecordingWledRepository()),
      wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
      wledConnectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
      deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
      participatingChannelIdsProvider.overrideWithValue(null),
      demoModeProvider.overrideWith((ref) => false),
      userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
    ];

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Opens the saved-design route for [design] the way My Designs does.
Future<void> _open(WidgetTester tester, CustomDesign design) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: _base([design]),
    child: MaterialApp(
      home: LibraryBrowserScreen(nodeId: 'design_${design.id}'),
    ),
  ));
  await _frames(tester);
}

void _expectCardPage() {
  expect(find.byType(ColorwayEffectSelectorPage), findsOneWidget);
  expect(find.byKey(const ValueKey('apply-design')), findsOneWidget);
  expect(find.byKey(const ValueKey('save-to-design')), findsOneWidget);
  expect(find.byType(DesignDetailScreen), findsNothing);
}

void _expectDetailScreen() {
  expect(find.byType(DesignDetailScreen), findsOneWidget);
  expect(find.byType(ColorwayEffectSelectorPage), findsNothing);
}

const _red = [255, 0, 34, 0];
const _gold = [255, 168, 0, 0];

ChannelDesign _ch(
  int id, {
  List<List<int>> colors = const [_red],
  int fx = 28,
  int sx = 44,
  int ix = 90,
  bool reverse = false,
  int grp = 2,
  int spc = 3,
  int ledCount = 128,
  bool included = true,
  SolidLayout layout = SolidLayout.blocks,
  bool spanChannel = true,
}) =>
    ChannelDesign(
      channelId: id,
      channelName: 'Channel ${id + 1}',
      included: included,
      // Now Playing writes one group spanning the channel; the Pattern Editor
      // writes one single-LED group per colour.
      colorGroups: spanChannel && colors.length == 1
          ? [LedColorGroup(startLed: 0, endLed: ledCount - 1, color: colors.first)]
          : [
              for (var i = 0; i < colors.length; i++)
                LedColorGroup(startLed: i, endLed: i, color: colors[i]),
            ],
      effectId: fx,
      speed: sx,
      intensity: ix,
      reverse: reverse,
      grouping: grp,
      spacing: spc,
      ledCount: ledCount,
      solidLayout: layout,
    );

CustomDesign _design(
  List<ChannelDesign> channels, {
  String id = 'd1',
  List<String> tags = const [],
  bool perPixel = false,
  Map<String, dynamic>? composedPattern,
}) =>
    CustomDesign(
      id: id,
      name: 'Saved $id',
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      ownerId: 'u',
      channels: channels,
      brightness: 150,
      brightnessStated: true,
      tags: tags,
      perPixel: perPixel,
      composedPattern: composedPattern,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the card page — an effect design whose channels share one look', () {
    testWidgets('a Now Playing save across two channels', (tester) async {
      // Different LED counts, so the groups span different ranges: ranges
      // are where the colour sits, not part of the look.
      await _open(tester,
          _design([_ch(0, ledCount: 128), _ch(1, ledCount: 162)]));
      _expectCardPage();
      final container = ProviderScope.containerOf(
          tester.element(find.byType(ColorwayEffectSelectorPage)));
      expect(container.read(selectorEffectIdProvider), 28);
      expect(container.read(selectorSpeedProvider), 44);
      expect(container.read(selectorIntensityProvider), 90);
      expect(container.read(selectorColorGroupProvider), 2);
      expect(container.read(selectorSpacingProvider), 3);
    });

    testWidgets('one channel', (tester) async {
      await _open(tester, _design([_ch(0)]));
      _expectCardPage();
    });

    testWidgets('a left-out channel does not count — only included channels '
        'are sent, and only they are compared', (tester) async {
      await _open(
          tester,
          _design([
            _ch(0),
            _ch(1),
            _ch(2, colors: const [_gold], fx: 9, included: false),
          ]));
      _expectCardPage();
    });

    testWidgets('a Pattern Editor design, as before', (tester) async {
      await _open(
          tester,
          _design([
            _ch(0, colors: const [_red, _gold], spanChannel: false),
            _ch(1, colors: const [_red, _gold], spanChannel: false),
          ], tags: const [kPatternEditorDesignTag]));
      _expectCardPage();
    });

    testWidgets('a Pattern Editor Static design keeps opening the card page, '
        'as before', (tester) async {
      await _open(
          tester,
          _design([
            _ch(0,
                colors: const [_red, _gold],
                fx: 0,
                spanChannel: false,
                layout: SolidLayout.alternating),
          ], tags: const [kPatternEditorDesignTag]));
      _expectCardPage();
    });
  });

  group('the detail screen — a design the card page would flatten', () {
    final differences = <String, ChannelDesign>{
      'colour': _ch(1, colors: const [_gold]),
      'a second colour': _ch(1, colors: const [_red, _gold], spanChannel: false),
      'effect': _ch(1, fx: 9),
      'speed': _ch(1, sx: 45),
      'intensity': _ch(1, ix: 91),
      'direction': _ch(1, reverse: true),
      'grouping': _ch(1, grp: 1),
      'spacing': _ch(1, spc: 0),
    };
    for (final e in differences.entries) {
      testWidgets('channels that differ in ${e.key}', (tester) async {
        await _open(tester, _design([_ch(0), e.value]));
        _expectDetailScreen();
      });
    }

    testWidgets('a Pattern Editor design whose channels differ', (tester) async {
      await _open(
          tester,
          _design([_ch(0), _ch(1, sx: 200)],
              tags: const [kPatternEditorDesignTag]));
      _expectDetailScreen();
    });
  });

  group('the detail screen, exactly as before', () {
    testWidgets('a painted design', (tester) async {
      await _open(
          tester,
          _design([
            const ChannelDesign(
              channelId: 0,
              channelName: 'Front',
              ledCount: 6,
              colorGroups: [
                LedColorGroup(startLed: 0, endLed: 2, color: [255, 0, 0, 0]),
                LedColorGroup(startLed: 3, endLed: 5, color: [0, 0, 255, 0]),
              ],
              effectId: 28,
            ),
          ], perPixel: true));
      _expectDetailScreen();
    });

    testWidgets('an AI design', (tester) async {
      await _open(
          tester,
          _design([_ch(0), _ch(1)],
              composedPattern: const {'has_motion': true, 'effect_id': 28}));
      _expectDetailScreen();
    });

    testWidgets('a Solid colour (effect 0)', (tester) async {
      await _open(tester, _design([_ch(0, fx: 0), _ch(1, fx: 0)]));
      _expectDetailScreen();
    });

    testWidgets('a design with no channel left in', (tester) async {
      await _open(tester, _design([_ch(0, included: false)]));
      _expectDetailScreen();
    });
  });
}
