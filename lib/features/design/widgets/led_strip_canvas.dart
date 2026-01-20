import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Interactive LED strip visualization for the Design Studio.
/// Displays channels as horizontal LED strips that users can tap/drag to paint colors.
class LedStripCanvas extends ConsumerStatefulWidget {
  const LedStripCanvas({super.key});

  @override
  ConsumerState<LedStripCanvas> createState() => _LedStripCanvasState();
}

class _LedStripCanvasState extends ConsumerState<LedStripCanvas> {
  int? _dragStartLed;
  int? _dragCurrentLed;
  int? _dragChannelId;

  @override
  Widget build(BuildContext context) {
    final design = ref.watch(currentDesignProvider);
    final selectedChannelId = ref.watch(selectedChannelIdProvider);

    if (design == null) {
      return const Center(
        child: Text('No design loaded'),
      );
    }

    final includedChannels = design.channels.where((ch) => ch.included).toList();

    if (includedChannels.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lightbulb_outline, size: 48, color: Colors.white54),
            SizedBox(height: 12),
            Text(
              'No channels included',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Enable channels below to start designing',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.lightbulb, color: NexGenPalette.cyan, size: 20),
                const SizedBox(width: 8),
                Text(
                  'LED Preview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  'Tap or drag to paint',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          // LED strips
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (final channel in includedChannels)
                    _ChannelStrip(
                      channel: channel,
                      isSelected: selectedChannelId == channel.channelId,
                      dragStart: _dragChannelId == channel.channelId ? _dragStartLed : null,
                      dragEnd: _dragChannelId == channel.channelId ? _dragCurrentLed : null,
                      onTap: () {
                        ref.read(selectedChannelIdProvider.notifier).state = channel.channelId;
                      },
                      onLedTap: (ledIndex) {
                        _paintSingleLed(channel.channelId, ledIndex);
                      },
                      onDragStart: (ledIndex) {
                        setState(() {
                          _dragChannelId = channel.channelId;
                          _dragStartLed = ledIndex;
                          _dragCurrentLed = ledIndex;
                        });
                        ref.read(selectedChannelIdProvider.notifier).state = channel.channelId;
                      },
                      onDragUpdate: (ledIndex) {
                        setState(() {
                          _dragCurrentLed = ledIndex;
                        });
                      },
                      onDragEnd: () {
                        if (_dragStartLed != null && _dragCurrentLed != null && _dragChannelId != null) {
                          _paintLedRange(_dragChannelId!, _dragStartLed!, _dragCurrentLed!);
                        }
                        setState(() {
                          _dragStartLed = null;
                          _dragCurrentLed = null;
                          _dragChannelId = null;
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _paintSingleLed(int channelId, int ledIndex) {
    final color = ref.read(selectedColorProvider);
    final white = ref.read(selectedWhiteProvider);
    ref.read(currentDesignProvider.notifier).paintLeds(channelId, ledIndex, ledIndex, color, white: white);
    ref.read(recentColorsProvider.notifier).addColor(color);
  }

  void _paintLedRange(int channelId, int start, int end) {
    final color = ref.read(selectedColorProvider);
    final white = ref.read(selectedWhiteProvider);
    final actualStart = start < end ? start : end;
    final actualEnd = start < end ? end : start;
    ref.read(currentDesignProvider.notifier).paintLeds(channelId, actualStart, actualEnd, color, white: white);
    ref.read(recentColorsProvider.notifier).addColor(color);
  }
}

class _ChannelStrip extends StatelessWidget {
  final ChannelDesign channel;
  final bool isSelected;
  final int? dragStart;
  final int? dragEnd;
  final VoidCallback onTap;
  final void Function(int ledIndex) onLedTap;
  final void Function(int ledIndex) onDragStart;
  final void Function(int ledIndex) onDragUpdate;
  final VoidCallback onDragEnd;

  const _ChannelStrip({
    required this.channel,
    required this.isSelected,
    this.dragStart,
    this.dragEnd,
    required this.onTap,
    required this.onLedTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final ledCount = channel.ledCount > 0 ? channel.ledCount : 30; // Default for visualization

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? NexGenPalette.cyan.withOpacity(0.1) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? NexGenPalette.cyan.withOpacity(0.5) : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Channel header
            Row(
              children: [
                Text(
                  channel.channelName,
                  style: TextStyle(
                    color: isSelected ? NexGenPalette.cyan : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$ledCount LEDs',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                if (channel.effectId > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: NexGenPalette.violet.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      kDesignEffects[channel.effectId] ?? 'Effect ${channel.effectId}',
                      style: const TextStyle(
                        color: NexGenPalette.violet,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // LED strip visualization
            LayoutBuilder(
              builder: (context, constraints) {
                return _LedStrip(
                  ledCount: ledCount,
                  colorGroups: channel.colorGroups,
                  maxWidth: constraints.maxWidth,
                  dragStart: dragStart,
                  dragEnd: dragEnd,
                  onLedTap: onLedTap,
                  onDragStart: onDragStart,
                  onDragUpdate: onDragUpdate,
                  onDragEnd: onDragEnd,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LedStrip extends StatelessWidget {
  final int ledCount;
  final List<LedColorGroup> colorGroups;
  final double maxWidth;
  final int? dragStart;
  final int? dragEnd;
  final void Function(int ledIndex) onLedTap;
  final void Function(int ledIndex) onDragStart;
  final void Function(int ledIndex) onDragUpdate;
  final VoidCallback onDragEnd;

  const _LedStrip({
    required this.ledCount,
    required this.colorGroups,
    required this.maxWidth,
    this.dragStart,
    this.dragEnd,
    required this.onLedTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  Color _getColorForLed(int ledIndex) {
    for (final group in colorGroups) {
      if (ledIndex >= group.startLed && ledIndex <= group.endLed) {
        return group.flutterColor;
      }
    }
    return Colors.white;
  }

  bool _isInDragRange(int ledIndex) {
    if (dragStart == null || dragEnd == null) return false;
    final start = dragStart! < dragEnd! ? dragStart! : dragEnd!;
    final end = dragStart! < dragEnd! ? dragEnd! : dragStart!;
    return ledIndex >= start && ledIndex <= end;
  }

  @override
  Widget build(BuildContext context) {
    // Calculate LED size based on available width
    // Show at most 50 LEDs per row for readability
    final ledsPerRow = (ledCount > 50 ? 50 : ledCount).clamp(1, ledCount);
    final ledSize = ((maxWidth - 8) / ledsPerRow).clamp(8.0, 24.0);
    final rows = (ledCount / ledsPerRow).ceil();

    return GestureDetector(
      onPanStart: (details) {
        final ledIndex = _getLedIndexFromPosition(details.localPosition, ledSize, ledsPerRow);
        if (ledIndex != null && ledIndex < ledCount) {
          onDragStart(ledIndex);
        }
      },
      onPanUpdate: (details) {
        final ledIndex = _getLedIndexFromPosition(details.localPosition, ledSize, ledsPerRow);
        if (ledIndex != null && ledIndex >= 0 && ledIndex < ledCount) {
          onDragUpdate(ledIndex);
        }
      },
      onPanEnd: (_) => onDragEnd(),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: List.generate(ledCount, (index) {
          final color = _getColorForLed(index);
          final isInDrag = _isInDragRange(index);

          return GestureDetector(
            onTap: () => onLedTap(index),
            child: Container(
              width: ledSize - 2,
              height: ledSize - 2,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
                border: isInDrag
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  int? _getLedIndexFromPosition(Offset position, double ledSize, int ledsPerRow) {
    final col = (position.dx / ledSize).floor();
    final row = (position.dy / ledSize).floor();
    if (col < 0 || col >= ledsPerRow || row < 0) return null;
    return row * ledsPerRow + col;
  }
}
