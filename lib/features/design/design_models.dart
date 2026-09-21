import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/design_spacing_defaults.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/models/segment_aware_pattern.dart';

/// Tag on every design the Pattern Editor ("Edit Pattern" screen) saves.
/// Provenance — and the one thing that reads it is the legacy arm of
/// [CustomDesign.statesBrightness].
const String kPatternEditorDesignTag = 'pattern-editor';

/// The master brightness the lights are showing right now, as a value a design
/// may store — or null when the app is not actually hearing from a controller,
/// in which case [brightness] is a stale or default number and must not be
/// recorded as something the user saw.
///
/// The writers with no brightness control of their own (the paint editor, the
/// AI Design Studio) save a look the user built while watching the lights at
/// THIS level, so this is the brightness that look was made under.
int? liveBrightnessToStore({required bool connected, required int brightness}) =>
    connected ? brightness.clamp(1, 255) : null;

/// Represents a complete custom design that can be saved and applied to WLED devices.
class CustomDesign {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String ownerId;

  /// Per-channel configurations
  final List<ChannelDesign> channels;

  /// Global brightness (0-255)
  final int brightness;

  /// Whether [brightness] is a level somebody actually set — so applying this
  /// design must restore it — or just the model default.
  ///
  /// * `true`  — every writer states this from 2026-09-21 on. Stored as
  ///   `brightness_stated`.
  /// * `false` — the writer had no trustworthy level to record (saved with no
  ///   controller connected), or the document carries no `brightness` at all.
  ///   Applying leaves the controller's brightness alone.
  /// * `null`  — NOT RECORDED: every document saved before the field existed.
  ///   Nothing is backfilled; [statesBrightness] decides from what those
  ///   documents are known to hold.
  ///
  /// Read [statesBrightness] / [appliedBrightness], never this directly.
  final bool? brightnessStated;

  /// Searchable tags for organization
  final List<String> tags;

  /// Reference to roofline configuration used (for segment mode)
  final String? rooflineConfigId;

  /// Whether this design was generated from segment-aware pattern
  final bool isSegmentAware;

  /// Pattern template type used (for segment mode)
  final PatternTemplateType? templateType;

  /// LED color groups for segment-aware patterns
  final List<LedColorGroup>? segmentColorGroups;

  /// Segment pattern configuration (anchor color, spacing, etc.)
  final Map<String, dynamic>? segmentPatternConfig;

  /// AI source-of-truth from the Design Studio (#86 option-b).
  ///
  /// When this design was created by the AI Design Studio, this holds the
  /// full `ComposedPattern.toJson()` — including the layered `sourceIntent`
  /// (zones/colors/motion/ambiguity-resolutions) and the composed
  /// `wled_payload`. `channels` (above) is a *derived denormalization* of
  /// this, so legacy read paths (My Designs previews, `toWledPayload`) keep
  /// working unchanged; this field is the additive AI layer that lets a
  /// Studio design be re-opened and re-edited as an AI design later.
  ///
  /// `null` for every non-Studio design (manual editor, Now-Playing save,
  /// brand seeds) — those behave exactly as before this field existed.
  ///
  /// Persisted jsonEncoded (see `toFirestore`/`fromFirestoreData`) because it
  /// embeds arrays-of-arrays (`col:[[r,g,b,w]]`) that the native iOS Firestore
  /// codec aborts on (#84). In-memory it is a decoded `Map`.
  ///
  /// ## WRITE-ONLY TODAY — and every writer MUST preserve it
  ///
  /// Audited 2026-08-24 (audit/DESIGN_CARD_P4.md §4): this field has **no
  /// reader anywhere in the app**. `grep composedPattern` outside this file
  /// finds writers, provenance null-checks, doc comments and tests — nothing
  /// that decodes the contents. In particular `composedPatternProvider`
  /// (design_studio_providers.dart:162) is a DIFFERENT thing: an in-memory
  /// `StateProvider<ComposedPattern?>` for the live studio session, never
  /// hydrated from a stored design.
  ///
  /// It is persisted for a FUTURE AI re-edit consumer — the layered
  /// `sourceIntent` is what would let a saved Studio design be reopened and
  /// re-composed rather than re-prompted from scratch. Until that consumer
  /// exists the field is dead weight that must not be dropped, because
  /// re-deriving it is impossible: the intent cannot be recovered from the
  /// rendered channels.
  ///
  /// **Every writer must preserve it.** In practice: edit via `copyWith` on the
  /// LOADED model (which carries the field forward) and write through
  /// `DesignService.updateDesign`, whose `.update()` merges by key so an
  /// omitted `composed_pattern` is left alone rather than deleted. The rename
  /// path, the manual editor's edit-save, and the colourway tuner's
  /// save-to-design all do this, and all are covered by tests asserting the
  /// field survives. A writer that constructs a FRESH `CustomDesign` instead of
  /// copying the loaded one WILL silently destroy it.
  final Map<String, dynamic>? composedPattern;

