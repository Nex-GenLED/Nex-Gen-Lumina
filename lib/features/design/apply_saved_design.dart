import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/wled/device_identity.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/features/schedule/schedule_off_warning.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';

/// Canonical "apply a saved design" routine.
///
/// Mirrors the 6-step shape of ColorwayEffectSelectorPage._applyPattern
/// (colorway_effect_selector.dart:213-345) so saved designs participate in
/// the SAME apply path as catalog patterns. Replaces the degraded bespoke
/// MyDesignsScreen._applyDesign apply (audit 2026-05-29 / #62 / #81).
///
/// Steps:
///   1. SyncWarningDialog.checkAndProceed — auto-pause Neighborhood Sync.
///   2. effectiveChannelIds U1 gate — skip if no channels.
///   3. applyChannelFilter — narrow seg[] to selected channels.
///   4. repo.applyJson — Bug B chokepoint (#77).
///   5. wledStateProvider.notifier.applyPreviewSync — dashboard preview
///      cache + #77 poll-overwrite suppression window. Kills the stale
///      colorSequence carry-over that left a previous design's colors
///      rendering until the next device poll.
///   6. activePresetLabelProvider.notifier.setLabelWithFingerprint(
///      design.name, currentState) — the Now Playing label is the
///      DESIGN'S own name. Kills the #81 wrong-label fall-through to
///      the effect-name lookup (which used to surface "Halloween Eyes"
///      for the fx=83 substitution case before #82 corrected the
///      lookup to the device-canonical catalog).
Future<void> applySavedDesign(
  BuildContext context,
  WidgetRef ref,
  CustomDesign design,
) async {
  final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
  if (!shouldProceed) return;

  final repo = ref.read(wledRepositoryProvider);
  if (repo == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(applyBlockedReason(ref.read) ?? 'No device connected'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
    return;
  }

  // The gate is read for the EFFECT shape below; a positional design decides
  // its own channels (row 40). A closed gate says why, never returns silently
  // (row 1 / foundation P2).
  final channels = ref.read(effectiveChannelIdsProvider);
  if (channels.isEmpty && !design.isPositional) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(applyBlockedReason(ref.read) ?? kApplyBlockedFallback),
        backgroundColor: Colors.red.shade800,
      ));
    }
    return;
  }

  // A POSITIONAL design (painted, or AI-composed) goes through the SAME
  // per-pixel spine the editor's own Apply uses, so it lands exactly as it
  // looked when it was saved. This button used to push every design through
  // the effect shape — first three colour groups, positions discarded, fx:83 —
  // which turned a painted house almost entirely dark under an "Applied"
  // toast (audit F3; bench: 257 black + one 33-LED block). The chunked spine
  // also has no payload-size ceiling, unlike a single applyJson.
  Map<String, dynamic> payload;
  DesignMotion? motion;
  if (design.isPositional) {
    payload = const <String, dynamic>{};
    // +110 E2 row 42: the DETAILED report, not a blanket "couldn't reach
    // your lights" — "the background landed but the pixels didn't" and "no
    // controller" are different sentences. Row 41: a composed design with
    // motion runs its effect (see applyPositionalDesignDetailed).
    final report = await applyCustomDesignDetailed(ref, design);
    if (!report.ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(report.result == DesignApplyResult.noMap
              ? '"${design.name}" has no lit pixels to apply.'
              // #94 — an identity refusal must say so, not blame the network.
              : (takeIdentityRefusalMessage() ??
                  report.message ??
                  "Couldn't apply \"${design.name}\" — your lights didn't "
                      'accept it. Check the connection and try again.')),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 6),
        ));
      }
      return;
    }
    motion = motionEffectOf(design);
  } else {
    payload = applyChannelFilter(
      design.toWledPayload(),
      channels,
      ref.read(deviceChannelsProvider),
    );

    final success = await repo.applyJson(payload);
    if (!success) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to apply ${design.name}')),
        );
      }
      return;
    }
  }

  final previewColors = _previewColorsFromDesign(design);
  final firstChannel = design.channels.firstWhere(
    (c) => c.included,
    orElse: () => const ChannelDesign(channelId: 0, channelName: ''),
  );
  // A per-pixel frame is static (fx 0) whatever effect id the channel stores
  // — unless the composed design carries motion, which ran as its effect.
  final effectId = design.isPositional
      ? (motion?.effectId ?? 0)
      : (_wireEffectIdFromPayload(payload) ?? firstChannel.effectId);

  ref.read(wledStateProvider.notifier).applyPreviewSync(
        colors: previewColors,
        effectId: effectId,
        // The as-sent `pal`: fx 83 + 5 is a Blocks design, fx 83 + 0 / fx 84
        // an Alternating one, and the Home hero draws them differently.
        paletteId: design.isPositional ? null : _wirePaletteIdFromPayload(payload),
        effectName: design.name,
        speed: motion?.speed ?? firstChannel.speed,
        intensity: motion?.intensity ?? firstChannel.intensity,
        // Mirror what was SENT. A design that states no brightness left the
        // controller's level alone, so the slider must stay where it is — this
        // used to show the design's unchosen 200 until the next poll.
        brightness:
            design.appliedBrightness ?? ref.read(wledStateProvider).brightness,
      );

  ref
      .read(activePresetLabelProvider.notifier)
      .setLabelWithFingerprint(design.name, ref.read(wledStateProvider));

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Applied: ${design.name}')),
    );
  }
  maybeShowManualApplyOffWarning(ref);
}

/// Gather up to 3 preview colors across all included channels. Falls back to
/// white if the design has no color groups (matches design.toWledPayload's
/// own fallback at design_models.dart:178-180).
List<Color> _previewColorsFromDesign(CustomDesign design) {
  final colors = <Color>[];
  for (final ch in design.channels.where((c) => c.included)) {
    for (final group in ch.colorGroups.take(3)) {
      colors.add(group.flutterColor);
      if (colors.length >= 3) break;
    }
    if (colors.length >= 3) break;
  }
  return colors.isEmpty ? const [Colors.white] : colors;
}

/// Extract the effect id from the first seg of the as-built (post-filter)
/// payload, since CustomDesign.toWledPayload substitutes fx 83 (Blocks) or
/// fx 84 (Alternating) for a multi-colour Solid (design_models.dart). The
/// dashboard preview uses the substituted fx so it animates whatever the
/// device animates. fx=83 → "Solid Pattern" via WledEffectsCatalog (verified
/// against device /json/effects; #82 resolved).
int? _wireEffectIdFromPayload(Map<String, dynamic> payload) {
  // firstDesignSeg, not seg[0]: applyChannelFilter emits the #67 full
  // partition, so a design scoped away from channel 0 leads with the
  // exclusion `{id:0, on:false}` — which has no fx at all.
  final fx = firstDesignSeg(payload['seg'])?['fx'];
  return fx is int ? fx : null;
}

/// The `pal` on the same seg, for the same reason.
int? _wirePaletteIdFromPayload(Map<String, dynamic> payload) {
  final pal = firstDesignSeg(payload['seg'])?['pal'];
  return pal is int ? pal : null;
}
