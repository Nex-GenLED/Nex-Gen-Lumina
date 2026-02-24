import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';

/// A compact, expandable bar that lets the user choose which WLED channels
/// (hardware buses) should receive aesthetic commands (patterns, colors, effects).
///
/// **Default state:** Shows "All Channels" as a single cyan chip.
/// **Expanded state:** Shows individual channel chips that can be toggled.
///
/// The selection is stored in [selectedChannelIdsProvider]:
/// - `null` → all channels (default, unified control)
/// - `Set<int>` → only those bus indices are targeted
class ChannelSelectorBar extends ConsumerStatefulWidget {
  const ChannelSelectorBar({super.key});

  @override
  ConsumerState<ChannelSelectorBar> createState() => _ChannelSelectorBarState();
}

class _ChannelSelectorBarState extends ConsumerState<ChannelSelectorBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(deviceChannelsProvider);

    // Don't render anything if we have 0 or 1 channel (no filtering needed).
    if (channels.length <= 1) return const SizedBox.shrink();

    final selectedIds = ref.watch(selectedChannelIdsProvider);
    final isFiltered = selectedIds != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isFiltered
                  ? NexGenPalette.cyan.withValues(alpha: 0.4)
                  : NexGenPalette.line,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header row — always visible
              _buildHeader(context, channels, selectedIds),
              // Expanded channel chips
              if (_expanded) _buildChannelChips(context, channels, selectedIds),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    List<DeviceChannel> channels,
    Set<int>? selectedIds,
  ) {
    final isFiltered = selectedIds != null;
    final selectedCount = isFiltered ? selectedIds.length : channels.length;
    final totalCount = channels.length;

    final String label;
    if (!isFiltered) {
      label = 'All Channels';
    } else if (selectedCount == totalCount) {
      label = 'All Channels';
    } else {
      label = '$selectedCount of $totalCount Channels';
    }

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.layers_outlined,
              size: 18,
              color: isFiltered ? NexGenPalette.cyan : Colors.white70,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: isFiltered ? NexGenPalette.cyan : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (isFiltered)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'FILTERED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: NexGenPalette.cyan,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: Colors.white54,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelChips(
    BuildContext context,
    List<DeviceChannel> channels,
    Set<int>? selectedIds,
  ) {
    final isAllMode = selectedIds == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          // "All" chip — resets to unified mode
          _buildChip(
            label: 'All',
            selected: isAllMode,
            onTap: () {
              ref.read(selectedChannelIdsProvider.notifier).state = null;
            },
          ),
          // Individual channel chips
          for (final ch in channels)
            _buildChip(
              label: ch.name,
              selected: isAllMode || selectedIds!.contains(ch.id),
              onTap: () => _toggleChannel(ch.id, channels, selectedIds),
            ),
        ],
      ),
    );
  }

  void _toggleChannel(
    int channelId,
    List<DeviceChannel> channels,
    Set<int>? currentSelection,
  ) {
    final allIds = channels.map((c) => c.id).toSet();

    if (currentSelection == null) {
      // Switching from all-mode: select all except the tapped one.
      final newSet = Set<int>.from(allIds)..remove(channelId);
      // Prevent empty selection.
      if (newSet.isEmpty) return;
      ref.read(selectedChannelIdsProvider.notifier).state = newSet;
    } else if (currentSelection.contains(channelId)) {
      // Deselect this channel — but ensure at least one remains.
      final newSet = Set<int>.from(currentSelection)..remove(channelId);
      if (newSet.isEmpty) return;
      ref.read(selectedChannelIdsProvider.notifier).state = newSet;
    } else {
      // Select this channel.
      final newSet = Set<int>.from(currentSelection)..add(channelId);
      // If all are now selected, switch back to all-mode for cleanliness.
      if (newSet.length == allIds.length) {
        ref.read(selectedChannelIdsProvider.notifier).state = null;
      } else {
        ref.read(selectedChannelIdsProvider.notifier).state = newSet;
      }
    }
  }

  Widget _buildChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? NexGenPalette.cyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? NexGenPalette.cyan
                : Colors.white.withValues(alpha: 0.2),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? NexGenPalette.cyan : Colors.white54,
          ),
        ),
      ),
    );
  }
}
