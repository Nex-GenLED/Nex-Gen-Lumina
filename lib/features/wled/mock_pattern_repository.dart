import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:flutter/material.dart';

/// In-memory mock data source for the Pattern Library.
/// Provides a consistent set of categories and items for demos and tests.
class MockPatternRepository {
  MockPatternRepository();

  // ================= Procedural Generator Templates =================
  // Uses the curated effect IDs from WledEffectsCatalog for pattern generation.
  static List<int> get kMotionTemplateEffectIds => WledEffectsCatalog.curatedEffectIds;

  // ================= Vibe Grouping =================
  // Tag effect IDs into "vibe" filters to organize the generated grid.
  // Elegant: solids, fades, breaths, ambient flows, and soft sparkles
  static const Set<int> kElegantFxIds = {
    0,   // Solid
    2,   // Breathe
    12,  // Fade
    38,  // Aurora
    43,  // Rain
    56,  // Tri Fade
    67,  // Colorwaves
    75,  // Lake
    88,  // Candle
    97,  // Plasma
    101, // Pacifica
    102, // Candle Multi
    104, // Sunrise
    105, // Phased
    110, // Flow
    112, // Dancing Shadows
    115, // Blends
  };

  // Motion: chases, wipes, scanners, scanlines
  static const Set<int> kMotionFxIds = {
    3, 4, 6,        // Wipe, Wipe Random, Sweep
    10, 11,         // Scan, Scan Dual
    13, 14, 15, 16, // Theater, Theater Rainbow, Running, Saw
    27, 28, 29, 30, 31, 32, 37, // Android, Chase variants
    40, 41,         // Scanner, Lighthouse
    50, 52, 54,     // Two Dots, Running Dual, Chase 3
    55,             // Tri Wipe
    58, 60,         // ICU, Scanner Dual
    59,             // Multi Comet
    64,             // Juggle
    76, 77,         // Meteor, Meteor Smooth
    78,             // Railway
    92, 93, 94,     // Sinelon variants
    111,            // Chunchun
  };

  // Energy: strobes, fireworks, sparkles
  static const Set<int> kEnergyFxIds = {
    1,              // Blink
    17, 20, 21, 22, // Twinkle, Sparkle variants
    23, 24, 25,     // Strobe variants
    42,             // Fireworks
    49, 51,         // Fairy, Fairytwinkle
    57,             // Lightning
    74,             // Colortwinkles
    79, 99,         // Ripple, Ripple Rainbow
    80, 81,         // Twinklefox, Twinklecat
    87,             // Glitter
    89, 90,         // Fireworks Starburst, Fireworks 1D
    91, 95,         // Bouncing Balls, Popcorn
    103, 106,       // Solid Glitter, Twinkleup
  };

  /// Returns the vibe filter label for a given effect id.
  static String vibeForFx(int fxId) {
    if (kElegantFxIds.contains(fxId)) return 'Elegant';
    if (kEnergyFxIds.contains(fxId)) return 'Energy';
    // Default any remaining curated ids to Motion
    return 'Motion';
  }

