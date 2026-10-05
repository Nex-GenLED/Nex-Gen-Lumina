// Owner request from live use, 2026-10-05: the Recent Patterns card on Explore
// keeps its width, loses a third of its height (100 → 66), and names the
// effect it plays, from the #167 catalog. Tapping applies exactly as before,
// and looking at the section writes nothing.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/pattern_library_browser.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/home_dashboard_harness.dart';
import '../../helpers/recording_wled_repository.dart';
import '../../helpers/text_scale_harness.dart';

const _uid = 'u1';

PatternUsageEvent _event(
  String id, {
  String? name,
  int? fx,
  String? effectName,
  String source = 'explore',
  List<List<int>> col = const [
    [0, 70, 255, 0],
    [255, 255, 255, 0],
  ],
}) =>
    PatternUsageEvent(
      id: id,
      createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
      source: source,
      patternName: name,
      effectId: fx,
      effectName: effectName,
      colorNames: const ['blue', 'white'],
      speed: 60,
      intensity: 128,
      wledPayload: {
        'on': true,
        'seg': [
          {if (fx != null) 'fx': fx, 'sx': 60, 'ix': 128, 'col': col}
        ],
      },
    );

/// One entry of every shape the section receives.
final _mixed = [
  // Library designs applied from Explore: the payload's fx, no stored name.
  _event('lib-fade', name: 'Royals Fade', fx: 12),
  _event('lib-dual', name: 'Harvest Running Dual', fx: 52),
  // A Home favorite with no fx in its payload: a Recent tap sends fx 0.
  _event('fav-static', name: 'Warm White', source: 'favorite'),
  // A saved design / scene: fx and colours, but no pattern name.
  _event('saved', fx: 28, source: 'design_studio'),
  // A voice apply whose stored effect_name predates #167.
  _event('voice', name: 'Porch Glow', fx: 63, effectName: 'Candle',
      source: 'voice'),
];

Widget _section(List<PatternUsageEvent> events) => ProviderScope(
      overrides: [
        recentUsageProvider.overrideWith((ref, limit) => Stream.value(events)),
      ],
      child: const SizedBox(width: 358, child: RecentPatternsSection()),
    );

final _cards = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_RecentPatternCard');

Finder _cardOf(String text) =>
    find.ancestor(of: find.text(text), matching: _cards);

class _RecordingUsage extends UsageLoggerNotifier {
  _RecordingUsage(this.log);
  final List<Map<String, dynamic>> log;

  @override
  Future<void> logUsage({
    required String source,
    String? patternName,
    List<String>? colorNames,
    int? effectId,
    String? effectName,
    int? paletteId,
    int? brightness,
    int? speed,
    int? intensity,
    Map<String, dynamic>? wledPayload,
  }) async {
    log.add({'source': source, 'name': patternName, 'fx': effectId});
  }
}

