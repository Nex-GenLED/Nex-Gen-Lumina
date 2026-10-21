// Store window (d): Explore's "Movies & Superheroes" category is hidden for
// build 120 (App Review 5.2: studio, franchise and character names). The
// switch is a const with a Provider twin in library_visibility.dart. Nothing
// is deleted, and flipping the const brings the category back with every id
// unchanged.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/library_visibility.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';

void main() {
  test('the const defaults to hidden, and the Provider twin follows it', () {
    expect(kMoviesCategoryVisible, isFalse);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(moviesCategoryVisibleProvider), isFalse);
  });

  group('hidden (default)', () {
    final repo = PatternRepository();

    test('no category tile', () async {
      final roots = await repo.getChildNodes(null);
      expect(roots.map((n) => n.id), isNot(contains(LibraryCategoryIds.movies)));
      final cats = await repo.getCategories();
      expect(cats.map((c) => c.id), isNot(contains(LibraryCategoryIds.movies)));
      expect(roots.map((n) => n.id), contains('cat_holiday'),
          reason: 'other categories untouched');
    });

    test('no franchise folder or palette by id or by search', () async {
      expect(await repo.getChildNodes(LibraryCategoryIds.movies), isEmpty);
      expect(await repo.getNodeById('franchise_disney'), isNull);
      for (final q in const ['batman', 'mickey', 'hogwarts', 'pikachu', 'star wars']) {
        final r = await repo.searchLibrary(q);
        expect(r.palettes.where((n) => n.id.startsWith('franchise_') ||
                (n.parentId?.startsWith('franchise_') ?? false)),
            isEmpty,
            reason: q);
        expect(r.folders.where((n) => n.id.startsWith('franchise_')), isEmpty,
            reason: q);
      }
    });
  });

  test('flipping the switch brings it all back, ids unchanged', () async {
    final repo = PatternRepository(moviesVisible: true);
    final roots = await repo.getChildNodes(null);
    expect(roots.map((n) => n.id), contains(LibraryCategoryIds.movies));
    expect(await repo.getNodeById('franchise_disney'), isNotNull);
  });

  test('the app repository reads the Provider twin', () async {
    final hidden = ProviderContainer(overrides: [
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
    ]);
    final shown = ProviderContainer(overrides: [
      currentUserProfileProvider.overrideWith((ref) => Stream.value(null)),
      moviesCategoryVisibleProvider.overrideWithValue(true),
    ]);
    addTearDown(hidden.dispose);
    addTearDown(shown.dispose);
    expect(hidden.read(patternRepositoryProvider).moviesVisible, isFalse);
    expect(shown.read(patternRepositoryProvider).moviesVisible, isTrue);
  });
}
