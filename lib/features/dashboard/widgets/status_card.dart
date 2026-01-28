import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// Card displaying connection status
class StatusCard extends StatelessWidget {
  final bool connected;

  const StatusCard({super.key, required this.connected});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(connected ? Icons.wifi_tethering : Icons.wifi_off_rounded, color: connected ? NexGenPalette.cyan : Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(connected ? 'Live' : 'Disconnected', style: Theme.of(context).textTheme.titleMedium)),
        ]),
      ),
    );
  }
}
