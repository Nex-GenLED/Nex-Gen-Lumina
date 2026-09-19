import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// Design Studio Slice 4 — the SHARED per-pixel apply spine used by the smart
/// presets (Slice 3), the manual editor, and the AI studio's "Apply to Lights"
/// (#86). One implementation, three call sites.
///
/// Transport (audit-recommended, structural since Slice 0): a solid BASE across
/// the effective channels via the normal chokepoint (applyChannelFilter →
/// applyJson), then per-channel ACCENT/paint spans via applyPerPixel (segmentId
/// == channelIndex; bypasses channel fan-out). Static `fx:0` frames; NO WLED
/// preset writes — Firestore stays the design source of truth.

enum DesignApplyResult { applied, noMap, staleApplied, error }

/// What actually happened on the wire. Every caller of the spine gets this —
/// the spine used to `await` both device writes, DROP both booleans and
/// `return true`, so the editor, the AI studio and the smart presets all
/// reported success whether or not anything reached the lights (audit F7).
enum SpineWriteResult {
  /// Every write was accepted by the controller.
  ok,

  /// No repository — not connected to a controller.
  noDevice,

  /// The effective-channel set is empty (the U1 gate): nothing to target.
  noChannels,

  /// The base write was refused. Nothing was painted.
  baseFailed,

  /// The base landed but a per-pixel paint did not: the lights are showing
  /// the BASE colour without (all of) the painted pixels.
  pixelsFailed;

  bool get isOk => this == SpineWriteResult.ok;

  /// A sentence a user can act on; null on success or when the transport
  /// layer has a more specific reason queued (identity refusal, #94).
  String? get userMessage {
    switch (this) {
      case SpineWriteResult.ok:
        return null;
      case SpineWriteResult.noDevice:
        return "Not connected to your lights.";
      case SpineWriteResult.noChannels:
        return 'No channels are selected to receive this.';
      case SpineWriteResult.baseFailed:
        return "Couldn't reach your lights — nothing was changed.";
      case SpineWriteResult.pixelsFailed:
        return "Only part of this reached your lights — the background "
            "arrived but the painted pixels didn't. Try again.";
    }
  }
}

/// Base solid + per-channel `i` spans. True ONLY when the controller accepted
/// every write. See [applyBaseAndSpansDetailed] for the reason on failure.
Future<bool> applyBaseAndSpans(
  WidgetRef ref, {
  required List<int> baseRgbw,
  required Map<int, List<PixelSpan>> spansByChannel,
  String? label,
}) async {
  final result = await applyBaseAndSpansDetailed(
    ref,
    baseRgbw: baseRgbw,
    spansByChannel: spansByChannel,
    label: label,
  );
  return result.isOk;
}

/// `ref.read`, from either a `WidgetRef` (screens) or a `Ref` (providers).
/// The spine only ever READS providers, so taking the reader rather than the
/// ref lets provider-side appliers (scenes) share the one implementation
/// instead of growing a second, drifting copy.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Base solid + per-channel `i` spans, with the wire outcome. Applies spans
/// only for channels in the effective set. Sets [label] ONLY on full success —
/// a "Now Playing" label for a look that never arrived is the same lie as the
/// toast.
Future<SpineWriteResult> applyBaseAndSpansDetailed(
  WidgetRef ref, {
  required List<int> baseRgbw,
  required Map<int, List<PixelSpan>> spansByChannel,
  String? label,
}) =>
    applyBaseAndSpansWith(ref.read,
        baseRgbw: baseRgbw, spansByChannel: spansByChannel, label: label);

