// Tests for UserService.sanitizeForFirestore — the recursive payload walker
// that converts non-Firestore-encodable Dart values to encodable forms
// (Color → int, DateTime → Timestamp, NaN/Infinity → null) and now
// THROWS [FirestoreSerializationError] for truly unknown types instead of
// silently coercing them via `toString()` (the #84 native-abort hole).
//
// The previous fallback masked any leak: a custom class instance got
// toString'd into a String at the Dart level, but if the iOS platform-
// channel codec downstream still rejected it (or a downstream consumer
// of the saved doc expected the original type), the save crashed natively
// with no diagnostic surface. Replacing the fallback with a hard throw
// converts the native abort into a Dart exception that the existing
// try/catch in every write path catches, surfaces via snackbar, and
// includes the offending key PATH + runtimeType so the next iteration
// can add explicit handling.
//
// Coverage targets per the #84 fix spec:
//   1. NaN / Infinity doubles → dropped (returns null at value level, key
//      omitted at map level).
//   2. Color → ARGB int.
//   3. DateTime → Timestamp.
//   4. Nested Map/List recursion preserves shape, keys stringified.
//   5. CustomDesign-shape payload (the actual #84 save path) produces ONLY
//      primitive / Firestore-native leaves.
//   6. Unknown type throws FirestoreSerializationError with the correct
//      key path (this is the diagnostic surface that #84 hinges on).

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/services/user_service.dart';

// A deliberately-unencodable class used to verify the throw path.
class _UnknownLeaf {
  final String tag;
  const _UnknownLeaf(this.tag);
  @override
  String toString() => 'UnknownLeaf($tag)';
}

