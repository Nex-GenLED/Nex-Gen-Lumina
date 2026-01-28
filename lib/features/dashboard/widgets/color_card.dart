import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/widgets/neon_color_wheel.dart';

/// Card with color wheel for primary color selection
class ColorCard extends ConsumerWidget {
  final Color color;

  const ColorCard({super.key, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(wledStateProvider.notifier);
    final state = ref.watch(wledStateProvider);
    final connected = state.connected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Primary Color', style: Theme.of(context).textTheme.titleMedium)),
            Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)])),
          ]),
          const SizedBox(height: 12),
          Center(
            child: IgnorePointer(
              ignoring: !connected,
              child: Opacity(
                opacity: connected ? 1 : 0.5,
                child: NeonColorWheel(size: 220, color: color, onChanged: notifier.setColor),
              ),
            ),
          ),
          if (state.supportsRgbw) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('Warm White', style: Theme.of(context).textTheme.labelLarge)),
              Text('${state.warmWhite}', style: Theme.of(context).textTheme.labelMedium),
            ]),
            Slider(
              value: state.warmWhite.toDouble(),
              min: 0,
              max: 255,
              onChanged: connected ? (v) => notifier.setWarmWhite(v.round()) : null,
              activeColor: NexGenPalette.cyan,
              inactiveColor: Colors.white.withValues(alpha: 0.2),
            ),
          ],
        ]),
      ),
    );
  }
}
