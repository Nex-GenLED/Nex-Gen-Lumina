import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

class ManageControllersPage extends ConsumerWidget {
  const ManageControllersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(controllersStreamProvider);
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Controllers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.wifiConnect),
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text('Add Controller'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: asyncList.when(
          data: (items) {
            if (items.isEmpty) {
              return _EmptyManageState(onAdd: () => context.push(AppRoutes.wifiConnect));
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _ControllerTile(item: items[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, st) => Center(child: Text('Failed to load: $e')),
        ),
      ),
    );
  }
}

class _ControllerTile extends ConsumerWidget {
  final ControllerInfo item;
  const _ControllerTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(selectedDeviceIpProvider) == item.ip;
    final deleteController = ref.watch(deleteControllerProvider);
    return Card(
      child: ListTile(
        leading: Icon(Icons.router_outlined, color: isActive ? NexGenPalette.cyan : Theme.of(context).colorScheme.onSurfaceVariant),
        title: Row(
          children: [
            Expanded(child: Text(item.name ?? 'Controller')),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Active',
                  style: TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('IP: ${item.ip}', overflow: TextOverflow.ellipsis),
            if (item.wifiConfigured == true && item.ssid != null)
              Text('Network: ${item.ssid}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        isThreeLine: item.wifiConfigured == true && item.ssid != null,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Details',
            onPressed: () => _showDetails(context, ref),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: () => _confirmDelete(context, deleteController),
            icon: const Icon(Icons.delete_outline),
          )
        ]),
        onTap: isActive ? null : () => ref.read(selectedDeviceIpProvider.notifier).state = item.ip,
      ),
    );
  }

  void _showDetails(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.name ?? 'Controller Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(label: 'Name', value: item.name ?? 'Unnamed'),
            _DetailRow(label: 'IP Address', value: item.ip),
            _DetailRow(label: 'Serial', value: item.serial ?? 'N/A'),
            if (item.ssid != null) _DetailRow(label: 'Wi-Fi Network', value: item.ssid!),
            _DetailRow(label: 'Wi-Fi Configured', value: item.wifiConfigured == true ? 'Yes' : 'No'),
            if (item.createdAt != null)
              _DetailRow(label: 'Added', value: _formatDate(item.createdAt)),
            if (item.updatedAt != null)
              _DetailRow(label: 'Last Updated', value: _formatDate(item.updatedAt)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showRenameDialog(context, ref);
            },
            child: const Text('Rename'),
          ),
          if (ref.read(selectedDeviceIpProvider) != item.ip)
            FilledButton(
              onPressed: () {
                ref.read(selectedDeviceIpProvider.notifier).state = item.ip;
                Navigator.of(ctx).pop();
              },
              child: const Text('Set as Active'),
            ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: item.name ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Controller'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Controller Name',
            hintText: 'Enter a name for this controller',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) return;
              Navigator.of(ctx).pop();
              final rename = ref.read(renameControllerProvider);
              final ok = await rename(item.id, newName);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Controller renamed to "$newName"' : 'Failed to rename controller'),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Future<bool> Function(String) deleteController) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Controller'),
        content: Text('Remove ${item.name ?? 'this controller'} from your account?\n\nThis will delete all saved settings for this controller.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final res = await deleteController(item.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res ? 'Controller removed successfully' : 'Failed to remove controller'),
            backgroundColor: res ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(dynamic timestamp) {
    try {
      if (timestamp == null) return 'N/A';
      final dt = timestamp.toDate() as DateTime;
      return '${dt.month}/${dt.day}/${dt.year}';
    } catch (e) {
      return 'N/A';
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyManageState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyManageState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.router, color: NexGenPalette.violet, size: 48),
        const SizedBox(height: 12),
        Text('No controllers yet', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Add your Nex-Gen Controller to manage it here.', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add Controller')),
      ]),
    );
  }
}
