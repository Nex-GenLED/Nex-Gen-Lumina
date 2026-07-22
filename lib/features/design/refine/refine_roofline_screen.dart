import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/design/manual_editor/design_frame.dart';
import 'package:nexgen_command/features/design/manual_editor/design_preview.dart';
import 'package:nexgen_command/features/design/refine/boundary_nudge_logic.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/theme.dart';

/// Design Studio Slice 5 — customer boundary refine. View the map, select a
/// feature (its range lights on the actual strip), nudge its boundary ±N with
/// LIVE on-house feedback, and repair a stale channel by proportional rescale.
/// Saves through the Slice 1 service (owner write). No map creation here.
class RefineRooflineScreen extends ConsumerStatefulWidget {
  const RefineRooflineScreen({super.key});

  @override
  ConsumerState<RefineRooflineScreen> createState() =>
      _RefineRooflineScreenState();
}

class _RefineRooflineScreenState extends ConsumerState<RefineRooflineScreen> {
  static const _dim = [20, 20, 26, 0];
  static const _accent = [0, 229, 255, 0]; // selected feature spotlight

  /// Working copy of the map, per channel.
  final Map<int, List<RooflineSegment>> _edited = {};
  int? _activeChannel;
  int? _selectedFeature;
  bool _dirty = false;
  bool _busy = false;
  Timer? _throttle;

  Map<String, dynamic>? _priorState;
  int? _litChannel;

  @override
  void dispose() {
    _throttle?.cancel();
    _restorePrior();
    super.dispose();
  }

  void _ensureLoaded() {
    if (_edited.isNotEmpty || _activeChannel != null) return;
    final config = ref.read(currentRooflineConfigProvider).valueOrNull;
    if (config == null) return;
    for (final ch in config.allChannelIndices) {
      _edited[ch] = config.segmentsForChannel(ch);
    }
    _activeChannel = config.allChannelIndices.isNotEmpty
        ? config.allChannelIndices.first
        : null;
  }

  Map<int, int> _busLen() {
    final channels = ref.read(deviceChannelsProvider);
    return {for (final c in channels) c.id: (c.stop - c.start).clamp(0, 100000)};
  }

  List<RooflineSegment> _segs(int ch) => _edited[ch] ?? const [];

  // ── Device spotlight (live feedback) ────────────────────────────────────

  PerPixelWriter? get _writer {
    final repo = ref.read(wledRepositoryProvider);
    return repo is PerPixelWriter ? repo as PerPixelWriter : null;
  }

  Future<void> _enterChannel(int ch) async {
    if (_litChannel == ch) return;
    await _restorePrior();
    _litChannel = ch;
    try {
      _priorState = await ref.read(wledRepositoryProvider)?.getState();
    } catch (_) {
      _priorState = null;
    }
  }

  /// Lights the selected feature's range (accent) over a dim base — throttled.
  void _spotlightSelected() {
    _throttle?.cancel();
    _throttle = Timer(const Duration(milliseconds: 200), () async {
      final ch = _activeChannel, fi = _selectedFeature;
      final writer = _writer;
      if (ch == null || fi == null || writer == null) return;
      final segs = _segs(ch);
      if (fi < 0 || fi >= segs.length) return;
      final f = segs[fi];
      // Dim base + bright accent on the selected feature.
      await writer.applyPerPixel(
        segmentId: ch,
        spans: [
          PixelSpan(start: 0, end: channelTotal(segs) - 1, color: _dim),
          PixelSpan(start: f.startPixel, end: f.endPixel, color: _accent),
        ],
      );
    });
  }

  Future<void> _restorePrior() async {
    final lit = _litChannel;
    if (lit == null) return;
    _litChannel = null;
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;
    try {
      final prior = _priorState;
      Map<String, dynamic>? seg;
      if (prior != null && prior['seg'] is List) {
        for (final s in (prior['seg'] as List)) {
          if (s is Map && s['id'] == lit) {
            seg = Map<String, dynamic>.from(s);
            break;
          }
        }
      }
      await repo.applyJson({
        'seg': [
          {
            'id': lit,
            'on': seg?['on'] ?? true,
            if (seg?['fx'] != null) 'fx': seg!['fx'],
            if (seg?['col'] != null) 'col': seg!['col'],
            'i': const <dynamic>[],
          }
        ]
      });
    } catch (_) {}
    _priorState = null;
  }

  // ── Editing ─────────────────────────────────────────────────────────────

  void _nudge(BoundaryEdge edge, int delta) {
    final ch = _activeChannel, fi = _selectedFeature;
    if (ch == null || fi == null) return;
    final updated = nudgeBoundary(_segs(ch), fi, edge, delta);
    setState(() {
      _edited[ch] = updated;
      _dirty = true;
    });
    _spotlightSelected();
  }

  void _selectFeature(int index) {
    setState(() => _selectedFeature = index);
    _spotlightSelected();
  }