  /// True when this design was PAINTED: its channels' colour groups are
  /// positional runs — "LEDs 40–44 are blue" — not a list of palette colours.
  ///
  /// Stored (`per_pixel`), because the two meanings share one field and cannot
  /// be told apart reliably by shape: a painted design that is all one colour
  /// (or blank) has a single group per channel and looks exactly like a
  /// captured solid, while the colour editor's "save as pattern" writes three
  /// single-LED groups (`0–0, 1–1, 2–2`) that look positional and are not.
  /// Guessing got it wrong in both directions — and the guess decided which
  /// editor opened AND, worse, how the design was sent to the lights.
  ///
  /// Written by the manual paint editor. Absent on older docs → see
  /// [isPositional] for the fallback.
  final bool perPixel;

  const CustomDesign({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.ownerId,
    required this.channels,
    this.brightness = 200,
    this.brightnessStated,
    this.tags = const [],
    this.rooflineConfigId,
    this.isSegmentAware = false,
    this.templateType,
    this.segmentColorGroups,
    this.segmentPatternConfig,
    this.composedPattern,
    this.perPixel = false,
  });

  CustomDesign copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? ownerId,
    List<ChannelDesign>? channels,
    int? brightness,
    bool? brightnessStated,
    List<String>? tags,
    String? rooflineConfigId,
    bool? isSegmentAware,
    PatternTemplateType? templateType,
    List<LedColorGroup>? segmentColorGroups,
    Map<String, dynamic>? segmentPatternConfig,
    Map<String, dynamic>? composedPattern,
    bool? perPixel,
  }) {
    return CustomDesign(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ownerId: ownerId ?? this.ownerId,
      channels: channels ?? this.channels,
      brightness: brightness ?? this.brightness,
      brightnessStated: brightnessStated ?? this.brightnessStated,
      tags: tags ?? this.tags,
      rooflineConfigId: rooflineConfigId ?? this.rooflineConfigId,
      isSegmentAware: isSegmentAware ?? this.isSegmentAware,
      templateType: templateType ?? this.templateType,
      segmentColorGroups: segmentColorGroups ?? this.segmentColorGroups,
      segmentPatternConfig: segmentPatternConfig ?? this.segmentPatternConfig,
      composedPattern: composedPattern ?? this.composedPattern,
      perPixel: perPixel ?? this.perPixel,
    );
  }

  /// Creates a new empty design for the editor
  factory CustomDesign.empty(String ownerId) {
    final now = DateTime.now();
    return CustomDesign(
      id: '',
      name: 'Untitled Design',
      createdAt: now,
      updatedAt: now,
      ownerId: ownerId,
      channels: [],
      brightness: 200,
    );
  }

  /// Creates from Firestore document
  factory CustomDesign.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return CustomDesign.fromFirestoreData(doc.id, data);
  }

  /// Creates from raw Firestore data with explicit ID
  factory CustomDesign.fromFirestoreData(String id, Map<String, dynamic> data) {
    // Parse template type if present
    PatternTemplateType? parsedTemplateType;
    final templateTypeStr = data['template_type'] as String?;
    if (templateTypeStr != null) {
      parsedTemplateType = PatternTemplateType.values.firstWhere(
        (t) => t.name == templateTypeStr,
        orElse: () => PatternTemplateType.downlighting,
      );
    }

    // #86 option-b: composed_pattern is stored jsonEncoded (a String) so its
    // nested arrays-of-arrays never reach Firestore's native codec (#84).
    // Decode back to a Map here. Legacy designs lack the field → null →
    // behave exactly as before. Defensive: tolerate a raw Map too (in case a
    // pre-encode write ever landed) and a corrupt/undecodable String → null.
    Map<String, dynamic>? parsedComposedPattern;
    final rawComposed = data['composed_pattern'];
    if (rawComposed is String && rawComposed.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawComposed);
        if (decoded is Map<String, dynamic>) {
          parsedComposedPattern = decoded;
        }
      } catch (_) {
        parsedComposedPattern = null;
      }
    } else if (rawComposed is Map) {
      parsedComposedPattern = Map<String, dynamic>.from(rawComposed);
    }

    // The ABSENT case. A document with no usable `brightness` has nothing to
    // restore: say so, rather than let the 200 below pass for a level anybody
    // chose. A document that has one but predates `brightness_stated` stays
    // null (not recorded) — see [statesBrightness]. Nothing is written back.
    final rawBrightness = data['brightness'];
    final bool? parsedBrightnessStated = rawBrightness is num
        ? data['brightness_stated'] as bool?
        : false;

    return CustomDesign(
      id: id,
      name: data['name'] as String? ?? 'Untitled',
      description: data['description'] as String?,
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ownerId: data['owner_id'] as String? ?? '',
      channels: (data['channels'] as List<dynamic>?)
              ?.map((c) => ChannelDesign.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      // `num`, not `int`: a level that came back as a double used to throw
      // here and take the whole document with it.
      brightness: rawBrightness is num ? rawBrightness.toInt() : 200,
      brightnessStated: parsedBrightnessStated,
      tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      rooflineConfigId: data['roofline_config_id'] as String?,
      isSegmentAware: data['is_segment_aware'] as bool? ?? false,
      templateType: parsedTemplateType,
      segmentColorGroups: (data['segment_color_groups'] as List<dynamic>?)
              ?.map((g) => LedColorGroup.fromJson(g as Map<String, dynamic>))
              .toList(),
      segmentPatternConfig: data['segment_pattern_config'] as Map<String, dynamic>?,
      composedPattern: parsedComposedPattern,
      perPixel: data['per_pixel'] as bool? ?? false,
    );
  }

  /// Converts to Firestore document data
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'owner_id': ownerId,
      'channels': channels.map((c) => c.toJson()).toList(),
      'brightness': brightness,
      // Omitted while null so re-saving an older design through a writer that
      // does not own brightness (rename, the tuner) records nothing it does
      // not know — `.update()` merges by key and leaves the doc as it was.
      if (brightnessStated != null) 'brightness_stated': brightnessStated,
      'tags': tags,
      if (rooflineConfigId != null) 'roofline_config_id': rooflineConfigId,
      'is_segment_aware': isSegmentAware,
      if (templateType != null) 'template_type': templateType!.name,
      if (segmentColorGroups != null)
        'segment_color_groups': segmentColorGroups!.map((g) => g.toJson()).toList(),
      if (segmentPatternConfig != null) 'segment_pattern_config': segmentPatternConfig,
      // #86 + #84: jsonEncode the composed pattern to a String. Its embedded
      // wled_payload holds arrays-of-arrays (col:[[r,g,b,w]]) which the native
      // iOS Firestore codec aborts on (SIGABRT). Encoding to a String renders
      // it an opaque primitive to UserService.sanitizeForFirestore (which
      // otherwise THROWS on nested lists) — mirrors logPatternUsage's
      // 'wled': jsonEncode(wled). Decoded back in fromFirestoreData.
      if (composedPattern != null) 'composed_pattern': jsonEncode(composedPattern),
      // Only ever written as `true`: absence keeps meaning "not stated", so
      // older docs and the legacy fallback in [isPositional] stay valid.
      if (perPixel) 'per_pixel': true,
    };
  }

  /// True when [brightness] is a level somebody set, so applying this design
  /// must restore it — from EVERY door, whatever the lights are at now and
  /// whichever screen saved it (decision of record 2026-09-21).
  ///
  /// This is the ONE rule. It used to be three: the per-pixel spine restored
  /// brightness only for Pattern Editor designs; the effect payload always
  /// stated it; and scene apply stamped it afterwards with a second write
  /// regardless — so the same design came back at a different level depending
  /// on which button applied it.
  ///
  /// [brightnessStated] answers it for anything saved from 2026-09-21 on. For
  /// the older documents that never recorded it (`null`), this goes by what
  /// each shape is known to hold — nothing is backfilled:
  ///
  /// * an EFFECT design — a real level. Its writers all captured one (Now
  ///   Playing and the colour editor store the live brightness, the Pattern
  ///   Editor its slider), and it has always been applied. Unchanged.
  /// * a Pattern Editor design ([kPatternEditorDesignTag]) — its slider.
  ///   Unchanged from the fix that introduced this getter.
  /// * any other POSITIONAL design — the model's default 200, which nobody
  ///   chose: the paint editor and the AI studio had no brightness to record.
  ///   Left alone rather than stamped over the controller's level.
  bool get statesBrightness =>
      brightnessStated ??
      (tags.contains(kPatternEditorDesignTag) || !isPositional);

  /// The master `bri` to send when applying this design, or null to leave the
  /// controller's brightness exactly as it is. Every apply path reads THIS.
  ///
  /// Floored at 1: a design always states `on: true`, and WLED treats `bri: 0`
  /// as off — the effect payload used to send a stored 0 as-is while the spine
  /// sent 1.
  int? get appliedBrightness =>
      statesBrightness ? brightness.clamp(1, 255) : null;

  /// Whether the channels hold an LED PICTURE (positional runs) that has to be
  /// sent per-pixel, rather than "up to three colours + an effect".
  ///
  /// * [perPixel] — stated by the paint editor.
  /// * [composedPattern] — AI Design Studio designs; their channel groups are
  ///   the composed layout clipped per channel, and the studio's own Apply has
  ///   always sent them per-pixel.
  /// * Legacy docs with neither: positional only when some channel's groups
  ///   genuinely TILE that channel (start at 0, contiguous, end at
  ///   `ledCount - 1`, more than one run). That is what the paint editor has
  ///   always written, and what no palette-style writer produces.
  bool get isPositional {
    if (perPixel || composedPattern != null) return true;
    return channels.any((c) => c.included && c.tilesItsChannel);
  }

  /// A self-contained per-pixel payload: every included channel as `fx:0` with
  /// an `i` array covering EVERY LED (uncovered LEDs are written black).
  ///
  /// Full coverage is what makes a single payload safe. A per-pixel write
  /// freezes the segment in the same request, so a base colour sent alongside
  /// it never renders — any LED the `i` array skipped would keep whatever the
  /// previous look left in the buffer.
  Map<String, dynamic> _positionalPayload() {
    final segments = <Map<String, dynamic>>[];
    for (final channel in channels) {
      if (!channel.included) continue;
      final spans = channel.fullCoverageSpans();
      if (spans.isEmpty) continue;
      final seg = (buildPerPixelPayload(spans, channel.channelId)['seg'] as List)
          .first as Map<String, dynamic>;
      segments.add({
        ...kDesignSpacingDefaults,
        ...seg, // id, on, fx:0, i
        'pal': 0,
        'col': const [
          [0, 0, 0, 0]
        ],
      });
    }
    final bri = appliedBrightness;
    return {'on': true, if (bri != null) 'bri': bri, 'seg': segments};
  }

  /// Converts this design to a WLED JSON API payload.
  ///
  /// A POSITIONAL design ([isPositional]) is emitted per-pixel. It used to be
  /// pushed through the effect shape below like everything else — first three
  /// colour groups, every position discarded, `fx:83` — which for a painted
  /// design (whose first group is nearly always the unlit base) turned the
  /// house almost entirely dark under an "Applied" toast (audit F3, twice
  /// bench-confirmed). Every payload consumer inherits this: My Designs,
  /// scenes (every saved design IS a custom scene), the Lumina command router.
  ///
  /// NOTE a payload is bounded by `kMaxApplyPayloadBytes`; callers that can,
  /// apply a positional design through the chunked spine instead
  /// (`applyCustomDesignToLights`), which has no such ceiling.
  Map<String, dynamic> toWledPayload() {
    if (isPositional) return _positionalPayload();

    final segments = <Map<String, dynamic>>[];

    for (final channel in channels) {
      if (!channel.included) continue;

      // WLED supports up to 3 colors in col array
      final colors = channel.colorGroups
          .take(3)
          .map((g) => g.color)
          .toList();

      // If no colors defined, use white
      if (colors.isEmpty) {
        colors.add([255, 255, 255, 0]);
      }

      // When effect 0 (Solid) is used with multiple colors, substitute effect 83
      // (Solid Pattern) which distributes colors in repeating blocks. Solid only
      // shows the first color, losing the rest of the palette.
      final fx = (channel.effectId == 0 && channel.colorGroups.length > 1)
          ? 83
          : channel.effectId;

      segments.add({
        // #88 — grp/spc are always ASSERTED, never omitted: a saved design must
        // not inherit the spacing of whatever ran before it. They now come
        // from the channel (defaults 1 / 0 for every older design) instead of
        // being pinned to the defaults, which erased a saved "1 On 4 Off".
        'grp': channel.grouping,
        'spc': channel.spacing,
        'id': channel.channelId,
        'col': colors,
        // STATED, for the same reason grp/spc are — see
        // [kDesignColorsOnlyPalette]. The chokepoint still swaps 5→4 for the
        // few effects that ignore user colours under "Colors Only".
        'pal': kDesignColorsOnlyPalette,
        'fx': fx,
        'sx': channel.speed,
        'ix': channel.intensity,
        // #4 (firmware-free half): emit 'rev' ONLY when the design explicitly
        // reverses this channel. reverse defaults false, so always writing it
        // forced rev:false on every apply — clobbering the device's manual
        // per-segment direction. Omitting the key when false lets the apply
        // PRESERVE the controller's current seg.rev instead of overriding it.
        // #76 — `rev` no longer written at all. Omitting-when-false was a
        // partial fix; the rule is that a design payload never asserts
        // geometry, in either direction. LOSES: channel.reverse reaches the
        // device only through provisioning now, not through a design apply.
      });
    }

    // Same rule as the positional shape and the spine — [appliedBrightness].
    // This payload is also what a schedule stores and what a scene sends.
    final bri = appliedBrightness;
    return {
      'on': true,
      if (bri != null) 'bri': bri,
      'seg': segments,
    };
  }

  /// Get preview colors for UI display (up to 4 colors)
  List<List<int>> get previewColors {
    final colors = <List<int>>[];
    for (final channel in channels.where((ch) => ch.included)) {
      for (final group in channel.colorGroups.take(2)) {
        colors.add(group.color.take(3).toList());
        if (colors.length >= 4) break;
      }
      if (colors.length >= 4) break;
    }
    return colors;
  }

  /// Get primary effect ID from first included channel
  int? get primaryEffectId {
    return channels
        .where((ch) => ch.included)
        .map((ch) => ch.effectId)
        .firstOrNull;
  }
}

