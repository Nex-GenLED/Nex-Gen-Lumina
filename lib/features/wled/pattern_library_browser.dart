import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/wled/pattern_grid_widgets.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/nav.dart' show AppRoutes;
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/features/wled/pattern_explore_screen.dart' show pagePadding, gap, executeCustomEffectIfNeeded;

/// Browse Design Library section with category cards
class DesignLibraryBrowser extends ConsumerWidget {
  const DesignLibraryBrowser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(patternCategoriesProvider);
    final selectedMood = ref.watch(selectedMoodFilterProvider);
    final designsAsync = ref.watch(designsStreamProvider);

    // Check if user has saved designs
    final hasSavedDesigns = designsAsync.whenOrNull(
      data: (designs) => designs.isNotEmpty,
    ) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Browse Design Library',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'Explore all categories',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: NexGenPalette.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Global mood selector - pre-filter patterns when navigating
        GlobalMoodSelector(
          selectedMood: selectedMood,
          onMoodSelected: (mood) {
            ref.read(selectedMoodFilterProvider.notifier).state = mood;
          },
        ),
        const SizedBox(height: 16),
        // Category grid
        categoriesAsync.when(
          data: (categories) {
            // Calculate total items: add 1 for saved designs card if user has saved designs
            final totalItems = hasSavedDesigns ? categories.length + 1 : categories.length;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
              ),
              itemCount: totalItems,
              itemBuilder: (context, index) {
                // If we have saved designs, show the saved designs card first
                if (hasSavedDesigns && index == 0) {
                  return const _SavedDesignsCategoryCard();
                }

                // Adjust index for regular categories if saved designs card is shown
                final categoryIndex = hasSavedDesigns ? index - 1 : index;
                final category = categories[categoryIndex];
                return _DesignLibraryCategoryCard(category: category);
              },
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, __) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Unable to load categories',
                style: TextStyle(color: NexGenPalette.textSecondary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Special category card for "My Saved Designs" - appears first when user has saved designs
class _SavedDesignsCategoryCard extends StatelessWidget {
  const _SavedDesignsCategoryCard();

  static const _icons = [
    Icons.palette_outlined,
    Icons.bookmark_outlined,
    Icons.favorite_outline,
    Icons.folder_special_outlined,
    Icons.auto_awesome_outlined,
    Icons.brush_outlined,
  ];

  static const _accentColor = NexGenPalette.cyan;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push('/designs');
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            // Premium dark background with cyan accent gradient
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _accentColor.withValues(alpha: 0.15),
                NexGenPalette.matteBlack.withValues(alpha: 0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _accentColor.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _accentColor.withValues(alpha: 0.2),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Accent glow in corner
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _accentColor.withValues(alpha: 0.25),
                        _accentColor.withValues(alpha: 0.0),
                      ],
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
                    // Icon grid
                    Expanded(
                      child: _buildIconGrid(),
                    ),
                    const SizedBox(height: 8),
                    // Category name
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'My Saved Designs',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: _accentColor.withValues(alpha: 0.7),
                          size: 12,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Star badge to indicate this is the user's custom content
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _accentColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.star,
                    color: _accentColor,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final iconSize = (constraints.maxWidth - 16) / 3.5;

        return Wrap(
          spacing: 4,
          runSpacing: 2,
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          children: _icons.asMap().entries.map((entry) {
            final index = entry.key;
            final icon = entry.value;

            final isHighlighted = index % 2 == 0;
            final iconColor = isHighlighted
                ? _accentColor
                : Colors.white.withValues(alpha: 0.5);

            return SizedBox(
              width: iconSize,
              height: iconSize,
              child: Icon(
                icon,
                color: iconColor,
                size: iconSize * 0.7,
                shadows: isHighlighted
                    ? [
                        Shadow(
                          color: _accentColor.withValues(alpha: 0.5),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

/// Individual category card for the Design Library browser
class _DesignLibraryCategoryCard extends ConsumerWidget {
  final PatternCategory category;

  const _DesignLibraryCategoryCard({required this.category});

  /// Returns a single hero icon that represents the category.
  /// For seasonal category, returns dynamic icon based on current season.
  IconData _heroIconForCategory(String categoryId) {
    switch (categoryId) {
      case 'cat_arch':
        return Icons.villa;
      case 'cat_holiday':
        return Icons.celebration;
      case 'cat_sports':
        return Icons.emoji_events;
      case 'cat_season':
        return _getSeasonalIcon();
      case 'cat_party':
        return Icons.cake;
      case 'cat_security':
        return Icons.shield;
      case 'cat_movies':
        return Icons.movie_filter;
      case 'cat_nature':
        return Icons.forest;
      default:
        return Icons.palette;
    }
  }

  /// Returns the appropriate seasonal icon based on current date.
  IconData _getSeasonalIcon() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    // Spring: March 20 - June 20
    if ((month == 3 && day >= 20) || month == 4 || month == 5 || (month == 6 && day < 21)) {
      return Icons.local_florist;
    }
    // Summer: June 21 - September 22
    if ((month == 6 && day >= 21) || month == 7 || month == 8 || (month == 9 && day < 23)) {
      return Icons.wb_sunny;
    }
    // Fall: September 23 - December 20
    if ((month == 9 && day >= 23) || month == 10 || month == 11 || (month == 12 && day < 21)) {
      return Icons.park;
    }
    // Winter: December 21 - March 19
    return Icons.ac_unit;
  }

  /// Returns gradient colors for each category background.
  List<Color> _gradientForCategory(String categoryId) {
    switch (categoryId) {
      case 'cat_arch':
        // Warm amber to burnt orange
        return const [Color(0xFFFFB347), Color(0xFFFF7043)];
      case 'cat_holiday':
        // Festive red to deep magenta
        return const [Color(0xFFFF4444), Color(0xFFC2185B)];
      case 'cat_sports':
        // Championship gold to orange
        return const [Color(0xFFFFD700), Color(0xFFFF9800)];
      case 'cat_season':
        return _getSeasonalGradient();
      case 'cat_party':
        // Party pink to purple
        return const [Color(0xFFFF69B4), Color(0xFF9C27B0)];
      case 'cat_security':
        // Alert blue to deep blue
        return const [Color(0xFF4FC3F7), Color(0xFF1565C0)];
      case 'cat_movies':
        // Cinema purple to deep violet
        return const [Color(0xFFE040FB), Color(0xFF6A1B9A)];
      case 'cat_nature':
        // Forest green to teal
        return const [Color(0xFF4CAF50), Color(0xFF00897B)];
      default:
        return [NexGenPalette.cyan, NexGenPalette.cyan.withValues(alpha: 0.5)];
    }
  }

  /// Returns seasonal gradient based on current date.
  List<Color> _getSeasonalGradient() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    // Spring: Fresh greens and pinks
    if ((month == 3 && day >= 20) || month == 4 || month == 5 || (month == 6 && day < 21)) {
      return const [Color(0xFF81C784), Color(0xFFF8BBD9)];
    }
    // Summer: Sunny yellow to ocean blue
    if ((month == 6 && day >= 21) || month == 7 || month == 8 || (month == 9 && day < 23)) {
      return const [Color(0xFFFFEB3B), Color(0xFF29B6F6)];
    }
    // Fall: Warm orange to burgundy
    if ((month == 9 && day >= 23) || month == 10 || month == 11 || (month == 12 && day < 21)) {
      return const [Color(0xFFFF9800), Color(0xFF8D6E63)];
    }
    // Winter: Icy blue to deep purple
    return const [Color(0xFF81D4FA), Color(0xFF7E57C2)];
  }

  /// Returns accent color for each category (used for icon highlights and glow).
  Color _accentForCategory(String categoryId) {
    switch (categoryId) {
      case 'cat_arch':
        return const Color(0xFFFFB347); // Warm amber
      case 'cat_holiday':
        return const Color(0xFFFF4444); // Festive red
      case 'cat_sports':
        return const Color(0xFFFFD700); // Championship gold
      case 'cat_season':
        return _getSeasonalAccentColor();
      case 'cat_party':
        return const Color(0xFFFF69B4); // Party pink
      case 'cat_security':
        return const Color(0xFF4FC3F7); // Alert blue
      case 'cat_movies':
        return const Color(0xFFE040FB); // Cinema purple
      case 'cat_nature':
        return const Color(0xFF4CAF50); // Forest green
      default:
        return NexGenPalette.cyan;
    }
  }

  /// Returns seasonal accent color based on current date.
  Color _getSeasonalAccentColor() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    // Spring: Fresh pink
    if ((month == 3 && day >= 20) || month == 4 || month == 5 || (month == 6 && day < 21)) {
      return const Color(0xFFF8BBD9);
    }
    // Summer: Sunny yellow
    if ((month == 6 && day >= 21) || month == 7 || month == 8 || (month == 9 && day < 23)) {
      return const Color(0xFFFFEB3B);
    }
    // Fall: Warm orange
    if ((month == 9 && day >= 23) || month == 10 || month == 11 || (month == 12 && day < 21)) {
      return const Color(0xFFFF9800);
    }
    // Winter: Icy blue
    return const Color(0xFF81D4FA);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroIcon = _heroIconForCategory(category.id);
    final accentColor = _accentForCategory(category.id);
    final gradientColors = _gradientForCategory(category.id);
    final pinnedIds = ref.watch(pinnedCategoryIdsProvider);
    final isPinned = pinnedIds.contains(category.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push(
            '/library/${category.id}',
            extra: {'name': category.name},
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            // Category-specific gradient background
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
              // Large radial glow behind icon
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
                    // Category name with arrow
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            category.name,
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
              // Pin button
              Positioned(
                right: 4,
                top: 4,
                child: GestureDetector(
                  onTap: () => _togglePin(context, ref, isPinned),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: isPinned ? NexGenPalette.cyan : Colors.white.withValues(alpha: 0.7),
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _togglePin(BuildContext context, WidgetRef ref, bool isPinned) async {
    final notifier = ref.read(pinnedCategoriesNotifierProvider.notifier);
    final success = isPinned
        ? await notifier.unpinCategory(category.id)
        : await notifier.pinCategory(category.id);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (isPinned ? 'Folder unpinned' : 'Folder pinned to Explore')
                : 'Failed to update pin status',
          ),
        ),
      );
    }
  }
}

/// Section for displaying user's saved custom designs
class MySavedDesignsSection extends ConsumerWidget {
  const MySavedDesignsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final designsAsync = ref.watch(designsStreamProvider);

    return designsAsync.when(
      data: (designs) {
        if (designs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header with manage button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.palette_outlined, color: NexGenPalette.cyan, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'My Saved Designs',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    // Navigate to My Designs screen for full management
                    context.push('/designs');
                  },
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Manage'),
                  style: TextButton.styleFrom(
                    foregroundColor: NexGenPalette.cyan,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Horizontal scrolling list of saved designs
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: designs.length.clamp(0, 10), // Max 10 visible
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final design = designs[index];
                  return _SavedDesignCard(
                    design: design,
                    onTap: () => _applyDesign(context, ref, design),
                    onRemove: () => _confirmRemoveDesign(context, ref, design),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _applyDesign(BuildContext context, WidgetRef ref, CustomDesign design) async {
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
      final payload = design.toWledPayload();
      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = design.name;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Applied: ${design.name}')),
        );
      }
    } catch (e) {
      debugPrint('Apply design failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to apply design')),
        );
      }
    }
  }

  Future<void> _confirmRemoveDesign(BuildContext context, WidgetRef ref, CustomDesign design) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Design?'),
        content: Text('Remove "${design.name}" from your saved designs?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final deleteDesign = ref.read(deleteDesignProvider);
      final success = await deleteDesign(design.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Design removed' : 'Failed to remove design'),
          ),
        );
      }
    }
  }
}

/// Card for displaying a saved design
class _SavedDesignCard extends StatelessWidget {
  final CustomDesign design;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _SavedDesignCard({
    required this.design,
    required this.onTap,
    required this.onRemove,
  });

  List<Color> _extractColors() {
    final colors = <Color>[];
    for (final channel in design.channels.where((ch) => ch.included)) {
      for (final group in channel.colorGroups.take(3)) {
        if (group.color.length >= 3) {
          colors.add(Color.fromARGB(
            255,
            group.color[0].clamp(0, 255),
            group.color[1].clamp(0, 255),
            group.color[2].clamp(0, 255),
          ));
        }
      }
    }
    if (colors.isEmpty) {
      return [NexGenPalette.violet, NexGenPalette.cyan];
    }
    return colors.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _extractColors();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors.length == 1 ? [colors[0], colors[0]] : colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Dark overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
            ),
            // Remove button
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
            // Design name
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(
                design.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4)],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section for displaying user's recently used patterns
class RecentPatternsSection extends ConsumerWidget {
  const RecentPatternsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentPatternsProvider);

    return recentAsync.when(
      data: (patterns) {
        if (patterns.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              children: [
                Icon(Icons.history_rounded, color: NexGenPalette.cyan, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Recent Patterns',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Horizontal scrolling list of recent patterns (most recent on left)
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: patterns.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final pattern = patterns[index];
                  return _RecentPatternCard(
                    pattern: pattern,
                    onTap: () => _applyPattern(context, ref, pattern),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _applyPattern(BuildContext context, WidgetRef ref, GradientPattern pattern) async {
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
      // Build WLED JSON payload from pattern
      final colors = pattern.colors.map((c) {
        final rgbw = rgbToRgbw(
          (c.r * 255).round(),
          (c.g * 255).round(),
          (c.b * 255).round(),
          forceZeroWhite: true,
        );
        return [rgbw[0], rgbw[1], rgbw[2], rgbw[3]];
      }).toList();

      // Check if this is a custom Lumina effect (ID >= 1000)
      final isCustomEffect = await executeCustomEffectIfNeeded(
        effectId: pattern.effectId,
        colors: colors.isNotEmpty ? colors.take(3).toList() : [[255, 180, 100, 0]],
        repo: repo,
      );

      if (!isCustomEffect) {
        // Standard WLED effect - send payload directly
        final payload = {
          'on': true,
          'bri': pattern.brightness,
          'seg': [
            {
              'fx': pattern.effectId,
              'sx': pattern.speed,
              'ix': pattern.intensity,
              'col': colors.isNotEmpty ? colors.take(3).toList() : [[255, 180, 100, 0]],
            }
          ],
        };

        await repo.applyJson(payload);
      }

      ref.read(activePresetLabelProvider.notifier).state = pattern.name;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Applied: ${pattern.name}')),
        );
      }
    } catch (e) {
      debugPrint('Apply recent pattern failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to apply pattern')),
        );
      }
    }
  }
}

/// Card for displaying a recent pattern
class _RecentPatternCard extends StatelessWidget {
  final GradientPattern pattern;
  final VoidCallback onTap;

  const _RecentPatternCard({
    required this.pattern,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = pattern.colors.isNotEmpty
        ? pattern.colors
        : const [Color(0xFFFFB347), Color(0xFFFFE4B5)];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors.length == 1 ? [colors[0], colors[0]] : colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Dark overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),
            ),
            // Time ago badge
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  pattern.subtitle ?? '',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
            // Pattern name
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(
                pattern.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4)],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section for displaying user's pinned categories
class PinnedCategoriesSection extends ConsumerWidget {
  const PinnedCategoriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinnedAsync = ref.watch(pinnedCategoriesProvider);

    return pinnedAsync.when(
      data: (pinnedCategories) {
        if (pinnedCategories.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final pinned in pinnedCategories) ...[
              _PinnedCategoryRow(pinnedData: pinned),
              const SizedBox(height: 24),
            ],
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Row showing a pinned category with its patterns
class _PinnedCategoryRow extends ConsumerWidget {
  final PinnedCategoryData pinnedData;

  const _PinnedCategoryRow({required this.pinnedData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with unpin button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.push_pin, color: NexGenPalette.cyan, size: 18),
                const SizedBox(width: 8),
                Text(
                  pinnedData.category.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    // Navigate to category detail
                    context.push(
                      AppRoutes.patternCategory.replaceFirst(':categoryId', pinnedData.category.id),
                      extra: pinnedData.category,
                    );
                  },
                  child: const Text('See All'),
                  style: TextButton.styleFrom(foregroundColor: NexGenPalette.textSecondary),
                ),
                IconButton(
                  onPressed: () => _confirmUnpin(context, ref),
                  icon: const Icon(Icons.close, size: 18),
                  color: NexGenPalette.textSecondary,
                  tooltip: 'Unpin folder',
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Sub-categories as horizontal scrolling chips
        if (pinnedData.subCategories.isNotEmpty)
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: pinnedData.subCategories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final subCat = pinnedData.subCategories[index];
                return _SubCategoryChip(
                  subCategory: subCat,
                  categoryId: pinnedData.category.id,
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _confirmUnpin(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpin Folder?'),
        content: Text('Remove "${pinnedData.category.name}" from your Explore page?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unpin'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final notifier = ref.read(pinnedCategoriesNotifierProvider.notifier);
      final success = await notifier.unpinCategory(pinnedData.category.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Folder unpinned' : 'Failed to unpin folder'),
          ),
        );
      }
    }
  }
}

/// Chip showing a sub-category within a pinned category
class _SubCategoryChip extends StatelessWidget {
  final SubCategory subCategory;
  final String categoryId;

  const _SubCategoryChip({
    required this.subCategory,
    required this.categoryId,
  });

  /// Returns a hero icon for each sub-category type.
  IconData _heroIconForSubCategory(String subId) {
    switch (subId) {
      // Holidays
      case 'sub_xmas':
        return Icons.park; // Christmas tree
      case 'sub_halloween':
        return Icons.pest_control; // Spider/bug for spooky
      case 'sub_july4':
        return Icons.celebration; // Fireworks/celebration
      case 'sub_easter':
        return Icons.egg; // Easter egg
      case 'sub_valentines':
        return Icons.favorite; // Heart
      case 'sub_st_patricks':
        return Icons.local_florist; // Clover/flower
      // Sports
      case 'sub_kc':
        return Icons.sports_football; // Football
      case 'sub_seattle':
        return Icons.sports_football;
      case 'sub_rb_generic':
      case 'sub_gy_generic':
      case 'sub_ob_generic':
        return Icons.emoji_events; // Trophy
      // Seasonal
      case 'sub_spring':
        return Icons.local_florist; // Flowers
      case 'sub_summer':
        return Icons.wb_sunny; // Sun
      case 'sub_autumn':
        return Icons.park; // Falling leaves
      case 'sub_winter':
        return Icons.ac_unit; // Snowflake
      // Architectural
      case 'sub_warm_whites':
        return Icons.wb_incandescent; // Warm bulb
      case 'sub_cool_whites':
        return Icons.light_mode; // Cool light
      case 'sub_gold_accents':
        return Icons.auto_awesome; // Sparkle/gold
      case 'sub_security_floods':
        return Icons.flashlight_on; // Flood light
      // Party
      case 'sub_birthday':
        return Icons.cake; // Birthday cake
      case 'sub_elegant_dinner':
        return Icons.restaurant; // Dinner
      case 'sub_rave':
        return Icons.speaker; // Music/rave
      case 'sub_baby_shower':
        return Icons.child_friendly; // Baby
      default:
        return Icons.palette; // Default
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = subCategory.themeColors;
    final gradientColors = colors.isEmpty
        ? [NexGenPalette.violet, NexGenPalette.cyan]
        : (colors.length == 1 ? [colors[0], colors[0]] : colors);
    final accentColor = gradientColors.first;
    final heroIcon = _heroIconForSubCategory(subCategory.id);

    return GestureDetector(
      onTap: () {
        // Navigate to theme selection for this sub-category
        context.push(
          AppRoutes.patternSubCategory
              .replaceFirst(':categoryId', categoryId)
              .replaceFirst(':subId', subCategory.id),
          extra: subCategory.name,
        );
      },
      child: Container(
        width: 110,
        decoration: BoxDecoration(
          // Premium gradient background matching main category cards
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              gradientColors[0].withValues(alpha: 0.3),
              gradientColors.length > 1 ? gradientColors[1].withValues(alpha: 0.2) : gradientColors[0].withValues(alpha: 0.2),
              NexGenPalette.matteBlack.withValues(alpha: 0.95),
            ],
            stops: const [0.0, 0.4, 1.0],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Radial glow behind icon
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        gradientColors[0].withValues(alpha: 0.35),
                        gradientColors.length > 1 ? gradientColors[1].withValues(alpha: 0.15) : Colors.transparent,
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Hero icon
                  Icon(
                    heroIcon,
                    size: 28,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: accentColor.withValues(alpha: 0.8),
                        blurRadius: 16,
                      ),
                      Shadow(
                        color: gradientColors[0].withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Name with arrow
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          subCategory.name,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.arrow_forward_ios,
                        color: accentColor.withValues(alpha: 0.8),
                        size: 8,
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

/// GPU-friendly animated gradient strip that simulates a flowing/chase effect
/// using a LinearGradient and a lightweight GradientTransform.
///
/// Pass a list of colors for the gradient and a speed value (0 = static).
class LiveGradientStrip extends StatefulWidget {
  final List<Color> colors;
  final double speed; // Typical range 0..255
  const LiveGradientStrip({super.key, required this.colors, required this.speed});

  @override
  State<LiveGradientStrip> createState() => _LiveGradientStripState();
}

class _LiveGradientStripState extends State<LiveGradientStrip> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Map speed (0..255) to a loop duration. Faster speed -> shorter duration.
  Duration _durationFor(double speed) {
    final s = speed.clamp(0, 255);
    final ms = 4200 - (s / 255) * 3600; // ~4.2s slow -> ~0.6s fast
    final clamped = ms.clamp(350, 8000).round();
    return Duration(milliseconds: clamped);
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _durationFor(widget.speed));
    _maybeStart();
  }

  void _maybeStart() {
    if (widget.speed <= 0) {
      _controller.stop();
      _controller.value = 0; // static
    } else {
      _controller.duration = _durationFor(widget.speed);
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant LiveGradientStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) {
      _maybeStart();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> get _effectiveColors {
    if (widget.colors.isEmpty) return const [Colors.white, Colors.white];
    if (widget.colors.length == 1) return [widget.colors.first, widget.colors.first];
    return widget.colors;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _effectiveColors;

    // Static gradient when speed == 0
    if (widget.speed <= 0) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: colors),
        ),
      );
    }

    // Animated: slide the gradient horizontally in a seamless loop
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: colors,
              tileMode: TileMode.mirror,
              transform: _SlidingGradientTransform(_controller.value),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent; // 0..1
  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    final dx = bounds.width * slidePercent;
    // Translate around the center to avoid edge stretching
    final m = Matrix4.identity();
    m.translate(dx);
    return m;
  }
}
