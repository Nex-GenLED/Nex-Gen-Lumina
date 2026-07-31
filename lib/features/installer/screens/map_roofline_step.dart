import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/installer/installer_access_providers.dart';
import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_logic.dart';
import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_state.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/theme.dart';

/// Design Studio Slice 2 — "Map Roofline" installer wizard step.
///
/// The installer walks a channel with a single lit pixel and drops marks at
/// feature edges (corners / peak apexes / run splits); ranges between marks
/// auto-infer as runs. Compiles to the Slice 1 per-channel pixelMap. Always
/// SKIPPABLE — "Map later" never blocks the install. Writes go under the
/// current (staff) uid subtree exactly like controller docs (owner writes);
/// the handoff migration carries them to the customer.
class MapRooflineStep extends ConsumerStatefulWidget {
  const MapRooflineStep({super.key, required this.onBack, required this.onNext});

  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  ConsumerState<MapRooflineStep> createState() => _MapRooflineStepState();
}

class _MapRooflineStepState extends ConsumerState<MapRooflineStep> {
  int? _selectedChannel;
  int _cursor = 0; // channel-local pixel index
  Timer? _chaseTimer;
  int _chaseSpeedMs = 120; // default chase cadence — see bench notes
  bool _saving = false;

  /// Full device state captured when a channel walk begins, so the channel can
  /// be restored on exit (prior-state restore preferred over blanking).
  Map<String, dynamic>? _priorState;
  int? _walkingChannel;

  @override
  void dispose() {
    _chaseTimer?.cancel();
    // Best-effort restore of whatever channel we were lighting.
    _restorePrior();
    super.dispose();
  }

  List<DeviceChannel> get _channels => ref.read(deviceChannelsProvider);

  DeviceChannel? get _channel {
    final ch = _selectedChannel;
    if (ch == null) return null;
    for (final c in _channels) {
      if (c.id == ch) return c;
    }
    return null;
  }

  int _channelLen(DeviceChannel c) => (c.stop - c.start).clamp(0, 100000);

  // ── Spotlight / walk ────────────────────────────────────────────────────

  PerPixelWriter? get _writer {
    final repo = ref.read(wledRepositoryProvider);
    return repo is PerPixelWriter ? repo as PerPixelWriter : null;
  }

  Future<void> _beginWalk(int channelIndex) async {
    if (_walkingChannel == channelIndex) return;
    await _restorePrior();
    _walkingChannel = channelIndex;
    // Capture the channel's current state so we can restore on exit.
    try {
      _priorState = await ref.read(wledRepositoryProvider)?.getState();
    } catch (_) {
      _priorState = null;
    }
    await _spotlight(_cursor);
  }

  /// Lights exactly one LED (white) on the selected channel — the walk cursor.
  /// Uses segmentId == channelIndex (Lumina splits segments to match buses) so
  /// the local index addresses the channel directly. Previous pixel goes dark
  /// because each write replaces the segment's `i` frame (single lit pixel).
  Future<void> _spotlight(int local) async {
    final ch = _selectedChannel;
    final writer = _writer;
    if (ch == null || writer == null) return;
    await writer.applyPerPixel(
      segmentId: ch,
      spans: [PixelSpan.single(local, const [255, 255, 255, 0])],
    );
  }

  /// Restores the walked channel's prior state (re-applies its captured segment
  /// verbatim; the explicit `id` makes it pass channel-filtering untouched). If
  /// no prior state was captured, best-effort clears the `i` override by
  /// re-asserting the segment as a solid off frame.
  Future<void> _restorePrior() async {
    final walking = _walkingChannel;
    if (walking == null) return;
    _walkingChannel = null;
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;
    try {
      final prior = _priorState;
      Map<String, dynamic>? seg;
      if (prior != null && prior['seg'] is List) {
        for (final s in (prior['seg'] as List)) {
          if (s is Map && s['id'] == walking) {
            seg = Map<String, dynamic>.from(s);
            break;
          }
        }
      }
      if (seg != null) {
        await repo.applyJson({
          'seg': [
            {
              'id': walking,
              'on': seg['on'] ?? true,
              if (seg['fx'] != null) 'fx': seg['fx'],
              if (seg['sx'] != null) 'sx': seg['sx'],
              if (seg['ix'] != null) 'ix': seg['ix'],
              if (seg['col'] != null) 'col': seg['col'],
              // Clear the per-pixel override so the effect renders again.
              'i': const <dynamic>[],
            }
          ]
        });
      } else {
        // No capture → clear the override, leave the segment on.
        await repo.applyJson({
          'seg': [
            {'id': walking, 'on': true, 'fx': 0, 'i': const <dynamic>[]}
          ]
        });
      }
    } catch (_) {
      // Non-blocking — restore is best-effort.
    }
    _priorState = null;
  }

