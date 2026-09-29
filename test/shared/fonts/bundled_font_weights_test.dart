// Proves that a weight asked of a google_fonts style is drawn with the real
// font file of that weight, not synthesised from another one.
//
// A face is identified by the pixels it draws for a fixed string. Advance
// width alone is not enough: every weight of a monospaced family is the same
// width.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/shared/fonts/bundled_font_weights.dart';

const String _sample = 'Hamburgefonstiv 0123456789';

double _width(String family, int weight) {
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: _sample,
      style: TextStyle(
        fontFamily: family,
        fontSize: 40,
        fontWeight: FontWeight.values[weight ~/ 100 - 1],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final double width = painter.width;
  painter.dispose();
  return width;
}

/// The pixels [family] draws for [_sample] when asked for [weight], as a
/// string that is equal only when every pixel is.
///
/// Must be called inside `tester.runAsync`.
Future<String> _pixels(String family, int weight) async {
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: _sample,
      style: TextStyle(
        fontFamily: family,
        fontSize: 40,
        fontWeight: FontWeight.values[weight ~/ 100 - 1],
        color: const Color(0xFFFFFFFF),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Offset(8, 8));
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    painter.width.ceil() + 16,
    painter.height.ceil() + 16,
  );
  final ByteData data = (await image.toByteData())!;
  final String result = '${image.width}x${image.height}:'
      '${Object.hashAll(data.buffer.asUint8List())}';
  image.dispose();
  picture.dispose();
  painter.dispose();
  return result;
}

ByteData _bytes(BundledFontFamily family, int weight) {
  return ByteData.sublistView(File(family.assetFor(weight)).readAsBytesSync());
}

