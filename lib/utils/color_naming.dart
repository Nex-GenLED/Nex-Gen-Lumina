/// Resolves an RGB or RGBW color tuple to one of nine named colors
/// (red, green, blue, white, yellow, orange, purple, cyan, pink) or a
/// fallback ("custom" for unmatched RGB, "unknown" for short arrays).
///
/// W channel (slot 3 on RGBW input) is intentionally ignored — the
/// caller's branding intent is captured in the RGB primaries; WLED
/// derives W automatically on RGBW bus types from RGB.
///
/// Used by Now Playing label composition ([composeEffectLabel] in
/// `wled_payload_utils.dart`) and the scene-preview color list
/// (`scene_providers.dart` still owns a private duplicate — eventual
/// replacement target, but not blocking).
///
/// Returns lowercase; callers that need title-case apply it themselves.
String colorRgbToName(List<int> color) {
  if (color.length < 3) return 'unknown';
  final r = color[0];
  final g = color[1];
  final b = color[2];

  if (r > 200 && g < 100 && b < 100) return 'red';
  if (r < 100 && g > 200 && b < 100) return 'green';
  if (r < 100 && g < 100 && b > 200) return 'blue';
  if (r > 200 && g > 200 && b > 200) return 'white';
  if (r > 200 && g > 200 && b < 100) return 'yellow';
  if (r > 200 && g > 100 && g < 200 && b < 100) return 'orange';
  if (r > 100 && g < 100 && b > 200) return 'purple';
  if (r < 100 && g > 200 && b > 200) return 'cyan';
  if (r > 200 && g < 150 && b > 150) return 'pink';

  return 'custom';
}