void main() {
  group('sanitizeForFirestore — primitive passthrough', () {
    test('top-level primitives survive unchanged', () {
      final out = UserService.sanitizeForFirestore({
        'a_string': 'hello',
        'an_int': 42,
        'a_double': 3.14,
        'a_bool': true,
      });
      expect(out['a_string'], 'hello');
      expect(out['an_int'], 42);
      expect(out['a_double'], 3.14);
      expect(out['a_bool'], true);
    });

    test('null values are dropped (Firestore reads null as "delete field")',
        () {
      final out = UserService.sanitizeForFirestore({
        'kept': 1,
        'dropped': null,
      });
      expect(out.containsKey('dropped'), false);
      expect(out['kept'], 1);
    });
  });

  group('sanitizeForFirestore — NaN / Infinity drops', () {
    test('NaN double is dropped from a map (no key emitted)', () {
      final out = UserService.sanitizeForFirestore({
        'good': 1.0,
        'bad': double.nan,
      });
      expect(out.containsKey('bad'), false);
      expect(out['good'], 1.0);
    });

    test('Infinity double (positive AND negative) dropped', () {
      final out = UserService.sanitizeForFirestore({
        'pos_inf': double.infinity,
        'neg_inf': double.negativeInfinity,
        'good': 0.5,
      });
      expect(out.containsKey('pos_inf'), false);
      expect(out.containsKey('neg_inf'), false);
      expect(out['good'], 0.5);
    });

    test('NaN inside a nested list is filtered, leaving the list shorter', () {
      final out = UserService.sanitizeForFirestore({
        'nums': [1.0, double.nan, 3.0, double.infinity, 5.0],
      });
      expect(out['nums'], [1.0, 3.0, 5.0]);
    });
  });

  group('sanitizeForFirestore — type conversions', () {
    test('Color → ARGB int', () {
      const red = Color(0xFFFF0000);
      final out = UserService.sanitizeForFirestore({'fill': red});
      expect(out['fill'], isA<int>());
      expect(out['fill'], 0xFFFF0000);
    });

    test('DateTime → Timestamp', () {
      final dt = DateTime.utc(2026, 5, 29, 12, 0, 0);
      final out = UserService.sanitizeForFirestore({'created': dt});
      expect(out['created'], isA<Timestamp>());
      expect((out['created'] as Timestamp).toDate().toUtc(), dt);
    });

    test('FieldValue.serverTimestamp() passes through unchanged', () {
      final st = FieldValue.serverTimestamp();
      final out = UserService.sanitizeForFirestore({'last_used': st});
      expect(out['last_used'], same(st));
    });

    test('Timestamp passes through unchanged', () {
      final ts = Timestamp.fromMillisecondsSinceEpoch(1700000000000);
      final out = UserService.sanitizeForFirestore({'ts': ts});
      expect(out['ts'], same(ts));
    });
  });

  group('sanitizeForFirestore — nested structure preservation', () {
    test('nested Map/List recursion keeps primitives in shape', () {
      final out = UserService.sanitizeForFirestore({
        'top': {
          'list': [
            {'inner': 1},
            {'inner': 2},
          ],
        },
      });
      expect(out['top'], isA<Map>());
      final list = (out['top'] as Map)['list'] as List;
      expect(list.length, 2);
      expect((list[0] as Map)['inner'], 1);
      expect((list[1] as Map)['inner'], 2);
    });

    test('Color inside deeply nested list is converted to int', () {
      final out = UserService.sanitizeForFirestore({
        'seg': [
          {
            'col': [Colors.blue],
          },
        ],
      });
      final col = ((out['seg'] as List).first as Map)['col'] as List;
      expect(col.first, isA<int>());
    });

    test('Map keys are stringified (non-String keys do not crash)', () {
      final out =
          UserService.sanitizeForFirestore(<String, dynamic>{'nested': {1: 'a', 2: 'b'}});
      final inner = out['nested'] as Map;
      expect(inner['1'], 'a');
      expect(inner['2'], 'b');
    });
  });

  group(
    'sanitizeForFirestore — CustomDesign-shape payload (#84 actual flow)',
    () {
      // The raw "Save As Custom Pattern" payload at wled_dashboard_page.dart:1475-1492.
      // The literal `'col': [[r,g,b,w]]` is `List<List<int>>` — WLED's color-slot
      // schema. Firestore's native iOS codec rejects directly-nested arrays
      // with NSInvalidArgumentException → objc_terminate → uncatchable SIGABRT
      // (#84). Previous version of this test asserted the sanitizer let it
      // through; that codified the bug. Post-fix, the sanitizer THROWS on the
      // raw shape and the addFavorite write path jsonEncodes the payload
      // first so the encoded form passes cleanly.
      final rawPayload = {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'fx': 0,
            'sx': 128,
            'ix': 128,
            'pal': 0,
            'col': [
              [255, 0, 0, 0],
            ],
          }
        ],
      };

      test(
        'raw payload (post-Fix-B) throws on nested arrays-of-arrays with correct path',
        () {
          try {
            UserService.sanitizeForFirestore({
              'name': 'My Test Pattern',
              'usageCount': 1,
              'lastUsed': FieldValue.serverTimestamp(),
              'wledPayload': rawPayload,
              'autoAdded': false,
            });
            fail('expected FirestoreSerializationError on nested arrays');
          } on FirestoreSerializationError catch (e) {
            // Path points at the inner array element — the offending list-in-list.
            expect(e.path, 'wledPayload.seg[0].col[0]');
            expect(e.valuePreview, contains('nested list'));
            expect(e.valuePreview, contains('jsonEncode'));
          }
        },
      );

      test(
        'jsonEncoded payload (post-Fix-A) sanitizes cleanly with only primitive leaves',
        () {
          // What favorites_providers.dart addFavorite now writes: wledPayload
          // is a String, not a Map. Firestore happily accepts arbitrary
          // String values, so nested-array structure is fully neutralized.
          final wrapped = {
            'name': 'My Test Pattern',
            'usageCount': 1,
            'lastUsed': FieldValue.serverTimestamp(),
            'wledPayload': jsonEncode(rawPayload),
            'autoAdded': false,
          };
          final out = UserService.sanitizeForFirestore(wrapped);
          expect(out['name'], 'My Test Pattern');
          expect(out['autoAdded'], false);
          expect(out['wledPayload'], isA<String>());
          // Round-trips: decode the persisted string yields original structure.
          final decoded = jsonDecode(out['wledPayload'] as String);
          expect(decoded, equals(rawPayload));
          _assertAllLeavesEncodable(out, path: 'wrapped');
        },
      );

      test(
        'top-level List<List<int>> input throws (covers any future caller)',
        () {
          // Same class of bug, simpler shape — proves Fix B catches it even
          // when the nested array isn't buried under wledPayload.
          expect(
            () => UserService.sanitizeForFirestore({
              'matrix': [
                [1, 2, 3],
                [4, 5, 6],
              ],
            }),
            throwsA(isA<FirestoreSerializationError>()
                .having((e) => e.path, 'path', 'matrix[0]')),
          );
        },
      );
    },
  );

  group('sanitizeForFirestore — unknown type throws (#84 diagnostic surface)',
      () {
    test('top-level unknown value throws with empty path', () {
      expect(
        () => UserService.sanitizeForFirestore({'leaf': const _UnknownLeaf('X')}),
        throwsA(isA<FirestoreSerializationError>()
            .having((e) => e.path, 'path', 'leaf')
            .having((e) => e.valueType, 'valueType', _UnknownLeaf)),
      );
    });

    test('deeply nested unknown value throws with full dotted+indexed path',
        () {
      // This is the precise diagnostic that #84 needs from production: when
      // the next save crash hits, the snackbar/debug_errors entry tells us
      // EXACTLY which leaf is offending so the sanitizer can grow an
      // explicit branch for that type. Shape avoids nested-list (covered
      // separately by Fix-B tests) to isolate dotted-key + list-index
      // path precision.
      try {
        UserService.sanitizeForFirestore({
          'wledPayload': {
            'seg': [
              {
                'extra': {
                  'tag': const _UnknownLeaf('warmWhite'),
                },
              },
            ],
          },
        });
        fail('expected FirestoreSerializationError to be thrown');
      } on FirestoreSerializationError catch (e) {
        expect(e.path, 'wledPayload.seg[0].extra.tag');
        expect(e.valueType, _UnknownLeaf);
        expect(e.valuePreview, contains('UnknownLeaf'));
        // The toString format is what surfaces in the user-facing snackbar
        // and in any /debug_errors/ doc — verify it's diagnostic.
        final msg = e.toString();
        expect(msg, contains('wledPayload.seg[0].extra.tag'));
        expect(msg, contains('_UnknownLeaf'));
      }
    });

    test('unknown value as a Map value throws with key in path', () {
      try {
        UserService.sanitizeForFirestore({
          'outer': {'inner_key': const _UnknownLeaf('Y')},
        });
        fail('expected throw');
      } on FirestoreSerializationError catch (e) {
        expect(e.path, 'outer.inner_key');
      }
    });
  });
}

// Recursively asserts every leaf in the sanitized output is a Firestore-
// encodable primitive or native type. Used by the CustomDesign-shape test
// to lock down the contract beyond spot-checks.
void _assertAllLeavesEncodable(dynamic value, {required String path}) {
  if (value == null) return;
  if (value is String || value is bool || value is int) return;
  if (value is double) {
    expect(value.isNaN, false, reason: '$path is NaN');
    expect(value.isInfinite, false, reason: '$path is Infinity');
    return;
  }
  if (value is Timestamp ||
      value is GeoPoint ||
      value is FieldValue ||
      value is DocumentReference) {
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      _assertAllLeavesEncodable(entry.value,
          path: '$path.${entry.key}');
    }
    return;
  }
  if (value is List) {
    for (var i = 0; i < value.length; i++) {
      _assertAllLeavesEncodable(value[i], path: '$path[$i]');
    }
    return;
  }
  fail('non-encodable leaf at $path: ${value.runtimeType}');
}
