import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

/// Card displaying scenes and presets with apply functionality
class ScenesCard extends ConsumerWidget {
  const ScenesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDemo = ref.watch(demoModeProvider);
    final repo = ref.watch(wledRepositoryProvider);
    final presets = repo?.getPresets() ?? const <WledPreset>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Scenes & Presets', style: Theme.of(context).textTheme.titleMedium)),
            if (!isDemo) ...[
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: () => _showBackendPrompt(context), icon: const Icon(Icons.cloud_upload), label: const Text('Save')),
            ]
          ]),
          const SizedBox(height: 8),
          if (isDemo && presets.isNotEmpty) ...[
            Text('Nex-Gen Signature Presets (Demo)', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: presets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = presets[i];
                return ListTile(
                  title: Text(p.name),
                  trailing: FilledButton(
                    onPressed: () async {
                      if (repo == null) return;
                      await repo.applyJson(p.json);
                      final notifier = ref.read(wledStateProvider.notifier);
                      // attempt to immediately reflect bri/color/speed
                      final colList = (p.json['seg'] is List && (p.json['seg'] as List).isNotEmpty) ? ((p.json['seg'] as List).first as Map)['col'] : null;
                      if (colList is List && colList.isNotEmpty && colList.first is List) {
                        final c = colList.first as List;
                        if (c.length >= 3) {
                          notifier.setColor(Color.fromARGB(255, (c[0] as num).toInt(), (c[1] as num).toInt(), (c[2] as num).toInt()));
                        }
                      }
                      final bri = p.json['bri'];
                      if (bri is int) notifier.setBrightness(bri);
                      final seg = p.json['seg'];
                      if (seg is List && seg.isNotEmpty && seg.first is Map) {
                        final sx = (seg.first as Map)['sx'];
                        if (sx is int) notifier.setSpeed(sx);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${p.name}')));
                      }
                    },
                    child: const Text('Apply'),
                  ),
                );
              },
            ),
          ] else ...[
            Text(
              'To sync scenes across devices, connect Firebase in the Firebase panel (left sidebar). After connecting, I can wire Firebase Auth and Firestore here.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ]
        ]),
      ),
    );
  }

  void _showBackendPrompt(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.cloud_sync, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Text('Connect Firebase', style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 12),
          Text('Open the Firebase panel in Dreamflow (left sidebar) and complete setup. Then ask me to integrate Firebase Auth and Firestore for Scenes/Presets.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))),
        ]),
      ),
    );
  }
}
