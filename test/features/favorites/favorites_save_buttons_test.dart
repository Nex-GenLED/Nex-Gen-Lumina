// Audit-2 S4 + S5 — favorites write paths actually persist (and surface
// failures) instead of faking success.
//
// S4 covered PatternControlCard's "Save to Favorites" button. That widget was
//     never built by any screen and was removed in +110 E1 (follow-up 5), so
//     its group went with it.
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
import 'package:nexgen_command/features/favorites/favorite_design_payload.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/widgets/favorite_heart_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('S5 — FavoriteHeartButton awaits + surfaces failures', () {
    const heart = FavoriteHeartButton(
      patternId: 'patt-1',
      patternName: 'Evening Glow',
      patternDataBuilder: _heartPayload,
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
      // The payload is built at TAP time and handed to the notifier as-is.
      expect(fake.lastPatternData, equals(await _heartPayload()));
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

    // The heart used to take an `unavailableMessage` and DECLINE (Static mode:
    // "tap SAVE instead"). Static favorites now work, so the only refusal left
    // is a builder that cannot build — and it says why.
    const unbuildable = FavoriteHeartButton(
      patternId: 'patt-1',
      patternName: 'Evening Glow',
      patternDataBuilder: _refusingPayload,
    );

    testWidgets('a builder that cannot build shows ITS reason and writes nothing',
        (tester) async {
      final fake = await pumpAndResolveAuth(tester,
          child: unbuildable, user: _StubUser('u1'));
      await tester.tap(find.byType(FavoriteHeartButton));
      await tester.pump();
      await tester.pump();
      expect(fake.addCalls, 0);
      expect(find.text('Connect to your lights first.'), findsOneWidget);
      expect(find.text('Failed to save favorite'), findsNothing,
          reason: 'the specific reason replaces the generic failure');
      expect(tester.takeException(), isNull);
    });

    testWidgets('…and a heart that is already filled can still be removed',
        (tester) async {
      final fake = await pumpAndResolveAuth(tester,
          child: unbuildable,
          user: _StubUser('u1'),
          favoritedIds: const {'patt-1'});
      await tester.tap(find.byType(FavoriteHeartButton));
      await tester.pump();
      await tester.pump();
      expect(fake.removeCalls, 1);
      expect(find.byType(SnackBar), findsNothing);
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

Future<Map<String, dynamic>> _refusingPayload() async =>
    throw const FavoriteNotSavable('Connect to your lights first.');

/// A WLED-state-shaped payload, as the heart's one real caller builds.
Future<Map<String, dynamic>> _heartPayload() async => {
      'on': true,
      'seg': [
        {
          'fx': 0,
          'col': [
            [255, 0, 0, 0],
          ],
        },
      ],
    };

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