/// Registers one file, alone, under its own family name and returns the name.
Future<String> _loadAlone(BundledFontFamily family, int weight) async {
  final String name = 'Alone_${family.family}_$weight';
  final FontLoader loader = FontLoader(name)
    ..addFont(Future<ByteData>.value(_bytes(family, weight)));
  await loader.load();
  return name;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final BundledFontFamily dmSans = kBundledFontFamilies
      .firstWhere((BundledFontFamily f) => f.family == 'DMSans');

  test('variant family names match the names google_fonts generates', () {
    expect(dmSans.variantFamilyName(400), GoogleFonts.dmSans().fontFamily);
    expect(
      dmSans.variantFamilyName(700),
      GoogleFonts.dmSans(fontWeight: FontWeight.w700).fontFamily,
    );
    final BundledFontFamily exo2 = kBundledFontFamilies
        .firstWhere((BundledFontFamily f) => f.family == 'Exo2');
    expect(
      exo2.variantFamilyName(600),
      GoogleFonts.exo2(fontWeight: FontWeight.w600).fontFamily,
    );
    for (final BundledFontFamily family in kBundledFontFamilies) {
      expect(
        GoogleFonts.getFont(family.displayName).fontFamilyFallback,
        <String>[family.family],
        reason: 'pubspec declares the fallback family as ${family.family}',
      );
    }
  });

  testWidgets('the premise: a lone regular face asked for bold is synthesised',
      (WidgetTester tester) async {
    await tester.runAsync<void>(() async {
      for (final BundledFontFamily family in kBundledFontFamilies) {
        final String regular = await _loadAlone(family, 400);
        final String bold = await _loadAlone(family, 700);
        final String realRegular = await _pixels(regular, 400);
        final String realBold = await _pixels(bold, 700);
        final String askedBold = await _pixels(regular, 700);

        expect(realRegular, isNot(realBold), reason: family.family);
        // With only the 400 file to hand, a request for 700 draws neither
        // the regular face as designed nor the real bold face.
        expect(askedBold, isNot(realBold), reason: family.family);
        expect(askedBold, isNot(realRegular), reason: family.family);
      }
    });
  });

  testWidgets('every shipped weight is real under every variant family name',
      (WidgetTester tester) async {
    await tester.runAsync<void>(() async {
      debugResetBundledFontRegistration();
      await registerBundledFontWeights();

      for (final BundledFontFamily family in kBundledFontFamilies) {
        final Map<int, String> real = <int, String>{
          for (final int weight in family.weights)
            weight: await _pixels(await _loadAlone(family, weight), weight),
        };
        expect(
          real.values.toSet(),
          hasLength(family.weights.length),
          reason: '${family.family}: each weight must draw differently, '
              'or pixels cannot tell the faces apart',
        );

        for (final int styledAs in family.weights) {
          final String name = family.variantFamilyName(styledAs);
          for (final int asked in family.weights) {
            expect(
              await _pixels(name, asked),
              real[asked],
              reason: '$name asked for weight $asked',
            );
          }
        }
      }
    });
  });

  testWidgets('Bold Text on a regular google_fonts style draws the real bold',
      (WidgetTester tester) async {
    late double realBold;
    late double realRegular;
    await tester.runAsync<void>(() async {
      debugResetBundledFontRegistration();
      await registerBundledFontWeights();
      realBold = _width(await _loadAlone(dmSans, 700), 700);
      realRegular = _width(await _loadAlone(dmSans, 400), 400);
    });

    Future<double> widthWithBoldText(bool boldText) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(boldText: boldText),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: Text(
                _sample,
                softWrap: false,
                style: TextStyle(
                  fontFamily: dmSans.variantFamilyName(400),
                  fontSize: 40,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      );
      return tester.renderObject<RenderBox>(find.text(_sample)).size.width;
    }

    expect(await widthWithBoldText(false), realRegular);
    expect(await widthWithBoldText(true), realBold);
  });

  testWidgets('a later single-face load by google_fonts does not undo it',
      (WidgetTester tester) async {
    await tester.runAsync<void>(() async {
      debugResetBundledFontRegistration();
      await registerBundledFontWeights();
      for (final BundledFontFamily family in kBundledFontFamilies) {
        final String realBold =
            await _pixels(await _loadAlone(family, 700), 700);

        // What google_fonts does the first time a style is built.
        final FontLoader late = FontLoader(family.variantFamilyName(400))
          ..addFont(Future<ByteData>.value(_bytes(family, 400)));
        await late.load();

        expect(
          await _pixels(family.variantFamilyName(400), 700),
          realBold,
          reason: family.family,
        );
      }
    });
  });

  testWidgets('google_fonts finds every shipped weight without the network',
      (WidgetTester tester) async {
    final bool before = GoogleFonts.config.allowRuntimeFetching;
    addTearDown(() => GoogleFonts.config.allowRuntimeFetching = before);
    // With fetching off, google_fonts throws for any font it cannot find in
    // the asset bundle.
    GoogleFonts.config.allowRuntimeFetching = false;

    await tester.runAsync<void>(() async {
      for (final BundledFontFamily family in kBundledFontFamilies) {
        for (final int weight in family.weights) {
          GoogleFonts.getFont(
            family.displayName,
            fontWeight: FontWeight.values[weight ~/ 100 - 1],
          );
        }
      }
      await GoogleFonts.pendingFonts();
    });
  });

  testWidgets('a missing file is reported and does not stop the rest',
      (WidgetTester tester) async {
    final List<FlutterErrorDetails> reported = <FlutterErrorDetails>[];
    final FlutterExceptionHandler? previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      await tester.runAsync<void>(() async {
        debugResetBundledFontRegistration();
        await registerBundledFontWeights(
          bundle: _MissingOne(dmSans.assetFor(500)),
        );
      });
    } finally {
      FlutterError.onError = previous;
      debugResetBundledFontRegistration();
    }

    expect(reported, hasLength(1));
    expect(reported.single.library, 'bundled fonts');
    expect(reported.single.context.toString(), contains('DMSans-Medium.ttf'));
  });

  testWidgets('registration runs once however often it is called',
      (WidgetTester tester) async {
    debugResetBundledFontRegistration();
    final _Counting bundle = _Counting();
    await tester.runAsync<void>(() async {
      await registerBundledFontWeights(bundle: bundle);
      final int afterFirst = bundle.loads;
      await registerBundledFontWeights(bundle: bundle);
      expect(bundle.loads, afterFirst);
      expect(afterFirst, greaterThan(0));
    });
    debugResetBundledFontRegistration();
  });
}

class _Counting extends CachingAssetBundle {
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    loads++;
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}

class _MissingOne extends CachingAssetBundle {
  _MissingOne(this.missing);
  final String missing;

  @override
  Future<ByteData> load(String key) async {
    if (key == missing) {
      throw FlutterError('Unable to load asset: "$key".');
    }
    return ByteData.sublistView(File(key).readAsBytesSync());
  }
}
