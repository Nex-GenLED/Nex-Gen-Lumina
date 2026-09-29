// +110 E1 — the Pattern Editor, driven from its real controls.
//
// Row 43: the heart is keyed by a fresh id per name, never the source
// palette's. Row 94: DIRECTION is Left ↔ Right through the direction door,
// and a refusal flips it back. Row 95: BG COLOR shows only where a background
// reaches the lights, and goes in WLED's background slot. Item D: a new MODE
// starts at its roofline speed.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/edit_pattern_screen.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/edit_pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/widgets/favorite_heart_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

class _GeoRepo extends RecordingWledRepository {
  _GeoRepo({this.geometryOk = true});
  bool geometryOk;
  final geometry = <Map<String, dynamic>>[];

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async {
    geometry.add(payload);
    return geometryOk;
  }
}

class _RecordingFavorites extends FavoritesNotifier {
  final added = <({String id, String name})>[];

  @override
  void build() {}

  @override
  Future<void> addFavorite({
    required String patternId,
    required String patternName,
    required Map<String, dynamic> patternData,
    bool autoAdded = false,
  }) async =>
      added.add((id: patternId, name: patternName));
}

// ignore: subtype_of_sealed_class
class _StubUser implements User {
  @override
  String get uid => 'u1';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

Future<({ProviderContainer c, _RecordingFavorites favorites})> _pump(
  WidgetTester tester,
  EditablePattern pattern, {
  _GeoRepo? repo,
  Set<String> favorited = const {},
}) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final favorites = _RecordingFavorites();
  final c = ProviderContainer(overrides: [
    designsStreamProvider
        .overrideWith((ref) => Stream.value(const <CustomDesign>[])),
    effectiveUserUidProvider.overrideWithValue('u1'),
    deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
    participatingChannelIdsProvider.overrideWithValue(null),
    wledRepositoryProvider.overrideWith((ref) => repo ?? _GeoRepo()),
    wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    demoModeProvider.overrideWith((ref) => false),
    authStateProvider.overrideWith((ref) => Stream<User?>.value(_StubUser())),
    favoritedPatternIdsProvider.overrideWith((ref) => Stream.value(favorited)),
    favoritesNotifierProvider.overrideWith(() => favorites),
    currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
  ]);
  addTearDown(c.dispose);
  await c.read(authStateProvider.future);
  await c.read(wledConnectivityStatusProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(home: EditPatternScreen(initialPattern: pattern)),
  ));
  await tester.pump();
  await tester.pump();
  return (c: c, favorites: favorites);
}

Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

