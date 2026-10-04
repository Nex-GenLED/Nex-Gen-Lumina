// #164 — favorites are capped at two, nothing adds one on its own, and an
// account that holds more from before the cap keeps every one of them.

import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';
import 'package:nexgen_command/features/favorites/favorites_full_dialog.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';

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

Future<FakeFirebaseFirestore> _withFavorites(int n, {bool auto = false}) async {
  final db = FakeFirebaseFirestore();
  for (var i = 0; i < n; i++) {
    await db.doc('users/u1/favorites/f$i').set({
      'pattern_name': 'Existing $i',
      'added_at': DateTime(2026, 9, 1),
      'pattern_data': '{}',
      'usage_count': i,
      'auto_added': auto,
    });
  }
  return db;
}

Future<List<String>> _ids(FakeFirebaseFirestore db) async =>
    (await db.collection('users/u1/favorites').get())
        .docs
        .map((d) => d.id)
        .toList()
      ..sort();

void main() {
  group('the cap at the one write chokepoint', () {
    test('a first and a second favorite are saved', () async {
      final db = await _withFavorites(0);
      await writeFavorite(db.doc('users/u1/favorites/a'),
          patternName: 'A', payload: _look);
      await writeFavorite(db.doc('users/u1/favorites/b'),
          patternName: 'B', payload: _look);
      expect(await _ids(db), ['a', 'b']);
      final a = (await db.doc('users/u1/favorites/a').get()).data()!;
      expect(a['auto_added'], isFalse, reason: 'a favorite is always explicit');
    });

    test('a THIRD is refused, and nothing is written', () async {
      final db = await _withFavorites(2);
      await expectLater(
        writeFavorite(db.doc('users/u1/favorites/c'),
            patternName: 'C', payload: _look),
        throwsA(isA<FavoritesFullException>()
            .having((e) => e.count, 'count', 2)
            .having((e) => e.toString(), 'message', kFavoritesFullMessage)),
      );
      expect(await _ids(db), ['f0', 'f1']);
    });

    test('the message is the owner\'s exact words', () {
      expect(kFavoritesFullMessage,
          'You can keep 2 favorites. Remove one to add another.');
      expect(kMaxFavorites, 2);
    });

    test('re-saving a favorite that exists is not an add — never refused',
        () async {
      final db = await _withFavorites(2);
      await writeFavorite(db.doc('users/u1/favorites/f1'),
          patternName: 'Existing 1', payload: _look);
      expect(await _ids(db), ['f0', 'f1']);
    });

    test('REPLACE swaps one for the new design in one write; the count holds',
        () async {
      final db = await _withFavorites(2);
      await replaceFavoriteDoc(db.doc('users/u1/favorites/new'),
          replaceId: 'f0', patternName: 'New', payload: _look);
      expect(await _ids(db), ['f1', 'new']);
    });
  });

  group('accounts already over the cap are left exactly as they are', () {
    test('an add is refused and all four documents are untouched', () async {
      // Four SAVED favorites (automatic ones no longer count — see
      // favorites_explicit_only_test.dart).
      final db = await _withFavorites(4);
      final before = {
        for (final d in (await db.collection('users/u1/favorites').get()).docs)
          d.id: d.data().toString(),
      };
      await expectLater(
          writeFavorite(db.doc('users/u1/favorites/x'),
              patternName: 'X', payload: _look),
          throwsA(isA<FavoritesFullException>()));
      final after = {
        for (final d in (await db.collection('users/u1/favorites').get()).docs)
          d.id: d.data().toString(),
      };
      expect(after, before, reason: 'nothing deleted, hidden or changed');
    });

    test('a replace on an over-cap account keeps the count where it was',
        () async {
      final db = await _withFavorites(4, auto: true);
      await replaceFavoriteDoc(db.doc('users/u1/favorites/new'),
          replaceId: 'f3', patternName: 'New', payload: _look);
      expect(await _ids(db), ['f0', 'f1', 'f2', 'new']);
    });
  });

  group('nothing adds a favorite on its own', () {
    // A favorites document may be CREATED only by favorite_doc.dart, and the
    // chokepoint may be reached only from an explicit favorite control.
    final lib = Directory('lib');
    final dart = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    String norm(String p) => p.replaceAll(r'\', '/');

    test('no automatic favorites writer remains', () {
      for (final f in dart) {
        final src = f.readAsStringSync();
        expect(src.contains('updateAutoFavorites('), isFalse,
            reason: '${norm(f.path)} — the habit learner wrote favorites on '
                'every app resume');
        expect(RegExp(r"'auto_added'\s*:\s*true").hasMatch(src), isFalse,
            reason: '${norm(f.path)} writes auto_added: true');
        expect(RegExp(r'autoAdded:\s*true').hasMatch(src), isFalse,
            reason: '${norm(f.path)} passes autoAdded: true');
        expect(
            RegExp(r"collection\('favorites'\)\s*\.add\(").hasMatch(src),
            isFalse,
            reason: '${norm(f.path)} adds a favorite with a random id, '
                'around the cap');
      }
    });

    test('only explicit favorite controls reach the chokepoint', () {
      const explicitControls = {
        // the chokepoint and its notifier
        'lib/features/favorites/favorite_doc.dart',
        'lib/features/favorites/favorites_providers.dart',
        'lib/features/favorites/favorites_full_dialog.dart',
        // Home "+" and Replace
        'lib/features/favorites/favorites_picker.dart',
        // the heart on Edit Pattern
        'lib/widgets/favorite_heart_button.dart',
        // Explore card "Save…" → "Save to Favorites"
        'lib/features/wled/colorway_effect_selector.dart',
        // Home suggestion "Add to favorites" button
        'lib/features/dashboard/wled_dashboard_page.dart',
        // Lumina "Save as Favorite"
        'lib/features/ai/lumina_conversation_driver.dart',
      };
      final writer = RegExp(
          r'\b(writeFavorite|replaceFavoriteDoc|saveFavoriteWithCap)\(|'
          r'\.(addFavorite|addToFavorites|replaceFavorite)\(');
      final offenders = [
        for (final f in dart)
          if (writer.hasMatch(f.readAsStringSync()) &&
              !explicitControls.contains(norm(f.path)))
            norm(f.path),
      ];
      expect(offenders, isEmpty,
          reason: 'a favorite is only ever an explicit tap');
    });
  });

  group('the full-list dialog', () {
    for (final (scale, bold) in [(1.0, false), (1.75, true), (2.0, true)]) {
      testWidgets('says the cap and offers each favorite (text ×$scale, '
          'bold $bold)', (tester) async {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);
        String? picked = 'unset';
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(390, 844),
              textScaler: TextScaler.linear(scale),
              boldText: bold,
            ),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async => picked = await showFavoritesFullDialog(
                      context,
                      newName: 'Ocean Breeze - Chase',
                      current: const [
                        FavoriteChoice('f0', 'Royals Game Night'),
                        FavoriteChoice('f1', 'Warm Evening Glow'),
                      ],
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text(kFavoritesFullMessage), findsOneWidget);
        expect(find.text('Royals Game Night'), findsOneWidget);
        expect(find.text('Warm Evening Glow'), findsOneWidget);
        expect(find.text('Keep my favorites'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no overflow');

        await tester.ensureVisible(
            find.byKey(const ValueKey('favorites-replace-f1')));
        await tester.tap(find.byKey(const ValueKey('favorites-replace-f1')));
        await tester.pumpAndSettle();
        expect(picked, 'f1');
      });
    }
  });

  group('saveFavoriteWithCap', () {
    Future<(ProviderContainer, _FullNotifier)> rig(WidgetTester tester) async {
      final notifier = _FullNotifier();
      final container = ProviderContainer(overrides: [
        favoritesNotifierProvider.overrideWith(() => notifier),
        allFavoritesProvider.overrideWith((ref) => Stream.value([
              FavoritePattern(
                patternId: 'f0',
                name: 'Royals Game Night',
                usageCount: 0,
                lastUsed: DateTime(2026, 9, 1),
                wledPayload: const {},
              ),
              FavoritePattern(
                patternId: 'f1',
                name: 'Warm Evening Glow',
                usageCount: 0,
                lastUsed: DateTime(2026, 9, 1),
                wledPayload: const {},
              ),
            ])),
      ]);
      addTearDown(container.dispose);
      return (container, notifier);
    }

    Future<FavoriteSaveOutcome?> run(
        WidgetTester tester, ProviderContainer c, Future<void> Function() act) async {
      FavoriteSaveOutcome? out;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => out = await saveFavoriteWithCap(
                  context,
                  c,
                  patternId: 'new',
                  patternName: 'Ocean Breeze - Chase',
                  payload: _look,
                ),
                child: const Text('save'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('save'));
      await tester.pumpAndSettle();
      await act();
      await tester.pumpAndSettle();
      return out;
    }

    testWidgets('a full list → the dialog → REPLACE the chosen one',
        (tester) async {
      final (c, n) = await rig(tester);
      final out = await run(tester, c, () async {
        await tester.tap(find.byKey(const ValueKey('favorites-replace-f0')));
      });
      expect(out, FavoriteSaveOutcome.replaced);
      expect(n.replaced, [('f0', 'new')]);
    });

    testWidgets('a full list → "Keep my favorites" → nothing changes',
        (tester) async {
      final (c, n) = await rig(tester);
      final out = await run(tester, c, () async {
        await tester.tap(find.byKey(const ValueKey('favorites-full-keep')));
      });
      expect(out, FavoriteSaveOutcome.keptExisting);
      expect(n.replaced, isEmpty);
    });
  });
}

/// A notifier whose list is full: every add is refused; replaces are recorded.
class _FullNotifier extends FavoritesNotifier {
  final replaced = <(String, String)>[];

  @override
  Future<void> addFavorite({
    required String patternId,
    required String patternName,
    required Map<String, dynamic> patternData,
  }) async =>
      throw const FavoritesFullException(2);

  @override
  Future<void> replaceFavorite({
    required String replaceId,
    required String patternId,
    required String patternName,
    required Map<String, dynamic> patternData,
  }) async =>
      replaced.add((replaceId, patternId));
}
