import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/dashboard/main_scaffold.dart' show showDemoExitSheet;
import 'package:nexgen_command/features/wled/effect_preview_widget.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/effect_mood_system.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/wled/pattern_explore_screen.dart' show executeCustomEffectIfNeeded;
import 'package:nexgen_command/features/game_day/live_scoring_prompt.dart';
import 'package:nexgen_command/features/explore_patterns/ui/explore_design_system.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/widgets/effect_speed_slider.dart';

/// Grid of library nodes (categories, folders, or palettes)
class LibraryNodeGrid extends StatelessWidget {
  final List<LibraryNode> children;
  final Color? parentAccent;
  final List<Color>? parentGradient;
  /// Override the default folder card aspect ratio (width / height).
  /// Higher values produce shorter cards.
  final double? folderAspectRatio;

  const LibraryNodeGrid({super.key, required this.children, this.parentAccent, this.parentGradient, this.folderAspectRatio});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return Center(
        child: Text(
          'No items found',
          style: TextStyle(color: NexGenPalette.textSecondary),
        ),
      );
    }

    // Detect if this grid is mostly palettes (e.g. architectural temp
    // folder with spacing palettes + one Brightness Gradients folder).
    // Use a compact single-column list for these mixed cases too.
    final mostlyPalettes = children.where((n) => n.isPalette).length >
        children.length / 2;

    if (mostlyPalettes) {
      return ListView.builder(
        padding: EdgeInsets.only(left: 16, top: 16, right: 16, bottom: navBarTotalHeight(context)),
        itemCount: children.length,
        itemBuilder: (context, index) {
          final node = children[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 44,
              child: LibraryNodeCard(node: node, index: index, parentAccent: parentAccent, parentGradient: parentGradient),
            ),
          );
        },
      );
    }

    // Folders: 2-column grid with hero cards
    return GridView.builder(
      padding: EdgeInsets.only(left: 16, top: 16, right: 16, bottom: navBarTotalHeight(context)),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: folderAspectRatio ?? 1.4,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) {
        final node = children[index];
        return LibraryNodeCard(node: node, index: index, parentAccent: parentAccent, parentGradient: parentGradient);
      },
    );
  }
}

/// Individual node card for navigation
class LibraryNodeCard extends StatelessWidget {
  final LibraryNode node;
  final int? index;
  final Color? parentAccent;
  final List<Color>? parentGradient;

  const LibraryNodeCard({super.key, required this.node, this.index, this.parentAccent, this.parentGradient});

  IconData _iconForNode() {
    final id = node.id;

    // Category icons
    if (id.startsWith('cat_')) {
      switch (id) {
        case LibraryCategoryIds.architectural:
          return Icons.home_outlined;
        case LibraryCategoryIds.holidays:
          return Icons.celebration_outlined;
        case LibraryCategoryIds.sports:
          return Icons.sports_football_outlined;
        case LibraryCategoryIds.seasonal:
          return Icons.wb_sunny_outlined;
        case LibraryCategoryIds.parties:
          return Icons.party_mode_outlined;
        case LibraryCategoryIds.security:
          return Icons.security_outlined;
        case LibraryCategoryIds.movies:
          return Icons.movie_outlined;
      }
    }

    // Sports folders
    if (id == 'league_soccer' || id == 'league_mls' || id == 'league_nwsl' ||
        id == 'league_epl' || id == 'league_la_liga' || id == 'league_bundesliga' ||
        id == 'league_serie_a' || id == 'league_champions_league' ||
        id == 'league_fifa_world_cup') return Icons.sports_soccer;
    if (id.startsWith('league_')) return Icons.sports;
    if (id.contains('ncaa')) return Icons.school_outlined;
    if (id.startsWith('conf_')) return Icons.groups_outlined;

    // Holiday/seasonal folders
    if (id.startsWith('holiday_')) return Icons.celebration;
    if (id.startsWith('season_')) return Icons.nature_outlined;
    if (id.startsWith('event_')) return Icons.event_outlined;

    // Architectural Kelvin folders
    if (id.startsWith('arch_k')) return Icons.thermostat_outlined;
    if (id == 'arch_galaxy') return Icons.auto_awesome_outlined;

    // Movie franchise folders
    if (id == 'franchise_disney') return Icons.castle_outlined;
    if (id == 'franchise_marvel') return Icons.shield_outlined;
    if (id == 'franchise_starwars') return Icons.star_outlined;
    if (id == 'franchise_dc') return Icons.bolt_outlined;
    if (id == 'franchise_pixar') return Icons.animation_outlined;
    if (id == 'franchise_dreamworks') return Icons.movie_filter_outlined;
    if (id == 'franchise_harrypotter') return Icons.auto_fix_high_outlined;
    if (id == 'franchise_nintendo') return Icons.videogame_asset_outlined;

    // Inherit icon from parentId when direct ID doesn't match
    final pid = node.parentId;
    if (pid != null) {
      if (pid.startsWith('holiday_')) return Icons.celebration;
      if (pid.startsWith('season_')) return Icons.nature_outlined;
      if (pid.startsWith('event_')) return Icons.event_outlined;
      if (pid.startsWith('league_')) return Icons.sports;
      if (pid.startsWith('franchise_')) return Icons.movie_outlined;
      if (pid.contains('ncaa') || pid.startsWith('conf_')) return Icons.school_outlined;
      if (pid.startsWith('arch_')) return Icons.thermostat_outlined;
      if (pid == LibraryCategoryIds.holidays) return Icons.celebration;
      if (pid == LibraryCategoryIds.sports) return Icons.sports_football_outlined;
      if (pid == LibraryCategoryIds.seasonal) return Icons.wb_sunny_outlined;
      if (pid == LibraryCategoryIds.parties) return Icons.party_mode_outlined;
      if (pid == LibraryCategoryIds.architectural) return Icons.home_outlined;
      if (pid == LibraryCategoryIds.security) return Icons.security_outlined;
      if (pid == LibraryCategoryIds.movies) return Icons.movie_outlined;
    }

    // Default based on node type
    if (node.isPalette) return Icons.palette_outlined;
    return Icons.folder_outlined;
  }

