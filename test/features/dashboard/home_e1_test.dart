// +110 E1 — Home, driven from its real controls (the real WledDashboardPage
// under test/helpers/home_dashboard_harness.dart).
//
// Rows: 1, 23, 24, 25/76, 77, 78, 79, 82, 83 and owner items A, B, E.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/dashboard/wled_dashboard_page.dart';
import 'package:nexgen_command/features/dashboard/widgets/channel_selector_bar.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_presets_section.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart'
    as fav;
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart'
    show LibraryDesignSelection;
import 'package:nexgen_command/features/wled/pattern_theme_selection.dart'
    show LibraryBrowserScreen;
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

FavoritePattern _fav(String id, String name, Map<String, dynamic> data) =>
    FavoritePattern(
      id: id,
      patternName: name,
      addedAt: DateTime(2026, 9, 1),
      usageCount: 1,
      patternData: data,
      autoAdded: false,
    );

/// A favourite as Explore's "Save…" stores it: at the handed-back 255.
Map<String, dynamic> _savedAt255() => {
      'on': true,
      'bri': 255,
      'seg': [
        {
          'fx': 28,
          'sx': 60,
          'ix': 128,
          'pal': 5,
          'col': [
            [0, 200, 0, 0],
            [255, 255, 255, 0],
          ],
        }
      ],
    };

SmartSuggestion _suggestion(String id, SuggestionType type,
        [Map<String, dynamic> data = const {}]) =>
    SmartSuggestion(
      id: id,
      type: type,
      title: 'Suggestion $id',
      description: 'Try this',
      createdAt: DateTime(2026, 9, 29),
      actionData: data,
      priority: 0.5,
    );

/// Records what the Favorites picker saves, and whether the tile being
/// replaced still existed at that moment.
class _RecordingFavorites extends fav.FavoritesNotifier {
  _RecordingFavorites(this.db);
  final FakeFirebaseFirestore db;
  final saved = <({String name, bool oldTileStillThere})>[];
  final replaced = <({String replaceId, String name})>[];

  @override
  Future<void> addToFavorites({
    required String patternId,
    required String patternName,
    required Map<String, dynamic> wledPayload,
  }) async {
    final old = await db.doc('users/customer-test/favorites/f1').get();
    saved.add((name: patternName, oldTileStillThere: old.exists));
  }

  /// #164: a replace is ONE write — recorded, then applied to the fake.
  @override
  Future<void> replaceFavorite({
    required String replaceId,
    required String patternId,
    required String patternName,
    required Map<String, dynamic> patternData,
  }) async {
    replaced.add((replaceId: replaceId, name: patternName));
    final batch = db.batch();
    batch.delete(db.doc('users/customer-test/favorites/$replaceId'));
    batch.set(db.doc('users/customer-test/favorites/$patternId'),
        {'pattern_name': patternName});
    await batch.commit();
  }
}

class _FakeSuggestions extends SuggestionsNotifier {
  _FakeSuggestions(this.ok, this.dismissed);
  final bool ok;
  final List<String> dismissed;

  @override
  Future<bool> dismissSuggestion(String suggestionId) async {
    dismissed.add(suggestionId);
    return ok;
  }
}

class _SpyNotifier extends SeededWledNotifier {
  _SpyNotifier(super.seed);
  int reconnects = 0;

  @override
  Future<void> refreshConnection() async => reconnects++;
}

UserModel _profile({List<String> hidden = const []}) => UserModel(
      id: 'customer-test',
      email: 'customer@example.com',
      displayName: 'Customer',
      ownerId: 'customer-test',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      favoriteWhitesHidden: hidden,
    );

