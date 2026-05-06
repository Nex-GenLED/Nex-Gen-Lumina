import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/models/commercial/brand_custom_design.dart';
import 'package:nexgen_command/models/commercial/brand_library_entry.dart';

void main() {
  group('BrandLibraryEntry customDesigns', () {
    test('defaults to empty list when field is absent (legacy docs)', () {
      final entry = BrandLibraryEntry.fromJson({
        'brand_id': 'mcdonalds',
        'company_name': "McDonald's",
        'search_terms': ['mcdonalds'],
        'industry': 'restaurant',
        'colors': [],
        'signature': {},
        'verified_by': 'nex-gen-manual',
      });
      expect(entry.customDesigns, isEmpty);
    });

    test('round-trips a custom design through fromJson + toJson', () {
      final source = {
        'brand_id': 'diamond-family-blue',
        'company_name': 'Diamond Family Blue',
        'search_terms': ['diamond family blue'],
        'industry': 'retail',
        'colors': [],
        'signature': {},
        'verified_by': 'nex-gen-manual',
        'custom_designs': [
          {
            'design_id': 'shimmer',
            'display_name': 'Shimmer',
            'wled_effect_name': 'Twinkle',
            'wled_effect_id': 50,
            'effect_params': {'sx': 96, 'ix': 200},
            'description': 'Subtle jewelry-like glimmer',
            'mood': 'elegant',
          },
        ],
      };
      final entry = BrandLibraryEntry.fromJson(source);
      expect(entry.customDesigns.length, 1);
      final design = entry.customDesigns.first;
      expect(design.designId, 'shimmer');
      expect(design.displayName, 'Shimmer');
      expect(design.wledEffectName, 'Twinkle');
      expect(design.wledEffectId, 50);
      expect(design.effectParams['sx'], 96);
      expect(design.effectParams['ix'], 200);
      expect(design.mood, 'elegant');
      expect(design.description, 'Subtle jewelry-like glimmer');

      final json = entry.toJson();
      expect(json['custom_designs'], isA<List>());
      final list = json['custom_designs'] as List;
      expect(list.length, 1);
      final out = list.first as Map<String, dynamic>;
      expect(out['design_id'], 'shimmer');
      expect(out['wled_effect_id'], 50);
      expect(out['mood'], 'elegant');
    });

    test('skips non-map entries inside custom_designs', () {
      final entry = BrandLibraryEntry.fromJson({
        'brand_id': 'x',
        'company_name': 'X',
        'search_terms': ['x'],
        'industry': 'retail',
        'colors': [],
        'signature': {},
        'verified_by': 'nex-gen-manual',
        'custom_designs': [
          'not a map',
          42,
          {
            'design_id': 'wave',
            'display_name': 'Wave',
            'wled_effect_name': 'Running',
            'wled_effect_id': 15,
          },
        ],
      });
      expect(entry.customDesigns.length, 1);
      expect(entry.customDesigns.first.designId, 'wave');
    });
  });

  group('BrandCustomDesign serialization', () {
    test('omits description when null on toJson', () {
      const design = BrandCustomDesign(
        designId: 'pulse',
        displayName: 'Pulse',
        wledEffectName: 'Breathe',
        wledEffectId: 2,
      );
      final json = design.toJson();
      expect(json.containsKey('description'), isFalse);
      expect(json['mood'], 'professional');
      expect(json['effect_params'], isEmpty);
    });

    test('preserves arbitrary effectParams keys for forward compat', () {
      const design = BrandCustomDesign(
        designId: 'future',
        displayName: 'Future',
        wledEffectName: 'Custom',
        wledEffectId: 999,
        effectParams: {'sx': 80, 'ix': 220, 'pal': 5, 'unknownKey': 'x'},
      );
      final round = BrandCustomDesign.fromJson(design.toJson());
      expect(round.effectParams['unknownKey'], 'x');
      expect(round.effectParams['pal'], 5);
    });
  });
}
