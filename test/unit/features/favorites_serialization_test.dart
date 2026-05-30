// Tests for FavoritePattern's wledPayload serialization — the #84 fix path.
//
// addFavorite (favorites_providers.dart) now `jsonEncode`s patternData before
// writing, because Firestore's native iOS codec rejects directly-nested
// arrays like `'col': [[r,g,b,w]]` with an uncatchable SIGABRT. Reads must
// tolerate BOTH the new String shape AND the legacy Map shape so docs that
// somehow persisted before the fix don't blow up on first read.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';

void main() {
  group('FavoritePattern.decodeWledPayload — Fix A back-compat', () {
    // The literal raw payload that wled_dashboard_page.dart:1475-1492 builds
    // for "Save As Custom Pattern". Note `col: [[r,g,b,w]]` is List<List<int>>.
    final rawWledPayload = <String, dynamic>{
      'on': true,
      'bri': 200,
      'seg': [
        {
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'pal': 0,
          'col': [
            [255, 64, 0, 0],
          ],
        },
      ],
    };

    test('String (jsonEncoded) input round-trips to the original Map shape', () {
      final encoded = jsonEncode(rawWledPayload);
      final decoded = FavoritePattern.decodeWledPayload(encoded);
      expect(decoded, equals(rawWledPayload));
      // Nested-array structure survives the round-trip — the consumer
      // (applying the favorite back to the WLED device) needs it intact.
      final col = ((decoded['seg'] as List).first as Map)['col'] as List;
      expect(col.first, isA<List>());
      expect((col.first as List).cast<int>(), [255, 64, 0, 0]);
    });

    test('Map (legacy pre-fix) input passes through without throwing', () {
      // A doc that was written before Fix A landed — if it somehow made it
      // to Firestore in raw-Map form, reads must not throw.
      final decoded = FavoritePattern.decodeWledPayload(rawWledPayload);
      expect(decoded, equals(rawWledPayload));
    });

    test('null input returns empty map', () {
      expect(FavoritePattern.decodeWledPayload(null), <String, dynamic>{});
    });

    test('empty string returns empty map (no jsonDecode crash)', () {
      expect(FavoritePattern.decodeWledPayload(''), <String, dynamic>{});
    });

    test('malformed JSON string returns empty map (graceful failure)', () {
      // A corrupt doc shouldn't propagate a FormatException out of a read.
      expect(
        FavoritePattern.decodeWledPayload('{this is not json'),
        <String, dynamic>{},
      );
    });

    test('JSON string encoding a non-Map (e.g. a list) returns empty map', () {
      // Defensive: jsonDecode could succeed on a list literal, but the
      // contract is Map<String, dynamic>.
      expect(
        FavoritePattern.decodeWledPayload('[1,2,3]'),
        <String, dynamic>{},
      );
    });

    test('non-String, non-Map input returns empty map', () {
      expect(FavoritePattern.decodeWledPayload(42), <String, dynamic>{});
      expect(FavoritePattern.decodeWledPayload(true), <String, dynamic>{});
    });
  });
}
