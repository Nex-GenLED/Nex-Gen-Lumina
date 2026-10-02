import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_feature_walkthrough.dart';
import 'package:nexgen_command/features/design/roofline_repair.dart';
import 'package:nexgen_command/features/design/roofline_target_bar.dart';
import 'package:nexgen_command/features/installer/installer_lock_screen.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// Screen for setting up and configuring roofline segments.
///
/// Allows users to:
/// - Add/edit/remove segments
/// - Reorder segments via drag and drop
/// - Configure anchor points per segment
/// - View total pixel count
class SegmentSetupScreen extends ConsumerStatefulWidget {
  const SegmentSetupScreen({super.key});

  @override
  ConsumerState<SegmentSetupScreen> createState() => _SegmentSetupScreenState();
}

class _SegmentSetupScreenState extends ConsumerState<SegmentSetupScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: initialize() can set provider state before its
    // first await (no controller chosen yet), which Riverpod does not allow
    // while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    // Locked for a customer: nothing to load (see build).
    if (!ref.read(installerModeActiveProvider)) return;
    await ref.read(rooflineConfigEditorProvider.notifier).initialize();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // +113 (owner decision 2026-10-01): this flat editor lets its user type
    // pixel counts and add segments to any channel, which is how a channel
    // outgrows its strip — an installer's tool. Same lock as the Roofline
    // Setup Wizard; a customer marks corners, peaks and runs in Mark Your
    // Roofline instead, and Design Studio's "Roofline setup" now opens that.
    if (!ref.watch(installerModeActiveProvider)) {
      return InstallerLockScreen(
        title: 'Roofline Segments',
        featureName: 'The Roofline Segments editor',
        alternativeLabel: 'Mark Your Roofline instead',
        onAlternative: () => openRooflineFeatureWalkthrough(context),
      );
    }

    final config = ref.watch(rooflineConfigEditorProvider);
    final totalPixels = ref.watch(editorTotalPixelCountProvider);
    final segmentCount = ref.watch(editorSegmentCountProvider);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: NexGenPalette.gunmetal90,
            title: const Text('Unsaved Changes', style: TextStyle(color: Colors.white)),
            content: const Text(
              'You have unsaved changes. Save before leaving?',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx, false);
                  await _save();
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (discard == true && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: GlassAppBar(
          title: const Text('Roofline Segments'),
          actions: [
            IconButton(
              onPressed: _isSaving ? null : _save,
              tooltip: 'Save Configuration',
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Row 70 (+110): which controller this roofline belongs to.
                  RooflineTargetBar(
                    enabled: !_dirty && !_isSaving,
                    onChanged: (_) {
                      setState(() => _isLoading = true);
                      _initialize();
                    },
                  ),
                  // Stats header
                  _buildStatsHeader(totalPixels, segmentCount),

                  // +113: a channel carrying stacked copies of the same
                  // segment gets a one-tap, backed-up cleanup.
                  if (config != null &&
                      cleanupHasWork(planRooflineCleanup(config)))
                    _CleanupBanner(
                      onReview: _isSaving
                          ? null
                          : () => _showCleanupSheet(config),
                    ),

                  // Segment list
                  Expanded(
                    child: config == null || config.segments.isEmpty
                        ? _buildEmptyState()
                        : _buildSegmentList(config.segments),
                  ),

                  // Add segment button
                  _buildAddButton(),
                ],
              ),
      ),
    );
  }

  Widget _buildStatsHeader(int totalPixels, int segmentCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        spacing: 24,
        runSpacing: 12,
        children: [
          _StatItem(
            label: 'Segments',
            value: segmentCount.toString(),
            icon: Icons.segment,
          ),
          _StatItem(
            label: 'Total Pixels',
            value: totalPixels.toString(),
            icon: Icons.lightbulb_outline,
          ),
          _StatItem(
            label: 'Anchors',
            value: ref.watch(rooflineConfigEditorProvider)?.totalAnchorCount.toString() ?? '0',
            icon: Icons.anchor,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(
            Icons.roofing,
            size: 64,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No segments defined',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white54,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add segments to define your roofline',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white38,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showAddSegmentDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add First Segment'),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentList(List<RooflineSegment> segments) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: segments.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        ref.read(rooflineConfigEditorProvider.notifier).reorderSegments(oldIndex, newIndex);
        setState(() => _dirty = true);
      },
      itemBuilder: (context, index) {
        final segment = segments[index];
        return _SegmentCard(
          key: ValueKey(segment.id),
          segment: segment,
          index: index,
          onEdit: () => _showEditSegmentDialog(segment),
          onDelete: () => _confirmDelete(segment),
          onEditAnchors: () => _showAnchorEditor(segment),
        );
      },
    );
  }

  Widget _buildAddButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _showAddSegmentDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add Segment'),
          ),
        ),
      ),
    );
  }

  /// The channels a segment can belong to: every channel the map already
  /// uses, every channel the connected controller reports, and at least the
  /// map's declared channel count. Sorted, 0-based.
  List<int> _channelChoices(RooflineConfiguration? config) {
    final out = <int>{0};
    if (config != null) {
      out.addAll(config.allChannelIndices);
      for (var i = 0; i < config.effectiveTotalChannelCount; i++) {
        out.add(i);
      }
    }
    for (final c in ref.read(deviceChannelsProvider)) {
      out.add(c.id);
    }
    return out.toList()..sort();
  }

  Future<void> _showAddSegmentDialog() async {
    final config = ref.read(rooflineConfigEditorProvider);
    final channels = _channelChoices(config);
    // Default to the channel the last segment is on — a new segment usually
    // continues the strip being described — never silently to channel 0.
    final initialChannel = config != null && config.segments.isNotEmpty
        ? config.segments.last.channelIndex
        : channels.first;
    final result = await showDialog<_SegmentFormResult>(
      context: context,
      builder: (ctx) => _SegmentFormDialog(
        channels: channels,
        initialChannel: initialChannel,
      ),
    );

    if (result != null) {
      ref.read(rooflineConfigEditorProvider.notifier).addSegment(
            name: result.name,
            pixelCount: result.pixelCount,
            type: result.type,
            anchorPixels: result.anchorPixels,
            anchorLedCount: result.anchorLedCount,
            // Row 1 of #108's finding 2 (+113): the form names the channel.
            // addSegment's default of 0 put every hand-added segment on
            // channel 0 regardless of where the lights are.
            channelIndex: result.channelIndex,
            // The customer chose this segment's type in the form.
            featureConfirmed: true,
          );
      setState(() => _dirty = true);
    }
  }

  Future<void> _showEditSegmentDialog(RooflineSegment segment) async {
    final result = await showDialog<_SegmentFormResult>(
      context: context,
      builder: (ctx) => _SegmentFormDialog(
        existingSegment: segment,
        channels: _channelChoices(ref.read(rooflineConfigEditorProvider)),
        initialChannel: segment.channelIndex,
      ),
    );

    if (result != null) {
      ref.read(rooflineConfigEditorProvider.notifier).updateSegment(
            segment.id,
            name: result.name,
            pixelCount: result.pixelCount,
            type: result.type,
            anchorPixels: result.anchorPixels,
            anchorLedCount: result.anchorLedCount,
            channelIndex: result.channelIndex,
            featureConfirmed: true,
          );
      setState(() => _dirty = true);
    }
  }

  /// Dry run, then "Back up and clean up". The backup goes to each channel's
  /// own pixelMap doc before the cleaned map is saved
  /// ([RooflineConfigEditorNotifier.applyCleanup]).
  Future<void> _showCleanupSheet(RooflineConfiguration config) async {
    final plans = planRooflineCleanup(config);
    final text = [
      for (final p in plans.values)
        if (p.hasWork) describeChannelCleanup(p),
    ].join('\n');
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Clean up duplicate segments',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              const Text(
                'This keeps one copy of each stacked segment. Nothing is '
                'lit differently: the kept segments keep their lights, and '
                'the removed copies are backed up on this map so the change '
                'can be undone.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    key: const ValueKey('cleanup-dry-run'),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Not now'),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('cleanup-confirm'),
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Back up and clean up'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _isSaving = true);
    final notifier = ref.read(rooflineConfigEditorProvider.notifier);
    final ok = await notifier.applyCleanup(plans);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (ok) _dirty = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Cleaned up. The previous segments are backed up on this map.'
          : notifier.lastSaveMessage ?? 'The cleanup did not save.'),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
  }

  Future<void> _showAnchorEditor(RooflineSegment segment) async {
    final before = ref.read(rooflineConfigEditorProvider);
    await _openAnchorSheet(segment);
    // The anchor sheet edits the map directly; count that as unsaved.
    if (mounted && !identical(before, ref.read(rooflineConfigEditorProvider))) {
      setState(() => _dirty = true);
    }
  }

  Future<void> _openAnchorSheet(RooflineSegment segment) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AnchorEditorSheet(segment: segment),
    );
  }

  Future<void> _confirmDelete(RooflineSegment segment) async {
    // +113: a segment's lights can join its neighbour on the channel (the
    // channel keeps every light it has) or go with it (the old behaviour).
    final neighbor =
        ref.read(rooflineConfigEditorProvider)?.mergeNeighborOf(segment.id);
    final n = segment.pixelCount;
    final choice = await showDialog<_DeleteChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Delete Segment?', style: TextStyle(color: Colors.white)),
        content: Text(
          neighbor == null
              ? 'Delete "${segment.name}" and its $n light${n == 1 ? '' : 's'}? '
                  'It is the only segment on channel ${segment.channelIndex + 1}.'
              : 'Delete "${segment.name}"? Its $n light${n == 1 ? '' : 's'} can '
                  'join "${neighbor.name}" so channel '
                  '${segment.channelIndex + 1} keeps all of its lights, or be '
                  'removed with it.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _DeleteChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('delete-remove-lights'),
            onPressed: () => Navigator.pop(ctx, _DeleteChoice.remove),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text(neighbor == null ? 'Delete' : 'Remove with its lights'),
          ),
          if (neighbor != null)
            FilledButton(
              key: const ValueKey('delete-merge'),
              onPressed: () => Navigator.pop(ctx, _DeleteChoice.merge),
              child: Text('Merge into "${neighbor.name}"'),
            ),
        ],
      ),
    );

    if (choice == null || choice == _DeleteChoice.cancel) return;
    // Row 72 (+110): this used to call save() on the WHOLE editor, so one
    // delete silently committed every other unsaved add, edit and reorder
    // on the screen and bypassed the unsaved-changes prompt. A delete is
    // now an edit like any other: it marks the screen dirty and is saved by
    // Save (or discarded by leaving).
    final notifier = ref.read(rooflineConfigEditorProvider.notifier);
    if (choice == _DeleteChoice.merge) {
      notifier.removeSegmentMerging(segment.id);
    } else {
      notifier.removeSegment(segment.id);
    }
    setState(() => _dirty = true);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final notifier = ref.read(rooflineConfigEditorProvider.notifier);
    final success = await notifier.save();

    if (mounted) {
      setState(() {
        _isSaving = false;
        if (success) _dirty = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Configuration saved!'
                : notifier.lastSaveMessage ?? 'Failed to save configuration',
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );

      if (success) {
        context.pop();
      }
    }
  }
}

