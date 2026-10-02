import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_feature_walkthrough.dart';
import 'package:nexgen_command/features/design/roofline_segmentation.dart';
import 'package:nexgen_command/features/design/roofline_target_bar.dart';
import 'package:nexgen_command/features/design/roofline_trace_merge.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/services/roofline_auto_detect_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/roofline_editor.dart';

/// Full-page screen for tracing roofline segments on a house image.
///
/// Supports multi-segment tracing with per-segment channel assignment,
/// story level, and label. Each segment is rendered in its channel color.
///
/// +110: loads and saves the controller named in [RooflineTargetBar]
/// (row 70), merges the trace into the stored map instead of replacing it
/// (row 71), writes the photo outline only after the map has saved (row
/// 164), and offers the feature walkthrough when the roofline's corners and
/// peaks have not been marked.
class RooflineEditorScreen extends ConsumerStatefulWidget {
  const RooflineEditorScreen({super.key});

  @override
  ConsumerState<RooflineEditorScreen> createState() => _RooflineEditorScreenState();
}

class _RooflineEditorScreenState extends ConsumerState<RooflineEditorScreen> {
  GlobalKey<RooflineEditorState> _editorKey = GlobalKey();
  bool _isSaving = false;
  bool _isDetecting = false;
  bool _segmentPanelExpanded = false;
  List<RooflineSegment> _currentSegments = [];
  int _totalChannelCount = 1;

  /// The editor's selected segment, reported by [RooflineEditor]. The toolbar
  /// used to read it off the editor's state while building, which is null on
  /// the first frame and never refreshed by a selection, so Delete stayed
  /// grey (+113, tester report).
  int? _activeIndex;

