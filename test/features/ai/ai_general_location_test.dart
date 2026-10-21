// Store window (c): Lumina AI gets city and state, never the street address.
// The profile keeps the full address; only what goes to the model changes.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/ai/ai_general_location.dart';

void main() {
  const cases = {
    '123 Main St, Kansas City, MO 64105': 'Kansas City, MO',
    '123 Main St, Kansas City, MO 64105, USA': 'Kansas City, MO',
    '123 Main St\nApt 4\nKansas City, MO 64105': 'Kansas City, MO',
    'One Main Street, Springfield, MO': 'Springfield, MO',
    'PO Box 12, Springfield, IL 62701': 'Springfield, IL',
    'Main Street, Springfield': 'Springfield',
    'Kansas City, MO': 'Kansas City, MO',
    'Kansas City': 'Kansas City',
    'Kansas City, MO 64105-1234': 'Kansas City, MO',
    // Nothing city-like survives, so say nothing.
    '123 Main St Kansas City MO 64105': kUnknownLocation,
    '64105': kUnknownLocation,
    '   ': kUnknownLocation,
  };

  for (final e in cases.entries) {
    test('"${e.key.replaceAll('\n', r'\n')}" → "${e.value}"', () {
      expect(generalLocationForAi(e.key), e.value);
    });
  }

  test('null → Unknown', () {
    expect(generalLocationForAi(null), kUnknownLocation);
  });

  test('never a house number or ZIP in the output', () {
    for (final raw in cases.keys) {
      final out = generalLocationForAi(raw);
      expect(out, isNot(matches(RegExp(r'\d'))), reason: raw);
    }
  });
}