/// Configuration for a single channel/segment in the design.
class ChannelDesign {
  /// Maps to WLED segment ID
  final int channelId;

  /// Display name for the channel
  final String channelName;

  /// Whether this channel is active in the design
  final bool included;

  /// LED color assignments (groups of LEDs with same color)
  final List<LedColorGroup> colorGroups;

  /// WLED effect ID (0 = Solid)
  final int effectId;

  /// Animation speed (0-255)
  final int speed;

  /// Effect intensity (0-255)
  final int intensity;

  /// Direction of effect
  final bool reverse;

  /// Total LED count for this channel (for visualization)
  final int ledCount;

  /// WLED `grp` — LEDs per lit band ("N on"). 1 = no grouping.
  ///
  /// `grp`/`spc` are DESIGN fields (#88, decision of record 2026-08-17) — and
  /// until now a design had nowhere to keep them. A saved "1 On 4 Off" came
  /// back from My Designs with every LED lit, and the tuner could neither show
  /// nor change the spacing of a design it was editing
  /// (design-studio-followup-2026-09-19 N3b).
  final int grouping;

  /// WLED `spc` — dark LEDs between bands ("M off"). 0 = no spacing.
  final int spacing;

  const ChannelDesign({
    required this.channelId,
    required this.channelName,
    this.included = true,
    this.colorGroups = const [],
    this.effectId = 0,
    this.speed = 128,
    this.intensity = 128,
    this.reverse = false,
    this.ledCount = 0,
    this.grouping = kDesignDefaultGrp,
    this.spacing = kDesignDefaultSpc,
  });

