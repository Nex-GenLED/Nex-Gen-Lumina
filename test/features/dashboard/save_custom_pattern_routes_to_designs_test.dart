// #85 W3 fix verification — "Save As Custom Pattern" now routes to /designs/
// (the canonical My Designs read surface), not /favorites/ (which had no
// reader and silently swallowed every save).
//
// Tests saveCurrentAsDesignProvider end-to-end against fake_cloud_firestore:
//   1. Write lands in users/{uid}/designs/{autoId}.
//   2. Write does NOT touch users/{uid}/favorites/.
//   3. designsStreamProvider yields the new design (proves the My Designs
//      surface — which feeds the synthetic Explore category — would render
//      it after this save).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_service.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#85 W3 — Save As Custom Pattern → /designs/', () {
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
          wledStateProvider.overrideWith(_FixedWledNotifier.new),
          zoneSegmentsProvider.overrideWith(_FixedZoneSegmentsNotifier.new),
        ],
      );
      addTearDown(container.dispose);
    });

    test('saveCurrentAsDesignProvider writes to users/{uid}/designs/ and '
        'NOT to /favorites/ (the #85 fix — was writing to unread '
        '/favorites/ before)', () async {
      // Hydrate the auth stream so saveCurrentAsDesignProvider's
      // ref.read(authStateProvider).valueOrNull returns a non-null user.
      await container.read(authStateProvider.future);

      final saveFn = container.read(saveCurrentAsDesignProvider);
      final designId = await saveFn('My Evening Glow');

      expect(designId, isNotNull);
      expect(designId, isNotEmpty);

      // The doc IS in /designs/.
      final designsSnap = await firestore
          .collection('users')
          .doc('u1')
          .collection('designs')
          .get();
      expect(designsSnap.docs, hasLength(1),
          reason: 'exactly one design written to the canonical collection');
      expect(designsSnap.docs.first.data()['name'], 'My Evening Glow');
      expect(designsSnap.docs.first.data()['owner_id'], 'u1');

      // The doc is NOT in /favorites/ (Symptom-1 regression guard for #85).
      final favsSnap = await firestore
          .collection('users')
          .doc('u1')
          .collection('favorites')
          .get();
      expect(favsSnap.docs, isEmpty,
          reason: '#85 fix: this save path must NOT write to /favorites/ '
              '(that collection has no My Designs reader; writes vanish)');
    });

    test('the saved design appears in designsStreamProvider (proves the My '
        'Designs synthetic Explore category would render it)', () async {
      await container.read(authStateProvider.future);

      final saveFn = container.read(saveCurrentAsDesignProvider);
      await saveFn('Holiday Special');

      // streamDesigns is keyed by orderBy('updated_at'); allow the
      // fake-firestore snapshot stream a microtask to deliver.
      // Using `.stream` rather than `.future` so we wait for a non-empty
      // emission (the initial AsyncValue may be loading or an empty list
      // before the post-write snapshot arrives).
      final designs = await container
          // ignore: deprecated_member_use
          .read(designsStreamProvider.stream)
          .firstWhere((list) => list.isNotEmpty);

      expect(designs, hasLength(1));
      expect(designs.first.name, 'Holiday Special');
      expect(designs.first.ownerId, 'u1');
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

/// Overrides WledNotifier.build to return a fixed state, bypassing the
/// real notifier's polling / network init.
class _FixedWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => const WledStateModel(
        isOn: true,
        brightness: 180,
        speed: 128,
        intensity: 200,
        color: Color(0xFFFF8800),
        connected: true,
        warmWhite: 64,
        supportsRgbw: true,
        effectId: 47,
      );
}

/// Overrides ZoneSegmentsNotifier.build to return a fixed segment list,
/// bypassing the real notifier's WLED fetch.
class _FixedZoneSegmentsNotifier extends ZoneSegmentsNotifier {
  @override
  Future<List<WledSegment>> build() async => const [
        WledSegment(id: 0, name: 'Roof', start: 0, stop: 128),
        WledSegment(id: 1, name: 'Side', start: 128, stop: 188),
      ];
}
