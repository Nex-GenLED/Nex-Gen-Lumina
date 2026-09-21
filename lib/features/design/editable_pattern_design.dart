import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/wled/design_spacing_defaults.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';

/// One channel the Pattern Editor is targeting: its WLED segment id, its
/// display name, and its device-truth LED count.
class PatternEditorChannel {
  final int id;
  final String name;
  final int ledCount;

  const PatternEditorChannel({
    required this.id,
    required this.name,
    required this.ledCount,
  });
}

/// The Pattern Editor's "Save" — an [EditablePattern] as the [CustomDesign]
/// that My Designs stores, applies and reopens.
///
/// This REPLACES the old "SAVE TO DEVICE", which `psave`d the pattern into a
/// WLED preset slot (100–200) that nothing in the app could list, load or
/// delete — and, for a Static pattern, stored a black frozen shell, because a
/// WLED preset cannot hold per-pixel data at all
/// (explore-palette-save-to-device-audit-2026-09-20, S1/S2).
///
/// It builds the two shapes the design system already has, rather than a third:
///
/// * **Static (`effectId == 0`)** → a PAINTED design (`perPixel: true`). The
///   editor lights Static per LED — `actionColors[(i ~/ grp) % n]`, restarting
///   at each channel's first LED, which is exactly what its live `i` write does
///   once the channel filter has fanned it out. The same picture is laid into a
///   [PixelDesignDocument] and compressed with `toLedColorGroups()` — the
///   writer the paint editor uses — so it applies through the per-pixel spine
///   and reopens in the paint editor with every LED intact. All 15 layers
///   survive; nothing here is limited to three colours.
///
/// * **Animated** → an EFFECT design, the shape the colourway tuner edits.
///   A WLED effect takes at most three colour slots, so the first three groups
///   are [EditablePattern.effectColorSlots] — byte-identical to what the editor
///   is showing on the lights, background slot included. Any further layers are
///   KEPT in the document (they are the user's choices) but no animated effect
///   can render them; the editor says so on screen rather than leaving it to be
///   discovered.
///
/// [channels] are the channels the editor is targeting. An empty list is only
/// legal for an animated pattern (offline save → one unsized "All" channel,
/// the same fallback `channelsFromComposedPattern` uses); a Static pattern has
/// no picture without LED counts, so it throws [StateError] and the caller
/// must say why nothing was saved.
CustomDesign customDesignFromEditablePattern({
  required EditablePattern pattern,
  required String name,
  required String ownerId,
  required List<PatternEditorChannel> channels,
  DateTime? now,
}) {
  final stamp = now ?? DateTime.now();
  final isStatic = pattern.effectId == 0;

  final List<ChannelDesign> channelDesigns;
  if (isStatic) {
    final sized = [for (final c in channels) if (c.ledCount > 0) c];
    if (sized.isEmpty) {
      throw StateError('A Static pattern is stored per LED and needs the '
          "channels' LED counts; none were available.");
    }
    final doc = _paintStatic(pattern, sized);
    final groups = doc.toLedColorGroups(); // full coverage → self-contained
    channelDesigns = [
      for (final c in sized)
        ChannelDesign(
          channelId: c.id,
          channelName: c.name,
          colorGroups: groups[c.id] ?? const [],
          ledCount: c.ledCount,
        ),
    ];
  } else {
    final palette = _paletteGroups(pattern);
    final targets = channels.isNotEmpty
        ? channels
        : const [PatternEditorChannel(id: 0, name: 'All', ledCount: 0)];
    channelDesigns = [
      for (final c in targets)
        ChannelDesign(
          channelId: c.id,
          channelName: c.name,
          colorGroups: palette,
          effectId: pattern.effectId,
          speed: pattern.speed,
          intensity: pattern.intensity,
          ledCount: c.ledCount,
          // The editor's live payload asserts exactly these (#88).
          grouping: pattern.colorGroupSize.clamp(1, 255),
          spacing: kDesignDefaultSpc,
        ),
    ];
  }

  return CustomDesign(
    id: '', // empty → DesignService.createDesign → `.add()` → a UNIQUE doc id
    name: name,
    description: 'Saved from the Pattern Editor',
    createdAt: stamp,
    updatedAt: stamp,
    ownerId: ownerId,
    channels: channelDesigns,
    brightness: pattern.brightness.clamp(0, 255),
    // The editor's own BRIGHTNESS slider — stated, so every apply restores it.
    brightnessStated: true,
    tags: const [kPatternEditorDesignTag],
    // STATED, never inferred — see CustomDesign.perPixel. A one-colour Static
    // pattern is a single group per channel and would otherwise be classed an
    // effect design and re-applied through the three-colour effect shape.
    perPixel: isStatic,
  );
}

/// The Static look as a per-LED document: every LED of every channel painted
/// `actionColors[(i ~/ grp) % n]`, channel-local.
PixelDesignDocument _paintStatic(
  EditablePattern pattern,
  List<PatternEditorChannel> channels,
) {
  final colors = pattern.staticColorsRgbw();
  final grp = pattern.colorGroupSize < 1 ? 1 : pattern.colorGroupSize;
  var doc = PixelDesignDocument.blank(
    baseColor: const [0, 0, 0, 0],
    channelLengths: {for (final c in channels) c.id: c.ledCount},
  );
  for (final c in channels) {
    // One paint per COLOUR, not per LED: `paint` copies the override map.
    for (int k = 0; k < colors.length; k++) {
      doc = doc.paint(
        c.id,
        [
          for (int i = 0; i < c.ledCount; i++)
            if ((i ~/ grp) % colors.length == k) i,
        ],
        colors[k],
      );
    }
  }
  return doc;
}

/// Palette-style groups for an effect design: the (≤3) live colour slots
/// first, then any layers beyond the third. Single-LED `i..i` groups are the
/// convention every palette writer uses (`current_colors_provider`), and can
/// never satisfy `ChannelDesign.tilesItsChannel` on a real channel.
List<LedColorGroup> _paletteGroups(EditablePattern pattern) {
  final slots = pattern.effectColorSlots();
  final extra = pattern.staticColorsRgbw().skip(3);
  final all = [...slots, ...extra];
  return [
    for (int i = 0; i < all.length; i++)
      LedColorGroup(startLed: i, endLed: i, color: all[i]),
  ];
}

/// [base], or "[base] 2", "[base] 3"… — the first that no design in [taken]
/// already uses (case-insensitive). Two saves from the same Explore card get
/// two distinguishable cards in My Designs instead of two identical names.
String uniqueDesignName(String base, Iterable<String> taken) {
  final used = {for (final t in taken) t.trim().toLowerCase()};
  if (!used.contains(base.trim().toLowerCase())) return base;
  for (int n = 2;; n++) {
    final candidate = '$base $n';
    if (!used.contains(candidate.toLowerCase())) return candidate;
  }
}
