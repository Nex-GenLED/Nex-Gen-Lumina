import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/theme.dart';

/// A grid widget displaying user's favorite patterns
class FavoritesGrid extends ConsumerWidget {
  final Function(FavoritePattern)? onPatternTap;
  final bool showAutoAddedBadge;

  const FavoritesGrid({
    super.key,
    this.onPatternTap,
    this.showAutoAddedBadge = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoritePatternsProvider);

    return favoritesAsync.when(
      data: (favorites) {
        if (favorites.isEmpty) {
          return _buildEmptyState(context, ref);
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: favorites.length,
          itemBuilder: (context, index) {
            final favorite = favorites[index];
            return _FavoritePatternCard(
              favorite: favorite,
              onTap: onPatternTap != null ? () => onPatternTap!(favorite) : null,
              showAutoAddedBadge: showAutoAddedBadge,
            );
          },
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Error loading favorites',
            style: TextStyle(color: Colors.red[300]),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_border_rounded,
              size: 64,
              color: NexGenPalette.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Favorites Yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: NexGenPalette.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Lumina will automatically add your\nmost-used patterns here',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: NexGenPalette.textSecondary.withOpacity(0.7),
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(favoritesNotifierProvider.notifier).refreshAutoFavorites();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh Favorites'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritePatternCard extends ConsumerWidget {
  final FavoritePattern favorite;
  final VoidCallback? onTap;
  final bool showAutoAddedBadge;

  const _FavoritePatternCard({
    required this.favorite,
    this.onTap,
    required this.showAutoAddedBadge,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: NexGenPalette.cardBackground,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: NexGenPalette.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pattern name
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          favorite.patternName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: NexGenPalette.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Used ${favorite.usageCount} times',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: NexGenPalette.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  // Last used
                  if (favorite.lastUsed != null)
                    Text(
                      _formatLastUsed(favorite.lastUsed!),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: NexGenPalette.textSecondary.withOpacity(0.7),
                          ),
                    ),
                ],
              ),
            ),
            // Auto-added badge
            if (showAutoAddedBadge && favorite.autoAdded)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: NexGenPalette.primary.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 12,
                        color: NexGenPalette.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Auto',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NexGenPalette.primary,
                              fontSize: 10,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            // Remove button (only for non-system favorites)
            if (!favorite.id.startsWith('system_'))
              Positioned(
                bottom: 8,
                right: 8,
                child: IconButton(
                  icon: Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 20,
                    color: NexGenPalette.textSecondary.withOpacity(0.5),
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: NexGenPalette.cardBackground,
                        title: const Text('Remove Favorite'),
                        content: Text('Remove "${favorite.patternName}" from favorites?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      await ref
                          .read(favoritesNotifierProvider.notifier)
                          .removeFavorite(favorite.id);
                    }
                  },
                ),
              ),
            // System default badge
            if (favorite.id.startsWith('system_'))
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: NexGenPalette.cyan.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: NexGenPalette.cyan,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatLastUsed(DateTime lastUsed) {
    final now = DateTime.now();
    final difference = now.difference(lastUsed);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }
}