Future<HomeHarness> _pumpWith(
  WidgetTester tester,
  List<Override> extra, {
  RecordingWledRepository? repo,
  WledStateModel state = kHomeLitState,
  List<FavoritePattern> favorites = const [],
  List<FavoritePattern>? whites,
  List<SmartSuggestion> suggestions = const [],
  UserModel? profile,
  List<DeviceChannel> channels = kHomeTwoChannels,
  bool smartPresets = false,
  List<dynamic>? controllers,
}) async {
  final r = repo ?? RecordingWledRepository();
  final c = ProviderContainer(overrides: [
    ...homeDashboardOverrides(
      repo: r,
      state: state,
      favorites: favorites,
      whites: whites,
      suggestions: suggestions,
      profile: profile,
      channels: channels,
      smartPresets: smartPresets,
      controllers: controllers?.cast(),
    ),
    ...extra,
  ]);
  addTearDown(c.dispose);
  tester.view.physicalSize = const Size(390, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(home: WledDashboardPage()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return HomeHarness(c, r);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('My Favorites — tap (rows 1, 25/76, item B)', () {
    testWidgets('item B: a favourite stored at 255 does NOT jump the house '
        'to 100 % — no `bri` is sent, and the Home preview keeps its level',
        (tester) async {
      final h = await _pumpWith(tester, const [],
          favorites: [_fav('f1', 'Green Chase', _savedAt255())]);

      await tester.tap(find.text('Green Chase'));
      await _settle(tester);

      final sent = h.repo.applied.single;
      expect(sent.containsKey('bri'), isFalse);
      expect(sent['on'], isTrue);
      expect(h.container.read(wledStateProvider).brightness, 120,
          reason: 'the preview shows the level the lights are actually at');
      expect(find.text('Applied: Green Chase'), findsOneWidget);
      await unmountHome(tester);
    });

    testWidgets('the reserved whites (stored at 220) apply at the house level too',
        (tester) async {
      final h = await _pumpWith(tester, const []);
      await tester.tap(find.text('Warm White'));
      await _settle(tester);
      expect(h.repo.applied.single.containsKey('bri'), isFalse);
      await unmountHome(tester);
    });

    testWidgets('row 1: a closed channel gate says WHY — nothing is sent',
        (tester) async {
      final h = await _pumpWith(tester, const [],
          channels: const [],
          favorites: [_fav('f1', 'Green Chase', _savedAt255())]);

      await tester.tap(find.text('Green Chase'));
      await _settle(tester);

      expect(h.repo.writeCount, 0);
      expect(h.container.read(wledCommandFailureProvider)?.message,
          contains("Couldn't read your controller's channels"));
      await unmountHome(tester);
    });

    testWidgets('rows 25/76: a favourite captured with channel 1 left out '
        're-applies its LOOK, and the hero shows its colours, not white',
        (tester) async {
      final stored = {
        'on': true,
        'seg': [
          {'id': 0, 'on': false},
          {
            'id': 1,
            'on': true,
            'fx': 28,
            'col': [
              [0, 0, 255, 0],
              [255, 0, 0, 0],
            ],
          },
        ],
      };
      final h = await _pumpWith(tester, const [],
          favorites: [_fav('f2', 'Blue Garage', stored)]);

      await tester.tap(find.text('Blue Garage'));
      await _settle(tester);

      final segs = (h.repo.applied.single['seg'] as List).cast<Map>();
      for (final s in segs) {
        expect(s['fx'], 28, reason: 'channel ${s['id']} got the look');
        expect(s['col'], isNotNull);
      }
      expect(h.container.read(wledStateProvider).colorSequence.first,
          const Color(0xFF0000FF));
      await unmountHome(tester);
    });
  });

  group('My Favorites — editable (item A)', () {
    testWidgets('#164: an account over the cap (from before it) sees EVERY '
        'favourite it has, and no "+"', (tester) async {
      await _pumpWith(tester, const [], favorites: [
        _fav('f1', 'One', _savedAt255()),
        _fav('f2', 'Two', _savedAt255()),
        _fav('f3', 'Three', _savedAt255()),
      ]);
      for (final n in ['Warm White', 'Bright White', 'One', 'Two', 'Three']) {
        expect(find.text(n), findsOneWidget,
            reason: '$n — existing data is never hidden silently');
      }
      expect(find.byKey(const ValueKey('favorites-add-tile')), findsNothing,
          reason: 'the list is full: change a favourite from its own tile');
      await unmountHome(tester);
    });

    testWidgets('#164: under the cap, EXACTLY ONE "+"', (tester) async {
      await _pumpWith(tester, const [], favorites: [
        _fav('f1', 'One', _savedAt255()),
      ]);
      expect(find.text('One'), findsOneWidget);
      expect(find.byKey(const ValueKey('favorites-add-tile')), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget,
          reason: 'no row of empty slots');
      await unmountHome(tester);
    });

    testWidgets('a reserved white can be REMOVED: long-press → Remove → it is '
        'recorded on the profile', (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/customer-test').set({'id': 'customer-test'});
      await _pumpWith(tester, [
        userServiceProvider.overrideWithValue(UserService(firestore: db)),
      ], profile: _profile());

      await tester.longPress(find.text('Warm White'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('favorite-action-remove')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('favorite-remove-confirm')));
      await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await _settle(tester);

      final doc = await tester.runAsync(() => db.doc('users/customer-test').get());
      expect(doc!.data()!['favorite_whites_hidden'], ['white_primary']);
      await unmountHome(tester);
    });

    testWidgets('a customer favourite can be removed from Edit mode — the '
        'document is deleted', (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/customer-test/favorites/f1').set({'pattern_name': 'One'});
      await _pumpWith(tester, [
        fav.favoritesFirestoreProvider.overrideWithValue(db),
      ], favorites: [_fav('f1', 'One', _savedAt255())]);

      await tester.tap(find.byKey(const ValueKey('favorites-edit-toggle')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('favorite-remove-f1')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('favorite-remove-confirm')));
      await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await _settle(tester);

      final doc = await tester
          .runAsync(() => db.doc('users/customer-test/favorites/f1').get());
      expect(doc!.exists, isFalse);
      expect(find.text('Removed "One" from My Favorites'), findsOneWidget);
      await unmountHome(tester);
    });

    testWidgets('a customer favourite can be REPLACED from Edit mode — the '
        'library opens as the picker; the old tile and the new look change in '
        'ONE write (#164)', (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/customer-test/favorites/f1').set({'pattern_name': 'One'});
      final recorder = _RecordingFavorites(db);
      await _pumpWith(tester, [
        fav.favoritesFirestoreProvider.overrideWithValue(db),
        fav.favoritesNotifierProvider.overrideWith(() => recorder),
      ], favorites: [_fav('f1', 'One', _savedAt255())]);

      await tester.tap(find.byKey(const ValueKey('favorites-edit-toggle')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('favorite-replace-f1')));
      await _settle(tester);

      final picker =
          tester.widget<LibraryBrowserScreen>(find.byType(LibraryBrowserScreen));
      expect(picker.saveDestinationLabel, 'Favorites');

      // The customer picks a look in the library; it hands it back.
      picker.onDesignSelected!(const LibraryDesignSelection(
        id: 'ocean_breeze_28',
        name: 'Ocean Breeze - Chase',
        wledPayload: {
          'seg': [
            {'fx': 28}
          ]
        },
      ));
      await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await _settle(tester);

      expect(recorder.saved, isEmpty,
          reason: 'never a plain add — on a full list that would be refused');
      expect(recorder.replaced.single,
          (replaceId: 'f1', name: 'Ocean Breeze - Chase'));
      final doc = await tester
          .runAsync(() => db.doc('users/customer-test/favorites/f1').get());
      expect(doc!.exists, isFalse);
      expect(find.text('Replaced "One" with "Ocean Breeze - Chase"'),
          findsOneWidget);
      await unmountHome(tester);
    });

    test('a hidden white is not shown', () async {
      // The real favoriteWhiteSlotsProvider, reading the profile.
      final c = ProviderContainer(overrides: [
        currentUserProfileProvider
            .overrideWith((ref) => Stream.value(_profile(hidden: ['white_primary']))),
      ]);
      addTearDown(c.dispose);
      await c.read(currentUserProfileProvider.future);
      final sub = c.listen(favoriteWhiteSlotsProvider, (_, __) {});
      addTearDown(sub.close);
      expect([for (final w in sub.read()) w.id], ['white_complement']);
    });
  });

  group('Suggestions (rows 24, 77, 78)', () {
    testWidgets('row 24: a suggested pattern that is not in the catalog is '
        'UNAVAILABLE — the first catalog pattern is never applied instead',
        (tester) async {
      final h = await _pumpWith(tester, const [], suggestions: [
        _suggestion('s1', SuggestionType.applyPattern,
            {'pattern_name': 'No Such Pattern'}),
      ]);

      await tester.tap(find.byKey(const ValueKey('suggestion-action-s1')));
      await _settle(tester);

      expect(h.repo.writeCount, 0);
      expect(find.textContaining('"No Such Pattern" isn\'t available'),
          findsOneWidget);
      await unmountHome(tester);
    });

    testWidgets('row 24: a suggestion that IS in the catalog applies exactly it',
        (tester) async {
      final h = await _pumpWith(tester, const [], suggestions: [
        _suggestion('s1', SuggestionType.applyPattern,
            {'pattern_name': 'Warm White Glow'}),
      ]);

      await tester.tap(find.byKey(const ValueKey('suggestion-action-s1')));
      await _settle(tester);

      final seg = firstDesign(h.repo.applied.single);
      // Warm White Glow is a two-colour Solid, which goes out as Solid
      // Pattern (fx 83) — the catalog pattern itself, nothing substituted.
      expect(seg['fx'], 83);
      expect(h.repo.applied.single.containsKey('bri'), isFalse);
      expect(find.text('Applied: Warm White Glow'), findsOneWidget);
      await unmountHome(tester);
    });

    testWidgets('row 77: kinds Home cannot act on show NO action button',
        (tester) async {
      await _pumpWith(tester, const [], suggestions: [
        _suggestion('a', SuggestionType.automation),
        _suggestion('o', SuggestionType.optimization),
        _suggestion('f', SuggestionType.favorite, {'pattern_name': 'Nope'}),
      ]);
      expect(find.byKey(const ValueKey('suggestion-action-a')), findsNothing);
      expect(find.byKey(const ValueKey('suggestion-action-o')), findsNothing);
      expect(find.byKey(const ValueKey('suggestion-action-f')), findsNothing);
      expect(find.byKey(const ValueKey('suggestion-dismiss-a')), findsOneWidget,
          reason: 'still dismissable');
      await unmountHome(tester);
    });

    testWidgets('row 77: "Got it" acknowledges (dismisses) the reminder',
        (tester) async {
      final dismissed = <String>[];
      await _pumpWith(tester, [
        suggestionsNotifierProvider
            .overrideWith(() => _FakeSuggestions(true, dismissed)),
      ], suggestions: [
        _suggestion('e', SuggestionType.eventReminder),
      ]);
      await tester.tap(find.byKey(const ValueKey('suggestion-action-e')));
      await _settle(tester);
      expect(dismissed, ['e']);
      await unmountHome(tester);
    });

    testWidgets('row 78: a dismissal that fails says so', (tester) async {
      final dismissed = <String>[];
      await _pumpWith(tester, [
        suggestionsNotifierProvider
            .overrideWith(() => _FakeSuggestions(false, dismissed)),
      ], suggestions: [
        _suggestion('d', SuggestionType.eventReminder),
      ]);
      await tester.tap(find.byKey(const ValueKey('suggestion-dismiss-d')));
      await _settle(tester);
      expect(dismissed, ['d']);
      expect(find.text("Couldn't dismiss that suggestion — try again."),
          findsOneWidget);
      expect(find.text('Suggestion dismissed'), findsNothing);
      await unmountHome(tester);
    });

    testWidgets('row 78: a failed SWIPE leaves the card in place',
        (tester) async {
      final dismissed = <String>[];
      await _pumpWith(tester, [
        suggestionsNotifierProvider
            .overrideWith(() => _FakeSuggestions(false, dismissed)),
      ], suggestions: [
        _suggestion('w', SuggestionType.eventReminder),
      ]);
      await tester.drag(find.text('Suggestion w'), const Offset(-500, 0));
      await _settle(tester);
      expect(dismissed, ['w']);
      expect(find.text('Suggestion w'), findsOneWidget);
      expect(find.text('Suggestion dismissed'), findsNothing);
      await unmountHome(tester);
    });
  });

  group('row 79 — the no-controller banner', () {
    testWidgets('says what the condition is, not "check your WiFi"',
        (tester) async {
      await _pumpWith(tester, const [], controllers: const []);
      expect(find.byKey(const ValueKey('no-controller-banner')), findsOneWidget);
      expect(find.textContaining('No controller is set up yet'), findsOneWidget);
      expect(find.textContaining('check your WiFi'), findsNothing);
      await unmountHome(tester);
    });

    testWidgets('is absent when a controller exists', (tester) async {
      await _pumpWith(tester, const []);
      expect(find.byKey(const ValueKey('no-controller-banner')), findsNothing);
      await unmountHome(tester);
    });
  });

  testWidgets('row 83: disconnected — the Now Playing bar says so and offers '
      'Reconnect', (tester) async {
    final spy = _SpyNotifier(kHomeLitState.copyWith(connected: false));
    await _pumpWith(tester, [
      wledStateProvider.overrideWith(() => spy),
    ]);
    expect(find.text(kNowPlayingUnreachable), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('now-playing-reconnect')));
    await tester.pump();
    expect(spy.reconnects, 1);
    await unmountHome(tester);
  });

  group('item E — Smart Presets', () {
    testWidgets('are hidden by default', (tester) async {
      await _pumpWith(tester, const []);
      expect(find.byType(SmartPresetsSection), findsNothing);
      expect(kSmartPresetsOnHome, isFalse,
          reason: 'the flag defaults OFF in every build without the define');
      await unmountHome(tester);
    });

    testWidgets('show when the flag is on', (tester) async {
      await _pumpWith(tester, const [], smartPresets: true);
      expect(find.byType(SmartPresetsSection), findsOneWidget);
      await unmountHome(tester);
    });
  });

  group('row 23 — "All Channels On"', () {
    test('an explicit ON per channel, nothing else', () {
      expect(buildAllChannelsOnPayload([1, 0]), {
        'on': true,
        'seg': [
          {'id': 0, 'on': true},
          {'id': 1, 'on': true},
        ],
      });
    });

    testWidgets('a channel LEFT OUT of shows is switched ON too — the button '
        'does what it says', (tester) async {
      final repo = RecordingWledRepository();
      final c = ProviderContainer(overrides: [
        ...homeDashboardOverrides(repo: repo),
        participatingChannelIdsProvider.overrideWithValue(const [0]),
        channelPowerStatesProvider.overrideWith((ref) => const {0: true, 1: false}),
      ]);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: ChannelSelectorBar()))),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      await tester.tap(find.text('All Channels On'));
      await tester.pump();
      await tester.pump();

      final sent = repo.applied.single;
      expect(sent['seg'], [
        {'id': 0, 'on': true},
        {'id': 1, 'on': true},
      ]);
    });

    testWidgets('a refused write is reported, not ignored', (tester) async {
      final repo = RecordingWledRepository(succeed: false);
      final c = ProviderContainer(overrides: [
        ...homeDashboardOverrides(repo: repo),
        channelPowerStatesProvider.overrideWith((ref) => const {0: true, 1: false}),
      ]);
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: ChannelSelectorBar()))),
      ));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pump();
      await tester.tap(find.text('All Channels On'));
      await tester.pump();
      await tester.pump();
      expect(c.read(wledCommandFailureProvider)?.message,
          contains("Couldn't turn every channel on"));
    });
  });

  group('row 82 — per-channel power follows the poll', () {
    const base = kHomeLitState;
    test('a change that can move channel power triggers a re-read', () {
      expect(channelPowerMayHaveChanged(base, base.copyWith(isOn: false)), isTrue);
      expect(channelPowerMayHaveChanged(base, base.copyWith(effectId: 9)), isTrue);
      expect(channelPowerMayHaveChanged(base, base.copyWith(presetId: 3)), isTrue);
      expect(
          channelPowerMayHaveChanged(
              base, base.copyWith(colorSequence: const [Color(0xFF00FF00)])),
          isTrue);
    });
    test('a poll that changes nothing relevant does not', () {
      expect(channelPowerMayHaveChanged(base, base.copyWith(speed: 3)), isFalse);
      expect(channelPowerMayHaveChanged(null, base), isFalse);
    });

    testWidgets('open chips re-read the device when master power changes',
        (tester) async {
      final repo = RecordingWledRepository(state: {
        'on': true,
        'seg': [
          {'id': 0, 'on': true},
          {'id': 1, 'on': true},
        ],
      });
      final h = await _pumpWith(tester, const [], repo: repo);
      // Open the Tune section, then the channel chips.
      await tester.tap(find.byIcon(Icons.tune_outlined));
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.expand_more).first);
      await _settle(tester);
      final before = repo.getStateCalls;

      // The poll sees the house go dark (a schedule, another phone…).
      h.container.read(wledStateProvider.notifier).state =
          kHomeLitState.copyWith(isOn: false);
      await _settle(tester);

      expect(repo.getStateCalls, greaterThan(before));
      await unmountHome(tester);
    });
  });
}

/// The first segment that carries a look.
Map firstDesign(Map<String, dynamic> payload) => (payload['seg'] as List)
    .cast<Map>()
    .firstWhere((s) => s.containsKey('fx') || s.containsKey('col'));