  ChannelDesign copyWith({
    int? channelId,
    String? channelName,
    bool? included,
    List<LedColorGroup>? colorGroups,
    int? effectId,
    int? speed,
    int? intensity,
    bool? reverse,
    int? ledCount,
    int? grouping,
    int? spacing,
  }) {
    return ChannelDesign(
      channelId: channelId ?? this.channelId,
      channelName: channelName ?? this.channelName,
      included: included ?? this.included,
      colorGroups: colorGroups ?? this.colorGroups,
      effectId: effectId ?? this.effectId,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      reverse: reverse ?? this.reverse,
      ledCount: ledCount ?? this.ledCount,
      grouping: grouping ?? this.grouping,
      spacing: spacing ?? this.spacing,
    );
  }

  factory ChannelDesign.fromJson(Map<String, dynamic> json) {
    return ChannelDesign(
      channelId: json['channel_id'] as int? ?? 0,
      channelName: json['channel_name'] as String? ?? 'Channel',
      included: json['included'] as bool? ?? true,
      colorGroups: (json['color_groups'] as List<dynamic>?)
              ?.map((g) => LedColorGroup.fromJson(g as Map<String, dynamic>))
              .toList() ??
          [],
      effectId: json['effect_id'] as int? ?? 0,
      speed: json['speed'] as int? ?? 128,
      intensity: json['intensity'] as int? ?? 128,
      reverse: json['reverse'] as bool? ?? false,
      ledCount: json['led_count'] as int? ?? 0,
      // Absent on every design saved before these fields existed → the #88
      // design defaults, which is exactly what those designs have always been
      // applied with. Clamped to what WLED accepts.
      grouping: ((json['grouping'] as num?)?.toInt() ?? kDesignDefaultGrp)
          .clamp(1, 255),
      spacing: ((json['spacing'] as num?)?.toInt() ?? kDesignDefaultSpc)
          .clamp(0, 255),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'channel_id': channelId,
      'channel_name': channelName,
      'included': included,
      'color_groups': colorGroups.map((g) => g.toJson()).toList(),
      'effect_id': effectId,
      'speed': speed,
      'intensity': intensity,
      'reverse': reverse,
      'led_count': ledCount,
      'grouping': grouping,
      'spacing': spacing,
    };
  }

