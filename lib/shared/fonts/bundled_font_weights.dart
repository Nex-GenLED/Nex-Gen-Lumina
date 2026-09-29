import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Directory, declared under `assets:` in `pubspec.yaml`, that holds the static
/// font files shipped with the app.
///
/// `google_fonts` looks a font up in the asset manifest by file name
/// (`<Family>-<Weight>.ttf`) before it touches the network, so a file placed
/// here is used offline and is never fetched at runtime.
const String kBundledFontAssetDir = 'assets/google_fonts';

const Map<int, String> _weightFileNames = <int, String>{
  100: 'Thin',
  200: 'ExtraLight',
  300: 'Light',
  400: 'Regular',
  500: 'Medium',
  600: 'SemiBold',
  700: 'Bold',
  800: 'ExtraBold',
  900: 'Black',
};

/// One font family shipped with the app, and the weights shipped for it.
@immutable
class BundledFontFamily {
  const BundledFontFamily({
    required this.family,
    required this.displayName,
    required this.weights,
  });

  /// The family name `google_fonts` uses internally, e.g. `DMSans`. It is also
  /// the fallback family name on every style `google_fonts` returns, and the
  /// `family:` this font is declared under in `pubspec.yaml`.
  final String family;

  /// The family's published name, e.g. `DM Sans`.
  final String displayName;

  /// Every weight shipped for this family (upright only), as CSS weights.
  final List<int> weights;

  /// Asset key of the static file for [weight].
  String assetFor(int weight) {
    assert(weights.contains(weight));
    return '$kBundledFontAssetDir/$family-${_weightFileNames[weight]}.ttf';
  }

  /// Asset key of this family's licence text.
  String get licenseAsset => '$kBundledFontAssetDir/OFL-$family.txt';

  /// The family name `google_fonts` puts on a style requested at [weight].
  ///
  /// `google_fonts` registers every variant as its own single-face family
  /// (`DMSans_regular`, `Exo2_600`, ...) rather than as one family with many
  /// weights.
  String variantFamilyName(int weight) {
    return weight == 400 ? '${family}_regular' : '${family}_$weight';
  }
}

/// The families the app requests, with the weights shipped for each.
///
/// DM Sans and Exo 2 are the theme families: every `TextStyle` in the app that
/// names no family inherits one of them, so any weight used anywhere in the app
/// is requested of them. Montserrat and JetBrains Mono are only requested
/// directly. Weight 700 is shipped for every family because the platform Bold
/// Text setting turns every text run into a weight-700 request.
const List<BundledFontFamily> kBundledFontFamilies = <BundledFontFamily>[
  BundledFontFamily(
    family: 'DMSans',
    displayName: 'DM Sans',
    weights: <int>[400, 500, 600, 700, 800],
  ),
  BundledFontFamily(
    family: 'Exo2',
    displayName: 'Exo 2',
    weights: <int>[400, 500, 600, 700, 800, 900],
  ),
  BundledFontFamily(
    family: 'Montserrat',
    displayName: 'Montserrat',
    weights: <int>[400, 500, 600, 700, 800, 900],
  ),
  BundledFontFamily(
    family: 'JetBrainsMono',
    displayName: 'JetBrains Mono',
    weights: <int>[400, 700],
  ),
];

Future<void>? _registration;

/// Makes every shipped weight available under every family name the app's
/// text styles actually carry.
///
/// Packaging the font files is not enough on its own. A style that comes from
/// `google_fonts` names a single-face family such as `DMSans_regular`. When a
/// different weight is then asked of that style — by `copyWith(fontWeight:)`,
/// by a plain `TextStyle(fontWeight:)` that inherits the theme family, or by
/// the platform Bold Text setting, which merges weight 700 into every text
/// run — the engine has only that one face to draw with and synthesises the
/// weight by smearing it.
///
/// This registers the family's full set of shipped faces under each of those
/// single-face names, so the engine picks the real file for the weight asked
/// for. It does not change the family or the weight any widget requests.
///
/// Safe to call more than once; the work is done once. It never throws: a
/// face that fails to load is reported through [FlutterError.reportError] and
/// the rest are still registered.
Future<void> registerBundledFontWeights({AssetBundle? bundle}) {
  return _registration ??= _registerAll(bundle ?? rootBundle);
}

/// Forgets that registration has run, so the next call does the work again.
@visibleForTesting
void debugResetBundledFontRegistration() {
  _registration = null;
}

Future<void> _registerAll(AssetBundle bundle) async {
  for (final BundledFontFamily family in kBundledFontFamilies) {
    _registerLicense(family, bundle);

    final List<ByteData> faces = <ByteData>[];
    for (final int weight in family.weights) {
      try {
        faces.add(await bundle.load(family.assetFor(weight)));
      } catch (error, stack) {
        _report(error, stack, 'loading ${family.assetFor(weight)}');
      }
    }
    if (faces.isEmpty) {
      continue;
    }

    for (final int weight in family.weights) {
      final String name = family.variantFamilyName(weight);
      try {
        final FontLoader loader = FontLoader(name);
        for (final ByteData face in faces) {
          loader.addFont(Future<ByteData>.value(face));
        }
        await loader.load();
      } catch (error, stack) {
        _report(error, stack, 'registering $name');
      }
    }
  }
}

void _registerLicense(BundledFontFamily family, AssetBundle bundle) {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      <String>[family.displayName],
      await bundle.loadString(family.licenseAsset),
    );
  });
}

void _report(Object error, StackTrace stack, String doing) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'bundled fonts',
      context: ErrorDescription('while $doing'),
    ),
  );
}
