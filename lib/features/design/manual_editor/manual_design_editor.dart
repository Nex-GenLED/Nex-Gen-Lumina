import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/schedule/schedule_off_warning.dart';
import 'package:nexgen_command/features/design/manual_editor/design_frame.dart';
import 'package:nexgen_command/features/design/manual_editor/design_preview.dart';
import 'package:nexgen_command/features/design/manual_editor/edit_history.dart';
import 'package:nexgen_command/features/design/manual_editor/pixel_design_document.dart';
import 'package:nexgen_command/features/design/manual_editor/selection_logic.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/smart_presets/smart_preset_models.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Design Studio Slice 4 — the manual per-pixel editor body (rendered inside
/// the studio's "Manual Design" mode). Select pixels (singles, drag ranges,
/// every-Nth, by-feature, anchors), paint them, undo/redo, live-preview on the
/// lights, apply, and save as a CustomDesign to the shared /designs library.
class ManualDesignEditor extends ConsumerStatefulWidget {
  const ManualDesignEditor({super.key, this.initialDesign});

  /// Optional design to open into the editor (a saved manual OR AI design).
  final CustomDesign? initialDesign;

  @override
  ConsumerState<ManualDesignEditor> createState() => _ManualDesignEditorState();
}

class _ManualDesignEditorState extends ConsumerState<ManualDesignEditor> {
  static const _base = [10, 10, 12, 0];

  EditHistory? _history;
  int? _activeChannel;
  final Map<int, Set<int>> _selection = {};
  List<int> _paintColor = kSmartPresetPalette[3].rgbw; // cyan default
  bool _livePreview = false;
  Timer? _previewThrottle;
  bool _busy = false;

  PixelDesignDocument get _doc => _history!.current;

  @override
  void dispose() {
    _previewThrottle?.cancel();
    super.dispose();
  }

  Map<int, int> _channelLengths() {
    final channels = ref.read(deviceChannelsProvider);
    return {for (final c in channels) c.id: (c.stop - c.start).clamp(0, 100000)};
  }

  void _ensureInit() {
    if (_history != null) return;
    final lengths = _channelLengths();
    if (lengths.isEmpty) return;
    PixelDesignDocument doc;
    if (widget.initialDesign != null) {
      final groups = <int, List<LedColorGroup>>{
        for (final ch in widget.initialDesign!.channels)
          if (ch.included) ch.channelId: ch.colorGroups,
      };
      doc = PixelDesignDocument.fromLedColorGroups(
          baseColor: _base, channelLengths: lengths, groupsByChannel: groups);
    } else {
      doc = PixelDesignDocument.blank(baseColor: _base, channelLengths: lengths);
    }
    _history = EditHistory(doc);
    _activeChannel = lengths.keys.first;
  }

  // ── Editing ─────────────────────────────────────────────────────────────

  void _commit(PixelDesignDocument next) {
    _history!.push(next);
    setState(() {});
    if (_livePreview) _scheduleLivePreview();
  }

  void _paintSelection() {
    if (_selection.values.every((s) => s.isEmpty)) return;
    var doc = _doc;
    for (final e in _selection.entries) {
      doc = doc.paint(e.key, e.value, _paintColor);
    }
    _commit(doc);
  }

  void _clearSelectionToBase() {
    var doc = _doc;
    for (final e in _selection.entries) {
      doc = doc.clearToBase(e.key, e.value);
    }
    _commit(doc);
  }

  void _undo() {
    _history!.undo();
    setState(() {});
    if (_livePreview) _scheduleLivePreview();
  }

  void _redo() {
    _history!.redo();
    setState(() {});
    if (_livePreview) _scheduleLivePreview();
  }

  // ── Selection ───────────────────────────────────────────────────────────

  Set<int> _sel(int channel) => _selection.putIfAbsent(channel, () => {});

  void _toggle(int channel, int index) {
    final s = _sel(channel);
    if (!s.remove(index)) s.add(index);
    setState(() {});
  }

  void _selectRange(int channel, int a, int b) {
    final s = _sel(channel);
    for (int i = a <= b ? a : b; i <= (a <= b ? b : a); i++) {
      s.add(i);
    }
    setState(() {});
  }

  void _addAll(int channel, Iterable<int> indices) {
    _sel(channel).addAll(indices);
    setState(() {});
  }

  void _clearSelection() {
    _selection.clear();
    setState(() {});
  }

