// FIX B (#11b) GUARD — The Neighborhood Sync "Popular" strip must be sourced
// from the LIVE pattern catalog, not a hardcoded array of fabricated names.
//
// Before this fix, `_kFeaturedPatterns` was 16 self-contained
// SyncPatternAssignments with invented names ("Warm Meteor", "Cyan Chase", …)
// that matched NO real catalog design — curation that silently drifts as the
// catalog evolves. These tests assert the replacement:
//
//   1. Every curated ref (kFeaturedSyncRefs) resolves to a REAL, current
//      catalog PALETTE node — no phantom/non-existent ids.
//   2. resolveFeaturedPatterns builds well-formed designs whose NAMES come from
//      the real catalog node (no fabricated names) and carry pal:5.
//   3. A curated id that can't resolve is OMITTED (not a phantom card).
//   4. The defense-in-depth guard rejects malformed payloads (empty col /
//      unknown fx) so they can never be shown or applied.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_control_panel.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PatternRepository repo;

  setUp(() {
    repo = PatternRepository();
  });

  group('Popular strip is catalog-sourced (#11b)', () {
    test('EVERY curated ref resolves to a real, current catalog palette '
        '(no phantom ids)', () async {
      expect(kFeaturedSyncRefs, isNotEmpty);
      for (final ref in kFeaturedSyncRefs) {
        final node = await repo.getNodeById(ref.nodeId);
        expect(node, isNotNull,
            reason: 'curated id "${ref.nodeId}" does not exist in the catalog '
                '— it would render as a phantom card');
        expect(node!.isPalette, isTrue,
            reason: '"${ref.nodeId}" must be a color palette node');
        expect(node.themeColors, isNotNull);
        expect(node.themeColors, isNotEmpty);
        // The effect must be a real WLED effect id.
        expect(WledEffectsCatalog.getById(ref.effectId), isNotNull,
            reason: 'effect ${ref.effectId} for "${ref.nodeId}" is not a real '
                'WLED effect');
      }
    });

    test('resolveFeaturedPatterns yields one well-formed design per ref, named '
        'from the real catalog node, carrying pal:5', () async {
      final resolved = await resolveFeaturedPatterns(repo, kFeaturedSyncRefs);

      // All curated refs are real → none dropped.
      expect(resolved.length, kFeaturedSyncRefs.length);

      for (var i = 0; i < resolved.length; i++) {
        final a = resolved[i];
        final node = await repo.getNodeById(kFeaturedSyncRefs[i].nodeId);

        // No fabricated names — the name IS the catalog node's name.
        expect(a.name, node!.name,
            reason: 'Popular entry must use the real catalog name, not a '
                'fabricated one');
        expect(a.effectId, kFeaturedSyncRefs[i].effectId);

        // Well-formed + Colors-Only palette (the chaos-prevention invariant).
        expect(a.colors, isNotEmpty);
        expect(a.pal, 5);
        expect(isWellFormedSyncAssignment(a), isTrue);
      }
    });

    test('NONE of the old fabricated names survive', () async {
      final resolved = await resolveFeaturedPatterns(repo, kFeaturedSyncRefs);
      final names = resolved.map((a) => a.name).toSet();
      const fabricated = {
        'Warm Meteor',
        'Cyan Chase',
        'Ocean Flow',
        'Crimson Wipe',
        'Electric Storm',
        'Gold Scan',
        'Sunset Flow',
        'Rainbow Chase',
      };
      expect(names.intersection(fabricated), isEmpty,
          reason: 'fabricated featured names must be gone — Popular is now '
              'catalog-sourced');
    });
  });

  group('Omission & safety guard (defense-in-depth)', () {
    test('a curated id that cannot resolve is OMITTED, not a phantom card',
        () async {
      final resolved = await resolveFeaturedPatterns(repo, const [
        FeaturedPatternRef('this_palette_does_not_exist_xyz', 28),
      ]);
      expect(resolved, isEmpty);
    });

    test('a real id mixed with a bogus id resolves only the real one', () async {
      final resolved = await resolveFeaturedPatterns(repo, const [
        FeaturedPatternRef('arch_k3000_all', 0),
        FeaturedPatternRef('totally_made_up_id', 0),
      ]);
      expect(resolved.length, 1);
      expect(resolved.single.colors, isNotEmpty);
    });

    test('a ref pointing at a folder/category (not a palette) is omitted',
        () async {
      // 'cat_holiday' and 'holiday_christmas' are category/folder nodes — they
      // carry no themeColors and must never reach the strip.
      final resolved = await resolveFeaturedPatterns(repo, const [
        FeaturedPatternRef('cat_holiday', 0),
        FeaturedPatternRef('holiday_christmas', 0),
      ]);
      expect(resolved, isEmpty);
    });

    test('isWellFormedSyncAssignment rejects empty colors and unknown effects',
        () {
      // Empty col → fail-safe reject.
      expect(
        isWellFormedSyncAssignment(
          const SyncPatternAssignment(name: 'X', effectId: 0, colors: []),
        ),
        isFalse,
      );
      // Unknown fx → fail-safe reject.
      expect(
        isWellFormedSyncAssignment(
          const SyncPatternAssignment(
              name: 'X', effectId: 99999, colors: [0xFFFFFF]),
        ),
        isFalse,
      );
      // Valid → allowed.
      expect(
        isWellFormedSyncAssignment(
          const SyncPatternAssignment(
              name: 'X', effectId: 28, colors: [0x00BCD4, 0xFFFFFF]),
        ),
        isTrue,
      );
    });
  });
}
