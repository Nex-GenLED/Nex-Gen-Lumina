import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/favorites/favorite_design_payload.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

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

  const FavoriteApplyOutcome(this.status, this.payload, {this.perPixel = false});

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
    return FavoriteApplyOutcome(FavoriteApplyStatus.noDevice, payload);
  }
  final channels = read(effectiveChannelIdsProvider);
  if (channels.isEmpty) {
    return FavoriteApplyOutcome(FavoriteApplyStatus.noChannels, payload);
  }

  final design = perPixelDesignOfFavorite(payload);
  if (design != null) {
    final result = await applyPositionalDesignWith(read, design);
    return FavoriteApplyOutcome(
      result == DesignApplyResult.applied
          ? FavoriteApplyStatus.applied
          : FavoriteApplyStatus.failed,
      payload,
      perPixel: true,
    );
  }

  final filtered =
      applyChannelFilter(payload, channels, read(deviceChannelsProvider));
  final ok = await repo.applyJson(filtered);
  return FavoriteApplyOutcome(
    ok ? FavoriteApplyStatus.applied : FavoriteApplyStatus.failed,
    filtered,
  );
}
