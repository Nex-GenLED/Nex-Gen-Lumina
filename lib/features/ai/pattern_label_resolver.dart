// Resolves the Now Playing label written to activePresetLabelProvider after
// Lumina AI applies a design. Two failure modes the resolver guards against:
//   1. AI returns a patternName that is just a raw WLED effect display name
//      (e.g. "Theater Chase" — fx 12's display name in effect_display_meta).
//   2. AI omits patternName entirely, which previously cleared the label and
//      let displayPatternNameProvider fall back to the WLED effect name.
//
// In both cases we synthesize a label from the original user prompt so the
// dashboard reflects the request context ("KC Royals Game Night") rather than
// the underlying effect.

const _wledEffectNames = <String>{
  'Theater Chase', 'Fire', 'Breathe', 'Fade',
  'Twinkle', 'Sparkle', 'Chase', 'Running',
  'Rainbow', 'Meteor', 'Ripple', 'Strobe',
  'Solid', 'Wipe', 'Scanner', 'Fireworks',
  'Popcorn', 'Bouncing Balls', 'Colortwinkles',
  'Twinklefox', 'Fairy', 'Glitter',
};

const _fillers = <String>{
  'lumina', 'give', 'me', 'a', 'an', 'the',
  'for', 'my', 'lights', 'please', 'can',
  'you', 'i', 'want', 'let', 'do', 'something',
  'cool', 'nice', 'great', 'tonight', 'this',
  'week', 'night',
};

String? resolveLuminaDisplayName(
  String? aiPatternName,
  String? originalPrompt,
) {
  if (aiPatternName != null &&
      aiPatternName.isNotEmpty &&
      !_wledEffectNames.contains(aiPatternName)) {
    return aiPatternName;
  }
  if (originalPrompt == null || originalPrompt.trim().isEmpty) return null;
  final words = originalPrompt
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), '')
      .split(RegExp(r'\s+'))
      .where((w) => !_fillers.contains(w) && w.length > 1)
      .take(4)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .toList();
  return words.isEmpty ? null : words.join(' ');
}
