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

  /// Builds the WLED payload to store, AT TAP TIME. It is what the dashboard's
  /// My Favorites grid later POSTs to the controller, so it must be a real
  /// `/json/state` body — and for a per-LED pattern that means knowing the
  /// device's LED count, which is an async read. (This used to be a map passed
  /// at build time, and its one caller passed the editor model's own JSON:
  /// a "favorite" that WLED would have ignored key for key.)
  final Future<Map<String, dynamic>> Function() patternDataBuilder;

  /// When set, this pattern cannot be kept as a favorite: tapping an EMPTY
  /// heart shows this instead of writing. (A filled heart still un-favorites.)
  /// For a pattern whose payload My Favorites could store but never re-apply —
  /// see the Pattern Editor's Static mode.
  final String? unavailableMessage;
  final double size;
  final Color activeColor;

  const FavoriteHeartButton({
    super.key,
    required this.patternId,
    required this.patternName,
    required this.patternDataBuilder,
    this.unavailableMessage,
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

    if (!currentlyFavorited && unavailableMessage != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(unavailableMessage!),
          duration: const Duration(seconds: 5),
        ));
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
          patternData: await patternDataBuilder(),
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