  /// Helper to extract the effect id from a PatternItem payload.
  static int? effectIdFromPayload(Map<String, dynamic> payload) {
    try {
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final first = seg.first;
        if (first is Map && first['fx'] is int) return first['fx'] as int;
      }
    } catch (_) {}
    return null;
  }

  /// Get effect name from the centralized catalog.
  static String _effectName(int id) => WledEffectsCatalog.getName(id);

  static List<List<int>> _colorsToWledCol(List<Color> colors) {
    // WLED col expects up to 3 color slots; keep first 3 theme colors
    // Force W=0 to keep saturated colors accurate - WLED handles GRB conversion
    return colors.take(3).map((c) => rgbToRgbw(c.red, c.green, c.blue, forceZeroWhite: true)).toList(growable: false);
  }

  /// Generate 50 PatternItems for a given sub-category using its theme palette.
  Future<List<PatternItem>> generatePatternsForTheme(SubCategory subCat) async {
    final List<List<int>> col = _colorsToWledCol(subCat.themeColors);
    // Determine a backdrop image based on parent category if possible
    final catImage = _categories.firstWhere((c) => c.id == subCat.parentCategoryId, orElse: () => _categories.first).imageUrl;

    final List<PatternItem> items = [];
    for (final fxId in kMotionTemplateEffectIds) {
      final effectName = _effectName(fxId);
      final name = '${subCat.name} - $effectName';
      final payload = {
        'seg': [
          {
            'fx': fxId,
            'col': col,
            'sx': 128,
            'ix': 128,
          }
        ]
      };
      items.add(PatternItem(
        id: 'gen_${subCat.id}_fx_$fxId',
        name: name,
        imageUrl: catImage,
        categoryId: subCat.parentCategoryId,
        wledPayload: payload,
      ));
    }
    return items;
  }

  // Premium Categories
  static const PatternCategory catArchitectural = PatternCategory(
    id: 'cat_arch',
    name: 'Architectural & White',
    // Warm white lit home exterior
    imageUrl: 'https://images.unsplash.com/photo-1600585154154-8c857b74f2ab',
  );

  static const PatternCategory catHoliday = PatternCategory(
    id: 'cat_holiday',
    name: 'Holidays',
    // Christmas/Holiday lights
    imageUrl: 'https://images.unsplash.com/photo-1482517967863-00e15c9b44be',
  );

  static const PatternCategory catSports = PatternCategory(
    id: 'cat_sports',
    name: 'Game Day',
    // Stadium / team colors
    imageUrl: 'https://images.unsplash.com/photo-1518600506278-4e8ef466b810',
  );

  static const PatternCategory catSeasonal = PatternCategory(
    id: 'cat_season',
    name: 'Seasonal',
    // Autumn leaves / Spring flowers
    imageUrl: 'https://images.unsplash.com/photo-1477587458883-47145ed94245',
  );

  static const PatternCategory catParty = PatternCategory(
    id: 'cat_party',
    name: 'Parties & Events',
    // Colorful balloons / confetti
    imageUrl: 'https://images.unsplash.com/photo-1544491843-0ce2884635f3',
  );

  static const PatternCategory catSecurity = PatternCategory(
    id: 'cat_security',
    name: 'Security & Alert',
    // Bright white floodlights
    imageUrl: 'https://images.unsplash.com/photo-1579403124614-197f69d8187b',
  );

  static const List<PatternCategory> _categories = [
    catArchitectural,
    catHoliday,
    catSports,
    catSeasonal,
    catParty,
    catSecurity,
  ];

  // ================= Sub-Categories (3-tier navigation) =================
  static final List<SubCategory> _subCategories = [
    // Holidays
    SubCategory(
      id: 'sub_xmas',
      name: 'Christmas',
      themeColors: const [Color(0xFFFF0000), Color(0xFF00FF00), Colors.white], // Pure red & green
      parentCategoryId: catHoliday.id,
    ),
    SubCategory(
      id: 'sub_halloween',
      name: 'Halloween',
      themeColors: const [Color(0xFFFF8C00), Color(0xFF800080), Colors.black], // Pure orange, purple
      parentCategoryId: catHoliday.id,
    ),
    SubCategory(
      id: 'sub_july4',
      name: '4th of July',
      themeColors: const [Color(0xFFFF0000), Colors.white, Color(0xFF0000FF)], // Pure red, white, blue
      parentCategoryId: catHoliday.id,
    ),
    SubCategory(
      id: 'sub_easter',
      name: 'Easter',
      themeColors: const [Color(0xFFFFB6C1), Color(0xFFADD8E6), Color(0xFFBFFF00)], // Light pink, light blue, lime
      parentCategoryId: catHoliday.id,
    ),
    SubCategory(
      id: 'sub_valentines',
      name: "Valentine's",
      themeColors: const [Color(0xFFFF0000), Color(0xFFFF69B4), Colors.white], // Pure red, hot pink
      parentCategoryId: catHoliday.id,
    ),
    SubCategory(
      id: 'sub_st_patricks',
      name: "St. Patrick's",
      themeColors: const [Color(0xFF00FF00), Color(0xFF90EE90), Colors.white], // Pure green, light green
      parentCategoryId: catHoliday.id,
    ),

    // Game Day - Using pure RGB colors for accurate LED display
    SubCategory(
      id: 'sub_kc',
      name: 'Kansas City',
      themeColors: const [Color(0xFFFF0000), Color(0xFFFFD700)], // Pure red, gold
      parentCategoryId: catSports.id,
    ),
    SubCategory(
      id: 'sub_seattle',
      name: 'Seattle',
      themeColors: const [Color(0xFF0000FF), Color(0xFF00FF00)], // Pure blue, pure green
      parentCategoryId: catSports.id,
    ),
    SubCategory(
      id: 'sub_rb_generic',
      name: 'General Red/Blue',
      themeColors: const [Color(0xFFFF0000), Color(0xFF0000FF), Colors.white], // Pure red, pure blue
      parentCategoryId: catSports.id,
    ),
    SubCategory(
      id: 'sub_gy_generic',
      name: 'General Green/Yellow',
      themeColors: const [Color(0xFF00FF00), Color(0xFFFFFF00)], // Pure green, pure yellow
      parentCategoryId: catSports.id,
    ),
    SubCategory(
      id: 'sub_ob_generic',
      name: 'General Orange/Blue',
      themeColors: const [Color(0xFFFF8C00), Color(0xFF0000FF)], // Pure orange, pure blue
      parentCategoryId: catSports.id,
    ),

    // Seasonal - Using pure RGB colors for accurate LED display
    SubCategory(
      id: 'sub_spring',
      name: 'Spring Pastels',
      themeColors: const [Color(0xFFFFB6C1), Color(0xFFDDA0DD), Color(0xFF90EE90)], // Light pink, plum, light green
      parentCategoryId: catSeasonal.id,
    ),
    SubCategory(
      id: 'sub_summer',
      name: 'Summer Vibrance',
      themeColors: const [Color(0xFF00FFFF), Color(0xFFFF8C00), Color(0xFF32CD32)], // Cyan, orange, lime green
      parentCategoryId: catSeasonal.id,
    ),
    SubCategory(
      id: 'sub_autumn',
      name: 'Autumn Harvest',
      themeColors: const [Color(0xFFFF8C00), Color(0xFF8B4513), Color(0xFFFF0000)], // Orange, saddle brown, red
      parentCategoryId: catSeasonal.id,
    ),
    SubCategory(
      id: 'sub_winter',
      name: 'Winter Frost',
      themeColors: const [Color(0xFF708090), Color(0xFFADD8E6), Colors.white], // Slate gray, light blue, white
      parentCategoryId: catSeasonal.id,
    ),

    // Architectural - Warm tones use specific hex values for LED accuracy
    SubCategory(
      id: 'sub_warm_whites',
      name: 'Warm Whites',
      themeColors: const [Color(0xFFFFB347), Color(0xFFFF8C00), Colors.white], // Warm amber, orange, white
      parentCategoryId: catArchitectural.id,
    ),
    SubCategory(
      id: 'sub_cool_whites',
      name: 'Cool Whites',
      themeColors: const [Color(0xFF708090), Colors.white], // Slate gray, white
      parentCategoryId: catArchitectural.id,
    ),
    SubCategory(
      id: 'sub_gold_accents',
      name: 'Gold Accents',
      themeColors: const [Color(0xFFFFD700), Color(0xFFFFFF00), Colors.white], // Gold, yellow, white
      parentCategoryId: catArchitectural.id,
    ),
    SubCategory(
      id: 'sub_security_floods',
      name: 'Security Floods',
      themeColors: const [Colors.white],
      parentCategoryId: catArchitectural.id,
    ),

    // Party - Using pure RGB colors for accurate LED display
    SubCategory(
      id: 'sub_birthday',
      name: 'Birthday Brights',
      themeColors: const [Color(0xFF00FFFF), Color(0xFFFF69B4), Color(0xFFFFFF00)], // Cyan, hot pink, yellow
      parentCategoryId: catParty.id,
    ),
    SubCategory(
      id: 'sub_elegant_dinner',
      name: 'Elegant Dinner',
      themeColors: const [Color(0xFFFFB347), Color(0xFF8B4513), Colors.white], // Amber, saddle brown, white
      parentCategoryId: catParty.id,
    ),
    SubCategory(
      id: 'sub_rave',
      name: 'Rave / Strobe',
      themeColors: const [Color(0xFF800080), Color(0xFF00FFFF), Color(0xFFFF69B4)], // Purple, cyan, hot pink
      parentCategoryId: catParty.id,
    ),
    SubCategory(
      id: 'sub_baby_shower',
      name: 'Baby Shower',
      themeColors: const [Color(0xFFADD8E6), Color(0xFFFFB6C1), Colors.white], // Light blue, light pink, white
      parentCategoryId: catParty.id,
    ),
  ];

  // Holiday items
  static final List<PatternItem> _holidayItems = [
    PatternItem(
      id: 'pat_candy_cane_chase',
      name: 'Candy Cane Chase',
      imageUrl: 'https://images.unsplash.com/photo-1543589077-47d81606c1bf',
      categoryId: catHoliday.id,
      wledPayload: const {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'fx': 12, // Chase
            'pal': 3, // Red/White
            'sx': 180,
            'ix': 200
          }
        ]
      },
    ),
    PatternItem(
      id: 'pat_july4_sparkle',
      name: 'July 4th Sparkle',
      imageUrl: 'https://images.unsplash.com/photo-1475724017904-b712052c192a',
      categoryId: catHoliday.id,
      wledPayload: const {
        'on': true,
        'bri': 230,
        'seg': [
          {
            'id': 0,
            'fx': 120, // Sparkle
            'pal': 6, // Red/White/Blue
            'sx': 170,
            'ix': 180
          }
        ]
      },
    ),
    PatternItem(
      id: 'pat_spooky_halloween',
      name: 'Spooky Halloween',
      imageUrl: 'https://images.unsplash.com/photo-1509557965875-b88c97052f0e',
      categoryId: catHoliday.id,
      wledPayload: const {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'fx': 76, // Lightning
            'pal': 5, // Purple/Orange
            'sx': 210,
            'ix': 200
          }
        ]
      },
    ),
    PatternItem(
      id: 'pat_easter_pastels',
      name: 'Easter Pastels',
      imageUrl: 'https://images.unsplash.com/photo-1522938974444-f12497b69347',
      categoryId: catHoliday.id,
      wledPayload: const {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'id': 0,
            'fx': 9, // Color Waves
            'pal': 12, // Pastel-like
            'sx': 140,
            'ix': 160
          }
        ]
      },
    ),
  ];

  // Index all items
  static final List<PatternItem> _items = [
    ..._holidayItems,
  ];

  Future<List<PatternCategory>> getCategories() async {
    debugPrint('MockPatternRepository.getCategories');
    return _categories;
  }

  Future<List<PatternItem>> getItemsByCategory(String categoryId) async {
    debugPrint('MockPatternRepository.getItemsByCategory($categoryId)');
    return _items.where((e) => e.categoryId == categoryId).toList(growable: false);
  }

  Future<List<PatternItem>> getAllItems() async {
    debugPrint('MockPatternRepository.getAllItems');
    return _items;
  }

  Future<PatternItem?> getItem(String id) async {
    debugPrint('MockPatternRepository.getItem($id)');
    try {
      return _items.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  // ================= Sub-Category Queries =================
  Future<List<SubCategory>> getSubCategoriesByCategory(String categoryId) async {
    debugPrint('MockPatternRepository.getSubCategoriesByCategory($categoryId)');
    return _subCategories.where((e) => e.parentCategoryId == categoryId).toList(growable: false);
  }

  Future<SubCategory?> getSubCategoryById(String subCategoryId) async {
    debugPrint('MockPatternRepository.getSubCategoryById($subCategoryId)');
    try {
      return _subCategories.firstWhere((e) => e.id == subCategoryId);
    } catch (_) {
      return null;
    }
  }
}
