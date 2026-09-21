// The canonical `/users/{uid}/favorites/{id}` document, and the two models
// that read it.
//
// WHY THIS FILE EXISTS: the favorite heart, "Save to Favorites" and the brand
// design generator all wrote `{name, usageCount, lastUsed, wledPayload,
// autoAdded}`. The live security rule requires a create to carry
// `pattern_name` + `added_at`, so every one of those writes was denied — and
// nothing caught it, because the widget tests swap the notifier for a fake and
// never look at the document. These tests pin the document to the RULES FILE
// itself, so the two cannot drift apart silently again.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart'
    as heart;
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart' as grid;
import 'package:nexgen_command/services/user_service.dart';

/// The keys the favorites CREATE rule demands, read out of `firestore.rules`.
List<String> _ruleRequiredCreateKeys() {
  final rules = File('firestore.rules').readAsStringSync();
  final start = rules.indexOf('match /users/{userId}/favorites/{favoriteId}');
  expect(start, greaterThanOrEqualTo(0), reason: 'favorites rule block moved');
  final block = rules.substring(start, rules.indexOf('\n    }\n', start));
  final m = RegExp(r"allow create:[\s\S]*?hasAll\(\[([^\]]*)\]\)")
      .firstMatch(block);
  expect(m, isNotNull, reason: 'favorites create rule no longer uses hasAll');
  return RegExp(r"'([^']+)'")
      .allMatches(m!.group(1)!)
      .map((x) => x.group(1)!)
      .toList();
}

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

