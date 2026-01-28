import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';

/// Card for navigating to zone configuration
class ZonesCard extends StatelessWidget {
  const ZonesCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.view_week_rounded, color: NexGenPalette.cyan),
          const SizedBox(width: 12),
          Expanded(child: Text('Zones & Segments', style: Theme.of(context).textTheme.titleMedium)),
          FilledButton.icon(onPressed: () => context.push(AppRoutes.wledZones), icon: const Icon(Icons.tune), label: const Text('Configure'))
        ]),
      ),
    );
  }
}
