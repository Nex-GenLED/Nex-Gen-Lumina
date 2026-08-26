// The colourway tuner's payload shape, extracted so every exit builds it the
// same way.
//
// `ColorwayEffectSelectorPage` had this map inlined twice — once in the
// debounced preview (`_sendToWled`) and once at commit (`_applyPattern`) — and
// Phase C adds a third caller (save-to-design). Three inline copies of a WLED
// seg is how the grp/spc split in #88 happened, so it is one builder now.
//
// Pure Dart apart from the effects catalog lookup: no Flutter, no providers.
// That is what lets the round-trip (payload → state → payload) be tested
// without a widget or a container.

import 'package:nexgen_command/features/wled/design_spacing_defaults.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

/// Everything the tuner's seven selector providers contribute to a payload.
///
/// Note what is NOT here: `gradientPreset` and `breathing` are inputs that
/// RESOLVE to [effectId] / [speed] / [colors] before a payload exists (see
/// the brightness-gradient branch in the selector), so they never reach the
/// wire as themselves.
class SelectorState {
  final int effectId;
  final int speed;
  final int intensity;

  /// WLED `grp` — LEDs per colour band.
  final int grouping;

  /// WLED `spc` — dark pixels between bands.
  final int spacing;

  /// `col`, already RGBW-normalised.
  final List<List<int>> colors;

  /// Top-level `bri`. The catalog exits commit at full brightness and let the
  /// device's own master control the level; a stored design carries its own.
  final int brightness;

  const SelectorState({
    required this.effectId,
    required this.speed,
    required this.intensity,
    required this.colors,
    this.grouping = kDesignDefaultGrp,
    this.spacing = kDesignDefaultSpc,
    this.brightness = 255,
  });

  SelectorState copyWith({
    int? effectId,
    int? speed,
    int? intensity,
    int? grouping,
    int? spacing,
    List<List<int>>? colors,
    int? brightness,
  }) {
    return SelectorState(
      effectId: effectId ?? this.effectId,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      grouping: grouping ?? this.grouping,
      spacing: spacing ?? this.spacing,
      colors: colors ?? this.colors,
      brightness: brightness ?? this.brightness,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SelectorState &&
      other.effectId == effectId &&
      other.speed == speed &&
      other.intensity == intensity &&
      other.grouping == grouping &&
      other.spacing == spacing &&
      other.brightness == brightness &&
      _colorsEqual(other.colors, colors);

  @override
  int get hashCode => Object.hash(
      effectId, speed, intensity, grouping, spacing, brightness, colors.length);

  @override
  String toString() => 'SelectorState(fx:$effectId sx:$speed ix:$intensity '
      'grp:$grouping spc:$spacing bri:$brightness cols:${colors.length})';
}

bool _colorsEqual(List<List<int>> a, List<List<int>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].length != b[i].length) return false;
    for (var j = 0; j < a[i].length; j++) {
      if (a[i][j] != b[i][j]) return false;
    }
  }
  return true;
}

/// The single tuner payload builder.
///
/// `pal` is derived from the effect's colour behaviour rather than hardcoded —
/// palette-driven effects sweep a gradient of the user's colours (pal 4),
/// col-based effects keep them discrete (pal 5). `WledEffectsCatalog` is the
/// single source of truth for that and is also enforced downstream at the
/// apply chokepoint.
Map<String, dynamic> buildSelectorPayload(SelectorState s) {
  final cols = s.colors.isEmpty
      ? <List<int>>[
          [255, 255, 255, 0]
        ]
      : s.colors;
  return <String, dynamic>{
    'on': true,
    'bri': s.brightness,
    'seg': [
      {
        'fx': s.effectId,
        'sx': s.speed,
        'ix': s.intensity,
        'pal': WledEffectsCatalog.paletteForEffect(s.effectId),
        'grp': s.grouping,
        'spc': s.spacing,
        'col': cols,
      }
    ],
  };
}

/// Inverse of [buildSelectorPayload]: read a stored payload back into the
/// state the tuner's providers hold.
///
/// Tolerant by design — it is fed payloads written by older builders. Any key
/// the payload omits falls back to the tuner's own default, which is why a
/// legacy seg with no `grp`/`spc` seeds the #88 design defaults rather than
/// whatever the controller happens to be showing.
SelectorState selectorStateFromPayload(Map<String, dynamic> payload) {
  final segs = payload['seg'];
  Map<String, dynamic>? seg;
  if (segs is List) {
    for (final s in segs) {
      // Skip the #67 exclusion segs (`{id: n, on: false}`) that
      // applyChannelFilter emits — they carry no design fields.
      if (s is Map && s.containsKey('fx')) {
        seg = Map<String, dynamic>.from(s);
        break;
      }
    }
  } else if (segs is Map) {
    seg = Map<String, dynamic>.from(segs);
  }
  seg ??= const <String, dynamic>{};

  int asInt(Object? v, int fallback) => v is num ? v.toInt() : fallback;

  final rawCols = seg['col'];
  final colors = <List<int>>[];
  if (rawCols is List) {
    for (final c in rawCols) {
      if (c is List) colors.add([for (final v in c) asInt(v, 0)]);
    }
  }

  return SelectorState(
    effectId: asInt(seg['fx'], 0),
    speed: asInt(seg['sx'], 128),
    intensity: asInt(seg['ix'], 128),
    grouping: asInt(seg['grp'], kDesignDefaultGrp),
    spacing: asInt(seg['spc'], kDesignDefaultSpc),
    colors: colors,
    brightness: asInt(payload['bri'], 255),
  );
}