  /// Get themed color for folder nodes (static, not flowing gradient)
  Color _getFolderThemeColor() {
    final id = node.id;

    // Category colors
    if (id == LibraryCategoryIds.architectural) return const Color(0xFFFF8C00);
    if (id == LibraryCategoryIds.holidays) return const Color(0xFFE53935);
    if (id == LibraryCategoryIds.sports) return const Color(0xFF1976D2);
    if (id == LibraryCategoryIds.seasonal) return const Color(0xFFE65100);
    if (id == LibraryCategoryIds.parties) return const Color(0xFF9C27B0);
    if (id == LibraryCategoryIds.security) return const Color(0xFFD32F2F);
    if (id == LibraryCategoryIds.movies) return const Color(0xFF6A1B9A);

    // Movie franchise colors
    if (id == 'franchise_disney') return const Color(0xFF1E88E5);
    if (id == 'franchise_marvel') return const Color(0xFFB71C1C);
    if (id == 'franchise_starwars') return const Color(0xFF212121);
    if (id == 'franchise_dc') return const Color(0xFF0D47A1);
    if (id == 'franchise_pixar') return const Color(0xFF43A047);
    if (id == 'franchise_dreamworks') return const Color(0xFF00838F);
    if (id == 'franchise_harrypotter') return const Color(0xFF5D4037);
    if (id == 'franchise_nintendo') return const Color(0xFFE53935);

    // Sports league colors
    if (id == 'league_nfl') return const Color(0xFF013369);
    if (id == 'league_nba') return const Color(0xFFC9082A);
    if (id == 'league_mlb') return const Color(0xFF041E42);
    if (id == 'league_nhl') return const Color(0xFF000000);
    if (id == 'league_mls') return const Color(0xFF005293);
    if (id == 'league_wnba') return const Color(0xFFFF6F00);
    if (id == 'league_nwsl') return const Color(0xFF00A3AD);
    if (id == 'league_soccer') return const Color(0xFF00D4FF);
    if (id == 'league_epl') return const Color(0xFF3D195B);
    if (id == 'league_la_liga') return const Color(0xFFFF6B35);
    if (id == 'league_bundesliga') return const Color(0xFFD4020D);
    if (id == 'league_serie_a') return const Color(0xFF1B4FBB);
    if (id == 'league_champions_league') return const Color(0xFF0D47A1);
    if (id == 'league_fifa_world_cup') return const Color(0xFFD4AF37);

    // Holiday colors
    if (id == 'holiday_christmas') return const Color(0xFFC62828);
    if (id == 'holiday_halloween') return const Color(0xFFFF6F00);
    if (id == 'holiday_july4' || id == 'holiday_july4th') return const Color(0xFF1565C0);
    if (id == 'holiday_valentines') return const Color(0xFFD81B60);
    if (id == 'holiday_stpatricks') return const Color(0xFF2E7D32);
    if (id == 'holiday_easter') return const Color(0xFF7B1FA2);
    if (id == 'holiday_thanksgiving') return const Color(0xFFE65100);
    if (id == 'holiday_newyears' || id == 'holiday_newyear') return const Color(0xFFFFD700);

    // Season colors
    if (id == 'season_spring') return const Color(0xFF4CAF50);
    if (id == 'season_summer') return const Color(0xFFFFC107);
    if (id == 'season_autumn') return const Color(0xFFFF5722);
    if (id == 'season_winter') return const Color(0xFF03A9F4);

    // NCAA Football conference colors
    if (id.startsWith('ncaafb_')) return const Color(0xFF8B0000);
    // NCAA Basketball conference colors
    if (id.startsWith('ncaabb_')) return const Color(0xFFFF6F00);
    // NCAA parent folder colors
    if (id.startsWith('ncaa_') || id.startsWith('conf_')) return const Color(0xFF1A237E);

    // Architectural Kelvin folders -- use the warm end of the node's theme
    // but enforce a minimum saturation so higher-K folders stay visible.
    if (id.startsWith('arch_') && node.themeColors != null && node.themeColors!.isNotEmpty) {
      final c = node.themeColors!.first;
      final hsl = HSLColor.fromColor(c);
      if (hsl.saturation < 0.35) {
        // Cool/daylight whites are too desaturated — boost saturation
        return hsl.withSaturation(0.55).withLightness(hsl.lightness.clamp(0, 0.7)).toColor();
      }
      return c;
    }

    // Inherit color from parentId when direct ID doesn't match
    final pid = node.parentId;
    if (pid != null) {
      final parentColor = _colorForKnownId(pid);
      if (parentColor != null) return parentColor;
    }

    // Use parent accent passed from route navigation as final fallback
    if (parentAccent != null) return parentAccent!;

    return NexGenPalette.cyan;
  }

  /// Look up a known ID in the color table. Returns null if not found.
  static Color? _colorForKnownId(String id) {
    if (id == LibraryCategoryIds.architectural) return const Color(0xFFFF8C00);
    if (id == LibraryCategoryIds.holidays) return const Color(0xFFE53935);
    if (id == LibraryCategoryIds.sports) return const Color(0xFF1976D2);
    if (id == LibraryCategoryIds.seasonal) return const Color(0xFFE65100);
    if (id == LibraryCategoryIds.parties) return const Color(0xFF9C27B0);
    if (id == LibraryCategoryIds.security) return const Color(0xFFD32F2F);
    if (id == LibraryCategoryIds.movies) return const Color(0xFF6A1B9A);
    if (id == 'holiday_christmas') return const Color(0xFFC62828);
    if (id == 'holiday_halloween') return const Color(0xFFFF6F00);
    if (id == 'holiday_july4' || id == 'holiday_july4th') return const Color(0xFF1565C0);
    if (id == 'holiday_valentines') return const Color(0xFFD81B60);
    if (id == 'holiday_stpatricks') return const Color(0xFF2E7D32);
    if (id == 'holiday_easter') return const Color(0xFF7B1FA2);
    if (id == 'holiday_thanksgiving') return const Color(0xFFE65100);
    if (id == 'holiday_newyears' || id == 'holiday_newyear') return const Color(0xFFFFD700);
    if (id == 'season_spring') return const Color(0xFF4CAF50);
    if (id == 'season_summer') return const Color(0xFFFFC107);
    if (id == 'season_autumn') return const Color(0xFFFF5722);
    if (id == 'season_winter') return const Color(0xFF03A9F4);
    if (id == 'league_soccer') return const Color(0xFF00D4FF);
    if (id == 'league_epl') return const Color(0xFF3D195B);
    if (id == 'league_la_liga') return const Color(0xFFFF6B35);
    if (id == 'league_bundesliga') return const Color(0xFFD4020D);
    if (id == 'league_serie_a') return const Color(0xFF1B4FBB);
    if (id == 'league_champions_league') return const Color(0xFF0D47A1);
    if (id == 'league_fifa_world_cup') return const Color(0xFFD4AF37);
    if (id == 'league_mls') return const Color(0xFF005293);
    if (id == 'league_nwsl') return const Color(0xFF00A3AD);
    if (id.startsWith('league_')) return const Color(0xFF1976D2);
    if (id.startsWith('franchise_')) return const Color(0xFF6A1B9A);
    if (id.startsWith('ncaa') || id.startsWith('conf_')) return const Color(0xFF1A237E);
    if (id.startsWith('event_')) return const Color(0xFF9C27B0);
    return null;
  }

