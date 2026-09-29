import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/favorites/favorites_editing.dart';
import 'package:nexgen_command/features/favorites/favorites_picker.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/theme.dart';

/// My Favorites on Home: the customer's favourite looks, two to a row, and
/// EXACTLY ONE "+" to add another (+110 E1, owner item A).
///
/// It used to be a fixed 2×2: a row of two reserved whites nobody could
/// change, then the first TWO of the customer's own favourites, padded with
/// empty "+" slots. Now:
///   • every tile — the whites included — can be replaced or removed (long
///     press a tile, or tap Edit);
///   • every favourite the customer has is shown, not just two;
///   • the add tile appears once, at the end.
///
/// The whites still render at once from local state (favoriteWhiteSlotsProvider)
/// — the instant render the reserved row was built for. Only the customer's own
/// favourites wait on Firestore, and every state of that wait is one tile-row
/// inside this section (see userFavoritePatternsProvider for why it always
/// ends).
class FavoritesGrid extends ConsumerStatefulWidget {
  final Function(FavoritePattern)? onPatternTap;
  final bool showAutoAddedBadge;

  /// Start in Edit mode (the Replace / Remove buttons on every tile).
  final bool initiallyEditing;

  const FavoritesGrid({
    super.key,
    this.onPatternTap,
    this.showAutoAddedBadge = true,
    this.initiallyEditing = false,
  });

  @override
  ConsumerState<FavoritesGrid> createState() => _FavoritesGridState();
}

class _FavoritesGridState extends ConsumerState<FavoritesGrid> {
  late bool _editing = widget.initiallyEditing;