  /// True when [colorGroups] tile this channel: more than one run, starting at
  /// 0, contiguous, ending at `ledCount - 1`. See [CustomDesign.isPositional].
  bool get tilesItsChannel {
    if (ledCount <= 0 || colorGroups.length < 2) return false;
    int cursor = 0;
    for (final g in colorGroups) {
      if (g.startLed != cursor || g.endLed < g.startLed) return false;
      cursor = g.endLed + 1;
    }
    return cursor == ledCount;
  }

  /// [colorGroups] as channel-local RGBW [PixelSpan]s, exactly as stored.
  /// RGB-only colours get W=0 (the same rule the apply spine uses).
  List<PixelSpan> positionalSpans() => [
        for (final g in colorGroups)
          if (g.endLed >= g.startLed && g.startLed >= 0)
            PixelSpan(start: g.startLed, end: g.endLed, color: _rgbwOf(g.color)),
      ];

  /// [positionalSpans] with every gap up to the channel's length filled black,
  /// so the result covers the whole channel (see `_positionalPayload`).
  List<PixelSpan> fullCoverageSpans() {
    final spans = positionalSpans()..sort((a, b) => a.start.compareTo(b.start));
    if (spans.isEmpty) return spans;
    final length = ledCount > 0 ? ledCount : spans.last.end + 1;
    final out = <PixelSpan>[];
    int cursor = 0;
    for (final s in spans) {
      if (s.start > cursor) {
        out.add(PixelSpan(start: cursor, end: s.start - 1, color: const [0, 0, 0, 0]));
      }
      out.add(s);
      if (s.end + 1 > cursor) cursor = s.end + 1;
    }
    if (cursor < length) {
      out.add(PixelSpan(start: cursor, end: length - 1, color: const [0, 0, 0, 0]));
    }
    return out;
  }

