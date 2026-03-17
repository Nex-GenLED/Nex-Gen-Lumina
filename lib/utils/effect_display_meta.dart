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

  /// Look up display metadata for a WLED effect ID.
  static EffectDisplayMeta fromId(int fxId) => _map[fxId] ?? _fallback;

  /// All mapped effects, keyed by WLED effect ID.
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
      name: 'Theater Chase',
      motionDescription: 'Blocks of light sweeping forward',
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
      name: 'Sparkle',
      motionDescription: 'Random bright flashes on a dim base',
      isMotion: true,
    ),
    41: EffectDisplayMeta(
      name: 'Running',
      motionDescription: 'Colors streaming along the strip',
      isMotion: true,
      previewFrameOffset: 0.4,
    ),
    43: EffectDisplayMeta(
      name: 'Twinkle',
      motionDescription: 'Random lights flickering on and off',
      isMotion: true,
      previewFrameOffset: 0.45,
    ),
    46: EffectDisplayMeta(
      name: 'Twinkle Fox',
      motionDescription: 'Soft random twinkling like starlight',
      isMotion: true,
    ),
    49: EffectDisplayMeta(
      name: 'Fairy',
      motionDescription: 'Delicate shimmering sparkles',
      isMotion: true,
    ),
    51: EffectDisplayMeta(
      name: 'Gradient',
      motionDescription: 'Smooth color blend across the strip',
      isMotion: true,
      previewFrameOffset: 0.0,
    ),
    52: EffectDisplayMeta(
      name: 'Fireworks',
      motionDescription: 'Bursts of color with sparkle',
      isMotion: true,
      previewFrameOffset: 0.6,
    ),
    63: EffectDisplayMeta(
      name: 'Candle',
      motionDescription: 'Gentle warm flicker',
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
