// Roofline slice 3 — a VARIATION keeps the saved design's layout stamp
// (owner decision 3): the AI studio's save writes the base design's
// `controller_id` / `bus_lengths`, not the live buses', and the in-memory
// apply design carries the same stamp so the slice 1 fit gate judges it
// against the lights it was composed for.
//
// New behaviour. Harness as design_layout_no_controller_id_test.dart (the
// studio save over a fake Firestore). The live device here is a DIFFERENT
// layout — two buses on ctl-b — to prove which stamp wins.

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
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

final _now = DateTime(2026, 11, 5);

/// The saved design's layout: three buses of 100 on ctl-a.
const kSavedStamp = DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]);

/// The live device: two buses of 100 on ctl-b.
const kLiveTwoBuses = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
];

CustomDesign _saved() => CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'u1',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      layoutStamp: kSavedStamp,
      channels: [
        for (var id = 0; id < 3; id++)
          ChannelDesign(channelId: id, channelName: 'Channel ${id + 1}', ledCount: 100,
              colorGroups: const [
                LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
                LedColorGroup(startLed: 50, endLed: 99, color: [0, 0, 255, 0]),
              ]),
      ],
    );

/// What the composer produced for the variation: channel-local, over the
/// saved design's three buses.
ComposedPattern _composed() => ComposedPattern(
      name: 'Red',
      description: 'red on everywhere (every other)',
      sourceIntent: DesignIntent(
        originalPrompt: 'every other light',
        layers: [
          DesignLayer(
            id: 'layer_0',
            name: 'red on everywhere',
            targetZone: const ZoneSelector.all(),
            colors: const ColorAssignment(
                primaryColor: Color(0xFFFF0000),
                secondaryColor: Color(0xFF0000FF),
                spacingRule: SpacingRule.everyOther()),
          ),
        ],
        parsedAt: _now,
      ),
      colorGroups: const [
        LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0, 0]),
      ],
      channelGroups: const {
        0: [LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0, 0])],
        1: [LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0, 0])],
        2: [LedColorGroup(startLed: 0, endLed: 0, color: [255, 0, 0, 0])],
      },
      channelLengths: const {0: 100, 1: 100, 2: 100},
      wledPayload: const {'on': true},
      totalPixels: 300,
      composedAt: _now,
    );

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

class _LiveZoneSegments extends ZoneSegmentsNotifier {
  @override
  Future<List<WledSegment>> build() async => const [
        WledSegment(id: 0, name: 'Channel 1', start: 0, stop: 100),
        WledSegment(id: 1, name: 'Channel 2', start: 100, stop: 200),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;
  setUp(() => firestore = FakeFirebaseFirestore());

  ProviderContainer studio({required bool variation}) {
    final c = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream<User?>.value(_StubUser('u1'))),
      designServiceProvider.overrideWith((ref) => DesignService(firestore: firestore)),
      zoneSegmentsProvider.overrideWith(_LiveZoneSegments.new),
      composedPatternProvider.overrideWith((ref) => _composed()),
      wledRepositoryProvider.overrideWith((ref) => null),
      deviceChannelsProvider.overrideWithValue(kLiveTwoBuses),
      selectedControllerIdProvider.overrideWithValue('ctl-b'),
      isRemoteModeProvider.overrideWithValue(false),
      if (variation)
        variationBaseProvider.overrideWith((ref) => variationBaseFor(_saved())),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<Map<String, dynamic>> savedDoc(ProviderContainer c, {String? name}) async {
    await c.read(authStateProvider.future);
    await c.read(zoneSegmentsProvider.future);
    final id = await c.read(saveComposedDesignProvider)(name: name);
    expect(id, isNotNull);
    final snap = await firestore.collection('users').doc('u1').collection('designs').get();
    return snap.docs.single.data();
  }

  group('the save', () {
    test('a variation is stamped with the SAVED design\'s controller and bus '
        'lengths, not the live device\'s', () async {
      final data = await savedDoc(studio(variation: true));
      expect(data[kDesignControllerIdField], 'ctl-a');
      expect(data[kDesignBusLengthsField], [100, 100, 100]);
      final back = CustomDesign.fromFirestoreData('x', data);
      expect(back.layoutStamp, kSavedStamp);
      // The composed picture, per channel, as composed over those buses.
      expect(back.channels.map((ch) => ch.channelId), [0, 1, 2]);
      expect(back.channels.map((ch) => ch.ledCount), [100, 100, 100]);
      expect(back.isPositional, isTrue);
      expect(back.composedPattern, isNotNull);
    });

    test('its default name says what it came from', () async {
      final data = await savedDoc(studio(variation: true));
      expect(data['name'], 'Variation of Porch stripes: Red');
    });

    test('a name the customer gives wins', () async {
      final data = await savedDoc(studio(variation: true), name: 'Porch every other');
      expect(data['name'], 'Porch every other');
      expect(data[kDesignBusLengthsField], [100, 100, 100]);
    });

    test('an ordinary studio save still stamps from the live buses (slice 1)',
        () async {
      final data = await savedDoc(studio(variation: false));
      expect(data[kDesignControllerIdField], 'ctl-b');
      expect(data[kDesignBusLengthsField], [100, 100]);
    });
  });

  group('the in-memory apply design', () {
    test('a variation carries the saved design\'s stamp, and the fit gate '
        'refuses it on the other layout', () async {
      final c = studio(variation: true);
      await c.read(authStateProvider.future);
      await c.read(zoneSegmentsProvider.future);
      final design = c.read(composedDesignForApplyProvider)!;
      expect(design.layoutStamp, kSavedStamp);
      final fit = designLayoutFit(c.read, design);
      expect(fit.applies, isFalse);
      expect(fit.verdict, LayoutFitVerdict.differentController);
    });

    test('an ordinary studio design is unstamped in memory, as before', () async {
      final c = studio(variation: false);
      await c.read(authStateProvider.future);
      await c.read(zoneSegmentsProvider.future);
      final design = c.read(composedDesignForApplyProvider)!;
      expect(design.layoutStamp, isNull);
      expect(designLayoutFit(c.read, design).applies, isTrue);
    });
  });
}
