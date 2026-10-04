import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

/// Human-readable display metadata for WLED effect IDs.
///
/// Used by the schedule card UI and detail bottom sheet to describe
/// what a lighting effect looks like without querying the pattern library.
class EffectDisplayMeta {
  /// Human-readable effect name (e.g. "Breathe", "Chase")
  final String name;

  /// One-line description of the visual appearance
  final String motionDescription;

  /// False only for fx:0 (Solid). True for all animated effects.
  final bool isMotion;

  /// 0.0–1.0 animation phase to show as a static preview thumbnail.
  /// Choosing a mid-cycle frame gives the most representative snapshot.
  final double previewFrameOffset;

  const EffectDisplayMeta({
    required this.name,
    required this.motionDescription,
    required this.isMotion,
    this.previewFrameOffset = 0.35,
  });

  /// Default metadata for unmapped effect IDs.
  static const _fallback = EffectDisplayMeta(
    name: 'Custom Effect',
    motionDescription: 'Animated lighting effect',
    isMotion: true,
  );

  /// Look up display metadata for a WLED effect ID. An id without a curated
  /// entry is named by the effect catalog (WLED 0.15.1's own names, #167) —
  /// never "Custom Effect" for an effect the controller can name.
  static EffectDisplayMeta fromId(int fxId) {
    final curated = _map[fxId];
    if (curated != null) return curated;
    final known = WledEffectsCatalog.getById(fxId);
    if (known == null) return _fallback;
    return EffectDisplayMeta(
      name: known.name,
      motionDescription: _fallback.motionDescription,
      isMotion: fxId != 0,
    );
  }

  /// All mapped effects, keyed by WLED effect ID. Every [name] is the effect
  /// catalog's name for that id (#167: several used to name a different
  /// effect — 12 read "Theater Chase" while the controller plays Fade).
  /// effect_display_meta_test.dart holds each one to the catalog.
  static const Map<int, EffectDisplayMeta> _map = {
    0: EffectDisplayMeta(
      name: 'Solid',
      motionDescription: 'All lights on, steady',
      isMotion: false,
      previewFrameOffset: 0.0,
    ),
    1: EffectDisplayMeta(
      name: 'Blink',
      motionDescription: 'Simple on/off blinking',
      isMotion: true,
      previewFrameOffset: 0.25,
    ),
    2: EffectDisplayMeta(
      name: 'Breathe',
      motionDescription: 'Slow fade in and out',
      isMotion: true,
      previewFrameOffset: 0.5,
    ),
    3: EffectDisplayMeta(
      name: 'Wipe',
      motionDescription: 'Color sweeping across the strip',
      isMotion: true,
    ),
    6: EffectDisplayMeta(
      name: 'Sweep',
      motionDescription: 'Smooth color wash end to end',
      isMotion: true,
    ),
    12: EffectDisplayMeta(
      name: 'Fade',
      motionDescription: 'Colors fading smoothly from one to the next',
      isMotion: true,
      previewFrameOffset: 0.3,
    ),
    15: EffectDisplayMeta(
      name: 'Running',
      motionDescription: 'Colors streaming along the strip',
      isMotion: true,
      previewFrameOffset: 0.4,
    ),
    17: EffectDisplayMeta(
      name: 'Twinkle',
      motionDescription: 'Random lights twinkling on and off',
      isMotion: true,
    ),
    41: EffectDisplayMeta(
      name: 'Lighthouse',
      motionDescription: 'A beam of light sweeping along the strip',
      isMotion: true,
      previewFrameOffset: 0.4,
    ),
    43: EffectDisplayMeta(
      name: 'Rain',
      motionDescription: 'Drops of color falling along the strip',
      isMotion: true,
      previewFrameOffset: 0.45,
    ),
    46: EffectDisplayMeta(
      name: 'Gradient',
      motionDescription: 'A smooth color blend moving across the strip',
      isMotion: true,
    ),
    49: EffectDisplayMeta(
      name: 'Fairy',
      motionDescription: 'Delicate shimmering sparkles',
      isMotion: true,
    ),
    51: EffectDisplayMeta(
      name: 'Fairytwinkle',
      motionDescription: 'Delicate lights twinkling softly',
      isMotion: true,
      previewFrameOffset: 0.0,
    ),
    52: EffectDisplayMeta(
      name: 'Running Dual',
      motionDescription: 'Two waves of color running in opposite directions',
      isMotion: true,
      previewFrameOffset: 0.6,
    ),
    63: EffectDisplayMeta(
      name: 'Pride 2015',
      motionDescription: 'Slowly shifting waves of color',
      isMotion: true,
      previewFrameOffset: 0.3,
    ),
    83: EffectDisplayMeta(
      name: 'Solid Pattern',
      motionDescription: 'Repeating color blocks across the strip',
      isMotion: false,
      previewFrameOffset: 0.0,
    ),
  };
}
