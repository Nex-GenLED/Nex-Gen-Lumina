// +110 package G — roofline rows 70, 71, 72, 163 and 164 of the 2026-09-25
// UX defect audit, and the owner's feature-segmentation request (2026-09-29).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_feature_marking.dart';
import 'package:nexgen_command/features/design/roofline_feature_walkthrough.dart';
import 'package:nexgen_command/features/design/roofline_segmentation.dart';
import 'package:nexgen_command/features/design/roofline_setup_wizard.dart';
import 'package:nexgen_command/features/design/roofline_trace_merge.dart';
import 'package:nexgen_command/features/design/segment_setup_screen.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_logic.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/roofline_editor_screen.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_mask.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/widgets/house_photo_uploader.dart';

import '../../helpers/recording_wled_repository.dart';
import 'setup_auth_fixtures.dart';

const _front =
    ControllerInfo(id: 'ctrl-a', ip: '192.0.2.10', name: 'Front House');
const _back =
    ControllerInfo(id: 'ctrl-b', ip: '192.0.2.11', name: 'Back House');

class _ActiveInstaller extends InstallerModeNotifier {
  _ActiveInstaller(super.ref) {
    state = true;
  }
}

/// A repository that also takes per-pixel paints, recording them.
class _LitRepo extends RecordingWledRepository implements PerPixelWriter {
  final List<List<PixelSpan>> paints = [];
  final List<int> paintSegments = [];
  @override
  Future<bool> applyPerPixel({
    int segmentId = 0,
    required List<PixelSpan> spans,
    int chunkSize = kDefaultPixelChunkSize,
  }) async {
    paints.add(spans);
    paintSegments.add(segmentId);
    return true;
  }
}

/// Records profile writes, to prove what was (not) written.
class _RecordingUserService extends UserService {
  _RecordingUserService(FakeFirebaseFirestore fs) : super(firestore: fs);
  final List<UserModel> updates = [];
  @override
  Future<void> updateUser(UserModel user) async => updates.add(user);
}

/// A roofline service whose pixel-map save always fails.
class _FailingRooflineService extends RooflineConfigService {
  _FailingRooflineService(FakeFirebaseFirestore fs) : super(firestore: fs);
  @override
  Future<void> savePixelMap(
    String userId,
    String controllerId,
    RooflineConfiguration config, {
    Map<int, int> sourceCounts = const {},
    String createdBy = '',
    int mapVersion = 1,
    Map<int, bool> staleByChannel = const {},
  }) async {
    throw StateError('permission-denied');
  }
}

UserModel _profile() => UserModel(
      id: kTestUid,
      email: kTestEmail,
      displayName: 'Pat',
      ownerId: kTestUid,
      createdAt: DateTime.utc(2026, 9, 29),
      updatedAt: DateTime.utc(2026, 9, 29),
    );

List<Override> _overrides(
  FakeFirebaseFirestore fs, {
  List<ControllerInfo> controllers = const [_front],
  String? selectedIp,
  RooflineConfigService? service,
  UserService? userService,
  UserModel? profile,
  RecordingWledRepository? repo,
}) =>
    [
      effectiveUserUidProvider.overrideWith((ref) => kTestUid),
      controllersStreamProvider
          .overrideWith((ref) => Stream.value(controllers)),
      rooflineConfigServiceProvider
          .overrideWithValue(service ?? RooflineConfigService(firestore: fs)),
      deviceChannelsProvider.overrideWith((ref) => const []),
      selectedDeviceIpProvider.overrideWith((ref) => selectedIp),
      controllerRepositoryProvider.overrideWith((ref, target) => repo),
      houseImageUrlProvider.overrideWith((ref) => null),
      useStockImageProvider.overrideWith((ref) => true),
      rooflineMaskProvider.overrideWith((ref) => null),
      currentUserProfileProvider.overrideWith((ref) => Stream.value(profile)),
      if (userService != null)
        userServiceProvider.overrideWithValue(userService),
    ];

