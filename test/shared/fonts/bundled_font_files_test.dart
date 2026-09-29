// Checks the font files that ship in the app bundle: that each one really is
// the weight its file name and its pubspec declaration say it is, that it is a
// static instance, that it is byte-for-byte the file Google Fonts publishes,
// and that the licence text ships next to it.
//
// Weight is read from the font's own OS/2 table, never inferred from the name.

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/shared/fonts/bundled_font_weights.dart';

/// SHA-256 of each shipped file. These are the digests the `google_fonts`
/// package itself expects for the file Google Fonts serves for that variant.
const Map<String, String> _publishedSha256 = <String, String>{
  'DMSans-Bold.ttf':
      '9909c4fcfbfe7b2c4a658b8d74eeb3ed38401a31cd4a3854546369c174f41440',
  'DMSans-ExtraBold.ttf':
      '403fb5b03e3e5b7a72e21c57e77deca1b7d36eae14cbc805b543d681b5921c60',
  'DMSans-Medium.ttf':
      'cd8be6a6d9a5579d829e3f4902d7d9acdaa01230bac60a024764c13afc6a049c',
  'DMSans-Regular.ttf':
      '2dbeb0e218984395ccb1b649dbe39bfecf9da420bf69fdc2da2860c2c9dc3324',
  'DMSans-SemiBold.ttf':
      'b0a9fe8b3a029cfaf00e31437c32a57e8adead3cade26ad1c6637a4908f4278e',
  'Exo2-Black.ttf':
      'e8d88186d114ab735ff45caf0fb77957afa7c62152ab56e712dad2f1156a4b16',
  'Exo2-Bold.ttf':
      'a1d998b767e12260d03971bf35a53ac86c15e84d7c7002132ae91be402be08d1',
  'Exo2-ExtraBold.ttf':
      '1cd11ffbb4fd893273d8103b9cad127659d3babf23290c7d784846d82e8e6838',
  'Exo2-Medium.ttf':
      '9569393e4fb27c674ccbe76dfdf79ae699d0e2a5b39da09f0c8e439a1546a4af',
  'Exo2-Regular.ttf':
      'd40384c64c9929b96a3908d20eb38e019d32a75810cfb3695d868eb6b103f38d',
  'Exo2-SemiBold.ttf':
      'd2709d298589f56f9bdc49e9d975b059356477484e3390524c11423d92e3c14a',
  'JetBrainsMono-Bold.ttf':
      'b43a7dfebfb8816fb3859f6a7932824f594e115538ccd3f1ebc0ffc231b0acab',
  'JetBrainsMono-Regular.ttf':
      'fc34426314d00825ccc768a0c4b1178fe704f04bd947882ef10c2b71b7e355e7',
  'Montserrat-Black.ttf':
      '0130a08a68975f07adfa07ca5b2e7aa2799af9b46d2b3b108fb90169b77c8d13',
  'Montserrat-Bold.ttf':
      'f7d4074869afb39d444728a57fe9d7dd18321cd8b7f94f014e8429c7a7b95c96',
  'Montserrat-ExtraBold.ttf':
      'fa9123659daabc277ebd7bcb2f89ab70ac25e0d6a4094689998885f3ad504a30',
  'Montserrat-Medium.ttf':
      '0640b607f11322748abad42219ea40d3c9d15736374ac53a8117a58dd7d0edb0',
  'Montserrat-Regular.ttf':
      'e3bb63f2cd246ff159b0841c2bd55d0914291a93487340cfa27574cc8d1861dd',
  'Montserrat-SemiBold.ttf':
      '7f24ab0c0148c4c2160552a4d8676977204aabee088a0f3fa71eb44250b89a8c',
};

class _FontFacts {
  _FontFacts(this.weightClass, this.isVariable, this.isItalic);
  final int weightClass;
  final bool isVariable;
  final bool isItalic;
}

_FontFacts _read(Uint8List bytes) {
  final ByteData data = ByteData.sublistView(bytes);
  final int tableCount = data.getUint16(4);
  final Map<String, int> offsets = <String, int>{};
  for (int i = 0; i < tableCount; i++) {
    final int record = 12 + 16 * i;
    final String tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    offsets[tag] = data.getUint32(record + 8);
  }
  final int os2 = offsets['OS/2']!;
  final int fsSelection = data.getUint16(os2 + 62);
  return _FontFacts(
    data.getUint16(os2 + 4),
    offsets.containsKey('fvar'),
    fsSelection & 0x01 != 0,
  );
}

void main() {
  final String pubspec = File('pubspec.yaml').readAsStringSync();

  for (final BundledFontFamily family in kBundledFontFamilies) {
    group(family.displayName, () {
      test('ships weight 700, for the platform Bold Text setting', () {
        expect(family.weights, contains(700));
      });

      test('ships its licence text', () {
        final File licence = File(family.licenseAsset);
        expect(licence.existsSync(), isTrue, reason: family.licenseAsset);
        expect(
          licence.readAsStringSync(),
          contains('SIL OPEN FONT LICENSE Version 1.1'),
        );
      });

      for (final int weight in family.weights) {
        final String asset = family.assetFor(weight);

        test('$asset is a static upright face of weight $weight', () {
          final File file = File(asset);
          expect(file.existsSync(), isTrue, reason: '$asset is missing');
          final _FontFacts facts = _read(file.readAsBytesSync());
          expect(facts.weightClass, weight, reason: 'OS/2 usWeightClass');
          expect(facts.isVariable, isFalse, reason: 'has an fvar table');
          expect(facts.isItalic, isFalse, reason: 'OS/2 fsSelection italic');
        });

        test('$asset is declared in pubspec.yaml at weight $weight', () {
          expect(
            pubspec,
            contains(RegExp(
              '- asset: ${RegExp.escape(asset)}\\s+weight: $weight\\b',
            )),
          );
        });
      }
    });
  }

  test('the font directory is declared as an asset directory', () {
    expect(pubspec, contains('    - $kBundledFontAssetDir/\n'));
  });

  test('every shipped file is byte-identical to the published file', () {
    final List<String> shipped = Directory(kBundledFontAssetDir)
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .where((String name) => name.endsWith('.ttf'))
        .toList()
      ..sort();
    expect(shipped, _publishedSha256.keys.toList()..sort());
    for (final String name in shipped) {
      final List<int> bytes =
          File('$kBundledFontAssetDir/$name').readAsBytesSync();
      expect(sha256.convert(bytes).toString(), _publishedSha256[name],
          reason: name);
    }
  });

  test('no shipped family is left out of the registry', () {
    final Set<String> expected = <String>{
      for (final BundledFontFamily family in kBundledFontFamilies)
        for (final int weight in family.weights)
          family.assetFor(weight).split('/').last,
    };
    final Set<String> shipped = Directory(kBundledFontAssetDir)
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .where((String name) => name.endsWith('.ttf'))
        .toSet();
    expect(shipped, expected);
  });
}
