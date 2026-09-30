import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/favorites/favorite_brightness.dart';
import 'package:nexgen_command/features/favorites/favorite_design_payload.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';

/// What applying a favorite did.
enum FavoriteApplyStatus {
  /// The controller accepted every write.
  applied,

  /// No repository — not connected to a controller.
  noDevice,

  /// The effective-channel set is empty (the U1 gate): nothing to target.
  noChannels,

  /// A write was refused. For a per-pixel favorite the lights may be showing
  /// the base without (all of) the painted pixels.
  failed,

  /// The stored payload describes no look at all — no effect, no colour on
  /// any channel. Nothing was sent: sending it would switch the channels on
  /// and change nothing else, under an "Applied" message.
  noDesign,
}

class FavoriteApplyOutcome {
  final FavoriteApplyStatus status;

  /// The WLED body to derive the dashboard preview and the usage event from.
  /// An ordinary favorite: the channel-filtered payload as sent. A per-pixel
  /// favorite: the stored payload, whole — its summary `seg` is what preview
  /// and analytics read, and logging it whole keeps the habit learner's copy
  /// of it (an auto-added favorite) re-appliable.
  final Map<String, dynamic> payload;

  /// True when the favorite went through the chunked per-pixel spine.
  final bool perPixel;

  /// Why nothing was sent, in the customer's words — set for [noDevice] and
  /// [noChannels] from `applyBlockedReason` (row 1: the grid used to return
  /// with only a debug log).
  final String? reason;

  const FavoriteApplyOutcome(this.status, this.payload,
      {this.perPixel = false, this.reason});

  bool get isApplied => status == FavoriteApplyStatus.applied;
}

/// Applies a favorite's stored [payload] — THE routine for anything holding
/// one (the dashboard's My Favorites grid today). Provider-side callers pass
/// `ref.read`.
///
/// A PER-PIXEL favorite (see `favorite_design_payload.dart`) goes through
/// [applyPositionalDesignWith] — the same chunked spine, by the same call, that
/// My Designs uses for a painted design. Everything else is one
/// channel-filtered `applyJson`, exactly as before.
///
/// This exists so the choice is made in ONE place. The grid used to inline
/// `applyChannelFilter` + `applyJson`, which is capped at 4 KB: a Static
/// favorite on any install past ~215 LEDs was refused before it was posted.
Future<FavoriteApplyOutcome> applyFavoritePayloadWith(
  ProviderReader read,
  Map<String, dynamic> payload,
) async {
  final repo = read(wledRepositoryProvider);
  if (repo == null) {
    return FavoriteApplyOutcome(FavoriteApplyStatus.noDevice, payload,
        reason: applyBlockedReason(read) ?? kApplyBlockedFallback);
  }
  // Row 1: waits for a channel source that is still answering (the first
  // seconds after launch, the first tap away from home) instead of refusing.
  final channels = await resolveEffectiveChannelIds(read);
  if (channels.isEmpty) {
    return FavoriteApplyOutcome(FavoriteApplyStatus.noChannels, payload,
        reason: applyBlockedReason(read) ?? kApplyBlockedFallback);
  }

  final design = perPixelDesignOfFavorite(payload);
  if (design != null) {
    // Item B: the design's stored level is applied only when the customer
    // chose it; otherwise the house keeps its own brightness.
    // +110 E2: a favourite keeps the Home grid's channel scope (the
    // effective set), the way an effect favourite on the same grid does;
    // a DESIGN apply (Design Studio, My Designs) goes to the channels the
    // design carries content for instead.
    final result = await applyPositionalDesignWith(
      read,
      design.copyWith(brightnessStated: favoriteStatesBrightness(payload)),
      targets: DesignApplyTargets.effective,
    );
    return FavoriteApplyOutcome(
      result == DesignApplyResult.applied
          ? FavoriteApplyStatus.applied
          : FavoriteApplyStatus.failed,
      payload,
      perPixel: true,
    );
  }

  // applyChannelFilter templates from the first REAL design segment, so a
  // favourite stored with a leading `{id: 0, on: false}` re-applies its look.
  if (payload['seg'] is List && firstRealDesignSegment(payload) == null) {
    return FavoriteApplyOutcome(FavoriteApplyStatus.noDesign, payload);
  }
  // Item B: no `bri` unless the customer saved one on purpose, and no
  // app-private keys on the wire (favorite_brightness.dart).
  final filtered = applyChannelFilter(favoritePayloadForApply(payload),
      channels, read(applyFilterChannelsProvider));
  final ok = await repo.applyJson(filtered);
  return FavoriteApplyOutcome(
    ok ? FavoriteApplyStatus.applied : FavoriteApplyStatus.failed,
    filtered,
  );
}
