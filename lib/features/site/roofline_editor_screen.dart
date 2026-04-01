import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/services/roofline_auto_detect_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/roofline_editor.dart';

/// Full-page screen for tracing roofline segments on a house image.
///
/// Supports multi-segment tracing with per-segment channel assignment,
/// story level, and label. Each segment is rendered in its channel color.
class RooflineEditorScreen extends ConsumerStatefulWidget {
  const RooflineEditorScreen({super.key});

  @override
  ConsumerState<RooflineEditorScreen> createState() => _RooflineEditorScreenState();
}

class _RooflineEditorScreenState extends ConsumerState<RooflineEditorScreen> {
  final GlobalKey<RooflineEditorState> _editorKey = GlobalKey();
  bool _isSaving = false;
  bool _isDetecting = false;
  bool _segmentPanelExpanded = false;
  List<RooflineSegment> _currentSegments = [];
  int _totalChannelCount = 1;

  @override
  void initState() {
    super.initState();
    // Load existing config channel count after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final config = ref.read(currentRooflineConfigProvider).valueOrNull;
      if (config != null) {
        setState(() => _totalChannelCount = config.effectiveTotalChannelCount);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = ref.watch(houseImageUrlProvider);
    final useStock = ref.watch(useStockImageProvider);
    final existingMask = ref.watch(rooflineMaskProvider);
    final existingConfig = ref.watch(currentRooflineConfigProvider).valueOrNull;

    // Determine image
    ImageProvider imageProvider;
    if (imageUrl != null && !useStock) {
      imageProvider = NetworkImage(imageUrl);
    } else {
      imageProvider = const AssetImage('assets/images/Demohomephoto.jpg');
    }

    // Load initial segments from config if available
    final initialSegments = existingConfig?.segments
        .where((s) => s.points.isNotEmpty)
        .toList();

    final activeIdx = _editorKey.currentState?.activeSegmentIndex;
    final activeSeg = activeIdx != null && activeIdx < _currentSegments.length
        ? _currentSegments[activeIdx]
        : null;

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text('Trace Roofline'),
        actions: [
          if (_currentSegments.isNotEmpty)
            TextButton.icon(
              onPressed: () => _editorKey.currentState?.clear(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Clear All'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Instructions
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: NexGenPalette.cyan, size: 18),
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

            // Editor canvas
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: RooflineEditor(
                  key: _editorKey,
                  imageProvider: imageProvider,
                  initialMask: initialSegments == null || initialSegments.isEmpty
                      ? existingMask
                      : null,
                  initialSegments: initialSegments,
                  onSegmentsChanged: (segments) {
                    setState(() => _currentSegments = segments);
                  },
                ),
              ),
            ),

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
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: activeSeg.channelDisplayColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      activeSeg.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    _ChannelBadge(channelIndex: activeSeg.channelIndex),
                    const Spacer(),
                    Text(
                      '${activeSeg.points.length} pts',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                    ),
                    if (activeSeg.level > 1) ...[
                      const SizedBox(width: 8),
                      Text(
                        'L${activeSeg.level}',
                        style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),

            // Segment panel (collapsible)
            if (_segmentPanelExpanded) _buildSegmentPanel(),

            // Toolbar
            _buildToolbar(),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          // Primary actions
          Row(
            children: [
              // New Segment
              Expanded(
                child: _ToolbarButton(
                  icon: Icons.add,
                  label: '+ New Segment',
                  onTap: _showNewSegmentDialog,
                  color: NexGenPalette.cyan,
                ),
              ),
              const SizedBox(width: 8),
              // Undo
              _ToolbarButton(
                icon: Icons.undo,
                label: 'Undo',
                onTap: _editorKey.currentState?.canUndo == true
                    ? () => _editorKey.currentState?.undo()
                    : null,
              ),
              const SizedBox(width: 8),
              // Delete Segment
              _ToolbarButton(
                icon: Icons.delete_outline,
                label: 'Delete',
                onTap: _editorKey.currentState?.activeSegmentIndex != null
                    ? _deleteActiveSegment
                    : null,
                color: Colors.redAccent,
              ),
              const SizedBox(width: 8),
              // Segment list toggle
              _ToolbarButton(
                icon: _segmentPanelExpanded ? Icons.expand_less : Icons.list,
                label: '${_currentSegments.length}',
                onTap: () => setState(() => _segmentPanelExpanded = !_segmentPanelExpanded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Save / secondary actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSaving || _isDetecting ? null : _autoDetectRoofline,
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
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _currentSegments.any((s) => s.points.length >= 2) && !_isSaving
                      ? _saveRoofline
                      : null,
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
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
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
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No segments yet. Tap on the photo to start tracing.',
                  style: TextStyle(color: NexGenPalette.textMedium)),
            )
          : ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              itemCount: _currentSegments.length,
              onReorder: (old, newIdx) {
                _editorKey.currentState?.reorderSegment(old, newIdx);
              },
              itemBuilder: (context, index) {
                final seg = _currentSegments[index];
                final isActive = index == _editorKey.currentState?.activeSegmentIndex;
                return ListTile(
                  key: ValueKey(seg.id),
                  dense: true,
                  selected: isActive,
                  selectedTileColor: seg.channelDisplayColor.withValues(alpha: 0.08),
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: Icon(Icons.drag_handle, color: NexGenPalette.textMedium, size: 20),
                  ),
                  title: Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: seg.channelDisplayColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          seg.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ChannelBadge(channelIndex: seg.channelIndex),
                      const SizedBox(width: 4),
                      Text('${seg.points.length} pts',
                          style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 11)),
                    ],
                  ),
                  onTap: () => _editorKey.currentState?.selectSegment(index),
                );
              },
            ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────

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
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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

              // Channel dropdown
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: channelIndex,
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
                                Text('Channel ${i + 1}'),
                              ],
                            ),
                          ),
                        DropdownMenuItem(
                          value: _totalChannelCount,
                          child: Row(
                            children: [
                              const Icon(Icons.add, size: 14, color: NexGenPalette.cyan),
                              const SizedBox(width: 8),
                              const Text('+ Add Channel', style: TextStyle(color: NexGenPalette.cyan)),
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
                  ),
                  const SizedBox(width: 12),
                  // Story level
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: storyLevel,
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
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Create button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
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
              ),
            ],
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
      final profile = ref.read(currentUserProfileProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );
      if (profile == null) throw Exception('No user profile found');

      // 1. Save the legacy RooflineMask for backward compatibility
      final mask = editorState.getMask();
      final userService = ref.read(userServiceProvider);
      final updatedProfile = profile.copyWith(
        rooflineMask: mask.toJson(),
        updatedAt: DateTime.now(),
      );
      await userService.updateUser(updatedProfile);

      // 2. Save the multi-segment RooflineConfiguration
      final configEditor = ref.read(rooflineConfigEditorProvider.notifier);
      await configEditor.initialize();

      // Build config from traced segments
      final imageUrl = ref.read(houseImageUrlProvider);
      final config = ref.read(rooflineConfigEditorProvider);
      if (config != null) {
        // Clear existing segments and replace with traced ones
        for (final existing in config.segments.toList()) {
          configEditor.removeSegment(existing.id);
        }
      }

      // Add each traced segment
      for (final seg in segments) {
        configEditor.addSegment(
          name: seg.name,
          pixelCount: seg.pixelCount > 0 ? seg.pixelCount : 30,
          channelIndex: seg.channelIndex,
          level: seg.level,
          points: seg.points,
          isConnectedToPrevious: seg.isConnectedToPrevious,
        );
      }

      configEditor.setPhotoPath(imageUrl);
      configEditor.setTotalChannelCount(_totalChannelCount);
      await configEditor.save();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved ${segments.length} roofline segment${segments.length == 1 ? '' : 's'}'),
            backgroundColor: Colors.green,
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
}

// ── Shared widgets ──────────────────────────────────────────────────────────

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

  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;
    final fgColor = isEnabled ? (color ?? Colors.white) : Colors.white38;

    return InkWell(
      onTap: onTap,
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
    );
  }
}