  /// The stored map this trace started from, and which of its segments the
  /// editor was shown (the ones with photo points).
  bool _loaded = false;
  RooflineConfiguration? _stored;
  List<RooflineSegment> _initialSegments = const [];
  Set<String> _shownIds = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final notifier = ref.read(rooflineConfigEditorProvider.notifier);
    await notifier.initialize();
    if (!mounted) return;
    final stored = ref.read(rooflineConfigEditorProvider);
    final initial =
        stored?.segments.where((s) => s.points.isNotEmpty).toList() ?? const [];
    setState(() {
      _stored = stored;
      _initialSegments = initial;
      _shownIds = {for (final s in initial) s.id};
      _currentSegments = List.of(initial);
      _totalChannelCount = (stored?.effectiveTotalChannelCount ?? 1)
          .clamp(1, 8)
          .toInt();
      _editorKey = GlobalKey();
      _activeIndex = null; // the new editor reports its own after its first frame
      _loaded = true;
    });
  }

  /// Stored sections the trace cannot show: they have no photo outline (the
  /// installer's walk, or a walkthrough section over lights that were never
  /// traced). They are kept on save and edited in Mark Your Roofline.
  int get _hiddenSectionCount =>
      _stored?.segments.where((s) => s.points.isEmpty).length ?? 0;

  /// Why Delete is disabled right now.
  String get _deleteDisabledReason {
    if (_currentSegments.isEmpty) {
      final hidden = _hiddenSectionCount;
      if (hidden > 0) {
        return 'This map\'s $hidden section${hidden == 1 ? '' : 's'} have no '
            'outline on the photo, so there is nothing to select here. '
            'Remove or merge them in Mark Your Roofline.';
      }
      return 'Nothing to delete yet. Trace a segment first.';
    }
    return 'Tap a segment on the photo or in the list to select it, then '
        'Delete removes that one.';
  }

  Future<void> _onTargetChanged(ControllerInfo picked) async {
    setState(() => _loaded = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = ref.watch(houseImageUrlProvider);
    final useStock = ref.watch(useStockImageProvider);
    final existingMask = ref.watch(rooflineMaskProvider);

    // Determine image
    ImageProvider imageProvider;
    if (imageUrl != null && !useStock) {
      imageProvider = NetworkImage(imageUrl);
    } else {
      imageProvider = const AssetImage('assets/images/Demohomephoto.jpg');
    }

    final activeIdx = _activeIndex;
    final activeSeg = activeIdx != null && activeIdx < _currentSegments.length
        ? _currentSegments[activeIdx]
        : null;
    final segmentation = assessRooflineSegmentation(_stored);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => context.pop(),
        ),
        title: const Text('Trace Roofline'),
        actions: [
          // Design Studio Slice 5 — jump to customer boundary refine.
          if (_currentSegments.isNotEmpty)
            IconButton(
              tooltip: 'Refine',
              onPressed: () => context.push(AppRoutes.rooflineRefine),
              icon: const Icon(Icons.tune),
            ),
          if (_currentSegments.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              onPressed: () => _editorKey.currentState?.clear(),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      // The canvas takes the middle; the controls above and below it each
      // scroll within at most 30% of the height, so large text never
      // squeezes the canvas to nothing or pushes Finish off-screen. (The
      // whole page does not scroll: dragging points on the canvas would
      // scroll it instead.)
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final chromeMax = constraints.maxHeight * 0.3;
          return Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: chromeMax),
              child: SingleChildScrollView(
                child: Column(children: [
            RooflineTargetBar(
              enabled: !_isSaving,
              onChanged: _onTargetChanged,
            ),
            // Instructions
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: NexGenPalette.cyan, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap along each roofline section. Use "+ New Segment" for '
                      'separate runs (garage, second story, etc).',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: NexGenPalette.textMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_loaded && segmentation.hasMap)
              _FeatureStatusBanner(
                segmentation: segmentation,
                onMark: _openWalkthrough,
              ),
                ]),
              ),
            ),

            // Editor canvas
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: !_loaded
                    ? const Center(child: CircularProgressIndicator())
                    : RooflineEditor(
                        key: _editorKey,
                        imageProvider: imageProvider,
                        initialMask:
                            _initialSegments.isEmpty ? existingMask : null,
                        initialSegments: _initialSegments,
                        onSegmentsChanged: (segments) {
                          setState(() => _currentSegments = segments);
                        },
                        onActiveSegmentChanged: (index) {
                          if (mounted && index != _activeIndex) {
                            setState(() => _activeIndex = index);
                          }
                        },
                      ),
              ),
            ),

            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: chromeMax),
              child: SingleChildScrollView(
                child: Column(children: [
            // Active segment info bar
            if (activeSeg != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: activeSeg.channelDisplayColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: activeSeg.channelDisplayColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: activeSeg.channelDisplayColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(
                      activeSeg.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
                    ),
                    _ChannelBadge(channelIndex: activeSeg.channelIndex),
                    Text(
                      '${activeSeg.points.length} pts'
                      '${activeSeg.level > 1 ? ' · L${activeSeg.level}' : ''}',
                      style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                    ),
                  ],
                ),
              ),

            // Segment panel (collapsible)
            if (_segmentPanelExpanded) _buildSegmentPanel(),

            // Toolbar
            _buildToolbar(),

            const SizedBox(height: 8),
                ]),
              ),
            ),
          ],
          );
        }),
      ),
    );
  }

  Widget _buildToolbar() {
    final target = ref.watch(rooflineEditTargetProvider);
    final canFinish = _loaded &&
        target.hasSelection &&
        _currentSegments.any((s) => s.points.length >= 2) &&
        !_isSaving;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Primary actions
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ToolbarButton(
                icon: Icons.add,
                label: 'New Segment',
                onTap: _loaded ? _showNewSegmentDialog : null,
                color: NexGenPalette.cyan,
              ),
              _ToolbarButton(
                icon: Icons.undo,
                label: 'Undo',
                onTap: _activeIndex != null &&
                        _activeIndex! < _currentSegments.length &&
                        _currentSegments[_activeIndex!].points.isNotEmpty
                    ? () => _editorKey.currentState?.undo()
                    : null,
                disabledReason: 'Undo removes the last point of the selected '
                    'segment. Select a segment that has points first.',
              ),
              _ToolbarButton(
                key: const ValueKey('trace-delete'),
                icon: Icons.delete_outline,
                label: 'Delete',
                onTap: _activeIndex != null ? _deleteActiveSegment : null,
                disabledReason: _deleteDisabledReason,
                color: Colors.redAccent,
              ),
              _ToolbarButton(
                icon: _segmentPanelExpanded ? Icons.expand_less : Icons.list,
                label: '${_currentSegments.length} segments',
                onTap: () => setState(() => _segmentPanelExpanded = !_segmentPanelExpanded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Save / secondary actions
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _isSaving || _isDetecting || !_loaded
                    ? null
                    : _autoDetectRoofline,
                icon: _isDetecting
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: NexGenPalette.cyan),
                      )
                    : const Icon(Icons.auto_fix_high, size: 18),
                label: Text(_isDetecting ? 'Detecting...' : 'Auto-Detect'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: NexGenPalette.cyan,
                  side: const BorderSide(color: NexGenPalette.cyan),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              FilledButton.icon(
                key: const ValueKey('trace-finish'),
                onPressed: canFinish ? _saveRoofline : null,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.check),
                label: Text(_isSaving ? 'Saving...' : 'Finish'),
                style: FilledButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: NexGenPalette.gunmetal50,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: _currentSegments.isEmpty
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                  _hiddenSectionCount > 0
                      ? 'No outlines to show. $_hiddenSectionCount '
                          'section${_hiddenSectionCount == 1 ? '' : 's'} '
                          'from Mark Your Roofline have no photo outline and '
                          'are kept as they are. Tap on the photo to trace.'
                      : 'No segments yet. Tap on the photo to start tracing.',
                  style: const TextStyle(color: NexGenPalette.textMedium)),
            )
          : ReorderableListView.builder(
              shrinkWrap: true,
              footer: _hiddenSectionCount > 0
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text(
                        '$_hiddenSectionCount more section'
                        '${_hiddenSectionCount == 1 ? '' : 's'} from Mark Your '
                        'Roofline have no photo outline and are not shown here.',
                        style: const TextStyle(
                            color: NexGenPalette.textMedium, fontSize: 11),
                      ),
                    )
                  : null,
              buildDefaultDragHandles: false,
              itemCount: _currentSegments.length,
              onReorder: (old, newIdx) {
                _editorKey.currentState?.reorderSegment(old, newIdx);
              },
              itemBuilder: (context, index) {
                final seg = _currentSegments[index];
                final isActive = index == _activeIndex;
                // A ListTile paints its ink and selected tint on the nearest
                // Material; inside this coloured panel that Material is behind
                // the panel, so Flutter 3.47 asserts in debug builds (the same
                // class 7b7dc79 fixed in the walkthrough). A transparent
                // Material of its own keeps the panel's look.
                return Material(
                  key: ValueKey(seg.id),
                  type: MaterialType.transparency,
                  child: ListTile(
                  dense: true,
                  selected: isActive,
                  selectedTileColor: seg.channelDisplayColor.withValues(alpha: 0.08),
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle, color: NexGenPalette.textMedium, size: 20),
                  ),
                  title: Text(
                    seg.name,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _ChannelBadge(channelIndex: seg.channelIndex),
                      Text('${seg.points.length} pts',
                          style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 11)),
                    ],
                  ),
                  onTap: () => _editorKey.currentState?.selectSegment(index),
                  ),
                );
              },
            ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _openWalkthrough() async {
    await openRooflineFeatureWalkthrough(context);
    if (!mounted) return;
    // The walkthrough saves; reload so this screen shows the marked map.
    setState(() => _loaded = false);
    await _load();
  }

  void _showNewSegmentDialog() {
    String label = '';
    int channelIndex = 0;
    int storyLevel = 1;

    // Auto-suggest label based on segment count
    final count = _currentSegments.length;
    final suggestions = ['Front Eave', 'Garage', 'Left Rake', 'Right Rake',
                         'Second Story', 'Back Eave', 'Side Accent', 'Porch'];
    if (count < suggestions.length) label = suggestions[count];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New Segment',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),

                // Label
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Segment Label',
                    hintText: 'e.g. Front Eave, Garage',
                    filled: true,
                    fillColor: NexGenPalette.matteBlack,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  controller: TextEditingController(text: label),
                  onChanged: (v) => label = v,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),

                // Channel
                DropdownButtonFormField<int>(
                  initialValue: channelIndex,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Channel',
                    filled: true,
                    fillColor: NexGenPalette.matteBlack,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  dropdownColor: NexGenPalette.gunmetal90,
                  style: const TextStyle(color: Colors.white),
                  items: [
                    for (int i = 0; i < _totalChannelCount; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Row(
                          children: [
                            Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(
                                color: kChannelColors[i % kChannelColors.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: Text('Channel ${i + 1}')),
                          ],
                        ),
                      ),
                    DropdownMenuItem(
                      value: _totalChannelCount,
                      child: const Row(
                        children: [
                          Icon(Icons.add, size: 14, color: NexGenPalette.cyan),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text('Add Channel', style: TextStyle(color: NexGenPalette.cyan)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == _totalChannelCount) {
                      setState(() => _totalChannelCount++);
                      setSheetState(() {});
                      channelIndex = _totalChannelCount - 1;
                    } else {
                      channelIndex = v ?? 0;
                    }
                  },
                ),
                const SizedBox(height: 12),
                // Story level
                DropdownButtonFormField<int>(
                  initialValue: storyLevel,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Story',
                    filled: true,
                    fillColor: NexGenPalette.matteBlack,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  dropdownColor: NexGenPalette.gunmetal90,
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Ground Floor')),
                    DropdownMenuItem(value: 2, child: Text('2nd Story')),
                    DropdownMenuItem(value: 3, child: Text('3rd Story')),
                  ],
                  onChanged: (v) => storyLevel = v ?? 1,
                ),
                const SizedBox(height: 16),

                // Create button
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _editorKey.currentState?.startNewSegment(
                      label: label.isEmpty ? 'Segment ${_currentSegments.length + 1}' : label,
                      channelIndex: channelIndex,
                      storyLevel: storyLevel,
                    );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Start Tracing'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _deleteActiveSegment() {
    final idx = _editorKey.currentState?.activeSegmentIndex;
    if (idx == null) return;
    _editorKey.currentState?.deleteSegment(idx);
  }

  Future<void> _autoDetectRoofline() async {
    final editorState = _editorKey.currentState;
    if (editorState == null) return;

    setState(() => _isDetecting = true);

    try {
      final result = await RooflineAutoDetectService.detectFromImage(
          editorState.currentImageProvider);

      if (!mounted) return;

      if (result != null && result.points.length >= 2) {
        editorState.setPoints(result.points);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Detected ${result.points.length} points. Adjust if needed.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not detect roofline. Try drawing manually.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Auto-detect failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Auto-detection failed. Try drawing manually.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  Future<void> _saveRoofline() async {
    if (_isSaving) return;

    final editorState = _editorKey.currentState;
    if (editorState == null) return;

    final segments = editorState.getSegments();
    if (segments.isEmpty || !segments.any((s) => s.points.length >= 2)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please trace at least one segment with 2+ points')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final configEditor = ref.read(rooflineConfigEditorProvider.notifier);
      final stored = _stored ?? RooflineConfiguration.empty();
      final mask = editorState.getMask();

      // Row 71: merge the trace into the stored map — keep counts, anchors
      // and feature marks; delete only what the customer deleted here.
      final merged = mergeTraceIntoRoofline(
        stored: stored,
        traced: segments,
        shownInEditor: _shownIds,
      ).copyWith(
        photoPath: ref.read(houseImageUrlProvider),
        totalChannelCount: _totalChannelCount,
        // Persist the traced photo's aspect so the preview/overlay project
        // the segments correctly under BoxFit.cover.
        sourceAspectRatio: mask.sourceAspectRatio,
      );
      configEditor.loadConfiguration(merged);

      // P1 (residential path audit §9.1 item 10 / S15): a pixelMap write that
      // never landed used to report "Saved N roofline segments" and pop. Do
      // not pop on a failure: the trace is only in memory and leaving loses
      // it.
      final saved = await configEditor.save();
      if (!saved) {
        debugPrint('Roofline editor: pixelMap save failed — '
            '${configEditor.lastSaveError}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${configEditor.lastSaveMessage ?? "Your roofline didn't save."} '
                'Nothing was changed — your trace is still here.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return;
      }

      // Row 164: the photo outline is written only AFTER the map the lights
      // use has saved, so "Roofline traced" can no longer describe a map
      // that failed to save.
      final maskNote = await _saveMaskToProfile(mask.toJson());

      if (mounted) {
        final n = merged.segments.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Saved your roofline ($n segment${n == 1 ? '' : 's'}).'
                '${maskNote == null ? '' : ' $maskNote'}'),
            backgroundColor: maskNote == null ? Colors.green : Colors.orange,
          ),
        );
        context.pop();
      }
    } catch (e) {
      debugPrint('Failed to save roofline: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Writes the photo outline to the profile. Returns null on success, or a
  /// sentence saying the outline did not update (the lights' map already
  /// saved, so this is not a failure of the save).
  Future<String?> _saveMaskToProfile(Map<String, dynamic> maskJson) async {
    final profile = ref.read(currentUserProfileProvider).maybeWhen(
          data: (p) => p,
          orElse: () => null,
        );
    if (profile == null) {
      return "The photo outline didn't update (your profile hasn't loaded).";
    }
    try {
      await ref.read(userServiceProvider).updateUser(
            profile.copyWith(rooflineMask: maskJson, updatedAt: DateTime.now()),
          );
      return null;
    } catch (e) {
      debugPrint('Roofline editor: mask write failed after map save: $e');
      return "The photo outline didn't update ($e).";
    }
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────

/// Whether the roofline's corners and peaks are marked, with the way to mark
/// them. Customers whose installer did not mark them finish it here.
class _FeatureStatusBanner extends StatelessWidget {
  const _FeatureStatusBanner({required this.segmentation, required this.onMark});

  final RooflineSegmentation segmentation;
  final VoidCallback onMark;

  @override
  Widget build(BuildContext context) {
    final done = segmentation.isSegmented;
    return Container(
      key: const ValueKey('roofline-feature-status'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: done
            ? NexGenPalette.cyan.withValues(alpha: 0.08)
            : Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done
              ? NexGenPalette.cyan.withValues(alpha: 0.4)
              : Colors.amber.withValues(alpha: 0.5),
        ),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Icon(done ? Icons.check_circle : Icons.roofing,
              size: 18, color: done ? NexGenPalette.cyan : Colors.amber),
          Text(
            done
                ? 'Corners and peaks marked'
                : "Your roofline's corners and peaks aren't marked yet.",
            style: const TextStyle(color: Colors.white),
          ),
          TextButton(
            key: const ValueKey('roofline-mark-features'),
            onPressed: onMark,
            child: Text(done ? 'Review' : 'Mark them'),
          ),
        ],
      ),
    );
  }
}

class _ChannelBadge extends StatelessWidget {
  final int channelIndex;
  const _ChannelBadge({required this.channelIndex});

  @override
  Widget build(BuildContext context) {
    final color = kChannelColors[channelIndex % kChannelColors.length];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        'CH${channelIndex + 1}',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  /// Why the button is disabled. A disabled button with a reason still
  /// responds to a tap — by saying the reason — instead of sitting grey and
  /// silent (+113).
  final String? disabledReason;

  const _ToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.disabledReason,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    final fgColor = isEnabled ? (color ?? Colors.white) : Colors.white38;
    final reason = disabledReason;

    return Semantics(
      button: true,
      enabled: isEnabled,
      hint: isEnabled ? null : reason,
      child: Tooltip(
      message: isEnabled ? label : (reason ?? label),
      child: InkWell(
      onTap: onTap ??
          (reason == null
              ? null
              : () => ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(reason)))),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isEnabled ? (color ?? NexGenPalette.line) : NexGenPalette.gunmetal50),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fgColor),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: fgColor, fontSize: 12)),
          ],
        ),
      ),
      ),
      ),
    );
  }
}
