// Build-time visibility switches for the Explore pattern library, withheld
// from the first App Store build (120) for App Review guideline 5.2
// (third-party marks). Nothing here deletes data. The palettes stay in
// lib/data/, ids are unchanged, and anything a customer already saved from
// a hidden folder keeps working. A hidden category returns by flipping one
// constant.
//
// Same shape as features/feature_visibility.dart (owned by the app/build
// window, so not edited here): each const has a Provider twin, the Provider's
// default is always the const, and tests override the Provider.

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Explore → "Movies & Superheroes" (cat_movies): film studio, franchise and
/// character names (lib/data/movies_superheroes_palettes.dart). Hidden: no
/// category tile, and none of its folders or palettes in browse, search or
/// any library picker.
const bool kMoviesCategoryVisible = false;

final moviesCategoryVisibleProvider =
    Provider<bool>((_) => kMoviesCategoryVisible);
