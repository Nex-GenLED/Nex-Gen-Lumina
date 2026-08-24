// Tests for the "My Designs" library node (#62, audit 2026-05-29; reworked in
// audit/DESIGN_CARD_P3.md). Verifies the adapter from CustomDesign →
// LibraryNode and the provider layer that supplies the dynamic root's children.
//
// UPDATED FOR THE TREE CHANGE: my_designs is no longer SYNTHESISED into the
// category list and the node-by-id / ancestors paths — it is a real root in
// PatternRepository._buildRootCategories(). What the provider layer still owns
// is only what a static, auth-less repository cannot know: the auth gate, and
// the per-user Firestore children. The #85 guarantee (surface visible with an
// empty state, never absent) is preserved and re-asserted below.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';

CustomDesign _design({
  String id = 'd1',
  String name = 'All Blue',
  List<List<int>> colors = const [
    [0, 0, 255],
  ],
}) {
  return CustomDesign(
    id: id,
    name: name,
    createdAt: DateTime(2026, 5, 29),
    updatedAt: DateTime(2026, 5, 29),
    ownerId: 'u',
    channels: [
      ChannelDesign(
        channelId: 0,
        channelName: 'Ch0',
        included: true,
        colorGroups: [
          for (final c in colors)
            LedColorGroup(startLed: 0, endLed: 9, color: c),
        ],
      ),
    ],
  );
}

/// [signedIn] drives the auth gate on the dynamic root. Defaults to true —
/// the signed-out case is asserted explicitly in its own group.
ProviderContainer _container(List<CustomDesign> designs,
    {bool signedIn = true}) {
  return ProviderContainer(overrides: [
    designsStreamProvider.overrideWith((_) => Stream.value(designs)),
    authStateProvider.overrideWith(
        (_) => Stream<User?>.value(signedIn ? _FakeUser() : null)),
  ]);
}

