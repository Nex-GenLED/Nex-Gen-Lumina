// #84 Audit-3 — Scene serialization twin of CustomDesign.
//
// Scene.toFirestore() persisted two List<List<int>> (arrays-of-arrays) fields
// RAW: top-level `preview_colors` and `library_pattern.colors`. The native iOS
// Firestore codec aborts on directly-nested arrays (SIGABRT, #84); after the
// sanitize guard landed it instead THROWS FirestoreSerializationError — so any
// scene carrying preview colors (every library/snapshot save) failed SILENTLY.
//
// The fix mirrors the in-file `wled_payload` idiom and CustomDesign's
// `composed_pattern`: jsonEncode the nested fields on write, decode on read,
// tolerating legacy raw-List docs.
//
// These tests prove:
//   1. toFirestore encodes both fields to opaque Strings (no nested arrays).
//   2. The output passes UserService.sanitizeForFirestore WITHOUT throwing
//      (this is the exact guard that made saves fail silently before).
//   3. Round-trips correctly on read (current jsonEncoded shape).
//   4. Legacy docs with RAW nested Lists still decode (backward compatible).

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';
import 'package:nexgen_command/models/smart_pattern.dart';
import 'package:nexgen_command/services/user_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Scene buildLibraryScene() => Scene.fromPattern(
        const SmartPattern(
          id: 'patt-1',
          name: 'Red White Blue',
          description: '',
          colors: [
            [255, 0, 0],
            [255, 255, 255],
            [0, 0, 255],
          ],
          effectId: 12,
          speed: 200,
          intensity: 64,
          category: 'holiday',
        ),
        'u1',
      );

  group('#84 Audit-3 — Scene.toFirestore nested-color encoding', () {
    test('encodes preview_colors and library_pattern.colors to opaque Strings',
        () {
      final fire = buildLibraryScene().toFirestore();

      // Must be Strings, NOT raw nested Lists — otherwise the iOS codec aborts
      // and sanitizeForFirestore throws.
      expect(fire['preview_colors'], isA<String>());
      final libraryPattern = fire['library_pattern'] as Map<String, dynamic>;
      expect(libraryPattern['colors'], isA<String>());

      // The Strings decode back to the original matrices.
      expect(
        jsonDecode(fire['preview_colors'] as String),
        [
          [255, 0, 0],
          [255, 255, 255],
          [0, 0, 255],
        ],
      );
      expect(
        jsonDecode(libraryPattern['colors'] as String),
        [
          [255, 0, 0],
          [255, 255, 255],
          [0, 0, 255],
        ],
      );
    });

    test('toFirestore output passes sanitizeForFirestore WITHOUT throwing '
        '(the guard that made saves fail silently before)', () {
      final fire = buildLibraryScene().toFirestore();

      // Pre-fix this threw FirestoreSerializationError on the nested arrays.
      expect(
        () => UserService.sanitizeForFirestore(fire),
        returnsNormally,
      );
    });

    test('a snapshot scene with preview_colors also sanitizes cleanly', () {
      final scene = Scene.snapshot(
        name: 'Captured',
        ownerId: 'u1',
        wledPayload: const {'on': true, 'bri': 200},
        previewColors: const [
          [10, 20, 30],
          [40, 50, 60],
        ],
      );
      expect(
        () => UserService.sanitizeForFirestore(scene.toFirestore()),
        returnsNormally,
      );
    });

    test('empty preview colors sanitize cleanly (encodes to "[]")', () {
      final scene = Scene.snapshot(
        name: 'No Preview',
        ownerId: 'u1',
        wledPayload: const {'on': true, 'bri': 200},
      );
      final fire = scene.toFirestore();
      expect(fire['preview_colors'], '[]');
      expect(
        () => UserService.sanitizeForFirestore(fire),
        returnsNormally,
      );
    });
  });

  group('#84 Audit-3 — Scene Firestore round-trip', () {
    late FakeFirebaseFirestore firestore;

    setUp(() => firestore = FakeFirebaseFirestore());

    Future<Scene> writeAndRead(Scene scene) async {
      final ref = firestore.collection('scenes').doc('s1');
      await ref.set(UserService.sanitizeForFirestore(scene.toFirestore()));
      final doc = await ref.get();
      return Scene.fromFirestore(doc);
    }

    test('library scene round-trips preview + pattern colors', () async {
      final restored = await writeAndRead(buildLibraryScene());

      expect(restored.type, SceneType.library);
      expect(restored.previewColors, [
        [255, 0, 0],
        [255, 255, 255],
        [0, 0, 255],
      ]);
      expect(restored.libraryPattern, isNotNull);
      expect(restored.libraryPattern!.colors, [
        [255, 0, 0],
        [255, 255, 255],
        [0, 0, 255],
      ]);
      expect(restored.libraryPattern!.effectId, 12);
      expect(restored.libraryPattern!.speed, 200);
      expect(restored.libraryPattern!.intensity, 64);
    });

    test('snapshot scene round-trips preview colors', () async {
      final restored = await writeAndRead(Scene.snapshot(
        name: 'Captured',
        ownerId: 'u1',
        wledPayload: const {'on': true, 'bri': 180},
        previewColors: const [
          [1, 2, 3],
          [4, 5, 6],
        ],
      ));
      expect(restored.type, SceneType.snapshot);
      expect(restored.previewColors, [
        [1, 2, 3],
        [4, 5, 6],
      ]);
      expect(restored.wledPayload, {'on': true, 'bri': 180});
    });
  });

  // Legacy docs (raw nested arrays) cannot be written through FakeFirebaseFirestore
  // — it validates and rejects nested arrays exactly like the real backend. So we
  // feed Scene.fromFirestore a lightweight DocumentSnapshot stub instead, which is
  // also closer to what a real Android-written pre-fix doc would deliver on read.
  group('#84 Audit-3 — legacy raw-List backward compatibility on read', () {
    test('decodes a pre-fix doc whose colors are RAW nested Lists', () {
      final restored = Scene.fromFirestore(_FakeDocSnapshot('legacy1', {
        'name': 'Legacy Library Scene',
        'type': 'library',
        'owner_id': 'u1',
        'created_at': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updated_at': Timestamp.fromDate(DateTime(2026, 1, 1)),
        // RAW nested lists (the old, unencoded shape).
        'preview_colors': [
          [9, 8, 7],
        ],
        'brightness': 200,
        'library_pattern': {
          'id': 'p9',
          'name': 'Old Pattern',
          'colors': [
            [1, 1, 1],
            [2, 2, 2],
          ],
          'effect_id': 5,
          'speed': 100,
          'intensity': 100,
          'category': 'mood',
        },
      }));

      expect(restored.previewColors, [
        [9, 8, 7],
      ]);
      expect(restored.libraryPattern!.colors, [
        [1, 1, 1],
        [2, 2, 2],
      ]);
    });

    test('null / missing color fields decode to empty lists', () {
      final restored = Scene.fromFirestore(_FakeDocSnapshot('sparse1', {
        'name': 'Sparse',
        'type': 'snapshot',
        'owner_id': 'u1',
        'created_at': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updated_at': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'wled_payload': jsonEncode({'on': true}),
      }));
      expect(restored.previewColors, isEmpty);
    });
  });
}

// Minimal DocumentSnapshot stub so we can hand Scene.fromFirestore raw
// (pre-encode) document data that FakeFirebaseFirestore would reject on write.
// DocumentSnapshot is sealed; subclassing for a scoped test fake is intentional.
// ignore: subtype_of_sealed_class
class _FakeDocSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDocSnapshot(this._id, this._data);
  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}
