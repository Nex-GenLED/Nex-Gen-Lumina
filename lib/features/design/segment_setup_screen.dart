import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
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

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await ref.read(rooflineConfigEditorProvider.notifier).initialize();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(rooflineConfigEditorProvider);
    final totalPixels = ref.watch(editorTotalPixelCountProvider);
    final segmentCount = ref.watch(editorSegmentCountProvider);

    return Scaffold(
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
                // Stats header
                _buildStatsHeader(totalPixels, segmentCount),

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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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

  Future<void> _showAddSegmentDialog() async {
    final result = await showDialog<_SegmentFormResult>(
      context: context,
      builder: (ctx) => _SegmentFormDialog(),
    );

    if (result != null) {
      ref.read(rooflineConfigEditorProvider.notifier).addSegment(
            name: result.name,
            pixelCount: result.pixelCount,
            type: result.type,
            anchorPixels: result.anchorPixels,
            anchorLedCount: result.anchorLedCount,
          );
    }
  }

  Future<void> _showEditSegmentDialog(RooflineSegment segment) async {
    final result = await showDialog<_SegmentFormResult>(
      context: context,
      builder: (ctx) => _SegmentFormDialog(existingSegment: segment),
    );

    if (result != null) {
      ref.read(rooflineConfigEditorProvider.notifier).updateSegment(
            segment.id,
            name: result.name,
            pixelCount: result.pixelCount,
            type: result.type,
            anchorPixels: result.anchorPixels,
            anchorLedCount: result.anchorLedCount,
          );
    }
  }

  Future<void> _showAnchorEditor(RooflineSegment segment) async {
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Delete Segment?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${segment.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      ref.read(rooflineConfigEditorProvider.notifier).removeSegment(segment.id);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final success =
        await ref.read(rooflineConfigEditorProvider.notifier).save();

    if (mounted) {
      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Configuration saved!'
                : 'Failed to save configuration',
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: ReorderableDragStartListener(
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
        title: Text(
          segment.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Row(
          children: [
            _InfoChip(
              icon: Icons.lightbulb_outline,
              value: '${segment.pixelCount} px',
            ),
            const SizedBox(width: 8),
            _InfoChip(
              icon: Icons.anchor,
              value: '${segment.anchorPixels.length} anchors',
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
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
              icon: const Icon(Icons.delete, size: 20),
              color: Colors.red.withValues(alpha: 0.7),
              onPressed: onDelete,
              tooltip: 'Delete Segment',
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
          Text(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
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

  _SegmentFormResult({
    required this.name,
    required this.pixelCount,
    required this.type,
    required this.anchorPixels,
    required this.anchorLedCount,
  });
}

/// Dialog for adding/editing a segment.
class _SegmentFormDialog extends StatefulWidget {
  final RooflineSegment? existingSegment;

  const _SegmentFormDialog({this.existingSegment});

  @override
  State<_SegmentFormDialog> createState() => _SegmentFormDialogState();
}

class _SegmentFormDialogState extends State<_SegmentFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _pixelCountController;
  late SegmentType _selectedType;
  late int _anchorLedCount;
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