  void _selectFeature(FeatureFilter filter) {
    final config = ref.read(currentRooflineConfigProvider).valueOrNull;
    final ch = _activeChannel;
    if (config == null || ch == null) return;
    _addAll(ch, featureIndices(config.segmentsForChannel(ch), filter));
  }

  void _selectAnchors() {
    final config = ref.read(currentRooflineConfigProvider).valueOrNull;
    final ch = _activeChannel;
    if (config == null || ch == null) return;
    _addAll(ch, anchorIndices(config.segmentsForChannel(ch)));
  }

  Future<void> _everyNthDialog() async {
    final ch = _activeChannel;
    if (ch == null) return;
    final len = _channelLengths()[ch] ?? 0;
    int start = 0, end = len - 1, step = 3;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: NexGenPalette.gunmetal90,
          title: const Text('Every-Nth', style: TextStyle(color: Colors.white)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _numRow('Start', start, 0, len - 1, (v) => set(() => start = v)),
            _numRow('End', end, 0, len - 1, (v) => set(() => end = v)),
            _numRow('Every', step, 1, 20, (v) => set(() => step = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                _addAll(ch, everyNthInRange(start: start, end: end, step: step));
                Navigator.pop(ctx);
              },
              child: const Text('Select'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numRow(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Row(children: [
      SizedBox(width: 60, child: Text(label, style: const TextStyle(color: NexGenPalette.textMedium))),
      Expanded(
        child: Slider(
          value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: (max - min).clamp(1, 1000),
          label: '$value',
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
      SizedBox(width: 30, child: Text('$value', style: const TextStyle(color: Colors.white))),
    ]);
  }

  // ── Apply / preview / save ──────────────────────────────────────────────

  Map<int, List<PixelSpan>> _spans() {
    final groups = _doc.toLedColorGroups(onlyPainted: true);
    return {for (final e in groups.entries) e.key: ledColorGroupsToSpans(e.value)};
  }

  void _scheduleLivePreview() {
    _previewThrottle?.cancel();
    _previewThrottle = Timer(const Duration(milliseconds: 300), () {
      applyBaseAndSpans(ref,
          baseRgbw: _doc.baseColor, spansByChannel: _spans(), label: 'Design (preview)');
    });
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final ok = await applyBaseAndSpans(ref,
          baseRgbw: _doc.baseColor, spansByChannel: _spans(), label: 'Custom Design');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? 'Applied to your lights' : "Couldn't reach your lights."),
          backgroundColor: ok ? Colors.green : Colors.red.shade800,
        ));
      }
      if (ok) maybeShowManualApplyOffWarning(ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final uid = ref.read(effectiveUserUidProvider);
    if (uid == null) return;
    setState(() => _busy = true);
    try {
      final groups = _doc.toLedColorGroups(); // full coverage → self-contained
      final channels = [
        for (final e in groups.entries)
          ChannelDesign(
            channelId: e.key,
            channelName: 'Channel ${e.key + 1}',
            colorGroups: e.value,
            ledCount: _doc.channelLength(e.key),
          ),
      ];
      final design = CustomDesign(
        id: '',
        name: 'Custom Design',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        ownerId: uid,
        channels: channels,
      );
      await ref.read(designServiceProvider).saveDesign(uid, design);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Saved to My Designs'), backgroundColor: NexGenPalette.cyan));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _ensureInit();
    final lengths = _channelLengths();
    if (_history == null || lengths.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Connect your controller to paint pixels.',
              style: TextStyle(color: NexGenPalette.textMedium)),
        ),
      );
    }
    final ch = _activeChannel!;
    final frame = frameFromDocument(_doc);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignPreview(frame: frame, height: 200),
          const SizedBox(height: 12),
          // Channel tabs.
          if (lengths.length > 1)
            Wrap(spacing: 8, children: [
              for (final id in lengths.keys)
                ChoiceChip(
                  selected: id == ch,
                  label: Text('Channel ${id + 1}'),
                  onSelected: (_) => setState(() => _activeChannel = id),
                ),
            ]),
          const SizedBox(height: 8),
          // Selection strip (tap toggle + drag range).
          _SelectionStrip(
            length: lengths[ch] ?? 0,
            selected: _sel(ch),
            colorAt: (i) => _toColorLocal(_doc.colorAt(ch, i)),
            onToggle: (i) => _toggle(ch, i),
            onRange: (a, b) => _selectRange(ch, a, b),
          ),
          const SizedBox(height: 10),
          // Selection tools.
          Wrap(spacing: 8, runSpacing: 8, children: [
            _tool('All corners', () => _selectFeature(FeatureFilter.allCorners)),
            _tool('All peaks', () => _selectFeature(FeatureFilter.allPeaks)),
            _tool('All runs', () => _selectFeature(FeatureFilter.allRuns)),
            _tool('Anchors', _selectAnchors),
            _tool('Every-Nth', _everyNthDialog),
            _tool('Clear sel.', _clearSelection),
          ]),
          const Divider(color: NexGenPalette.line, height: 24),
          // Palette.
          const Text('Paint color', style: TextStyle(color: NexGenPalette.textMedium)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in kSmartPresetPalette)
              GestureDetector(
                onTap: () => setState(() => _paintColor = p.rgbw),
                child: Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(255, p.rgbw[0], p.rgbw[1], p.rgbw[2]),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _eq(p.rgbw, _paintColor) ? NexGenPalette.cyan : NexGenPalette.line,
                      width: _eq(p.rgbw, _paintColor) ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: _paintSelection, icon: const Icon(Icons.brush, size: 18), label: const Text('Paint')),
            OutlinedButton.icon(onPressed: _clearSelectionToBase, icon: const Icon(Icons.format_color_reset, size: 18), label: const Text('Erase')),
            IconButton(onPressed: _history!.canUndo ? _undo : null, icon: const Icon(Icons.undo), color: Colors.white),
            IconButton(onPressed: _history!.canRedo ? _redo : null, icon: const Icon(Icons.redo), color: Colors.white),
          ]),
          const Divider(color: NexGenPalette.line, height: 24),
          Row(children: [
            Switch(value: _livePreview, onChanged: (v) {
              setState(() => _livePreview = v);
              if (v) _scheduleLivePreview();
            }),
            const Text('Preview on lights', style: TextStyle(color: Colors.white)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
                onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined, size: 18), label: const Text('Save'))),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: FilledButton.icon(
                onPressed: _busy ? null : _apply, icon: const Icon(Icons.lightbulb, size: 18), label: const Text('Apply to Lights'))),
          ]),
        ],
      ),
    );
  }

  Widget _tool(String label, VoidCallback onTap) =>
      OutlinedButton(onPressed: onTap, child: Text(label));

  Color _toColorLocal(List<int> rgbw) => rgbw.length >= 3
      ? Color.fromARGB(255, rgbw[0], rgbw[1], rgbw[2])
      : Colors.black;

  bool _eq(List<int> a, List<int> b) =>
      a.length == b.length && a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3];
}