  void _toggleChase() {
    if (_chaseTimer != null) {
      _chaseTimer!.cancel();
      setState(() => _chaseTimer = null);
      return;
    }
    setState(() {
      _chaseTimer = Timer.periodic(Duration(milliseconds: _chaseSpeedMs), (_) {
        final c = _channel;
        if (c == null) return;
        final len = _channelLen(c);
        final next = (_cursor + 1) % (len == 0 ? 1 : len);
        setState(() => _cursor = next);
        _spotlight(next);
      });
    });
  }

  void _nudge(int delta) {
    final c = _channel;
    if (c == null) return;
    final len = _channelLen(c);
    final next = (_cursor + delta).clamp(0, (len - 1).clamp(0, len));
    setState(() => _cursor = next);
    _spotlight(next);
  }

  void _scrubTo(int local) {
    setState(() => _cursor = local);
    _spotlight(local);
  }

  // ── Marks ───────────────────────────────────────────────────────────────

  void _addMark(MarkKind kind, {SegmentType? customType, int slopeLength = 3}) {
    final ch = _selectedChannel;
    if (ch == null) return;
    ref.read(rooflineCaptureProvider.notifier).addMark(
          ch,
          CaptureMark(
            pixel: _cursor,
            kind: kind,
            slopeLength: slopeLength,
            customType: customType ?? SegmentType.run,
          ),
        );
    setState(() {});
  }

