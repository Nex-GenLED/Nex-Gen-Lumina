// Tests for the synthetic "My Designs" category injection (#62, audit
// 2026-05-29). Verifies the adapter from CustomDesign → LibraryNode and
// the provider-layer branching that surfaces saved designs as standard
// Explore-catalog nodes without modifying PatternRepository.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

ProviderContainer _container(List<CustomDesign> designs) {
  return ProviderContainer(overrides: [
    designsStreamProvider.overrideWith((_) => Stream.value(designs)),
  ]);
}

/// Awaits the designs stream's first emission so providers that depend
/// on its `valueOrNull` (patternCategoriesProvider, libraryChildNodesProvider,
/// libraryNodeByIdProvider for the 'design_*' branch) see the seeded value
/// instead of the pre-emission null.
Future<void> _primeDesignsStream(ProviderContainer c) async {
  await c.read(designsStreamProvider.future);
}

void main() {
  group('libraryNodeByIdProvider — synthetic id space', () {
    test('"my_designs" → synthetic category node', () async {
      final c = _container(const []);
      addTearDown(c.dispose);
      final node = await c.read(libraryNodeByIdProvider('my_designs').future);
      expect(node, isNotNull);
      expect(node!.id, kMyDesignsCategoryId);
      expect(node.name, 'My Designs');
      expect(node.nodeType, LibraryNodeType.category);
      expect(node.parentId, isNull, reason: 'root category');
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
    test('"my_designs" → empty (root category)', () async {
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

  group('patternCategoriesProvider — synthetic prepend (always)', () {
    // ASSERTION INVERTED in the #85 companion fix. Previously the synthetic
    // my_designs category was only prepended when designs.isNotEmpty, which
    // combined with a writer-drift to make a lost save present as a
    // disappeared surface (debugging detour for #85). The category is now
    // ALWAYS prepended; the drill-in view shows a meaningful empty-state
    // placeholder when designs is empty.
    test('empty designs → "My Designs" STILL prepended as first category '
        '(#85 companion: surface visible-with-empty-state, never absent)',
        () async {
      final c = _container(const []);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final cats = await c.read(patternCategoriesProvider.future);
      expect(cats, isNotEmpty);
      expect(cats.first.id, kMyDesignsCategoryId,
          reason: '#85 companion regression guard: if this fails because '
              'my_designs is missing from categories, a future edit has '
              're-introduced the writer-drift-hides-surface bug class');
      expect(cats.first.name, 'My Designs');
    });

    test('non-empty designs → "My Designs" prepended as first category',
        () async {
      final c = _container([_design()]);
      addTearDown(c.dispose);
      await _primeDesignsStream(c);
      final cats = await c.read(patternCategoriesProvider.future);
      expect(cats, isNotEmpty);
      expect(cats.first.id, kMyDesignsCategoryId);
      expect(cats.first.name, 'My Designs');
    });
  });
}
