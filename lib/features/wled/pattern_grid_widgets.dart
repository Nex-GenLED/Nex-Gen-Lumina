import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/wled_models.dart' show kEffectNames;
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/effect_preview_widget.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/features/wled/effect_mood_system.dart';
import 'package:nexgen_command/features/wled/pattern_explore_screen.dart' show executeCustomEffectIfNeeded;

/// Grid of library nodes (categories, folders, or palettes)
class LibraryNodeGrid extends StatelessWidget {
  final List<LibraryNode> children;

  const LibraryNodeGrid({super.key, required this.children});

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

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) {
        final node = children[index];
        return LibraryNodeCard(node: node);
      },
    );
  }
}

/// Individual node card for navigation
class LibraryNodeCard extends StatelessWidget {
  final LibraryNode node;

  const LibraryNodeCard({super.key, required this.node});

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
    if (id == 'league_mls') return const Color(0xFF3A5A40);
    if (id == 'league_wnba') return const Color(0xFFFF6F00);
    if (id == 'league_nwsl') return const Color(0xFF0D47A1);

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

    // Architectural Kelvin folders -- use the node's own theme color
    if (id.startsWith('arch_') && node.themeColors != null && node.themeColors!.isNotEmpty) {
      return node.themeColors!.first;
    }

    return NexGenPalette.cyan;
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
    if (id == 'league_mls') return const [Color(0xFF66BB6A), Color(0xFF2E7D32)];
    if (id == 'league_wnba') return const [Color(0xFFFF8F00), Color(0xFFE65100)];
    if (id == 'league_nwsl') return const [Color(0xFF42A5F5), Color(0xFF0D47A1)];

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

    // Architectural Kelvin folders -- use the node's own theme colors
    if (id.startsWith('arch_') && node.themeColors != null && node.themeColors!.length >= 2) {
      return [node.themeColors![0], node.themeColors![1]];
    }

