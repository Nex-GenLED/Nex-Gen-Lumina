import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/rainbow_scope.dart';

/// Nature & Outdoors > Rainbow — the folder and its cards.
///
/// PLACEMENT. A sub-folder of Nature & Outdoors, built with the same
/// `LibraryNodeType.folder` + `parentId` mechanism as Nature's other seven
/// sub-folders (`nature_outdoors_palettes.dart`), which is what wires it into
/// the tree (`getAllNatureFolders` / `getAllNaturePaletteNodes`). It was a root
/// category (`cat_rainbow`) for one day, 2026-09-18; that root no longer
/// exists.
///
/// SCOPING IS BY TAG, NOT BY PLACEMENT. Rainbow-family effects are offered
/// only on cards that are rainbow-scoped (rainbow_scope.dart), and there they
/// are sent with `pal:0` so the firmware's hue wheel renders the full
/// spectrum. Every card here carries `metadata: {'rainbow': true}`; a card
/// added to this folder later is also scoped by its `parentId`, so the folder
/// can hold more than one card without further wiring.
///
/// Deliberately ONE card to start. What further rainbow cards should be (pastel
/// spectrum? two-tone pride flags? — those would be user-colour palettes, not
/// hue-wheel rainbows) is a content decision, not something to invent here.
class RainbowPalettes {
  RainbowPalettes._();

  static const String fullSpectrumId = 'rainbow_spectrum';

  /// The "Rainbow" tile shown inside Nature & Outdoors. No stock photo: the
  /// swatch is the spectrum itself. Sorts after Nature's seven existing
  /// sub-folders (sortOrder 0–6) so none of them moves.
  static const LibraryNode rainbowFolder = LibraryNode(
    id: NatureFolderIds.rainbow,
    name: 'Rainbow',
    description: 'Full-spectrum colourways',
    nodeType: LibraryNodeType.folder,
    parentId: LibraryCategoryIds.nature,
    sortOrder: 7,
    themeColors: kRainbowSpectrum,
    metadata: {'icon': 'looks', 'theme': 'rainbow'},
  );

  static List<LibraryNode> getRainbowPaletteNodes() {
    return const [
      LibraryNode(
        id: fullSpectrumId,
        name: 'Full Spectrum',
        description: 'Red through violet — the whole rainbow, moving',
        nodeType: LibraryNodeType.palette,
        parentId: NatureFolderIds.rainbow,
        sortOrder: 0,
        themeColors: kRainbowSpectrum,
        metadata: {
          'rainbow': true,
          // WLED fx 9 "Rainbow" (mode_rainbow_cycle): the hue wheel laid out
          // along the strip and scrolling. The colourway's natural effect.
          'suggestedEffectId': 9,
        },
      ),
    ];
  }
}