  /// Get gradient color pair for folder nodes, matching the visual style
  /// used by _DesignLibraryCategoryCard and _SubCategoryCard.
  List<Color> _getGradientForNode() {
    final id = node.id;

    // Category gradients (matching _DesignLibraryCategoryCard)
    if (id == LibraryCategoryIds.architectural) return const [Color(0xFFFFB347), Color(0xFFFF7043)];
    if (id == LibraryCategoryIds.holidays) return const [Color(0xFFFF4444), Color(0xFFC2185B)];
    if (id == LibraryCategoryIds.sports) return const [Color(0xFF1976D2), Color(0xFF0D47A1)];
    if (id == LibraryCategoryIds.seasonal) return const [Color(0xFFFF8F00), Color(0xFFE65100)];
    if (id == LibraryCategoryIds.parties) return const [Color(0xFFFF69B4), Color(0xFF9C27B0)];
    if (id == LibraryCategoryIds.security) return const [Color(0xFF4FC3F7), Color(0xFF1565C0)];
    if (id == LibraryCategoryIds.movies) return const [Color(0xFFE040FB), Color(0xFF6A1B9A)];

    // Movie franchise gradients
    if (id == 'franchise_disney') return const [Color(0xFF42A5F5), Color(0xFF1565C0)];
    if (id == 'franchise_marvel') return const [Color(0xFFE53935), Color(0xFFB71C1C)];
    if (id == 'franchise_starwars') return const [Color(0xFF546E7A), Color(0xFF212121)];
    if (id == 'franchise_dc') return const [Color(0xFF1E88E5), Color(0xFF0D47A1)];
    if (id == 'franchise_pixar') return const [Color(0xFF66BB6A), Color(0xFF2E7D32)];
    if (id == 'franchise_dreamworks') return const [Color(0xFF26C6DA), Color(0xFF00695C)];
    if (id == 'franchise_harrypotter') return const [Color(0xFF8D6E63), Color(0xFF3E2723)];
    if (id == 'franchise_nintendo') return const [Color(0xFFEF5350), Color(0xFFB71C1C)];

    // Sports league gradients
    if (id == 'league_nfl') return const [Color(0xFF1565C0), Color(0xFF013369)];
    if (id == 'league_nba') return const [Color(0xFFE53935), Color(0xFF880E4F)];
    if (id == 'league_mlb') return const [Color(0xFF1976D2), Color(0xFF041E42)];
    if (id == 'league_nhl') return const [Color(0xFF424242), Color(0xFF000000)];
    if (id == 'league_mls') return const [Color(0xFF005293), Color(0xFF003060)];
    if (id == 'league_wnba') return const [Color(0xFFFF8F00), Color(0xFFE65100)];
    if (id == 'league_nwsl') return const [Color(0xFF00A3AD), Color(0xFF006D75)];
    if (id == 'league_soccer') return const [Color(0xFF00D4FF), Color(0xFF0088AA)];
    if (id == 'league_epl') return const [Color(0xFF3D195B), Color(0xFF280E3B)];
    if (id == 'league_la_liga') return const [Color(0xFFFF6B35), Color(0xFFCC4400)];
    if (id == 'league_bundesliga') return const [Color(0xFFD4020D), Color(0xFF8B0000)];
    if (id == 'league_serie_a') return const [Color(0xFF1B4FBB), Color(0xFF0D2D6B)];
    if (id == 'league_champions_league') return const [Color(0xFF0D47A1), Color(0xFF1A237E)];
    if (id == 'league_fifa_world_cup') return const [Color(0xFFD4AF37), Color(0xFF1565C0)];

    // Holiday gradients (matching _SubCategoryCard)
    if (id == 'holiday_christmas') return const [Color(0xFF2E7D32), Color(0xFFC62828)];
    if (id == 'holiday_halloween') return const [Color(0xFFFF6D00), Color(0xFF6A1B9A)];
    if (id == 'holiday_july4' || id == 'holiday_july4th') return const [Color(0xFFEF5350), Color(0xFF1565C0)];
    if (id == 'holiday_valentines') return const [Color(0xFFE91E63), Color(0xFFAD1457)];
    if (id == 'holiday_stpatricks') return const [Color(0xFF43A047), Color(0xFF00C853)];
    if (id == 'holiday_easter') return const [Color(0xFFCE93D8), Color(0xFF7B1FA2)];
    if (id == 'holiday_thanksgiving') return const [Color(0xFFFF9800), Color(0xFF8D6E63)];
    if (id == 'holiday_newyears' || id == 'holiday_newyear') return const [Color(0xFFFFD700), Color(0xFFFF6F00)];

    // Season gradients (matching _SubCategoryCard)
    if (id == 'season_spring') return const [Color(0xFF81C784), Color(0xFFF48FB1)];
    if (id == 'season_summer') return const [Color(0xFFFFEE58), Color(0xFF29B6F6)];
    if (id == 'season_autumn') return const [Color(0xFFFF8F00), Color(0xFF6D4C41)];
    if (id == 'season_winter') return const [Color(0xFF81D4FA), Color(0xFF7E57C2)];

    // Party/event gradients
    if (id == 'event_birthdays' || id == 'event_birthday') return const [Color(0xFF00E5FF), Color(0xFFFF4081)];
    if (id == 'event_bday_boy') return const [Color(0xFF42A5F5), Color(0xFF1565C0)];
    if (id == 'event_bday_girl') return const [Color(0xFFFF80AB), Color(0xFFAD1457)];
    if (id == 'event_bday_adult') return const [Color(0xFFFFD54F), Color(0xFFFF6F00)];
    if (id == 'event_weddings' || id == 'event_wedding') return const [Color(0xFFFFE0B2), Color(0xFFBCAAA4)];
    if (id == 'event_babyshower') return const [Color(0xFF80DEEA), Color(0xFFF8BBD0)];
    if (id == 'event_graduation') return const [Color(0xFF212121), Color(0xFFFFD700)];
    if (id == 'event_anniversary') return const [Color(0xFFFFD700), Color(0xFFE91E63)];

    // NCAA / Conference folders
    if (id.startsWith('ncaafb_')) return const [Color(0xFFB71C1C), Color(0xFF8B0000)];
    if (id.startsWith('ncaabb_')) return const [Color(0xFFFF8F00), Color(0xFFE65100)];
    if (id.startsWith('ncaa_') || id.startsWith('conf_')) return const [Color(0xFF3949AB), Color(0xFF1A237E)];

    // Architectural Kelvin folders -- use the node's own theme colors but
    // boost saturation for higher-K temperatures so the card gradient is visible.
    if (id.startsWith('arch_') && node.themeColors != null && node.themeColors!.length >= 2) {
      Color boost(Color c) {
        final hsl = HSLColor.fromColor(c);
        if (hsl.saturation < 0.35) {
          return hsl.withSaturation(0.50).withLightness(hsl.lightness.clamp(0, 0.75)).toColor();
        }
        return c;
      }
      return [boost(node.themeColors![0]), boost(node.themeColors![1])];
    }

    // Inherit gradient from parentId when direct ID doesn't match
    final pid = node.parentId;
    if (pid != null) {
      final parentGrad = _gradientForKnownId(pid);
      if (parentGrad != null) return parentGrad;
    }

    // Use parent gradient passed from route navigation as final fallback
    if (parentGradient != null && parentGradient!.length >= 2) return parentGradient!;

    // Default: derive from theme color
    final c = _getFolderThemeColor();
    return [c, c.withValues(alpha: 0.5)];
  }

  /// Look up a known ID in the gradient table. Returns null if not found.
  static List<Color>? _gradientForKnownId(String id) {
    // Categories
    if (id == LibraryCategoryIds.architectural) return const [Color(0xFFFFB347), Color(0xFFFF7043)];
    if (id == LibraryCategoryIds.holidays) return const [Color(0xFFFF4444), Color(0xFFC2185B)];
    if (id == LibraryCategoryIds.sports) return const [Color(0xFF1976D2), Color(0xFF0D47A1)];
    if (id == LibraryCategoryIds.seasonal) return const [Color(0xFFFF8F00), Color(0xFFE65100)];
    if (id == LibraryCategoryIds.parties) return const [Color(0xFFFF69B4), Color(0xFF9C27B0)];
    if (id == LibraryCategoryIds.security) return const [Color(0xFF4FC3F7), Color(0xFF1565C0)];
    if (id == LibraryCategoryIds.movies) return const [Color(0xFFE040FB), Color(0xFF6A1B9A)];
    // Holidays
    if (id == 'holiday_christmas') return const [Color(0xFF2E7D32), Color(0xFFC62828)];
    if (id == 'holiday_halloween') return const [Color(0xFFFF6D00), Color(0xFF6A1B9A)];
    if (id == 'holiday_july4' || id == 'holiday_july4th') return const [Color(0xFFEF5350), Color(0xFF1565C0)];
    if (id == 'holiday_valentines') return const [Color(0xFFE91E63), Color(0xFFAD1457)];
    if (id == 'holiday_stpatricks') return const [Color(0xFF43A047), Color(0xFF00C853)];
    if (id == 'holiday_easter') return const [Color(0xFFCE93D8), Color(0xFF7B1FA2)];
    if (id == 'holiday_thanksgiving') return const [Color(0xFFFF9800), Color(0xFF8D6E63)];
    if (id == 'holiday_newyears' || id == 'holiday_newyear') return const [Color(0xFFFFD700), Color(0xFFFF6F00)];
    // Seasons
    if (id == 'season_spring') return const [Color(0xFF81C784), Color(0xFFF48FB1)];
    if (id == 'season_summer') return const [Color(0xFFFFEE58), Color(0xFF29B6F6)];
    if (id == 'season_autumn') return const [Color(0xFFFF8F00), Color(0xFF6D4C41)];
    if (id == 'season_winter') return const [Color(0xFF81D4FA), Color(0xFF7E57C2)];
    // Events
    if (id.startsWith('event_')) return const [Color(0xFFFF69B4), Color(0xFF9C27B0)];
    // Sports
    if (id == 'league_nfl') return const [Color(0xFF1565C0), Color(0xFF013369)];
    if (id == 'league_nba') return const [Color(0xFFE53935), Color(0xFF880E4F)];
    if (id == 'league_mlb') return const [Color(0xFF1976D2), Color(0xFF041E42)];
    if (id == 'league_nhl') return const [Color(0xFF424242), Color(0xFF000000)];
    if (id == 'league_mls') return const [Color(0xFF005293), Color(0xFF003060)];
    if (id == 'league_wnba') return const [Color(0xFFFF8F00), Color(0xFFE65100)];
    if (id == 'league_nwsl') return const [Color(0xFF00A3AD), Color(0xFF006D75)];
    if (id == 'league_soccer') return const [Color(0xFF00D4FF), Color(0xFF0088AA)];
    if (id == 'league_epl') return const [Color(0xFF3D195B), Color(0xFF280E3B)];
    if (id == 'league_la_liga') return const [Color(0xFFFF6B35), Color(0xFFCC4400)];
    if (id == 'league_bundesliga') return const [Color(0xFFD4020D), Color(0xFF8B0000)];
    if (id == 'league_serie_a') return const [Color(0xFF1B4FBB), Color(0xFF0D2D6B)];
    if (id == 'league_champions_league') return const [Color(0xFF0D47A1), Color(0xFF1A237E)];
    if (id == 'league_fifa_world_cup') return const [Color(0xFFD4AF37), Color(0xFF1565C0)];
    if (id.startsWith('league_')) return const [Color(0xFF1976D2), Color(0xFF0D47A1)];
    // Franchises
    if (id.startsWith('franchise_')) return const [Color(0xFFE040FB), Color(0xFF6A1B9A)];
    // NCAA
    if (id.startsWith('ncaa') || id.startsWith('conf_')) return const [Color(0xFF3949AB), Color(0xFF1A237E)];
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Palettes get color-dominant cards, folders get solid themed cards
    if (node.isPalette) {
      // Only animate the first 8 visible palette cards
      final shouldAnimate = index == null || index! < 8;
      return _buildPaletteCard(context, animate: shouldAnimate);
    } else if (node.parentId != null && node.parentId!.startsWith('arch_k')) {
      // Compact folder card inside architectural temperature folders
      return _buildCompactFolderCard(context);
    } else {
      return _buildFolderCard(context);
    }
  }

