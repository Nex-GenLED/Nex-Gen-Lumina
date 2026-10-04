// #164 (c), owner decision 2026-10-04: Home shows ONLY favorites the customer
// saved. Documents the retired habit learner wrote (`auto_added: true`) are
// never deleted — they stay in the data — but they are not shown and do not
// count toward the cap of two. The two white tiles do not count either.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';
import 'package:nexgen_command/features/favorites/favorites_load_guard.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/widgets/favorites_grid.dart';

const _uid = 'u1';
const _look = {
  'on': true,
  'seg': [
    {
      'fx': 0,
      'col': [
        [0, 70, 255, 0]
      ]
    }
  ]
};

/// [auto] habit-learner documents and [explicit] customer-saved ones.
Future<FakeFirebaseFirestore> _seed({int auto = 0, int explicit = 0}) async {
  final db = FakeFirebaseFirestore();
  for (var i = 0; i < auto; i++) {
    await db.doc('users/$_uid/favorites/auto$i').set({
      'pattern_name': 'Learned $i',
      'added_at': Timestamp.fromDate(DateTime(2026, 9, 20 + i)),
      'pattern_data': '{}',
      'usage_count': 10 - i,
      'auto_added': true,
    });
  }
  for (var i = 0; i < explicit; i++) {
    await db.doc('users/$_uid/favorites/mine$i').set({
      'pattern_name': 'Mine $i',
      'added_at': Timestamp.fromDate(DateTime(2026, 9, 1 + i)),
      'pattern_data': '{}',
      'usage_count': 0,
      'auto_added': false,
    });
  }
  return db;
}

Future<Map<String, String>> _snapshot(FakeFirebaseFirestore db) async => {
      for (final d in (await db.collection('users/$_uid/favorites').get()).docs)
        d.id: d.data().toString(),
    };

FavoritePattern _white(String id, String name) => FavoritePattern(
      id: id,
      patternName: name,
      addedAt: DateTime(2026),
      patternData: const {'on': true},
    );

Future<void> _pumpGrid(WidgetTester tester, FakeFirebaseFirestore db) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      favoriteWhiteSlotsProvider.overrideWith((ref) => [
            _white('white_primary', 'Warm White'),
            _white('white_complement', 'Bright White'),
          ]),
      effectiveUserUidProvider.overrideWith((ref) => _uid),
      installerAccessingCustomerProvider.overrideWith((ref) => null),
      ownProfileProvisioningProvider
          .overrideWith((ref) => ProfileProvisioning.provisioned),
      userServiceProvider.overrideWithValue(UserService(firestore: db)),
      favoritesLoadTimeoutProvider
          .overrideWithValue(const Duration(seconds: 2)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: FavoritesGrid())),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  group('Home shows only the favorites the customer saved', () {
    testWidgets('5 automatic and 0 saved → none shown; the whites and "+" '
        'are', (tester) async {
      final db = await _seed(auto: 5);
      await _pumpGrid(tester, db);
      for (var i = 0; i < 5; i++) {
        expect(find.text('Learned $i'), findsNothing);
      }
      expect(find.text('Warm White'), findsOneWidget);
      expect(find.text('Bright White'), findsOneWidget);
      expect(find.byKey(const ValueKey('favorites-add-tile')), findsOneWidget,
          reason: 'automatic documents do not fill the list');
      await _unmount(tester);
    });

    testWidgets('1 saved + 5 automatic → exactly the one saved is shown',
        (tester) async {
      final db = await _seed(auto: 5, explicit: 1);
      await _pumpGrid(tester, db);
      expect(find.text('Mine 0'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(find.text('Learned $i'), findsNothing);
      }
      expect(find.byKey(const ValueKey('favorites-add-tile')), findsOneWidget);
      await _unmount(tester);
    });

    test('the pure parser drops automatic documents', () {
      final list = sortUserFavorites([
        {'id': 'a', 'pattern_name': 'Learned', 'pattern_data': '{}', 'auto_added': true},
        {'id': 'b', 'pattern_name': 'Mine', 'pattern_data': '{}', 'auto_added': false},
      ]);
      expect(list.map((f) => f.id), ['b']);
    });
  });

  group('the cap counts only saved favorites', () {
    test('5 automatic + 0 saved → two can be added, the third is refused',
        () async {
      final db = await _seed(auto: 5);
      await writeFavorite(db.doc('users/$_uid/favorites/new0'),
          patternName: 'New 0', payload: _look);
      await writeFavorite(db.doc('users/$_uid/favorites/new1'),
          patternName: 'New 1', payload: _look);
      await expectLater(
          writeFavorite(db.doc('users/$_uid/favorites/new2'),
              patternName: 'New 2', payload: _look),
          throwsA(isA<FavoritesFullException>()));
    });

    test('2 saved + any automatic → the third is refused', () async {
      for (final auto in [0, 1, 7]) {
        final db = await _seed(auto: auto, explicit: 2);
        await expectLater(
            writeFavorite(db.doc('users/$_uid/favorites/x'),
                patternName: 'X', payload: _look),
            throwsA(isA<FavoritesFullException>()
                .having((e) => e.count, 'saved count', 2)),
            reason: 'auto $auto');
      }
    });

    test('automatic documents are untouched by adds, refusals and replaces',
        () async {
      final db = await _seed(auto: 5, explicit: 1);
      final before = await _snapshot(db);
      await writeFavorite(db.doc('users/$_uid/favorites/new0'),
          patternName: 'New 0', payload: _look);
      await expectLater(
          writeFavorite(db.doc('users/$_uid/favorites/new1'),
              patternName: 'New 1', payload: _look),
          throwsA(isA<FavoritesFullException>()));
      await replaceFavoriteDoc(db.doc('users/$_uid/favorites/new2'),
          replaceId: 'new0', patternName: 'New 2', payload: _look);
      final after = await _snapshot(db);
      for (var i = 0; i < 5; i++) {
        expect(after['auto$i'], before['auto$i'],
            reason: 'auto$i stays exactly as it was');
      }
      expect(after.keys.where((k) => k.startsWith('auto')), hasLength(5),
          reason: 'nothing automatic is deleted');
    });

    test('saving a pattern whose id an automatic document holds makes it the '
        'customer\'s own (and counts it)', () async {
      final db = await _seed(auto: 1, explicit: 1);
      await writeFavorite(db.doc('users/$_uid/favorites/auto0'),
          patternName: 'Learned 0', payload: _look);
      final d = (await db.doc('users/$_uid/favorites/auto0').get()).data()!;
      expect(d['auto_added'], isFalse);
      await expectLater(
          writeFavorite(db.doc('users/$_uid/favorites/z'),
              patternName: 'Z', payload: _look),
          throwsA(isA<FavoritesFullException>()));
    });
  });
}
