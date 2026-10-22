// Store window item 6, effect renames (App Review 5.2, option A, owner
// approved): three effects keep their WLED ids and change display names.
//   27  Android     → Loading Chase  (robot icon replaced)
//   44  Tetrix      → Falling Blocks
//   120 Ghost Rider → Ghost Trail
//
// Nothing stored refers to an effect by display name: saved designs,
// favorites, Game Day configs (celebrationEffectId), schedules and controller
// presets all carry the numeric fx id, so no hidden alias is needed. The one
// internal name lookup, EffectDatabase routing its entries through
// WledEffectsCatalog.idForName, is renamed in the same commit. These tests
// prove an old stored id still resolves, and that the database did not
// silently drop effect 27.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/effect_database.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

void main() {
  test('stored ids resolve to the new names', () {
    expect(WledEffectsCatalog.getById(27)?.name, 'Loading Chase');
    expect(WledEffectsCatalog.getById(44)?.name, 'Falling Blocks');
    expect(WledEffectsCatalog.getById(120)?.name, 'Ghost Trail');
  });

  test('a Game Day celebration saved as effect 27 is still offered', () {
    expect(WledEffectsCatalog.celebrationPickIds, contains(27));
    expect(WledEffectsCatalog.celebrationPicks.map((e) => e.name),
        contains('Loading Chase'));
  });

  test('EffectDatabase still carries effect 27 (name lookup renamed in step)', () {
    final meta = EffectDatabase.getEffect(27);
    expect(meta, isNotNull, reason: 'a catalog-only rename would drop it');
    expect(meta!.name, 'Loading Chase');
    expect(WledEffectsCatalog.idForName('Loading Chase'), 27);
  });

  test('no displayed catalog name or description uses the old names', () {
    final shown = [
      for (final e in WledEffectsCatalog.allEffects) e.name,
      for (final c in WledEffectsCatalog.categories) c.description,
    ].join(' | ').toLowerCase();
    for (final old in const ['android', 'tetrix', 'ghost rider']) {
      expect(shown, isNot(contains(old)), reason: old);
    }
  });
}