  Future<void> _symmetricPeakDialog() async {
    final ch = _selectedChannel;
    final c = _channel;
    if (ch == null || c == null) return;
    int slope = 6;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: NexGenPalette.gunmetal90,
          title: const Text('Symmetric peak',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Apex at LED $_cursor. Slope length (LEDs each side): $slope',
                  style: const TextStyle(color: NexGenPalette.textMedium)),
              Slider(
                value: slope.toDouble(),
                min: 1,
                max: 40,
                divisions: 39,
                label: '$slope',
                onChanged: (v) => setLocal(() => slope = v.round()),
              ),
              TextButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('Sweep preview'),
                onPressed: () => _sweepPreview(_cursor, slope),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Add peak')),
          ],
        ),
      ),
    );
    if (accepted == true) {
      _addMark(MarkKind.peak, slopeLength: slope);
    } else {
      _spotlight(_cursor); // restore single-pixel cursor after preview
    }
  }

  /// Sweeps the inferred peak range for visual confirmation, then returns the
  /// spotlight to the apex.
  Future<void> _sweepPreview(int apex, int slope) async {
    final c = _channel;
    if (c == null) return;
    final len = _channelLen(c);
    final start = (apex - slope).clamp(0, len - 1);
    final end = (apex + slope).clamp(0, len - 1);
    for (int p = start; p <= end; p++) {
      await _spotlight(p);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    await _spotlight(apex);
  }

  Future<void> _adjustMarkDialog(int index) async {
    final ch = _selectedChannel;
    final c = _channel;
    if (ch == null || c == null) return;
    final marks = ref.read(rooflineCaptureProvider).channelMarks(ch);
    if (index < 0 || index >= marks.length) return;
    var mark = marks[index];
    final len = _channelLen(c);
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: NexGenPalette.gunmetal90,
          title: Text('Adjust ${mark.kind.name} @ ${mark.pixel}',
              style: const TextStyle(color: Colors.white)),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final d in [-10, -1, 1, 10])
                OutlinedButton(
                  onPressed: () {
                    final np = (mark.pixel + d).clamp(0, len - 1);
                    mark = mark.copyWith(pixel: np);
                    ref
                        .read(rooflineCaptureProvider.notifier)
                        .updateMark(ch, index, mark);
                    _scrubTo(np); // spotlight jumps there — live feedback
                    setLocal(() {});
                    setState(() {});
                  },
                  child: Text(d > 0 ? '+$d' : '$d'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref.read(rooflineCaptureProvider.notifier).removeMark(ch, index);
                setState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
            FilledButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  // ── Copy across channels ────────────────────────────────────────────────

  Future<void> _copyToChannelDialog() async {
    final ch = _selectedChannel;
    final c = _channel;
    if (ch == null || c == null) return;
    final srcLen = _channelLen(c);
    final targets = _channels.where((t) => t.id != ch).toList();
    if (targets.isEmpty) return;
    final marks = ref.read(rooflineCaptureProvider).channelMarks(ch);
    if (marks.isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Copy map to…', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in targets)
              ListTile(
                title: Text(t.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  _channelLen(t) == srcLen
                      ? 'Exact length match (${_channelLen(t)} LEDs)'
                      : 'Different length (${_channelLen(t)} vs $srcLen) — copy then adjust',
                  style: TextStyle(
                    color: _channelLen(t) == srcLen
                        ? NexGenPalette.cyan
                        : NexGenPalette.textMedium,
                  ),
                ),
                onTap: () {
                  ref.read(rooflineCaptureProvider.notifier).setMarks(t.id, marks);
                  Navigator.pop(ctx);
                  setState(() {});
                },
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // ── Compile + save ──────────────────────────────────────────────────────

  /// Builds the aggregate config from every channel that has marks and writes
  /// it via the Slice 1 service (all channels at once, so saving one doesn't
  /// orphan another). source_pixel_count comes from bus.len; created_by = uid.
  /// Why the last [_saveMappedChannels] failed. Surfaced to the installer by
  /// [_onContinue] — F-5 was that this cause was discarded entirely.
  Object? _lastSaveError;

  Future<bool> _saveMappedChannels() async {
    final capture = ref.read(rooflineCaptureProvider);
    final channels = _channels;

    // Nothing captured → nothing can be lost. Checked BEFORE the uid/controller
    // guard so an installer who legitimately mapped nothing is never blocked by
    // the retry gate below.
    if (!channels.any((c) => capture.channelMarks(c.id).isNotEmpty)) return true;

    final uid = ref.read(effectiveUserUidProvider);
    final controllerId = ref.read(activePixelMapControllerIdProvider);
    if (uid == null || controllerId == null) {
      // Marks exist but there is nowhere to put them. Previously a silent
      // `false` that _onContinue discarded.
      _lastSaveError = StateError(
        uid == null
            ? 'no signed-in session to save under'
            : 'no controller selected for this capture',
      );
      debugPrint('MapRoofline: cannot save pixel map — $_lastSaveError');
      return false;
    }

    final segments = <RooflineSegment>[];
    final sourceCounts = <int, int>{};
    for (final c in channels) {
      sourceCounts[c.id] = _channelLen(c);
      final marks = capture.channelMarks(c.id);
      if (marks.isEmpty) continue;
      segments.addAll(compileMarksToChannelSegments(
        channelIndex: c.id,
        pixelCount: _channelLen(c),
        marks: marks,
      ));
    }
    if (segments.isEmpty) return true; // nothing mapped → nothing to write

    final config = RooflineConfiguration(
      id: controllerId,
      controllerId: controllerId,
      name: 'Roofline',
      segments: segments,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      totalChannelCount: channels.length,
    );

    setState(() => _saving = true);
    try {
      await ref.read(rooflineConfigServiceProvider).savePixelMap(
            uid,
            controllerId,
            config,
            sourceCounts: sourceCounts,
            createdBy: uid,
          );
      final notifier = ref.read(rooflineCaptureProvider.notifier);
      for (final c in channels) {
        if (capture.channelMarks(c.id).isNotEmpty) notifier.markSaved(c.id);
      }
      _lastSaveError = null;
      return true;
    } catch (e, st) {
      // F-5: was `catch (_) { return false; }` — the cause was destroyed and
      // the return value discarded, so a failed save looked exactly like a
      // successful one.
      _lastSaveError = e;
      debugPrint('MapRoofline: pixel-map save FAILED for '
          'uid=$uid controller=$controllerId: $e\n$st');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onContinue() async {
    await _restorePrior();
    // Auto-persist any mapped-but-unsaved channels so nothing is lost at
    // handoff; skipping (no marks) simply writes nothing.
    //
    // F-5 GATE: the wizard MUST NOT advance on an unacknowledged failure. A
    // pixel-walk is the most expensive thing an installer does on site, and a
    // dropped save is unrecoverable once they leave the property.
    //
    // NO "save offline and continue" OPTION — deliberately. Firestore's offline
    // queue would make this look survivable while relocating the silent failure
    // somewhere strictly worse:
    //   • the capture is written under the STAFF uid, and the very next wizard
    //     step migrates that path to the customer and DELETES the source. A
    //     write still pending at that moment is copied from cache, not from the
    //     server, so the customer can inherit a map the backend never stored.
    //   • if the app is killed or the installer signs out before the queue
    //     flushes, the capture is gone with no record anywhere.
    //   • the installer has already left the site by the time anyone could know.
    // A queued write we cannot guarantee reaches Firestore is not a save, so it
    // is not offered as one. Retry-on-site or explicitly "Map later" instead.
    while (true) {
      if (await _saveMappedChannels()) {
        widget.onNext();
        return;
      }
      if (!mounted) return;

      final retry = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Roofline map didn't save"),
          content: Text(
            'This roofline capture could NOT be saved '
            '(${_lastSaveError ?? 'unknown error'}).\n\n'
            'It is not stored anywhere yet — leaving this screen now would lose '
            'the whole pixel walk. Check your connection and tap Retry.\n\n'
            'If you need to move on, go back and choose "Map later" to record '
            'this controller as unmapped on purpose.',
          ),
          actions: [
            // 'Close', not 'Back' — the step already has its own Back button,
            // and two of them on screen at once is genuinely ambiguous.
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
      // 'Back' keeps the installer on this step with their marks intact — it
      // does NOT advance. Only an actual successful save calls onNext().
      if (retry != true) return;
    }
  }

  Future<void> _onMapLater() async {
    await _restorePrior();
    for (final c in _channels) {
      ref.read(rooflineCaptureProvider.notifier).markSkipped(c.id);
    }
    widget.onNext();
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final channels = _channels;
    final capture = ref.watch(rooflineCaptureProvider);
    final selectedIp = ref.watch(selectedDeviceIpProvider);
    final c = _channel;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Map Roofline',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Walk each channel with the lit pixel and mark corners, peaks, and '
            'run splits. Everything between marks becomes a run. Optional — you '
            'can map later.',
            style: TextStyle(color: NexGenPalette.textMedium),
          ),
          const SizedBox(height: 16),
          if (selectedIp == null)
            const _Warn('No controller connected — connect on the local '
                'network to walk the roofline, or map later.')
          else if (channels.isEmpty)
            const _Warn('No channels detected from the device hardware config.'),
          if (channels.isNotEmpty) ...[
            _ChannelChips(
              channels: channels,
              capture: capture,
              selected: _selectedChannel,
              onSelect: (id) async {
                setState(() {
                  _selectedChannel = id;
                  _cursor = 0;
                });
                await _beginWalk(id);
              },
            ),
            const SizedBox(height: 12),
            if (c != null)
              Expanded(child: _walkPanel(c, capture.channelMarks(c.id)))
            else
              const Expanded(
                child: Center(
                  child: Text('Select a channel to begin mapping',
                      style: TextStyle(color: NexGenPalette.textMedium)),
                ),
              ),
          ] else
            const Spacer(),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await _restorePrior();
                  widget.onBack();
                },
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back'),
              ),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : _onMapLater,
                child: const Text('Map later'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _onContinue,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Continue'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _walkPanel(DeviceChannel c, List<CaptureMark> marks) {
    final len = _channelLen(c);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${c.name} — $len LEDs',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          // Cursor + scrub.
          Row(
            children: [
              Text('LED $_cursor',
                  style: const TextStyle(color: NexGenPalette.cyan)),
              Expanded(
                child: Slider(
                  value: _cursor.toDouble().clamp(0, (len - 1).toDouble()),
                  min: 0,
                  max: (len - 1).clamp(1, len).toDouble(),
                  onChanged: (v) => _scrubTo(v.round()),
                ),
              ),
            ],
          ),
          // Chase + nudge controls.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _toggleChase,
                icon: Icon(_chaseTimer == null ? Icons.play_arrow : Icons.pause,
                    size: 18),
                label: Text(_chaseTimer == null ? 'Chase' : 'Pause'),
              ),
              OutlinedButton(onPressed: () => _nudge(-10), child: const Text('−10')),
              OutlinedButton(onPressed: () => _nudge(-1), child: const Text('−1')),
              OutlinedButton(onPressed: () => _nudge(1), child: const Text('+1')),
              OutlinedButton(onPressed: () => _nudge(10), child: const Text('+10')),
            ],
          ),
          const SizedBox(height: 6),
          // Speed.
          Row(
            children: [
              const Text('Speed', style: TextStyle(color: NexGenPalette.textMedium)),
              Expanded(
                child: Slider(
                  value: _chaseSpeedMs.toDouble(),
                  min: 40,
                  max: 400,
                  divisions: 9,
                  label: '${_chaseSpeedMs}ms',
                  onChanged: (v) => setState(() => _chaseSpeedMs = v.round()),
                ),
              ),
            ],
          ),
          const Divider(color: NexGenPalette.line),
          const Text('Mark at cursor',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _addMark(MarkKind.corner),
                icon: const Icon(Icons.turn_right, size: 18),
                label: const Text('Corner'),
              ),
              FilledButton.icon(
                onPressed: _symmetricPeakDialog,
                icon: const Icon(Icons.change_history, size: 18),
                label: const Text('Peak'),
              ),
              OutlinedButton.icon(
                onPressed: () => _addMark(MarkKind.runBoundary),
                icon: const Icon(Icons.linear_scale, size: 18),
                label: const Text('Run split'),
              ),
              OutlinedButton.icon(
                onPressed: () => _addMark(MarkKind.custom, customType: SegmentType.column),
                icon: const Icon(Icons.view_column, size: 18),
                label: const Text('Column'),
              ),
              if (marks.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    ref.read(rooflineCaptureProvider.notifier).undoLast(c.id);
                    setState(() {});
                  },
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Undo'),
                ),
              if (marks.isNotEmpty)
                TextButton.icon(
                  onPressed: _copyToChannelDialog,
                  icon: const Icon(Icons.copy_all, size: 18),
                  label: const Text('Copy to…'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (marks.isNotEmpty) ...[
            Text('${marks.length} mark(s) — tap to adjust',
                style: const TextStyle(color: NexGenPalette.textMedium)),
            for (int i = 0; i < marks.length; i++)
              ListTile(
                dense: true,
                leading: Icon(_iconFor(marks[i].kind),
                    color: NexGenPalette.cyan, size: 18),
                title: Text('${_labelFor(marks[i].kind)} @ LED ${marks[i].pixel}',
                    style: const TextStyle(color: Colors.white)),
                onTap: () => _adjustMarkDialog(i),
              ),
            const SizedBox(height: 8),
            // Preview of the inferred feature list.
            _FeaturePreview(
              segments: compileMarksToChannelSegments(
                channelIndex: c.id,
                pixelCount: len,
                marks: marks,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconFor(MarkKind k) {
    switch (k) {
      case MarkKind.corner:
        return Icons.turn_right;
      case MarkKind.peak:
        return Icons.change_history;
      case MarkKind.runBoundary:
        return Icons.linear_scale;
      case MarkKind.custom:
        return Icons.view_column;
    }
  }

  String _labelFor(MarkKind k) {
    switch (k) {
      case MarkKind.corner:
        return 'Corner';
      case MarkKind.peak:
        return 'Peak';
      case MarkKind.runBoundary:
        return 'Run split';
      case MarkKind.custom:
        return 'Custom';
    }
  }
}

/// Convenience accessor for a channel's marks off the capture map.
extension _CaptureRead on Map<int, ChannelCaptureState> {
  List<CaptureMark> channelMarks(int channelIndex) =>
      this[channelIndex]?.marks ?? const [];
}

class _ChannelChips extends StatelessWidget {
  const _ChannelChips({
    required this.channels,
    required this.capture,
    required this.selected,
    required this.onSelect,
  });

  final List<DeviceChannel> channels;
  final Map<int, ChannelCaptureState> capture;
  final int? selected;
  final void Function(int id) onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in channels)
          ChoiceChip(
            selected: c.id == selected,
            onSelected: (_) => onSelect(c.id),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.name),
                const SizedBox(width: 6),
                _badge(capture[c.id]),
              ],
            ),
          ),
      ],
    );
  }

  Widget _badge(ChannelCaptureState? s) {
    if (s == null) return const SizedBox.shrink();
    if (s.saved) {
      return const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16);
    }
    if (s.skipped) {
      return const Icon(Icons.remove_circle_outline,
          color: NexGenPalette.textMedium, size: 16);
    }
    if (s.hasMarks) {
      return const Icon(Icons.edit, color: NexGenPalette.cyan, size: 16);
    }
    return const SizedBox.shrink();
  }
}

class _FeaturePreview extends StatelessWidget {
  const _FeaturePreview({required this.segments});
  final List<RooflineSegment> segments;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Inferred features',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
          const SizedBox(height: 6),
          for (final s in segments)
            Text(
              '• ${s.name}  [${s.startPixel}–${s.endPixel}]  ${s.type.name}'
              '${s.direction == SegmentDirection.upward ? ' ↑' : s.direction == SegmentDirection.downward ? ' ↓' : ''}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _Warn extends StatelessWidget {
  const _Warn(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: NexGenPalette.textMedium))),
        ],
      ),
    );
  }
}
