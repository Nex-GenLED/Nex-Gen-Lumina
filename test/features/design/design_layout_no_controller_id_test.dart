// Roofline slice 1 follow-up — the layout stamp and the fit gate when there
// is NO selected controller id. In simulation and during setup the buses are
// known (the LAN cfg read works) but the account has no controller record
// for the device, so `selectedControllerIdProvider` is null.
//
// Proved here, end to end, on the slice-1 code as built:
//   * a design saved with no controller id is still stamped with its bus
//     lengths — the AI studio's save provider here; the paint editor's case
//     is manual_editor_layout_stamp_test.dart ("no selected controller
//     record → stamped with the lengths only");
//   * the fit gate compares the lengths and SKIPS the controller comparison
//     when either side has no id — it never refuses for a missing id alone —
//     at the pure verdict and through the apply spine;
//   * the AI studio saves UNSTAMPED when there is no live layout at all, as
//     design_studio_save_composed_test.dart requires (refusing a layout-less
//     positional save is slice 3's job, not this one's).
//
// Fixture: three buses of 100 LEDs (ids 0, 1, 2); the mismatch cases are
// bus 2 at 120 and a two-bus controller.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_layout_fit.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/design/design_studio_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/models/composed_pattern.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kThreeBuses = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 300, gpioPin: 12),
];
const kTwoBuses = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
];
const kMiddleBusLonger = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 220, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 220, stop: 320, gpioPin: 12),
];

/// Stamped for three buses of 100 on ctl-a, or with no id at all.
const kStampWithId = DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]);
const kStampNoId = DesignLayoutStamp(busLengths: [100, 100, 100]);

final _now = DateTime(2026, 11, 5);

CustomDesign _painted(DesignLayoutStamp? stamp) => CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'customer-uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      layoutStamp: stamp,
      channels: [
        for (var id = 0; id < 3; id++)
          ChannelDesign(channelId: id, channelName: 'Channel ${id + 1}', ledCount: 100,
              colorGroups: const [
                LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
                LedColorGroup(startLed: 50, endLed: 99, color: [0, 0, 255, 0]),
              ]),
      ],
    );

// ── the apply-spine harness (as design_layout_fit_apply_test.dart) ──────────

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

class _Repo implements WledRepository, PerPixelWriter {
  final json = <Map<String, dynamic>>[];
  final pixels = <int, List<PixelSpan>>{};
  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    json.add(payload);
    return true;
  }

  @override
  Future<bool> applyPerPixel(
      {int segmentId = 0,
      required List<PixelSpan> spans,
      int chunkSize = kDefaultPixelChunkSize}) async {
    pixels[segmentId] = spans;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(WidgetRef, _Repo)> _pump(
  WidgetTester tester, {
  required List<DeviceChannel> live,
  required String? controllerId,
}) async {
  SharedPreferences.setMockInitialValues({});
  final repo = _Repo();
  late WidgetRef ref;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      deviceChannelsProvider.overrideWithValue(live),
      effectiveChannelIdsProvider.overrideWithValue([for (final c in live) c.id]),
      selectedControllerIdProvider.overrideWithValue(controllerId),
      isRemoteModeProvider.overrideWithValue(false),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    ],
    child: Consumer(builder: (c, r, _) {
      ref = r;
      return const SizedBox();
    }),
  ));
  return (ref, repo);
}

// ── the studio harness (as design_studio_save_composed_test.dart) ───────────

