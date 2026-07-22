// Audit-2 S4 + S5 — favorites write paths actually persist (and surface
// failures) instead of faking success.
//
// S4: PatternControlCard's "Save to Favorites" button previously ONLY showed a
//     'Saved to Favorites' toast and called nothing — a dead success toast. It
//     now calls FavoritesNotifier.addFavorite and gates the toast on the write.
//
// S5: FavoriteHeartButton previously fired addFavorite/removeFromFavorites with
//     no await and no try/catch — they rethrow on failure → unhandled async
//     exception while the heart silently reverted. It now awaits, surfaces
//     failures via SnackBar, and handles the signed-out case explicitly.
//
// FavoritesNotifier talks to FirebaseFirestore.instance directly (not
// injectable), so these tests override favoritesNotifierProvider with a
// recording/throwing fake and assert the WIDGET-level behavior the fixes added:
// the write is invoked, success is gated on it, and failures surface.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/wled/pattern_category_detail.dart';
import 'package:nexgen_command/models/smart_pattern.dart';
import 'package:nexgen_command/widgets/favorite_heart_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pattern = SmartPattern(
    id: 'patt-1',
    name: 'Evening Glow',
    colors: [
      [255, 0, 0],
      [0, 0, 255],
    ],
    effectId: 0,
    speed: 128,
    intensity: 200,
  );

  // Pumps a widget under a ProviderScope + MaterialApp, then resolves the
  // (stream-backed) authStateProvider so the handler's synchronous
  // `ref.read(authStateProvider).value` sees the overridden value.
  Future<_RecordingFavoritesNotifier> pumpAndResolveAuth(
    WidgetTester tester, {
    required Widget child,
    required User? user,
    Set<String> favoritedIds = const {},
    bool throwOnWrite = false,
  }) async {
    final fake = _RecordingFavoritesNotifier(throwOnWrite: throwOnWrite);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(user)),
          favoritedPatternIdsProvider
              .overrideWith((ref) => Stream<Set<String>>.value(favoritedIds)),
          favoritesNotifierProvider.overrideWith(() => fake),
        ],
        child: MaterialApp(home: Scaffold(body: Center(child: child))),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(authStateProvider.future);
    await tester.pump();
    return fake;
  }

  group('S4 — PatternControlCard "Save to Favorites" actually persists', () {
    Future<void> expandCard(WidgetTester tester) async {
      // The Save buttons live behind the expander.
      await tester.tap(find.byIcon(Icons.expand_more));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping the button calls addFavorite with the pattern data '
        'and shows the success toast', (tester) async {
      final fake = await pumpAndResolveAuth(
        tester,
        child: const PatternControlCard(pattern: pattern),
        user: _StubUser('u1'),
      );

      await expandCard(tester);
      await tester.tap(find.text('Save to Favorites'));
      await tester.pump(); // run the async handler
      await tester.pump(); // surface the SnackBar

      expect(fake.addCalls, 1, reason: 'the button must actually persist');
      expect(fake.lastPatternId, 'patt-1');
      expect(fake.lastPatternName, 'Evening Glow');
      expect(fake.lastPatternData, isNotNull);
      expect(fake.lastPatternData!['seg'], isA<List>());
      expect(find.text('Saved to Favorites'), findsOneWidget);
    });

    testWidgets('a failing write surfaces an error instead of a fake success',
        (tester) async {
      final fake = await pumpAndResolveAuth(
        tester,
        child: const PatternControlCard(pattern: pattern),
        user: _StubUser('u1'),
        throwOnWrite: true,
      );

      await expandCard(tester);
      await tester.tap(find.text('Save to Favorites'));
      await tester.pump();
      await tester.pump();

      expect(fake.addCalls, 1);
      expect(find.text('Failed to save to Favorites'), findsOneWidget);
      expect(find.text('Saved to Favorites'), findsNothing,
          reason: 'must not claim success on a failed write');
    });

    testWidgets('signed-out user is prompted to sign in and nothing is written',
        (tester) async {
      final fake = await pumpAndResolveAuth(
        tester,
        child: const PatternControlCard(pattern: pattern),
        user: null,
      );

      await expandCard(tester);
      await tester.tap(find.text('Save to Favorites'));
      await tester.pump();
      await tester.pump();

      expect(fake.addCalls, 0);
      expect(find.text('Please sign in to save favorites'), findsOneWidget);
      expect(find.text('Saved to Favorites'), findsNothing);
    });
  });

  group('S5 — FavoriteHeartButton awaits + surfaces failures', () {
    const heart = FavoriteHeartButton(
      patternId: 'patt-1',
      patternName: 'Evening Glow',
      patternData: {'seg': []},
    );

    testWidgets('successful add is awaited and toggles via the notifier',
        (tester) async {
      final fake = await pumpAndResolveAuth(
        tester,
        child: heart,
        user: _StubUser('u1'),
      );

      await tester.tap(find.byType(FavoriteHeartButton));
      await tester.pump();
      await tester.pump();

      expect(fake.addCalls, 1);
      expect(fake.lastPatternId, 'patt-1');
      // No error SnackBar on the happy path.
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('already-favorited tap calls removeFromFavorites',
        (tester) async {
      final fake = await pumpAndResolveAuth(
        tester,
        child: heart,
        user: _StubUser('u1'),
        favoritedIds: const {'patt-1'},
      );

      await tester.tap(find.byType(FavoriteHeartButton));
      await tester.pump();
      await tester.pump();

      expect(fake.removeCalls, 1);
      expect(fake.addCalls, 0);
    });

    testWidgets('a failing write surfaces an error with no unhandled exception',
        (tester) async {
      final fake = await pumpAndResolveAuth(
        tester,
        child: heart,
        user: _StubUser('u1'),
        throwOnWrite: true,
      );

      await tester.tap(find.byType(FavoriteHeartButton));
      await tester.pump();
      await tester.pump();

      expect(fake.addCalls, 1);
      expect(find.text('Failed to save favorite'), findsOneWidget);
      // If the rethrow had gone unhandled, takeException() would return it.
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed-out tap prompts sign-in and never calls the notifier',
        (tester) async {
      final fake = await pumpAndResolveAuth(
        tester,
        child: heart,
        user: null,
      );

      await tester.tap(find.byType(FavoriteHeartButton));
      await tester.pump();
      await tester.pump();

      expect(fake.addCalls, 0);
      expect(fake.removeCalls, 0);
      expect(find.text('Please sign in to save favorites'), findsOneWidget);
    });
  });
}

// ── Test fakes ──────────────────────────────────────────────────────────

/// Records add/remove calls in place of the real Firestore-backed notifier,
/// optionally throwing to simulate a write failure (the real methods rethrow).
class _RecordingFavoritesNotifier extends FavoritesNotifier {
  _RecordingFavoritesNotifier({this.throwOnWrite = false});
  final bool throwOnWrite;

  int addCalls = 0;
  int removeCalls = 0;
  String? lastPatternId;
  String? lastPatternName;
  Map<String, dynamic>? lastPatternData;

  @override
  void build() {}

  @override
  Future<void> addFavorite({
    required String patternId,
    required String patternName,
    required Map<String, dynamic> patternData,
    bool autoAdded = false,
  }) async {
    addCalls++;
    lastPatternId = patternId;
    lastPatternName = patternName;
    lastPatternData = patternData;
    if (throwOnWrite) throw Exception('simulated write failure');
  }

  @override
  Future<void> removeFromFavorites(String patternId) async {
    removeCalls++;
    lastPatternId = patternId;
    if (throwOnWrite) throw Exception('simulated remove failure');
  }
}

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