void main() {
  // cloud_firestore captures its FieldValue factory in a static on FIRST use.
  // Constructing the fake installs the mock factory, so it has to happen before
  // anything in this file builds a server timestamp.
  setUpAll(FakeFirebaseFirestore.new);

  group('buildFavoriteCreateData — conforms to the live rule', () {
    test('carries every key the create rule requires, correctly typed', () {
      final required = _ruleRequiredCreateKeys();
      expect(required, containsAll(<String>['pattern_name', 'added_at']),
          reason: 'sanity: parsed the rule this fix was written against');

      final doc = buildFavoriteCreateData(
          patternName: 'Kansas City Chiefs', payload: _wledPayload);
      for (final key in required) {
        expect(doc.containsKey(key), isTrue, reason: 'rule requires "$key"');
      }
      // `pattern_name is string`
      expect(doc['pattern_name'], 'Kansas City Chiefs');
      // `added_at is timestamp` — a server timestamp resolves to request.time.
      expect(doc['added_at'], isA<FieldValue>());
    });

    test('is exactly the key set of the favorites that exist in production',
        () {
      final doc = buildFavoriteCreateData(
          patternName: 'Evening Glow', payload: _wledPayload);
      expect(doc.keys.toSet(), {
        'pattern_name',
        'added_at',
        'pattern_data',
        'usage_count',
        'auto_added',
      });
      expect(doc['usage_count'], 0);
      expect(doc['auto_added'], isFalse);
    });

    test('never writes the camelCase shape the rule rejects', () {
      final doc =
          buildFavoriteCreateData(patternName: 'X', payload: _wledPayload);
      for (final dead in [
        'name',
        'usageCount',
        'lastUsed',
        'wledPayload',
        'autoAdded'
      ]) {
        expect(doc.containsKey(dead), isFalse, reason: '"$dead" is the old shape');
      }
    });

    test('pattern_data is a JSON string — arrays-of-arrays never reach '
        'Firestore (#84) — and decodes back losslessly', () {
      final doc =
          buildFavoriteCreateData(patternName: 'X', payload: _wledPayload);
      expect(doc['pattern_data'], isA<String>());
      expect(decodeFavoritePayload(doc['pattern_data']), equals(_wledPayload));
      // The sanitizer THROWS on a nested list; passing proves there is none.
      expect(() => UserService.sanitizeForFirestore(doc), returnsNormally);
    });

    test('a per-LED Static payload (290 LEDs, ~5 KB of nested arrays) is '
        'storable', () {
      const pattern = EditablePattern(
        id: 'team_nfl_chiefs',
        name: 'Kansas City Chiefs',
        actionColors: [Color(0xFFE31837), Color(0xFFFFB81C), Color(0xFFFFFFFF)],
      );
      final payload = pattern.toWledPayload(290);
      final doc = buildFavoriteCreateData(
          patternName: pattern.name, payload: payload);
      final back = decodeFavoritePayload(doc['pattern_data']);
      expect(jsonEncode(back), jsonEncode(payload));
      expect(((back['seg'] as List).first as Map)['i'], hasLength(580));
    });

    test('a blank name still satisfies `pattern_name is string` visibly', () {
      final doc =
          buildFavoriteCreateData(patternName: '   ', payload: _wledPayload);
      expect(doc['pattern_name'], kFavoriteFallbackName);
    });
  });

  group('updates — the rule freezes pattern_name and added_at', () {
    test('a refresh never restates either', () {
      final doc = buildFavoriteRefreshData(payload: _wledPayload);
      expect(doc.containsKey('pattern_name'), isFalse);
      expect(doc.containsKey('added_at'), isFalse,
          reason: 'a fresh server timestamp != the stored one → denied');
      expect(decodeFavoritePayload(doc['pattern_data']), equals(_wledPayload));
    });

    test('a usage bump writes the snake_case fields the grid reads', () {
      expect(buildFavoriteUsageData().keys.toSet(),
          {'usage_count', 'last_used'});
    });
  });

  group('writeFavorite', () {
    test('creates the canonical doc at the given id, then REFRESHES it on a '
        'second save without touching its identity fields', () async {
      final db = FakeFirebaseFirestore();
      final ref = db.doc('users/u1/favorites/team_nfl_chiefs');

      await writeFavorite(ref,
          patternName: 'Kansas City Chiefs', payload: _wledPayload);
      final first = (await ref.get()).data()!;
      expect(first['pattern_name'], 'Kansas City Chiefs');
      expect(first['added_at'], isA<Timestamp>());
      expect(first['pattern_data'], isA<String>());

      final tweaked = {..._wledPayload, 'bri': 90};
      await writeFavorite(ref, patternName: 'Renamed', payload: tweaked);
      final second = (await ref.get()).data()!;
      expect(second['pattern_name'], 'Kansas City Chiefs',
          reason: 'immutable under the update rule — must not be restated');
      expect(second['added_at'], first['added_at']);
      expect(decodeFavoritePayload(second['pattern_data'])['bri'], 90);
      expect((await db.collection('users/u1/favorites').get()).size, 1);
    });
  });

  group('readers', () {
    // Field-for-field the shape of every favorite in production (written by
    // the habit learner): pattern_data is a STRING.
    Map<String, dynamic> productionShaped() => {
          'pattern_name': 'Warm White',
          'pattern_data': jsonEncode(_wledPayload),
          'auto_added': true,
          'usage_count': 3,
          'added_at': Timestamp.fromDate(DateTime(2026, 9, 1)),
        };

    test('My Favorites grid model parses a production-shaped favorite '
        '(it used to throw on the string and blank the whole grid)', () {
      final f = grid.FavoritePattern.fromJson({'id': 'a1', ...productionShaped()});
      expect(f.patternName, 'Warm White');
      expect(f.patternData, equals(_wledPayload));
      expect(f.usageCount, 3);
      expect(f.autoAdded, isTrue);
    });

    test('grid model survives the first snapshot after a create, where the '
        'pending server timestamp reads as null', () {
      final pending = {'id': 'a2', ...productionShaped(), 'added_at': null};
      expect(() => grid.FavoritePattern.fromJson(pending), returnsNormally);
    });

    test('grid model still reads a legacy raw-Map payload', () {
      final f = grid.FavoritePattern.fromJson(
          {'id': 'a3', ...productionShaped(), 'pattern_data': _wledPayload});
      expect(f.patternData, equals(_wledPayload));
    });

    test('grid model reads what writeFavorite wrote — write→read round trip',
        () async {
      final db = FakeFirebaseFirestore();
      final ref = db.doc('users/u1/favorites/patt-1');
      await writeFavorite(ref, patternName: 'Evening Glow', payload: _wledPayload);
      final snap = await ref.get();
      final f = grid.FavoritePattern.fromJson({'id': snap.id, ...snap.data()!});
      expect(f.patternName, 'Evening Glow');
      expect(f.patternData, equals(_wledPayload));
      expect(f.autoAdded, isFalse);
    });

    test('a written favorite is returned by the grid\'s own query '
        '(orderBy added_at drops docs lacking the field)', () async {
      final db = FakeFirebaseFirestore();
      await writeFavorite(db.doc('users/u1/favorites/patt-1'),
          patternName: 'Evening Glow', payload: _wledPayload);
      final q = await db
          .collection('users/u1/favorites')
          .orderBy('added_at', descending: true)
          .get();
      expect(q.docs.map((d) => d.id), ['patt-1']);
    });

    test('the heart-side model reads the canonical doc (it used to see '
        '"Unnamed Pattern" and an empty payload for every stored favorite)',
        () async {
      final db = FakeFirebaseFirestore();
      final ref = db.doc('users/u1/favorites/patt-1');
      await ref.set(productionShaped());
      final f = heart.FavoritePattern.fromFirestore(await ref.get());
      expect(f.patternId, 'patt-1');
      expect(f.name, 'Warm White');
      expect(f.usageCount, 3);
      expect(f.autoAdded, isTrue);
      expect(f.wledPayload, equals(_wledPayload));
    });

    test('the heart-side model still reads an old camelCase doc', () async {
      final db = FakeFirebaseFirestore();
      final ref = db.doc('users/u1/favorites/old');
      await ref.set({
        'name': 'Old Shape',
        'usageCount': 2,
        'wledPayload': jsonEncode(_wledPayload),
        'autoAdded': false,
      });
      final f = heart.FavoritePattern.fromFirestore(await ref.get());
      expect(f.name, 'Old Shape');
      expect(f.usageCount, 2);
      expect(f.wledPayload, equals(_wledPayload));
    });
  });
}
