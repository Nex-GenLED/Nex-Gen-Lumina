// The Edit Pattern screen's app-bar action.
//
// It was "SAVE TO DEVICE": a WLED psave into a preset slot nothing in the app
// could read back. It is now "SAVE": a design written through DesignService
// into My Designs. These tests drive the real screen and assert what reaches
// the service — and that the device is never asked to store anything.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/edit_pattern_screen.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

class _RecordingDesignService implements DesignService {
  _RecordingDesignService({this.error, this.existing = const []});
  final Object? error;

  /// What is already in the account's My Designs.
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
    if (error != null) throw error!;
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

EditablePattern _chiefs({int fx = 0}) => EditablePattern.fromGradientColors(
      id: 'team_nfl_chiefs',
      name: 'Kansas City Chiefs',
      colors: const [Color(0xFFE31837), Color(0xFFFFB81C)],
      effectId: fx,
    ).copyWith(actionColors: const [
      Color(0xFFE31837),
      Color(0xFFFFB81C),
      Color(0xFFFFFFFF),
    ]);

Future<void> _pump(
  WidgetTester tester,
  DesignService service, {
  EditablePattern? pattern,
  String? uid = 'u1',
  List<DeviceChannel> channels = _channels,
}) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => EditPatternScreen(initialPattern: pattern ?? _chiefs()),
    ),
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
      effectiveUserUidProvider.overrideWithValue(uid),
      deviceChannelsProvider.overrideWithValue(channels),
      effectiveChannelIdsProvider
          .overrideWithValue([for (final c in channels) c.id]),
      // No controller: Save must not need one for anything but LED counts.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the action is labelled SAVE — "SAVE TO DEVICE" is gone',
      (tester) async {
    await _pump(tester, _RecordingDesignService());
    expect(find.text('SAVE'), findsOneWidget);
    expect(find.text('SAVE TO DEVICE'), findsNothing);
    expect(find.byTooltip('Save to My Designs'), findsOneWidget);
  });

  testWidgets('Static: saves a per-pixel design named after the source card, '
      'and says where it went', (tester) async {
    final service = _RecordingDesignService();
    await _pump(tester, service);

    await tester.tap(find.text('SAVE'));
    await tester.pump();
    await tester.pump();

    final d = service.saved.single;
    expect(d.id, isEmpty, reason: 'a NEW design → createDesign → unique auto-id');
    expect(d.name, 'Kansas City Chiefs');
    expect(d.ownerId, 'u1');
    expect(d.perPixel, isTrue);
    expect(d.channels.map((c) => c.ledCount), [128, 162]);
    expect(d.tags, contains(kPatternEditorDesignTag));
    expect(find.text('Saved "Kansas City Chiefs" to My Designs'), findsOneWidget);
    expect(find.textContaining('Saved to device'), findsNothing);
  });

  testWidgets('Animated: saves an effect design with the editor\'s effect',
      (tester) async {
    final service = _RecordingDesignService();
    await _pump(tester, service, pattern: _chiefs(fx: 12));

    await tester.tap(find.text('SAVE'));
    await tester.pump();
    await tester.pump();

    final d = service.saved.single;
    expect(d.perPixel, isFalse);
    expect(d.isPositional, isFalse);
    expect(d.channels.every((c) => c.effectId == 12), isTrue);
  });

  testWidgets('the typed name is what gets saved', (tester) async {
    final service = _RecordingDesignService();
    await _pump(tester, service);

    await tester.enterText(find.byType(TextField).first, 'Chiefs + White');
    await tester.tap(find.text('SAVE'));
    await tester.pump();
    await tester.pump();

    expect(service.saved.single.name, 'Chiefs + White');
  });

  testWidgets('a name already in My Designs is made distinguishable, not '
      'duplicated', (tester) async {
    final now = DateTime(2026, 9, 21);
    final service = _RecordingDesignService(existing: [
      CustomDesign(
          id: 'x',
          name: 'Kansas City Chiefs',
          createdAt: now,
          updatedAt: now,
          ownerId: 'u1',
          channels: const []),
    ]);
    await _pump(tester, service);

    await tester.tap(find.text('SAVE'));
    await tester.pump();
    await tester.pump();

    expect(service.listedFor, ['u1'],
        reason: 'names are checked against the account being saved INTO');
    expect(service.saved.single.name, 'Kansas City Chiefs 2');
    expect(find.text('Saved "Kansas City Chiefs 2" to My Designs'), findsOneWidget);
  });

  testWidgets('Save twice under one name UPDATES that design; a new name '
      'creates a SECOND one — a variation never overwrites the first',
      (tester) async {
    final service = _RecordingDesignService();
    await _pump(tester, service);

    await tester.tap(find.text('SAVE'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('SAVE'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // old toast out, new one in
    await tester.pump(const Duration(seconds: 1));

    expect(service.saved, hasLength(2));
    expect(service.saved[0].id, isEmpty);
    expect(service.saved[1].id, 'auto-1', reason: 'same name → update in place');
    expect(find.text('Updated "Kansas City Chiefs" in My Designs'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Chiefs Alt');
    await tester.tap(find.text('SAVE'));
    await tester.pump();
    await tester.pump();

    expect(service.saved, hasLength(3));
    expect(service.saved[2].id, isEmpty, reason: 'new name → a new document');
    expect(service.saved[2].name, 'Chiefs Alt');
  });

  testWidgets('VIEW opens My Designs', (tester) async {
    await _pump(tester, _RecordingDesignService());
    await tester.tap(find.text('SAVE'));
    await tester.pump();
    await tester.pump();

    await tester.pump(const Duration(seconds: 1)); // toast slides in from below
    await tester.tap(find.text('VIEW'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('LIBRARY:my_designs'), findsOneWidget);
  });

  testWidgets('a denied write LOOKS failed', (tester) async {
    final service = _RecordingDesignService(
        error: FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    await _pump(tester, service);

    await tester.tap(find.text('SAVE'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('to My Designs'), findsNothing);
    expect(find.textContaining("don't have permission"), findsOneWidget);
  });

  testWidgets('signed out: says so, writes nothing', (tester) async {
    final service = _RecordingDesignService();
    await _pump(tester, service, uid: null);

    await tester.tap(find.text('SAVE'));
    await tester.pump();

    expect(service.saved, isEmpty);
    expect(find.text('Sign in to save designs. Nothing was saved.'), findsOneWidget);
  });

  testWidgets('Static with no channel lengths: refuses with a reason instead '
      'of saving a guess', (tester) async {
    final service = _RecordingDesignService();
    await _pump(tester, service, channels: const []);

    await tester.tap(find.text('SAVE'));
    await tester.pump();

    expect(service.saved, isEmpty);
    expect(find.textContaining('Connect to your lights'), findsOneWidget);
  });

  testWidgets('animated MODE with more than 3 layers says only 3 are used; '
      'Static does not', (tester) async {
    final five = const [
      Color(0xFFE31837),
      Color(0xFFFFB81C),
      Color(0xFFFFFFFF),
      Color(0xFF00FF00),
      Color(0xFF0000FF),
    ];
    await _pump(tester, _RecordingDesignService(),
        pattern: _chiefs(fx: 12).copyWith(actionColors: five));
    expect(find.byKey(const ValueKey('edit-pattern-effect-slot-hint')),
        findsOneWidget);

    await _pump(tester, _RecordingDesignService(),
        pattern: _chiefs(fx: 0).copyWith(actionColors: five));
    expect(find.byKey(const ValueKey('edit-pattern-effect-slot-hint')),
        findsNothing);
  });
}
