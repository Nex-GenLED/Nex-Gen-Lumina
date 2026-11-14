import 'package:nexgen_command/features/design/design_models.dart';

/// Design Studio Slice 4 — the manual editor's per-LED working document.
///
/// A sparse per-channel override of a solid [baseColor]: every LED is the base
/// unless painted. Channel-local indices (0-based within each channel's
/// `bus.len`), matching [ChannelDesign.colorGroups] and the Slice 0/3 span
/// transport (`segmentId == channelIndex`).
///
/// Build 129 — a second sparse layer, BRIGHTNESS (0–255, absent = full), kept
/// apart from colour: painting a colour never touches brightness, dimming
/// never touches colour, so re-editing cannot compound and a dim red stays
/// "red at 40 %". [colorAt] is the pure colour; [litColorAt] is what the
/// preview and the lights get.
///
/// Immutable — every edit returns a new document, which the undo/redo history
/// snapshots. Pure (no Firestore, no device, no Riverpod).
class PixelDesignDocument {
  /// RGBW background applied to unpainted LEDs.
  final List<int> baseColor;

  /// channelIndex → LED count (device-truth `WledLedBus.len`).
  final Map<int, int> channelLengths;

  /// Sparse overrides: channelIndex → (localIndex → RGBW). Absent = base.
  final Map<int, Map<int, List<int>>> _overrides;

  /// Sparse brightness: channelIndex → (localIndex → 0–255). Absent = full.
  final Map<int, Map<int, int>> _brightness;

  const PixelDesignDocument({
    required this.baseColor,
    required this.channelLengths,
    Map<int, Map<int, List<int>>> overrides = const {},
    Map<int, Map<int, int>> brightness = const {},
  })  : _overrides = overrides,
        _brightness = brightness;

  /// A blank document (all base) for the given channel lengths.
  factory PixelDesignDocument.blank({
    required List<int> baseColor,
    required Map<int, int> channelLengths,
  }) =>
      PixelDesignDocument(baseColor: baseColor, channelLengths: channelLengths);

  int channelLength(int channel) => channelLengths[channel] ?? 0;

  /// RGBW at a pixel (its override, else the base) — the PURE colour.
  List<int> colorAt(int channel, int index) =>
      _overrides[channel]?[index] ?? baseColor;

  /// The pixel's brightness, 0–255 (full when never dimmed).
  int brightnessAt(int channel, int index) =>
      _brightness[channel]?[index] ?? kLedGroupFullBrightness;

  /// What the pixel SHOWS: its colour at its brightness (the lights' RGBW).
  List<int> litColorAt(int channel, int index) =>
      litRgbwForBrightness(colorAt(channel, index), brightnessAt(channel, index));

  bool isPainted(int channel, int index) =>
      _overrides[channel]?.containsKey(index) ?? false;

  bool isDimmed(int channel, int index) =>
      (_brightness[channel]?[index] ?? kLedGroupFullBrightness) <
      kLedGroupFullBrightness;

  int get paintedCount =>
      _overrides.values.fold(0, (sum, m) => sum + m.length);

  int get dimmedCount =>
      _brightness.values.fold(0, (sum, m) => sum + m.length);

  Map<int, Map<int, List<int>>> _copyOverrides() => {
        for (final e in _overrides.entries)
          e.key: {for (final p in e.value.entries) p.key: p.value},
      };

  Map<int, Map<int, int>> _copyBrightness() => {
        for (final e in _brightness.entries)
          e.key: {for (final p in e.value.entries) p.key: p.value},
      };

  /// Paints [indices] on [channel] with [rgbw] (out-of-range indices ignored).
  /// Brightness is untouched.
  PixelDesignDocument paint(int channel, Iterable<int> indices, List<int> rgbw) {
    final ov = _copyOverrides();
    final ch = ov.putIfAbsent(channel, () => {});
    final len = channelLength(channel);
    for (final i in indices) {
      if (i >= 0 && i < len) ch[i] = rgbw;
    }
    return copyWith(overrides: ov);
  }

  /// Sets the brightness of [indices] on [channel] to [bri] (0–255); full
  /// removes the entry. Colour is untouched.
  PixelDesignDocument setBrightness(int channel, Iterable<int> indices, int bri) {
    final b = _copyBrightness();
    final ch = b.putIfAbsent(channel, () => {});
    final len = channelLength(channel);
    final v = bri.clamp(0, kLedGroupFullBrightness);
    for (final i in indices) {
      if (i < 0 || i >= len) continue;
      if (v >= kLedGroupFullBrightness) {
        ch.remove(i);
      } else {
        ch[i] = v;
      }
    }
    if (ch.isEmpty) b.remove(channel);
    return copyWith(brightness: b);
  }

  /// Clears [indices] on [channel] back to the base color at full brightness.
  PixelDesignDocument clearToBase(int channel, Iterable<int> indices) {
    final ov = _copyOverrides();
    final ch = ov[channel];
    if (ch != null) {
      for (final i in indices) {
        ch.remove(i);
      }
      if (ch.isEmpty) ov.remove(channel);
    }
    final b = _copyBrightness();
    final bch = b[channel];
    if (bch != null) {
      for (final i in indices) {
        bch.remove(i);
      }
      if (bch.isEmpty) b.remove(channel);
    }
    return copyWith(overrides: ov, brightness: b);
  }

