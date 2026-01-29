import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';

/// Named color palettes for all holidays.
/// Each holiday has 10+ themed color combinations.
class HolidayPalettes {
  // ==================== CHRISTMAS ====================
  static const List<NamedPalette> christmas = [
    NamedPalette(
      id: 'xmas_classic',
      name: 'Classic Christmas',
      description: 'Traditional red, green, and white',
      colors: [Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFFFFFFFF)],
      suggestedEffects: [12, 41, 43, 0], // Theater Chase, Running, Twinkle, Solid
    ),
    NamedPalette(
      id: 'xmas_candycane',
      name: 'Candy Cane',
      description: 'Red and white stripes',
      colors: [Color(0xFFFF0000), Color(0xFFFFFFFF)],
      suggestedEffects: [12, 41, 0], // Theater Chase, Running, Solid
    ),
    NamedPalette(
      id: 'xmas_grinch',
      name: 'The Grinch',
      description: 'Shades of green with a hint of red',
      colors: [Color(0xFF00FF00), Color(0xFF228B22), Color(0xFFFF0000)],
      suggestedEffects: [2, 41, 0], // Breathe, Running, Solid
    ),
    NamedPalette(
      id: 'xmas_frosty',
      name: 'Frosty the Snowman',
      description: 'Icy blue and white winter tones',
      colors: [Color(0xFF87CEEB), Color(0xFFFFFFFF), Color(0xFFADD8E6)],
      suggestedEffects: [43, 2, 0], // Twinkle, Breathe, Solid
    ),
    NamedPalette(
      id: 'xmas_santa',
      name: 'Santa Claus',
      description: 'Santa red with white and black accents',
      colors: [Color(0xFFFF0000), Color(0xFFFFFFFF), Color(0xFF000000)],
      suggestedEffects: [12, 0], // Theater Chase, Solid
    ),
    NamedPalette(
      id: 'xmas_nutcracker',
      name: 'Nutcracker',
      description: 'Royal red and gold',
      colors: [Color(0xFFDC143C), Color(0xFFFFD700), Color(0xFF000000)],
      suggestedEffects: [12, 41, 0], // Theater Chase, Running, Solid
    ),
    NamedPalette(
      id: 'xmas_winterwonderland',
      name: 'Winter Wonderland',
      description: 'Silver, blue, and white snow',
      colors: [Color(0xFFC0C0C0), Color(0xFF4169E1), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 2, 0], // Twinkle, Breathe, Solid
    ),
    NamedPalette(
      id: 'xmas_northpole',
      name: 'North Pole',
      description: 'Green, red, and gold festive',
      colors: [Color(0xFF00FF00), Color(0xFFFF0000), Color(0xFFFFD700)],
      suggestedEffects: [12, 43, 0], // Theater Chase, Twinkle, Solid
    ),
    NamedPalette(
      id: 'xmas_goldbells',
      name: 'Gold Bells',
      description: 'Warm gold and cream tones',
      colors: [Color(0xFFFFD700), Color(0xFFFFFDD0), Color(0xFFDAA520)],
      suggestedEffects: [2, 43, 0], // Breathe, Twinkle, Solid
    ),
    NamedPalette(
      id: 'xmas_silvertinsel',
      name: 'Silver Tinsel',
      description: 'Sparkling silver and white',
      colors: [Color(0xFFC0C0C0), Color(0xFFFFFFFF), Color(0xFFE8E8E8)],
      suggestedEffects: [43, 87, 0], // Twinkle, Glitter, Solid
    ),
    NamedPalette(
      id: 'xmas_rudolph',
      name: 'Rudolph',
      description: 'Red nose with brown and gold',
      colors: [Color(0xFFFF0000), Color(0xFF8B4513), Color(0xFFFFD700)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'xmas_snowflake',
      name: 'Snowflake',
      description: 'Pure white with ice blue',
      colors: [Color(0xFFFFFFFF), Color(0xFFB0E0E6)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
  ];

  // ==================== HALLOWEEN ====================
  static const List<NamedPalette> halloween = [
    NamedPalette(
      id: 'halloween_classic',
      name: 'Classic Halloween',
      description: 'Orange and black spooky',
      colors: [Color(0xFFFF8C00), Color(0xFF000000)],
      suggestedEffects: [43, 57, 0], // Twinkle, Lightning, Solid
    ),
    NamedPalette(
      id: 'halloween_witchbrew',
      name: 'Witch\'s Brew',
      description: 'Purple and green cauldron',
      colors: [Color(0xFF800080), Color(0xFF00FF00), Color(0xFF000000)],
      suggestedEffects: [2, 43, 0], // Breathe, Twinkle, Solid
    ),
    NamedPalette(
      id: 'halloween_pumpkinpatch',
      name: 'Pumpkin Patch',
      description: 'Orange pumpkin glow',
      colors: [Color(0xFFFF8C00), Color(0xFFFF6600), Color(0xFFFFD700)],
      suggestedEffects: [2, 101, 0], // Breathe, Candle, Solid
    ),
    NamedPalette(
      id: 'halloween_hauntedhouse',
      name: 'Haunted House',
      description: 'Eerie purple and orange',
      colors: [Color(0xFF800080), Color(0xFFFF8C00), Color(0xFF000000)],
      suggestedEffects: [57, 43, 0], // Lightning, Twinkle, Solid
    ),
    NamedPalette(
      id: 'halloween_skeleton',
      name: 'Skeleton',
      description: 'White bones on black',
      colors: [Color(0xFFFFFFFF), Color(0xFF000000)],
      suggestedEffects: [1, 43, 0], // Blink, Twinkle, Solid
    ),
    NamedPalette(
      id: 'halloween_vampire',
      name: 'Vampire',
      description: 'Blood red and black',
      colors: [Color(0xFF8B0000), Color(0xFF000000), Color(0xFFFF0000)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'halloween_ghost',
      name: 'Ghost',
      description: 'Pale white with purple',
      colors: [Color(0xFFFFFFFF), Color(0xFFE6E6FA), Color(0xFF9370DB)],
      suggestedEffects: [2, 43, 0], // Breathe, Twinkle, Solid
    ),
    NamedPalette(
      id: 'halloween_franken',
      name: 'Frankenstein',
      description: 'Monster green and black',
      colors: [Color(0xFF00FF00), Color(0xFF000000), Color(0xFFADFF2F)],
      suggestedEffects: [57, 1, 0], // Lightning, Blink, Solid
    ),
    NamedPalette(
      id: 'halloween_candy',
      name: 'Candy Corn',
      description: 'Yellow, orange, and white layers',
      colors: [Color(0xFFFFFF00), Color(0xFFFF8C00), Color(0xFFFFFFFF)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'halloween_blackcat',
      name: 'Black Cat',
      description: 'Black with yellow eyes',
      colors: [Color(0xFF000000), Color(0xFFFFFF00)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'halloween_spiderweb',
      name: 'Spider Web',
      description: 'Silver web on purple',
      colors: [Color(0xFFC0C0C0), Color(0xFF800080), Color(0xFF000000)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
  ];

  // ==================== 4TH OF JULY ====================
  static const List<NamedPalette> july4th = [
    NamedPalette(
      id: 'july4_classic',
      name: 'Classic Patriotic',
      description: 'Red, white, and blue',
      colors: [Color(0xFFFF0000), Color(0xFFFFFFFF), Color(0xFF0000FF)],
      suggestedEffects: [52, 12, 43, 0], // Fireworks, Theater Chase, Twinkle, Solid
    ),
    NamedPalette(
      id: 'july4_fireworks',
      name: 'Fireworks',
      description: 'Explosive patriotic bursts',
      colors: [Color(0xFFFF0000), Color(0xFFFFFFFF), Color(0xFF0000FF)],
      suggestedEffects: [52, 66, 0], // Fireworks, Fireworks, Solid
    ),
    NamedPalette(
      id: 'july4_oldglory',
      name: 'Old Glory',
      description: 'Deep flag colors',
      colors: [Color(0xFFBF0A30), Color(0xFFFFFFFF), Color(0xFF002868)],
      suggestedEffects: [12, 41, 0], // Theater Chase, Running, Solid
    ),
    NamedPalette(
      id: 'july4_sparkler',
      name: 'Sparkler',
      description: 'White sparkle with color accents',
      colors: [Color(0xFFFFFFFF), Color(0xFFFF0000), Color(0xFF0000FF)],
      suggestedEffects: [43, 87, 0], // Twinkle, Glitter, Solid
    ),
    NamedPalette(
      id: 'july4_stripes',
      name: 'Stars and Stripes',
      description: 'Alternating red and white',
      colors: [Color(0xFFFF0000), Color(0xFFFFFFFF)],
      suggestedEffects: [41, 12, 0], // Running, Theater Chase, Solid
    ),
    NamedPalette(
      id: 'july4_bluewave',
      name: 'Blue Wave',
      description: 'Blue with white crests',
      colors: [Color(0xFF0000FF), Color(0xFF4169E1), Color(0xFFFFFFFF)],
      suggestedEffects: [41, 2, 0], // Running, Breathe, Solid
    ),
    NamedPalette(
      id: 'july4_liberty',
      name: 'Liberty',
      description: 'Copper green with gold',
      colors: [Color(0xFF4A9B7F), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'july4_bbq',
      name: 'BBQ Party',
      description: 'Warm patriotic glow',
      colors: [Color(0xFFFF4500), Color(0xFFFFD700), Color(0xFFFF6347)],
      suggestedEffects: [101, 0], // Candle, Solid
    ),
    NamedPalette(
      id: 'july4_stars',
      name: 'Starry Night',
      description: 'Blue sky with white stars',
      colors: [Color(0xFF002868), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'july4_parade',
      name: 'Parade',
      description: 'Bright and bold tricolor',
      colors: [Color(0xFFFF0000), Color(0xFFFFFFFF), Color(0xFF1E90FF)],
      suggestedEffects: [12, 41, 0], // Theater Chase, Running, Solid
    ),
  ];

  // ==================== VALENTINE'S DAY ====================
  static const List<NamedPalette> valentines = [
    NamedPalette(
      id: 'val_romance',
      name: 'Romance',
      description: 'Classic red and pink',
      colors: [Color(0xFFFF0000), Color(0xFFFF69B4), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 43, 0], // Breathe, Twinkle, Solid
    ),
    NamedPalette(
      id: 'val_heartbeat',
      name: 'Heartbeat',
      description: 'Pulsing red love',
      colors: [Color(0xFFFF0000), Color(0xFFDC143C)],
      suggestedEffects: [82, 2, 0], // Heartbeat, Breathe, Solid
    ),
    NamedPalette(
      id: 'val_roses',
      name: 'Red Roses',
      description: 'Deep red with green',
      colors: [Color(0xFFDC143C), Color(0xFF228B22), Color(0xFFFF0000)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'val_blush',
      name: 'Blush',
      description: 'Soft pink tones',
      colors: [Color(0xFFFFB6C1), Color(0xFFFFC0CB), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'val_passion',
      name: 'Passion',
      description: 'Bold red and purple',
      colors: [Color(0xFFFF0000), Color(0xFF800080), Color(0xFFFF1493)],
      suggestedEffects: [2, 41, 0], // Breathe, Running, Solid
    ),
    NamedPalette(
      id: 'val_candy',
      name: 'Candy Hearts',
      description: 'Pastel conversation hearts',
      colors: [Color(0xFFFFB6C1), Color(0xFFADD8E6), Color(0xFFFFFF00)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'val_chocolate',
      name: 'Chocolate Box',
      description: 'Rich brown with gold',
      colors: [Color(0xFF8B4513), Color(0xFFFFD700), Color(0xFFFF0000)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'val_cupid',
      name: 'Cupid',
      description: 'White and gold with pink',
      colors: [Color(0xFFFFFFFF), Color(0xFFFFD700), Color(0xFFFF69B4)],
      suggestedEffects: [43, 2, 0], // Twinkle, Breathe, Solid
    ),
    NamedPalette(
      id: 'val_wine',
      name: 'Wine & Dine',
      description: 'Burgundy and gold elegance',
      colors: [Color(0xFF722F37), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'val_sweetheart',
      name: 'Sweetheart',
      description: 'Pink and white stripes',
      colors: [Color(0xFFFF69B4), Color(0xFFFFFFFF)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
  ];

  // ==================== ST. PATRICK'S DAY ====================
  static const List<NamedPalette> stPatricks = [
    NamedPalette(
      id: 'stpat_shamrock',
      name: 'Shamrock',
      description: 'Classic Irish green',
      colors: [Color(0xFF00FF00), Color(0xFF228B22), Color(0xFF90EE90)],
      suggestedEffects: [2, 41, 0], // Breathe, Running, Solid
    ),
    NamedPalette(
      id: 'stpat_goldpot',
      name: 'Pot of Gold',
      description: 'Green with gold treasure',
      colors: [Color(0xFF00FF00), Color(0xFFFFD700)],
      suggestedEffects: [43, 12, 0], // Twinkle, Theater Chase, Solid
    ),
    NamedPalette(
      id: 'stpat_rainbow',
      name: 'End of Rainbow',
      description: 'Rainbow to gold',
      colors: [Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'stpat_lucky',
      name: 'Lucky Clover',
      description: 'Four-leaf clover greens',
      colors: [Color(0xFF00FF00), Color(0xFF32CD32), Color(0xFF006400)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'stpat_irish',
      name: 'Irish Flag',
      description: 'Green, white, and orange',
      colors: [Color(0xFF00FF00), Color(0xFFFFFFFF), Color(0xFFFF8C00)],
      suggestedEffects: [41, 12, 0], // Running, Theater Chase, Solid
    ),
    NamedPalette(
      id: 'stpat_leprechaun',
      name: 'Leprechaun',
      description: 'Green suit with gold buckle',
      colors: [Color(0xFF228B22), Color(0xFFFFD700), Color(0xFF8B4513)],
      suggestedEffects: [12, 0], // Theater Chase, Solid
    ),
    NamedPalette(
      id: 'stpat_emerald',
      name: 'Emerald Isle',
      description: 'Deep emerald greens',
      colors: [Color(0xFF50C878), Color(0xFF006400), Color(0xFF00FF7F)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'stpat_celtic',
      name: 'Celtic',
      description: 'Green with gold Celtic knots',
      colors: [Color(0xFF006400), Color(0xFFDAA520), Color(0xFF228B22)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'stpat_guinness',
      name: 'Pub Night',
      description: 'Dark brown with gold foam',
      colors: [Color(0xFF3D1F0D), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'stpat_moss',
      name: 'Irish Moss',
      description: 'Soft green earth tones',
      colors: [Color(0xFF8A9A5B), Color(0xFF90EE90), Color(0xFF228B22)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
  ];

  // ==================== EASTER ====================
  static const List<NamedPalette> easter = [
    NamedPalette(
      id: 'easter_pastels',
      name: 'Easter Pastels',
      description: 'Soft pastel rainbow',
      colors: [Color(0xFFFFB6C1), Color(0xFFADD8E6), Color(0xFFFFFF00)],
      suggestedEffects: [41, 43, 0], // Running, Twinkle, Solid
    ),
    NamedPalette(
      id: 'easter_bunny',
      name: 'Easter Bunny',
      description: 'White and pink bunny',
      colors: [Color(0xFFFFFFFF), Color(0xFFFFB6C1), Color(0xFFFF69B4)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'easter_eggs',
      name: 'Easter Eggs',
      description: 'Colorful egg hunt',
      colors: [Color(0xFFFF69B4), Color(0xFF00FFFF), Color(0xFFFFFF00)],
      suggestedEffects: [43, 41, 0], // Twinkle, Running, Solid
    ),
    NamedPalette(
      id: 'easter_spring',
      name: 'Spring Morning',
      description: 'Fresh green and yellow',
      colors: [Color(0xFF90EE90), Color(0xFFFFFF00), Color(0xFFADD8E6)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'easter_lilies',
      name: 'Easter Lilies',
      description: 'White lilies with green',
      colors: [Color(0xFFFFFFFF), Color(0xFFFFFDD0), Color(0xFF90EE90)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'easter_chicks',
      name: 'Baby Chicks',
      description: 'Yellow and orange chicks',
      colors: [Color(0xFFFFFF00), Color(0xFFFFD700), Color(0xFFFF8C00)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'easter_lavender',
      name: 'Lavender Field',
      description: 'Purple and green garden',
      colors: [Color(0xFFE6E6FA), Color(0xFF9370DB), Color(0xFF90EE90)],
      suggestedEffects: [2, 41, 0], // Breathe, Running, Solid
    ),
    NamedPalette(
      id: 'easter_robin',
      name: 'Robin Egg',
      description: 'Soft blue robin eggs',
      colors: [Color(0xFF00FFFF), Color(0xFFADD8E6), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'easter_tulip',
      name: 'Tulip Garden',
      description: 'Red, yellow, pink tulips',
      colors: [Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFFFF69B4)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'easter_sunrise',
      name: 'Easter Sunrise',
      description: 'Morning gold and pink',
      colors: [Color(0xFFFFD700), Color(0xFFFF69B4), Color(0xFFFFB6C1)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
  ];

  // ==================== THANKSGIVING ====================
  static const List<NamedPalette> thanksgiving = [
    NamedPalette(
      id: 'thanks_harvest',
      name: 'Harvest',
      description: 'Orange and brown autumn',
      colors: [Color(0xFFFF8C00), Color(0xFF8B4513), Color(0xFFFFD700)],
      suggestedEffects: [101, 2, 0], // Candle, Breathe, Solid
    ),
    NamedPalette(
      id: 'thanks_turkey',
      name: 'Turkey',
      description: 'Brown with red gobble',
      colors: [Color(0xFF8B4513), Color(0xFFFF0000), Color(0xFFFF8C00)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'thanks_pumpkin',
      name: 'Pumpkin Pie',
      description: 'Warm pumpkin and cream',
      colors: [Color(0xFFFF8C00), Color(0xFFFFFDD0), Color(0xFF8B4513)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'thanks_leaves',
      name: 'Fall Leaves',
      description: 'Red, orange, and yellow',
      colors: [Color(0xFFFF0000), Color(0xFFFF8C00), Color(0xFFFFFF00)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'thanks_corn',
      name: 'Indian Corn',
      description: 'Multi-colored corn',
      colors: [Color(0xFFFFD700), Color(0xFF8B0000), Color(0xFFFF8C00)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'thanks_acorn',
      name: 'Acorn',
      description: 'Brown and tan earth tones',
      colors: [Color(0xFF8B4513), Color(0xFFD2B48C), Color(0xFF6B4423)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'thanks_cranberry',
      name: 'Cranberry',
      description: 'Deep red cranberry',
      colors: [Color(0xFF8B0000), Color(0xFFDC143C), Color(0xFFFF6347)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'thanks_golden',
      name: 'Golden Feast',
      description: 'Warm gold tones',
      colors: [Color(0xFFFFD700), Color(0xFFDAA520), Color(0xFFFF8C00)],
      suggestedEffects: [2, 101, 0], // Breathe, Candle, Solid
    ),
    NamedPalette(
      id: 'thanks_fireside',
      name: 'Fireside',
      description: 'Warm fireplace glow',
      colors: [Color(0xFFFF4500), Color(0xFFFF8C00), Color(0xFFFFD700)],
      suggestedEffects: [101, 0], // Candle, Solid
    ),
    NamedPalette(
      id: 'thanks_gratitude',
      name: 'Gratitude',
      description: 'Warm and inviting amber',
      colors: [Color(0xFFFFB347), Color(0xFFFFE4B5), Color(0xFFFF8C00)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
  ];

  // ==================== NEW YEAR'S ====================
  static const List<NamedPalette> newYears = [
    NamedPalette(
      id: 'ny_celebration',
      name: 'Celebration',
      description: 'Gold and silver sparkle',
      colors: [Color(0xFFFFD700), Color(0xFFC0C0C0), Color(0xFFFFFFFF)],
      suggestedEffects: [52, 43, 87, 0], // Fireworks, Twinkle, Glitter, Solid
    ),
    NamedPalette(
      id: 'ny_midnight',
      name: 'Midnight',
      description: 'Dark blue with gold stars',
      colors: [Color(0xFF00008B), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 52, 0], // Twinkle, Fireworks, Solid
    ),
    NamedPalette(
      id: 'ny_champagne',
      name: 'Champagne',
      description: 'Bubbly gold tones',
      colors: [Color(0xFFFFD700), Color(0xFFFAF0E6), Color(0xFFDAA520)],
      suggestedEffects: [43, 2, 0], // Twinkle, Breathe, Solid
    ),
    NamedPalette(
      id: 'ny_balldrop',
      name: 'Ball Drop',
      description: 'Crystal and lights',
      colors: [Color(0xFFFFFFFF), Color(0xFF00FFFF), Color(0xFFFF00FF)],
      suggestedEffects: [52, 43, 0], // Fireworks, Twinkle, Solid
    ),
    NamedPalette(
      id: 'ny_confetti',
      name: 'Confetti',
      description: 'Multi-color party',
      colors: [Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFFFFD700)],
      suggestedEffects: [87, 43, 0], // Glitter, Twinkle, Solid
    ),
    NamedPalette(
      id: 'ny_disco',
      name: 'Disco Ball',
      description: 'Silver disco shimmer',
      colors: [Color(0xFFC0C0C0), Color(0xFFFFFFFF), Color(0xFF87CEEB)],
      suggestedEffects: [43, 87, 0], // Twinkle, Glitter, Solid
    ),
    NamedPalette(
      id: 'ny_countdown',
      name: 'Countdown',
      description: 'Red and gold countdown',
      colors: [Color(0xFFFF0000), Color(0xFFFFD700)],
      suggestedEffects: [1, 82, 0], // Blink, Heartbeat, Solid
    ),
    NamedPalette(
      id: 'ny_party',
      name: 'Party Time',
      description: 'Vibrant party colors',
      colors: [Color(0xFFFF00FF), Color(0xFF00FFFF), Color(0xFFFFFF00)],
      suggestedEffects: [52, 12, 0], // Fireworks, Theater Chase, Solid
    ),
    NamedPalette(
      id: 'ny_elegant',
      name: 'Black Tie',
      description: 'Elegant black and gold',
      colors: [Color(0xFF000000), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'ny_fireworks',
      name: 'Fireworks',
      description: 'Explosive celebration',
      colors: [Color(0xFFFF0000), Color(0xFFFFFFFF), Color(0xFF0000FF)],
      suggestedEffects: [52, 66, 0], // Fireworks, Solid
    ),
  ];

  /// Get all palettes for a given holiday
  static List<NamedPalette> getPalettesForHoliday(String holidayId) {
    switch (holidayId) {
      case 'holiday_christmas':
        return christmas;
      case 'holiday_halloween':
        return halloween;
      case 'holiday_july4':
        return july4th;
      case 'holiday_valentines':
        return valentines;
      case 'holiday_stpatricks':
        return stPatricks;
      case 'holiday_easter':
        return easter;
      case 'holiday_thanksgiving':
        return thanksgiving;
      case 'holiday_newyears':
        return newYears;
      default:
        return [];
    }
  }

  /// Get all holiday folder definitions
  static List<LibraryNode> getHolidayFolders() {
    return const [
      LibraryNode(
        id: 'holiday_christmas',
        name: 'Christmas',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_holiday',
        sortOrder: 0,
        imageUrl: 'https://images.unsplash.com/photo-1543589077-47d81606c1bf',
      ),
      LibraryNode(
        id: 'holiday_halloween',
        name: 'Halloween',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_holiday',
        sortOrder: 1,
        imageUrl: 'https://images.unsplash.com/photo-1509557965875-b88c97052f0e',
      ),
      LibraryNode(
        id: 'holiday_july4',
        name: '4th of July',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_holiday',
        sortOrder: 2,
        imageUrl: 'https://images.unsplash.com/photo-1475724017904-b712052c192a',
      ),
      LibraryNode(
        id: 'holiday_valentines',
        name: "Valentine's Day",
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_holiday',
        sortOrder: 3,
      ),
      LibraryNode(
        id: 'holiday_stpatricks',
        name: "St. Patrick's Day",
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_holiday',
        sortOrder: 4,
      ),
      LibraryNode(
        id: 'holiday_easter',
        name: 'Easter',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_holiday',
        sortOrder: 5,
        imageUrl: 'https://images.unsplash.com/photo-1522938974444-f12497b69347',
      ),
      LibraryNode(
        id: 'holiday_thanksgiving',
        name: 'Thanksgiving',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_holiday',
        sortOrder: 6,
      ),
      LibraryNode(
        id: 'holiday_newyears',
        name: "New Year's Eve",
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_holiday',
        sortOrder: 7,
      ),
    ];
  }

  /// Convert all holiday palettes to LibraryNodes
  static List<LibraryNode> getAllHolidayPaletteNodes() {
    final nodes = <LibraryNode>[];

    void addPalettes(String parentId, List<NamedPalette> palettes) {
      for (var i = 0; i < palettes.length; i++) {
        nodes.add(palettes[i].toLibraryNode(parentId, sortOrder: i));
      }
    }

    addPalettes('holiday_christmas', christmas);
    addPalettes('holiday_halloween', halloween);
    addPalettes('holiday_july4', july4th);
    addPalettes('holiday_valentines', valentines);
    addPalettes('holiday_stpatricks', stPatricks);
    addPalettes('holiday_easter', easter);
    addPalettes('holiday_thanksgiving', thanksgiving);
    addPalettes('holiday_newyears', newYears);

    return nodes;
  }
}
