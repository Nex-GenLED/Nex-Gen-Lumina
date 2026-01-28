import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

/// Card with power, brightness, and speed controls
class ControlsCard extends ConsumerWidget {
  final dynamic state;

  const ControlsCard({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(wledStateProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Power', style: Theme.of(context).textTheme.titleMedium)),
            Switch(
              value: state.isOn,
              onChanged: state.connected ? (v) => notifier.togglePower(v) : null,
              activeColor: NexGenPalette.cyan,
            )
          ]),
          const SizedBox(height: 12),
          Text('Brightness', style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: state.brightness.toDouble(),
            min: 0,
            max: 255,
            onChanged: state.connected ? (v) => notifier.setBrightness(v.round()) : null,
            activeColor: NexGenPalette.cyan,
            inactiveColor: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 8),
          Text('Speed', style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: state.speed.toDouble(),
            min: 0,
            max: 255,
            onChanged: state.connected ? (v) => notifier.setSpeed(v.round()) : null,
            activeColor: NexGenPalette.violet,
            inactiveColor: Colors.white.withValues(alpha: 0.2),
          ),
        ]),
      ),
    );
  }
}
