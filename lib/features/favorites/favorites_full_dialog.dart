// lib/features/favorites/favorites_full_dialog.dart
//
// #164 — favorites are capped at two (favorite_doc.dart). Every EXPLICIT save
// (the heart, Home "+", the Explore card's "Save to Favorites", a Home
// suggestion) goes through [saveFavoriteWithCap]: it saves, and when the list
// is full it says so plainly and lets the customer put the new design in the
// place of one they have. Nothing is ever removed without that choice.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/patterns/utils/pattern_display_name.dart';

/// What [saveFavoriteWithCap] did.
enum FavoriteSaveOutcome {
  /// The favorite was added (or an existing one refreshed).
  saved,

  /// The list was full and the customer chose one to replace.
  replaced,

  /// The list was full and the customer kept what they had.
  keptExisting,
}

/// One favorite the full-list dialog offers to replace.
class FavoriteChoice {
  final String id;
  final String name;
  const FavoriteChoice(this.id, this.name);
}

/// Saves a favorite. When the account already holds [kMaxFavorites], shows
/// [kFavoritesFullMessage] with the current favorites and, if the customer
/// picks one, replaces it with the new design in one write.
///
/// Takes a [ProviderContainer] rather than a widget ref so the save finishes
/// even if the widget that asked is gone by the time the dialog closes. Any
/// other failure is rethrown for the caller to report.
Future<FavoriteSaveOutcome> saveFavoriteWithCap(
  BuildContext context,
  ProviderContainer container, {
  required String patternId,
  required String patternName,
  required Map<String, dynamic> payload,
}) async {
  final notifier = container.read(favoritesNotifierProvider.notifier);
  try {
    await notifier.addFavorite(
      patternId: patternId,
      patternName: patternName,
      patternData: payload,
    );
    return FavoriteSaveOutcome.saved;
  } on FavoritesFullException {
    if (!context.mounted) return FavoriteSaveOutcome.keptExisting;
    List<FavoritePattern> current;
    try {
      current = await container
          .read(allFavoritesProvider.future)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      current = const [];
    }
    if (!context.mounted) return FavoriteSaveOutcome.keptExisting;
    final replaceId = await showFavoritesFullDialog(
      context,
      newName: displayNameFor(patternName),
      // Only the customer's own favorites — the ones the cap counts.
      current: [
        for (final f in current)
          if (!f.autoAdded) FavoriteChoice(f.patternId, displayNameFor(f.name)),
      ],
    );
    if (replaceId == null) return FavoriteSaveOutcome.keptExisting;
    await notifier.replaceFavorite(
      replaceId: replaceId,
      patternId: patternId,
      patternName: patternName,
      patternData: payload,
    );
    return FavoriteSaveOutcome.replaced;
  }
}

/// The full-list dialog: the cap in plain words, then one button per
/// favorite to replace it with [newName], and "Keep my favorites". Returns
/// the id to replace, or null. Scrolls at large text sizes.
Future<String?> showFavoritesFullDialog(
  BuildContext context, {
  required String newName,
  required List<FavoriteChoice> current,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('favorites-full-dialog'),
      title: const Text('Favorites are full'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(kFavoritesFullMessage),
            if (current.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Put "$newName" in place of:'),
              const SizedBox(height: 4),
              for (final f in current)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: ValueKey('favorites-replace-${f.id}'),
                    onPressed: () => Navigator.of(ctx).pop(f.id),
                    child: Text(f.name),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('favorites-full-keep'),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Keep my favorites'),
        ),
      ],
    ),
  );
}

/// The snackbar line for [outcome] after saving [name].
String favoriteSaveMessage(FavoriteSaveOutcome outcome, String name) =>
    switch (outcome) {
      FavoriteSaveOutcome.saved => 'Saved "$name" to Favorites',
      FavoriteSaveOutcome.replaced => 'Saved "$name" to Favorites',
      FavoriteSaveOutcome.keptExisting => kFavoritesFullMessage,
    };
