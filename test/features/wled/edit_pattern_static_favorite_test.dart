// The Edit Pattern screen's heart, in STATIC mode.
//
// It used to decline — "This mode is stored LED by LED — tap SAVE to keep it in
// My Designs." — because My Favorites re-applied a favorite as one message and
// `applyJson` refuses anything over 4 KB. These tests drive the real screen and
// assert what the heart now hands the favorites writer.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/favorites/favorite_design_payload.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/edit_pattern_screen.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/widgets/favorite_heart_button.dart';

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 0),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];

EditablePattern _chiefs({int fx = 0}) => EditablePattern.fromGradientColors(
      id: 'team_nfl_chiefs',
      name: 'Kansas City Chiefs',
      colors: const [Color(0xFFE31837), Color(0xFFFFB81C)],
      effectId: fx,
    ).copyWith(actionColors: const [
      Color(0xFFE31837),
      Color(0xFFFFB81C),
      Color(0xFFFFFFFF),
    ], brightness: 180);

class _RecordingFavorites extends FavoritesNotifier {
  final added = <({String id, String name, Map<String, dynamic> data})>[];

  @override
  void build() {}

  @override
  Future<void> addFavorite({
    required String patternId,
    required String patternName,
    required Map<String, dynamic> patternData,
    bool autoAdded = false,
  }) async =>
      added.add((id: patternId, name: patternName, data: patternData));
}

// ignore: subtype_of_sealed_class
class _StubUser implements User {
  @override
  String get uid => 'u1';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

Future<_RecordingFavorites> _pump(
  WidgetTester tester, {
  required EditablePattern pattern,
  List<DeviceChannel> channels = _channels,
}) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final favorites = _RecordingFavorites();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      designsStreamProvider
          .overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue('u1'),
      deviceChannelsProvider.overrideWithValue(channels),
      effectiveChannelIdsProvider
          .overrideWithValue([for (final c in channels) c.id]),
      wledRepositoryProvider.overrideWith((ref) => null),
      demoModeProvider.overrideWith((ref) => true),
      authStateProvider.overrideWith((ref) => Stream<User?>.value(_StubUser())),
      favoritedPatternIdsProvider
          .overrideWith((ref) => Stream.value(const <String>{})),
      favoritesNotifierProvider.overrideWith(() => favorites),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
    ],
    child: MaterialApp(home: EditPatternScreen(initialPattern: pattern)),
  ));
  final container =
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  await container.read(authStateProvider.future);
  await tester.pump();
  return favorites;
}

Future<void> _tapHeart(WidgetTester tester) async {
  await tester.tap(find.byType(FavoriteHeartButton));
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Static: the heart SAVES — it no longer declines and points at '
      'SAVE', (tester) async {
    final favorites = await _pump(tester, pattern: _chiefs());
    await _tapHeart(tester);

    expect(find.textContaining('stored LED by LED'), findsNothing);
    expect(find.textContaining('tap SAVE'), findsNothing);
    expect(favorites.added, hasLength(1));
    expect(favorites.added.single.id, 'team_nfl_chiefs');
    expect(favorites.added.single.name, 'Kansas City Chiefs');
  });

  testWidgets('Static: what it stores is the design SAVE would store — both '
      'channels, every LED, the chosen brightness', (tester) async {
    final favorites = await _pump(tester, pattern: _chiefs());
    await _tapHeart(tester);

    final stored = perPixelDesignOfFavorite(favorites.added.single.data);
    expect(stored, isNotNull, reason: 'a per-pixel favorite, not an `i` payload');

    final saved = customDesignFromEditablePattern(
      pattern: _chiefs(),
      name: 'Kansas City Chiefs',
      ownerId: '',
      channels: const [
        PatternEditorChannel(id: 0, name: 'Channel 1', ledCount: 128),
        PatternEditorChannel(id: 1, name: 'Channel 2', ledCount: 162),
      ],
    );
    expect(stored!.perPixel, isTrue);
    expect(stored.brightness, 180);
    expect(stored.channels.map((c) => c.ledCount), [128, 162]);
    expect(stored.channels.map((c) => c.toJson()).toList(),
        saved.channels.map((c) => c.toJson()).toList());
  });

  testWidgets('Animated: unchanged — one WLED payload, no embedded design',
      (tester) async {
    final favorites = await _pump(tester, pattern: _chiefs(fx: 15));
    await _tapHeart(tester);

    final data = favorites.added.single.data;
    expect(data.containsKey(kFavoriteDesignKey), isFalse);
    expect(perPixelDesignOfFavorite(data), isNull);
    expect(((data['seg'] as List).first as Map)['fx'], 15);
  });

  testWidgets('Static with no channel lengths: says why, writes nothing',
      (tester) async {
    final favorites =
        await _pump(tester, pattern: _chiefs(), channels: const []);
    await _tapHeart(tester);

    expect(favorites.added, isEmpty);
    expect(find.textContaining('Connect to your lights to favorite'),
        findsOneWidget);
    expect(find.text('Failed to save favorite'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