/// The spine itself. See [applyBaseAndSpansDetailed].
Future<SpineWriteResult> applyBaseAndSpansWith(
  ProviderReader read, {
  required List<int> baseRgbw,
  required Map<int, List<PixelSpan>> spansByChannel,
  String? label,
}) async {
  final repo = read(wledRepositoryProvider);
  if (repo == null) return SpineWriteResult.noDevice;

  final deviceChannels = read(deviceChannelsProvider);
  final effective = read(effectiveChannelIdsProvider);
  if (effective.isEmpty) return SpineWriteResult.noChannels;
  final effectiveSet = effective.toSet();

  var basePayload = <String, dynamic>{
    'on': true,
    'seg': [
      {
        'fx': 0,
        'sx': 128,
        'ix': 128,
        'pal': 0,
        'col': [baseRgbw],
      }
    ],
  };
  basePayload = applyChannelFilter(basePayload, effective, deviceChannels);
  final baseOk = await repo.applyJson(basePayload);
  if (!baseOk) return SpineWriteResult.baseFailed;

  final toPaint = [
    for (final entry in spansByChannel.entries)
      if (entry.value.isNotEmpty && effectiveSet.contains(entry.key)) entry,
  ];
  if (toPaint.isNotEmpty) {
    // A repository that cannot paint per-pixel used to be skipped silently —
    // base applied, pixels dropped, success reported.
    if (repo is! PerPixelWriter) return SpineWriteResult.pixelsFailed;
    final writer = repo as PerPixelWriter;
    for (final entry in toPaint) {
      final ok =
          await writer.applyPerPixel(segmentId: entry.key, spans: entry.value);
      // Stop at the first refusal: later channels would only add to a frame
      // that is already wrong, and the caller is about to say so.
      if (!ok) return SpineWriteResult.pixelsFailed;
    }
  }

  if (label != null) {
    read(activePresetLabelProvider.notifier)
        .setLabelWithFingerprint(label, read(wledStateProvider));
  }
  return SpineWriteResult.ok;
}

/// Channel-local [LedColorGroup]s → [PixelSpan]s (RGBW-normalized). RGB-only
/// groups get W=0 via [rgbToRgbw] (forceZeroWhite) — closing the "RGB-only,
/// W dropped" #86 fidelity gap.
List<PixelSpan> ledColorGroupsToSpans(List<LedColorGroup> groups) {
  return [
    for (final g in groups)
      PixelSpan(start: g.startLed, end: g.endLed, color: _rgbw(g.color)),
  ];
}

/// Applies a stored POSITIONAL design (painted, or AI-composed) exactly the
/// way the editor's own "Apply to Lights" does — the ONE routine behind My
/// Designs, scenes, and anything else holding a [CustomDesign]. Provider-side
/// callers pass `ref.read`.
Future<DesignApplyResult> applyPositionalDesignWith(
  ProviderReader read,
  CustomDesign design,
) async {
  final spans = customDesignToSpans(design);
  if (spans.isEmpty) return DesignApplyResult.noMap;
  final result = await applyBaseAndSpansWith(
    read,
    baseRgbw: const [0, 0, 0, 0], // groups define the lit picture
    spansByChannel: spans,
    label: design.name,
  );
  return result.isOk ? DesignApplyResult.applied : DesignApplyResult.error;
}

List<int> _rgbw(List<int> c) {
  if (c.length >= 4) {
    return [c[0], c[1], c[2], c[3]];
  }
  if (c.length == 3) {
    return rgbToRgbw(c[0], c[1], c[2], forceZeroWhite: true);
  }
  return const [0, 0, 0, 0];
}

/// A [CustomDesign]'s per-channel color groups → per-channel spans, keyed by
/// each [ChannelDesign.channelId] (the WLED segment id). Groups are already
/// channel-local (reconciled at save time), so they map straight to
/// per-segment `i` writes — this is the per-pixel path that fixes #86's
/// "single whole-roofline seg vs multi-bus split" concern.
Map<int, List<PixelSpan>> customDesignToSpans(CustomDesign design) {
  final out = <int, List<PixelSpan>>{};
  for (final ch in design.channels) {
    if (!ch.included) continue;
    final spans = ledColorGroupsToSpans(ch.colorGroups);
    if (spans.isNotEmpty) out[ch.channelId] = spans;
  }
  return out;
}

/// Applies a full [CustomDesign] via the shared per-pixel spine. Used by BOTH
/// the manual editor's "Apply to Lights" and the AI studio's #86 button.
///
/// Renders the design's color layout as a STATIC per-pixel frame (base black +
/// per-channel `i` spans). This is faithful for every manual design and for AI
/// STATIC designs; an AI design carrying a motion effect renders as its static
/// color layout via this path (animated features are the post-build consumer
/// iv — out of Slice-4 scope). Colors are RGBW-normalized; per-segment
/// targeting is multi-bus-correct — the three #86 fidelity concerns resolved.
Future<DesignApplyResult> applyCustomDesignToLights(
  WidgetRef ref,
  CustomDesign design,
) =>
    applyPositionalDesignWith(ref.read, design);