EditablePattern _pattern({
  String id = 'edit_1',
  int fx = 28,
  List<Color> colors = const [Color(0xFF0000FF)],
}) =>
    EditablePattern(
      id: id,
      name: 'Blue Chase',
      actionColors: colors,
      effectId: fx,
      speed: 128,
      brightness: 120,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('row 43 — the heart', () {
    testWidgets('a favourited SOURCE palette does not fill the editor\'s heart, '
        'and a tap adds a NEW favourite under the typed name — never deletes '
        'the palette\'s', (tester) async {
      // The id the tuner used to open the editor with: the palette's own.
      final r = await _pump(tester, _pattern(id: 'team_nfl_chiefs'),
          favorited: {'team_nfl_chiefs'});

      expect(find.byIcon(Icons.favorite_border), findsOneWidget,
          reason: 'this editor has not favourited anything yet');

      await tester.tap(find.byType(FavoriteHeartButton));
      await _frames(tester, 2);
      expect(r.favorites.added.single.name, 'Blue Chase');
      expect(r.favorites.added.single.id, isNot('team_nfl_chiefs'));
    });

    testWidgets('after a rename, the heart saves a second favourite under the '
        'NEW name (the old name could never change — the rules keep it)',
        (tester) async {
      final r = await _pump(tester, _pattern());
      await tester.tap(find.byType(FavoriteHeartButton));
      await _frames(tester, 2);

      await tester.enterText(find.byType(TextField).first, 'Blue Chase Slow');
      await tester.pump();
      await tester.tap(find.byType(FavoriteHeartButton));
      await _frames(tester, 2);

      expect([for (final a in r.favorites.added) a.name],
          ['Blue Chase', 'Blue Chase Slow']);
      expect(r.favorites.added[0].id, isNot(r.favorites.added[1].id));
    });
  });

  group('row 94 — DIRECTION', () {
    testWidgets('Right → Left goes through the direction door (rev on every '
        'channel) and cycles Left ↔ Right — no "Center"', (tester) async {
      final repo = _GeoRepo();
      await _pump(tester, _pattern(), repo: repo);
      final card = find.byKey(const ValueKey('edit-pattern-direction'));

      await tester.tap(card);
      await _frames(tester, 2);
      expect(repo.geometry.single, {
        'seg': [
          {'id': 0, 'rev': true},
          {'id': 1, 'rev': true},
        ],
      });
      expect(find.descendant(of: card, matching: find.text('Left')),
          findsOneWidget);

      await tester.tap(card);
      await _frames(tester, 2);
      expect(find.descendant(of: card, matching: find.text('Right')),
          findsOneWidget);
      expect(find.text('Center'), findsNothing);
      expect(repo.applied, isEmpty,
          reason: 'a direction change is not a look re-send');
    });

    testWidgets('a refused change flips back and says so', (tester) async {
      final repo = _GeoRepo(geometryOk: false);
      final r = await _pump(tester, _pattern(), repo: repo);
      final card = find.byKey(const ValueKey('edit-pattern-direction'));

      await tester.tap(card);
      await _frames(tester, 2);

      expect(find.descendant(of: card, matching: find.text('Right')),
          findsOneWidget);
      expect(r.c.read(wledCommandFailureProvider)?.message,
          contains("Direction couldn't be changed"));
    });
  });

  group('row 95 — BG COLOR', () {
    testWidgets('hidden for Static', (tester) async {
      await _pump(tester, _pattern(fx: 0));
      expect(find.byKey(const ValueKey('edit-pattern-bg-color')), findsNothing);
    });

    testWidgets('hidden with two or more colours (slot 2 is colour 2)',
        (tester) async {
      await _pump(tester,
          _pattern(colors: const [Color(0xFF0000FF), Color(0xFFFF0000)]));
      expect(find.byKey(const ValueKey('edit-pattern-bg-color')), findsNothing);
    });

    testWidgets('shown for one animated colour — and the chosen background '
        'reaches the lights as WLED\'s background slot (col[1])',
        (tester) async {
      final repo = _GeoRepo();
      await _pump(tester, _pattern(), repo: repo);
      final bg = find.byKey(const ValueKey('edit-pattern-bg-color'));
      expect(bg, findsOneWidget);

      await tester.tap(bg);
      await tester.pump();
      await tester.tap(find.text(PresetColors.all.first.label).first);
      await _frames(tester, 4);

      final seg = (repo.applied.last['seg'] as List).cast<Map>().first;
      final c = PresetColors.all.first.color;
      expect((seg['col'] as List)[1],
          [c.red, c.green, c.blue, 0]);
    });
  });

  testWidgets('item D — a new MODE starts at its roofline speed',
      (tester) async {
    final repo = _GeoRepo();
    await _pump(tester, _pattern(), repo: repo);

    await tester.tap(find.text('MODE'));
    await _frames(tester, 6); // the preview animates forever
    // The sheet's own list (lazy), not the editor behind it.
    final sheetList = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byType(Scrollable));
    final target = find.descendant(
        of: find.byType(DraggableScrollableSheet), matching: find.text('Juggle'));
    await tester.scrollUntilVisible(target, 300, scrollable: sheetList.first);
    await tester.ensureVisible(target);
    await _frames(tester, 2);
    await tester.tap(target);
    await _frames(tester, 4);

    final seg = (repo.applied.last['seg'] as List).cast<Map>().first;
    expect(seg['fx'], 64);
    expect(seg['sx'], effectDefaultSpeed(64));
  });
}
