// #80 — "absent" and "unknown" are DIFFERENT, and the hero image is where the
// app used to collapse them.
//
// The dashboard read the profile with `hasValue` for the guard and
// `maybeWhen(data:, orElse: null)` for the value. On a Riverpod
// loading-with-previous-value state those DISAGREE: `hasValue` is true (there
// IS a cached profile) but the value is `AsyncLoading`, so `data:` does not
// match and `orElse` returns null. The guard admitted the rebuild; the read
// then reported "no photo". `_updateHeroImage` could not tell *"this user has
// no photo"* from *"the profile is momentarily unavailable"* — both arrived as
// `null` — so it committed the stock house to state, over the customer's own.
//
// This file makes the third state nameable. Same defect class as #78
// (fabricated geometry) and the geometry gate's "unreadable ≠ empty":
// ABSENT MUST NOT RENDER AS A VALUE, and UNKNOWN must not render as ABSENT.
//
// Tyler, 2026-08-15: *a fallback must never flash stock over an existing user
// photo, even once.* Rarity is not a fix; it only decides who sees it.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/models/user_model.dart';

/// What the hero card should do with the profile it currently has.
sealed class HeroImageIntent {
  const HeroImageIntent();
}

/// The profile is not resolved (loading, refreshing, erroring). HOLD
/// LAST-KNOWN-GOOD: touch nothing, leave whatever is on screen on screen.
/// Before anything has ever resolved, that means the matte-black interim —
/// which is correct, because we genuinely do not know yet.
class HeroHold extends HeroImageIntent {
  const HeroHold();
}

/// A loaded profile AFFIRMATIVELY reports no house photo. This — and only
/// this — is when the stock house is the right thing to show.
class HeroStock extends HeroImageIntent {
  const HeroStock();
}

/// A loaded profile carries a photo.
class HeroPhoto extends HeroImageIntent {
  final String url;

  /// Roofline mask version, folded into the cache identity so a re-traced
  /// roofline re-resolves the image rather than reusing the stale one.
  final String? maskVersion;

  const HeroPhoto(this.url, {this.maskVersion});
}

/// Resolve the hero intent from the profile stream's CURRENT state.
///
/// The discriminator is `AsyncData` and nothing else — deliberately not
/// `hasValue`, which is the exact predicate that produced #80. A refresh of a
/// stream that already has a value is `AsyncLoading` with `hasValue == true`;
/// that is UNKNOWN, not "no photo".
HeroImageIntent resolveHeroImage(AsyncValue<UserModel?> profile) {
  if (profile is! AsyncData<UserModel?>) {
    // Loading (with or without a previous value) and error both land here.
    // An error is not evidence the user has no photo, so it holds too.
    return const HeroHold();
  }
  final url = profile.value?.housePhotoUrl;
  if (url == null || url.isEmpty) return const HeroStock();
  return HeroPhoto(url, maskVersion: profile.value?.rooflineMask?.toString());
}
