import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Reusable heart/favorite toggle button.
///
/// Shows outlined heart when not favorited, filled heart when favorited.
/// Animates between states with a satisfying scale bounce.
class FavoriteHeartButton extends ConsumerWidget {
  final String patternId;
  final String patternName;
  final Map<String, dynamic> patternData;
  final double size;
  final Color activeColor;

  const FavoriteHeartButton({
    super.key,
    required this.patternId,
    required this.patternName,
    required this.patternData,
    this.size = 24,
    this.activeColor = const Color(0xFFFF4081), // Pink/red default
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritedIds = ref.watch(favoritedPatternIdsProvider);
    final isFavorited = favoritedIds.maybeWhen(
      data: (ids) => ids.contains(patternId),
      orElse: () => false,
    );

    return GestureDetector(
      onTap: () => _toggleFavorite(ref, isFavorited),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) {
          return ScaleTransition(scale: animation, child: child);
        },
        child: Icon(
          isFavorited ? Icons.favorite : Icons.favorite_border,
          key: ValueKey(isFavorited),
          color: isFavorited ? activeColor : NexGenPalette.textSecondary,
          size: size,
        ),
      ),
    );
  }

  void _toggleFavorite(WidgetRef ref, bool currentlyFavorited) {
    final notifier = ref.read(favoritesNotifierProvider.notifier);
    if (currentlyFavorited) {
      notifier.removeFromFavorites(patternId);
    } else {
      notifier.addFavorite(
        patternId: patternId,
        patternName: patternName,
        patternData: patternData,
      );
    }
  }
}