    // Default: derive from theme color
    final c = _getFolderThemeColor();
    return [c, c.withValues(alpha: 0.5)];
  }

  @override
  Widget build(BuildContext context) {
    // Palettes get flowing gradient cards, folders get solid themed cards
    if (node.isPalette) {
      return _buildPaletteCard(context);
    } else {
      return _buildFolderCard(context);
    }
  }

  /// Build a folder card with single hero icon design matching main category cards
  Widget _buildFolderCard(BuildContext context) {
    final heroIcon = _iconForNode();
    final accentColor = _getFolderThemeColor();
    final gradientColors = _getGradientForNode();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push('/library/${node.id}', extra: {'name': node.name});
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                gradientColors[0].withValues(alpha: 0.25),
                gradientColors[1].withValues(alpha: 0.15),
                NexGenPalette.matteBlack.withValues(alpha: 0.95),
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Centered radial glow behind icon
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          gradientColors[0].withValues(alpha: 0.3),
                          gradientColors[1].withValues(alpha: 0.1),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Single hero icon - centered and prominent
                    Expanded(
                      child: Center(
                        child: Icon(
                          heroIcon,
                          size: 52,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: accentColor.withValues(alpha: 0.8),
                              blurRadius: 24,
                            ),
                            Shadow(
                              color: gradientColors[0].withValues(alpha: 0.5),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Folder name with arrow
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            node.name,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: accentColor.withValues(alpha: 0.8),
                          size: 10,
                        ),
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

  /// Build a palette card with flowing gradient colors
  Widget _buildPaletteCard(BuildContext context) {
    final colors = node.themeColors ?? [NexGenPalette.cyan, NexGenPalette.blue];
    final gradient = colors.length >= 2
        ? [colors[0], colors[1]]
        : [colors.first, colors.first.withValues(alpha: 0.7)];
    // Adaptive contrast -- dark text on light cards, white on dark cards
    final textColor = NexGenPalette.contrastTextFor(gradient);
    final secondaryColor = NexGenPalette.contrastSecondaryFor(gradient);
    final isLight = textColor == const Color(0xFF1A1A1A);
    final dotBorder = isLight ? const Color(0xFF4A4A4A) : Colors.white;
    final watermark = isLight
        ? Colors.black.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.1);

    return GestureDetector(
      onTap: () {
        context.push('/library/${node.id}', extra: {'name': node.name});
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Subtle icon watermark
            Positioned(
              right: -15,
              bottom: -15,
              child: Icon(
                Icons.palette,
                size: 70,
                color: watermark,
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Color dots preview at top
                  Row(
                    children: [
                      for (var i = 0; i < (colors.length > 4 ? 4 : colors.length); i++)
                        Container(
                          width: 16,
                          height: 16,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: colors[i],
                            shape: BoxShape.circle,
                            border: Border.all(color: dotBorder, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  // Text content
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(color: isLight ? Colors.white38 : Colors.black26, blurRadius: 2)],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (node.description != null)
                        Text(
                          node.description!,
                          style: TextStyle(
                            color: secondaryColor,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
                              child: const Text('Show All Patterns'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
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
      loading: () => const Center(child: CircularProgressIndicator()),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
class PatternCard extends ConsumerWidget {
  final PatternItem pattern;

  const PatternCard({required this.pattern});

  /// Extract colors from wledPayload
  List<Color> _getColors() {
    try {
      final payload = pattern.wledPayload;
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
    } catch (_) {}
    return [NexGenPalette.cyan, NexGenPalette.blue];
  }

  /// Extract effect ID from wledPayload
  int _getEffectId() {
    try {
      final payload = pattern.wledPayload;
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final firstSeg = seg.first;
        if (firstSeg is Map) {
          final fx = firstSeg['fx'];
          if (fx is int) return fx;
        }
      }
    } catch (_) {}
    return 0;
  }

  /// Get effect name from effect ID
  String? _getEffectName() {
    final effectId = _getEffectId();
    return kEffectNames[effectId];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = _getColors();
    final effectId = _getEffectId();
    final effectName = _getEffectName();

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
              child: EffectPreviewWidget(
                effectId: effectId,
                colors: colors,
                borderRadius: 10,
              ),
            ),
            // Pattern info - compact for 4-column layout
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                pattern.name,
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
          ],
        ),
      ),
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
      final effectId = _getEffectId();
      final colorsRgbw = _getColorsRgbw();

      // Check if this is a custom Lumina effect (ID >= 1000)
      final isCustomEffect = await executeCustomEffectIfNeeded(
        effectId: effectId,
        colors: colorsRgbw,
        repo: repo,
      );

      if (!isCustomEffect) {
        // Standard WLED effect - apply the pattern's wledPayload directly
        final success = await repo.applyJson(pattern.wledPayload);

        if (!success) {
          throw Exception('Device did not accept command');
        }
      }

      // Update the active preset label so home screen reflects the change
      ref.read(activePresetLabelProvider.notifier).state = pattern.name;

      if (context.mounted) {
        // Show pattern adjustment panel in a bottom sheet
        _showAdjustmentPanel(context, ref);
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

  /// Extract colors as RGBW arrays for custom effect execution
  List<List<int>> _getColorsRgbw() {
    try {
      final payload = pattern.wledPayload;
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
    } catch (_) {}
    return [[255, 255, 255, 0]];
  }

  void _showAdjustmentPanel(BuildContext context, WidgetRef ref) {
    // Extract pattern values from wledPayload
    final payload = pattern.wledPayload;
    final seg = payload['seg'];
    int effectId = 0;
    int speed = 128;
    int intensity = 128;
    int grouping = 1;
    int spacing = 0;
    List<Color> colors = _getColors();

    if (seg is List && seg.isNotEmpty) {
      final firstSeg = seg.first;
      if (firstSeg is Map) {
        effectId = (firstSeg['fx'] as int?) ?? 0;
        speed = (firstSeg['sx'] as int?) ?? 128;
        intensity = (firstSeg['ix'] as int?) ?? 128;
        // WLED uses 'grp' and 'spc', but check old keys 'gp'/'sp' as fallback
        grouping = (firstSeg['grp'] as int?) ?? (firstSeg['gp'] as int?) ?? 1;
        spacing = (firstSeg['spc'] as int?) ?? (firstSeg['sp'] as int?) ?? 0;
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _PatternAdjustmentBottomSheet(
        patternName: pattern.name,
        effectId: effectId,
        speed: speed,
        intensity: intensity,
        grouping: grouping,
        spacing: spacing,
        colors: colors,
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

  const _PatternAdjustmentBottomSheet({
    required this.patternName,
    required this.effectId,
    required this.speed,
    required this.intensity,
    required this.grouping,
    required this.spacing,
    required this.colors,
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

  @override
  void initState() {
    super.initState();
    _speed = widget.speed;
    _intensity = widget.intensity;
    _grouping = widget.grouping;
    _spacing = widget.spacing;
    _effectId = widget.effectId;
    _reverse = false;
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
        await repo.applyJson({'seg': [segUpdate]});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isStatic = _effectId == 0;

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
              // Speed slider (hide for static effects)
              if (!isStatic) ...[
                _buildSliderRow(
                  icon: Icons.speed,
                  label: 'Speed',
                  value: _speed.toDouble(),
                  onChanged: (v) {
                    setState(() => _speed = v.round());
                    _applyChange({'sx': _speed});
                  },
                ),
                const SizedBox(height: 12),
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
              // Pixel layout section
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
          ),
        ),
      ),
    );
  }

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
