import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/wled/design_spacing_defaults.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/shared/apply_blocked_reason.dart';

/// Design Studio Slice 4 — the SHARED per-pixel apply spine used by the smart
/// presets (Slice 3), the manual editor, and the AI studio's "Apply to Lights"
/// (#86). One implementation, three call sites.
///
/// Transport (audit-recommended, structural since Slice 0): a solid BASE on
/// every targeted channel (one explicit `seg` per channel, `applyJson`), then
/// per-channel ACCENT/paint spans via applyPerPixel (segmentId ==
/// channelIndex; bypasses channel fan-out). Static `fx:0` frames; NO WLED
/// preset writes — Firestore stays the design source of truth.
///
/// +110 package E2, audit row 40 — WHICH channels a design goes to. A design
/// used to be sent through `applyChannelFilter` over the Home channel bar's
/// selection: only the ticked channels received it, every other channel was
/// switched OFF with an exclusion marker, and its painted pixels were dropped
/// — from screens that show no channel selection at all. A design now goes
/// to every channel it CARRIES CONTENT FOR ([designTargetChannels]), and the
/// base write names only those channels, so a channel the design says
/// nothing about keeps its power exactly as it is (E1's rule: an apply never
/// changes a channel's power).

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

/// The outcome of applying a whole design, with the sentence to show when it
/// did not land (audit row 42: every failure used to collapse to "Couldn't
/// reach your lights", including the one where the background landed and the
/// house is now dark).
class DesignApplyReport {
  const DesignApplyReport(this.result, {this.message, this.wire});

  final DesignApplyResult result;

  /// Customer-readable. Null when [ok].
  final String? message;

  /// The spine's own outcome, when the spine ran.
  final SpineWriteResult? wire;

  bool get ok =>
      result == DesignApplyResult.applied ||
      result == DesignApplyResult.staleApplied;
}

/// Base solid + per-channel `i` spans. True ONLY when the controller accepted
/// every write. See [applyBaseAndSpansDetailed] for the reason on failure.
Future<bool> applyBaseAndSpans(
  WidgetRef ref, {
  required List<int> baseRgbw,
  required Map<int, List<PixelSpan>> spansByChannel,
  String? label,
  int? brightness,
  List<int>? targetChannels,
}) async {
  final result = await applyBaseAndSpansDetailed(
    ref,
    baseRgbw: baseRgbw,
    spansByChannel: spansByChannel,
    label: label,
    brightness: brightness,
    targetChannels: targetChannels,
  );
  return result.isOk;
}

/// `ref.read`, from either a `WidgetRef` (screens) or a `Ref` (providers).
/// The spine only ever READS providers, so taking the reader rather than the
/// ref lets provider-side appliers (scenes) share the one implementation
/// instead of growing a second, drifting copy.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Base solid + per-channel `i` spans, with the wire outcome. Sets [label]
/// ONLY on full success — a "Now Playing" label for a look that never arrived
/// is the same lie as the toast.
Future<SpineWriteResult> applyBaseAndSpansDetailed(
  WidgetRef ref, {
  required List<int> baseRgbw,
  required Map<int, List<PixelSpan>> spansByChannel,
  String? label,
  int? brightness,
  List<int>? targetChannels,
}) =>
    applyBaseAndSpansWith(ref.read,
        baseRgbw: baseRgbw,
        spansByChannel: spansByChannel,
        label: label,
        brightness: brightness,
        targetChannels: targetChannels);

/// The channels a DESIGN apply goes to (audit row 40): every channel the
/// design carries content for, kept to the channels the controller has (when
/// the census is known) and to the channels the customer has not set aside
/// ("leave out of shows"). NEVER the Home channel bar's selection — none of
/// the design screens shows it, and the painted design says which channels
/// it is for.
List<int> designTargetChannels(
  ProviderReader read,
  Iterable<int> designChannels,
) {
  var ids = designChannels.toSet();
  final census = read(applyChannelCensusProvider).ids;
  if (census.isNotEmpty) ids = ids.intersection(census.toSet());
  final participating = read(participatingChannelIdsProvider);
  if (participating != null) ids = ids.intersection(participating.toSet());
  return ids.toList()..sort();
}

