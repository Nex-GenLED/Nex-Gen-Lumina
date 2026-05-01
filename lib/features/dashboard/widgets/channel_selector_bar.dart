import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// A compact, expandable bar that lets the user choose which WLED channels
/// (hardware buses) should receive aesthetic commands (patterns, colors, effects).
///
/// **Default state:** Shows "All Zones" as a single cyan chip.
/// **Expanded state:** Shows individual zone/channel chips that can be toggled.
///
/// When a [RooflineConfiguration] exists with named segments, zone labels are
/// derived from the first segment name on each channel (e.g., "Front Eave" → "Front").
/// Otherwise falls back to generic "Channel 1", "Channel 2" labels.
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

    // Get roofline config for zone labels
    final rooflineConfig = ref.watch(currentRooflineConfigProvider).valueOrNull;

    // Build zone label map: channelIndex → display name
    final zoneLabels = <int, String>{};
    if (rooflineConfig != null && rooflineConfig.segments.isNotEmpty) {
      for (final ch in channels) {
        final segsForChannel = rooflineConfig.segmentsForChannel(ch.id);
        if (segsForChannel.isNotEmpty) {
          // Use first segment's name, truncated to first word for brevity
          final fullName = segsForChannel.first.name;
          zoneLabels[ch.id] = _shortenLabel(fullName);
        }
      }
    }

    final hasZoneNames = zoneLabels.isNotEmpty;

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
              _buildHeader(context, channels, selectedIds, hasZoneNames),
              if (_expanded)
                _buildChannelChips(context, channels, selectedIds, zoneLabels, hasZoneNames),
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
    bool hasZoneNames,
  ) {
    final isFiltered = selectedIds != null;
    final selectedCount = isFiltered ? selectedIds.length : channels.length;
    final totalCount = channels.length;
    final zoneTerm = hasZoneNames ? 'Zones' : 'Channels';

    final String label;
    if (!isFiltered || selectedCount == totalCount) {
      label = 'All $zoneTerm';
    } else {
      label = '$selectedCount of $totalCount $zoneTerm';
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
    Map<int, String> zoneLabels,
    bool hasZoneNames,
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
            label: hasZoneNames ? 'All Zones' : 'All',
            selected: isAllMode,
            onTap: () {
              ref.read(selectedChannelIdsProvider.notifier).state = null;
            },
          ),
          // Individual channel/zone chips
          for (final ch in channels)
            _buildChip(
              label: zoneLabels[ch.id] ?? ch.name,
              selected: isAllMode || selectedIds.contains(ch.id),
              onTap: () => _toggleChannel(ch.id, channels, selectedIds),
              channelColor: kChannelColors[ch.id % kChannelColors.length],
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
      // From "All" mode, tapping a channel narrows the selection to JUST
      // that channel. Previously this removed the tapped channel from a
      // fresh all-set — which made the OTHER channels light up while the
      // tapped one stayed off, the opposite of user intent. The "All"
      // chip remains the way to return to unified control.
      ref.read(selectedChannelIdsProvider.notifier).state = {channelId};
    } else if (currentSelection.contains(channelId)) {
      final newSet = Set<int>.from(currentSelection)..remove(channelId);
      if (newSet.isEmpty) return;
      ref.read(selectedChannelIdsProvider.notifier).state = newSet;
    } else {
      final newSet = Set<int>.from(currentSelection)..add(channelId);
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
    Color? channelColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (channelColor ?? NexGenPalette.cyan).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? (channelColor ?? NexGenPalette.cyan)
                : Colors.white.withValues(alpha: 0.2),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (channelColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: selected ? channelColor : channelColor.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? (channelColor ?? NexGenPalette.cyan)
                    : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shorten a segment label for chip display.
  /// "Front Eave" → "Front", "3rd Car Garage" → "3rd Car Garage" (already short enough)
  static String _shortenLabel(String fullName) {
    // If the name contains a common suffix, strip it
    const suffixes = ['Eave', 'Rake', 'Fascia', 'Soffit', 'Run', 'Peak', 'Ridge'];
    for (final suffix in suffixes) {
      if (fullName.endsWith(' $suffix') && fullName.length > suffix.length + 2) {
        return fullName.substring(0, fullName.length - suffix.length - 1).trim();
      }
    }
    // Truncate if too long
    if (fullName.length > 16) return '${fullName.substring(0, 14)}...';
    return fullName;
  }
}
