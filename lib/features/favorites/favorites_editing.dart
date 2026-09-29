// lib/features/favorites/favorites_editing.dart
//
// Removing and replacing My Favorites tiles (+110 E1, owner item A).
//
// Before this, the two reserved whites could not be changed at all and the
// customer's own favourites could not be removed from Home. Every tile is now
// replaceable and removable:
//
//   • a customer favourite is a `/users/{uid}/favorites/{id}` document —
//     removing it deletes the document; replacing it saves the chosen design
//     as a new favourite FIRST and deletes the old one only once that landed;
//   • a reserved white is not a document (it is built from the profile's white
//     preferences so it renders at once) — removing it records its slot id in
//     the profile's `favorite_whites_hidden`; replacing it saves the chosen
//     design and then hides the white.
//
// Nothing here rewrites an existing favourite document.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart'
    show favoritesFirestoreProvider;
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';

/// Reserved tiles are built locally, not stored as favourite documents.
bool isReservedFavoriteTile(FavoritePattern favorite) =>
    favorite.id.startsWith('white_') || favorite.id.startsWith('system_');

/// Removes [favorite] from My Favorites. Throws when the write fails — the
/// caller says so rather than showing the tile gone.
Future<void> removeFavoriteTile(
  ProviderContainer container,
  FavoritePattern favorite,
) async {
  if (isReservedFavoriteTile(favorite)) {
    await hideReservedFavoriteTile(container, favorite.id);
    return;
  }
  // The account whose favourites are ON SCREEN — the effective uid, so an
  // installer viewing a customer removes the customer's tile, not their own.
  final uid = container.read(effectiveUserUidProvider);
  if (uid == null || uid.isEmpty) {
    throw StateError('Sign in to change your favorites.');
  }
  await container
      .read(favoritesFirestoreProvider)
      .doc('users/$uid/favorites/${favorite.id}')
      .delete();
}

/// Records [slotId] (`white_primary` / `white_complement`) as removed.
Future<void> hideReservedFavoriteTile(
  ProviderContainer container,
  String slotId,
) async {
  final profile = container.read(currentUserProfileProvider).valueOrNull;
  if (profile == null) {
    throw StateError("Your profile hasn't loaded yet. Try again in a moment.");
  }
  final next = <String>{...profile.favoriteWhitesHidden, slotId}.toList()
    ..sort();
  await container
      .read(userServiceProvider)
      .updateUserProfile(profile.id, {'favorite_whites_hidden': next});
}
