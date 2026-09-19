// The Rainbow leak and the Rainbow folder (Nature & Outdoors > Rainbow).
//
// Leak: `topPickIds` carried fx 9, and the All/Any-Color filter returns every
// rainbow-family effect, so a Rainbow tile sat on EVERY palette's selector.
// Colours: on WLED 0.15.1 `color_wheel` samples the segment palette when
// pal != 0, so a "Rainbow" from a 3-colour card rendered a gradient of those
// three colours — and a 6-colour spectrum swatch sent only take(3). The hue
// wheel (the true full spectrum) is reached only at pal:0.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/data/rainbow_palettes.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/rainbow_scope.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

LibraryNode _node(String id, {String? parentId, Map<String, dynamic>? meta}) =>
    LibraryNode(
      id: id,
      name: id,
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      metadata: meta,
    );

void main() {
  group('the leak — rainbow effects no longer reach every card', () {
    test('topPicks (the default list on EVERY palette) carries no rainbow',
        () {
      final ids = WledEffectsCatalog.topPicks.map((e) => e.id).toList();
      expect(ids, isNot(contains(9)), reason: 'fx 9 Rainbow was the leak');
      for (final id in ids) {
        expect(isRainbowEffectId(id), isFalse, reason: 'fx $id in top picks');
      }
      // The list is otherwise the same picks, in the same order.
      expect(ids, [0, 2, 17, 28, 3, 49, 76, 66, 87]);
    });

    test('isRainbowEffectId covers the registry AND the Rainbow category', () {
      for (final id in WledEffectsCatalog.rainbowEffectIds) {
        expect(isRainbowEffectId(id), isTrue, reason: 'registry id $id');
      }
      for (final e in WledEffectsCatalog.allEffects
          .where((e) => e.category == 'Rainbow')) {
        expect(isRainbowEffectId(e.id), isTrue, reason: 'category id ${e.id}');
      }
      for (final id in [0, 2, 17, 28, 83, 84]) {
        expect(isRainbowEffectId(id), isFalse, reason: 'fx $id');
      }
    });

    test('a non-rainbow palette sees NO rainbow-family effect, even under '
        'the All / Any Color filter', () {
      final all = WledEffectsCatalog.filterEffects();
      expect(all.any((e) => isRainbowEffectId(e.id)), isTrue,
          reason: 'sanity: the unscoped catalog does contain them');
      final scoped = scopeRainbowEffects(all, rainbowScope: false);
      expect(scoped.any((e) => isRainbowEffectId(e.id)), isFalse);
      expect(scoped.length, all.length - all.where((e) => isRainbowEffectId(e.id)).length,
          reason: 'only rainbow-family effects are removed');
    });

    test('a Rainbow-folder palette keeps them', () {
      final all = WledEffectsCatalog.filterEffects();
      expect(scopeRainbowEffects(all, rainbowScope: true), all);
    });
  });

  group('the scope — which nodes count as Rainbow', () {
    test('a tagged node, the Rainbow folder itself, or a child of it', () {
      expect(isRainbowLibraryNode(_node('x', meta: {'rainbow': true})), isTrue);
      expect(isRainbowLibraryNode(_node(NatureFolderIds.rainbow)), isTrue);
      expect(isRainbowLibraryNode(_node('x', parentId: NatureFolderIds.rainbow)),
          isTrue);
    });

    test('the TAG scopes a card wherever it is placed — scoping is not a path',
        () {
      for (final parent in [
        LibraryCategoryIds.nature,
        LibraryCategoryIds.holidays,
        'nature_ocean',
        null,
      ]) {
        expect(
            isRainbowLibraryNode(
                _node('x', parentId: parent, meta: {'rainbow': true})),
            isTrue,
            reason: 'tagged card under $parent');
      }
    });

    test('the retired cat_rainbow root id scopes nothing', () {
      expect(isRainbowLibraryNode(_node('cat_rainbow')), isFalse);
      expect(isRainbowLibraryNode(_node('x', parentId: 'cat_rainbow')), isFalse);
    });

    test('Nature & Outdoors nodes are NOT rainbow-scoped', () {
      expect(isRainbowLibraryNode(_node('nature_ocean', parentId: LibraryCategoryIds.nature)),
          isFalse);
      expect(isRainbowLibraryNode(_node('cat_nature')), isFalse);
      expect(isRainbowLibraryNode(null), isFalse);
    });
  });

  group('the colours — full spectrum only from the hue wheel (pal:0)', () {
    test('rainbow effect on a Rainbow card → pal:0; anywhere else → derived',
        () {
      expect(rainbowPaletteOverride(effectId: 9, rainbowScope: true), 0);
      expect(rainbowPaletteOverride(effectId: 63, rainbowScope: true), 0);
      expect(rainbowPaletteOverride(effectId: 9, rainbowScope: false), isNull);
      expect(rainbowPaletteOverride(effectId: 28, rainbowScope: true), isNull,
          reason: 'a chase on a Rainbow card still honours its colours');
    });

    test('the wire payload for a Rainbow card running fx 9 carries pal:0', () {
      final seg = (buildSelectorPayload(SelectorState(
        effectId: 9,
        speed: 128,
        intensity: 200,
        colors: const [
          [255, 0, 0, 0],
          [255, 140, 0, 0],
          [255, 255, 0, 0]
        ],
        paletteOverride: rainbowPaletteOverride(effectId: 9, rainbowScope: true),
      ))['seg'] as List)
          .first as Map;
      expect(seg['pal'], 0,
          reason: 'pal:4 would render a red→orange→yellow gradient of take(3)');
      expect(WledEffectsCatalog.paletteForEffect(9), isNot(0),
          reason: 'sanity: the derived palette is what leaked the truncation');
    });

    test('the swatch is a six-stop spectrum, red through violet, in hue order',
        () {
      expect(kRainbowSpectrum, hasLength(6));
      expect(kRainbowSpectrum.first, const Color(0xFFFF0000));
      expect(kRainbowSpectrum.last, const Color(0xFF8B00FF));
      // Hue must increase monotonically across the six stops.
      double hue(Color c) => HSVColorOf(c).hue;
      final hues = kRainbowSpectrum.map(hue).toList();
      for (var i = 1; i < hues.length; i++) {
        expect(hues[i] > hues[i - 1], isTrue, reason: 'stop $i: $hues');
      }
      expect(hues.last - hues.first, greaterThan(240),
          reason: 'spans most of the wheel, not a warm subset');
    });
  });

  group('the folder — Nature & Outdoors > Rainbow > Full Spectrum', () {
    late PatternRepository repo;
    setUp(() => repo = PatternRepository());

    /// Every node reachable from the roots, via the same getChildNodes the
    /// Explore screens use. My Designs is dynamic (no static children).
    Future<List<LibraryNode>> walk() async {
      final out = <LibraryNode>[];
      final queue = <String?>[null];
      while (queue.isNotEmpty) {
        final kids = await repo.getChildNodes(queue.removeLast());
        for (final k in kids) {
          out.add(k);
          if (!k.isPalette) queue.add(k.id);
        }
      }
      return out;
    }

    test('Rainbow is NOT a top-level folder; the roots are the original eight '
        '+ My Designs, which is last at its original sortOrder 8', () async {
      final roots = await repo.getChildNodes(null);
      expect(roots.map((n) => n.id).toSet(), {
        LibraryCategoryIds.architectural,
        LibraryCategoryIds.sports,
        LibraryCategoryIds.holidays,
        LibraryCategoryIds.movies,
        LibraryCategoryIds.nature,
        LibraryCategoryIds.parties,
        LibraryCategoryIds.seasonal,
        LibraryCategoryIds.security,
        LibraryCategoryIds.myDesigns,
      });
      expect(roots.map((n) => n.id), isNot(contains('cat_rainbow')));
      expect(roots.where((n) => n.name.toLowerCase().contains('rainbow')),
          isEmpty);
      expect(roots.any(isRainbowLibraryNode), isFalse);
      expect(await repo.getNodeById('cat_rainbow'), isNull,
          reason: 'the old root is gone, not orphaned');

      final mine =
          roots.firstWhere((n) => n.id == LibraryCategoryIds.myDesigns);
      expect(mine.sortOrder, 8, reason: 'restored from 9');
      expect(roots.last.id, LibraryCategoryIds.myDesigns);
    });

    test('Nature & Outdoors keeps its seven sub-folders, unmoved, and gains '
        'Rainbow as the eighth', () async {
      final kids = await repo.getChildNodes(LibraryCategoryIds.nature);
      final folders = kids.where((n) => n.isFolder).toList();
      expect(folders.map((n) => n.id).toList(), [
        'nature_space',
        'nature_forest',
        'nature_ocean',
        'nature_mountain',
        'nature_garden',
        'nature_earth',
        'nature_wildlife',
        NatureFolderIds.rainbow,
      ]);
      expect(folders.take(7).map((n) => n.sortOrder).toList(),
          [0, 1, 2, 3, 4, 5, 6]);
      final rainbow = folders.last;
      expect(rainbow.name, 'Rainbow');
      expect(rainbow.nodeType, LibraryNodeType.folder);
      expect(rainbow.parentId, LibraryCategoryIds.nature);
      expect(rainbow.themeColors, kRainbowSpectrum);
      // The card is INSIDE Rainbow, not beside it.
      expect(kids.map((n) => n.id),
          isNot(contains(RainbowPalettes.fullSpectrumId)));
    });

    test('navigation: Nature → Rainbow → Full Spectrum → fx 9 goes out pal:0',
        () async {
      final nature = await repo.getChildNodes(LibraryCategoryIds.nature);
      final folder = nature.firstWhere((n) => n.id == NatureFolderIds.rainbow);

      final cards = await repo.getChildNodes(folder.id);
      expect(cards.map((n) => n.id).toList(), [RainbowPalettes.fullSpectrumId]);
      final card = cards.single;
      expect(card.name, 'Full Spectrum');
      expect(card.isPalette, isTrue);
      expect(card.parentId, NatureFolderIds.rainbow);
      expect(card.themeColors, kRainbowSpectrum);
      expect(card.metadata?['suggestedEffectId'], 9);

      // The breadcrumb is the navigation path.
      final crumbs = await repo.getAncestors(card.id);
      expect(
          crumbs.map((n) => n.id).toList(),
          containsAllInOrder(
              [LibraryCategoryIds.nature, NatureFolderIds.rainbow]));

      // Selecting it: the selector computes scope from the node and the
      // override from the scope — the same two calls the page makes.
      final scope = isRainbowLibraryNode(card);
      expect(scope, isTrue);
      final seg = (buildSelectorPayload(SelectorState(
        effectId: 9,
        speed: 128,
        intensity: 200,
        colors: const [
          [255, 0, 0, 0],
          [255, 140, 0, 0],
          [255, 255, 0, 0]
        ],
        paletteOverride:
            rainbowPaletteOverride(effectId: 9, rainbowScope: scope),
      ))['seg'] as List)
          .first as Map;
      expect(seg['fx'], 9);
      expect(seg['pal'], 0);
      expect(
          scopeRainbowEffects(WledEffectsCatalog.filterEffects(),
                  rainbowScope: scope)
              .any((e) => e.id == 9),
          isTrue,
          reason: 'the Rainbow effect is offered on this card');
    });

    test('the folder holds however many cards are placed in it — untagged '
        'ones included', () {
      // A card dropped in later is scoped by its parentId even if the tag is
      // forgotten.
      expect(
          isRainbowLibraryNode(
              _node('rainbow_pastel', parentId: NatureFolderIds.rainbow)),
          isTrue);
    });

    test('WHOLE LIBRARY: the only rainbow-scoped nodes are the Rainbow folder '
        'and what is inside it — no leak after the move', () async {
      final all = await walk();
      expect(all.length, greaterThan(100), reason: 'sanity: the walk ran');
      final scoped = all.where(isRainbowLibraryNode).map((n) => n.id).toSet();
      expect(scoped, {NatureFolderIds.rainbow, RainbowPalettes.fullSpectrumId});

      // Nature's other seven folders and every card in them stay unscoped.
      final natureSiblings = all.where((n) =>
          n.parentId != null &&
          n.parentId!.startsWith('nature_') &&
          n.parentId != NatureFolderIds.rainbow);
      expect(natureSiblings, isNotEmpty);
      expect(natureSiblings.any(isRainbowLibraryNode), isFalse);

      // Exactly one node named Rainbow anywhere, and it is not a root.
      final named = all.where((n) => n.name == 'Rainbow').toList();
      expect(named.map((n) => n.id).toList(), [NatureFolderIds.rainbow]);
      expect(named.single.parentId, LibraryCategoryIds.nature);
    });
  });
}

/// Minimal HSV hue for a Color without importing material (keeps this a pure
/// Dart test): standard RGB → hue in degrees.
class HSVColorOf {
  final double hue;
  HSVColorOf._(this.hue);
  factory HSVColorOf(Color c) {
    final r = c.r, g = c.g, b = c.b;
    final mx = [r, g, b].reduce((a, b) => a > b ? a : b);
    final mn = [r, g, b].reduce((a, b) => a < b ? a : b);
    final d = mx - mn;
    double h;
    if (d == 0) {
      h = 0;
    } else if (mx == r) {
      h = 60 * (((g - b) / d) % 6);
    } else if (mx == g) {
      h = 60 * (((b - r) / d) + 2);
    } else {
      h = 60 * (((r - g) / d) + 4);
    }
    if (h < 0) h += 360;
    return HSVColorOf._(h);
  }
}
