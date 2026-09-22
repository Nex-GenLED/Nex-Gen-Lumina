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
        const SnackBar(content: Text('No device connected')),
      );
    }
    return;
  }

  final channels = ref.read(effectiveChannelIdsProvider);
  if (channels.isEmpty) {
    debugPrint('applySavedDesign: skip (U1 gate — no effective channels)');
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
  if (design.isPositional) {
    payload = const <String, dynamic>{};
    final result = await applyCustomDesignToLights(ref, design);
    if (result != DesignApplyResult.applied &&
        result != DesignApplyResult.staleApplied) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(result == DesignApplyResult.noMap
              ? '"${design.name}" has no lit pixels to apply.'
              // #94 — an identity refusal must say so, not blame the network.
              : (takeIdentityRefusalMessage() ??
                  "Couldn't apply \"${design.name}\" — your lights didn't "
                      'accept it. Check the connection and try again.')),
          backgroundColor: Colors.red.shade800,
        ));
      }
      return;
    }
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
  // A per-pixel frame is static (fx 0) whatever effect id the channel stores.
  final effectId = design.isPositional
      ? 0
      : (_wireEffectIdFromPayload(payload) ?? firstChannel.effectId);

  ref.read(wledStateProvider.notifier).applyPreviewSync(
        colors: previewColors,
        effectId: effectId,
        effectName: design.name,
        speed: firstChannel.speed,
        intensity: firstChannel.intensity,
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
/// payload, since CustomDesign.toWledPayload substitutes fx=83 for
/// multi-color solid (design_models.dart:185-187). The dashboard preview
/// uses the substituted fx so it animates whatever the device animates.
/// fx=83 → "Solid Pattern" via WledEffectsCatalog (verified against
/// device /json/effects; #82 resolved).
int? _wireEffectIdFromPayload(Map<String, dynamic> payload) {
  // firstDesignSeg, not seg[0]: applyChannelFilter emits the #67 full
  // partition, so a design scoped away from channel 0 leads with the
  // exclusion `{id:0, on:false}` — which has no fx at all.
  final fx = firstDesignSeg(payload['seg'])?['fx'];
  return fx is int ? fx : null;
}
