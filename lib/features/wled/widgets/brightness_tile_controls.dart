import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/brightness_tile.dart';
import 'package:nexgen_command/theme.dart';

/// A white the customer can pick for a brightness pattern.
typedef WhiteChoice = ({String name, Color color});

/// The adjustable brightness pattern (the brief's T3): presets, shape,
/// brightest / dimmest / cycle / offset, lights per step, and a custom tile
/// where every light's level is set by hand. One widget, used by the Explore
/// card's adjustment sheet and by the pattern tuner, so both edit the same
/// thing the same way.
///
/// Stateless about the tile: the owner holds it and gets [onTileChanged] on
/// every edit (it decides when the lights are written).
class BrightnessTileControls extends StatelessWidget {
  final BrightnessTile tile;
  final Color baseColor;
  final ValueChanged<BrightnessTile> onTileChanged;

  /// Whites to offer (Kelvin steps); null hides the row.
  final List<WhiteChoice>? whites;
  final ValueChanged<Color>? onWhiteChanged;

  /// Lights drawn in the preview row.
  final int previewDots;

  const BrightnessTileControls({
    super.key,
    required this.tile,
    required this.baseColor,
    required this.onTileChanged,
    this.whites,
    this.onWhiteChanged,
    this.previewDots = 36,
  });