// User is sealed; subclassing for a scoped test fake is intentional.
// ignore: subtype_of_sealed_class
class _StubUser implements User {
  _StubUser(this._uid);
  final String _uid;
  @override
  String get uid => _uid;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

class _FixedZoneSegmentsNotifier extends ZoneSegmentsNotifier {
  @override
  Future<List<WledSegment>> build() async => const [
        WledSegment(id: 0, name: 'Channel 1', start: 0, stop: 100),
        WledSegment(id: 1, name: 'Channel 2', start: 100, stop: 200),
        WledSegment(id: 2, name: 'Channel 3', start: 200, stop: 300),
      ];
}

ComposedPattern _composed() => ComposedPattern(
      name: 'Studio stripes',
      description: 'red then blue',
      sourceIntent: DesignIntent(
        originalPrompt: 'red then blue',
        layers: [
          DesignLayer(
            id: 'layer-1',
            name: 'base',
            targetZone: const ZoneSelector.all(),
            colors: const ColorAssignment.solid(Color(0xFFFF0000)),
          ),
        ],
        parsedAt: _now,
      ),
      colorGroups: const [
        LedColorGroup(startLed: 0, endLed: 149, color: [255, 0, 0, 0]),
        LedColorGroup(startLed: 150, endLed: 299, color: [0, 0, 255, 0]),
      ],
      effectId: 0,
      speed: 128,
      intensity: 128,
      brightness: 200,
      hasMotion: false,
      wledPayload: const {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'id': 0,
            'start': 0,
            'stop': 300,
            'col': [
              [255, 0, 0],
              [0, 0, 255],
            ],
            'fx': 0,
          }
        ],
      },
      totalPixels: 300,
      composedAt: _now,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the stamp with no controller id', () {
    test('fromChannels: the lengths are stamped, the id is absent, and the '
        'document carries bus_lengths only', () {
      final s = DesignLayoutStamp.fromChannels(kThreeBuses, controllerId: null)!;
      expect(s.controllerId, isNull);
      expect(s.busLengths, [100, 100, 100]);
      final doc = _painted(s).toFirestore();
      expect(doc[kDesignBusLengthsField], [100, 100, 100]);
      expect(doc.containsKey(kDesignControllerIdField), isFalse, reason: 'nothing invented');
      expect(CustomDesign.fromFirestoreData('d1', doc).layoutStamp, s);
    });

    test('liveDesignLayoutStamp: buses known, no selected controller → stamped on '
        'the lengths', () {
      final container = ProviderContainer(overrides: [
        deviceChannelsProvider.overrideWithValue(kThreeBuses),
        selectedControllerIdProvider.overrideWithValue(null),
      ]);
      addTearDown(container.dispose);
      final s = liveDesignLayoutStamp(container.read);
      expect(s, isNotNull, reason: 'a missing id must not block the stamp');
      expect(s!.controllerId, isNull);
      expect(s.busLengths, [100, 100, 100]);
    });

    test('liveDesignLayoutStamp: no buses → no stamp, and the controller '
        'selection is not consulted', () {
      final container = ProviderContainer(overrides: [
        deviceChannelsProvider.overrideWithValue(const []),
        selectedControllerIdProvider.overrideWith(
            (ref) => throw StateError('the controller list must not be read')),
      ]);
      addTearDown(container.dispose);
      expect(liveDesignLayoutStamp(container.read), isNull);
    });
  });

  group('the AI studio save', () {
    late FakeFirebaseFirestore firestore;

    setUp(() => firestore = FakeFirebaseFirestore());

    List<Override> studio({List<DeviceChannel>? liveBuses}) => [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(_StubUser('u1'))),
          designServiceProvider.overrideWith((ref) => DesignService(firestore: firestore)),
          zoneSegmentsProvider.overrideWith(_FixedZoneSegmentsNotifier.new),
          composedPatternProvider.overrideWith((ref) => _composed()),
          // No controller: the studio composes and saves without one.
          wledRepositoryProvider.overrideWith((ref) => null),
          if (liveBuses != null) deviceChannelsProvider.overrideWithValue(liveBuses),
          if (liveBuses != null) selectedControllerIdProvider.overrideWithValue(null),
        ];

    Future<Map<String, dynamic>> savedDoc(ProviderContainer c) async {
      await c.read(authStateProvider.future);
      await c.read(zoneSegmentsProvider.future);
      final id = await c.read(saveComposedDesignProvider)();
      expect(id, isNotNull);
      final snap = await firestore.collection('users').doc('u1').collection('designs').get();
      return snap.docs.single.data();
    }

    test('no live layout at all → saved UNSTAMPED, as the existing studio tests '
        'require (a layout-less positional save is refused in slice 3, not here)',
        () async {
      final c = ProviderContainer(overrides: studio());
      addTearDown(c.dispose);
      final data = await savedDoc(c);
      expect(data.containsKey(kDesignBusLengthsField), isFalse);
      expect(data.containsKey(kDesignControllerIdField), isFalse);
      final back = CustomDesign.fromFirestoreData('x', data);
      expect(back.isPositional, isTrue);
      expect(back.layoutStamp, isNull, reason: 'applies as before: not gated');
    });

    test('live buses, no selected controller → stamped with the lengths only',
        () async {
      final c = ProviderContainer(overrides: studio(liveBuses: kThreeBuses));
      addTearDown(c.dispose);
      final data = await savedDoc(c);
      expect(data[kDesignBusLengthsField], [100, 100, 100]);
      expect(data.containsKey(kDesignControllerIdField), isFalse);
      expect(CustomDesign.fromFirestoreData('x', data).layoutStamp, kStampNoId);
    });
  });

  group('the fit verdict skips the controller comparison when either side has '
      'no id, and the lengths still decide', () {
    LayoutFit fit(DesignLayoutStamp stamp, List<DeviceChannel> live, String? liveId) =>
        layoutFitOf(
          designName: 'Porch stripes',
          stamp: stamp,
          liveChannels: live,
          liveControllerId: liveId,
          remote: () => false,
        );

    test('stamp without an id, live selection ctl-b', () {
      expect(fit(kStampNoId, kThreeBuses, 'ctl-b').verdict, LayoutFitVerdict.fits);
      expect(fit(kStampNoId, kMiddleBusLonger, 'ctl-b').verdict, LayoutFitVerdict.busLengthDiffers);
      expect(fit(kStampNoId, kTwoBuses, 'ctl-b').verdict, LayoutFitVerdict.busCountDiffers);
    });

    test('stamp for ctl-a, no live selection', () {
      expect(fit(kStampWithId, kThreeBuses, null).verdict, LayoutFitVerdict.fits);
      expect(fit(kStampWithId, kMiddleBusLonger, null).verdict, LayoutFitVerdict.busLengthDiffers);
      expect(fit(kStampWithId, kTwoBuses, null).verdict, LayoutFitVerdict.busCountDiffers);
    });

    test('neither side has an id', () {
      expect(fit(kStampNoId, kThreeBuses, null).verdict, LayoutFitVerdict.fits);
      expect(fit(kStampNoId, kMiddleBusLonger, null).verdict, LayoutFitVerdict.busLengthDiffers);
    });

    test('differentController only when BOTH sides know an id and they differ', () {
      expect(fit(kStampWithId, kThreeBuses, 'ctl-b').verdict, LayoutFitVerdict.differentController);
      expect(fit(kStampWithId, kThreeBuses, 'ctl-a').verdict, LayoutFitVerdict.fits);
      for (final f in [
        fit(kStampNoId, kThreeBuses, 'ctl-b'),
        fit(kStampWithId, kThreeBuses, null),
        fit(kStampNoId, kThreeBuses, null),
        fit(kStampNoId, kThreeBuses, ''),
      ]) {
        expect(f.verdict, isNot(LayoutFitVerdict.differentController), reason: f.toString());
        expect(f.applies, isTrue, reason: f.toString());
      }
    });
  });

  group('the apply spine', () {
    testWidgets('stamp without an id, selection ctl-b, matching lengths → applied',
        (tester) async {
      final (ref, repo) = await _pump(tester, live: kThreeBuses, controllerId: 'ctl-b');
      final report = await applyPositionalDesignDetailed(ref.read, _painted(kStampNoId));
      expect(report.ok, isTrue, reason: report.message);
      expect(repo.json, hasLength(1));
      expect(repo.pixels.keys.toSet(), {0, 1, 2});
    });

    testWidgets('stamp for ctl-a, no selection, matching lengths → applied',
        (tester) async {
      final (ref, repo) = await _pump(tester, live: kThreeBuses, controllerId: null);
      final report = await applyPositionalDesignDetailed(ref.read, _painted(kStampWithId));
      expect(report.ok, isTrue, reason: report.message);
      expect(repo.json, hasLength(1));
    });

    testWidgets('stamp without an id, no selection, bus 2 at 120 → refused on the '
        'length, naming channel 2; nothing written', (tester) async {
      final (ref, repo) = await _pump(tester, live: kMiddleBusLonger, controllerId: null);
      final report = await applyPositionalDesignDetailed(ref.read, _painted(kStampNoId));
      expect(report.ok, isFalse);
      expect(report.message, contains('100 lights on channel 2'));
      expect(report.message, contains('has 120 now'));
      expect(repo.json, isEmpty);
      expect(repo.pixels, isEmpty);
    });

    testWidgets('stamp without an id, selection ctl-b, two live buses → refused on '
        'the count, not the controller', (tester) async {
      final (ref, repo) = await _pump(tester, live: kTwoBuses, controllerId: 'ctl-b');
      final report = await applyPositionalDesignDetailed(ref.read, _painted(kStampNoId));
      expect(report.ok, isFalse);
      expect(report.message, contains('has 2 now'));
      expect(report.message, isNot(contains('different controller')));
      expect(repo.json, isEmpty);
    });
  });
}
