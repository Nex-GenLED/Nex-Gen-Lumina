// Geofence finds a favorite by the canonical `pattern_name`.
//
// WHY THIS FILE EXISTS: the Welcome Home picker and its trigger both keyed on
// the camelCase `name` — a field the live rule rejected on every write, so no
// stored favorite has ever had it. The picker listed no favorites and the
// trigger matched none. Every favorite below is written by the REAL writer
// (`writeFavorite`), so geofence is pinned to the document the app stores, not
// to a look-alike typed into a test.

import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';
import 'package:nexgen_command/features/geofence/geofence_favorite_lookup.dart';

final _wledPayload = <String, dynamic>{
  'on': true,
  'bri': 200,
  'seg': [
    {
      'fx': 12,
      'pal': 5,
      'col': [
        [227, 24, 55, 0],
        [255, 184, 28, 0],
      ],
    },
  ],
};

Future<List<String>> _pickerNames(FakeFirebaseFirestore db, String uid) async {
  final snap = await db.collection('users').doc(uid).collection('favorites').get();
  return geofenceFavoriteNames(snap.docs.map((d) => d.data()));
}

void main() {
  // cloud_firestore captures its FieldValue factory in a static on FIRST use.
  // Constructing the fake installs the mock factory, so it has to happen before
  // anything in this file builds a server timestamp.
  setUpAll(FakeFirebaseFirestore.new);

  group('lookupGeofenceFavoritePayload', () {
    test('finds a favorite saved through the real writer', () async {
      final db = FakeFirebaseFirestore();
      await writeFavorite(db.doc('users/u1/favorites/patt-1'),
          patternName: 'Welcome Home', payload: _wledPayload);

      final payload = await lookupGeofenceFavoritePayload(db,
          uid: 'u1', actionName: 'Welcome Home');

      expect(payload, _wledPayload);
    });

    test('the old `name` query finds nothing on that same document', () async {
      // The bug, pinned: this is the query geofence_monitor used to run.
      final db = FakeFirebaseFirestore();
      await writeFavorite(db.doc('users/u1/favorites/patt-1'),
          patternName: 'Welcome Home', payload: _wledPayload);

      final old = await db
          .collection('users/u1/favorites')
          .where('name', isEqualTo: 'Welcome Home')
          .limit(1)
          .get();

      expect(old.docs, isEmpty);
    });

    test('finds a habit-learned favorite (the shape of every production doc)',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('users/u1/favorites').add({
        'pattern_name': 'Evening Glow',
        'pattern_data': jsonEncode(_wledPayload),
        'added_at': DateTime(2026, 9, 1),
        'usage_count': 4,
        'auto_added': true,
      });

      final payload = await lookupGeofenceFavoritePayload(db,
          uid: 'u1', actionName: 'Evening Glow');

      expect(payload, _wledPayload);
    });

    test('no favorite by that name → null, so the trigger falls back', () async {
      final db = FakeFirebaseFirestore();
      await writeFavorite(db.doc('users/u1/favorites/patt-1'),
          patternName: 'Welcome Home', payload: _wledPayload);

      expect(
        await lookupGeofenceFavoritePayload(db, uid: 'u1', actionName: 'Relax'),
        isNull,
      );
    });

    test("never reads another user's favorites", () async {
      final db = FakeFirebaseFirestore();
      await writeFavorite(db.doc('users/u2/favorites/patt-1'),
          patternName: 'Welcome Home', payload: _wledPayload);

      expect(
        await lookupGeofenceFavoritePayload(db,
            uid: 'u1', actionName: 'Welcome Home'),
        isNull,
      );
    });

    test('an unusable duplicate does not shadow a usable one', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/u1/favorites/a-broken').set({
        'pattern_name': 'Welcome Home',
        'pattern_data': '{not json',
        'added_at': DateTime(2026, 9, 1),
      });
      await writeFavorite(db.doc('users/u1/favorites/b-good'),
          patternName: 'Welcome Home', payload: _wledPayload);

      final payload = await lookupGeofenceFavoritePayload(db,
          uid: 'u1', actionName: 'Welcome Home');

      expect(payload, _wledPayload);
    });

    test('only unusable matches → null', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/u1/favorites/a-broken').set({
        'pattern_name': 'Welcome Home',
        'pattern_data': '',
        'added_at': DateTime(2026, 9, 1),
      });

      expect(
        await lookupGeofenceFavoritePayload(db,
            uid: 'u1', actionName: 'Welcome Home'),
        isNull,
      );
    });
  });

  group('picker ↔ trigger', () {
    test('every name the picker offers resolves in the trigger', () async {
      final db = FakeFirebaseFirestore();
      await writeFavorite(db.doc('users/u1/favorites/patt-1'),
          patternName: 'Welcome Home', payload: _wledPayload);
      // The writer trims; the picker must offer the STORED name, or the
      // trigger's equality query would miss it.
      await writeFavorite(db.doc('users/u1/favorites/patt-2'),
          patternName: '  Chiefs Kingdom  ', payload: _wledPayload);

      final names = await _pickerNames(db, 'u1');

      expect(names, unorderedEquals(['Welcome Home', 'Chiefs Kingdom']));
      for (final name in names) {
        expect(
          await lookupGeofenceFavoritePayload(db, uid: 'u1', actionName: name),
          _wledPayload,
          reason: '"$name" is offered by the picker but not found by the trigger',
        );
      }
    });
  });

  group('geofenceFavoriteNames', () {
    test('reads pattern_name; ignores the dead camelCase `name`', () {
      expect(
        geofenceFavoriteNames([
          {'pattern_name': 'Evening Glow'},
          {'name': 'Old Shape'},
        ]),
        ['Evening Glow'],
      );
    });

    test('de-duplicates — a dropdown asserts on duplicate values', () {
      expect(
        geofenceFavoriteNames([
          {'pattern_name': 'Evening Glow'},
          {'pattern_name': 'Chiefs'},
          {'pattern_name': 'Evening Glow'},
        ]),
        ['Evening Glow', 'Chiefs'],
      );
    });

    test('skips blank and non-string names', () {
      expect(
        geofenceFavoriteNames([
          {'pattern_name': ''},
          {'pattern_name': '   '},
          {'pattern_name': 42},
          {'pattern_name': null},
          <String, dynamic>{},
        ]),
        isEmpty,
      );
    });
  });

  group('geofenceActionChoices', () {
    test('no favorites → exactly the built-in scenes', () {
      expect(geofenceActionChoices(favoriteNames: const []),
          kGeofenceBuiltInActions);
    });

    test('favorites come first; built-ins stay available', () {
      expect(
        geofenceActionChoices(favoriteNames: const ['Evening Glow']),
        ['Evening Glow', ...kGeofenceBuiltInActions],
      );
    });

    test('a favorite named like a built-in appears once', () {
      final choices = geofenceActionChoices(favoriteNames: const ['Relax']);
      expect(choices.where((c) => c == 'Relax'), hasLength(1));
      expect(choices.first, 'Relax');
    });

    test('a saved built-in is still selectable once favorites exist', () {
      final choices = geofenceActionChoices(
          favoriteNames: const ['Evening Glow'], saved: 'Relax');
      expect(choices.where((c) => c == 'Relax'), hasLength(1));
    });

    test('a saved action whose favorite was deleted stays a valid selection',
        () {
      final choices = geofenceActionChoices(
          favoriteNames: const ['Evening Glow'], saved: 'Deleted Favorite');
      expect(choices.where((c) => c == 'Deleted Favorite'), hasLength(1));
    });

    test('never yields duplicates (the dropdown invariant)', () {
      final choices = geofenceActionChoices(
          favoriteNames: const ['Relax', 'Turn Off', 'Evening Glow'],
          saved: 'Evening Glow');
      expect(choices.toSet(), hasLength(choices.length));
    });
  });
}
