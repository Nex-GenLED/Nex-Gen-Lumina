import 'package:nexgen_command/features/design/design_models.dart';

/// Design Studio Slice 4 — the manual editor's per-LED working document.
///
/// A sparse per-channel override of a solid [baseColor]: every LED is the base
/// unless painted. Channel-local indices (0-based within each channel's
/// `bus.len`), matching [ChannelDesign.colorGroups] and the Slice 0/3 span
/// transport (`segmentId == channelIndex`).
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

  const PixelDesignDocument({
    required this.baseColor,
    required this.channelLengths,
    Map<int, Map<int, List<int>>> overrides = const {},
  }) : _overrides = overrides;

  /// A blank document (all base) for the given channel lengths.
  factory PixelDesignDocument.blank({
    required List<int> baseColor,
    required Map<int, int> channelLengths,
  }) =>
      PixelDesignDocument(baseColor: baseColor, channelLengths: channelLengths);

  int channelLength(int channel) => channelLengths[channel] ?? 0;

  /// RGBW at a pixel (its override, else the base).
  List<int> colorAt(int channel, int index) =>
      _overrides[channel]?[index] ?? baseColor;

  bool isPainted(int channel, int index) =>
      _overrides[channel]?.containsKey(index) ?? false;

  int get paintedCount =>
      _overrides.values.fold(0, (sum, m) => sum + m.length);

  Map<int, Map<int, List<int>>> _copyOverrides() => {
        for (final e in _overrides.entries)
          e.key: {for (final p in e.value.entries) p.key: p.value},
      };

  /// Paints [indices] on [channel] with [rgbw] (out-of-range indices ignored).
  PixelDesignDocument paint(int channel, Iterable<int> indices, List<int> rgbw) {
    final ov = _copyOverrides();
    final ch = ov.putIfAbsent(channel, () => {});
    final len = channelLength(channel);
    for (final i in indices) {
      if (i >= 0 && i < len) ch[i] = rgbw;
    }
    return copyWith(overrides: ov);
  }

  /// Clears [indices] on [channel] back to the base color.
  PixelDesignDocument clearToBase(int channel, Iterable<int> indices) {
    final ov = _copyOverrides();
    final ch = ov[channel];
    if (ch != null) {
      for (final i in indices) {
        ch.remove(i);
      }
      if (ch.isEmpty) ov.remove(channel);
    }
    return copyWith(overrides: ov);
  }

  /// Clears every painted pixel (whole design back to base).
  PixelDesignDocument clearAll() =>
      copyWith(overrides: const <int, Map<int, List<int>>>{});

  /// Compresses each channel into FULL-COVERAGE merged [LedColorGroup] runs
  /// (every pixel — base and painted — belongs to exactly one group,
  /// consecutive same-color LEDs merged). This makes a saved design
  /// self-contained and losslessly round-trippable. Channel-local start/end
  /// (inclusive), RGBW color. Channels with no length are skipped.
  ///
  /// Set [onlyPainted] to emit ONLY non-base runs (used for the accent-overlay
  /// apply where a solid base is applied separately).
  Map<int, List<LedColorGroup>> toLedColorGroups({bool onlyPainted = false}) {
    final out = <int, List<LedColorGroup>>{};
    for (final channel in channelLengths.keys) {
      final len = channelLength(channel);
      if (len <= 0) continue;
      final ch = _overrides[channel];
      if (onlyPainted && (ch == null || ch.isEmpty)) continue;
      final groups = <LedColorGroup>[];
      int runStart = 0;
      List<int> runColor = colorAt(channel, 0);
      for (int i = 1; i < len; i++) {
        final c = colorAt(channel, i);
        if (_sameColor(c, runColor)) continue;
        _maybeAdd(groups, runStart, i - 1, runColor, channel, onlyPainted);
        runStart = i;
        runColor = c;
      }
      _maybeAdd(groups, runStart, len - 1, runColor, channel, onlyPainted);
      if (groups.isNotEmpty) out[channel] = groups;
    }
    return out;
  }

  void _maybeAdd(List<LedColorGroup> groups, int start, int end,
      List<int> color, int channel, bool onlyPainted) {
    if (onlyPainted) {
      // Skip runs whose color equals the base (they'll be covered by the
      // base apply). Also skip runs where no pixel is actually overridden.
      if (_sameColor(color, baseColor)) return;
    }
    groups.add(LedColorGroup(startLed: start, endLed: end, color: color));
  }

  /// Loads channel-local [groupsByChannel] into a document (opens a saved manual
  /// OR AI design in the editor). Groups are painted over [baseColor].
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
        doc = doc.paint(
          entry.key,
          [for (int i = g.startLed; i <= g.endLed; i++) i],
          rgbw,
        );
      }
    }
    return doc;
  }

  PixelDesignDocument copyWith({
    List<int>? baseColor,
    Map<int, int>? channelLengths,
    Map<int, Map<int, List<int>>>? overrides,
  }) {
    return PixelDesignDocument(
      baseColor: baseColor ?? this.baseColor,
      channelLengths: channelLengths ?? this.channelLengths,
      overrides: overrides ?? _overrides,
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