/// Stats item widget for the header.
class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: NexGenPalette.cyan, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// Card widget for displaying a single segment.
class _SegmentCard extends StatelessWidget {
  final RooflineSegment segment;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onEditAnchors;

  const _SegmentCard({
    super.key,
    required this.segment,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onEditAnchors,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getTypeColor(segment.type).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getTypeIcon(segment.type),
                      color: _getTypeColor(segment.type),
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    segment.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoChip(
                  icon: _getTypeIcon(segment.type),
                  value: segment.type.displayName,
                ),
                _InfoChip(
                  icon: Icons.lightbulb_outline,
                  value: '${segment.pixelCount} px',
                ),
                _InfoChip(
                  icon: Icons.anchor,
                  value: '${segment.anchorPixels.length} anchors',
                ),
                _InfoChip(
                  icon: Icons.cable,
                  value: 'Channel ${segment.channelIndex + 1}',
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.anchor, size: 20),
                  color: Colors.white54,
                  onPressed: onEditAnchors,
                  tooltip: 'Edit Anchors',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  color: Colors.white54,
                  onPressed: onEdit,
                  tooltip: 'Edit Segment',
                ),
                IconButton(
                  key: ValueKey('delete-${segment.id}'),
                  icon: const Icon(Icons.delete, size: 20),
                  color: Colors.red.withValues(alpha: 0.7),
                  onPressed: onDelete,
                  tooltip: 'Delete Segment',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTypeIcon(SegmentType type) {
    switch (type) {
      case SegmentType.run:
        return Icons.horizontal_rule;
      case SegmentType.corner:
        return Icons.turn_right;
      case SegmentType.peak:
        return Icons.change_history;
      case SegmentType.column:
        return Icons.height;
      case SegmentType.connector:
        return Icons.link;
    }
  }

  Color _getTypeColor(SegmentType type) {
    switch (type) {
      case SegmentType.run:
        return NexGenPalette.cyan;
      case SegmentType.corner:
        return Colors.orange;
      case SegmentType.peak:
        return Colors.purple;
      case SegmentType.column:
        return Colors.green;
      case SegmentType.connector:
        return Colors.grey;
    }
  }
}

/// Small info chip for segment details.
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String value;

  const _InfoChip({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DeleteChoice { cancel, remove, merge }

/// "Clean up duplicates" offer, shown only when the map has stacked copies.
class _CleanupBanner extends StatelessWidget {
  const _CleanupBanner({required this.onReview});

  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.layers, color: Colors.amber, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Some segments on this map are stacked copies of each '
                  'other. Clean-up keeps one of each and backs up the rest.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              key: const ValueKey('cleanup-review'),
              onPressed: onReview,
              icon: const Icon(Icons.cleaning_services, size: 18),
              label: const Text('Review clean-up'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Form result for segment creation/editing.
class _SegmentFormResult {
  final String name;
  final int pixelCount;
  final SegmentType type;
  final List<int> anchorPixels;
  final int anchorLedCount;
  final int channelIndex;

  _SegmentFormResult({
    required this.name,
    required this.pixelCount,
    required this.type,
    required this.anchorPixels,
    required this.anchorLedCount,
    required this.channelIndex,
  });
}

/// Dialog for adding/editing a segment.
class _SegmentFormDialog extends StatefulWidget {
  final RooflineSegment? existingSegment;

  /// Channels offered (0-based), and the one selected to start with.
  final List<int> channels;
  final int initialChannel;

  const _SegmentFormDialog({
    this.existingSegment,
    this.channels = const [0],
    this.initialChannel = 0,
  });

  @override
  State<_SegmentFormDialog> createState() => _SegmentFormDialogState();
}

class _SegmentFormDialogState extends State<_SegmentFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _pixelCountController;
  late SegmentType _selectedType;
  late int _anchorLedCount;
  late int _channelIndex;
  bool _hasStartAnchor = true;
  bool _hasEndAnchor = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingSegment;

    _nameController = TextEditingController(text: existing?.name ?? '');
    _pixelCountController =
        TextEditingController(text: existing?.pixelCount.toString() ?? '');
    _selectedType = existing?.type ?? SegmentType.run;
    _anchorLedCount = existing?.anchorLedCount ?? 2;
    _channelIndex = widget.channels.contains(widget.initialChannel)
        ? widget.initialChannel
        : widget.channels.first;

    if (existing != null && existing.anchorPixels.isNotEmpty) {
      _hasStartAnchor = existing.anchorPixels.contains(0);
      _hasEndAnchor = existing.anchorPixels
          .contains(existing.pixelCount - existing.anchorLedCount);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pixelCountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingSegment != null;

    return AlertDialog(
      backgroundColor: NexGenPalette.gunmetal90,
      title: Text(
        isEditing ? 'Edit Segment' : 'Add Segment',
        style: const TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Channel — which strip the lights are on. Asked first because
            // nothing else on the form means anything without it.
            const Text(
              'Channel',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: const ValueKey('segment-form-channel'),
              initialValue: _channelIndex,
              dropdownColor: NexGenPalette.gunmetal90,
              style: const TextStyle(color: Colors.white),
              items: [
                for (final ch in widget.channels)
                  DropdownMenuItem(value: ch, child: Text('Channel ${ch + 1}')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _channelIndex = v);
              },
            ),
            const SizedBox(height: 16),

            // Name field
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Segment Name',
                labelStyle: TextStyle(color: Colors.white54),
                hintText: 'e.g., Front Porch',
                hintStyle: TextStyle(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 16),

            // Pixel count field
            TextField(
              controller: _pixelCountController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Pixel Count',
                labelStyle: TextStyle(color: Colors.white54),
                hintText: 'Number of LEDs',
                hintStyle: TextStyle(color: Colors.white24),
              ),
            ),
            const SizedBox(height: 16),

            // Segment type dropdown
            const Text(
              'Segment Type',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<SegmentType>(
              value: _selectedType,
              dropdownColor: NexGenPalette.gunmetal90,
              style: const TextStyle(color: Colors.white),
              items: SegmentType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type.displayName),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedType = value);
                }
              },
            ),
            const SizedBox(height: 16),

            // Anchor LED count
            const Text(
              'LEDs per Anchor Zone',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
              ],
              selected: {_anchorLedCount},
              onSelectionChanged: (values) {
                setState(() => _anchorLedCount = values.first);
              },
            ),
            const SizedBox(height: 16),

            // Default anchors
            const Text(
              'Default Anchors',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _hasStartAnchor,
              onChanged: (v) => setState(() => _hasStartAnchor = v ?? false),
              title: const Text('Start of segment',
                  style: TextStyle(color: Colors.white)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _hasEndAnchor,
              onChanged: (v) => setState(() => _hasEndAnchor = v ?? false),
              title: const Text('End of segment',
                  style: TextStyle(color: Colors.white)),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    final pixelCount = int.tryParse(_pixelCountController.text) ?? 0;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a segment name')),
      );
      return;
    }

    if (pixelCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid pixel count')),
      );
      return;
    }

    // Build anchor list
    final anchors = <int>[];
    if (_hasStartAnchor) anchors.add(0);
    if (_hasEndAnchor && pixelCount >= _anchorLedCount) {
      anchors.add(pixelCount - _anchorLedCount);
    }

    Navigator.pop(
      context,
      _SegmentFormResult(
        name: name,
        pixelCount: pixelCount,
        type: _selectedType,
        anchorPixels: anchors,
        anchorLedCount: _anchorLedCount,
        channelIndex: _channelIndex,
      ),
    );
  }
}

/// Bottom sheet for editing anchor points on a segment.
class _AnchorEditorSheet extends ConsumerWidget {
  final RooflineSegment segment;

