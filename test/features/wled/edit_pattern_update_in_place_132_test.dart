// Build 132, fix 4 — the Pattern Editor's SAVE, when it was opened from a
// saved design.
//
// It used to save a copy named "Name 2": the editor never knew the design it
// came from, so the design's own name counted as taken. The rule now:
//   * opened from a saved design and the name is unchanged → SAVE updates
//     THAT design in place;
//   * the name was changed → SAVE creates a new design with that name, made
//     distinct only if it collides with one already in My Designs;
//   * opened from Explore → exactly as before.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart'
    show PatternEditorChannel;
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/edit_pattern_screen.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/pattern_editor_design.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

class _RecordingDesignService implements DesignService {
  _RecordingDesignService({this.existing = const []});

  final List<CustomDesign> existing;
  final saved = <CustomDesign>[];
  final listedFor = <String>[];
  int _next = 0;

  @override
  Future<List<CustomDesign>> getDesigns(String userId) async {
    listedFor.add(userId);
    return existing;
  }

  @override
  Future<String> saveDesign(String userId, CustomDesign design) async {
    saved.add(design);
    return design.id.isEmpty ? 'auto-${++_next}' : design.id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 0),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];

/// The saved design the card page was showing.
CustomDesign _source() => CustomDesign(
      id: 'd1',
      name: 'Blue Chase',
      description: 'Captured on Home',
      createdAt: DateTime(2026, 9, 29),
      updatedAt: DateTime(2026, 9, 29),
      ownerId: 'u1',
      channels: const [
        ChannelDesign(
          channelId: 0,
          channelName: 'Front',
          colorGroups: [
            LedColorGroup(startLed: 0, endLed: 127, color: [0, 0, 255, 0]),
          ],
          effectId: 28,
          speed: 44,
          intensity: 90,
          ledCount: 128,
        ),
      ],
      brightness: 150,
      brightnessStated: true,
      tags: const ['team'],
    );

CustomDesign _other(String name) => CustomDesign(
      id: 'x-$name',
      name: name,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
      ownerId: 'u1',
      channels: const [],
    );

/// What the card page hands the editor for [_source] (colorway_effect_selector
/// builds it from the card's own state).
EditablePattern _pattern() => EditablePattern.fromGradientColors(
      id: 'edit_1',
      name: 'Blue Chase',
      colors: const [Color(0xFF0000FF)],
      effectId: 28,
      speed: 44,
      intensity: 90,
      brightness: 150,
    );