/// The spine itself. See [applyBaseAndSpansDetailed].
///
/// [targetChannels] — the channels this design goes to. Pass
/// [designTargetChannels] for a design apply. Null keeps the legacy gate
/// (the effective channel list) for callers that have no design of their
/// own, such as a smart preset.
///
/// [brightness] — master `bri`, stated ONLY when the caller has a level that
/// was actually set: a stored design's [CustomDesign.appliedBrightness], or an
/// editor's own slider. Null (a look with no brightness of its own yet — a new
/// painting, a smart preset) leaves the controller's brightness exactly as it
/// is. It rides in the base write, so it lands with the base rather than as a
/// visible step afterwards.
Future<SpineWriteResult> applyBaseAndSpansWith(
  ProviderReader read, {
  required List<int> baseRgbw,
  required Map<int, List<PixelSpan>> spansByChannel,
  String? label,
  int? brightness,
  List<int>? targetChannels,
}) async {
  final repo = read(wledRepositoryProvider);
  if (repo == null) return SpineWriteResult.noDevice;

  final List<int> targets =
      targetChannels ?? read<List<int>>(effectiveChannelIdsProvider);
  if (targets.isEmpty) return SpineWriteResult.noChannels;
  final targetSet = targets.toSet();

  // One explicit `seg` per targeted channel and NOTHING about the others:
  // a channel this design does not paint keeps its power (row 40).
  final basePayload = <String, dynamic>{
    'on': true,
    if (brightness != null) 'bri': brightness.clamp(1, 255),
    'seg': [
      for (final id in targets.toList()..sort())
        <String, dynamic>{
          'id': id,
          'on': true,
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'pal': 0,
          'col': [baseRgbw],
          ...kDesignSpacingDefaults,
        },
    ],
  };
  final baseOk = await repo.applyJson(basePayload);
  if (!baseOk) return SpineWriteResult.baseFailed;

  final toPaint = [
    for (final entry in spansByChannel.entries)
      if (entry.value.isNotEmpty && targetSet.contains(entry.key)) entry,
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

// ── Motion (audit row 41) ──────────────────────────────────────────────────

/// The effect an AI-composed design asked for, or null when the design is a
/// still picture.
///
/// Read from the stored `composed_pattern` layer — the composer's own
/// `effect_id` / `has_motion` — which every writer preserves. A painted
/// design has no such layer and is always static.
class DesignMotion {
  const DesignMotion({
    required this.effectId,
    required this.speed,
    required this.intensity,
  });

  final int effectId;
  final int speed;
  final int intensity;
}

DesignMotion? motionEffectOf(CustomDesign design) {
  final cp = design.composedPattern;
  if (cp == null) return null;
  if (cp['has_motion'] != true) return null;
  final fx = (cp['effect_id'] as num?)?.toInt() ?? 0;
  if (fx <= 0) return null;
  return DesignMotion(
    effectId: fx,
    speed: ((cp['speed'] as num?)?.toInt() ?? 128).clamp(0, 255),
    intensity: ((cp['intensity'] as num?)?.toInt() ?? 128).clamp(0, 255),
  );
}

/// Up to three distinct colours the design paints, in RGBW, in the order the
/// composer laid them down — the colours the effect runs with.
List<List<int>> _effectColorsOf(CustomDesign design) {
  final out = <List<int>>[];
  for (final ch in design.channels) {
    if (!ch.included) continue;
    for (final g in ch.colorGroups) {
      final c = _rgbw(g.color);
      if (c[0] == 0 && c[1] == 0 && c[2] == 0 && c[3] == 0) continue;
      if (out.any((o) =>
          o[0] == c[0] && o[1] == c[1] && o[2] == c[2] && o[3] == c[3])) {
        continue;
      }
      out.add(c);
      if (out.length == 3) return out;
    }
  }
  return out;
}

/// The `/json/state` body that runs [motion] in the design's colours on
/// [targets]: one explicit `seg` per channel, nothing about the others.
Map<String, dynamic> buildDesignMotionPayload(
  CustomDesign design,
  DesignMotion motion,
  List<int> targets,
) {
  final colors = _effectColorsOf(design);
  final col = colors.isEmpty ? const <List<int>>[[255, 255, 255, 0]] : colors;
  final bri = design.appliedBrightness;
  return <String, dynamic>{
    'on': true,
    if (bri != null) 'bri': bri,
    'seg': [
      for (final id in targets.toList()..sort())
        <String, dynamic>{
          'id': id,
          'on': true,
          'fx': motion.effectId,
          'sx': motion.speed,
          'ix': motion.intensity,
          'pal': kDesignColorsOnlyPalette,
          'col': col,
          ...kDesignSpacingDefaults,
        },
    ],
  };
}

// ── Whole-design apply ─────────────────────────────────────────────────────

/// Which channels a whole-design apply goes to.
enum DesignApplyTargets {
  /// Every channel the design carries content for (row 40). The Design
  /// Studio, the manual editor and My Designs.
  design,

  /// The effective channel list (the Home channel bar's selection, less the
  /// channels set aside). Home favourites keep this, so a per-pixel favourite
  /// scopes the same way as an effect favourite on the same grid.
  effective,
}

/// Applies a stored design the way the editor's own "Apply to Lights" does —
/// the ONE routine behind My Designs, scenes, the AI studio and anything else
/// holding a [CustomDesign] — and says what happened. Provider-side callers
/// pass `ref.read`.
///
///  * A design with motion (an AI-composed design whose prompt asked for a
///    chase, a wave, a twinkle…) runs its EFFECT in its colours (row 41). It
///    used to be flattened to a still frame under an "Applied" toast.
///  * Any other positional design is painted per pixel through the spine.
///  * Both go to [targets]: by default the channels the design carries
///    content for (row 40).
Future<DesignApplyReport> applyPositionalDesignDetailed(
  ProviderReader read,
  CustomDesign design, {
  DesignApplyTargets targets = DesignApplyTargets.design,
}) async {
  final spans = customDesignToSpans(design);
  if (spans.isEmpty) {
    return const DesignApplyReport(
      DesignApplyResult.noMap,
      message: 'This design has no lit pixels to apply.',
    );
  }

  final targetIds = targets == DesignApplyTargets.design
      ? designTargetChannels(read, spans.keys)
      : (read<List<int>>(effectiveChannelIdsProvider).toList()..sort());
  final repo = read(wledRepositoryProvider);
  if (repo == null) {
    return DesignApplyReport(
      DesignApplyResult.error,
      message: applyBlockedReason(read) ?? SpineWriteResult.noDevice.userMessage,
      wire: SpineWriteResult.noDevice,
    );
  }
  if (targetIds.isEmpty) {
    return DesignApplyReport(
      DesignApplyResult.error,
      message: applyBlockedReason(read) ??
          "None of this design's channels are on your controller right now, "
              'so nothing was sent.',
      wire: SpineWriteResult.noChannels,
    );
  }

  final motion = motionEffectOf(design);
  if (motion != null) {
    final ok = await repo
        .applyJson(buildDesignMotionPayload(design, motion, targetIds));
    if (!ok) {
      return const DesignApplyReport(
        DesignApplyResult.error,
        message: "Couldn't reach your lights — nothing was changed.",
        wire: SpineWriteResult.baseFailed,
      );
    }
    read(activePresetLabelProvider.notifier)
        .setLabelWithFingerprint(design.name, read(wledStateProvider));
    return const DesignApplyReport(DesignApplyResult.applied);
  }

  final wire = await applyBaseAndSpansWith(
    read,
    baseRgbw: const [0, 0, 0, 0], // groups define the lit picture
    spansByChannel: spans,
    label: design.name,
    // The ONE brightness rule — the same getter the payload shapes read.
    brightness: design.appliedBrightness,
    targetChannels: targetIds,
  );
  if (wire.isOk) return const DesignApplyReport(DesignApplyResult.applied);
  return DesignApplyReport(
    DesignApplyResult.error,
    message: wire == SpineWriteResult.noDevice ||
            wire == SpineWriteResult.noChannels
        ? (applyBlockedReason(read) ?? wire.userMessage)
        : wire.userMessage,
    wire: wire,
  );
}

/// [applyPositionalDesignDetailed] reduced to its result, for callers that
/// only branch on success.
Future<DesignApplyResult> applyPositionalDesignWith(
  ProviderReader read,
  CustomDesign design, {
  DesignApplyTargets targets = DesignApplyTargets.design,
}) async =>
    (await applyPositionalDesignDetailed(read, design, targets: targets)).result;

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

/// Applies a full [CustomDesign] via the shared spine and reports what
/// happened. Used by BOTH the manual editor's "Apply to Lights" and the AI
/// studio's #86 button.
Future<DesignApplyReport> applyCustomDesignDetailed(
  WidgetRef ref,
  CustomDesign design,
) =>
    applyPositionalDesignDetailed(ref.read, design);

/// [applyCustomDesignDetailed] reduced to its result.
Future<DesignApplyResult> applyCustomDesignToLights(
  WidgetRef ref,
  CustomDesign design,
) =>
    applyPositionalDesignWith(ref.read, design);