  const _AnchorEditorSheet({required this.segment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Re-read the segment from the editor state to get latest changes
    final config = ref.watch(rooflineConfigEditorProvider);
    final currentSegment = config?.segmentById(segment.id) ?? segment;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.anchor, color: NexGenPalette.cyan),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Anchors: ${currentSegment.name}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Tap LEDs to toggle anchor points',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      ref
                          .read(rooflineConfigEditorProvider.notifier)
                          .applyDefaultAnchors(segment.id);
                    },
                    child: const Text('Reset Defaults'),
                  ),
                ],
              ),
            ),
            // LED strip visualization
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: _AnchorLedStrip(
                  segment: currentSegment,
                  onToggleAnchor: (localIndex) {
                    ref
                        .read(rooflineConfigEditorProvider.notifier)
                        .toggleAnchor(segment.id, localIndex);
                  },
                ),
              ),
            ),
            // Done button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Visual LED strip for anchor editing.
class _AnchorLedStrip extends StatelessWidget {
  final RooflineSegment segment;
  final ValueChanged<int> onToggleAnchor;

  const _AnchorLedStrip({
    required this.segment,
    required this.onToggleAnchor,
  });

  @override
  Widget build(BuildContext context) {
    const ledsPerRow = 20;
    final rowCount = (segment.pixelCount / ledsPerRow).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int row = 0; row < rowCount; row++) ...[
          // Row label
          if (rowCount > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'LEDs ${row * ledsPerRow} - ${((row + 1) * ledsPerRow - 1).clamp(0, segment.pixelCount - 1)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
              ),
            ),
          // LED row
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (int col = 0; col < ledsPerRow; col++)
                Builder(
                  builder: (context) {
                    final ledIndex = row * ledsPerRow + col;
                    if (ledIndex >= segment.pixelCount) {
                      return const SizedBox.shrink();
                    }

                    final isAnchor = segment.isAnchorPixel(ledIndex);

                    return GestureDetector(
                      onTap: () {
                        // Find the anchor start position for this LED
                        if (isAnchor) {
                          // Find which anchor zone this belongs to
                          for (final anchor in segment.anchorPixels) {
                            if (ledIndex >= anchor &&
                                ledIndex < anchor + segment.anchorLedCount) {
                              onToggleAnchor(anchor);
                              break;
                            }
                          }
                        } else {
                          // Add new anchor starting at this position
                          onToggleAnchor(ledIndex);
                        }
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isAnchor
                              ? Colors.amber.withValues(alpha: 0.8)
                              : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isAnchor
                                ? Colors.amber
                                : Colors.white.withValues(alpha: 0.2),
                            width: isAnchor ? 2 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '$ledIndex',
                            style: TextStyle(
                              color: isAnchor ? Colors.black : Colors.white54,
                              fontSize: 8,
                              fontWeight: isAnchor
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        // Legend
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Anchor LED (always lit in downlighting)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
