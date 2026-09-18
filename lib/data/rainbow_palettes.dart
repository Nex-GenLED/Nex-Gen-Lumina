import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/rainbow_scope.dart';

/// The Rainbow root's cards — genuine rainbow colourways.
///
/// Its own root (`cat_rainbow`), distinct from Nature & Outdoors, because a
/// rainbow is a colourway, not an environment. Rainbow-family effects are
/// offered ONLY on these cards (rainbow_scope.dart), and here they are sent
/// with `pal:0` so the firmware's hue wheel renders the full spectrum.
///
/// Deliberately ONE card to start. What further rainbow cards should be (pastel
/// spectrum? two-tone pride flags? — those would be user-colour palettes, not
/// hue-wheel rainbows) is a content decision, not something to invent here.
class RainbowPalettes {
  RainbowPalettes._();

  static const String fullSpectrumId = 'rainbow_spectrum';

  static List<LibraryNode> getRainbowPaletteNodes() {
    return const [
      LibraryNode(
        id: fullSpectrumId,
        name: 'Full Spectrum',
        description: 'Red through violet — the whole rainbow, moving',
        nodeType: LibraryNodeType.palette,
        parentId: LibraryCategoryIds.rainbow,
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
