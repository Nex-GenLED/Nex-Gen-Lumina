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
// +110 E1 (owner item A): the same flow REPLACES a tile. #164: a favorite
// document is replaced in one write (delete + create together), so the cap of
// two holds and a failed save never leaves the customer one favourite fewer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wled/colorway_effect_selector.dart'
    show LibraryDesignSelection, favoritePatternIdFor;
import '../wled/pattern_theme_selection.dart' show LibraryBrowserScreen;
import 'favorite_doc.dart' show kFavoritesFullMessage;
import 'favorites_full_dialog.dart';
import 'favorites_providers.dart';

/// The SAVE-mode callback the Favorites picker hands to the library.
///
/// [replaceId] is the favorite document being replaced: the new design takes
/// its place in ONE write ([FavoritesNotifier.replaceFavorite]), so a full
/// list (#164) is never one over and a failed save never leaves the customer
/// one short. [removeReplaced] is for a reserved white tile, which is not a
/// document: it is hidden only once the new favorite was saved.
///
/// A plain add goes through [saveFavoriteWithCap]: on a full list the
/// customer is told and may pick one to replace. Choosing to keep what they
/// have leaves the library open.
void Function(LibraryDesignSelection) favoritesSaveHandler(
  BuildContext context,
  ProviderContainer container, {
  String? replacing,
  String? replaceId,
  Future<void> Function()? removeReplaced,
}) {
  return (selection) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final patternId = favoritePatternIdFor(selection);
    String message;
    try {
      if (replaceId != null) {
        await container.read(favoritesNotifierProvider.notifier).replaceFavorite(
              replaceId: replaceId,
              patternId: patternId,
              patternName: selection.name,
              patternData: selection.wledPayload,
            );
        message = 'Replaced "$replacing" with "${selection.name}"';
      } else {
        final outcome = await saveFavoriteWithCap(
          context,
          container,
          patternId: patternId,
          patternName: selection.name,
          payload: selection.wledPayload,
        );
        if (outcome == FavoriteSaveOutcome.keptExisting) {
          messenger.showSnackBar(
              const SnackBar(content: Text(kFavoritesFullMessage)));
          return;
        }
        message = replacing == null
            ? favoriteSaveMessage(outcome, selection.name)
            : 'Replaced "$replacing" with "${selection.name}"';
        if (removeReplaced != null && outcome == FavoriteSaveOutcome.saved) {
          try {
            await removeReplaced();
          } catch (e) {
            message = 'Saved "${selection.name}" to Favorites, but '
                '"$replacing" couldn\'t be removed. Try removing it again.';
          }
        }
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text("Couldn't save to Favorites: $e"),
        backgroundColor: Colors.red.shade800,
      ));
      return;
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
  String? replaceId,
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
          replaceId: replaceId,
          removeReplaced: removeReplaced,
        ),
      ),
    ),
  );
}
