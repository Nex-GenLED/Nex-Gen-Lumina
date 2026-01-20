import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Effect selector widget for the Design Studio.
/// Shows effect dropdown, speed, intensity sliders, and direction toggle.
class EffectSelector extends ConsumerWidget {
  const EffectSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final design = ref.watch(currentDesignProvider);
    final selectedChannelId = ref.watch(selectedChannelIdProvider);

    if (design == null || selectedChannelId == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: const Center(
          child: Text(
            'Select a channel to configure effects',
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }

    final channel = design.channels.firstWhere(
      (ch) => ch.channelId == selectedChannelId,
      orElse: () => design.channels.first,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: NexGenPalette.violet, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Effect: ${channel.channelName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Effect dropdown
                const Text(
                  'Animation',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: channel.effectId,
                      isExpanded: true,
                      dropdownColor: NexGenPalette.gunmetal90,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      icon: const Icon(Icons.expand_more, color: Colors.white54),
                      items: kCuratedEffectIds.map((id) {
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            kDesignEffects[id] ?? 'Effect $id',
                            style: const TextStyle(color: Colors.white),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          ref.read(currentDesignProvider.notifier).setChannelEffect(selectedChannelId, value);
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Speed slider
                _EffectSlider(
                  label: 'Speed',
                  value: channel.speed,
                  icon: Icons.speed,
                  color: NexGenPalette.cyan,
                  onChanged: (value) {
                    ref.read(currentDesignProvider.notifier).setChannelSpeed(selectedChannelId, value);
                  },
                ),

                const SizedBox(height: 12),

                // Intensity slider
                _EffectSlider(
                  label: 'Intensity',
                  value: channel.intensity,
                  icon: Icons.graphic_eq,
                  color: NexGenPalette.cyan,
                  onChanged: (value) {
                    ref.read(currentDesignProvider.notifier).setChannelIntensity(selectedChannelId, value);
                  },
                ),

                const SizedBox(height: 16),

                // Direction toggle
                Row(
                  children: [
                    const Icon(Icons.swap_horiz, color: Colors.white54, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Reverse Direction',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                    Switch(
                      value: channel.reverse,
                      activeColor: NexGenPalette.cyan,
                      onChanged: (value) {
                        ref.read(currentDesignProvider.notifier).toggleChannelReverse(selectedChannelId);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EffectSlider extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final ValueChanged<int> onChanged;

  const _EffectSlider({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 18),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            activeColor: color,
            inactiveColor: Colors.white.withOpacity(0.1),
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// Quick action buttons for the selected channel
class ChannelQuickActions extends ConsumerWidget {
  const ChannelQuickActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedChannelId = ref.watch(selectedChannelIdProvider);
    final selectedColor = ref.watch(selectedColorProvider);
    final selectedWhite = ref.watch(selectedWhiteProvider);

    if (selectedChannelId == null) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _QuickActionButton(
          icon: Icons.format_color_fill,
          label: 'Fill All',
          onPressed: () {
            ref.read(currentDesignProvider.notifier).fillChannel(
              selectedChannelId,
              selectedColor,
              white: selectedWhite,
            );
          },
        ),
        _QuickActionButton(
          icon: Icons.gradient,
          label: 'Gradient',
          onPressed: () => _showGradientDialog(context, ref, selectedChannelId),
        ),
        _QuickActionButton(
          icon: Icons.refresh,
          label: 'Reset',
          onPressed: () {
            ref.read(currentDesignProvider.notifier).fillChannel(
              selectedChannelId,
              Colors.white,
            );
          },
        ),
      ],
    );
  }

  Future<void> _showGradientDialog(BuildContext context, WidgetRef ref, int channelId) async {
    final result = await showDialog<({Color startColor, Color endColor})>(
      context: context,
      builder: (ctx) => const _GradientDialog(),
    );

    if (result != null) {
      final design = ref.read(currentDesignProvider);
      if (design == null) return;

      final channel = design.channels.firstWhere((ch) => ch.channelId == channelId);
      final ledCount = channel.ledCount > 0 ? channel.ledCount : 30;

      // Create gradient color groups
      final groups = <LedColorGroup>[];
      const steps = 10; // Number of gradient steps

      for (int i = 0; i < steps; i++) {
        final t = i / (steps - 1);
        final color = Color.lerp(result.startColor, result.endColor, t)!;
        final startLed = (ledCount * i / steps).floor();
        final endLed = ((ledCount * (i + 1) / steps) - 1).floor().clamp(startLed, ledCount - 1);

        groups.add(LedColorGroup(
          startLed: startLed,
          endLed: endLed,
          color: [color.red, color.green, color.blue, 0],
        ));
      }

      final updatedChannel = channel.copyWith(colorGroups: groups);
      ref.read(currentDesignProvider.notifier).updateChannel(channelId, updatedChannel);
    }
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: BorderSide(color: Colors.white.withOpacity(0.2)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

class _GradientDialog extends StatefulWidget {
  const _GradientDialog();

  @override
  State<_GradientDialog> createState() => _GradientDialogState();
}

class _GradientDialogState extends State<_GradientDialog> {
  Color _startColor = Colors.cyan;
  Color _endColor = Colors.purple;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NexGenPalette.gunmetal90,
      title: const Text('Create Gradient', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gradient preview
          Container(
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [_startColor, _endColor]),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 16),

          // Start color row
          _GradientColorRow(
            label: 'Start',
            color: _startColor,
            onColorChanged: (c) => setState(() => _startColor = c),
          ),
          const SizedBox(height: 12),

          // End color row
          _GradientColorRow(
            label: 'End',
            color: _endColor,
            onColorChanged: (c) => setState(() => _endColor = c),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (startColor: _startColor, endColor: _endColor)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _GradientColorRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onColorChanged;

  const _GradientColorRow({
    required this.label,
    required this.color,
    required this.onColorChanged,
  });

  static const _presetColors = [
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.cyan,
    Colors.blue,
    Colors.purple,
    Colors.pink,
    Colors.white,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            children: _presetColors.map((c) {
              final isSelected = c.value == color.value;
              return GestureDetector(
                onTap: () => onColorChanged(c),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
