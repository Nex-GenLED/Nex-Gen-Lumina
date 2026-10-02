import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_feature_marking.dart';
import 'package:nexgen_command/features/design/roofline_segmentation.dart';
import 'package:nexgen_command/features/design/roofline_target_bar.dart';
import 'package:nexgen_command/features/design/roofline_walkthrough_widgets.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_logic.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/wled/device_write_reporter.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/theme.dart';

/// Opens the feature walkthrough. Returns when the customer leaves it.
Future<void> openRooflineFeatureWalkthrough(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const RooflineFeatureWalkthroughScreen(),
    ),
  );
}

/// Customer-facing walkthrough that marks the roofline's corners, peaks and
/// runs (+110, owner request 2026-09-29).
///
/// The installer normally does this during install (the Map Roofline step).
/// When it has not been done, the customer finishes it here: one LED lights
/// up on the house, they walk it along each channel, and tap what it is
/// sitting on — a corner, a peak, or the start of a new run. Everything
/// between marks becomes a run. Each channel is saved as confirmed features,
/// which is what Design Studio uses as its selection unit.
class RooflineFeatureWalkthroughScreen extends ConsumerStatefulWidget {
  const RooflineFeatureWalkthroughScreen({super.key});

  @override
  ConsumerState<RooflineFeatureWalkthroughScreen> createState() =>
      _RooflineFeatureWalkthroughScreenState();
}