  static List<int> _rgbwOf(List<int> c) {
    if (c.length >= 4) return [c[0], c[1], c[2], c[3]];
    if (c.length == 3) return [c[0], c[1], c[2], 0];
    return const [0, 0, 0, 0];
  }

  /// Gets the primary color for display (first color group or white)
  Color get primaryColor {
    if (colorGroups.isEmpty) return Colors.white;
    final c = colorGroups.first.color;
    return Color.fromARGB(255, c[0], c[1], c[2]);
  }
}

/// Represents a group of LEDs with the same color.
/// Allows "virtual" per-LED control by defining color ranges.
class LedColorGroup {
  /// 0-indexed start LED position
  final int startLed;

  /// 0-indexed end LED position (inclusive)
  final int endLed;

  /// Color as [R, G, B] or [R, G, B, W]
  final List<int> color;

  const LedColorGroup({
    required this.startLed,
    required this.endLed,
    required this.color,
  });

  /// Number of LEDs in this group
  int get ledCount => endLed - startLed + 1;

  LedColorGroup copyWith({
    int? startLed,
    int? endLed,
    List<int>? color,
  }) {
    return LedColorGroup(
      startLed: startLed ?? this.startLed,
      endLed: endLed ?? this.endLed,
      color: color ?? this.color,
    );
  }

