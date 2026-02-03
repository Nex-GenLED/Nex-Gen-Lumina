import 'package:flutter/material.dart';

/// Types of nodes in the pattern library hierarchy.
enum LibraryNodeType {
  /// Top-level category (Game Day Fan Zone, Holidays, etc.)
  category,

  /// Intermediate folder (NFL, SEC, Christmas, Spring, Birthdays)
  folder,

  /// Final selectable color palette/theme (Kansas City Chiefs, The Grinch, etc.)
  palette,
}

/// A node in the pattern library hierarchy.
///
/// Can represent categories, subcategories, leagues, conferences, teams,
/// holidays, seasons, events, or color palettes depending on [nodeType].
class LibraryNode {
  final String id;
  final String name;
  final String? description;
  final String? imageUrl;
  final LibraryNodeType nodeType;

  /// Parent node ID. Null for root categories.
  final String? parentId;

  /// Theme colors for palette nodes. Null for folder/category nodes.
  final List<Color>? themeColors;

  /// Sort order within parent (lower = first)
  final int sortOrder;

  /// Additional metadata (league info, suggested effects, etc.)
  final Map<String, dynamic>? metadata;

  const LibraryNode({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    required this.nodeType,
    this.parentId,
    this.themeColors,
    this.sortOrder = 0,
    this.metadata,
  });

  /// Returns true if this node has color themes (is a palette/team)
  bool get isPalette => nodeType == LibraryNodeType.palette &&
                        themeColors != null &&
                        themeColors!.isNotEmpty;

  /// Returns true if this node is a root category
  bool get isRoot => parentId == null;

  /// Returns true if this node is a folder (intermediate navigation level)
  bool get isFolder => nodeType == LibraryNodeType.folder;

  /// Returns true if this node is a top-level category
  bool get isCategory => nodeType == LibraryNodeType.category;

  /// Get suggested effect IDs from metadata, or default list
  List<int> get suggestedEffects {
    final effects = metadata?['suggestedEffects'];
    if (effects is List) {
      return effects.cast<int>();
    }
    // Default effects: Theater Chase, Running, Breathe, Solid
    return const [12, 41, 2, 0];
  }

  /// Get default speed from metadata
  int get defaultSpeed => (metadata?['defaultSpeed'] as int?) ?? 128;

  /// Get default intensity from metadata
  int get defaultIntensity => (metadata?['defaultIntensity'] as int?) ?? 128;

  /// Create a copy with optional overrides
  LibraryNode copyWith({
    String? id,
    String? name,
    String? description,
    String? imageUrl,
    LibraryNodeType? nodeType,
    String? parentId,
    List<Color>? themeColors,
    int? sortOrder,
    Map<String, dynamic>? metadata,
  }) {
    return LibraryNode(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      nodeType: nodeType ?? this.nodeType,
      parentId: parentId ?? this.parentId,
      themeColors: themeColors ?? this.themeColors,
      sortOrder: sortOrder ?? this.sortOrder,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() => 'LibraryNode(id: $id, name: $name, type: $nodeType)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LibraryNode && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Helper class for building named color palettes
class NamedPalette {
  final String id;
  final String name;
  final String? description;
  final List<Color> colors;
  final List<int>? suggestedEffects;
  final int? defaultSpeed;
  final int? defaultIntensity;

  const NamedPalette({
    required this.id,
    required this.name,
    this.description,
    required this.colors,
    this.suggestedEffects,
    this.defaultSpeed,
    this.defaultIntensity,
  });

  /// Convert to LibraryNode
  LibraryNode toLibraryNode(String parentId, {int sortOrder = 0}) {
    return LibraryNode(
      id: id,
      name: name,
      description: description,
      nodeType: LibraryNodeType.palette,
      parentId: parentId,
      themeColors: colors,
      sortOrder: sortOrder,
      metadata: {
        if (suggestedEffects != null) 'suggestedEffects': suggestedEffects,
        if (defaultSpeed != null) 'defaultSpeed': defaultSpeed,
        if (defaultIntensity != null) 'defaultIntensity': defaultIntensity,
      },
    );
  }
}

/// Root category IDs (matching existing category IDs for compatibility)
class LibraryCategoryIds {
  static const String quickPicks = 'cat_quick_picks';
  static const String sports = 'cat_sports';
  static const String holidays = 'cat_holiday';
  static const String seasonal = 'cat_season';
  static const String parties = 'cat_party';
  static const String architectural = 'cat_arch';
  static const String security = 'cat_security';
  static const String movies = 'cat_movies';
  static const String nature = 'cat_nature';
}

/// Special folder IDs for personalized content
class PersonalizedFolderIds {
  /// My Teams folder under Game Day - shows user's favorite teams
  static const String myTeams = 'sports_my_teams';
}

/// League/folder IDs for Game Day Fan Zone
class LeagueFolderIds {
  static const String nfl = 'league_nfl';
  static const String nba = 'league_nba';
  static const String mlb = 'league_mlb';
  static const String nhl = 'league_nhl';
  static const String mls = 'league_mls';
  static const String wnba = 'league_wnba';
  static const String ncaaFootball = 'ncaa_football';
  static const String ncaaBasketball = 'ncaa_basketball';
  static const String golf = 'league_golf';
}

/// Golf subfolder IDs
class GolfFolderIds {
  static const String masters = 'golf_masters';
  static const String ryderCup = 'golf_ryder_cup';
  static const String usOpen = 'golf_us_open';
  static const String theOpen = 'golf_the_open';
  static const String pga = 'golf_pga_championship';
  static const String generalThemes = 'golf_general_themes';
}

/// Holiday folder IDs
class HolidayFolderIds {
  static const String christmas = 'holiday_christmas';
  static const String halloween = 'holiday_halloween';
  static const String july4th = 'holiday_july4';
  static const String valentines = 'holiday_valentines';
  static const String stPatricks = 'holiday_stpatricks';
  static const String easter = 'holiday_easter';
  static const String thanksgiving = 'holiday_thanksgiving';
  static const String newYears = 'holiday_newyears';
}

/// Season folder IDs
class SeasonFolderIds {
  static const String spring = 'season_spring';
  static const String summer = 'season_summer';
  static const String autumn = 'season_autumn';
  static const String winter = 'season_winter';
}

/// Party/Event folder IDs
class PartyFolderIds {
  static const String birthdays = 'event_birthdays';
  static const String weddings = 'event_weddings';
  static const String babyShower = 'event_babyshower';
  static const String graduation = 'event_graduation';
  static const String anniversary = 'event_anniversary';
}