  static const List<int> _tapCycle = [100, 80, 60, 40, 20, 0];

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(color: NexGenPalette.textSecondary, fontSize: 12);
    final shape = tile.shape;
    final shaped = shape == BrightnessShape.triangle || shape == BrightnessShape.ramp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Brightness pattern', style: labelStyle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in kBrightnessPatternPresets)
              _chip(
                key: ValueKey('tile-preset-${p.id}'),
                label: p.name,
                selected: p.tile == tile,
                onTap: () => onTileChanged(p.tile),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _previewRow(),
        const SizedBox(height: 12),
        Text('Shape', style: labelStyle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip(
              key: const ValueKey('tile-shape-triangle'),
              label: 'Wave',
              selected: shape == BrightnessShape.triangle,
              onTap: () => onTileChanged(BrightnessTile.triangle(
                  brightest: tile.brightest,
                  dimmest: tile.dimmest,
                  cycle: tile.cycleLength,
                  offset: tile.offset)),
            ),
            _chip(
              key: const ValueKey('tile-shape-ramp'),
              label: 'Ramp',
              selected: shape == BrightnessShape.ramp,
              onTap: () => onTileChanged(BrightnessTile.ramp(
                  brightest: tile.brightest,
                  dimmest: tile.dimmest,
                  cycle: tile.cycleLength,
                  offset: tile.offset)),
            ),
            _chip(
              key: const ValueKey('tile-shape-steps'),
              label: 'Steps',
              selected: shape == BrightnessShape.steps,
              onTap: () => onTileChanged(BrightnessTile.steps(
                  _stepLevels(tile),
                  bandWidth: tile.bandWidth,
                  offset: tile.offset)),
            ),
            _chip(
              key: const ValueKey('tile-shape-custom'),
              label: 'Custom',
              selected: shape == BrightnessShape.custom,
              onTap: () => onTileChanged(tile.copyWith(
                  levels: tile.levelsForRun(tile.cycleLength),
                  bandWidth: 1,
                  offset: 0,
                  shape: BrightnessShape.custom)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (shaped) ...[
          _slider(
            key: const ValueKey('tile-brightest'),
            label: 'Brightest',
            value: tile.brightest,
            min: tile.dimmest + 5,
            max: 100,
            onChanged: (v) => onTileChanged(_reshape(brightest: v)),
          ),
          _slider(
            key: const ValueKey('tile-dimmest'),
            label: 'Dimmest',
            value: tile.dimmest,
            min: 0,
            max: tile.brightest - 5,
            onChanged: (v) => onTileChanged(_reshape(dimmest: v)),
          ),
          _slider(
            key: const ValueKey('tile-cycle'),
            label: 'Lights per cycle',
            value: tile.cycleLength,
            min: 2,
            max: 60,
            suffix: '',
            onChanged: (v) => onTileChanged(_reshape(cycle: v)),
          ),
        ],
        if (shape == BrightnessShape.steps)
          _stepper(
            key: const ValueKey('tile-band-width'),
            label: 'Lights per step',
            value: tile.bandWidth,
            min: 1,
            max: 6,
            onChanged: (v) => onTileChanged(tile.copyWith(bandWidth: v)),
          ),
        if (shape == BrightnessShape.steps || shape == BrightnessShape.custom) ...[
          _stepper(
            key: const ValueKey('tile-cell-count'),
            label: shape == BrightnessShape.steps ? 'Steps' : 'Lights in the tile',
            value: tile.levels.length,
            min: 2,
            max: 24,
            onChanged: (n) {
              final levels = List<int>.from(tile.levels);
              while (levels.length < n) {
                levels.add(levels.last);
              }
              onTileChanged(tile.copyWith(levels: levels.take(n).toList()));
            },
          ),
          const SizedBox(height: 6),
          Text('Tap a light to step its level; hold to type a number.', style: labelStyle),
          const SizedBox(height: 6),
          _cellEditor(context),
        ],
        _slider(
          key: const ValueKey('tile-offset'),
          label: 'Start offset',
          value: tile.offset.clamp(0, tile.cycleLength - 1),
          min: 0,
          max: tile.cycleLength - 1,
          suffix: '',
          onChanged: (v) => onTileChanged(tile.copyWith(offset: v)),
        ),
        if (whites != null && whites!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('White', style: labelStyle),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in whites!)
                _chip(
                  key: ValueKey('tile-white-${w.name}'),
                  label: w.name,
                  selected: w.color.toARGB32() == baseColor.toARGB32(),
                  onTap: onWhiteChanged == null ? null : () => onWhiteChanged!(w.color),
                  swatch: w.color,
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          tile.distinctLevelCount > 3
              ? 'This pattern has ${tile.distinctLevelCount} brightness levels, so it is sent to '
                  'each light individually. Apply it now, or save it to My Designs; '
                  'scheduling a saved pattern follows the painted-design rules.'
              : 'Sent to each light individually. Apply it now, or save it to My '
                  'Designs; scheduling a saved pattern follows the painted-design rules.',
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
        ),
      ],
    );
  }

  /// The levels a steps tile should start from: the distinct levels of the
  /// current tile in order (a wave becomes its down-slope), at most 8.
  static List<int> _stepLevels(BrightnessTile t) {
    final out = <int>[];
    for (final l in t.levels) {
      if (out.isEmpty || out.last != l) out.add(l);
      if (out.length == 8) break;
    }
    return out.length < 2 ? [t.brightest, t.dimmest] : out;
  }

  BrightnessTile _reshape({int? brightest, int? dimmest, int? cycle}) {
    final b = (brightest ?? tile.brightest).clamp(0, 100);
    final d = (dimmest ?? tile.dimmest).clamp(0, 100);
    final n = (cycle ?? tile.cycleLength).clamp(2, 60);
    final offset = tile.offset.clamp(0, n - 1);
    return tile.shape == BrightnessShape.ramp
        ? BrightnessTile.ramp(brightest: b, dimmest: d, cycle: n, offset: offset)
        : BrightnessTile.triangle(brightest: b, dimmest: d, cycle: n, offset: offset);
  }

  Widget _previewRow() {
    final levels = tile.levelsForRun(previewDots);
    return SizedBox(
      key: const ValueKey('tile-preview-row'),
      height: 16,
      child: Row(
        children: [
          for (final l in levels)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: dimmedForScreen(baseColor, l),
                  shape: BoxShape.circle,
                  border: Border.all(color: NexGenPalette.line, width: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cellEditor(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < tile.levels.length; i++)
          GestureDetector(
            key: ValueKey('tile-cell-$i'),
            onTap: () {
              final cur = tile.levels[i];
              final idx = _tapCycle.indexWhere((v) => v < cur);
              final next = idx < 0 ? _tapCycle.first : _tapCycle[idx];
              onTileChanged(tile.copyWith(levels: [
                for (var k = 0; k < tile.levels.length; k++)
                  k == i ? next : tile.levels[k],
              ]));
            },
            onLongPress: () => _editCell(context, i),
            child: Container(
              width: 40,
              height: 44,
              decoration: BoxDecoration(
                color: dimmedForScreen(baseColor, tile.levels[i]),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.line),
              ),
              alignment: Alignment.center,
              child: Text('${tile.levels[i]}',
                  style: TextStyle(
                      color: tile.levels[i] > 55 ? Colors.black : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  Future<void> _editCell(BuildContext context, int i) async {
    var value = tile.levels[i];
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: NexGenPalette.gunmetal,
          title: Text('Light ${i + 1} brightness',
              style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 16)),
          content: Row(
            children: [
              Expanded(
                child: Slider(
                  value: value.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  activeColor: NexGenPalette.cyan,
                  onChanged: (v) => setState(() => value = v.round()),
                ),
              ),
              SizedBox(
                  width: 44,
                  child: Text('$value %',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: NexGenPalette.textHigh))),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(value), child: const Text('Set')),
          ],
        ),
      ),
    );
    if (result == null) return;
    onTileChanged(tile.copyWith(levels: [
      for (var k = 0; k < tile.levels.length; k++) k == i ? result : tile.levels[k],
    ]));
  }

  Widget _chip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    Color? swatch,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? NexGenPalette.cyan.withValues(alpha: 0.2) : NexGenPalette.gunmetal,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? NexGenPalette.cyan : NexGenPalette.line,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (swatch != null) ...[
              Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: swatch, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required Key key,
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    String suffix = ' %',
  }) {
    final lo = min.toDouble();
    final hi = max <= min ? lo + 1 : max.toDouble();
    return Row(
      children: [
        SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13))),
        Expanded(
          child: Slider(
            key: key,
            value: value.toDouble().clamp(lo, hi),
            min: lo,
            max: hi,
            divisions: (hi - lo).round().clamp(1, 255),
            activeColor: NexGenPalette.cyan,
            onChanged: max <= min ? null : (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
            width: 48,
            child: Text('$value$suffix',
                textAlign: TextAlign.right,
                style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 12))),
      ],
    );
  }

  Widget _stepper({
    required Key key,
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      key: key,
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13))),
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline, color: NexGenPalette.cyan, size: 20),
        ),
        Text('$value', style: const TextStyle(color: NexGenPalette.textHigh, fontWeight: FontWeight.w700)),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline, color: NexGenPalette.cyan, size: 20),
        ),
      ],
    );
  }
}

/// How a light at [levelPct] % looks on the phone: the base colour scaled
/// linearly (the controller does its own gamma; the phone shows the level).
Color dimmedForScreen(Color base, int levelPct) {
  final k = levelPct.clamp(0, 100) / 100.0;
  return Color.fromARGB(
    255,
    (base.r * 255.0 * k).round().clamp(0, 255),
    (base.g * 255.0 * k).round().clamp(0, 255),
    (base.b * 255.0 * k).round().clamp(0, 255),
  );
}