/// A horizontal LED strip for selection: tap toggles a cell, horizontal drag
/// selects a range. Each cell shows its current paint color; selected cells get
/// a highlight ring.
class _SelectionStrip extends StatefulWidget {
  const _SelectionStrip({
    required this.length,
    required this.selected,
    required this.colorAt,
    required this.onToggle,
    required this.onRange,
  });

  final int length;
  final Set<int> selected;
  final Color Function(int) colorAt;
  final void Function(int) onToggle;
  final void Function(int a, int b) onRange;

  @override
  State<_SelectionStrip> createState() => _SelectionStripState();
}

class _SelectionStripState extends State<_SelectionStrip> {
  int? _dragStart;

  int _indexAt(double dx, double width) {
    if (widget.length <= 0) return 0;
    final cell = width / widget.length;
    return (dx / cell).floor().clamp(0, widget.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      return GestureDetector(
        onTapDown: (d) => widget.onToggle(_indexAt(d.localPosition.dx, width)),
        onHorizontalDragStart: (d) => _dragStart = _indexAt(d.localPosition.dx, width),
        onHorizontalDragUpdate: (d) {
          if (_dragStart != null) {
            widget.onRange(_dragStart!, _indexAt(d.localPosition.dx, width));
          }
        },
        onHorizontalDragEnd: (_) => _dragStart = null,
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: NexGenPalette.matteBlack,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NexGenPalette.line),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              for (int i = 0; i < widget.length; i++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 0.3),
                    decoration: BoxDecoration(
                      color: widget.colorAt(i),
                      borderRadius: BorderRadius.circular(2),
                      border: widget.selected.contains(i)
                          ? Border.all(color: NexGenPalette.cyan, width: 2)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}
