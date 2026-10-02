// The design card's Static setup (Blocks | Alternating) and grouping row:
// what shows for every selection, decided by the pure `staticSetupControls`
// (solid_palette_blocks.dart). Field report 2026-10-02: the card hid the
// chips and the grouping numbers as soon as another effect was previewed,
// and showed the grouping row under Blocks, where it means nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

StaticSetupControls _for({
  required int effectId,
  int colorCount = 3,
  SolidLayout layout = SolidLayout.blocks,
  bool isArchitectural = false,
  bool isBrightnessGradient = false,
}) =>
    staticSetupControls(
      effectId: effectId,
      colorCount: colorCount,
      layout: layout,
      isArchitectural: isArchitectural,
      isBrightnessGradient: isBrightnessGradient,
      effectUsesColorLayout: WledEffectsCatalog.effectUsesColorLayout(effectId),
    );

void main() {
  group('Static selected on a multi-colour palette', () {
    test('Blocks: chips on and active, NO grouping row, spacing + preview on',
        () {
      final c = _for(effectId: 0, layout: SolidLayout.blocks);
      expect(c.showCard, isTrue);
      expect(c.showChips, isTrue);
      expect(c.chipsActive, isTrue);
      expect(c.showGrouping, isFalse,
          reason: 'Blocks lays the palette out positionally; grp is meaningless');
      expect(c.showSpacingAndPreview, isTrue);
      expect(c.groupingReturnsToStatic, isFalse);
    });

    test('Alternating: chips active AND the grouping row', () {
      final c = _for(effectId: 0, layout: SolidLayout.alternating);
      expect(c.chipsActive, isTrue);
      expect(c.showGrouping, isTrue, reason: 'bands are grp LEDs wide');
      expect(c.groupingReturnsToStatic, isFalse,
          reason: 'Static is already selected');
      expect(c.showSpacingAndPreview, isTrue);
    });

    test('two colours behave like three', () {
      for (final layout in SolidLayout.values) {
        final c = _for(effectId: 0, colorCount: 2, layout: layout);
        expect(c.showChips, isTrue);
        expect(c.chipsActive, isTrue);
        expect(c.showGrouping, layout == SolidLayout.alternating);
      }
    });
  });

  group('previewing another effect keeps the Static setup on screen', () {
    test('Chase (no colour layout), Blocks remembered: chips only, unselected',
        () {
      final c = _for(effectId: 28, layout: SolidLayout.blocks);
      expect(c.showCard, isTrue, reason: 'the card used to vanish here');
      expect(c.showChips, isTrue);
      expect(c.chipsActive, isFalse, reason: 'Chase is what plays, not Blocks');
      expect(c.showGrouping, isFalse);
      expect(c.showSpacingAndPreview, isFalse,
          reason: 'spacing and the dot row describe the SELECTED effect');
    });

    test('Chase, Alternating remembered: chips AND the grouping row, both '
        'returning to Static on a tap', () {
      final c = _for(effectId: 28, layout: SolidLayout.alternating);
      expect(c.showChips, isTrue);
      expect(c.chipsActive, isFalse);
      expect(c.showGrouping, isTrue,
          reason: 'the row is Static setup: Alternating is remembered');
      expect(c.groupingReturnsToStatic, isTrue,
          reason: 'Chase does not read grp; a tap is a return to Static');
      expect(c.showSpacingAndPreview, isFalse);
    });

    test('Glitter (uses colour layout), either layout remembered: chips '
        'unselected, grouping row for Glitter, a tap keeps Glitter', () {
      for (final layout in SolidLayout.values) {
        final c = _for(effectId: 87, layout: layout);
        expect(c.showChips, isTrue);
        expect(c.chipsActive, isFalse);
        expect(c.showGrouping, isTrue, reason: 'Glitter bands are grp wide');
        expect(c.groupingReturnsToStatic, isFalse,
            reason: 'the row drives Glitter here, not Static');
        expect(c.showSpacingAndPreview, isTrue);
      }
    });

    test('every top pick keeps the chips on a multi-colour palette', () {
      for (final effect in WledEffectsCatalog.topPicks) {
        final c = _for(effectId: effect.id);
        expect(c.showChips, isTrue, reason: 'fx ${effect.id} ${effect.name}');
        expect(c.chipsActive, effect.id == 0,
            reason: 'fx ${effect.id} ${effect.name}');
      }
    });
  });

  group('returning to Static', () {
    test('the remembered layout decides the row again, nothing else changes',
        () {
      // A preview never writes the layout or grouping providers; the decider
      // is a pure function of them, so the state before the preview is the
      // state after.
      final before = _for(effectId: 0, layout: SolidLayout.alternating);
      final during = _for(effectId: 76, layout: SolidLayout.alternating);
      final after = _for(effectId: 0, layout: SolidLayout.alternating);
      expect(during.chipsActive, isFalse);
      expect(after.chipsActive, before.chipsActive);
      expect(after.showGrouping, before.showGrouping);
      expect(after.showSpacingAndPreview, before.showSpacingAndPreview);
    });
  });

  group('palettes the Static setup does not apply to', () {
    test('one colour: no chips; Solid hides the card, Glitter keeps its row',
        () {
      final solid = _for(effectId: 0, colorCount: 1);
      expect(solid.showCard, isFalse);
      final glitter = _for(effectId: 87, colorCount: 1);
      expect(glitter.showCard, isTrue);
      expect(glitter.showChips, isFalse);
      expect(glitter.showGrouping, isTrue);
      expect(glitter.showSpacingAndPreview, isTrue);
    });

    test('architectural multi-colour Solid: no chips, the grp/spc rows as '
        'before (its spacing IS the look)', () {
      final c = _for(effectId: 0, colorCount: 2, isArchitectural: true);
      expect(c.showCard, isTrue);
      expect(c.showChips, isFalse);
      expect(c.showGrouping, isTrue);
      expect(c.groupingReturnsToStatic, isFalse);
      expect(c.showSpacingAndPreview, isTrue);
    });

    test('architectural palette previewing Chase: no card at all', () {
      final c = _for(effectId: 28, colorCount: 2, isArchitectural: true);
      expect(c.showCard, isFalse);
    });

    test('brightness gradient: nothing (it has its own controls)', () {
      final c = _for(effectId: 0, isBrightnessGradient: true);
      expect(c, same(StaticSetupControls.none));
      expect(c.showCard, isFalse);
    });
  });
}