  /// Clears every painted pixel (whole design back to base, full brightness).
  PixelDesignDocument clearAll() => copyWith(
        overrides: const <int, Map<int, List<int>>>{},
        brightness: const <int, Map<int, int>>{},
      );

  /// Compresses each channel into FULL-COVERAGE merged [LedColorGroup] runs
  /// (every pixel — base and painted — belongs to exactly one group,
  /// consecutive pixels with the same colour AND brightness merged). This
  /// makes a saved design self-contained and losslessly round-trippable.
  /// Channel-local start/end (inclusive), pure RGBW colour, `bri` per run.
  /// Channels with no length are skipped.
  ///
  /// Set [onlyPainted] to emit ONLY the runs that differ from the base at
  /// full brightness (used for the accent-overlay apply where a solid base is
  /// applied separately) — a dimmed base pixel counts as painted.
  Map<int, List<LedColorGroup>> toLedColorGroups({bool onlyPainted = false}) {
    final out = <int, List<LedColorGroup>>{};
    for (final channel in channelLengths.keys) {
      final len = channelLength(channel);
      if (len <= 0) continue;
      final ch = _overrides[channel];
      final bch = _brightness[channel];
      if (onlyPainted && (ch == null || ch.isEmpty) && (bch == null || bch.isEmpty)) {
        continue;
      }
      final groups = <LedColorGroup>[];
      int runStart = 0;
      List<int> runColor = colorAt(channel, 0);
      int runBri = brightnessAt(channel, 0);
      for (int i = 1; i < len; i++) {
        final c = colorAt(channel, i);
        final b = brightnessAt(channel, i);
        if (b == runBri && _sameColor(c, runColor)) continue;
        _maybeAdd(groups, runStart, i - 1, runColor, runBri, onlyPainted);
        runStart = i;
        runColor = c;
        runBri = b;
      }
      _maybeAdd(groups, runStart, len - 1, runColor, runBri, onlyPainted);
      if (groups.isNotEmpty) out[channel] = groups;
    }
    return out;
  }

  void _maybeAdd(List<LedColorGroup> groups, int start, int end,
      List<int> color, int bri, bool onlyPainted) {
    if (onlyPainted) {
      // Skip runs that ARE the base at full brightness (the base apply covers
      // them).
      if (bri >= kLedGroupFullBrightness && _sameColor(color, baseColor)) return;
    }
    groups.add(LedColorGroup(startLed: start, endLed: end, color: color, bri: bri));
  }

  /// Loads channel-local [groupsByChannel] into a document (opens a saved manual
  /// OR AI design in the editor). Groups are painted over [baseColor]; a
  /// group's `bri` lands in the brightness layer.
  factory PixelDesignDocument.fromLedColorGroups({
    required List<int> baseColor,
    required Map<int, int> channelLengths,
    required Map<int, List<LedColorGroup>> groupsByChannel,
  }) {
    var doc = PixelDesignDocument.blank(
        baseColor: baseColor, channelLengths: channelLengths);
    for (final entry in groupsByChannel.entries) {
      for (final g in entry.value) {
        final rgbw = g.color.length >= 4
            ? g.color
            : [...g.color.take(3), 0];
        final indices = [for (int i = g.startLed; i <= g.endLed; i++) i];
        doc = doc.paint(entry.key, indices, rgbw);
        if (g.isDimmed) doc = doc.setBrightness(entry.key, indices, g.bri);
      }
    }
    return doc;
  }

  PixelDesignDocument copyWith({
    List<int>? baseColor,
    Map<int, int>? channelLengths,
    Map<int, Map<int, List<int>>>? overrides,
    Map<int, Map<int, int>>? brightness,
  }) {
    return PixelDesignDocument(
      baseColor: baseColor ?? this.baseColor,
      channelLengths: channelLengths ?? this.channelLengths,
      overrides: overrides ?? _overrides,
      brightness: brightness ?? _brightness,
    );
  }

  static bool _sameColor(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Build 129 — a brightness RAMP over [indices] (in the order given): from
/// [startPct] at the first to [endPct] at the last, linear in light; with
/// [mirror] the ramp runs start → end → start (the peak/eave look). Returns
/// index → brightness 0–255. Two or more indices; one index gets [startPct].
Map<int, int> brightnessRamp(
  List<int> indices, {
  required int startPct,
  required int endPct,
  bool mirror = false,
}) {
  final out = <int, int>{};
  final n = indices.length;
  if (n == 0) return out;
  int toBri(double pct) => (pct.clamp(0, 100) / 100 * kLedGroupFullBrightness).round();
  if (n == 1) {
    out[indices.first] = toBri(startPct.toDouble());
    return out;
  }
  for (var k = 0; k < n; k++) {
    final t = n == 1 ? 0.0 : k / (n - 1);
    final phase = mirror ? (1 - (1 - 2 * t).abs()) : t;
    out[indices[k]] = toBri(startPct + (endPct - startPct) * phase);
  }
  return out;
}