  Future<void> _rescale(int ch) async {
    final live = _busLen()[ch];
    if (live == null || live <= 0) return;
    final segs = _segs(ch);
    final old = channelTotal(segs);
    if (old == live) return;
    final preview = rescaleChannel(segs, old, live);
    final accept = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Rescale to fit', style: TextStyle(color: Colors.white)),
        content: Text(
          'Your roofline now has $live LEDs on this channel (was $old). '
          'Rescale all ${segs.length} features proportionally?',
          style: const TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Rescale')),
        ],
      ),
    );
    if (accept == true) {
      setState(() {
        _edited[ch] = preview;
        _dirty = true;
        _selectedFeature = null;
      });
    }
  }

  Future<void> _save() async {
    final uid = ref.read(effectiveUserUidProvider);
    final controllerId = ref.read(activePixelMapControllerIdProvider);
    if (uid == null || controllerId == null) return;
    setState(() => _busy = true);
    try {
      await _restorePrior();
      final segments = <RooflineSegment>[
        for (final ch in (_edited.keys.toList()..sort())) ..._edited[ch]!,
      ];
      // source_pixel_count = mapped total per channel → a rescaled channel now
      // matches live bus.len and its stale flag clears.
      final sourceCounts = {
        for (final ch in _edited.keys) ch: channelTotal(_edited[ch]!),
      };
      final config = RooflineConfiguration(
        id: controllerId,
        controllerId: controllerId,
        name: 'Roofline',
        segments: segments,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        totalChannelCount: _edited.length,
      );
      await ref.read(rooflineConfigServiceProvider).savePixelMap(
            uid, controllerId, config,
            sourceCounts: sourceCounts, createdBy: uid,
          );
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Saved'), backgroundColor: NexGenPalette.cyan));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Preview frame (feature-colored) ─────────────────────────────────────

  DesignFrame _frame() {
    final frame = <int, List<Color>>{};
    _edited.forEach((ch, segs) {
      final total = channelTotal(segs);
      final colors = List<Color>.filled(total, const Color(0xFF14141A));
      for (int fi = 0; fi < segs.length; fi++) {
        final s = segs[fi];
        final c = ch == _activeChannel && fi == _selectedFeature
            ? const Color(0xFF00E5FF)
            : _tint(s);
        for (int i = s.startPixel; i <= s.endPixel && i < total; i++) {
          colors[i] = c;
        }
      }
      frame[ch] = colors;
    });
    return frame;
  }

  Color _tint(RooflineSegment s) {
    if (s.type == SegmentType.peak) return const Color(0xFF8A5A00);
    if (s.type == SegmentType.corner) return const Color(0xFF006B78);
    return const Color(0xFF2A2A3A);
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _ensureLoaded();
    final config = ref.watch(currentRooflineConfigProvider).valueOrNull;
    final staleness = ref.watch(pixelMapStalenessProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Refine Roofline', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: _dirty && !_busy ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: (config == null || _edited.isEmpty)
            ? const _EmptyRefine()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DesignPreview(frame: _frame(), height: 190),
                    const SizedBox(height: 12),
                    if (_edited.length > 1)
                      Wrap(spacing: 8, children: [
                        for (final ch in (_edited.keys.toList()..sort()))
                          ChoiceChip(
                            selected: ch == _activeChannel,
                            label: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text('Channel ${ch + 1}'),
                              if (staleness[ch] == true) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                              ],
                            ]),
                            onSelected: (_) async {
                              setState(() {
                                _activeChannel = ch;
                                _selectedFeature = null;
                              });
                              await _enterChannel(ch);
                            },
                          ),
                      ]),
                    const SizedBox(height: 8),
                    if (_activeChannel != null &&
                        staleness[_activeChannel] == true)
                      _StaleBanner(
                        onRescale: () => _rescale(_activeChannel!),
                        onWalk: () => context.push(AppRoutes.rooflineEditor),
                      ),
                    const SizedBox(height: 8),
                    if (_activeChannel != null) _featureList(_activeChannel!),
                    if (_selectedFeature != null) _nudgeControls(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _featureList(int ch) {
    final segs = _segs(ch);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Features — tap to spotlight & adjust',
            style: TextStyle(color: NexGenPalette.textMedium)),
        for (int i = 0; i < segs.length; i++)
          ListTile(
            dense: true,
            selected: i == _selectedFeature,
            selectedTileColor: NexGenPalette.cyan.withValues(alpha: 0.1),
            leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: _tint(segs[i]), shape: BoxShape.circle)),
            title: Text('${segs[i].name}  [${segs[i].startPixel}–${segs[i].endPixel}]',
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text('${segs[i].pixelCount} LEDs · ${segs[i].type.name}',
                style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 11)),
            onTap: () async {
              await _enterChannel(ch);
              _selectFeature(i);
            },
          ),
      ],
    );
  }

  Widget _nudgeControls() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Move boundaries', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _edgeRow('Start', BoundaryEdge.start),
          const SizedBox(height: 6),
          _edgeRow('End', BoundaryEdge.end),
        ],
      ),
    );
  }

  Widget _edgeRow(String label, BoundaryEdge edge) {
    return Row(children: [
      SizedBox(width: 48, child: Text(label, style: const TextStyle(color: NexGenPalette.textMedium))),
      _stepBtn('−5', () => _nudge(edge, -5)),
      _stepBtn('−1', () => _nudge(edge, -1)),
      const SizedBox(width: 8),
      _stepBtn('+1', () => _nudge(edge, 1)),
      _stepBtn('+5', () => _nudge(edge, 5)),
    ]);
  }

  Widget _stepBtn(String label, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 36), padding: EdgeInsets.zero),
          child: Text(label),
        ),
      );
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.onRescale, required this.onWalk});
  final VoidCallback onRescale;
  final VoidCallback onWalk;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber, color: Colors.orange, size: 18),
          SizedBox(width: 8),
          Expanded(child: Text('Your roofline changed on this channel.',
              style: TextStyle(color: Colors.white))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton(onPressed: onRescale, child: const Text('Rescale to fit')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onWalk, child: const Text('Walk it again')),
        ]),
      ]),
    );
  }
}

class _EmptyRefine extends StatelessWidget {
  const _EmptyRefine();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('No roofline map yet. Map your roofline first, then refine it here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NexGenPalette.textMedium)),
      ),
    );
  }
}
