import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
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
      onTap: () => _toggleFavorite(context, ref, isFavorited),
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

  /// S5 (Audit-2): previously add/removeFromFavorites were fired without
  /// await or try/catch — they rethrow on failure, producing an unhandled
  /// async exception while the heart silently reverted to its prior state.
  /// Now we await, surface failures to the user, and handle the signed-out
  /// case explicitly (the notifier silently no-ops on a null user, which
  /// would otherwise look like a successful toggle that persisted nothing).
  Future<void> _toggleFavorite(
      BuildContext context, WidgetRef ref, bool currentlyFavorited) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to save favorites')),
        );
      }
      return;
    }

    final notifier = ref.read(favoritesNotifierProvider.notifier);
    try {
      if (currentlyFavorited) {
        await notifier.removeFromFavorites(patternId);
      } else {
        await notifier.addFavorite(
          patternId: patternId,
          patternName: patternName,
          patternData: patternData,
        );
      }
    } catch (e) {
      // The heart is driven by favoritedPatternIdsProvider, so a failed write
      // leaves it in its pre-tap state automatically — just surface the error.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(currentlyFavorited
                ? 'Failed to remove favorite'
                : 'Failed to save favorite'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
}
