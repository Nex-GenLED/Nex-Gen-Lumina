// lib/features/schedule/widgets/channel_scope_picker.dart
//
// Scheduling V3 D4 — the channel picker shared by both schedule editors.
//
// ── THE ONE SENTENCE THAT MATTERS ─────────────────────────────────────────────
//
// "Other channels will turn off during this schedule."
//
// That is not a softening of the feature; it is the feature's actual behaviour,
// and it is stated because the alternative is not available. U-7 proved `psave`
// snapshots every segment, so a timer-fired preset cannot say "leave the others
// as they were" — a scoped ON has to name every excluded segment `on:false`.
// The editor says so rather than letting a customer discover it after dark.
//
// A scoped OFF is different and does NOT darken anything else (it names only
// its own segments), which is why the note is phrased around "during this
// schedule" rather than "always".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/theme.dart';

/// What the picker hands back. Both null = all channels.
typedef ChannelScopeSelection = ({List<int>? channels, String? controllerId});

/// All-channels vs a subset of the SELECTED controller's channels.
///
/// P5 decision: no multi-controller picker in this version. The picker offers
/// the currently selected controller's channels and stamps that controller's
/// id, so a scoped item is always unambiguous about which `hw.led.ins` its bus
/// indices refer to. A home with more than one controller sees the controller
/// NAME on scoped rows and nothing else changes.
class ChannelScopePicker extends ConsumerWidget {
  final List<int>? channels;
  final ValueChanged<ChannelScopeSelection> onChanged;

  const ChannelScopePicker({
    super.key,
    required this.channels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceChannels = ref.watch(deviceChannelsProvider);
    final controllerId = ref.watch(selectedControllerIdProvider);

    // A single-channel (or unknown) controller has nothing to scope. Rendering
    // a picker there would offer a choice with no effect.
    if (deviceChannels.length <= 1) return const SizedBox.shrink();

    final selected = channels?.toSet();
    final isAll = selected == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tune_rounded, size: 18, color: NexGenPalette.cyan),
            const SizedBox(width: 10),
            const Text('Channels',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(
              label: 'All channels',
              selected: isAll,
              onTap: () => onChanged((channels: null, controllerId: null)),
            ),
            for (final ch in deviceChannels)
              _Chip(
                label: _labelFor(ch),
                selected: !isAll && selected.contains(ch.id),
                onTap: () => _toggle(ch.id, deviceChannels, controllerId),
              ),
          ],
        ),
        if (!isAll) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 13, color: NexGenPalette.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Other channels will turn off during this schedule.',
                  style: TextStyle(
                    fontSize: 11,
                    color: NexGenPalette.amber,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _toggle(int id, List<DeviceChannel> all, String? controllerId) {
    // From "All", the first tap means "only this one" — not "all except this",
    // which is what a naive toggle-from-full-set would produce.
    final next = channels == null ? <int>{id} : channels!.toSet();
    if (channels != null) {
      if (!next.remove(id)) next.add(id);
    }

    // Deselecting the last channel, or selecting every one of them, both mean
    // "all channels". Storing an empty list would be an item that fires nowhere,
    // and storing the full set would be a scope that pins itself to a controller
    // for no reason.
    if (next.isEmpty || next.length == all.length) {
      onChanged((channels: null, controllerId: null));
      return;
    }
    final sorted = next.toList()..sort();
    onChanged((channels: sorted, controllerId: controllerId));
  }

  static String _labelFor(DeviceChannel ch) => ch.name;
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? NexGenPalette.cyan.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? NexGenPalette.cyan : NexGenPalette.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
          ),
        ),
      ),
    );
  }
}

/// Short scope label for a timeline row or detail sheet, e.g. `"Channel 2"` or
/// `"2 of 4 channels"`. Null when the item is all-channel — the common case
/// must add no chrome at all.
String? channelScopeLabel(List<int>? channels, List<DeviceChannel> all) {
  if (channels == null) return null;
  if (channels.isEmpty) return 'No channels';
  if (channels.length == 1) {
    for (final c in all) {
      if (c.id == channels.first) return c.name;
    }
    return 'Channel ${channels.first + 1}';
  }
  if (all.isNotEmpty && channels.length == all.length) return null;
  return '${channels.length}'
      '${all.isEmpty ? '' : ' of ${all.length}'} channels';
}