Widget _hosted(Widget screen, List<Override> overrides) {
  final router = GoRouter(initialLocation: '/', routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.push('/screen'),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    GoRoute(path: '/screen', builder: (_, __) => screen),
  ]);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<List<RooflineSegment>> _stored(FakeFirebaseFirestore fs,
    {String controllerId = 'ctrl-a'}) async {
  final channels = await RooflineConfigService(firestore: fs)
      .loadPixelMapChannels(kTestUid, controllerId);
  return [for (final c in channels) ...c.segments];
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  // ── Row 70 ───────────────────────────────────────────────────────────────
  group('row 70 — every roofline save names an explicit controller', () {
    ProviderContainer container(List<ControllerInfo> list,
        {String? selectedIp}) {
      final c = ProviderContainer(overrides: [
        controllersStreamProvider.overrideWith((ref) => Stream.value(list)),
        selectedDeviceIpProvider.overrideWith((ref) => selectedIp),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('two controllers, nothing chosen → no target (never first or newest)',
        () async {
      final c = container([_back, _front]);
      await c.read(controllersStreamProvider.future);
      final decision = c.read(rooflineEditTargetProvider);
      expect(decision.hasSelection, isFalse);
      expect(
          decision.reason, 'Choose which controller this roofline belongs to.');
    });

    test('the Home selection, or a pick on the roofline screen, decides',
        () async {
      final c = container([_front, _back], selectedIp: _back.ip);
      await c.read(controllersStreamProvider.future);
      expect(c.read(rooflineEditTargetProvider).value?.id, 'ctrl-b');
      c.read(rooflineTargetControllerIdProvider.notifier).state = 'ctrl-a';
      expect(c.read(rooflineEditTargetProvider).value?.id, 'ctrl-a');
    });

    test('a single controller is the target', () async {
      final c = container([_front]);
      await c.read(controllersStreamProvider.future);
      expect(c.read(rooflineEditTargetProvider).value?.id, 'ctrl-a');
    });

    testWidgets(
        'Segment Setup with two controllers says which to choose, refuses to '
        'save, then saves only to the one the customer picks', (tester) async {
      final fs = FakeFirebaseFirestore();
      await seedPixelMap(fs, twoChannelRoofline(controllerId: 'ctrl-a'));
      await seedPixelMap(fs, twoChannelRoofline(controllerId: 'ctrl-b'),
          controllerId: 'ctrl-b');
      await tester.pumpWidget(_hosted(const SegmentSetupScreen(),
          _overrides(fs, controllers: [_front, _back])));
      await _open(tester);
      await tester.pumpAndSettle();

      expect(find.text('Choose which controller this roofline belongs to.'),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('roofline-target-choose')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back House'));
      await tester.pumpAndSettle();
      expect(find.text('Saving to: Back House'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('delete-ch0_corner')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save Configuration'));
      await tester.pumpAndSettle();

      final back = await _stored(fs, controllerId: 'ctrl-b');
      final front = await _stored(fs, controllerId: 'ctrl-a');
      expect(back.map((s) => s.id), isNot(contains('ch0_corner')));
      expect(front.map((s) => s.id), contains('ch0_corner'),
          reason: 'the other controller must be untouched');
    });
  });

  // ── Row 71 ───────────────────────────────────────────────────────────────
  group('row 71 — Trace Roofline merges instead of replacing', () {
    testWidgets(
        '"Finish" keeps installer segments, their counts and anchors, and the '
        'traced segment keeps its count', (tester) async {
      final fs = FakeFirebaseFirestore();
      await seedPixelMap(fs, twoChannelRoofline());
      await tester
          .pumpWidget(_hosted(const RooflineEditorScreen(), _overrides(fs)));
      await _open(tester);
      await tester.pump(const Duration(seconds: 1));

      await tester.ensureVisible(find.byKey(const ValueKey('trace-finish')));
      await tester.tap(find.byKey(const ValueKey('trace-finish')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final stored = await _stored(fs);
      final byId = {for (final s in stored) s.id: s};
      expect(byId.keys,
          containsAll(['ch0_run', 'ch0_corner', 'ch0_peak', 'ch1_traced']));
      expect(byId['ch0_run']!.pixelCount, 40);
      expect(byId['ch0_run']!.anchorPixels, [0, 38]);
      expect(byId['ch0_peak']!.type, SegmentType.peak);
      expect(byId['ch0_peak']!.architecturalRole, ArchitecturalRole.peak);
      expect(byId['ch1_traced']!.pixelCount, 50,
          reason: 'a traced segment keeps its stored count, not an estimate');
    });

    test('the merge removes only what the customer deleted in the trace', () {
      final stored = twoChannelRoofline();
      final traced = <RooflineSegment>[
        const RooflineSegment(
          id: 'new_seg',
          name: 'Porch',
          pixelCount: 0,
          channelIndex: 1,
          points: [Offset(0.2, 0.7), Offset(0.4, 0.7)],
        ),
      ];
      final merged = mergeTraceIntoRoofline(
        stored: stored,
        traced: traced,
        shownInEditor: {'ch1_traced'},
      );
      final ids = merged.segments.map((s) => s.id).toList();
      expect(ids, isNot(contains('ch1_traced')),
          reason: 'deleted in the trace');
      expect(ids, containsAll(['ch0_run', 'ch0_corner', 'ch0_peak']),
          reason: 'never shown in the trace, so never deleted');
      final porch = merged.segments.firstWhere((s) => s.id == 'new_seg');
      expect(porch.pixelCount, kNewTracedSegmentFallbackCount);
    });

    test('a traced segment updates only its outline', () {
      final stored = twoChannelRoofline();
      final moved = [Offset(0.05, 0.3), Offset(0.95, 0.3)];
      final merged = mergeTraceIntoRoofline(
        stored: stored,
        traced: [
          stored.segments.last.copyWith(points: moved, pixelCount: 7),
        ],
        shownInEditor: {'ch1_traced'},
      );
      final seg = merged.segments.firstWhere((s) => s.id == 'ch1_traced');
      expect(seg.points, moved);
      expect(seg.pixelCount, 50);
    });
  });

  // ── Row 72 ───────────────────────────────────────────────────────────────
  group('row 72 — Segment Setup delete does not save everything else', () {
    testWidgets(
        'Delete marks the screen unsaved; nothing is written until Save',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      await seedPixelMap(fs, twoChannelRoofline());
      await tester
          .pumpWidget(_hosted(const SegmentSetupScreen(), _overrides(fs)));
      await _open(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('delete-ch0_corner')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect((await _stored(fs)).map((s) => s.id), contains('ch0_corner'),
          reason: 'the delete must not have been saved on its own');

      // Leaving now asks about the unsaved change.
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).last);
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Unsaved Changes'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
          (await _stored(fs)).map((s) => s.id), isNot(contains('ch0_corner')));
    });
  });

  // ── Row 163 ──────────────────────────────────────────────────────────────
  group('row 163 — roofline wizard total is the sum of the channels', () {
    FilledButton nextButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.ancestor(
            of: find.text('Next'), matching: find.byType(FilledButton)));

    testWidgets('no −/+ total; Next needs every channel count', (tester) async {
      final fs = FakeFirebaseFirestore();
      await tester.pumpWidget(_hosted(const RooflineSetupWizard(), [
        ..._overrides(fs),
        installerModeActiveProvider.overrideWith(_ActiveInstaller.new),
      ]));
      await _open(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('wizard-total-leds')), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsNothing);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('wizard-total-leds')))
              .data,
          '0');
      expect(nextButton(tester).onPressed, isNull);

      await tester.enterText(
          find.widgetWithText(TextFormField, '0').first, '120');
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('wizard-total-leds')))
              .data,
          '120');
      expect(nextButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Ch 2'));
      await tester.pumpAndSettle();
      expect(nextButton(tester).onPressed, isNull,
          reason: 'channel 2 has no count yet');
    });
  });

  // ── Row 164 ──────────────────────────────────────────────────────────────
  group('row 164 — the roofline chip reads the pixel map', () {
    Widget card(List<Override> overrides) => ProviderScope(
          overrides: overrides,
          child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(child: HousePhotoUploader())),
          ),
        );

    testWidgets('a mapped home says "Mapped" even with no photo outline',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      await tester.pumpWidget(card([
        ..._overrides(fs),
        currentRooflineConfigProvider
            .overrideWith((ref) => Stream.value(twoChannelRoofline())),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Roofline Mapped'), findsOneWidget);
      expect(find.textContaining('4 sections mapped'), findsOneWidget);
    });

    testWidgets('an outline with no map says "Not Set", and why',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      await tester.pumpWidget(card([
        ..._overrides(fs),
        currentRooflineConfigProvider.overrideWith((ref) => Stream.value(null)),
        rooflineMaskProvider.overrideWith((ref) => const RooflineMask(
              points: [Offset(0.1, 0.2), Offset(0.9, 0.2)],
              maskHeight: 0.25,
              isManuallyDrawn: true,
            )),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('Roofline Not Set'), findsOneWidget);
      expect(
          find.textContaining("isn't linked to your lights"), findsOneWidget);
    });

    testWidgets('Trace "Finish" writes the outline only after the map saves',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      await seedPixelMap(fs, twoChannelRoofline());
      final users = _RecordingUserService(fs);
      await tester.pumpWidget(_hosted(
        const RooflineEditorScreen(),
        _overrides(fs,
            service: _FailingRooflineService(fs),
            userService: users,
            profile: _profile()),
      ));
      await _open(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.byKey(const ValueKey('trace-finish')));
      await tester.tap(find.byKey(const ValueKey('trace-finish')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(users.updates, isEmpty,
          reason: 'the photo outline must not claim a map that did not save');
      expect(find.textContaining('your trace is still here'), findsOneWidget);
    });
  });

  // ── Feature segmentation ─────────────────────────────────────────────────
  group('feature segmentation — the gate package E asks', () {
    test(
        'default runs are not named features; roles, types and confirmation are',
        () {
      const plain = RooflineSegment(id: 'a', name: 'a', pixelCount: 10);
      expect(isNamedFeature(plain), isFalse);
      expect(isNamedFeature(plain.copyWith(featureConfirmed: true)), isTrue);
      expect(isNamedFeature(plain.copyWith(type: SegmentType.corner)), isTrue);
      expect(
          isNamedFeature(
              plain.copyWith(architecturalRole: ArchitecturalRole.peak)),
          isTrue);
      expect(
          featureKindOf(plain.copyWith(
              type: SegmentType.run,
              architecturalRole: ArchitecturalRole.corner)),
          RooflineFeatureKind.corner);
    });

    test('assessment: none, unmarked, partly and fully segmented', () {
      expect(assessRooflineSegmentation(null).hasMap, isFalse);
      final config = twoChannelRoofline();
      final partly = assessRooflineSegmentation(config);
      expect(partly.markedChannels, [0]);
      expect(partly.unmarkedChannels, [1]);
      expect(partly.isSegmented, isFalse);
      expect(partly.isPartlySegmented, isTrue);

      final all = assessRooflineSegmentation(config.copyWith(segments: [
        for (final s in config.segments)
          s.channelIndex == 1 ? s.copyWith(featureConfirmed: true) : s,
      ]));
      expect(all.isSegmented, isTrue);
      expect(all.corners, 1);
      expect(all.peaks, 1);
    });

    test('feature_confirmed survives Firestore JSON; absent reads as false',
        () {
      const s = RooflineSegment(
          id: 'a', name: 'a', pixelCount: 3, featureConfirmed: true);
      expect(s.toJson()['feature_confirmed'], isTrue);
      expect(RooflineSegment.fromJson(s.toJson()).featureConfirmed, isTrue);
      const plain = RooflineSegment(id: 'b', name: 'b', pixelCount: 3);
      expect(plain.toJson().containsKey('feature_confirmed'), isFalse);
      expect(
          RooflineSegment.fromJson(plain.toJson()).featureConfirmed, isFalse);
    });

    test('marking a traced run keeps its photo outline and confirms each part',
        () {
      const run = RooflineSegment(
        id: 'r',
        name: 'Back Eave',
        pixelCount: 50,
        channelIndex: 1,
        anchorPixels: [30],
        points: [Offset(0.0, 0.5), Offset(1.0, 0.5)],
      );
      final features = applyFeatureMarksToChannel(
        channelIndex: 1,
        pixelCount: 50,
        existing: const [run],
        marks: const [CaptureMark(pixel: 20, kind: MarkKind.corner)],
      );
      expect(features.map((f) => featureKindOf(f)), [
        RooflineFeatureKind.run,
        RooflineFeatureKind.corner,
        RooflineFeatureKind.run,
      ]);
      expect(features.every((f) => f.featureConfirmed), isTrue);
      expect(features.map((f) => f.pixelCount), [20, 1, 29]);
      // The outline over LEDs 0–20 is the first 40% of the traced line.
      expect(features.first.points.first.dx, closeTo(0.0, 1e-9));
      expect(features.first.points.last.dx, closeTo(0.4, 1e-9));
      // The anchor at LED 30 lands in the last run, at its local LED 9.
      expect(features.last.anchorPixels, [9]);
    });

    test('an already-marked channel reopens with its marks', () {
      final segs = compileMarksToChannelSegments(
        channelIndex: 0,
        pixelCount: 60,
        marks: const [
          CaptureMark(pixel: 10, kind: MarkKind.corner),
          CaptureMark(pixel: 30, kind: MarkKind.peak, slopeLength: 3),
          CaptureMark(pixel: 45, kind: MarkKind.runBoundary),
        ],
      );
      final again = compileMarksToChannelSegments(
        channelIndex: 0,
        pixelCount: 60,
        marks: marksFromChannelSegments(segs),
      );
      expect(again.map((s) => '${s.type.name}:${s.startPixel}+${s.pixelCount}'),
          segs.map((s) => '${s.type.name}:${s.startPixel}+${s.pixelCount}'));
    });

    testWidgets(
        'the Trace screen offers the walkthrough when corners and peaks are '
        'not marked', (tester) async {
      final fs = FakeFirebaseFirestore();
      await seedPixelMap(fs, twoChannelRoofline());
      await tester
          .pumpWidget(_hosted(const RooflineEditorScreen(), _overrides(fs)));
      await _open(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text("Your roofline's corners and peaks aren't marked yet."),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('roofline-mark-features')), findsOneWidget);
    });

    testWidgets(
        'walkthrough: walk the light, mark a corner, save — the channel is '
        'stored as confirmed features and the lights are put back',
        (tester) async {
      final fs = FakeFirebaseFirestore();
      await seedPixelMap(fs, twoChannelRoofline());
      final lit = _LitRepo();
      await tester.pumpWidget(_hosted(
        const RooflineFeatureWalkthroughScreen(),
        _overrides(fs, repo: lit),
      ));
      await _open(tester);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(const ValueKey('walkthrough-channel-1')));
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 2; i++) {
        await tester
            .ensureVisible(find.byKey(const ValueKey('walkthrough-step-10')));
        await tester.tap(find.byKey(const ValueKey('walkthrough-step-10')));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.text('Light 21 of 50'), findsOneWidget);
      expect(lit.paintSegments.last, 1);
      expect(lit.paints.last.any((s) => s.start == 20 && s.end == 20), isTrue,
          reason: 'the cursor LED is lit on the house');

      await tester
          .ensureVisible(find.byKey(const ValueKey('walkthrough-mark-corner')));
      await tester.tap(find.byKey(const ValueKey('walkthrough-mark-corner')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(
          find.byKey(const ValueKey('walkthrough-save-channel')));
      await tester.tap(find.byKey(const ValueKey('walkthrough-save-channel')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final ch1 =
          (await _stored(fs)).where((s) => s.channelIndex == 1).toList();
      expect(ch1.map((s) => s.type),
          [SegmentType.run, SegmentType.corner, SegmentType.run]);
      expect(ch1.every((s) => s.featureConfirmed), isTrue);
      expect(ch1.first.points, isNotEmpty,
          reason: 'photo outline carried over');
      final all = await RooflineConfigService(firestore: fs)
          .loadPixelMapChannels(kTestUid, 'ctrl-a');
      expect(assessPixelMapChannels(all).isSegmented, isTrue);

      // Leaving restores the channel's previous look (clears the paint).
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(lit.applied.last['seg'][0]['i'], isEmpty);
    });
  });
}