  factory LedColorGroup.fromJson(Map<String, dynamic> json) {
    return LedColorGroup(
      startLed: json['start_led'] as int? ?? 0,
      endLed: json['end_led'] as int? ?? 0,
      color: (json['color'] as List<dynamic>?)?.cast<int>() ?? [255, 255, 255],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start_led': startLed,
      'end_led': endLed,
      'color': color,
    };
  }

  /// Creates from a Flutter Color
  factory LedColorGroup.fromColor(int startLed, int endLed, Color color, {int white = 0}) {
    return LedColorGroup(
      startLed: startLed,
      endLed: endLed,
      color: [color.red, color.green, color.blue, white],
    );
  }

  /// Gets the Flutter Color representation
  Color get flutterColor {
    if (color.length >= 3) {
      return Color.fromARGB(255, color[0], color[1], color[2]);
    }
    return Colors.white;
  }
}

/// Curated Design-Studio effects, defined by their CATALOG NAME and resolved
/// to the device's 0.15.1 fx ID via [WledEffectsCatalog]. Routing by name (not
/// hardcoded numbers) keeps these in lockstep with the firmware and prevents the
/// effect-ID drift that previously shipped wrong fx (e.g. Candle→Chase 2).
///
/// `[catalogName, userFacingLabel]`. The label may differ from the catalog name
/// where the product wording differs (e.g. "Theater" → "Theater Chase",
/// "Fire 2012" → "Fire").
const List<List<String>> _kDesignEffectSpecs = [
  ['Solid', 'Solid'],
  ['Blink', 'Blink'],
  ['Breathe', 'Breathe'],
  ['Rainbow', 'Rainbow'],
  ['Theater', 'Theater Chase'],
  ['Chase', 'Chase'],
  ['Candle', 'Candle'],
  ['Fire 2012', 'Fire'],
  ['Fireworks', 'Fireworks'],
  ['Twinkle', 'Twinkle'],
  ['Colortwinkles', 'Colortwinkles'],
  ['Palette', 'Palette'],
  ['Ripple', 'Ripple'],
  ['Pacifica', 'Pacifica'],
];

/// Common WLED effects with user-friendly names, keyed by the real 0.15.1 fx ID.
final Map<int, String> kDesignEffects = {
  for (final spec in _kDesignEffectSpecs)
    if (WledEffectsCatalog.idForName(spec[0]) != null)
      WledEffectsCatalog.idForName(spec[0])!: spec[1],
};

/// Curated list of effect IDs for the design studio (resolved by name, in order).
/// Intentionally a subset of [kDesignEffects] — omits Blink, Fire, Fireworks,
/// matching the pre-drift curated selection.
final List<int> kCuratedEffectIds = WledEffectsCatalog.idsForNames(const [
  'Solid',
  'Breathe',
  'Rainbow',
  'Theater',
  'Chase',
  'Candle',
  'Twinkle',
  'Colortwinkles',
  'Palette',
  'Ripple',
  'Pacifica',
]);
