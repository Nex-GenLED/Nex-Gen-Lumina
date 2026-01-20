import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/theme.dart';

class ZoneConfigurationPage extends ConsumerStatefulWidget {
  const ZoneConfigurationPage({super.key});

  @override
  ConsumerState<ZoneConfigurationPage> createState() => _ZoneConfigurationPageState();
}

class _ZoneConfigurationPageState extends ConsumerState<ZoneConfigurationPage> {
  @override
  Widget build(BuildContext context) {
    final segsAsync = ref.watch(zoneSegmentsProvider);
    final selected = ref.watch(selectedSegmentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zone Control'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(zoneSegmentsProvider.notifier).refreshNow(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header section
          Text('My Channels', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Select and manage your lighting channels',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 16),

          // Channel list
          segsAsync.when(
            data: (segs) => segs.isEmpty
                ? _EmptySegments()
                : Column(
                    children: [
                      for (final s in segs)
                        _ChannelTile(
                          segment: s,
                          selected: selected.contains(s.id),
                          onChanged: (v) {
                            final set = {...selected};
                            if (v) {
                              set.add(s.id);
                            } else {
                              set.remove(s.id);
                            }
                            ref.read(selectedSegmentsProvider.notifier).state = set;
                          },
                          onRename: () => _renameSegment(context, s),
                        ),
                    ],
                  ),
            error: (e, st) => _ErrorText(error: '$e'),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Selection actions
          Wrap(spacing: 12, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: segsAsync.hasValue && segsAsync.value!.isNotEmpty
                  ? () {
                      final ids = segsAsync.value!.map((e) => e.id).toSet();
                      ref.read(selectedSegmentsProvider.notifier).state = ids;
                    }
                  : null,
              icon: const Icon(Icons.select_all),
              label: const Text('Select All'),
            ),
            OutlinedButton.icon(
              onPressed: selected.isNotEmpty
                  ? () => ref.read(selectedSegmentsProvider.notifier).state = <int>{}
                  : null,
              icon: const Icon(Icons.cancel_presentation_outlined),
              label: const Text('Clear Selection'),
            ),
          ]),

          const SizedBox(height: 24),

          // Design Studio promotion card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  NexGenPalette.cyan.withOpacity(0.15),
                  NexGenPalette.violet.withOpacity(0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NexGenPalette.cyan.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: NexGenPalette.cyan.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.palette, color: NexGenPalette.cyan),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Design Studio',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Create custom patterns and colors',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Use Design Studio to paint individual LEDs, create gradients, and apply effects to your channels.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => context.push('/design-studio'),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Open Design Studio'),
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Hardware config link
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.white54),
            title: const Text('Hardware Configuration'),
            subtitle: const Text('Configure LED counts per channel'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/hardware'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameSegment(BuildContext context, WledSegment s) async {
    final controller = TextEditingController(text: s.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Channel'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;
    final success = await repo.renameSegment(id: s.id, name: name);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Channel renamed')),
        );
        await ref.read(zoneSegmentsProvider.notifier).refreshNow();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rename failed')),
        );
      }
    }
  }
}

class _ChannelTile extends StatelessWidget {
  final WledSegment segment;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRename;

  const _ChannelTile({
    required this.segment,
    required this.selected,
    required this.onChanged,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final ledCount = segment.ledCount;
    final subtitle = ledCount > 0
        ? '$ledCount lights (LEDs ${segment.start + 1}–${segment.stop})'
        : 'No lights configured';

    return Card(
      child: ListTile(
        leading: Checkbox(
          value: selected,
          onChanged: (v) => onChanged(v ?? false),
        ),
        title: Text(segment.name, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
        trailing: IconButton(
          tooltip: 'Rename',
          icon: const Icon(Icons.drive_file_rename_outline),
          onPressed: onRename,
        ),
      ),
    );
  }
}

class _EmptySegments extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.view_week_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No channels configured. Enable channels in Hardware Configuration.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String error;

  const _ErrorText({required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(error),
    );
  }
}
