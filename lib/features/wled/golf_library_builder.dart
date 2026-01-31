import 'package:nexgen_command/data/golf_themes.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';

/// Builds the golf hierarchy from GolfThemesDatabase.
/// Creates folders for major tournaments and general themes.
class GolfLibraryBuilder {
  /// Folder display info: ID -> (Name, Description, SortOrder)
  static const Map<String, _FolderInfo> _folderInfo = {
    GolfThemesDatabase.mastersFolderId: _FolderInfo(
      name: 'The Masters',
      description: 'Augusta National\'s legendary tournament',
      sortOrder: 0,
    ),
    GolfThemesDatabase.ryderCupFolderId: _FolderInfo(
      name: 'Ryder Cup',
      description: 'USA vs Europe biennial showdown',
      sortOrder: 1,
    ),
    GolfThemesDatabase.usOpenFolderId: _FolderInfo(
      name: 'US Open',
      description: 'USGA\'s major championship',
      sortOrder: 2,
    ),
    GolfThemesDatabase.theOpenFolderId: _FolderInfo(
      name: 'The Open',
      description: 'The British Open Championship',
      sortOrder: 3,
    ),
    GolfThemesDatabase.pgaFolderId: _FolderInfo(
      name: 'PGA Championship',
      description: 'PGA of America\'s major',
      sortOrder: 4,
    ),
    GolfThemesDatabase.generalFolderId: _FolderInfo(
      name: 'Golf Themes',
      description: 'General golf-inspired colorways',
      sortOrder: 5,
    ),
  };

  /// Build the main Golf folder node (child of Game Day Fan Zone)
  static LibraryNode getGolfMainFolder() {
    return const LibraryNode(
      id: LeagueFolderIds.golf,
      name: 'Golf',
      description: 'Major tournaments and golf-themed colorways',
      nodeType: LibraryNodeType.folder,
      parentId: LibraryCategoryIds.sports,
      sortOrder: 10, // After NCAA
      metadata: {'category': 'golf'},
    );
  }

  /// Build all golf subfolder nodes (Masters, Ryder Cup, etc.)
  static List<LibraryNode> getGolfSubfolders() {
    final folders = <LibraryNode>[];

    for (final entry in _folderInfo.entries) {
      folders.add(LibraryNode(
        id: entry.key,
        name: entry.value.name,
        description: entry.value.description,
        nodeType: LibraryNodeType.folder,
        parentId: LeagueFolderIds.golf,
        sortOrder: entry.value.sortOrder,
        metadata: {'category': 'golf', 'tournament': entry.key},
      ));
    }

    return folders;
  }

  /// Build all golf theme palette nodes from GolfThemesDatabase
  static List<LibraryNode> getGolfPaletteNodes() {
    final nodes = <LibraryNode>[];

    // Group themes by folder
    final themesByFolder = <String, List<GolfTheme>>{};
    for (final theme in GolfThemesDatabase.allThemes) {
      themesByFolder.putIfAbsent(theme.folder, () => []).add(theme);
    }

    // Create palette nodes for each theme
    for (final entry in themesByFolder.entries) {
      final folderId = entry.key;
      final themes = entry.value;

      for (var i = 0; i < themes.length; i++) {
        final theme = themes[i];

        nodes.add(LibraryNode(
          id: theme.id,
          name: theme.name,
          description: theme.description,
          nodeType: LibraryNodeType.palette,
          parentId: folderId,
          themeColors: theme.colors,
          sortOrder: i,
          metadata: {
            'category': 'golf',
            'folder': folderId,
            'keywords': theme.keywords,
            'suggestedEffects': [12, 41, 2, 0], // Theater Chase, Running, Breathe, Solid
            'defaultSpeed': 100,
            'defaultIntensity': 150,
          },
        ));
      }
    }

    return nodes;
  }

  /// Build the complete golf hierarchy
  static List<LibraryNode> buildFullGolfHierarchy() {
    final nodes = <LibraryNode>[];

    // Main golf folder
    nodes.add(getGolfMainFolder());

    // Tournament/theme subfolders
    nodes.addAll(getGolfSubfolders());

    // Individual palettes
    nodes.addAll(getGolfPaletteNodes());

    return nodes;
  }

  /// Get themes for a specific folder/tournament
  static List<LibraryNode> getThemesForFolder(String folderId) {
    final nodes = getGolfPaletteNodes();
    return nodes.where((n) => n.parentId == folderId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// Search golf themes
  static List<LibraryNode> searchGolfThemes(String query) {
    final lowercaseQuery = query.toLowerCase();
    final allPalettes = getGolfPaletteNodes();

    return allPalettes.where((node) {
      final name = node.name.toLowerCase();
      final description = node.description?.toLowerCase() ?? '';
      final keywords = (node.metadata?['keywords'] as List<dynamic>?)
          ?.map((k) => k.toString().toLowerCase())
          .toList() ?? [];

      return name.contains(lowercaseQuery) ||
             description.contains(lowercaseQuery) ||
             keywords.any((k) => k.contains(lowercaseQuery));
    }).toList();
  }
}

/// Helper class for folder info
class _FolderInfo {
  final String name;
  final String description;
  final int sortOrder;

  const _FolderInfo({
    required this.name,
    required this.description,
    required this.sortOrder,
  });
}