  /// Compact folder card for architectural sub-folders (e.g. Brightness Gradients
  /// inside a Kelvin temperature folder). Renders as a row matching palette cards,
  /// with an 8-dot gradient preview fading from full to ~30% brightness.
  Widget _buildCompactFolderCard(BuildContext context) {
    final accentColor = _getFolderThemeColor();
    final icon = _iconForNode();
    final colors = node.themeColors;
    final baseColor = (colors != null && colors.isNotEmpty) ? colors.first : accentColor;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push('/explore/library/${node.id}', extra: {
            'name': node.name,
            'accentColor': accentColor.toARGB32(),
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: NexGenPalette.matteBlack,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                accentColor.withValues(alpha: 0.12),
                NexGenPalette.matteBlack,
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accentColor.withValues(alpha: 0.30), width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                // 8-dot gradient preview: full → dim → full
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(8, (i) {
                    // Smooth fade: 1.0, 0.9, 0.7, 0.45, 0.3, 0.45, 0.7, 0.9
                    const levels = [1.0, 0.9, 0.7, 0.45, 0.3, 0.45, 0.7, 0.9];
                    final level = levels[i];
                    final r = ((baseColor.r * 255).round() * level).round().clamp(0, 255);
                    final g = ((baseColor.g * 255).round() * level).round().clamp(0, 255);
                    final b = ((baseColor.b * 255).round() * level).round().clamp(0, 255);
                    return Container(
                      width: 8,
                      height: 8,
                      margin: EdgeInsets.only(right: i < 7 ? 3 : 0),
                      decoration: BoxDecoration(
                        color: Color.fromARGB(255, r, g, b),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 14, color: accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: accentColor.withValues(alpha: 0.5), size: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build a subfolder card with gradient background, glow orb, icon, and pixel strip
  Widget _buildFolderCard(BuildContext context) {
    final gradientColors = _getGradientForNode();
    final accentColor = _getFolderThemeColor();
    final icon = _iconForNode();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push('/explore/library/${node.id}', extra: {
            'name': node.name,
            'accentColor': accentColor.toARGB32(),
            'gradient0': gradientColors[0].toARGB32(),
            'gradient1': gradientColors[1].toARGB32(),
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                gradientColors[0].withValues(alpha: 0.3),
                gradientColors[1].withValues(alpha: 0.15),
                NexGenPalette.matteBlack.withValues(alpha: 0.95),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: gradientColors[0].withValues(alpha: 0.15),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Glow orb — top-right
              Positioned(
                top: -10,
                right: -10,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        gradientColors[0].withValues(alpha: 0.25),
                        gradientColors[1].withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon with glow
                    Icon(
                      icon,
                      size: 28,
                      color: Colors.white,
                      shadows: [
                        Shadow(color: accentColor.withValues(alpha: 0.7), blurRadius: 18),
                        Shadow(color: gradientColors[0].withValues(alpha: 0.4), blurRadius: 10),
                      ],
                    ),
                    const Spacer(),
                    // Color gradient bar
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: LinearGradient(
                          colors: gradientColors,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Name
                    Text(
                      node.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          'Tap to explore',
                          style: TextStyle(
                            color: accentColor.withValues(alpha: 0.6),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.arrow_forward_ios, color: accentColor.withValues(alpha: 0.5), size: 8),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a palette card with LED-pattern dot indicators
  Widget _buildPaletteCard(BuildContext context, {bool animate = true}) {
    final colors = node.themeColors;
    final hasColors = colors != null && colors.isNotEmpty;
    final primaryColor = hasColors ? colors.first : NexGenPalette.cyan;

    // Determine on/off dot pattern from architectural metadata
    final grouping = node.metadata?['grouping'] as int?;
    final spacing = node.metadata?['spacing'] as int?;
    final hasSpacing = grouping != null && spacing != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push('/explore/library/${node.id}', extra: {
            'name': node.name,
            'accentColor': primaryColor.toARGB32(),
            'gradient0': primaryColor.toARGB32(),
            'gradient1': (hasColors && colors.length > 1 ? colors[1] : primaryColor).withValues(alpha: 0.6).toARGB32(),
          });
        },
        borderRadius: BorderRadius.circular(10),
        splashColor: primaryColor.withValues(alpha: 0.08),
        highlightColor: primaryColor.withValues(alpha: 0.04),
        child: Container(
          decoration: BoxDecoration(
            color: NexGenPalette.matteBlack,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                primaryColor.withValues(alpha: 0.08),
                NexGenPalette.matteBlack,
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.20),
              width: 0.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                // LED dot preview — 8 dots showing the on/off pattern
                if (hasSpacing) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(8, (i) {
                      final cycle = grouping + spacing;
                      final lit = cycle == 0 || spacing == 0 || (i % cycle) < grouping;
                      return Container(
                        width: 8,
                        height: 8,
                        margin: EdgeInsets.only(right: i < 7 ? 3 : 0),
                        decoration: BoxDecoration(
                          color: lit
                              ? primaryColor
                              : primaryColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(width: 10),
                ] else if (hasColors) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < (colors.length <= 4 ? colors.length : 4); i++)
                        Container(
                          width: 8,
                          height: 8,
                          margin: EdgeInsets.only(right: i < 3 ? 3 : 0),
                          decoration: BoxDecoration(
                            color: colors[i],
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  const Icon(Icons.palette_outlined, color: Colors.white24, size: 14),
                  const SizedBox(width: 10),
                ],
                // Palette name
                Expanded(
                  child: Text(
                    node.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: primaryColor.withValues(alpha: 0.4),
                  size: 10,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Grid of patterns generated from a palette node with mood filter
class PalettePatternGrid extends ConsumerWidget {
  final LibraryNode node;

  const PalettePatternGrid({super.key, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch mood filter and filtered patterns
    final selectedMood = ref.watch(selectedMoodFilterProvider);
    final patternsAsync = ref.watch(filteredLibraryNodePatternsProvider(node.id));
    final moodCountsAsync = ref.watch(nodeMoodCountsProvider(node.id));

    return patternsAsync.when(
      data: (patterns) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Palette preview header
            if (node.themeColors != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Color Palette:',
                      style: TextStyle(
                        color: NexGenPalette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    for (final color in node.themeColors!)
                      Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: NexGenPalette.line),
                        ),
                      ),
                  ],
                ),
              ),
            // Mood filter bar
            MoodFilterBar(
              selectedMood: selectedMood,
              moodCounts: moodCountsAsync.valueOrNull ?? {},
              onMoodSelected: (mood) {
                ref.read(selectedMoodFilterProvider.notifier).state = mood;
              },
            ),
            // Pattern count (updates based on filter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                selectedMood != null
                    ? '${patterns.length} ${selectedMood.label} Patterns'
                    : '${patterns.length} Patterns',
                style: TextStyle(
                  color: NexGenPalette.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Pattern grid or empty state
            Expanded(
              child: patterns.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            selectedMood?.icon ?? Icons.pattern,
                            size: 48,
                            color: NexGenPalette.textSecondary.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            selectedMood != null
                                ? 'No ${selectedMood.label} patterns available'
                                : 'No patterns available',
                            style: TextStyle(color: NexGenPalette.textSecondary),
                          ),
                          if (selectedMood != null) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                ref.read(selectedMoodFilterProvider.notifier).state = null;
                              },
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 56),
                                textStyle: const TextStyle(fontSize: 15),
                              ),
                              child: const Text('Show All Patterns'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.only(left: 12, top: 12, right: 12, bottom: navBarTotalHeight(context)),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: patterns.length,
                      itemBuilder: (context, index) {
                        final pattern = patterns[index];
                        return PatternCard(pattern: pattern);
                      },
                    ),
            ),
          ],
        );
      },
      loading: () => const ExploreShimmerGrid(crossAxisCount: 4, itemCount: 8, childAspectRatio: 0.85),
      error: (_, __) => Center(
        child: Text(
          'Unable to load patterns',
          style: TextStyle(color: NexGenPalette.textSecondary),
        ),
      ),
    );
  }
}

/// Mood filter bar with horizontally scrollable chips
class MoodFilterBar extends StatelessWidget {
  final EffectMood? selectedMood;
  final Map<EffectMood, int> moodCounts;
  final ValueChanged<EffectMood?> onMoodSelected;

  const MoodFilterBar({
    super.key,
    required this.selectedMood,
    required this.moodCounts,
    required this.onMoodSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            // "All" chip
            _MoodChip(
              label: 'All',
              emoji: '',
              isSelected: selectedMood == null,
              count: moodCounts.values.fold(0, (a, b) => a + b),
              onTap: () => onMoodSelected(null),
            ),
            const SizedBox(width: 8),
            // Mood chips
            for (final mood in EffectMoodSystem.displayOrder) ...[
              _MoodChip(
                label: mood.label,
                emoji: mood.emoji,
                isSelected: selectedMood == mood,
                count: moodCounts[mood] ?? 0,
                color: mood.color,
                onTap: () => onMoodSelected(selectedMood == mood ? null : mood),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Individual mood filter chip
class _MoodChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool isSelected;
  final int count;
  final Color? color;
  final VoidCallback onTap;

  const _MoodChip({
    required this.label,
    required this.emoji,
    required this.isSelected,
    required this.count,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? NexGenPalette.cyan;

    return GestureDetector(
      onTap: count > 0 || isSelected ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha: 0.2)
              : NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? chipColor : NexGenPalette.line,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji.isNotEmpty) ...[
              Text(emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? chipColor : (count > 0 ? Colors.white : NexGenPalette.textSecondary),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? chipColor.withValues(alpha: 0.3)
                      : NexGenPalette.gunmetal,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? chipColor : NexGenPalette.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Global mood selector for the main Explore page.
/// Allows users to pre-filter patterns by mood before navigating into categories.
/// The selection persists when navigating to color cards.
class GlobalMoodSelector extends StatelessWidget {
  final EffectMood? selectedMood;
  final ValueChanged<EffectMood?> onMoodSelected;

  const GlobalMoodSelector({
    super.key,
    required this.selectedMood,
    required this.onMoodSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tune, size: 16, color: NexGenPalette.textSecondary),
            const SizedBox(width: 6),
            Text(
              'Pre-filter by mood',
              style: TextStyle(
                color: NexGenPalette.textSecondary,
                fontSize: 12,
              ),
            ),
            if (selectedMood != null) ...[
              const Spacer(),
              GestureDetector(
                onTap: () => onMoodSelected(null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Clear filter',
                        style: TextStyle(
                          color: NexGenPalette.cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.close, size: 12, color: NexGenPalette.cyan),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // "All" chip (no filter)
              _GlobalMoodChip(
                label: 'All Moods',
                emoji: '',
                isSelected: selectedMood == null,
                color: NexGenPalette.cyan,
                onTap: () => onMoodSelected(null),
              ),
              const SizedBox(width: 8),
              // Mood chips
              for (final mood in EffectMoodSystem.displayOrder) ...[
                _GlobalMoodChip(
                  label: mood.label,
                  emoji: mood.emoji,
                  isSelected: selectedMood == mood,
                  color: mood.color,
                  onTap: () => onMoodSelected(selectedMood == mood ? null : mood),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact mood chip for the global mood selector
class _GlobalMoodChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _GlobalMoodChip({
    required this.label,
    required this.emoji,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : NexGenPalette.line,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji.isNotEmpty) ...[
              Text(emoji, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual pattern card with apply action
class PatternCard extends ConsumerStatefulWidget {
  final PatternItem pattern;

  const PatternCard({super.key, required this.pattern});

  @override
  ConsumerState<PatternCard> createState() => _PatternCardState();
}

class _PatternCardState extends ConsumerState<PatternCard> {
  /// Indices into the original `_getColors()` list that the user has left
  /// active. Default: every color active. State is local to this card —
  /// never persisted, never mutates `widget.pattern.wledPayload`.
  late Set<int> _activeColorIndices;

  /// Block width for the WLED `grp` field at apply time. Range 1–10.
  int _ledsPerColor = 1;

  @override
  void initState() {
    super.initState();
    _activeColorIndices = {for (var i = 0; i < _getColors().length; i++) i};
  }

  /// Extract colors from wledPayload
  List<Color> _getColors() {
    try {
      final payload = widget.pattern.wledPayload;
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final firstSeg = seg.first;
        if (firstSeg is Map) {
          final cols = firstSeg['col'];
          if (cols is List && cols.isNotEmpty) {
            final colors = <Color>[];
            for (final col in cols) {
              if (col is List && col.length >= 3) {
                colors.add(Color.fromARGB(
                  255,
                  (col[0] as num).toInt().clamp(0, 255),
                  (col[1] as num).toInt().clamp(0, 255),
                  (col[2] as num).toInt().clamp(0, 255),
                ));
              }
            }
            if (colors.isNotEmpty) return colors;
          }
        }
      }
    } catch (e) {
      debugPrint('Error in pattern grid _getColors: $e');
    }
    return [NexGenPalette.cyan, NexGenPalette.blue];
  }

  /// Extract effect ID from wledPayload
  int _getEffectId() {
    try {
      final payload = widget.pattern.wledPayload;
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final firstSeg = seg.first;
        if (firstSeg is Map) {
          final fx = firstSeg['fx'];
          if (fx is int) return fx;
        }
      }
    } catch (e) {
      debugPrint('Error in pattern grid _getEffectId: $e');
    }
    return 0;
  }

  /// Check if this pattern is a brightness gradient and extract its colors.
  List<Color>? _getGradientColors() {
    final meta = widget.pattern.wledPayload['_gradientMeta'];
    if (meta is! Map || meta['isGradient'] != true) return null;
    // Gradient colors are stored in themeColors on the PatternItem's payload col
    // Reconstruct from the payload col (RGBW) back to display colors — or use
    // the theme colors directly since they're already Flutter Colors.
    return _getColors();
  }

  int _getGradientBandWidth() {
    try {
      final seg = widget.pattern.wledPayload['seg'];
      if (seg is List && seg.isNotEmpty) {
        return (seg.first['grp'] as int?) ?? 1;
      }
    } catch (e) {
      debugPrint('Error in pattern grid _getGradientBandWidth: $e');
    }
    return 1;
  }

  /// Build the active-color subset preserving the user's toggle order
  /// (lowest index first). Always returns at least one color — single-color
  /// patterns and any guard rails fall back to col[0].
  List<Color> _activeColors(List<Color> all) {
    if (all.isEmpty) return all;
    final indices = _activeColorIndices.toList()..sort();
    final filtered = [for (final i in indices) if (i < all.length) all[i]];
    return filtered.isEmpty ? [all.first] : filtered;
  }

  /// Build the WLED payload that will actually be sent when the user taps
  /// Apply. Substitutes fx=83 (Solid Pattern) when the original effect is
  /// Solid (fx=0) and the user has more than one active color, so the
  /// device renders the alternating bands the preview implies. For other
  /// multi-color cases the original fx is kept and `grp`/`spc` are added so
  /// WLED groups colors into bands of `_ledsPerColor`.
  ///
  /// Never mutates `rawPayload` — always returns a deep copy.
  Map<String, dynamic> _preparePayload(
    Map<String, dynamic> rawPayload,
    List<Color> activeColors,
    int ledsPerColor,
  ) {
    // Deep copy so the original PatternItem definition is never touched.
    final payload = <String, dynamic>{
      for (final entry in rawPayload.entries)
        entry.key: _deepCopy(entry.value),
    };

    final seg = payload['seg'];
    if (seg is! List || seg.isEmpty) return payload;

    final s = Map<String, dynamic>.from(seg.first as Map);
    final originalFx = s['fx'] as int? ?? 0;

    // Build col[] from active colors only. Force W=0 — RGBW strips otherwise
    // bleed white into saturated branded colors (red→pink, etc.).
    final col = activeColors
        .map<List<int>>((c) => [c.red, c.green, c.blue, 0])
        .toList();
    s['col'] = col;

    if (activeColors.length > 1) {
      if (originalFx == 0) {
        // Solid + multiple colors → Solid Pattern with explicit band width.
        s['fx'] = 83;
        // fx=83 ignores grp; band width = 1 + (ix >> 3). Inverse: ix = 8*(N-1).
        s['ix'] = ((ledsPerColor - 1) * 8).clamp(0, 255);
      }
      // For all other multi-color effects, keep the original fx but force
      // grouping so the device honors the user's ledsPerColor choice.
      s['grp'] = ledsPerColor;
      s['spc'] = 0;
    } else {
      // Single active color: collapse to plain Solid regardless of original.
      // A multi-color effect with one color produces undefined results on
      // many WLED effects, so this keeps the apply behavior predictable.
      s['fx'] = 0;
      s['grp'] = 1;
      s['spc'] = 0;
    }

    seg[0] = s;
    payload['seg'] = seg;
    return payload;
  }

  /// Recursive deep-copy for JSON-shaped maps/lists so `_preparePayload`
  /// can never mutate `widget.pattern.wledPayload`.
  Object? _deepCopy(Object? v) {
    if (v is Map) {
      return {for (final e in v.entries) e.key: _deepCopy(e.value)};
    }
    if (v is List) {
      return [for (final item in v) _deepCopy(item)];
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _getColors();
    final effectId = _getEffectId();
    final gradientColors = _getGradientColors();
    final isGradient = gradientColors != null;

    final activeColors = _activeColors(colors);
    // Preview should reflect what apply will produce. When the user has
    // 2+ active colors and the source effect is Solid, the apply path
    // substitutes fx=83 — the only honest preview for that is equal
    // repeating bands of `_ledsPerColor` width, which `_GradientDotPreview`
    // renders directly.
    final usePreparedBandPreview = !isGradient &&
        activeColors.length >= 2 &&
        effectId == 0;

    final showColorToggles = !isGradient && colors.length >= 2;
    // Per FIX 4 confirmation: stepper visible for every multi-color
    // non-gradient card, since `_preparePayload` writes `grp` in all those
    // cases anyway.
    final showLedStepper = !isGradient && activeColors.length >= 2;

    return GestureDetector(
      onTap: () async {
        await _applyPattern(context, ref);
      },
      child: Container(
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Animated effect preview - more prominent for compact cards
            Expanded(
              flex: 3,
              child: isGradient
                  ? _GradientDotPreview(
                      gradientColors: gradientColors,
                      bandWidth: _getGradientBandWidth(),
                      borderRadius: 10,
                    )
                  : usePreparedBandPreview
                      ? _GradientDotPreview(
                          gradientColors: activeColors,
                          bandWidth: _ledsPerColor,
                          borderRadius: 10,
                        )
                      : EffectPreviewWidget(
                          effectId: effectId,
                          colors: activeColors,
                          borderRadius: 10,
                        ),
            ),
            // Pattern info - compact for 4-column layout
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                widget.pattern.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (showColorToggles)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _buildColorToggles(colors),
              ),
            if (showLedStepper)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildLedStepper(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorToggles(List<Color> colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < colors.length; i++)
          GestureDetector(
            // Absorb the tap so the parent card's onTap (apply) does not fire.
            onTap: () => setState(() {
              if (_activeColorIndices.contains(i)) {
                // Don't allow deactivating all colors — keep at least one.
                if (_activeColorIndices.length > 1) {
                  _activeColorIndices.remove(i);
                }
              } else {
                _activeColorIndices.add(i);
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _activeColorIndices.contains(i)
                    ? colors[i]
                    : NexGenPalette.gunmetal90,
                border: Border.all(
                  color: _activeColorIndices.contains(i)
                      ? Colors.white.withValues(alpha: 0.4)
                      : NexGenPalette.line,
                  width: 1.2,
                ),
                boxShadow: _activeColorIndices.contains(i)
                    ? [
                        BoxShadow(
                          color: colors[i].withValues(alpha: 0.5),
                          blurRadius: 5,
                        )
                      ]
                    : null,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLedStepper() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'LEDs/color (1–10, 1=alt):',
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 9),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => setState(() {
            if (_ledsPerColor > 1) _ledsPerColor--;
          }),
          child: Icon(
            Icons.remove_circle_outline,
            color: NexGenPalette.cyan,
            size: 14,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$_ledsPerColor',
          style: TextStyle(
            color: NexGenPalette.textHigh,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => setState(() {
            if (_ledsPerColor < 10) _ledsPerColor++;
          }),
          child: Icon(
            Icons.add_circle_outline,
            color: NexGenPalette.cyan,
            size: 14,
          ),
        ),
      ],
    );
  }

  Future<void> _applyPattern(BuildContext context, WidgetRef ref) async {
    // Check for active neighborhood sync before changing lights
    final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No device connected')),
        );
      }
      return;
    }

    try {
      // Extract effect ID and colors from payload to check for custom effects
      final originalFx = _getEffectId();
      final allColors = _getColors();
      final activeColors = _activeColors(allColors);
      final colorsRgbw = activeColors
          .map<List<int>>((c) => [c.red, c.green, c.blue, 0])
          .toList();

      // Check if this is a custom Lumina effect (ID >= 1000). Custom effects
      // bypass the fx-substitution path because they're rendered client-side.
      final isCustomEffect = await executeCustomEffectIfNeeded(
        effectId: originalFx,
        colors: colorsRgbw,
        repo: repo,
      );

      // Build the prepared payload up front so both the apply call and the
      // local-preview state agree on the same fx/grp/spc/col values.
      final preparedPayload = _preparePayload(
        widget.pattern.wledPayload,
        activeColors,
        _ledsPerColor,
      );

      if (!isCustomEffect) {
        var payload = preparedPayload;
        final channels = ref.read(effectiveChannelIdsProvider);
        if (channels.isNotEmpty) payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
        final success = await repo.applyJson(payload);

        if (!success) {
          throw Exception('Device did not accept command');
        }
      }

      // Pull per-segment fields from the *prepared* payload (not the raw
      // pattern definition) so the home dashboard roofline preview renders
      // the same fx/grp/spc combination that the device received.
      final segList = preparedPayload['seg'];
      final firstSeg = (segList is List && segList.isNotEmpty && segList.first is Map)
          ? (segList.first as Map)
          : const <dynamic, dynamic>{};
      final appliedFx = (firstSeg['fx'] as int?) ?? originalFx;
      final patternSpeed = (firstSeg['sx'] as int?) ?? 128;
      final patternIntensity = (firstSeg['ix'] as int?) ?? 128;
      final patternGrp = (firstSeg['grp'] as int?) ?? 1;
      final patternSpc = (firstSeg['spc'] as int?) ?? 0;

      // Update preview immediately so home screen roofline matches device
      try {
        ref.read(wledStateProvider.notifier).applyLocalPreview(
          colors: activeColors,
          effectId: appliedFx,
          speed: patternSpeed,
          intensity: patternIntensity,
          effectName: widget.pattern.name,
          colorGroupSize: patternGrp,
          spacing: patternSpc,
        );
      } catch (e) {
        debugPrint('Error in pattern grid applyLocalPreview: $e');
      }
      ref.read(activePresetLabelProvider.notifier).state = widget.pattern.name;
      // Update Explore page roofline preview
      ref.read(explorePreviewProvider.notifier).state = ExplorePreviewState(
        colors: activeColors,
        effectId: appliedFx,
        speed: patternSpeed,
        brightness: preparedPayload['bri'] as int? ?? 255,
        name: widget.pattern.name,
        colorGroupSize: patternGrp,
        spacing: patternSpc,
      );

      if (context.mounted) {
        // Show pattern adjustment panel in a bottom sheet
        _showAdjustmentPanel(context, ref);

        // If this is a team-associated pattern, check for a live/upcoming
        // game and offer to enable live scoring celebrations.
        maybePromptLiveScoring(
          context: context,
          ref: ref,
          patternId: widget.pattern.id,
        );

        // Demo conversion nudge — once per session
        if (ref.read(demoBrowsingProvider) &&
            !ref.read(hasShownDemoNudgeProvider)) {
          ref.read(hasShownDemoNudgeProvider.notifier).state = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Love this look? Get it on your home.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      showDemoExitSheet(context, ref);
                    },
                    child: const Text(
                      'Talk to us',
                      style: TextStyle(
                        color: Color(0xFF00D4FF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF111527),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to apply pattern: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Extract colors as RGBW arrays for custom effect execution.
  /// Currently unused — `_applyPattern` derives the active-color RGBW list
  /// inline so toggles are honored. Kept for any external callers.
  // ignore: unused_element
  List<List<int>> _getColorsRgbw() {
    try {
      final payload = widget.pattern.wledPayload;
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final firstSeg = seg.first;
        if (firstSeg is Map) {
          final cols = firstSeg['col'];
          if (cols is List && cols.isNotEmpty) {
            final colors = <List<int>>[];
            for (final col in cols) {
              if (col is List && col.length >= 3) {
                colors.add([
                  (col[0] as num).toInt().clamp(0, 255),
                  (col[1] as num).toInt().clamp(0, 255),
                  (col[2] as num).toInt().clamp(0, 255),
                  col.length >= 4 ? (col[3] as num).toInt().clamp(0, 255) : 0,
                ]);
              }
            }
            if (colors.isNotEmpty) return colors;
          }
        }
      }
    } catch (e) {
      debugPrint('Error in pattern grid _getColorsRgbw: $e');
    }
    return [[255, 255, 255, 0]];
  }

  void _showAdjustmentPanel(BuildContext context, WidgetRef ref) {
    // Extract pattern values from wledPayload. Pass the *active* colors and
    // user-chosen ledsPerColor so the adjustment sheet starts from the same
    // state the device just received, not the raw catalog definition.
    final payload = widget.pattern.wledPayload;
    final seg = payload['seg'];
    int effectId = 0;
    int speed = 128;
    int intensity = 128;
    int grouping = _ledsPerColor;
    int spacing = 0;
    final activeColors = _activeColors(_getColors());

    if (seg is List && seg.isNotEmpty) {
      final firstSeg = seg.first;
      if (firstSeg is Map) {
        effectId = (firstSeg['fx'] as int?) ?? 0;
        speed = (firstSeg['sx'] as int?) ?? 128;
        intensity = (firstSeg['ix'] as int?) ?? 128;
        // The card-level ledsPerColor stepper takes precedence over any
        // grp/spc in the catalog payload — those are the pre-toggle defaults.
        if (activeColors.length < 2) {
          grouping = (firstSeg['grp'] as int?) ?? (firstSeg['gp'] as int?) ?? 1;
          spacing = (firstSeg['spc'] as int?) ?? (firstSeg['sp'] as int?) ?? 0;
        }
        // Reflect the fx-substitution that _preparePayload would apply.
        if (effectId == 0 && activeColors.length >= 2) {
          effectId = 83;
        }
      }
    }

    // Detect brightness gradient patterns
    final gradientMeta = payload['_gradientMeta'] as Map<String, dynamic>?;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PatternAdjustmentBottomSheet(
        patternName: widget.pattern.name,
        effectId: effectId,
        speed: speed,
        intensity: intensity,
        grouping: grouping,
        spacing: spacing,
        colors: activeColors,
        gradientMeta: gradientMeta,
      ),
    );
  }
}

/// Bottom sheet containing PatternAdjustmentPanel for fine-tuning a selected pattern
class _PatternAdjustmentBottomSheet extends ConsumerStatefulWidget {
  final String patternName;
  final int effectId;
  final int speed;
  final int intensity;
  final int grouping;
  final int spacing;
  final List<Color> colors;

  /// Non-null when the pattern is a brightness gradient.
  /// Contains 'isGradient', 'presetId', 'baseColorValue'.
  final Map<String, dynamic>? gradientMeta;

  const _PatternAdjustmentBottomSheet({
    required this.patternName,
    required this.effectId,
    required this.speed,
    required this.intensity,
    required this.grouping,
    required this.spacing,
    required this.colors,
    this.gradientMeta,
  });

  @override
  ConsumerState<_PatternAdjustmentBottomSheet> createState() => _PatternAdjustmentBottomSheetState();
}

class _PatternAdjustmentBottomSheetState extends ConsumerState<_PatternAdjustmentBottomSheet> {
  late int _speed;
  late int _intensity;
  late int _grouping;
  late int _spacing;
  late int _effectId;
  late bool _reverse;
  Timer? _debounce;

  // Brightness gradient state
  late bool _isGradient;
  String _gradientPresetId = 'gentle';
  int _bandWidth = 1;
  bool _breathing = false;
  Color _gradientBaseColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _speed = widget.speed;
    _intensity = widget.intensity;
    _grouping = widget.grouping;
    _spacing = widget.spacing;
    _effectId = widget.effectId;
    _reverse = false;

    // Initialise gradient state from metadata
    final gm = widget.gradientMeta;
    _isGradient = gm?['isGradient'] == true;
    if (_isGradient) {
      _gradientPresetId = (gm?['presetId'] as String?) ?? 'gentle';
      _bandWidth = widget.grouping; // bandWidth was stored as grp
      _breathing = _effectId == 2; // fx 2 = Breathe
      _gradientBaseColor = Color(gm?['baseColorValue'] as int? ?? 0xFFFFFFFF);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _applyChange(Map<String, dynamic> segUpdate) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final repo = ref.read(wledRepositoryProvider);
      if (repo != null) {
        var payload = <String, dynamic>{'seg': [segUpdate]};
        final channels = ref.read(effectiveChannelIdsProvider);
        if (channels.isNotEmpty) payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
        await repo.applyJson(payload);
      }
    });
  }

  /// Recompute gradient colors from the current preset + base color and
  /// send the full segment payload (col + fx + grp) to the device.
  void _applyGradientChange() {
    // Find the selected preset's brightness steps
    final presets = PatternRepository.brightnessGradientPresets;
    final preset = presets.firstWhere(
      (p) => p.id == _gradientPresetId,
      orElse: () => presets.first,
    );

    final r = _gradientBaseColor.red;
    final g = _gradientBaseColor.green;
    final b = _gradientBaseColor.blue;

    final gradientColors = preset.steps
        .map((pct) => Color.fromARGB(
              255,
              (r * pct).round(),
              (g * pct).round(),
              (b * pct).round(),
            ))
        .toList();

    final col = PatternRepository.colorsToWledCol(gradientColors);
    final fx = _breathing ? 2 : 83;
    final sx = _breathing ? 100 : 0;

    setState(() {
      _effectId = fx;
      _speed = sx;
      _grouping = _bandWidth;
    });

    _applyChange({
      'fx': fx,
      'col': col,
      'grp': _bandWidth,
      'spc': 0,
      'sx': sx,
      'pal': 5,
    });
  }

  @override
  Widget build(BuildContext context) {
    // Solid (0) and non-breathing gradients (83) are static — hide speed/direction controls
    final isStatic = _effectId == 0 || (_isGradient && !_breathing);

    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.colors.length >= 2
                            ? [widget.colors[0], widget.colors[1]]
                            : [widget.colors.first, widget.colors.first],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isStatic ? Icons.circle : Icons.auto_awesome,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Now Playing',
                          style: TextStyle(
                            color: NexGenPalette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          widget.patternName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Brightness Gradient controls ──
              if (_isGradient) ...[
                // CONTROL 1 — Gradient Preset Selector
                Row(
                  children: [
                    const Icon(Icons.gradient, color: NexGenPalette.cyan, size: 20),
                    const SizedBox(width: 8),
                    Text('Gradient', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: PatternRepository.brightnessGradientPresets.map((preset) {
                      final selected = preset.id == _gradientPresetId;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            preset.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: selected ? Colors.black : Colors.white70,
                            ),
                          ),
                          selected: selected,
                          selectedColor: NexGenPalette.cyan,
                          backgroundColor: NexGenPalette.gunmetal90,
                          side: BorderSide(
                            color: selected ? NexGenPalette.cyan : NexGenPalette.line,
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onSelected: (_) {
                            setState(() => _gradientPresetId = preset.id);
                            _applyGradientChange();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                // CONTROL 2 — Band Width Selector
                Row(
                  children: [
                    const Icon(Icons.view_column, color: NexGenPalette.cyan, size: 20),
                    const SizedBox(width: 12),
                    const Text('Band Width', style: TextStyle(color: Colors.white, fontSize: 14)),
                    const Spacer(),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('1 LED', style: TextStyle(fontSize: 12))),
                        ButtonSegment(value: 2, label: Text('2 LED', style: TextStyle(fontSize: 12))),
                      ],
                      selected: {_bandWidth},
                      onSelectionChanged: (s) {
                        setState(() => _bandWidth = s.first);
                        _applyGradientChange();
                      },
                      style: ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // CONTROL 3 — Breathing Toggle
                Row(
                  children: [
                    const Icon(Icons.air, color: NexGenPalette.cyan, size: 20),
                    const SizedBox(width: 12),
                    const Text('Breathing', style: TextStyle(color: Colors.white, fontSize: 14)),
                    const Spacer(),
                    Switch(
                      value: _breathing,
                      activeColor: NexGenPalette.cyan,
                      onChanged: (v) {
                        setState(() => _breathing = v);
                        _applyGradientChange();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Speed slider with per-effect profile (hide for static effects)
              if (!isStatic) ...[
                EffectSpeedSlider(
                  rawSpeed: _speed,
                  effectId: _effectId,
                  initialExtended: getSpeedProfile(_effectId)
                      .mapRawToSlider(_speed)
                      .needsExtended,
                  onChanged: (raw) {
                    setState(() => _speed = raw);
                    _applyChange({'sx': _speed});
                  },
                ),
                const SizedBox(height: 4),
              ],
              // Intensity slider
              _buildSliderRow(
                icon: Icons.tune,
                label: 'Intensity',
                value: _intensity.toDouble(),
                onChanged: (v) {
                  setState(() => _intensity = v.round());
                  _applyChange({'ix': _intensity});
                },
              ),
              const SizedBox(height: 12),
              // Direction toggle (hide for static effects)
              if (!isStatic) ...[
                Row(
                  children: [
                    const Icon(Icons.swap_horiz, color: NexGenPalette.cyan, size: 20),
                    const SizedBox(width: 12),
                    const Text('Direction', style: TextStyle(color: Colors.white, fontSize: 14)),
                    const Spacer(),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('L→R', style: TextStyle(fontSize: 12))),
                        ButtonSegment(value: true, label: Text('R→L', style: TextStyle(fontSize: 12))),
                      ],
                      selected: {_reverse},
                      onSelectionChanged: (s) {
                        final rev = s.isNotEmpty ? s.first : false;
                        setState(() => _reverse = rev);
                        _applyChange({'rev': rev});
                      },
                      style: ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              // Pixel layout section (hidden for gradient patterns — band width replaces it)
              if (!_hidePixelLayout) ...[
                Row(
                  children: [
                    const Icon(Icons.grid_view, color: NexGenPalette.cyan, size: 20),
                    const SizedBox(width: 8),
                    Text('Pixel Layout', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 8),
                // Grouping slider
                _buildSliderRow(
                  icon: Icons.blur_on,
                  label: 'Grouping',
                  value: _grouping.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (v) {
                    setState(() => _grouping = v.round());
                    _applyChange({'grp': _grouping});
                  },
                ),
                const SizedBox(height: 8),
                // Spacing slider
                _buildSliderRow(
                  icon: Icons.space_bar,
                  label: 'Spacing',
                  value: _spacing.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  onChanged: (v) {
                    setState(() => _spacing = v.round());
                    _applyChange({'spc': _spacing});
                  },
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Hide generic grouping/spacing sliders for gradient patterns — those are
  // controlled by the dedicated Band Width selector above.
  bool get _hidePixelLayout => _isGradient;

  Widget _buildSliderRow({
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    double min = 0,
    double max = 255,
    int? divisions,
  }) {
    return Row(
      children: [
        Icon(icon, color: NexGenPalette.cyan, size: 20),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${value.round()}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Pixel-dot preview that simulates a brightness gradient on a miniature LED strip.
/// Each dot's color is determined by cycling through [gradientColors] at [bandWidth].
class _GradientDotPreview extends StatelessWidget {
  final List<Color> gradientColors;
  final int bandWidth;
  final double borderRadius;

  const _GradientDotPreview({
    required this.gradientColors,
    required this.bandWidth,
    this.borderRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(borderRadius),
        topRight: Radius.circular(borderRadius),
      ),
      child: Container(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const dotSize = 6.0;
            const spacing = 2.0;
            const step = dotSize + spacing;
            final cols = (constraints.maxWidth / step).floor().clamp(1, 100);
            final rows = (constraints.maxHeight / step).floor().clamp(1, 20);

            final bw = bandWidth.clamp(1, 4);
            final stepCount = gradientColors.length;

            return CustomPaint(
              painter: _GradientDotPainter(
                gradientColors: gradientColors,
                bandWidth: bw,
                stepCount: stepCount,
                cols: cols,
                rows: rows,
                dotSize: dotSize,
                spacing: spacing,
              ),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            );
          },
        ),
      ),
    );
  }
}

class _GradientDotPainter extends CustomPainter {
  final List<Color> gradientColors;
  final int bandWidth;
  final int stepCount;
  final int cols;
  final int rows;
  final double dotSize;
  final double spacing;

  _GradientDotPainter({
    required this.gradientColors,
    required this.bandWidth,
    required this.stepCount,
    required this.cols,
    required this.rows,
    required this.dotSize,
    required this.spacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final step = dotSize + spacing;
    // Centre the dot grid within the available space
    final xOffset = (size.width - cols * step + spacing) / 2;
    final yOffset = (size.height - rows * step + spacing) / 2;
    final radius = dotSize / 2;
    final paint = Paint();

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        final i = row * cols + col;
        // bandWidth determines how many consecutive dots share a step
        final colorIndex = (i ~/ bandWidth) % stepCount;
        paint.color = gradientColors[colorIndex];

        canvas.drawCircle(
          Offset(xOffset + col * step + radius, yOffset + row * step + radius),
          radius,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GradientDotPainter old) =>
      gradientColors != old.gradientColors ||
      bandWidth != old.bandWidth ||
      cols != old.cols ||
      rows != old.rows;
}
