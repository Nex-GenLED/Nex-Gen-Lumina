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
void Function(LibraryDesignSelection) favoritesSaveHandler(
  BuildContext context,
  ProviderContainer container,
) {
  return (selection) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await saveFavoriteSelection(container, selection);
      messenger.showSnackBar(SnackBar(
        content: Text('Saved "${selection.name}" to Favorites'),
        duration: const Duration(seconds: 2),
      ));
      if (navigator.canPop()) navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't save to Favorites: $e"),
        backgroundColor: Colors.red.shade800,
      ));
    }
  };
}

/// Open the library in SAVE-to-Favorites mode on the root navigator.
void openFavoritesPicker(BuildContext context) {
  final container = ProviderScope.containerOf(context);
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (ctx) => LibraryBrowserScreen(
        nodeId: null,
        saveDestinationLabel: 'Favorites',
        onDesignSelected: favoritesSaveHandler(ctx, container),
      ),
    ),
  );
}
