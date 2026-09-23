// Library tree coherence after the Galaxy & Starlight removal (2026-09-23).
//
// The `arch_galaxy` root (9 Kelvin "Stars" folders, 27 "Dim at N %" folders,
// 9 "Twinkling Stars" folders, 576 leaf cards) stored its second LED
// population as WLED `spc` — a spacing GAP the firmware never lights — so
// every card rendered half the strip permanently black. It was removed
// outright. These tests pin what must be true of the tree afterwards, and
// guard the one thing a catalog deletion can silently break: a node whose
// parent no longer exists is unreachable from Explore.
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';

Future<List<LibraryNode>> _walk(PatternRepository repo) async {
  final all = <LibraryNode>[];
  Future<void> visit(String? parent) async {
    for (final n in await repo.getChildNodes(parent)) {
      all.add(n);
      await visit(n.id);
    }
  }

  await visit(null);
  return all;
}

void main() {
  final repo = PatternRepository();

  test('every node reachable from a root has a parent that exists', () async {
    final all = await _walk(repo);
    final ids = all.map((n) => n.id).toSet();
    expect(all, isNotEmpty);
    for (final n in all) {
      if (n.parentId == null) continue;
      expect(ids, contains(n.parentId), reason: '${n.id} points at a missing parent ${n.parentId}');
    }
  });

  test('no node references the removed Galaxy & Starlight root or its children', () async {
    final all = await _walk(repo);
    for (final n in all) {
      expect(n.id, isNot(startsWith('arch_galaxy')), reason: n.id);
      expect(n.parentId ?? '', isNot(startsWith('arch_galaxy')), reason: '${n.id} parent ${n.parentId}');
      expect(n.metadata?['isGalaxyPattern'], isNull, reason: n.id);
      expect(n.metadata?['isTwinklePattern'], isNull, reason: n.id);
    }
    expect(await repo.getNodeById('arch_galaxy'), isNull);
  });

  test('Architectural Downlighting holds exactly the nine Kelvin folders', () async {
    final kids = await repo.getChildNodes(LibraryCategoryIds.architectural);
    expect(kids.map((n) => n.id).toList(), [
      'arch_k2000', 'arch_k2700', 'arch_k3000', 'arch_k3500', 'arch_k4000',
      'arch_k4500', 'arch_k5000', 'arch_k5500', 'arch_k6500',
    ]);
    for (final k in kids) {
      final direct = await repo.getChildNodes(k.id);
      // Brightness Gradients folder + "All <K>" + 16 "X On Y Off" cards.
      expect(direct.length, 18, reason: k.id);
      expect(direct.where((n) => n.isPalette).length, 17, reason: k.id);
      final gradients = direct.singleWhere((n) => n.id == '${k.id}_gradients');
      expect((await repo.getChildNodes(gradients.id)).length, 6, reason: gradients.id);
      // The spacing cards are the only ones allowed to promise dark LEDs.
      for (final card in direct.where((n) => n.isPalette)) {
        final spc = (card.metadata?['spacing'] as int?) ?? 0;
        if (spc > 0) {
          expect(card.name, matches(RegExp(r'^\d On \d Off$')), reason: card.id);
        }
      }
    }
  });

  test('no palette card outside "X On Y Off" carries spacing', () async {
    final all = await _walk(repo);
    final spaced = all.where((n) => n.isPalette && ((n.metadata?['spacing'] as int?) ?? 0) > 0);
    for (final n in spaced) {
      expect(n.name, matches(RegExp(r'^\d On \d Off$')), reason: n.id);
    }
    expect(spaced.length, 144);
  });
}
