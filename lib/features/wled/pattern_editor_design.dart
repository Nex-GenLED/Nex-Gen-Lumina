// lib/features/wled/pattern_editor_design.dart
//
// What the Pattern Editor's SAVE writes to My Designs (+110 E1, item C).
//
// WHICH MODEL IT USED TO WRITE. `customDesignFromEditablePattern`
// (lib/features/design/editable_pattern_design.dart) filed a STATIC pattern
// (MODE = Solid, fx 0 — which is what the editor opens on from an Explore
// palette whose tuner was never moved) as a PER-PIXEL design: `perPixel: true`,
// every LED painted into positional colour runs. That one choice is why an
// edited Explore pattern came back from My Designs "stripped down":
//   • the card read its swatches from the first two positional runs (row 119)
//     and had no effect or speed to show;
//   • tapping it opened the design detail screen, not the tuner it came from;
//   • the detail screen showed "Effect: Solid (fx 0)" for something that
//     always applies as a still picture (row 118);
//   • schedule and Game Day pickers refused it, because a controller timer
//     cannot replay a per-pixel picture (row 92).
// Animated patterns were already effect designs, but lost direction (row 94)
// and filed the background colour in a slot the effect does not read (row 95).
//
// WHAT IT WRITES NOW. The palette/effect design — the same model the palette
// tuner edits — with the full look:
//   colours      the ≤3 WLED colour slots the lights are sent, background
//                included where it applies (see [EditablePattern.backgroundApplies])
//   effect       `effectId`
//   speed        `speed`
//   intensity    `intensity`
//   layout       `grouping` (the editor's colour-group size), `spacing` (the
//                design default — the editor has no spacing control), and for
//                a multi-colour Static the ALTERNATING Solid layout, which is
//                exactly the editor's `actionColors[(i ~/ grp) % n]` bands
//   direction    `reverse` (Left = reversed). Stored, and applied live through
//                the direction door; a design APPLY never states `rev` (#76).
//   brightness   the editor's own slider, stated
//
// The one case that stays per-pixel: a Static pattern with more than three
// colours. An effect design has three colour slots; only a per-LED picture can
// hold fifteen layers.

import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/wled/design_spacing_defaults.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/solid_palette_blocks.dart';

/// True when [pattern] saves as a palette/effect design (everything except a
/// Static pattern with more than three colours).
bool editorSavesAsEffectDesign(EditablePattern pattern) =>
    pattern.effectId != 0 ||
    pattern.actionColors.length <= EditablePattern.maxEffectColors;

/// The design the Pattern Editor's SAVE stores for [pattern].
///
/// [channels] are the channels the editor is targeting. An effect design needs
/// no LED counts, so an empty list saves as one unsized "All" channel (the
/// same fallback the tuner's writers use). Only the per-pixel fallback needs
/// counts, and throws [StateError] without them.
CustomDesign designFromPatternEditor({
  required EditablePattern pattern,
  required String name,
  required String ownerId,
  required List<PatternEditorChannel> channels,
  DateTime? now,
}) {
  if (!editorSavesAsEffectDesign(pattern)) {
    return customDesignFromEditablePattern(
      pattern: pattern,
      name: name,
      ownerId: ownerId,
      channels: channels,
      now: now,
    );
  }

  final stamp = now ?? DateTime.now();
  final isStatic = pattern.effectId == 0;
  final colours = <List<int>>[
    ...(isStatic ? pattern.staticColorsRgbw() : pattern.effectColorSlots()),
    // Layers an animated effect cannot render are KEPT (they are the
    // customer's choices); every apply reads only the first three.
    if (!isStatic && !pattern.backgroundApplies)
      ...pattern.staticColorsRgbw().skip(EditablePattern.maxEffectColors),
  ];
  final groups = <LedColorGroup>[
    for (var i = 0; i < colours.length; i++)
      LedColorGroup(startLed: i, endLed: i, color: colours[i]),
  ];
  final targets = channels.isNotEmpty
      ? channels
      : const [PatternEditorChannel(id: 0, name: 'All', ledCount: 0)];

  return CustomDesign(
    id: '', // empty → DesignService.createDesign → a unique doc id
    name: name,
    description: 'Saved from the Pattern Editor',
    createdAt: stamp,
    updatedAt: stamp,
    ownerId: ownerId,
    channels: [
      for (final c in targets)
        ChannelDesign(
          channelId: c.id,
          channelName: c.name,
          colorGroups: groups,
          effectId: pattern.effectId,
          speed: pattern.speed,
          intensity: pattern.intensity,
          ledCount: c.ledCount,
          grouping: pattern.colorGroupSize.clamp(1, 255),
          spacing: kDesignDefaultSpc,
          // The editor's Static bands ARE the alternating layout.
          solidLayout: isStatic ? SolidLayout.alternating : SolidLayout.blocks,
          reverse: pattern.direction == PatternDirection.left,
        ),
    ],
    brightness: pattern.brightness.clamp(0, 255),
    // The editor's own BRIGHTNESS slider — stated, so every apply restores it.
    brightnessStated: true,
    tags: const [kPatternEditorDesignTag],
    perPixel: false,
  );
}
