import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/zones/models/fixture_type.dart';
import 'package:nexgen_command/features/zones/models/zone_assignment.dart';
import 'package:nexgen_command/features/zones/services/zone_config_service.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

class ZoneSetupScreen extends ConsumerWidget {
  const ZoneSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segmentsAsync = ref.watch(zoneSegmentsProvider);
    final assignmentsAsync = ref.watch(zoneAssignmentsProvider);

    return Scaffold(
      appBar: const GlassAppBar(title: Text('Zone & Fixture Setup')),
      body: segmentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Failed to load segments: $e',
              style: Theme.of(context).textTheme.bodyMedium),
        ),
        data: (segments) {
          if (segments.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cable, size: 48,
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    Text('No Segments Found',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Connect to a controller to view and assign fixture types to segments.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }

          final assignments = assignmentsAsync.valueOrNull ?? [];
          final assignmentMap = {
            for (final a in assignments) a.segmentId: a,
          };

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: segments.length,
            itemBuilder: (context, index) {
              final seg = segments[index];
              final assignment = assignmentMap[seg.id];
              return _SegmentCard(segment: seg, assignment: assignment);
            },
          );
        },
      ),
    );
  }
}

class _SegmentCard extends ConsumerWidget {
  const _SegmentCard({required this.segment, this.assignment});

  final WledSegment segment;
  final ZoneAssignment? assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAssigned = assignment != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openAssignmentSheet(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isAssigned)
                    Icon(_iconForFixture(assignment!.fixtureType),
                        color: NexGenPalette.cyan, size: 20)
                  else
                    Icon(Icons.cable,
                        color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(segment.name,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  Text(
                    '${segment.ledCount} LEDs',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  'Pixels ${segment.start} → ${segment.stop}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              if (isAssigned) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Row(
                    children: [
                      Text(
                        assignment!.fixtureType.displayName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: NexGenPalette.cyan,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (assignment!.locationLabel.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text('·',
                            style: TextStyle(color: NexGenPalette.cyan.withValues(alpha: 0.5))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            assignment!.locationLabel,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: NexGenPalette.cyan.withValues(alpha: 0.85),
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Text(
                    'Tap to assign fixture type',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForFixture(FixtureType type) {
    return switch (type) {
      FixtureType.rooflineRail => Icons.roofing,
      FixtureType.flushLandscape => Icons.landscape,
      FixtureType.diffusedRope => Icons.light_mode,
      FixtureType.stairLight => Icons.stairs,
      FixtureType.soffitUplight => Icons.highlight,
      FixtureType.wallWash => Icons.wallpaper,
    };
  }

  Future<void> _openAssignmentSheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AssignmentSheet(
        segment: segment,
        existing: assignment,
      ),
    );
  }
}

class _AssignmentSheet extends ConsumerStatefulWidget {
  const _AssignmentSheet({required this.segment, this.existing});

  final WledSegment segment;
  final ZoneAssignment? existing;

  @override
  ConsumerState<_AssignmentSheet> createState() => _AssignmentSheetState();
}

class _AssignmentSheetState extends ConsumerState<_AssignmentSheet> {
  late FixtureType? _selectedType;
  late final TextEditingController _labelCtrl;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.existing?.fixtureType;
    _labelCtrl = TextEditingController(text: widget.existing?.locationLabel ?? '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.4,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Title
            Text(widget.segment.name,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Pixels ${widget.segment.start} → ${widget.segment.stop}  ·  ${widget.segment.ledCount} LEDs',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            // Fixture type picker
            Text('Fixture Type',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  for (final type in FixtureType.values)
                    _FixtureTypeOption(
                      type: type,
                      isSelected: _selectedType == type,
                      onTap: () => setState(() => _selectedType = type),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Location label — pinned below the scrollable fixture list
            Text('Location Label',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _labelCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. Front Roofline, Patio Edge',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            // Action buttons — always visible at bottom
            Row(
              children: [
                if (widget.existing != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _removeAssignment,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (widget.existing != null) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _selectedType != null ? _saveAssignment : null,
                    icon: const Icon(Icons.check),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAssignment() async {
    if (_selectedType == null) return;
    final service = ref.read(zoneConfigServiceProvider);
    await service.upsertAssignment(ZoneAssignment(
      segmentId: widget.segment.id,
      fixtureType: _selectedType!,
      locationLabel: _labelCtrl.text.trim(),
      assignedAt: DateTime.now(),
    ));
    ref.invalidate(zoneAssignmentsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _removeAssignment() async {
    final service = ref.read(zoneConfigServiceProvider);
    await service.removeAssignment(widget.segment.id);
    ref.invalidate(zoneAssignmentsProvider);
    if (mounted) Navigator.of(context).pop();
  }
}

class _FixtureTypeOption extends StatelessWidget {
  const _FixtureTypeOption({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  final FixtureType type;
  final bool isSelected;
  final VoidCallback onTap;

  IconData _iconForType(FixtureType t) {
    return switch (t) {
      FixtureType.rooflineRail => Icons.roofing,
      FixtureType.flushLandscape => Icons.landscape,
      FixtureType.diffusedRope => Icons.light_mode,
      FixtureType.stairLight => Icons.stairs,
      FixtureType.soffitUplight => Icons.highlight,
      FixtureType.wallWash => Icons.wallpaper,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isSelected
          ? NexGenPalette.cyan.withValues(alpha: 0.12)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: NexGenPalette.cyan, width: 1.5)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Icon(
          _iconForType(type),
          color: isSelected ? NexGenPalette.cyan : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(
          type.displayName,
          style: TextStyle(
            color: isSelected ? NexGenPalette.cyan : null,
            fontWeight: isSelected ? FontWeight.w600 : null,
          ),
        ),
        subtitle: Text(
          type.behaviorHint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: NexGenPalette.cyan)
            : null,
        onTap: onTap,
      ),
    );
  }
}
