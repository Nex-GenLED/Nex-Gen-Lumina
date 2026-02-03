import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/demo/demo_models.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/demo/widgets/demo_scaffold.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/theme.dart';
import 'package:uuid/uuid.dart';

/// Simplified demo roofline setup screen.
///
/// Allows users to:
/// - Add basic roofline segments
/// - Use a suggested layout
/// - Preview their roofline configuration
class DemoRooflineScreen extends ConsumerStatefulWidget {
  const DemoRooflineScreen({super.key});

  @override
  ConsumerState<DemoRooflineScreen> createState() => _DemoRooflineScreenState();
}

class _DemoRooflineScreenState extends ConsumerState<DemoRooflineScreen> {
  void _useSuggestedLayout() {
    ref.read(demoRooflineNotifierProvider.notifier).applySuggestedLayout();
  }

  void _addSegment() {
    final notifier = ref.read(demoRooflineNotifierProvider.notifier);
    if (!notifier.canAddMore) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 segments allowed in demo')),
      );
      return;
    }

    _showAddSegmentDialog();
  }

  Future<void> _showAddSegmentDialog() async {
    DemoSegmentType selectedType = DemoSegmentType.run;
    final nameController = TextEditingController();
    int pixelCount = 50;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: NexGenPalette.gunmetal,
          title: const Text('Add Segment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Segment Name',
                  hintText: 'e.g., Front Porch',
                ),
              ),
              const SizedBox(height: 20),
              const Text('Type'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: DemoSegmentType.values.map((type) {
                  final isSelected = selectedType == type;
                  return ChoiceChip(
                    label: Text(type.shortName),
                    selected: isSelected,
                    selectedColor: NexGenPalette.cyan,
                    onSelected: (selected) {
                      if (selected) {
                        setDialogState(() {
                          selectedType = type;
                          pixelCount = type.defaultPixelCount;
                        });
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text('LED Count: $pixelCount'),
              Slider(
                value: pixelCount.toDouble(),
                min: 10,
                max: 100,
                divisions: 18,
                label: pixelCount.toString(),
                onChanged: (value) {
                  setDialogState(() => pixelCount = value.round());
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim().isEmpty
                    ? '${selectedType.shortName} ${ref.read(demoRooflineNotifierProvider).length + 1}'
                    : nameController.text.trim();

                ref.read(demoRooflineNotifierProvider.notifier).addSegment(
                      DemoSegment(
                        id: const Uuid().v4(),
                        name: name,
                        pixelCount: pixelCount,
                        type: selectedType,
                      ),
                    );
                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _continueToNext() {
    ref.read(demoFlowProvider.notifier).goToStep(DemoStep.completion);
    context.push(AppRoutes.demoComplete);
  }

  @override
  Widget build(BuildContext context) {
    final segments = ref.watch(demoRooflineNotifierProvider);
    final totalPixels = ref.watch(demoTotalPixelCountProvider);
    final canAddMore = ref.watch(demoRooflineNotifierProvider.notifier).canAddMore;

    return DemoScaffold(
      title: 'Configure Your Roofline',
      subtitle: 'Add the sections of your home\'s roofline',
      showSkip: true,
      onSkip: () {
        _useSuggestedLayout();
        _continueToNext();
      },
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick action - Use suggested layout
            if (segments.isEmpty)
              DemoGlassCard(
                onTap: _useSuggestedLayout,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NexGenPalette.cyan.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.auto_fix_high,
                        color: NexGenPalette.cyan,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Use Suggested Layout',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Auto-generate a typical home configuration',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: NexGenPalette.textMedium,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: NexGenPalette.textMedium,
                    ),
                  ],
                ),
              ),

            if (segments.isNotEmpty) ...[
              // Stats bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat('Segments', '${segments.length}'),
                    Container(
                      width: 1,
                      height: 24,
                      color: NexGenPalette.line,
                    ),
                    _buildStat('Total LEDs', '$totalPixels'),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Segment list
              ...segments.asMap().entries.map((entry) {
                final index = entry.key;
                final segment = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildSegmentCard(segment, index),
                );
              }),
            ],

            const SizedBox(height: 16),

            // Add segment button
            if (canAddMore)
              OutlinedButton.icon(
                onPressed: _addSegment,
                icon: const Icon(Icons.add),
                label: const Text('Add Segment'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),

            const SizedBox(height: 24),

            // Info banner
            DemoInfoBanner(
              message:
                  'In the full app, you can define detailed anchor points and directions for each segment.',
              icon: Icons.info_outline,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomAction: segments.isNotEmpty
          ? DemoPrimaryButton(
              label: 'Continue to Preview',
              icon: Icons.arrow_forward,
              onPressed: _continueToNext,
            )
          : null,
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: NexGenPalette.cyan,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: NexGenPalette.textMedium,
              ),
        ),
      ],
    );
  }

  Widget _buildSegmentCard(DemoSegment segment, int index) {
    return DemoGlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Segment icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getSegmentIcon(segment.type),
              color: NexGenPalette.cyan,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          // Segment info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  segment.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${segment.type.shortName} \u2022 ${segment.pixelCount} LEDs',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: NexGenPalette.textMedium,
                      ),
                ),
              ],
            ),
          ),
          // Delete button
          IconButton(
            onPressed: () {
              ref.read(demoRooflineNotifierProvider.notifier).removeSegment(segment.id);
            },
            icon: const Icon(
              Icons.delete_outline,
              color: NexGenPalette.textMedium,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getSegmentIcon(DemoSegmentType type) {
    switch (type) {
      case DemoSegmentType.run:
        return Icons.horizontal_rule;
      case DemoSegmentType.corner:
        return Icons.turn_right;
      case DemoSegmentType.peak:
        return Icons.change_history;
    }
  }
}