class _RooflineFeatureWalkthroughScreenState
    extends ConsumerState<RooflineFeatureWalkthroughScreen> {
  static const _dim = [20, 20, 26, 0];
  static const _markColor = [255, 160, 0, 0];
  static const _cursorColor = [0, 229, 255, 0];

  bool _loaded = false;
  bool _saving = false;
  String? _loadProblem;
  RooflineConfiguration? _config;
  final Map<int, List<CaptureMark>> _marks = {};

  /// Per channel, the mark lists before each change this visit, for Undo.
  final Map<int, List<List<CaptureMark>>> _history = {};
  final Set<int> _savedChannels = {};
  int? _channel;
  int _cursor = 0;

  // Live lighting on the controller being marked.
  final _reporter = DeviceWriteReporter(what: 'walkthrough light');
  Timer? _throttle;
  Map<String, dynamic>? _priorState;
  int? _litChannel;
  WledRepository? _litRepo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _throttle?.cancel();
    unawaited(_restorePrior());
    super.dispose();
  }

  Future<void> _load() async {
    await _restorePrior();
    final notifier = ref.read(rooflineConfigEditorProvider.notifier);
    await notifier.initialize();
    if (!mounted) return;
    final config = ref.read(rooflineConfigEditorProvider);
    setState(() {
      _loadProblem = notifier.loadProblem;
      _config = config;
      _marks.clear();
      _history.clear();
      _savedChannels.clear();
      final channels = config?.allChannelIndices ?? const <int>[];
      for (final ch in channels) {
        _marks[ch] = marksFromChannelSegments(config!.segmentsForChannel(ch));
      }
      _channel = channels.isEmpty ? null : channels.first;
      _cursor = 0;
      _loaded = true;
    });
    unawaited(_enterChannel());
  }

  ControllerInfo? get _target => ref.read(rooflineEditTargetProvider).value;

  int? _liveLength(int ch) {
    final target = _target;
    if (target == null || target.ip != ref.read(selectedDeviceIpProvider)) {
      return null;
    }
    for (final c in ref.read(deviceChannelsProvider)) {
      if (c.id == ch) return c.stop - c.start;
    }
    return null;
  }

  int _length(int ch) => _config == null
      ? 0
      : channelLengthForMarking(_config!, ch, liveLength: _liveLength(ch));

  List<CaptureMark> get _channelMarks => _marks[_channel] ?? const [];

  // ── Lighting ────────────────────────────────────────────────────────────

  WledRepository? _repo() {
    final target = _target;
    if (target == null || target.ip.isEmpty) return null;
    return ref.read(controllerRepositoryProvider(ControllerTarget(
        ip: target.ip, controllerId: target.id, name: target.name)));
  }

  Future<void> _enterChannel() async {
    final ch = _channel;
    if (ch == null) return;
    if (_litChannel != ch) {
      await _restorePrior();
      final repo = _repo();
      if (repo == null) return;
      _litChannel = ch;
      // Kept so the restore on dispose needs no `ref` (not allowed there).
      _litRepo = repo;
      try {
        _priorState = await repo.getState();
      } catch (_) {
        _priorState = null;
      }
    }
    _spotlight();
  }

  void _spotlight() {
    _throttle?.cancel();
    _throttle = Timer(const Duration(milliseconds: 150), () async {
      final ch = _channel;
      final repo = _repo();
      if (ch == null || repo is! PerPixelWriter) return;
      final len = _length(ch);
      if (len <= 0) return;
      final ok = await (repo as PerPixelWriter).applyPerPixel(
        segmentId: ch,
        spans: [
          PixelSpan(start: 0, end: len - 1, color: _dim),
          for (final m in _channelMarks)
            if (m.pixel < len) PixelSpan.single(m.pixel, _markColor),
          PixelSpan.single(_cursor.clamp(0, len - 1), _cursorColor),
        ],
      );
      if (mounted) _reporter.report(context, ok);
    });
  }

  /// Puts the lit channel back the way it was.
  Future<void> _restorePrior() async {
    final lit = _litChannel;
    final repo = _litRepo;
    if (lit == null || repo == null) return;
    _litChannel = null;
    _litRepo = null;
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

  // ── Marking ─────────────────────────────────────────────────────────────

  void _moveCursor(int to) {
    final ch = _channel;
    if (ch == null) return;
    final len = _length(ch);
    if (len <= 0) return;
    setState(() => _cursor = to.clamp(0, len - 1));
    _spotlight();
  }

  /// Replaces the channel's marks, remembering the previous list for Undo.
  void _setMarks(int ch, List<CaptureMark> marks) {
    setState(() {
      (_history[ch] ??= []).add(_channelMarks);
      _marks[ch] = marks;
      _savedChannels.remove(ch);
    });
    _spotlight();
  }

  /// Places a mark at the cursor. One light carries one mark, so the same
  /// mark twice changes nothing ([placeMark]).
  void _addMark(MarkKind kind) {
    final ch = _channel;
    if (ch == null) return;
    final placed = placeMark(_channelMarks, CaptureMark(pixel: _cursor, kind: kind));
    if (identical(placed, _channelMarks)) return;
    _setMarks(ch, placed);
  }

  void _removeMark(int index) {
    final ch = _channel;
    if (ch == null) return;
    _setMarks(ch, [..._channelMarks]..removeAt(index));
  }

  bool get _canUndo => (_history[_channel]?.isNotEmpty ?? false);

  void _undo() {
    final ch = _channel;
    final stack = _history[ch];
    if (ch == null || stack == null || stack.isEmpty) return;
    setState(() {
      _marks[ch] = stack.removeLast();
      _savedChannels.remove(ch);
    });
    _spotlight();
  }

  /// Deletes a compiled section by removing the mark that made it, so its
  /// lights merge into the neighbouring section.
  void _mergeSection(RooflineSegment section) {
    final ch = _channel;
    if (ch == null) return;
    final plan = planSectionRemoval(
      channelIndex: ch,
      pixelCount: _length(ch),
      marks: _channelMarks,
      section: section,
    );
    if (plan == null) return;
    _setMarks(ch, plan.marksAfter);
  }

  /// Whether "Start over" has anything to do on the current channel.
  bool get _canStartOver {
    final ch = _channel;
    final config = _config;
    if (ch == null || config == null) return false;
    return _channelMarks.isNotEmpty || config.segmentsForChannel(ch).length > 1;
  }

  Future<void> _startOver() async {
    final ch = _channel;
    if (ch == null) return;
    final len = _length(ch);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: Text('Start over on channel ${ch + 1}?',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          startOverDescription(
            channelNumber: ch + 1,
            lights: len,
            marks: marksSummary(_channelMarks),
          ),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('walkthrough-start-over-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Start over'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _setMarks(ch, const []);
  }

  Future<void> _selectChannel(int ch) async {
    setState(() {
      _channel = ch;
      _cursor = 0;
    });
    await _enterChannel();
  }

  Future<void> _saveChannel() async {
    final ch = _channel;
    final config = _config;
    if (ch == null || config == null || _saving) return;
    final len = _length(ch);
    if (len <= 0) return;
    setState(() => _saving = true);

    final features = applyFeatureMarksToChannel(
      channelIndex: ch,
      pixelCount: len,
      existing: config.segmentsForChannel(ch),
      marks: _channelMarks,
    );
    final updated = replaceChannelSegments(config, ch, features);
    final notifier = ref.read(rooflineConfigEditorProvider.notifier);
    notifier.loadConfiguration(updated);
    final ok = await notifier.save();
    if (!mounted) return;

    if (!ok) {
      notifier.loadConfiguration(config);
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(notifier.lastSaveMessage ??
            "Channel ${ch + 1} didn't save. Try again."),
        backgroundColor: Colors.red,
      ));
      return;
    }

    final channels = updated.allChannelIndices;
    final nextUnsaved = channels.firstWhere(
      (c) => c != ch && !_savedChannels.contains(c) && !_isMarked(updated, c),
      orElse: () => -1,
    );
    setState(() {
      _config = updated;
      _savedChannels.add(ch);
      _saving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Channel ${ch + 1} saved with '
          '${features.length} section${features.length == 1 ? '' : 's'}.'),
      backgroundColor: Colors.green,
    ));
    if (nextUnsaved >= 0) await _selectChannel(nextUnsaved);
  }

  bool _isMarked(RooflineConfiguration config, int ch) =>
      isChannelFeatureMarked(config.segmentsForChannel(ch));

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final segmentation = assessRooflineSegmentation(config);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Mark Your Roofline'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RooflineTargetBar(
                verb: 'Marking',
                enabled: !_saving,
                onChanged: (_) {
                  setState(() => _loaded = false);
                  _load();
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'One light is lit on your house. Move it along your '
                  'roofline and tap what it is sitting on: a corner, a peak, '
                  'or the start of a new run. Everything between your marks '
                  'is a run.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: NexGenPalette.textMedium),
                ),
              ),
              const SizedBox(height: 12),
              if (!_loaded)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (config == null || config.segments.isEmpty)
                _Notice(
                  text: _loadProblem ??
                      "Your roofline hasn't been set up yet. Trace it on "
                          'your house photo first, or ask your installer.',
                )
              else ...[
                if (_repo() is! PerPixelWriter)
                  const _Notice(
                    text: "Your lights can't be lit from here right now "
                        '(you may be away from home). You can still mark by '
                        'LED number.',
                  ),
                _buildChannelChips(config),
                if (_channel != null) _buildMarker(_channel!),
                if (segmentation.isSegmented)
                  const _Notice(
                    icon: Icons.check_circle,
                    color: NexGenPalette.cyan,
                    text: 'Every channel is marked. Design Studio can now '
                        'select your corners, peaks and runs.',
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton(
                    key: const ValueKey('walkthrough-done'),
                    onPressed:
                        _saving ? null : () => Navigator.of(context).maybePop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChannelChips(RooflineConfiguration config) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final ch in config.allChannelIndices)
            ChoiceChip(
              key: ValueKey('walkthrough-channel-$ch'),
              selected: ch == _channel,
              avatar: _isMarked(config, ch)
                  ? const Icon(Icons.check, size: 16)
                  : null,
              label: Text('Channel ${ch + 1}'),
              onSelected: _saving ? null : (_) => _selectChannel(ch),
            ),
        ],
      ),
    );
  }

  Widget _buildMarker(int ch) {
    final len = _length(ch);
    final marks = _channelMarks;
    final preview = len <= 0
        ? const <RooflineSegment>[]
        : compileMarksToChannelSegments(
            channelIndex: ch, pixelCount: len, marks: marks);
    final saved = _savedChannels.contains(ch);
    final mapped = _config == null ? 0 : mappedLengthOfChannel(_config!, ch);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Channel ${ch + 1}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            len <= 0
                ? 'This channel has no lights mapped yet.'
                : 'Light ${_cursor + 1} of $len',
            key: const ValueKey('walkthrough-cursor'),
            style: const TextStyle(color: NexGenPalette.textMedium),
          ),
          if (len > 0 && mapped > 0 && mapped != len)
            ChannelLengthNotice(
                channelNumber: ch + 1, mapped: mapped, strip: len),
          if (len > 1)
            Slider(
              value: _cursor.toDouble().clamp(0, (len - 1).toDouble()),
              min: 0,
              max: (len - 1).toDouble(),
              divisions: len - 1,
              label: '${_cursor + 1}',
              onChanged: (v) => _moveCursor(v.round()),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final step in const [-10, -1, 1, 10])
                OutlinedButton(
                  key: ValueKey('walkthrough-step-$step'),
                  onPressed: len > 0 ? () => _moveCursor(_cursor + step) : null,
                  child: Text(step > 0 ? '+$step' : '$step'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('This light is on…',
              style: TextStyle(color: Colors.white)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('walkthrough-mark-corner'),
                onPressed: len > 0 && !_saving
                    ? () => _addMark(MarkKind.corner)
                    : null,
                icon: const Icon(Icons.turn_right),
                label: const Text('A corner'),
              ),
              FilledButton.icon(
                key: const ValueKey('walkthrough-mark-peak'),
                onPressed:
                    len > 0 && !_saving ? () => _addMark(MarkKind.peak) : null,
                icon: const Icon(Icons.change_history),
                label: const Text('A peak'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('walkthrough-mark-run'),
                onPressed: len > 0 && !_saving
                    ? () => _addMark(MarkKind.runBoundary)
                    : null,
                icon: const Icon(Icons.straighten),
                label: const Text('The start of a new run'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          WalkthroughMarkActions(
            onUndo: _canUndo && !_saving ? _undo : null,
            onStartOver: _canStartOver && !_saving ? _startOver : null,
            disabledReason: len <= 0
                ? null
                : 'No marks on this channel yet — it is one straight run.',
          ),
          if (marks.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Your marks', style: TextStyle(color: Colors.white)),
            for (var i = 0; i < marks.length; i++)
              // A ListTile paints its ink on the nearest Material; inside this
              // coloured card that Material is behind the card, so Flutter
              // 3.47 asserts in debug builds. A transparent Material of its
              // own keeps the card's look and gives the tile a surface.
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${_markLabel(marks[i].kind)} at light '
                      '${marks[i].pixel + 1}'),
                  trailing: IconButton(
                    tooltip: 'Remove this mark',
                    icon: const Icon(Icons.close),
                    onPressed: _saving ? null : () => _removeMark(i),
                  ),
                  onTap: () => _moveCursor(marks[i].pixel),
                ),
              ),
          ],
          const SizedBox(height: 8),
          if (preview.isNotEmpty) ...[
            Text(
              'This channel will have: ${_summary(preview)}',
              style: const TextStyle(color: NexGenPalette.textMedium),
            ),
            // Every section with its own delete: the section's lights merge
            // back into the section next to it. A section that no single
            // mark removal can merge says why on its row instead of showing
            // a grey button.
            for (final f in preview)
              Builder(builder: (context) {
                final blocker = sectionRemovalBlocker(
                  channelIndex: ch,
                  pixelCount: len,
                  marks: marks,
                  section: f,
                );
                return RooflineSectionRow(
                  key: ValueKey('walkthrough-section-${f.startPixel}'),
                  label: _sectionLabel(f),
                  lights: _lightsLabel(f),
                  blocker: blocker,
                  onMerge: blocker == null && !_saving
                      ? () => _mergeSection(f)
                      : null,
                  onTap: () => _moveCursor(f.startPixel),
                );
              }),
          ],
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('walkthrough-save-channel'),
            onPressed: len > 0 && !_saving ? _saveChannel : null,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(saved
                    ? 'Channel ${ch + 1} saved'
                    : marks.isEmpty
                        ? 'Save — this channel is one straight run'
                        : 'Save channel ${ch + 1}'),
          ),
        ],
      ),
    );
  }

  static String _markLabel(MarkKind kind) {
    switch (kind) {
      case MarkKind.corner:
        return 'Corner';
      case MarkKind.peak:
        return 'Peak';
      case MarkKind.runBoundary:
        return 'New run';
      case MarkKind.custom:
        return 'Feature';
    }
  }

  static String _sectionLabel(RooflineSegment f) {
    final kind = featureKindOf(f);
    final base = switch (kind) {
      RooflineFeatureKind.run => 'Run',
      RooflineFeatureKind.corner => 'Corner',
      RooflineFeatureKind.peak => switch (f.direction) {
          SegmentDirection.upward => 'Peak, up slope',
          SegmentDirection.downward => 'Peak, down slope',
          _ => 'Peak',
        },
      RooflineFeatureKind.column => 'Column',
      RooflineFeatureKind.connector => 'Connector',
    };
    // Runs are auto-numbered by the compiler ("Run 2"); keep that.
    return kind == RooflineFeatureKind.run && f.name.startsWith('Run')
        ? f.name
        : base;
  }

  /// 1-indexed for the customer; stored values stay 0-based.
  static String _lightsLabel(RooflineSegment f) => f.pixelCount == 1
      ? 'light ${f.startPixel + 1}'
      : 'lights ${f.startPixel + 1}–${f.startPixel + f.pixelCount}';

  static String _summary(List<RooflineSegment> features) {
    final counts = <String, int>{};
    for (final f in features) {
      final kind = featureKindOf(f);
      final label = switch (kind) {
        RooflineFeatureKind.run => 'run',
        RooflineFeatureKind.corner => 'corner',
        RooflineFeatureKind.peak => 'peak section',
        RooflineFeatureKind.column => 'column',
        RooflineFeatureKind.connector => 'connector',
      };
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => '${e.value} ${e.key}${e.value == 1 ? '' : 's'}')
        .join(', ');
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    this.icon = Icons.info_outline,
    this.color = Colors.amber,
  });

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
