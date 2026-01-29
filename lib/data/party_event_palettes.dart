import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';

/// Named color palettes for parties and events.
/// Each event type has multiple themed color combinations.
class PartyEventPalettes {
  // ==================== BOY BIRTHDAY ====================
  static const List<NamedPalette> birthdayBoy = [
    NamedPalette(
      id: 'bday_boy_superhero',
      name: 'Superhero',
      description: 'Red, blue, and yellow hero',
      colors: [Color(0xFFFF0000), Color(0xFF0000FF), Color(0xFFFFFF00)],
      suggestedEffects: [12, 41, 0], // Theater Chase, Running, Solid
    ),
    NamedPalette(
      id: 'bday_boy_sports',
      name: 'Sports Star',
      description: 'Green field with gold',
      colors: [Color(0xFF228B22), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'bday_boy_dinosaur',
      name: 'Dinosaur',
      description: 'Green dino jungle',
      colors: [Color(0xFF228B22), Color(0xFF8B4513), Color(0xFFFF8C00)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'bday_boy_space',
      name: 'Outer Space',
      description: 'Galaxy purple and blue',
      colors: [Color(0xFF4B0082), Color(0xFF0000FF), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'bday_boy_monster',
      name: 'Monster Truck',
      description: 'Orange and black trucks',
      colors: [Color(0xFFFF8C00), Color(0xFF000000), Color(0xFFFF0000)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'bday_boy_pirate',
      name: 'Pirate Adventure',
      description: 'Black and gold treasure',
      colors: [Color(0xFF000000), Color(0xFFFFD700), Color(0xFFFF0000)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'bday_boy_ocean',
      name: 'Under the Sea',
      description: 'Blue ocean depths',
      colors: [Color(0xFF0000FF), Color(0xFF00CED1), Color(0xFF00FF7F)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'bday_boy_minecraft',
      name: 'Block Builder',
      description: 'Green and brown blocks',
      colors: [Color(0xFF228B22), Color(0xFF8B4513), Color(0xFF808080)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'bday_boy_race',
      name: 'Race Car',
      description: 'Red racing stripes',
      colors: [Color(0xFFFF0000), Color(0xFFFFFFFF), Color(0xFF000000)],
      suggestedEffects: [41, 12, 0], // Running, Theater Chase, Solid
    ),
    NamedPalette(
      id: 'bday_boy_safari',
      name: 'Safari Adventure',
      description: 'Jungle animal colors',
      colors: [Color(0xFFFFD700), Color(0xFF8B4513), Color(0xFF228B22)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
  ];

  // ==================== GIRL BIRTHDAY ====================
  static const List<NamedPalette> birthdayGirl = [
    NamedPalette(
      id: 'bday_girl_princess',
      name: 'Princess',
      description: 'Pink and gold royalty',
      colors: [Color(0xFFFF69B4), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 2, 0], // Twinkle, Breathe, Solid
    ),
    NamedPalette(
      id: 'bday_girl_unicorn',
      name: 'Unicorn Magic',
      description: 'Rainbow pastel sparkle',
      colors: [Color(0xFFFF69B4), Color(0xFF9370DB), Color(0xFF00FFFF)],
      suggestedEffects: [43, 41, 0], // Twinkle, Running, Solid
    ),
    NamedPalette(
      id: 'bday_girl_barbie',
      name: 'Barbie Pink',
      description: 'Hot pink and white',
      colors: [Color(0xFFFF1493), Color(0xFFFFFFFF), Color(0xFFFF69B4)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'bday_girl_mermaid',
      name: 'Mermaid',
      description: 'Teal and purple sea',
      colors: [Color(0xFF00CED1), Color(0xFF9370DB), Color(0xFF00FF7F)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'bday_girl_fairy',
      name: 'Fairy Garden',
      description: 'Pink flowers and green',
      colors: [Color(0xFFFF69B4), Color(0xFF90EE90), Color(0xFFE6E6FA)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'bday_girl_butterfly',
      name: 'Butterfly',
      description: 'Colorful butterfly wings',
      colors: [Color(0xFFFF69B4), Color(0xFF00FFFF), Color(0xFFFFFF00)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'bday_girl_rainbow',
      name: 'Rainbow Bright',
      description: 'Full rainbow colors',
      colors: [Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'bday_girl_ballerina',
      name: 'Ballerina',
      description: 'Soft pink tutu',
      colors: [Color(0xFFFFB6C1), Color(0xFFFFFFFF), Color(0xFFFFC0CB)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'bday_girl_frozen',
      name: 'Ice Princess',
      description: 'Icy blue and white',
      colors: [Color(0xFF87CEEB), Color(0xFFFFFFFF), Color(0xFFADD8E6)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'bday_girl_sunshine',
      name: 'Sunshine',
      description: 'Yellow and orange joy',
      colors: [Color(0xFFFFFF00), Color(0xFFFF8C00), Color(0xFFFF69B4)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
  ];

  // ==================== ADULT BIRTHDAY ====================
  static const List<NamedPalette> birthdayAdult = [
    NamedPalette(
      id: 'bday_adult_elegant',
      name: 'Elegant Gold',
      description: 'Gold and black sophistication',
      colors: [Color(0xFFFFD700), Color(0xFF000000), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'bday_adult_silver',
      name: 'Silver Celebration',
      description: 'Silver and white sparkle',
      colors: [Color(0xFFC0C0C0), Color(0xFFFFFFFF), Color(0xFF000000)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'bday_adult_party',
      name: 'Party Lights',
      description: 'Multi-color celebration',
      colors: [Color(0xFFFF00FF), Color(0xFF00FFFF), Color(0xFFFFFF00)],
      suggestedEffects: [12, 43, 0], // Theater Chase, Twinkle, Solid
    ),
    NamedPalette(
      id: 'bday_adult_champagne',
      name: 'Champagne Toast',
      description: 'Bubbly gold tones',
      colors: [Color(0xFFFFD700), Color(0xFFFAF0E6), Color(0xFFDAA520)],
      suggestedEffects: [43, 2, 0], // Twinkle, Breathe, Solid
    ),
    NamedPalette(
      id: 'bday_adult_neon',
      name: 'Neon Night',
      description: 'Bright neon colors',
      colors: [Color(0xFFFF00FF), Color(0xFF00FF00), Color(0xFF00FFFF)],
      suggestedEffects: [12, 0], // Theater Chase, Solid
    ),
    NamedPalette(
      id: 'bday_adult_rose',
      name: 'Rose Gold',
      description: 'Rose gold and blush',
      colors: [Color(0xFFB76E79), Color(0xFFFFC0CB), Color(0xFFFFD700)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'bday_adult_milestone',
      name: 'Milestone',
      description: 'Gold and silver balloons',
      colors: [Color(0xFFFFD700), Color(0xFFC0C0C0), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'bday_adult_tropical',
      name: 'Tropical Party',
      description: 'Bright island colors',
      colors: [Color(0xFFFF8C00), Color(0xFF00CED1), Color(0xFF32CD32)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'bday_adult_vintage',
      name: 'Vintage Glam',
      description: 'Deep burgundy and gold',
      colors: [Color(0xFF722F37), Color(0xFFFFD700), Color(0xFF000000)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'bday_adult_disco',
      name: 'Disco Fever',
      description: 'Shimmering disco colors',
      colors: [Color(0xFFC0C0C0), Color(0xFFFFD700), Color(0xFFFF00FF)],
      suggestedEffects: [43, 12, 0], // Twinkle, Theater Chase, Solid
    ),
  ];

  // ==================== WEDDING ====================
  static const List<NamedPalette> wedding = [
    NamedPalette(
      id: 'wedding_classic',
      name: 'Classic White',
      description: 'Pure white elegance',
      colors: [Color(0xFFFFFFFF), Color(0xFFFFFDD0)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'wedding_romantic',
      name: 'Romantic Blush',
      description: 'Blush pink and gold',
      colors: [Color(0xFFFFB6C1), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'wedding_garden',
      name: 'Garden Romance',
      description: 'Pink roses and green',
      colors: [Color(0xFFFF69B4), Color(0xFF90EE90), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'wedding_navy',
      name: 'Navy & Gold',
      description: 'Elegant navy and gold',
      colors: [Color(0xFF000080), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'wedding_rustic',
      name: 'Rustic Charm',
      description: 'Burlap and lace',
      colors: [Color(0xFFD2B48C), Color(0xFFFFFFFF), Color(0xFF8B4513)],
      suggestedEffects: [101, 0], // Candle, Solid
    ),
    NamedPalette(
      id: 'wedding_lavender',
      name: 'Lavender Dreams',
      description: 'Soft purple elegance',
      colors: [Color(0xFFE6E6FA), Color(0xFF9370DB), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'wedding_burgundy',
      name: 'Burgundy Romance',
      description: 'Deep wine and gold',
      colors: [Color(0xFF722F37), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'wedding_beach',
      name: 'Beach Wedding',
      description: 'Sandy and ocean blue',
      colors: [Color(0xFFD2B48C), Color(0xFF00CED1), Color(0xFFFFFFFF)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'wedding_sage',
      name: 'Sage Green',
      description: 'Earthy sage and cream',
      colors: [Color(0xFF9DC183), Color(0xFFFFFDD0), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'wedding_sunset',
      name: 'Sunset Romance',
      description: 'Coral and gold sunset',
      colors: [Color(0xFFFF7F50), Color(0xFFFFD700), Color(0xFFFF69B4)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
  ];

  // ==================== BABY SHOWER ====================
  static const List<NamedPalette> babyShower = [
    NamedPalette(
      id: 'baby_boy',
      name: 'Baby Boy Blue',
      description: 'Soft blue for boys',
      colors: [Color(0xFFADD8E6), Color(0xFF87CEEB), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'baby_girl',
      name: 'Baby Girl Pink',
      description: 'Soft pink for girls',
      colors: [Color(0xFFFFB6C1), Color(0xFFFFC0CB), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'baby_neutral',
      name: 'Gender Neutral',
      description: 'Yellow and green joy',
      colors: [Color(0xFFFFFF00), Color(0xFF90EE90), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'baby_safari',
      name: 'Safari Animals',
      description: 'Jungle animal colors',
      colors: [Color(0xFFFFD700), Color(0xFF8B4513), Color(0xFF90EE90)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'baby_cloud',
      name: 'Clouds & Stars',
      description: 'White clouds, gold stars',
      colors: [Color(0xFFFFFFFF), Color(0xFFFFD700), Color(0xFFADD8E6)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'baby_elephant',
      name: 'Elephant Parade',
      description: 'Gray and pastel blue',
      colors: [Color(0xFF808080), Color(0xFFADD8E6), Color(0xFFFFFFFF)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'baby_rainbow',
      name: 'Rainbow Baby',
      description: 'Soft rainbow pastels',
      colors: [Color(0xFFFFB6C1), Color(0xFFFFFF00), Color(0xFFADD8E6)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'baby_woodland',
      name: 'Woodland Creatures',
      description: 'Forest browns and greens',
      colors: [Color(0xFF8B4513), Color(0xFF90EE90), Color(0xFFFFFDD0)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'baby_navy',
      name: 'Nautical',
      description: 'Navy and white stripes',
      colors: [Color(0xFF000080), Color(0xFFFFFFFF), Color(0xFFFF0000)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'baby_twinkle',
      name: 'Twinkle Star',
      description: 'Night sky with stars',
      colors: [Color(0xFF191970), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
  ];

  // ==================== GRADUATION ====================
  static const List<NamedPalette> graduation = [
    NamedPalette(
      id: 'grad_classic',
      name: 'Classic Cap & Gown',
      description: 'Black and gold achievement',
      colors: [Color(0xFF000000), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'grad_success',
      name: 'Success Gold',
      description: 'Celebratory gold',
      colors: [Color(0xFFFFD700), Color(0xFFDAA520), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'grad_future',
      name: 'Bright Future',
      description: 'Optimistic blue and gold',
      colors: [Color(0xFF4169E1), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'grad_celebrate',
      name: 'Celebration',
      description: 'Multi-color party',
      colors: [Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF0000FF)],
      suggestedEffects: [52, 43, 0], // Fireworks, Twinkle, Solid
    ),
    NamedPalette(
      id: 'grad_class',
      name: 'Class Colors',
      description: 'School colors pride',
      colors: [Color(0xFF000080), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [12, 0], // Theater Chase, Solid
    ),
    NamedPalette(
      id: 'grad_elegant',
      name: 'Elegant Silver',
      description: 'Refined silver and white',
      colors: [Color(0xFFC0C0C0), Color(0xFFFFFFFF), Color(0xFF000000)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'grad_milestone',
      name: 'Milestone',
      description: 'Achievement purple',
      colors: [Color(0xFF800080), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'grad_adventure',
      name: 'New Adventure',
      description: 'Bold and bright start',
      colors: [Color(0xFFFF8C00), Color(0xFF00CED1), Color(0xFFFFFF00)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'grad_books',
      name: 'Books & Knowledge',
      description: 'Library browns and gold',
      colors: [Color(0xFF8B4513), Color(0xFFFFD700), Color(0xFFFFFDD0)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'grad_stars',
      name: 'Reach for Stars',
      description: 'Night sky achievement',
      colors: [Color(0xFF191970), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
  ];

  // ==================== ANNIVERSARY ====================
  static const List<NamedPalette> anniversary = [
    NamedPalette(
      id: 'anniv_gold',
      name: 'Golden Anniversary',
      description: '50 years of gold',
      colors: [Color(0xFFFFD700), Color(0xFFDAA520), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'anniv_silver',
      name: 'Silver Anniversary',
      description: '25 years of silver',
      colors: [Color(0xFFC0C0C0), Color(0xFFFFFFFF), Color(0xFFE8E8E8)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'anniv_ruby',
      name: 'Ruby Anniversary',
      description: '40 years of red',
      colors: [Color(0xFFE0115F), Color(0xFFFFFFFF), Color(0xFFDC143C)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'anniv_romance',
      name: 'Romantic Evening',
      description: 'Red roses and candlelight',
      colors: [Color(0xFFFF0000), Color(0xFFFFB347), Color(0xFFFFFFFF)],
      suggestedEffects: [101, 2, 0], // Candle, Breathe, Solid
    ),
    NamedPalette(
      id: 'anniv_pearl',
      name: 'Pearl Anniversary',
      description: '30 years of pearls',
      colors: [Color(0xFFFFFDD0), Color(0xFFFFFFFF), Color(0xFFFFE4B5)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'anniv_diamond',
      name: 'Diamond Anniversary',
      description: '60 years of diamonds',
      colors: [Color(0xFFFFFFFF), Color(0xFFB9F2FF), Color(0xFFC0C0C0)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'anniv_love',
      name: 'Love Story',
      description: 'Pink and red hearts',
      colors: [Color(0xFFFF69B4), Color(0xFFFF0000), Color(0xFFFFFFFF)],
      suggestedEffects: [82, 2, 0], // Heartbeat, Breathe, Solid
    ),
    NamedPalette(
      id: 'anniv_champagne',
      name: 'Champagne Toast',
      description: 'Bubbly celebration',
      colors: [Color(0xFFFFD700), Color(0xFFFAF0E6), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'anniv_starlight',
      name: 'Starlight',
      description: 'Romantic night sky',
      colors: [Color(0xFF191970), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'anniv_eternal',
      name: 'Eternal Flame',
      description: 'Warm everlasting glow',
      colors: [Color(0xFFFF4500), Color(0xFFFFB347), Color(0xFFFFD700)],
      suggestedEffects: [101, 0], // Candle, Solid
    ),
  ];

  /// Get palettes for a given event subcategory
  static List<NamedPalette> getPalettesForEvent(String eventId) {
    switch (eventId) {
      case 'event_bday_boy':
        return birthdayBoy;
      case 'event_bday_girl':
        return birthdayGirl;
      case 'event_bday_adult':
        return birthdayAdult;
      case 'event_weddings':
        return wedding;
      case 'event_babyshower':
        return babyShower;
      case 'event_graduation':
        return graduation;
      case 'event_anniversary':
        return anniversary;
      default:
        return [];
    }
  }

  /// Get all party/event folder definitions
  static List<LibraryNode> getEventFolders() {
    return const [
      // Birthdays parent folder
      LibraryNode(
        id: 'event_birthdays',
        name: 'Birthdays',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_party',
        sortOrder: 0,
      ),
      // Birthday sub-folders
      LibraryNode(
        id: 'event_bday_boy',
        name: 'Boy Birthday',
        nodeType: LibraryNodeType.folder,
        parentId: 'event_birthdays',
        sortOrder: 0,
      ),
      LibraryNode(
        id: 'event_bday_girl',
        name: 'Girl Birthday',
        nodeType: LibraryNodeType.folder,
        parentId: 'event_birthdays',
        sortOrder: 1,
      ),
      LibraryNode(
        id: 'event_bday_adult',
        name: 'Adult Birthday',
        nodeType: LibraryNodeType.folder,
        parentId: 'event_birthdays',
        sortOrder: 2,
      ),
      // Other event folders
      LibraryNode(
        id: 'event_weddings',
        name: 'Weddings',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_party',
        sortOrder: 1,
      ),
      LibraryNode(
        id: 'event_babyshower',
        name: 'Baby Shower',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_party',
        sortOrder: 2,
      ),
      LibraryNode(
        id: 'event_graduation',
        name: 'Graduation',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_party',
        sortOrder: 3,
      ),
      LibraryNode(
        id: 'event_anniversary',
        name: 'Anniversary',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_party',
        sortOrder: 4,
      ),
    ];
  }

  /// Convert all party/event palettes to LibraryNodes
  static List<LibraryNode> getAllEventPaletteNodes() {
    final nodes = <LibraryNode>[];

    void addPalettes(String parentId, List<NamedPalette> palettes) {
      for (var i = 0; i < palettes.length; i++) {
        nodes.add(palettes[i].toLibraryNode(parentId, sortOrder: i));
      }
    }

    addPalettes('event_bday_boy', birthdayBoy);
    addPalettes('event_bday_girl', birthdayGirl);
    addPalettes('event_bday_adult', birthdayAdult);
    addPalettes('event_weddings', wedding);
    addPalettes('event_babyshower', babyShower);
    addPalettes('event_graduation', graduation);
    addPalettes('event_anniversary', anniversary);

    return nodes;
  }
}
