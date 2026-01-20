import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/theme.dart';

/// Screen for viewing and managing saved designs.
class MyDesignsScreen extends ConsumerWidget {
  const MyDesignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final designsAsync = ref.watch(designsStreamProvider);

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('My Designs'),
        actions: [
          IconButton(
            onPressed: () => context.push('/design-studio'),
            icon: const Icon(Icons.add),
            tooltip: 'New Design',
          ),
        ],
      ),
      body: designsAsync.when(
        data: (designs) {
          if (designs.isEmpty) {
            return _EmptyState(
              onCreateNew: () => context.push('/design-studio'),
            );
          }
          return _DesignsList(designs: designs);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error loading designs: $error'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(designsStreamProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/design-studio'),
        icon: const Icon(Icons.add),
        label: const Text('New Design'),
        backgroundColor: NexGenPalette.cyan,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateNew;

  const _EmptyState({required this.onCreateNew});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.palette_outlined,
                size: 64,
                color: NexGenPalette.cyan,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Designs Yet',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first custom lighting design\nusing the Design Studio.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCreateNew,
              icon: const Icon(Icons.add),
              label: const Text('Create Design'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesignsList extends ConsumerWidget {
  final List<CustomDesign> designs;

  const _DesignsList({required this.designs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: designs.length,
      itemBuilder: (context, index) {
        final design = designs[index];
        return _DesignCard(
          design: design,
          onTap: () => _editDesign(context, ref, design),
          onApply: () => _applyDesign(context, ref, design),
          onDuplicate: () => _duplicateDesign(context, ref, design),
          onDelete: () => _deleteDesign(context, ref, design),
        );
      },
    );
  }

  void _editDesign(BuildContext context, WidgetRef ref, CustomDesign design) {
    ref.read(currentDesignProvider.notifier).loadDesign(design);
    context.push('/design-studio');
  }

  Future<void> _applyDesign(BuildContext context, WidgetRef ref, CustomDesign design) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No device connected')),
      );
      return;
    }

    final payload = design.toWledPayload();
    final success = await repo.applyJson(payload);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Applied "${design.name}"' : 'Failed to apply design'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _duplicateDesign(BuildContext context, WidgetRef ref, CustomDesign design) async {
    final controller = TextEditingController(text: '${design.name} (Copy)');

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Duplicate Design', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'New Name',
            labelStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final newId = await ref.read(duplicateDesignProvider)(design, result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newId != null ? 'Created "$result"' : 'Failed to duplicate'),
            backgroundColor: newId != null ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteDesign(BuildContext context, WidgetRef ref, CustomDesign design) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Delete Design?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${design.name}"? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await ref.read(deleteDesignProvider)(design.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Deleted "${design.name}"' : 'Failed to delete'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }
}

class _DesignCard extends StatelessWidget {
  final CustomDesign design;
  final VoidCallback onTap;
  final VoidCallback onApply;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _DesignCard({
    required this.design,
    required this.onTap,
    required this.onApply,
    required this.onDuplicate,
    required this.onDelete,
  });

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final includedChannels = design.channels.where((ch) => ch.included).length;
    final totalChannels = design.channels.length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Color preview row
                  _ColorPreview(design: design),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          design.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$includedChannels of $totalChannels channels',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Quick apply button
                  IconButton(
                    onPressed: onApply,
                    icon: const Icon(Icons.play_arrow),
                    tooltip: 'Apply to Device',
                    color: NexGenPalette.cyan,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Tags
              if (design.tags.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: design.tags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: NexGenPalette.violet.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        color: NexGenPalette.violet,
                        fontSize: 11,
                      ),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 12),
              ],
              // Footer
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.white.withOpacity(0.4)),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(design.updatedAt),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  // Actions
                  IconButton(
                    onPressed: onDuplicate,
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Duplicate',
                    color: Colors.white54,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Delete',
                    color: Colors.red.withOpacity(0.7),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPreview extends StatelessWidget {
  final CustomDesign design;

  const _ColorPreview({required this.design});

  @override
  Widget build(BuildContext context) {
    // Gather unique colors from all channels
    final colors = <Color>[];
    for (final channel in design.channels.where((ch) => ch.included)) {
      for (final group in channel.colorGroups.take(3)) {
        colors.add(group.flutterColor);
        if (colors.length >= 4) break;
      }
      if (colors.length >= 4) break;
    }

    if (colors.isEmpty) {
      colors.add(Colors.white);
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: colors.length > 1
            ? LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: colors.length == 1 ? colors.first : null,
        boxShadow: [
          BoxShadow(
            color: colors.first.withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}
