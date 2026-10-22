// Store window item 6, group 3: consumer brand names out of display names,
// visible hints, and the AI examples the model could echo back (App Review
// 5.2). Ids are unchanged.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';

void main() {
  test('Barbie Pink → Hot Pink Glam (id bday_girl_barbie unchanged)', () async {
    final node = await PatternRepository().getNodeById('bday_girl_barbie');
    expect(node?.name, 'Hot Pink Glam');
  });

  test('the AI prompt examples name no brand', () {
    final src = File('lib/lumina_ai/lumina_ai_service.dart').readAsStringSync();
    for (final brand in const ['Coca-Cola', 'Starbucks', 'FedEx', 'Tiffany']) {
      expect(src, isNot(contains(brand)), reason: brand);
    }
  });

  test('the commercial brand-search hint names no brand', () {
    final src = File('lib/features/commercial/brand/brand_search_screen.dart')
        .readAsStringSync();
    expect(src, contains("hintText: 'Search brands (e.g. your business name)'"));
    expect(src, isNot(contains('State Farm')));
  });
}
