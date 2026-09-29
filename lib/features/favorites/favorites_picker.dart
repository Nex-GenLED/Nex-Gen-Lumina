// lib/features/favorites/favorites_picker.dart
//
// The Favorites "+" flow: browse the design library in SAVE mode and add the
// chosen design to Favorites.
//
// Until 2026-09-25 the "+" tile pushed the plain Explore tab, where every
// card tap APPLIED the design to the controller and nothing was ever added to
// Favorites. Now it opens the library with a Favorites destination: tapping
// "Save to Favorites" writes the favorite and returns; the only thing that
// reaches the controller is the selector's explicit "Preview on lights".
//
// +110 E1 (owner item A): the same flow REPLACES a tile. The chosen design is
// saved first; the tile being replaced is removed only once that save landed,
// so a failed save never leaves the customer with one favourite fewer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wled/colorway_effect_selector.dart'
    show LibraryDesignSelection, favoritePatternIdFor;
import '../wled/pattern_theme_selection.dart' show LibraryBrowserScreen;
import 'favorites_providers.dart';

/// Persist [selection] as a favorite. No controller write.
Future<void> saveFavoriteSelection(
  ProviderContainer container,
  LibraryDesignSelection selection,
) {
  return container.read(favoritesNotifierProvider.notifier).addToFavorites(
        patternId: favoritePatternIdFor(selection),
        patternName: selection.name,
        wledPayload: selection.wledPayload,
      );
}

/// The SAVE-mode callback the Favorites picker hands to the library.
///
/// [replacing] names the tile being replaced; [removeReplaced] removes it and
/// runs only after the new favourite was saved.
void Function(LibraryDesignSelection) favoritesSaveHandler(
  BuildContext context,
  ProviderContainer container, {
  String? replacing,
  Future<void> Function()? removeReplaced,
}) {
  return (selection) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await saveFavoriteSelection(container, selection);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't save to Favorites: $e"),
        backgroundColor: Colors.red.shade800,
      ));
      return;
    }
    var message = replacing == null
        ? 'Saved "${selection.name}" to Favorites'
        : 'Replaced "$replacing" with "${selection.name}"';
    if (removeReplaced != null) {
      try {
        await removeReplaced();
      } catch (e) {
        message = 'Saved "${selection.name}" to Favorites, but '
            '"$replacing" couldn\'t be removed. Try removing it again.';
      }
    }
    messenger.showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 3),
    ));
    if (navigator.canPop()) navigator.pop();
  };
}

/// Open the library in SAVE-to-Favorites mode on the root navigator.
///
/// With [replacing] and [removeReplaced], the chosen design takes that tile's
/// place (see [favoritesSaveHandler]).
void openFavoritesPicker(
  BuildContext context, {
  String? replacing,
  Future<void> Function()? removeReplaced,
}) {
  final container = ProviderScope.containerOf(context);
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (ctx) => LibraryBrowserScreen(
        nodeId: null,
        saveDestinationLabel: 'Favorites',
        onDesignSelected: favoritesSaveHandler(
          ctx,
          container,
          replacing: replacing,
          removeReplaced: removeReplaced,
        ),
      ),
    ),
  );
}