// ignore: subtype_of_sealed_class
class _StubUser implements User {
  @override
  String get uid => _uid;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

ProviderContainer _container(
  RecordingWledRepository repo,
  List<Map<String, dynamic>> log, {
  List<Override> extra = const [],
}) {
  final c = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWith((ref) => repo),
    wledStateProvider.overrideWith(() => SeededWledNotifier(kHomeLitState)),
    wledConnectivityStatusProvider.overrideWith(
        (ref) => Stream<ConnectivityStatus>.value(ConnectivityStatus.local)),
    deviceChannelsProvider.overrideWithValue(kHomeTwoChannels),
    participatingChannelIdsProvider.overrideWithValue(null),
    currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
    demoModeProvider.overrideWith((ref) => false),
    userSyncStatusProvider.overrideWithValue(const UserSyncStatus()),
    usageLoggerNotifierProvider.overrideWith(() => _RecordingUsage(log)),
    ...extra,
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _pump(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await c.read(wledConnectivityStatusProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: const MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: RecentPatternsSection(),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sizing', () {
    test('the width is unchanged and the height is two thirds of 100', () {
      expect(kRecentPatternCardWidth, 120);
      expect(kRecentPatternCardMinHeight, 66);
      expect(kRecentPatternCardMinHeight / 100, closeTo(2 / 3, 0.01));
      expect(kRecentPatternCardMinHeight, greaterThanOrEqualTo(44),
          reason: 'the whole card stays a 44 dp tap target');
    });

    testWidgets('at the default text size every card is exactly 120 x 66, '
        'and the row is no taller', (tester) async {
      final report = await pumpAtTextScale(tester, _section(_mixed),
          profile: TextScaleProfile.defaultSize,
          allowEllipsis: [find.byKey(const ValueKey('recent-card-name'))]);
      expect(report.isClean, isTrue, reason: report.describe());
      expect(_cards, findsNWidgets(_mixed.length));
      for (final e in _cards.evaluate()) {
        expect((e.renderObject! as RenderBox).size, const Size(120, 66));
      }
      expect(tester.getSize(find.byType(IntrinsicHeight)).height, 66);
    });

    testWidgets('the whole card meets the tap-target guidelines',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAtTextScale(tester, _section(_mixed),
          profile: TextScaleProfile.defaultSize,
          allowEllipsis: [find.byKey(const ValueKey('recent-card-name'))]);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  });

  group('the effect line names what a tap plays (#167 catalog)', () {
    testWidgets('library, saved, static and voice entries', (tester) async {
      await pumpAtTextScale(tester, _section(_mixed),
          profile: TextScaleProfile.defaultSize,
          allowEllipsis: [find.byKey(const ValueKey('recent-card-name'))]);

      String effectOn(String cardText) => tester
          .widget<Text>(find.descendant(
              of: _cardOf(cardText),
              matching: find.byKey(const ValueKey('recent-card-effect'))))
          .data!;

      expect(effectOn('Royals Fade'), 'Fade');
      expect(effectOn('Harvest Running Dual'), 'Running Dual');
      expect(effectOn('Warm White'), 'Solid',
          reason: 'no fx id: the tap sends fx 0');
      expect(effectOn('Recent Pattern'), 'Chase',
          reason: 'a saved design carries its fx but no name');
      expect(effectOn('Porch Glow'), 'Pride 2015',
          reason: 'the catalog name for fx 63, not the stored effect_name');
      expect(find.text('Candle'), findsNothing);
    });

    testWidgets('a static effect reads as the controller names it',
        (tester) async {
      await pumpAtTextScale(
          tester,
          _section([
            _event('solid', name: 'Red Solid', fx: 0),
            _event('blocks', name: 'Red Green Blocks', fx: 83),
          ]),
          profile: TextScaleProfile.defaultSize);
      expect(find.text('Solid'), findsOneWidget);
      expect(find.text('Solid Pattern'), findsOneWidget);
      for (final name in ['Red Solid', 'Red Green Blocks']) {
        expect(
            find.descendant(
                of: _cardOf(name), matching: find.byIcon(Icons.circle)),
            findsOneWidget,
            reason: 'a still effect gets the still icon');
      }
      expect(find.byIcon(Icons.animation_rounded), findsNothing);
    });

    testWidgets('a moving effect gets the motion icon', (tester) async {
      await pumpAtTextScale(
          tester, _section([_event('lib-fade', name: 'Royals Fade', fx: 12)]),
          profile: TextScaleProfile.defaultSize);
      expect(find.byIcon(Icons.animation_rounded), findsOneWidget);
      expect(find.byIcon(Icons.circle), findsNothing);
    });

    testWidgets('the motion icon gives way before the effect name is cut',
        (tester) async {
      final report = await pumpAtTextScale(
          tester,
          _section([
            _event('short', name: 'Royals Fade', fx: 12),
            _event('long', name: 'Prism', fx: 14), // Theater Rainbow
          ]),
          profile: TextScaleProfile.defaultSize);
      expect(report.isClean, isTrue, reason: report.describe());
      expect(
          find.descendant(
              of: _cardOf('Royals Fade'),
              matching: find.byKey(const ValueKey('recent-card-motion-icon'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: _cardOf('Prism'),
              matching: find.byKey(const ValueKey('recent-card-motion-icon'))),
          findsNothing);
      expect(find.text('Theater Rainbow'), findsOneWidget);
    });
  });

  group('text scale', () {
    testWidgets('1.0x, 1.75x and 2.0x with Bold Text: no overflow, no '
        'clipping, no effect name cut; only a very long pattern name may '
        'ellipsize', (tester) async {
      final events = [
        ..._mixed,
        _event('long', name: 'Halloween Spooky Harvest Night Running Dual',
            fx: 52),
      ];
      final reports = await pumpAcrossTextScaleMatrix(tester, _section(events),
          allowEllipsis: [find.byKey(const ValueKey('recent-card-name'))]);
      expect(describeTextScaleMatrixFailures(reports), isNull);
    });

    for (final profile in TextScaleProfile.standardMatrix) {
      testWidgets('at ${profile.textScale}x the width never changes, the '
          'height only grows, and the effect is still shown', (tester) async {
        await pumpAtTextScale(tester, _section(_mixed),
            profile: profile,
            allowEllipsis: [find.byKey(const ValueKey('recent-card-name'))]);
        final heights = <double>{};
        for (final e in _cards.evaluate()) {
          final size = (e.renderObject! as RenderBox).size;
          expect(size.width, kRecentPatternCardWidth);
          expect(size.height, greaterThanOrEqualTo(kRecentPatternCardMinHeight));
          heights.add(size.height);
        }
        expect(heights, hasLength(1), reason: 'every card in the row matches');
        expect(find.text('Running Dual'), findsOneWidget);
        expect(find.text('Pride 2015'), findsOneWidget);
        final large = profile.textScale > 1.3;
        expect(find.text('3m ago'), large ? findsNothing : findsNWidgets(5),
            reason: 'the time badge is the first thing to give way');
      });
    }
  });

  group('accessibility', () {
    testWidgets('one button per card that reads the name, the effect and '
        'when', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAtTextScale(tester, _section(_mixed),
          profile: TextScaleProfile.defaultSize,
          allowEllipsis: [find.byKey(const ValueKey('recent-card-name'))]);
      expect(
          tester.getSemantics(
              find.bySemanticsLabel('Royals Fade, Fade effect, 3m ago')),
          isSemantics(
            label: 'Royals Fade, Fade effect, 3m ago',
            isButton: true,
            hasTapAction: true,
          ));
      expect(find.bySemanticsLabel('Warm White, Solid effect, 3m ago'),
          findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Running Dual effect')),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('a cut-short name can be read in full from the tooltip',
        (tester) async {
      const long = 'Halloween Spooky Harvest Night Running Dual';
      await pumpAtTextScale(tester, _section([_event('long', name: long, fx: 52)]),
          profile: TextScaleProfile.defaultSize,
          allowEllipsis: [find.byKey(const ValueKey('recent-card-name'))]);
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message,
          '$long · Running Dual');
    });
  });

  group('tapping applies exactly as before', () {
    testWidgets('anywhere on the card: one gated write of the recorded fx, '
        'speed, intensity and colours, power on, no brightness, and a '
        '"recent" use', (tester) async {
      final repo = RecordingWledRepository();
      final log = <Map<String, dynamic>>[];
      final c = _container(repo, log, extra: [
        recentUsageProvider.overrideWith((ref, limit) => Stream.value([
              _event('lib-dual', name: 'Harvest Running Dual', fx: 52, col: const [
                [255, 100, 0, 0],
                [128, 0, 128, 0],
              ]),
            ])),
      ]);
      await _pump(tester, c);

      // The card's top-left corner — the colourway, away from any label.
      await tester.tapAt(tester.getTopLeft(_cards) + const Offset(6, 6));
      await _settle(tester);

      final sent = repo.applied.single;
      expect(sent['on'], isTrue);
      expect(sent.containsKey('bri'), isFalse);
      final seg = firstRealDesignSegment(sent)!;
      expect(seg['fx'], 52);
      expect(seg['sx'], 60);
      expect(seg['ix'], 128);
      expect(seg['col'], [
        [255, 100, 0, 0],
        [128, 0, 128, 0],
      ]);
      expect(c.read(activePresetLabelProvider), isNotNull);
      expect(log.single, {'source': 'recent', 'name': 'Harvest Running Dual', 'fx': 52});
      expect(find.text('Applied: Harvest Running Dual'), findsOneWidget);
    });

    testWidgets('the screen-reader tap does the same', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = RecordingWledRepository();
      final log = <Map<String, dynamic>>[];
      final c = _container(repo, log, extra: [
        recentUsageProvider.overrideWith((ref, limit) =>
            Stream.value([_event('lib-fade', name: 'Royals Fade', fx: 12)])),
      ]);
      await _pump(tester, c);

      tester.semantics.tap(find.semantics.byLabel(RegExp('^Royals Fade, Fade effect')));
      await _settle(tester);

      expect(firstRealDesignSegment(repo.applied.single)!['fx'], 12);
      expect(log.single['source'], 'recent');
      handle.dispose();
    });
  });

  group('looking at Recent Patterns writes nothing', () {
    testWidgets('the real Firestore-backed stream: no controller write, no '
        'usage event, no favorite or usage document touched', (tester) async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/$_uid/favorites/mine0').set({
        'pattern_name': 'Mine 0',
        'added_at': Timestamp.fromDate(DateTime(2026, 9, 1)),
        'pattern_data': '{}',
        'usage_count': 0,
        'auto_added': false,
      });
      for (final (i, fx) in [12, 52, 0].indexed) {
        await db.collection('users/$_uid/pattern_usage').add({
          'created_at': Timestamp.fromDate(
              DateTime.now().subtract(Duration(minutes: 5 + i))),
          'source': 'explore',
          'pattern_name': 'Look $i',
          'effect_id': fx,
          'colors': ['blue'],
          'wled': '{"on":true,"seg":[{"fx":$fx,"col":[[0,0,255,0]]}]}',
        });
      }
      Future<Map<String, String>> snapshot() async => {
            for (final path in ['favorites', 'pattern_usage'])
              for (final d
                  in (await db.collection('users/$_uid/$path').get()).docs)
                '$path/${d.id}': d.data().toString(),
          };
      final before = await snapshot();

      final repo = RecordingWledRepository();
      final log = <Map<String, dynamic>>[];
      final c = _container(repo, log, extra: [
        authStateProvider.overrideWith((ref) => Stream<User?>.value(_StubUser())),
        userServiceProvider.overrideWithValue(UserService(firestore: db)),
      ]);
      await _pump(tester, c);
      await _settle(tester, 10);

      expect(find.text('Look 0'), findsOneWidget, reason: 'the section showed');
      expect(find.text('Fade'), findsOneWidget);
      expect(find.text('Running Dual'), findsOneWidget);
      expect(find.text('Solid'), findsOneWidget);

      // Scroll the row, as a customer looking through it would.
      await tester.drag(find.byType(SingleChildScrollView).first,
          const Offset(-200, 0));
      await _settle(tester);

      expect(repo.writeCount, 0);
      expect(log, isEmpty);
      expect(await snapshot(), before);
    });
  });
}
