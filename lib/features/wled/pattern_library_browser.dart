import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/nav.dart' show AppRoutes;
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/features/wled/pattern_explore_screen.dart' show executeCustomEffectIfNeeded;

/// Browse Design Library section with category cards
class DesignLibraryBrowser extends ConsumerWidget {
  const DesignLibraryBrowser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(patternCategoriesProvider);
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
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'Browse Design Library',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFFDCF0FF),
              ),
            ),
            Text(
              'Explore all categories',
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFFDCF0FF).withValues(alpha: 0.50),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.55,
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

  static const _accentColor = NexGenPalette.cyan;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push('/my-designs');
        },
        splashColor: _accentColor.withValues(alpha: 0.10),
        highlightColor: _accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _accentColor.withValues(alpha: 0.12),
                NexGenPalette.matteBlack.withValues(alpha: 0.98),
              ],
              stops: const [0.0, 1.0],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _accentColor.withValues(alpha: 0.20),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _accentColor.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Compact icon with subtle glow ring
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accentColor.withValues(alpha: 0.12),
                    border: Border.all(
                      color: _accentColor.withValues(alpha: 0.25),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    size: 16,
                    color: _accentColor,
                    shadows: [
                      Shadow(
                        color: _accentColor.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'My Saved Designs',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: _accentColor.withValues(alpha: 0.4),
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

/// Individual category card for the Design Library browser
class _DesignLibraryCategoryCard extends ConsumerWidget {
  final PatternCategory category;

  const _DesignLibraryCategoryCard({required this.category});

  IconData _heroIconForCategory(String categoryId) {
    switch (categoryId) {
      case 'cat_arch':
        return Icons.villa;
      case 'cat_holiday':
        return Icons.celebration;
      case 'cat_sports':
        return Icons.emoji_events;
      case 'cat_season':
        final now = DateTime.now();
        final m = now.month, d = now.day;
        if ((m == 3 && d >= 20) || m == 4 || m == 5 || (m == 6 && d < 21)) return Icons.local_florist;
        if ((m == 6 && d >= 21) || m == 7 || m == 8 || (m == 9 && d < 23)) return Icons.wb_sunny;
        if ((m == 9 && d >= 23) || m == 10 || m == 11 || (m == 12 && d < 21)) return Icons.park;
        return Icons.ac_unit;
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

  /// Accent color derived from the category name string.
  Color _accentForName(String name) {
    final n = name.toLowerCase();
    if (n.contains('architectural') || n.contains('white')) return const Color(0xFFDCF0FF);
    if (n.contains('holiday')) return const Color(0xFFFF3C3C);
    if (n.contains('season')) return const Color(0xFFFF8C00);
    if (n.contains('game') || n.contains('fan')) return const Color(0xFF00D4FF);
    if (n.contains('sport') || n.contains('team') || n.contains('soccer') ||
        n.contains('football') || n.contains('baseball')) return const Color(0xFF6E2FFF);
    return const Color(0xFF00D4FF);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heroIcon = _heroIconForCategory(category.id);
    final accent = _accentForName(category.name);
    final pinnedIds = ref.watch(pinnedCategoryIdsProvider);
    final isPinned = pinnedIds.contains(category.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.push(
            '/explore/library/${category.id}',
            extra: {'name': category.name},
          );
        },
        splashColor: accent.withValues(alpha: 0.12),
        highlightColor: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111527),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accent.withValues(alpha: 0.25), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Radial accent glow from bottom-center upward
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.bottomCenter,
                      radius: 0.9,
                      colors: [
                        accent.withValues(alpha: 0.0),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.6],
                    ),
                  ),
                ),
              ),

              // Centered icon
              Center(
                child: Icon(
                  heroIcon,
                  size: 36,
                  color: accent.withValues(alpha: 0.85),
                  shadows: [
                    Shadow(color: accent.withValues(alpha: 0.4), blurRadius: 16),
                  ],
                ),
              ),

              // Category name — bottom-left
              Positioned(
                left: 12,
                bottom: 14,
                right: 30,
                child: Text(
                  category.name,
                  style: const TextStyle(
                    color: Color(0xFFDCF0FF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Pin button — top-right
              Positioned(
                right: 4,
                top: 4,
                child: GestureDetector(
                  onTap: () => _togglePin(context, ref, isPinned),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      color: isPinned ? NexGenPalette.cyan : Colors.white.withValues(alpha: 0.6),
                      size: 13,
                    ),
                  ),
                ),
              ),

              // Glowing LED strip along the bottom edge
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: accent,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.70),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
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
                    context.push('/my-designs');
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
      var payload = design.toWledPayload();
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isNotEmpty) payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
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
        var payload = <String, dynamic>{
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

        final channels = ref.read(effectiveChannelIdsProvider);
        if (channels.isNotEmpty) payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
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

  IconData _heroIconForSubCategory(String subId) {
    if (subId.contains('warm') || subId.contains('white')) return Icons.lightbulb;
    if (subId.contains('cool') || subId.contains('ice')) return Icons.ac_unit;
    if (subId.contains('fire') || subId.contains('flame')) return Icons.local_fire_department;
    if (subId.contains('ocean') || subId.contains('water')) return Icons.water;
    if (subId.contains('forest') || subId.contains('nature')) return Icons.forest;
    if (subId.contains('rain') || subId.contains('storm')) return Icons.thunderstorm;
    if (subId.contains('sun') || subId.contains('gold')) return Icons.wb_sunny;
    if (subId.contains('night') || subId.contains('star')) return Icons.nightlight_round;
    if (subId.contains('party') || subId.contains('dance')) return Icons.music_note;
    if (subId.contains('holiday') || subId.contains('festiv')) return Icons.celebration;
    if (subId.contains('sport') || subId.contains('team')) return Icons.emoji_events;
    if (subId.contains('flag') || subId.contains('patriot')) return Icons.flag;
    return Icons.auto_awesome;
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