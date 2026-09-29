// +110 E1 follow-ups — Explore, the palette tuner, the Pattern Editor and the
// wire, each driven from the real control. (The Home Tune panel's are in
// test/widgets/pattern_adjustment_panel_followups_test.dart.)
//
//   1. An Explore search-result card set the house to the catalogue's stored
//      brightness and opened the adjustment sheet on every tap.
//   3. "Connect to venue Wi-Fi" (commercial copy) shown to homeowners.
//   4. Away from home, a drag queued one slow relay command per pause.
//   5. The two unbuilt category-screen widgets that still carried the
//      channel-switch-off bug are gone.
//   Strobe (owner decision 2026-09-29): Strobe / Strobe Rainbow capped at
//      sx 240; Strobe Mega removed from every picker, and a stored reference
//      degrades to Strobe rather than failing.

import 'dart:convert';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/favorites/favorite_brightness.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart';
import 'package:nexgen_command/features/wled/edit_pattern_screen.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/effect_database.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_flash_safety.dart';
import 'package:nexgen_command/features/wled/pattern_grid_widgets.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_tweak_sender.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/widgets/effect_speed_slider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';

// ── harness ────────────────────────────────────────────────────────────────

ProviderContainer _container(
  RecordingWledRepository repo, {
  ConnectivityStatus status = ConnectivityStatus.local,
  SiteMode mode = SiteMode.residential,
  List<Override> extra = const [],
}) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
    wledConnectivityStatusProvider
        .overrideWith((ref) => Stream<ConnectivityStatus>.value(status)),
    deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
    participatingChannelIdsProvider.overrideWithValue(null),
    currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
    demoModeProvider.overrideWith((ref) => false),
    userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
    siteModeProvider.overrideWith((ref) => mode),
    authStateProvider.overrideWith((_) => Stream<User?>.value(null)),
    ...extra,
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _pump(WidgetTester tester, ProviderContainer c, Widget body,
    {Size size = const Size(900, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await c.read(wledConnectivityStatusProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp(home: Scaffold(body: body)),
  ));
  await tester.pump();
}

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A drag in [steps] moves, pausing longer than the at-home debounce and
/// shorter than the away settle between them. Returns the held gesture.
Future<TestGesture> _dragInSteps(WidgetTester tester, Finder slider,
    {int steps = 5}) async {
  final start = tester.getTopLeft(slider) + const Offset(30, 20);
  final g = await tester.startGesture(start);
  for (var i = 0; i < steps; i++) {
    await g.moveBy(const Offset(25, 0));
    await tester.pump(const Duration(milliseconds: 400));
  }
  return g;
}

/// A catalogue search result, as pattern_repository.dart builds them: the
/// catalogue states `bri` 200 on every such card.
final _card = PatternItem(
  id: 'gen_ocean_fx_28',
  name: 'Blue Chase',
  imageUrl: '',
  categoryId: 'cat_holiday',
  wledPayload: const {
    'on': true,
    'bri': 200,
    'seg': [
      {
        'fx': 28,
        'sx': 60,
        'col': [
          [0, 0, 255, 0]
        ]
      }
    ],
  },
);

Widget _cardHost(PatternItem item) =>
    SizedBox(width: 200, height: 220, child: PatternCard(pattern: item));

Future<void> _tapCardThenAdjust(WidgetTester tester) async {
  await tester.tap(find.text('Blue Chase'));
  await _settle(tester);
  await tester.tap(find.text('Adjust'));
  await _settle(tester);
}

const _palette = LibraryNode(
  id: 'ocean_breeze',
  name: 'Ocean Breeze',
  nodeType: LibraryNodeType.palette,
  parentId: 'cat_water',
  themeColors: [Color(0xFF0066FF), Color(0xFFFFFFFF)],
);

/// A design saved before the retirement, with Strobe Mega at a fast speed.
CustomDesign _megaDesign() => CustomDesign(
      id: 'd_mega',
      name: 'Party Flash',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      ownerId: 'customer-test',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0, 0]),
          ],
          effectId: 25,
          speed: 250,
          intensity: 200,
        ),
      ],
      brightness: 150,
      brightnessStated: true,
      tags: const [kPatternEditorDesignTag],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── 1 ──────────────────────────────────────────────────────────────────
  group('item 1 — an Explore search-result card', () {
    testWidgets('applies WITHOUT the catalogue\'s brightness, and does NOT '
        'open the adjustment sheet', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo);
      await _pump(tester, c, _cardHost(_card));

      await tester.tap(find.text('Blue Chase'));
      await _settle(tester);

      final sent = repo.applied.single;
      expect(sent.containsKey('bri'), isFalse,
          reason: 'the catalogue\'s 200 is nobody\'s choice');
      expect(sent['on'], isTrue);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Applied Blue Chase'), findsOneWidget);
      expect(c.read(wledStateProvider).brightness, kHomeLitState.brightness,
          reason: 'Home shows the level the lights are actually at');
    });

    testWidgets('"Adjust" on the confirmation opens the sheet — on request',
        (tester) async {
      final c = _container(RecordingWledRepository());
      await _pump(tester, c, _cardHost(_card));
      await _tapCardThenAdjust(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('a level the customer chose (marked) is kept; the marker never '
        'reaches the lights', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo);
      final marked = PatternItem(
        id: 'mine',
        name: 'Blue Chase',
        imageUrl: '',
        categoryId: 'cat_holiday',
        wledPayload: markFavoriteBrightnessStated({
          ..._card.wledPayload,
          'bri': 90,
        }),
      );
      await _pump(tester, c, _cardHost(marked));
      await tester.tap(find.text('Blue Chase'));
      await _settle(tester);

      expect(repo.applied.single['bri'], 90);
      expect(repo.applied.single.containsKey(kFavoriteBrightnessStatedKey),
          isFalse);
    });
  });

  // ── 3 ──────────────────────────────────────────────────────────────────
  group('item 3 — direction away from home, residential wording', () {
    testWidgets('the Explore sheet', (tester) async {
      final c = _container(RecordingWledRepository(),
          status: ConnectivityStatus.remote);
      await _pump(tester, c, _cardHost(_card));
      await _tapCardThenAdjust(tester);

      final text = tester
          .widget<Text>(find.byKey(const ValueKey('sheet-direction-away')))
          .data!;
      expect(text, directionLanOnlyMessage(SiteMode.residential));
      expect(text.toLowerCase(), isNot(contains('venue')));
    });

    testWidgets('the Pattern Editor\'s DIRECTION card', (tester) async {
      final c = _container(RecordingWledRepository(),
          status: ConnectivityStatus.remote, extra: _editorOverrides());
      await _pump(tester, c,
          const EditPatternScreen(initialPattern: _editorPattern),
          size: const Size(1200, 4200));

      await tester.tap(find.byKey(const ValueKey('edit-pattern-direction')));
      await _settle(tester, 2);

      final message = c.read(wledCommandFailureProvider)?.message;
      expect(message, directionLanOnlyMessage(SiteMode.residential));
      expect(message!.toLowerCase(), isNot(contains('venue')));
    });
  });

  // ── 4 ──────────────────────────────────────────────────────────────────
  group('item 4 — away, a drag sends ONE write when it settles', () {
    testWidgets('the Explore sheet', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, status: ConnectivityStatus.remote);
      await _pump(tester, c, _cardHost(_card));
      await _tapCardThenAdjust(tester);
      final before = repo.applied.length;

      final intensity = find.descendant(
          of: find.byType(BottomSheet), matching: find.byType(Slider)).at(1);
      final g = await _dragInSteps(tester, intensity);
      expect(repo.applied.length, before, reason: 'nothing mid-drag');
      await g.up();
      await _settle(tester);
      expect(repo.applied.length, before + 1);
    });

    testWidgets('the palette tuner\'s live preview', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo, status: ConnectivityStatus.remote);
      await _pump(tester, c,
          const ColorwayEffectSelectorPage(paletteNode: _palette),
          size: const Size(1200, 3000));
      await _settle(tester);

      final intensity = find.byType(Slider).at(1);
      final g = await _dragInSteps(tester, intensity);
      expect(repo.applied, isEmpty, reason: 'nothing mid-drag');
      await g.up();
      await _settle(tester);
      expect(repo.applied, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink()); // Back restores
      await _settle(tester);
    });

    testWidgets('the Pattern Editor', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo,
          status: ConnectivityStatus.remote, extra: _editorOverrides());
      await _pump(tester, c,
          const EditPatternScreen(initialPattern: _editorPattern),
          size: const Size(1200, 4200));
      await _settle(tester);
      final before = repo.applied.length;

      // BRIGHTNESS is the first parameter slider under the preview.
      final brightness = find
          .ancestor(of: find.text('BRIGHTNESS'), matching: find.byType(Column))
          .first;
      final slider =
          find.descendant(of: brightness, matching: find.byType(Slider));
      final g = await _dragInSteps(tester, slider);
      expect(repo.applied.length, before, reason: 'nothing mid-drag');
      await g.up();
      await _settle(tester);
      expect(repo.applied.length, before + 1);
    });
  });

  // ── 5 ──────────────────────────────────────────────────────────────────
  test('item 5 — the unbuilt category-screen widgets (and their full-partition '
      'tweaks) are gone', () {
    final src =
        File('lib/features/wled/pattern_category_detail.dart').readAsStringSync();
    expect(src, isNot(contains('class PatternControlCard')));
    expect(src, isNot(contains('class PatternCategoryRow')));
    expect(src, isNot(contains('applyChannelFilter(')),
        reason: 'no adjustment on this screen may use the design partition');
  });

  // ── Strobe ─────────────────────────────────────────────────────────────
  group('Strobe — the wire (every applyJson / savePreset, local and relay)',
      () {
    Map<String, dynamic> seg0(Map<String, dynamic> p) =>
        Map<String, dynamic>.from((p['seg'] as List).first as Map);

    test('a stored Strobe Mega plays Strobe, at the capped speed', () {
      final out = seg0(normalizeWledPayload({
        'seg': [
          {
            'fx': 25,
            'sx': 250,
            'ix': 255,
            'col': [
              [255, 0, 0, 0]
            ]
          }
        ]
      }));
      expect(out['fx'], 23);
      expect(out['sx'], kStrobeSpeedCap);
      expect(out['ix'], kRetiredEffectFallbackIntensity);
    });

    test('Strobe and Strobe Rainbow above 240 come down to 240; anything '
        'else is untouched', () {
      for (final fx in [23, 24]) {
        expect(seg0(normalizeWledPayload({
          'seg': [
            {'fx': fx, 'sx': 255}
          ]
        }))['sx'], 240);
      }
      expect(seg0(normalizeWledPayload({
        'seg': [
          {'fx': 23, 'sx': 200}
        ]
      }))['sx'], 200);
      expect(seg0(normalizeWledPayload({
        'seg': [
          {'fx': 28, 'sx': 255}
        ]
      }))['sx'], 255);
    });

    test('AWAY: the relay queues the degraded look, not Strobe Mega', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final fs = FakeFirebaseFirestore();
      final relay = CloudRelayRepository(
        userId: 'u1',
        controllerId: 'c1',
        controllerIp: '192.0.2.10',
        webhookUrl: '',
        firestore: fs,
        commandTimeout: const Duration(milliseconds: 50),
      );
      await relay.applyJson({
        'on': true,
        'seg': [
          {
            'id': 0,
            'fx': 25,
            'sx': 250,
            'col': [
              [255, 0, 0, 0]
            ]
          }
        ],
      });
      final docs = (await fs.collection('users/u1/commands').get()).docs;
      final sent = jsonDecode(docs.single.data()['payload'] as String)
          as Map<String, dynamic>;
      final fxs = [
        for (final s in (sent['seg'] as List).cast<Map>())
          if (s['fx'] != null) s['fx'],
      ];
      expect(fxs, everyElement(23));
      expect(jsonEncode(sent), isNot(contains('"fx":25')));
    });

    test('a bare speed tweak on a live Strobe is capped too', () {
      expect(capAdjustmentForLiveEffect({'sx': 255}, 23), {'sx': 240});
      expect(capAdjustmentForLiveEffect({'sx': 255}, 28), {'sx': 255});
      expect(capAdjustmentForLiveEffect({'fx': 28, 'sx': 255}, 23),
          {'fx': 28, 'sx': 255},
          reason: 'a tweak that names its effect is the normalizer\'s job');
    });
  });

  group('Strobe — no picker offers Strobe Mega', () {
    test('the catalog: every offered list leaves it out; it still has a name',
        () {
      bool has25(Iterable<WledEffect> l) => l.any((e) => e.id == 25);
      expect(has25(WledEffectsCatalog.offeredEffects), isFalse);
      expect(has25(WledEffectsCatalog.standardEffects), isFalse);
      expect(has25(WledEffectsCatalog.topPicks), isFalse);
      expect(has25(WledEffectsCatalog.celebrationPicks), isFalse);
      expect(has25(WledEffectsCatalog.getByCategory('Strobe')), isFalse);
      expect(WledEffectsCatalog.getByCategory('Strobe').map((e) => e.id),
          contains(23));
      for (final l in WledEffectsCatalog.effectsBySelectorMood.values) {
        expect(has25(l), isFalse);
      }
      for (final l in WledEffectsCatalog.effectsByMotionType.values) {
        expect(has25(l), isFalse);
      }
      expect(WledEffectsCatalog.getName(25), 'Strobe Mega',
          reason: 'an old reference can still be named');
    });

    test('Lumina\'s recommendation database never picks it', () {
      expect(EffectDatabase.getEffect(25), isNull);
      expect(EffectDatabase.findMatchingEffects(requireColorRespect: false)
          .any((e) => e.id == 25), isFalse);
    });

    testWidgets('the palette tuner: the full effect list has Strobe, and no '
        'Strobe Mega', (tester) async {
      final c = _container(RecordingWledRepository());
      await _pump(tester, c,
          const ColorwayEffectSelectorPage(paletteNode: _palette),
          size: const Size(1200, 12000));
      await _settle(tester);
      // The default view is the top picks; the full list is behind a motion
      // chip. Tap the one Strobe sits under — where Strobe Mega sat too.
      final motion = WledEffectsCatalog.getMotionTypeById(23);
      await tester.tap(find.textContaining(motion.displayName).first);
      await _settle(tester);
      expect(find.text('Strobe'), findsWidgets, reason: 'the strobes listed');
      expect(find.text('Strobe Mega'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the celebration picker: a stored Strobe Mega pick opens on '
        'Strobe; Mega is not offered', (tester) async {
      final c = _container(RecordingWledRepository());
      await _pump(
        tester,
        c,
        ColorwayEffectSelectorPage(
          paletteNode: _palette,
          celebrationMode: true,
          initialEffectId: 25,
          initialSpeed: 250,
          onDesignSelected: (_) {},
        ),
        size: const Size(1200, 3000),
      );
      await _settle(tester);
      expect(c.read(selectorEffectIdProvider), 23);
      expect(c.read(selectorSpeedProvider), lessThanOrEqualTo(240));
      expect(find.text('Strobe Mega'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a stored design with Strobe Mega opens on Strobe at 240, and '
        'Apply sends Strobe', (tester) async {
      final repo = RecordingWledRepository();
      final c = _container(repo);
      await _pump(tester, c,
          ColorwayEffectSelectorPage.forDesign(design: _megaDesign()),
          size: const Size(1200, 3000));
      await _settle(tester);

      expect(c.read(selectorEffectIdProvider), 23);
      expect(c.read(selectorSpeedProvider), 240);

      await tester.tap(find.byKey(const ValueKey('apply-design')));
      await _settle(tester);
      final seg = (repo.applied.single['seg'] as List)
          .cast<Map>()
          .firstWhere((s) => s['fx'] != null);
      expect(seg['fx'], 23);
      expect(seg['sx'], 240);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the Pattern Editor opened on a Strobe Mega pattern shows '
        'Strobe', (tester) async {
      final c = _container(RecordingWledRepository(),
          extra: _editorOverrides());
      await _pump(
        tester,
        c,
        const EditPatternScreen(
          initialPattern: EditablePattern(
            id: 'edit_mega',
            name: 'Party Flash',
            actionColors: [Color(0xFFFF0000)],
            effectId: 25,
            speed: 250,
          ),
        ),
        size: const Size(1200, 4200),
      );
      await _settle(tester, 2);
      expect(find.text('Strobe Mega'), findsNothing);
      expect(find.text('Strobe'), findsWidgets);
    });

    testWidgets('the speed slider never offers a Strobe above 240',
        (tester) async {
      final seen = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: EffectSpeedSlider(
            rawSpeed: 128,
            effectId: 23,
            initialExtended: true,
            onChanged: seen.add,
          ),
        ),
      ));
      await tester.pump();
      await tester.drag(find.byType(Slider), const Offset(2000, 0));
      await tester.pump();
      expect(seen, isNotEmpty);
      expect(seen.every((v) => v <= kStrobeSpeedCap), isTrue, reason: '$seen');
    });
  });
}

const _editorPattern = EditablePattern(
  id: 'edit_1',
  name: 'Blue Chase',
  actionColors: [Color(0xFF0000FF)],
  effectId: 28,
  speed: 128,
  brightness: 120,
);

List<Override> _editorOverrides() => [
      designsStreamProvider
          .overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue('customer-test'),
      favoritedPatternIdsProvider
          .overrideWith((ref) => Stream.value(const <String>{})),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
    ];