/// Minimal stand-in: the providers under test only check `!= null`.
class _FakeUser implements User {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Awaits the designs stream's first emission so providers that depend
/// on its `valueOrNull` (patternCategoriesProvider, libraryChildNodesProvider,
/// libraryNodeByIdProvider for the 'design_*' branch) see the seeded value
/// instead of the pre-emission null.
Future<void> _primeDesignsStream(ProviderContainer c) async {
  await c.read(designsStreamProvider.future);
}

void main() {
  group('libraryNodeByIdProvider — the dynamic root and its children', () {
    test('"my_designs" resolves from the REPOSITORY TREE, not a synthesis',
        () async {
      final c = _container(const []);
      addTearDown(c.dispose);
      final node = await c.read(libraryNodeByIdProvider('my_designs').future);
      expect(node, isNotNull);
      expect(node!.id, kMyDesignsCategoryId);
      expect(node.name, 'My Designs');
      expect(node.nodeType, LibraryNodeType.category);
      expect(node.parentId, isNull, reason: 'root category');
      expect(node.metadata?['isDynamic'], isTrue,
          reason: 'the marker is how the provider layer knows to auth-gate it '
              'and to source its children from Firestore');
    });

    test('"design_<id>" → adapted palette node with isSavedDesign:true',
        () async {
      final c = _container([_design(id: 'abc123', name: 'Calming Sky')]);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final node = await c.read(libraryNodeByIdProvider('design_abc123').future);
      expect(node, isNotNull);
      expect(node!.id, 'design_abc123');
      expect(node.name, 'Calming Sky');
      expect(node.nodeType, LibraryNodeType.palette);
      expect(node.parentId, kMyDesignsCategoryId);
      expect(node.metadata?['isSavedDesign'], isTrue);
      expect(node.metadata?['sourceDesignId'], 'abc123');
      expect(node.themeColors, isNotEmpty);
    });

    test('"design_<unknown>" → null', () async {
      final c = _container([_design(id: 'real')]);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final node = await c.read(libraryNodeByIdProvider('design_ghost').future);
      expect(node, isNull);
    });

    test('themeColors fall back to white when design has no color groups',
        () async {
      final design = CustomDesign(
        id: 'empty',
        name: 'Empty',
        createdAt: DateTime(2026, 5, 29),
        updatedAt: DateTime(2026, 5, 29),
        ownerId: 'u',
        channels: const [
          ChannelDesign(channelId: 0, channelName: 'Ch0', included: true),
        ],
      );
      final c = _container([design]);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final node = await c.read(libraryNodeByIdProvider('design_empty').future);
      expect(node, isNotNull);
      expect(node!.themeColors, equals(<Color>[Colors.white]));
    });
  });

  group('libraryChildNodesProvider("my_designs")', () {
    test('empty designs → empty children', () async {
      final c = _container(const []);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final children =
          await c.read(libraryChildNodesProvider('my_designs').future);
      expect(children, isEmpty);
    });

    test('multiple designs → each adapted as palette node', () async {
      final c = _container([
        _design(id: 'a', name: 'Alpha'),
        _design(id: 'b', name: 'Bravo'),
      ]);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final children =
          await c.read(libraryChildNodesProvider('my_designs').future);
      expect(children, hasLength(2));
      expect(children[0].name, 'Alpha');
      expect(children[0].id, 'design_a');
      expect(children[1].name, 'Bravo');
      expect(children[1].metadata?['isSavedDesign'], isTrue);
    });
  });

  group('libraryAncestorsProvider', () {
    test('"my_designs" → empty (a real root, resolved by the repo)', () async {
      final c = _container(const []);
      addTearDown(c.dispose);
      final ancestors =
          await c.read(libraryAncestorsProvider('my_designs').future);
      expect(ancestors, isEmpty);
    });

    test('"design_<id>" → just the My Designs category', () async {
      final c = _container([_design(id: 'x')]);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final ancestors =
          await c.read(libraryAncestorsProvider('design_x').future);
      expect(ancestors, hasLength(1));
      expect(ancestors.first.id, kMyDesignsCategoryId);
    });
  });

  group('patternCategoriesProvider — one source of truth', () {
    // The #85 guarantee survives the tree change: the surface must be VISIBLE
    // WITH AN EMPTY STATE, never absent, so a writer-drift "lost save" can only
    // look empty (a visible bug) and never like a vanished folder (a silent
    // one). What changed is WHERE that comes from — membership in
    // _buildRootCategories() instead of a runtime prepend.
    test('empty designs → "My Designs" is STILL present '
        '(#85 companion: visible-with-empty-state, never absent)', () async {
      final c = _container(const []);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final cats = await c.read(patternCategoriesProvider.future);
      expect(cats.map((e) => e.id), contains(kMyDesignsCategoryId),
          reason: '#85 companion regression guard: if this fails because '
              'my_designs is missing from categories, a future edit has '
              're-introduced the writer-drift-hides-surface bug class');
    });

    test('appears exactly ONCE — the old prepend would have doubled it',
        () async {
      final c = _container([_design()]);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final cats = await c.read(patternCategoriesProvider.future);
      expect(cats.where((e) => e.id == kMyDesignsCategoryId), hasLength(1));
    });

    test('sorts LAST, after the catalog roots', () async {
      final c = _container(const []);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final cats = await c.read(patternCategoriesProvider.future);
      expect(cats.last.id, kMyDesignsCategoryId);
      expect(cats, hasLength(9));
    });

    test('signed out → 8 categories, My Designs absent', () async {
      final c = _container(const [], signedIn: false);
      addTearDown(c.dispose);
      final cats = await c.read(patternCategoriesProvider.future);
      expect(cats, hasLength(8));
      expect(cats.map((e) => e.id), isNot(contains(kMyDesignsCategoryId)));
    });
  });

  group('node tree root — B4 gate', () {
    test('9 roots authenticated, 8 unauthenticated', () async {
      final signedIn = _container(const []);
      addTearDown(signedIn.dispose);
      final inRoots =
          await signedIn.read(libraryChildNodesProvider(null).future);
      expect(inRoots, hasLength(9));
      expect(inRoots.last.id, kMyDesignsCategoryId,
          reason: 'sortOrder 8 puts it after the 8 catalog roots');

      final guest = _container(const [], signedIn: false);
      addTearDown(guest.dispose);
      final outRoots = await guest.read(libraryChildNodesProvider(null).future);
      expect(outRoots, hasLength(8));
      expect(outRoots.map((n) => n.id), isNot(contains(kMyDesignsCategoryId)));
    });

    test('the grid and the tree agree on the root set AND its order', () async {
      final c = _container(const []);
      addTearDown(c.dispose);
      final cats = await c.read(patternCategoriesProvider.future);
      final nodes = await c.read(libraryChildNodesProvider(null).future);
      expect(cats.map((e) => e.id).toList(), nodes.map((n) => n.id).toList(),
          reason: 'both derive from _buildRootCategories()');
    });
  });

  group('search — saved designs participate, one path', () {
    test('a saved design is findable by name', () async {
      final c = _container([_design(id: 'sd1', name: 'Calming Sky')]);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final results = await c.read(librarySearchProvider('Calming Sky').future);
      expect(results.palettes.map((n) => n.id), contains('design_sd1'));
    });

    test('with no saved designs the catalog result is unchanged', () async {
      final c = _container(const []);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final results = await c.read(librarySearchProvider('Christmas').future);
      expect(results.hasResults, isTrue,
          reason: 'catalog search must be untouched by the extraNodes hook');
      expect(results.palettes.where((n) => n.id.startsWith('design_')), isEmpty);
    });
  });

  group('pinning — my_designs resolves to its real name', () {
    // pinnedCategoriesProvider resolves pinned ids against repo.getCategories(),
    // which used to be the raw static list — so a pinned 'my_designs' fell
    // through to the 'Unknown' placeholder (audit/MY_DESIGNS_AUDIT.md 2b.5
    // item 5). getCategories() is now derived from the tree.
    test('getCategories() contains my_designs with its real name', () async {
      final c = _container(const []);
      addTearDown(c.dispose);
      final repo = c.read(patternRepositoryProvider);
      final cats = await repo.getCategories();
      final mine = cats.where((e) => e.id == kMyDesignsCategoryId).toList();
      expect(mine, hasLength(1));
      expect(mine.single.name, 'My Designs');
      expect(mine.single.name, isNot('Unknown'));
    });
  });
}
