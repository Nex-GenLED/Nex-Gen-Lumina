// #86 option-b verification — AI Design Studio SAVE.
//
// Proves a Design Studio save:
//   1. Adapter: splits a ComposedPattern's whole-roofline colorGroups into
//      per-channel ChannelDesigns (segment-local re-base) AND attaches the
//      full composedPattern map (with sourceIntent preserved).
//   2. Model round-trip: composed_pattern is persisted jsonEncoded (a String,
//      so its nested col:[[…]] arrays never hit the #84 native codec) and
//      decodes back to a Map; legacy docs without the field → null (unchanged).
//   3. End-to-end: saveComposedDesignProvider writes /users/{uid}/designs/
//      {autoId} with BOTH populated channels AND a composed_pattern field,
//      and the design surfaces via designsStreamProvider (My Designs).

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/design/design_studio_providers.dart';
import 'package:nexgen_command/features/design/models/composed_pattern.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A ComposedPattern spanning a 188-LED roofline split as Roof [0,128) and
  // Side [128,188). colorGroups are ABSOLUTE; wledPayload carries the #84
  // nested-array shape (col:[[…]]).
  ComposedPattern buildPattern() => ComposedPattern(
        name: 'Spooky Halloween',
        description: 'Orange and purple',
        sourceIntent: DesignIntent(
          originalPrompt: 'orange roofline, purple on the side',
          layers: [
            DesignLayer(
              id: 'layer-1',
              name: 'base',
              targetZone: const ZoneSelector.all(),
              colors: const ColorAssignment.solid(Color(0xFFFF6600)),
            ),
          ],
          parsedAt: DateTime(2026, 5, 30),
        ),
        colorGroups: const [
          LedColorGroup(startLed: 0, endLed: 127, color: [255, 102, 0, 0]),
          LedColorGroup(startLed: 128, endLed: 187, color: [128, 0, 128, 0]),
        ],
        effectId: 9,
        speed: 200,
        intensity: 64,
        brightness: 210,
        hasMotion: true,
        wledPayload: const {
          'on': true,
          'bri': 210,
          'seg': [
            {
              'id': 0,
              'start': 0,
              'stop': 188,
              // Nested arrays — the exact #84 SIGABRT shape.
              'col': [
                [255, 102, 0],
                [128, 0, 128],
              ],
              'fx': 9,
            }
          ],
        },
        totalPixels: 188,
        composedAt: DateTime(2026, 5, 30),
      );

  const segments = <WledSegment>[
    WledSegment(id: 0, name: 'Roof', start: 0, stop: 128),
    WledSegment(id: 1, name: 'Side', start: 128, stop: 188),
  ];

  group('#86 — adapter (channelsFromComposedPattern / customDesignFromComposedPattern)', () {
    test('splits absolute colorGroups into segment-local per-channel designs', () {
      final channels = channelsFromComposedPattern(buildPattern(), segments);

      expect(channels, hasLength(2));

      final roof = channels.firstWhere((c) => c.channelId == 0);
      expect(roof.channelName, 'Roof');
      expect(roof.ledCount, 128);
      expect(roof.colorGroups, hasLength(1));
      expect(roof.colorGroups.first.startLed, 0);
      expect(roof.colorGroups.first.endLed, 127);
      expect(roof.colorGroups.first.color, [255, 102, 0, 0]);
      // Pattern-global effect params propagate to each channel.
      expect(roof.effectId, 9);
      expect(roof.speed, 200);
      expect(roof.intensity, 64);

      final side = channels.firstWhere((c) => c.channelId == 1);
      expect(side.channelName, 'Side');
      expect(side.ledCount, 60);
      expect(side.colorGroups, hasLength(1));
      // Re-based to segment-local: absolute 128..187 → local 0..59.
      expect(side.colorGroups.first.startLed, 0);
      expect(side.colorGroups.first.endLed, 59);
      expect(side.colorGroups.first.color, [128, 0, 128, 0]);
    });

    test('no segments → single channel 0 spanning all pixels', () {
      final channels = channelsFromComposedPattern(buildPattern(), const []);
      expect(channels, hasLength(1));
      expect(channels.first.channelId, 0);
      expect(channels.first.ledCount, 188);
      expect(channels.first.colorGroups, hasLength(2));
    });

    test('customDesignFromComposedPattern attaches the AI source-of-truth', () {
      final design = customDesignFromComposedPattern(
        pattern: buildPattern(),
        segments: segments,
        ownerId: 'u1',
      );

      expect(design.name, 'Spooky Halloween'); // auto-named from pattern
      expect(design.ownerId, 'u1');
      expect(design.brightness, 210);
      expect(design.channels, hasLength(2));

      // composedPattern present and carries the layered sourceIntent.
      expect(design.composedPattern, isNotNull);
      expect(design.composedPattern!['source_intent'], isNotNull);
      final intent = design.composedPattern!['source_intent'] as Map;
      expect(intent['original_prompt'], 'orange roofline, purple on the side');
      expect((intent['layers'] as List), hasLength(1));
      // Raw wled_payload (nested arrays) is carried in-memory pre-encode.
      expect(design.composedPattern!['wled_payload'], isNotNull);
    });
  });

  group('#86 — CustomDesign Firestore round-trip (composed_pattern)', () {
    test('toFirestore writes composed_pattern as a jsonEncoded String (#84-safe)', () {
      final design = customDesignFromComposedPattern(
        pattern: buildPattern(),
        segments: segments,
        ownerId: 'u1',
      );

      final fire = design.toFirestore();

      // Must be a String, NOT a raw Map — otherwise sanitizeForFirestore would
      // throw on the nested col:[[…]] arrays.
      expect(fire['composed_pattern'], isA<String>());
      expect(fire['channels'], isA<List>());
      expect((fire['channels'] as List), hasLength(2));

      // The String decodes back to the full composed map.
      final decoded = jsonDecode(fire['composed_pattern'] as String) as Map<String, dynamic>;
      expect(decoded['name'], 'Spooky Halloween');
      expect(decoded['source_intent'], isNotNull);
      expect(decoded['wled_payload'], isNotNull);
    });

    test('fromFirestoreData decodes composed_pattern back to a Map', () {
      final design = customDesignFromComposedPattern(
        pattern: buildPattern(),
        segments: segments,
        ownerId: 'u1',
      );
      final fire = design.toFirestore();

      final restored = CustomDesign.fromFirestoreData('doc1', fire);
      expect(restored.composedPattern, isA<Map<String, dynamic>>());
      expect(restored.composedPattern!['name'], 'Spooky Halloween');
      expect(restored.composedPattern!['source_intent'], isNotNull);
      expect(restored.channels, hasLength(2));
    });

    test('legacy doc without composed_pattern → null (unchanged behavior)', () {
      final legacy = <String, dynamic>{
        'name': 'Old Manual Design',
        'owner_id': 'u1',
        'channels': const [],
        'brightness': 200,
      };
      final restored = CustomDesign.fromFirestoreData('legacy1', legacy);
      expect(restored.composedPattern, isNull);
      expect(restored.name, 'Old Manual Design');
    });
  });

  group('#86 — saveComposedDesignProvider end-to-end', () {
    late FakeFirebaseFirestore firestore;
    late ProviderContainer container;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream<User?>.value(_StubUser('u1')),
          ),
          designServiceProvider.overrideWith(
            (ref) => DesignService(firestore: firestore),
          ),
          zoneSegmentsProvider.overrideWith(_FixedZoneSegmentsNotifier.new),
          composedPatternProvider.overrideWith((ref) => buildPattern()),
        ],
      );
      addTearDown(container.dispose);
    });

    test('writes /users/{uid}/designs/{autoId} with BOTH channels AND '
        'composed_pattern (and does not throw on the #84 nested arrays)', () async {
      await container.read(authStateProvider.future);
      // Hydrate the async segment list so the adapter splits per-channel
      // rather than falling back to the offline single-channel path.
      await container.read(zoneSegmentsProvider.future);

      final saveFn = container.read(saveComposedDesignProvider);
      final designId = await saveFn();

      expect(designId, isNotNull);
      expect(designId, isNotEmpty);

      final snap = await firestore
          .collection('users')
          .doc('u1')
          .collection('designs')
          .get();
      expect(snap.docs, hasLength(1));

      final data = snap.docs.first.data();
      expect(data['owner_id'], 'u1');
      expect(data['name'], 'Spooky Halloween');
      // Derived denormalization present.
      expect(data['channels'], isA<List>());
      expect((data['channels'] as List), hasLength(2));
      // AI source-of-truth present and stored as a String (jsonEncoded).
      expect(data['composed_pattern'], isA<String>());
      final composed = jsonDecode(data['composed_pattern'] as String) as Map<String, dynamic>;
      expect(composed['source_intent'], isNotNull);
    });

    test('saved design surfaces via designsStreamProvider (My Designs)', () async {
      await container.read(authStateProvider.future);
      // Hydrate the async segment list so the adapter splits per-channel
      // rather than falling back to the offline single-channel path.
      await container.read(zoneSegmentsProvider.future);

      final saveFn = container.read(saveComposedDesignProvider);
      await saveFn();

      final designs = await container
          // ignore: deprecated_member_use
          .read(designsStreamProvider.stream)
          .firstWhere((list) => list.isNotEmpty);

      expect(designs, hasLength(1));
      expect(designs.first.name, 'Spooky Halloween');
      expect(designs.first.composedPattern, isNotNull);
      expect(designs.first.channels, hasLength(2));
    });
  });
}

// ── Test fakes ──────────────────────────────────────────────────────────

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

/// Returns a fixed segment list, bypassing the real notifier's WLED fetch.
class _FixedZoneSegmentsNotifier extends ZoneSegmentsNotifier {
  @override
  Future<List<WledSegment>> build() async => const [
        WledSegment(id: 0, name: 'Roof', start: 0, stop: 128),
        WledSegment(id: 1, name: 'Side', start: 128, stop: 188),
      ];
}
