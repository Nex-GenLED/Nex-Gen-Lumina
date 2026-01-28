import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/theme.dart';

/// A grid widget displaying user's favorite patterns in a 2x2 compact layout
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

        // Show first 4 favorites in a 2x2 grid layout
        final displayFavorites = favorites.take(4).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              // First row (2 cards)
              Row(
                children: [
                  Expanded(
                    child: _FavoritePatternCard(
                      favorite: displayFavorites[0],
                      onTap: onPatternTap != null ? () => onPatternTap!(displayFavorites[0]) : null,
                      showAutoAddedBadge: showAutoAddedBadge,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: displayFavorites.length > 1
                        ? _FavoritePatternCard(
                            favorite: displayFavorites[1],
                            onTap: onPatternTap != null ? () => onPatternTap!(displayFavorites[1]) : null,
                            showAutoAddedBadge: showAutoAddedBadge,
                          )
                        : const _EmptySlot(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Second row (2 cards)
              Row(
                children: [
                  Expanded(
                    child: displayFavorites.length > 2
                        ? _FavoritePatternCard(
                            favorite: displayFavorites[2],
                            onTap: onPatternTap != null ? () => onPatternTap!(displayFavorites[2]) : null,
                            showAutoAddedBadge: showAutoAddedBadge,
                          )
                        : const _EmptySlot(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: displayFavorites.length > 3
                        ? _FavoritePatternCard(
                            favorite: displayFavorites[3],
                            onTap: onPatternTap != null ? () => onPatternTap!(displayFavorites[3]) : null,
                            showAutoAddedBadge: showAutoAddedBadge,
                          )
                        : const _EmptySlot(),
                  ),
                ],
              ),
            ],
          ),
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
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_border_rounded,
            size: 48,
            color: NexGenPalette.textSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No Favorites Yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: NexGenPalette.textSecondary,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your most-used patterns will appear here',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: NexGenPalette.textSecondary.withOpacity(0.7),
                ),
          ),
        ],
      ),
    );
  }
}

/// Empty slot placeholder for the 2x2 grid
class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.add_rounded,
          color: Colors.white.withOpacity(0.2),
          size: 24,
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

  /// Extract colors from patternData to create a gradient background
  /// Always returns at least one color (never empty list)
  List<Color> _extractPatternColors() {
    try {
      final seg = favorite.patternData['seg'];
      if (seg is List && seg.isNotEmpty) {
        final firstSeg = seg[0];
        if (firstSeg is Map) {
          final col = firstSeg['col'];
          if (col is List && col.isNotEmpty) {
            final colors = <Color>[];
            for (final c in col) {
              if (c is List && c.length >= 3) {
                colors.add(Color.fromARGB(
                  255,
                  (c[0] as num).toInt().clamp(0, 255),
                  (c[1] as num).toInt().clamp(0, 255),
                  (c[2] as num).toInt().clamp(0, 255),
                ));
              }
            }
            if (colors.isNotEmpty) return colors;
          }
        }
      }
    } catch (_) {}

    // Fallback: use pattern name heuristics (always returns non-empty)
    try {
      final fallback = _colorsFromPatternName(favorite.patternName);
      if (fallback.isNotEmpty) return fallback;
    } catch (_) {}

    // Ultimate fallback - ensure we never return empty list
    return [NexGenPalette.violet, NexGenPalette.cyan];
  }

  List<Color> _colorsFromPatternName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('warm white') || lower.contains('warm')) {
      return [Colors.amber, Colors.orange.shade300];
    }
    if (lower.contains('bright white') || lower.contains('bright')) {
      return [Colors.white, Colors.grey.shade300];
    }
    if (lower.contains('holiday') || lower.contains('christmas')) {
      return [Colors.red, Colors.green];
    }
    if (lower.contains('candy') || lower.contains('cane')) {
      return [Colors.red, Colors.white, Colors.red];
    }
    // Default gradient
    return [NexGenPalette.violet, NexGenPalette.cyan];
  }

  Color _textColorFor(List<Color> colors) {
    if (colors.isEmpty) return Colors.white;
    // Calculate average luminance
    double avgLuminance = 0;
    for (final c in colors) {
      avgLuminance += c.computeLuminance();
    }
    avgLuminance /= colors.length;
    return avgLuminance > 0.5 ? Colors.black87 : Colors.white;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patternColors = _extractPatternColors();
    final textColor = _textColorFor(patternColors);
    final isSystemDefault = favorite.id.startsWith('system_');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: patternColors.length == 1
                  ? [patternColors[0], patternColors[0]]
                  : patternColors,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: patternColors.first.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Subtle overlay for text readability
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withOpacity(0.15),
                        Colors.transparent,
                        Colors.black.withOpacity(0.15),
                      ],
                    ),
                  ),
                ),
              ),
              // Content - centered text in compact view
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // System default star icon
                      if (isSystemDefault) ...[
                        Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: textColor.withOpacity(0.9),
                        ),
                        const SizedBox(width: 6),
                      ],
                      // Pattern name (truncated for compact view)
                      Flexible(
                        child: Text(
                          favorite.patternName,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withOpacity(0.4),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
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
}