  @override
  Widget build(BuildContext context) {
    final whites = ref.watch(favoriteWhiteSlotsProvider);
    final userFavoritesAsync = ref.watch(userFavoritePatternsProvider);
    final userFavorites = userFavoritesAsync.valueOrNull ?? const [];
    final hasTiles = whites.isNotEmpty || userFavorites.isNotEmpty;

    Widget tile(FavoritePattern f) => _FavoritePatternCard(
          key: ValueKey('favorite-tile-${f.id}'),
          favorite: f,
          editing: _editing,
          onTap: _editing
              ? () => _showTileActions(f)
              : (widget.onPatternTap != null
                  ? () => widget.onPatternTap!(f)
                  : null),
          onLongPress: () => _showTileActions(f),
          onReplace: () => _replace(f),
          onRemove: () => _confirmRemove(f),
        );

    // The customer-favourites part: tiles when loaded, otherwise one
    // full-width status row. Retry invalidates the provider; show that it is
    // loading again rather than leaving the error row up (Riverpod's default
    // for a refresh).
    final Widget? statusRow = userFavoritesAsync.when(
      skipLoadingOnRefresh: false,
      data: (_) => null,
      loading: () => const _FavoritesLoadingRow(),
      error: (error, stack) {
        debugPrint('FavoritesGrid: error loading favorites: $error');
        return _FavoritesErrorRow(
          onRetry: () => ref.invalidate(userFavoritePatternsProvider),
        );
      },
    );
    final loaded = userFavoritesAsync.hasValue && !userFavoritesAsync.isLoading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasTiles)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('favorites-edit-toggle'),
                onPressed: () => setState(() => _editing = !_editing),
                icon: Icon(_editing ? Icons.check_rounded : Icons.edit_outlined,
                    size: 16),
                label: Text(_editing ? 'Done' : 'Edit'),
                style: TextButton.styleFrom(
                  foregroundColor: NexGenPalette.cyan,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          LayoutBuilder(builder: (context, constraints) {
            const gap = 10.0;
            final half = (constraints.maxWidth - gap) / 2;
            Widget sized(Widget child) => SizedBox(width: half, child: child);
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final w in whites) sized(tile(w)),
                if (loaded)
                  for (final f in userFavorites) sized(tile(f)),
                if (statusRow != null)
                  SizedBox(width: constraints.maxWidth, child: statusRow),
                // Exactly one — and, with nothing else to show, the whole
                // row, with words.
                SizedBox(
                  width: hasTiles || statusRow != null
                      ? half
                      : constraints.maxWidth,
                  child: _AddFavoriteTile(
                    labelled: !hasTiles && statusRow == null,
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Future<void> _showTileActions(FavoritePattern favorite) async {
    final choice = await showModalBottomSheet<_TileAction>(
      context: context,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  favorite.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const ValueKey('favorite-action-replace'),
                leading: const Icon(Icons.swap_horiz_rounded,
                    color: NexGenPalette.cyan),
                title: const Text('Replace…',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Pick a different look for this tile',
                    style: TextStyle(color: NexGenPalette.textMedium)),
                onTap: () => Navigator.of(sheet).pop(_TileAction.replace),
              ),
              ListTile(
                key: const ValueKey('favorite-action-remove'),
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent),
                title: const Text('Remove from My Favorites',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () => Navigator.of(sheet).pop(_TileAction.remove),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _TileAction.replace:
        _replace(favorite);
      case _TileAction.remove:
        await _confirmRemove(favorite);
    }
  }

  void _replace(FavoritePattern favorite) {
    final container = ProviderScope.containerOf(context, listen: false);
    openFavoritesPicker(
      context,
      replacing: favorite.displayName,
      removeReplaced: () => removeFavoriteTile(container, favorite),
    );
  }

  Future<void> _confirmRemove(FavoritePattern favorite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove favorite?'),
        content: Text(
            'Remove "${favorite.displayName}" from My Favorites? Your lights '
            "don't change."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('favorite-remove-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await removeFavoriteTile(container, favorite);
      messenger.showSnackBar(SnackBar(
        content: Text('Removed "${favorite.displayName}" from My Favorites'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(
            "Couldn't remove \"${favorite.displayName}\" — try again."),
        backgroundColor: Colors.orange.shade800,
      ));
    }
  }
}

enum _TileAction { replace, remove }

/// The frame every status state is drawn in: the height and outline of a
/// favorite card, so the section does not jump between states.
class _FavoritesStatusRow extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _FavoritesStatusRow({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _FavoritesLoadingRow extends StatelessWidget {
  const _FavoritesLoadingRow();

  @override
  Widget build(BuildContext context) {
    return const _FavoritesStatusRow(
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _FavoritesErrorRow extends StatelessWidget {
  final VoidCallback onRetry;

  const _FavoritesErrorRow({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _FavoritesStatusRow(
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 20,
              color: NexGenPalette.textSecondary.withValues(alpha: 0.6)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Couldn't load your favorites",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: NexGenPalette.textSecondary,
                  ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// THE add tile — there is exactly one. With no favourites at all it spans
/// the row and says what it does.
class _AddFavoriteTile extends StatelessWidget {
  final bool labelled;
  const _AddFavoriteTile({required this.labelled});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add a favorite',
      child: _FavoritesStatusRow(
        onTap: () => openFavoritesPicker(context),
        child: Row(
          key: const ValueKey('favorites-add-tile'),
          mainAxisAlignment:
              labelled ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded,
                size: 22, color: Colors.white.withValues(alpha: 0.5)),
            if (labelled) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Add a favorite — pick any look from the library',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: NexGenPalette.textSecondary,
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

class _FavoritePatternCard extends ConsumerWidget {
  final FavoritePattern favorite;
  final bool editing;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  const _FavoritePatternCard({
    super.key,
    required this.favorite,
    required this.editing,
    required this.onTap,
    required this.onLongPress,
    required this.onReplace,
    required this.onRemove,
  });

  /// Extract colors from patternData to create a gradient background
  /// Always returns at least one color (never empty list)
  List<Color> _extractPatternColors() {
    try {
      // The DESIGN segment, not seg[0] — see firstRealDesignSegment.
      final col = firstRealDesignSegment(favorite.patternData)?['col'];
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
    } catch (e) {
      debugPrint('Error in favorites grid extracting colors from payload: $e');
    }

    // Fallback: use pattern name heuristics (always returns non-empty)
    try {
      final fallback = _colorsFromPatternName(favorite.patternName);
      if (fallback.isNotEmpty) return fallback;
    } catch (e) {
      debugPrint('Error in favorites grid _colorsFromPatternName: $e');
    }

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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          // A minimum, not a fixed height: the name wraps at large text.
          constraints: const BoxConstraints(minHeight: 52),
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
              color: editing
                  ? NexGenPalette.cyan.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: patternColors.first.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Container(
            // Subtle overlay for text readability
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.15),
                ],
              ),
            ),
            padding: EdgeInsets.fromLTRB(12, 8, editing ? 4 : 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    favorite.displayName,
                    key: const ValueKey('favorite-tile-name'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                    // Data, not copy: the full name is in the tile's action
                    // sheet and in Now Playing once applied.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: editing ? TextAlign.start : TextAlign.center,
                  ),
                ),
                if (editing) ...[
                  _TileIconButton(
                    key: ValueKey('favorite-replace-${favorite.id}'),
                    icon: Icons.swap_horiz_rounded,
                    tooltip: 'Replace',
                    color: textColor,
                    onPressed: onReplace,
                  ),
                  _TileIconButton(
                    key: ValueKey('favorite-remove-${favorite.id}'),
                    icon: Icons.close_rounded,
                    tooltip: 'Remove',
                    color: textColor,
                    onPressed: onRemove,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _TileIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: color),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
    );
  }
}