Future<void> _pump(
  WidgetTester tester,
  DesignService service,
  Object? extra,
) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => editPatternScreenForExtra(extra)),
    GoRoute(
      path: '/explore/library/:id',
      builder: (_, s) => Scaffold(body: Text('LIBRARY:${s.pathParameters['id']}')),
    ),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      designServiceProvider.overrideWithValue(service),
      designsStreamProvider
          .overrideWith((ref) => Stream.value(const <CustomDesign>[])),
      effectiveUserUidProvider.overrideWithValue('u1'),
      deviceChannelsProvider.overrideWithValue(_channels),
      effectiveChannelIdsProvider
          .overrideWithValue([for (final c in _channels) c.id]),
      wledRepositoryProvider.overrideWith((ref) => null),
      demoModeProvider.overrideWith((ref) => true),
      authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
      favoritedPatternIdsProvider
          .overrideWith((ref) => Stream.value(const <String>{})),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('SAVE'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('opened from a saved design', () {
    testWidgets('name unchanged: SAVE updates THAT design in place — no '
        '"Blue Chase 2"', (tester) async {
      final service = _RecordingDesignService(existing: [_source()]);
      var updated = 0;
      await _pump(
        tester,
        service,
        PatternEditorLaunch(
          pattern: _pattern(),
          sourceDesign: _source(),
          onSourceUpdated: () => updated++,
        ),
      );
      await _save(tester);

      final d = service.saved.single;
      expect(d.id, 'd1', reason: 'the original id routes saveDesign to update');
      expect(d.name, 'Blue Chase');
      expect(service.listedFor, isEmpty,
          reason: 'an update needs no free name');
      expect(find.text('Updated "Blue Chase" in My Designs'), findsOneWidget);
      expect(updated, 1);

      // Kept from the stored design: what the editor does not own.
      expect(d.createdAt, DateTime(2026, 9, 29));
      expect(d.description, 'Captured on Home');
      expect(d.ownerId, 'u1');
      expect(d.tags, containsAll(<String>['team', kPatternEditorDesignTag]));

      // Written: exactly the look a new Pattern Editor save stores.
      final fresh = designFromPatternEditor(
        pattern: _pattern(),
        name: 'Blue Chase',
        ownerId: 'u1',
        channels: [
          for (final c in _channels)
            PatternEditorChannel(
                id: c.id, name: c.name, ledCount: c.stop - c.start),
        ],
      );
      expect(d.toWledPayload(), fresh.toWledPayload());
      expect([for (final c in d.channels) c.toJson()],
          [for (final c in fresh.channels) c.toJson()]);
      expect(d.brightness, fresh.brightness);
      expect(d.brightnessStated, isTrue);
      expect(d.perPixel, fresh.perPixel);
    });

    testWidgets('name changed: SAVE creates a NEW design with that name',
        (tester) async {
      final service = _RecordingDesignService(existing: [_source()]);
      var updated = 0;
      await _pump(
        tester,
        service,
        PatternEditorLaunch(
          pattern: _pattern(),
          sourceDesign: _source(),
          onSourceUpdated: () => updated++,
        ),
      );
      await tester.enterText(find.byType(TextField).first, 'Ocean');
      await _save(tester);

      final d = service.saved.single;
      expect(d.id, isEmpty, reason: 'a new design → createDesign');
      expect(d.name, 'Ocean', reason: 'no collision → the name as typed');
      expect(find.text('Saved "Ocean" to My Designs'), findsOneWidget);
      expect(updated, 0, reason: 'the design it came from is untouched');
    });

    testWidgets('a changed name that collides is made distinct',
        (tester) async {
      final service =
          _RecordingDesignService(existing: [_source(), _other('Ocean')]);
      await _pump(tester, service,
          PatternEditorLaunch(pattern: _pattern(), sourceDesign: _source()));
      await tester.enterText(find.byType(TextField).first, 'Ocean');
      await _save(tester);

      expect(service.saved.single.id, isEmpty);
      expect(service.saved.single.name, 'Ocean 2');
    });

    testWidgets('changed, saved, then changed back: the second SAVE updates '
        'the original design', (tester) async {
      final service = _RecordingDesignService(existing: [_source()]);
      await _pump(tester, service,
          PatternEditorLaunch(pattern: _pattern(), sourceDesign: _source()));
      await tester.enterText(find.byType(TextField).first, 'Ocean');
      await _save(tester);
      await tester.enterText(find.byType(TextField).first, 'Blue Chase');
      await _save(tester);

      expect(service.saved, hasLength(2));
      expect(service.saved[0].id, isEmpty);
      expect(service.saved[0].name, 'Ocean');
      expect(service.saved[1].id, 'd1');
      expect(service.saved[1].name, 'Blue Chase');
    });

    testWidgets('SAVE twice unchanged keeps updating the same design',
        (tester) async {
      final service = _RecordingDesignService(existing: [_source()]);
      await _pump(tester, service,
          PatternEditorLaunch(pattern: _pattern(), sourceDesign: _source()));
      await _save(tester);
      await _save(tester);

      expect([for (final d in service.saved) d.id], ['d1', 'd1']);
    });
  });

  group('opened from Explore — unchanged', () {
    testWidgets('a name already in My Designs is still made distinct',
        (tester) async {
      final service = _RecordingDesignService(existing: [_source()]);
      await _pump(tester, service, _pattern());
      await _save(tester);

      expect(service.listedFor, ['u1']);
      expect(service.saved.single.id, isEmpty);
      expect(service.saved.single.name, 'Blue Chase 2');
    });
  });

  group('the route', () {
    test('builds the editor for each kind of extra', () {
      final none = editPatternScreenForExtra(null) as EditPatternScreen;
      expect(none.initialPattern, isNull);
      expect(none.sourceDesign, isNull);

      final explore = editPatternScreenForExtra(_pattern()) as EditPatternScreen;
      expect(explore.initialPattern?.name, 'Blue Chase');
      expect(explore.sourceDesign, isNull);

      final fromDesign = editPatternScreenForExtra(PatternEditorLaunch(
          pattern: _pattern(), sourceDesign: _source())) as EditPatternScreen;
      expect(fromDesign.initialPattern?.name, 'Blue Chase');
      expect(fromDesign.sourceDesign?.id, 'd1');
    });
  });
}
