import 'package:flutter/material.dart';

/// Represents a golf theme/event with its name and colors.
class GolfTheme {
  final String id;
  final String name;
  final String? description;
  final String folder; // Which subfolder this belongs to
  final List<Color> colors;
  final List<String> keywords;

  const GolfTheme({
    required this.id,
    required this.name,
    this.description,
    required this.folder,
    required this.colors,
    this.keywords = const [],
  });

  /// Search-friendly string
  String get searchKey => '$name ${description ?? ''} ${keywords.join(' ')} golf'.toLowerCase();
}

/// Database of golf themes organized by tournament/event and general themes.
class GolfThemesDatabase {
  // Folder identifiers
  static const String mastersFolderId = 'golf_masters';
  static const String ryderCupFolderId = 'golf_ryder_cup';
  static const String usOpenFolderId = 'golf_us_open';
  static const String theOpenFolderId = 'golf_the_open';
  static const String pgaFolderId = 'golf_pga_championship';
  static const String generalFolderId = 'golf_general_themes';

  static const List<GolfTheme> allThemes = [
    // ============================================
    // THE MASTERS - Augusta National
    // ============================================
    GolfTheme(
      id: 'golf_masters_classic',
      name: 'Masters Green',
      description: 'The iconic Augusta National green jacket',
      folder: mastersFolderId,
      colors: [Color(0xFF006747), Color(0xFFFFD700)], // Augusta green + gold
      keywords: ['augusta', 'green jacket', 'tradition'],
    ),
    GolfTheme(
      id: 'golf_masters_azalea',
      name: 'Azalea Pink',
      description: 'Famous azaleas blooming at Augusta',
      folder: mastersFolderId,
      colors: [Color(0xFFFF69B4), Color(0xFF006747), Color(0xFFFFFFFF)],
      keywords: ['azalea', 'flowers', 'spring', 'augusta'],
    ),
    GolfTheme(
      id: 'golf_masters_amen_corner',
      name: 'Amen Corner',
      description: 'The legendary holes 11, 12, and 13',
      folder: mastersFolderId,
      colors: [Color(0xFF006747), Color(0xFF228B22), Color(0xFFFFD700)],
      keywords: ['amen corner', 'augusta', '11', '12', '13'],
    ),
    GolfTheme(
      id: 'golf_masters_champion',
      name: 'Champion\'s Gold',
      description: 'Golden celebration for the champion',
      folder: mastersFolderId,
      colors: [Color(0xFFFFD700), Color(0xFF006747), Color(0xFFFFFFFF)],
      keywords: ['winner', 'champion', 'trophy', 'gold'],
    ),
    GolfTheme(
      id: 'golf_masters_magnolia',
      name: 'Magnolia Lane',
      description: 'The famous entrance drive at Augusta',
      folder: mastersFolderId,
      colors: [Color(0xFFFFFFFF), Color(0xFF228B22), Color(0xFFFFF8DC)],
      keywords: ['magnolia', 'entrance', 'tradition'],
    ),

    // ============================================
    // RYDER CUP
    // ============================================
    GolfTheme(
      id: 'golf_ryder_usa',
      name: 'Team USA',
      description: 'Red, white, and blue for America',
      folder: ryderCupFolderId,
      colors: [Color(0xFFB22234), Color(0xFFFFFFFF), Color(0xFF3C3B6E)],
      keywords: ['usa', 'america', 'united states', 'team'],
    ),
    GolfTheme(
      id: 'golf_ryder_europe',
      name: 'Team Europe',
      description: 'European team colors',
      folder: ryderCupFolderId,
      colors: [Color(0xFF003399), Color(0xFFFFD700)],
      keywords: ['europe', 'eu', 'team'],
    ),
    GolfTheme(
      id: 'golf_ryder_classic',
      name: 'Ryder Cup Classic',
      description: 'Traditional Ryder Cup gold and navy',
      folder: ryderCupFolderId,
      colors: [Color(0xFFCFB53B), Color(0xFF002B5C), Color(0xFFFFFFFF)],
      keywords: ['ryder', 'classic', 'biennial'],
    ),
    GolfTheme(
      id: 'golf_ryder_rivalry',
      name: 'Transatlantic Rivalry',
      description: 'USA vs Europe showdown',
      folder: ryderCupFolderId,
      colors: [Color(0xFFB22234), Color(0xFF003399), Color(0xFFFFD700)],
      keywords: ['rivalry', 'usa', 'europe', 'showdown'],
    ),

    // ============================================
    // US OPEN
    // ============================================
    GolfTheme(
      id: 'golf_usopen_classic',
      name: 'US Open Classic',
      description: 'Traditional USGA red and blue',
      folder: usOpenFolderId,
      colors: [Color(0xFF002B5C), Color(0xFFCC0000), Color(0xFFFFFFFF)],
      keywords: ['usga', 'championship', 'june'],
    ),
    GolfTheme(
      id: 'golf_usopen_rough',
      name: 'US Open Rough',
      description: 'The notoriously deep rough',
      folder: usOpenFolderId,
      colors: [Color(0xFF006400), Color(0xFF228B22), Color(0xFF002B5C)],
      keywords: ['rough', 'deep', 'difficult', 'challenge'],
    ),
    GolfTheme(
      id: 'golf_usopen_pinehurst',
      name: 'Pinehurst Sandhills',
      description: 'Sandy tones of Pinehurst',
      folder: usOpenFolderId,
      colors: [Color(0xFFD4A574), Color(0xFF006400), Color(0xFF8B7355)],
      keywords: ['pinehurst', 'sand', 'north carolina'],
    ),
    GolfTheme(
      id: 'golf_usopen_patriot',
      name: 'Patriotic Glory',
      description: 'Stars and stripes celebration',
      folder: usOpenFolderId,
      colors: [Color(0xFFB22234), Color(0xFFFFFFFF), Color(0xFF3C3B6E)],
      keywords: ['patriotic', 'america', 'flag', 'glory'],
    ),

    // ============================================
    // THE OPEN (British Open)
    // ============================================
    GolfTheme(
      id: 'golf_open_claret',
      name: 'Claret Jug',
      description: 'The famous championship trophy',
      folder: theOpenFolderId,
      colors: [Color(0xFF722F37), Color(0xFFC0C0C0), Color(0xFF1C1C1C)],
      keywords: ['claret', 'jug', 'trophy', 'british'],
    ),
    GolfTheme(
      id: 'golf_open_links',
      name: 'Links Land',
      description: 'Scottish coastal links colors',
      folder: theOpenFolderId,
      colors: [Color(0xFF8B7355), Color(0xFF6B8E23), Color(0xFF4682B4)],
      keywords: ['links', 'scotland', 'coastal', 'st andrews'],
    ),
    GolfTheme(
      id: 'golf_open_scotland',
      name: 'Scottish Royal',
      description: 'Royal blue and gold of Scotland',
      folder: theOpenFolderId,
      colors: [Color(0xFF0065BD), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      keywords: ['scotland', 'royal', 'tartan', 'tradition'],
    ),
    GolfTheme(
      id: 'golf_open_heather',
      name: 'Highland Heather',
      description: 'Purple heather of Scottish highlands',
      folder: theOpenFolderId,
      colors: [Color(0xFF9370DB), Color(0xFF6B8E23), Color(0xFF8B7355)],
      keywords: ['heather', 'highlands', 'purple', 'scotland'],
    ),
    GolfTheme(
      id: 'golf_open_stormy',
      name: 'Stormy Links',
      description: 'Dramatic British weather on the course',
      folder: theOpenFolderId,
      colors: [Color(0xFF4A4A4A), Color(0xFF708090), Color(0xFF6B8E23)],
      keywords: ['stormy', 'weather', 'wind', 'rain', 'dramatic'],
    ),

    // ============================================
    // PGA CHAMPIONSHIP
    // ============================================
    GolfTheme(
      id: 'golf_pga_classic',
      name: 'PGA Championship',
      description: 'Official PGA navy and gold',
      folder: pgaFolderId,
      colors: [Color(0xFF002B5C), Color(0xFFD4AF37), Color(0xFFFFFFFF)],
      keywords: ['pga', 'championship', 'major'],
    ),
    GolfTheme(
      id: 'golf_pga_wanamaker',
      name: 'Wanamaker Trophy',
      description: 'The iconic silver trophy',
      folder: pgaFolderId,
      colors: [Color(0xFFC0C0C0), Color(0xFF002B5C), Color(0xFFFFFFFF)],
      keywords: ['wanamaker', 'trophy', 'silver', 'champion'],
    ),
    GolfTheme(
      id: 'golf_pga_glory',
      name: 'PGA Glory',
      description: 'Golden victory celebration',
      folder: pgaFolderId,
      colors: [Color(0xFFD4AF37), Color(0xFF002B5C), Color(0xFFC0C0C0)],
      keywords: ['glory', 'victory', 'celebration', 'winner'],
    ),

    // ============================================
    // GENERAL GOLF THEMES
    // ============================================
    GolfTheme(
      id: 'golf_fairway_green',
      name: 'Fairway Green',
      description: 'Classic golf course fairway',
      folder: generalFolderId,
      colors: [Color(0xFF228B22), Color(0xFF006400), Color(0xFF90EE90)],
      keywords: ['fairway', 'green', 'grass', 'classic'],
    ),
    GolfTheme(
      id: 'golf_putting_green',
      name: 'Putting Green',
      description: 'Smooth, manicured putting surface',
      folder: generalFolderId,
      colors: [Color(0xFF006400), Color(0xFF228B22), Color(0xFFFFFFFF)],
      keywords: ['putting', 'green', 'smooth', 'pin'],
    ),
    GolfTheme(
      id: 'golf_sunrise_links',
      name: 'Sunrise Tee Time',
      description: 'Early morning golf with golden sunrise',
      folder: generalFolderId,
      colors: [Color(0xFFFF8C00), Color(0xFFFFD700), Color(0xFF228B22)],
      keywords: ['sunrise', 'morning', 'dawn', 'tee time'],
    ),
    GolfTheme(
      id: 'golf_sunset_round',
      name: 'Sunset Round',
      description: 'Golden hour on the back nine',
      folder: generalFolderId,
      colors: [Color(0xFFFF6B35), Color(0xFFFFD700), Color(0xFF8B4513)],
      keywords: ['sunset', 'evening', 'golden hour', 'back nine'],
    ),
    GolfTheme(
      id: 'golf_birdie',
      name: 'Birdie Celebration',
      description: 'One under par celebration',
      folder: generalFolderId,
      colors: [Color(0xFFFFD700), Color(0xFF228B22)],
      keywords: ['birdie', 'under par', 'celebration', 'score'],
    ),
    GolfTheme(
      id: 'golf_eagle',
      name: 'Eagle Soar',
      description: 'Two under par - rare and golden',
      folder: generalFolderId,
      colors: [Color(0xFFD4AF37), Color(0xFF002B5C), Color(0xFFFFFFFF)],
      keywords: ['eagle', 'two under', 'rare', 'achievement'],
    ),
    GolfTheme(
      id: 'golf_hole_in_one',
      name: 'Hole In One!',
      description: 'The ultimate golf achievement',
      folder: generalFolderId,
      colors: [Color(0xFFFF0000), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      keywords: ['ace', 'hole in one', 'celebration', 'amazing'],
    ),
    GolfTheme(
      id: 'golf_19th_hole',
      name: '19th Hole',
      description: 'Post-round celebration at the clubhouse',
      folder: generalFolderId,
      colors: [Color(0xFFD4AF37), Color(0xFF8B4513), Color(0xFFFFFFFF)],
      keywords: ['19th hole', 'clubhouse', 'bar', 'celebration'],
    ),
    GolfTheme(
      id: 'golf_sand_trap',
      name: 'Sand Trap',
      description: 'Bunker sand and rescue shot',
      folder: generalFolderId,
      colors: [Color(0xFFD4A574), Color(0xFFF5DEB3), Color(0xFF228B22)],
      keywords: ['bunker', 'sand', 'trap', 'beach'],
    ),
    GolfTheme(
      id: 'golf_water_hazard',
      name: 'Water Hazard',
      description: 'Challenging water features on course',
      folder: generalFolderId,
      colors: [Color(0xFF4169E1), Color(0xFF87CEEB), Color(0xFF228B22)],
      keywords: ['water', 'hazard', 'pond', 'lake'],
    ),
    GolfTheme(
      id: 'golf_caddy_white',
      name: 'Caddy White',
      description: 'Classic caddy jumpsuit white and green',
      folder: generalFolderId,
      colors: [Color(0xFFFFFFFF), Color(0xFF006747), Color(0xFF228B22)],
      keywords: ['caddy', 'caddie', 'white', 'jumpsuit'],
    ),
    GolfTheme(
      id: 'golf_country_club',
      name: 'Country Club',
      description: 'Elegant navy and cream club colors',
      folder: generalFolderId,
      colors: [Color(0xFF002B5C), Color(0xFFFFF8DC), Color(0xFFD4AF37)],
      keywords: ['country club', 'elegant', 'sophisticated', 'member'],
    ),
    GolfTheme(
      id: 'golf_classic_plaid',
      name: 'Classic Plaid',
      description: 'Traditional golf fashion colors',
      folder: generalFolderId,
      colors: [Color(0xFFB22234), Color(0xFF002B5C), Color(0xFFFFFFFF)],
      keywords: ['plaid', 'argyle', 'fashion', 'traditional'],
    ),
    GolfTheme(
      id: 'golf_tropical_resort',
      name: 'Tropical Resort',
      description: 'Vibrant resort golf destination',
      folder: generalFolderId,
      colors: [Color(0xFF00CED1), Color(0xFF228B22), Color(0xFFFF6B35)],
      keywords: ['tropical', 'resort', 'vacation', 'hawaii', 'caribbean'],
    ),
    GolfTheme(
      id: 'golf_desert_course',
      name: 'Desert Links',
      description: 'Arizona and Palm Springs desert golf',
      folder: generalFolderId,
      colors: [Color(0xFFD2691E), Color(0xFFE97451), Color(0xFF228B22)],
      keywords: ['desert', 'arizona', 'palm springs', 'scottsdale'],
    ),
    GolfTheme(
      id: 'golf_autumn_round',
      name: 'Autumn Round',
      description: 'Fall foliage on the course',
      folder: generalFolderId,
      colors: [Color(0xFFFF8C00), Color(0xFFB22222), Color(0xFFDAA520)],
      keywords: ['autumn', 'fall', 'foliage', 'leaves'],
    ),
  ];

  /// Get all themes for a specific folder
  static List<GolfTheme> getByFolder(String folderId) {
    return allThemes.where((t) => t.folder == folderId).toList();
  }

  /// Search themes by query string
  static List<GolfTheme> search(String query) {
    if (query.isEmpty) return [];
    final lower = query.toLowerCase();
    return allThemes.where((t) => t.searchKey.contains(lower)).toList();
  }

  /// Get all unique folder IDs
  static List<String> get folderIds {
    return allThemes.map((t) => t.folder).toSet().toList();
  }
}
