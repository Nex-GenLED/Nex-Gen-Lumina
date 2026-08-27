import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_persistence.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
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
    // #91 — DISPLAY source, not device truth. Off-LAN `deviceChannelsProvider`
    // is empty (the relay has no `/json/cfg` door), which used to blank this bar
    // entirely even though every per-channel command it fires relays fine.
    // `displayChannelsProvider` falls back to the pixel map / denormalized ids /
    // live seg[] and tags which one it used.
    final display = ref.watch(displayChannelsProvider);
    final channels = display.channels;

    // Don't render anything if we have 0 or 1 channel (no filtering needed).
    if (channels.length <= 1) return const SizedBox.shrink();

    final selectedIds = ref.watch(selectedChannelIdsProvider);
    final isFiltered = selectedIds != null;

    // U1 (Bundle 3b.3b): participation is the OUTER gate; channels not in
    // the participation list are NOT selectable from the dashboard. null
    // = no preference set, all device channels eligible (backward-safe).
    final participating = ref.watch(participatingChannelIdsProvider);
    final participatingSet = participating?.toSet();

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
              _buildHeader(context, channels, selectedIds, hasZoneNames,
                  participatingSet, display.source),
              if (_expanded)
                _buildChannelChips(context, channels, selectedIds, zoneLabels, hasZoneNames, participatingSet),
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
    Set<int>? participatingSet,
    DisplayChannelSource source,
  ) {
    final isFiltered = selectedIds != null;
    final selectedCount = isFiltered ? selectedIds.length : channels.length;
    final totalCount = channels.length;
    final zoneTerm = hasZoneNames ? 'Zones' : 'Channels';

    // #95 item 3 — "All Zones" was a LIE whenever participation narrowed.
    // `effectiveChannelIdsProvider` intersects the selector with participation
    // even in the null-selector "All" case, so an apply labelled "All Zones"
    // could silently skip a channel: no seg emitted for it, no warning, and a
    // cheerful "Applied: <design>" afterwards. The count below is the truth the
    // apply path already acts on.
    final excludedCount = participatingSet == null
        ? 0
        : channels.where((c) => !participatingSet.contains(c.id)).length;

    final String label;
    if (!isFiltered || selectedCount == totalCount) {
      label = excludedCount == 0
          ? 'All $zoneTerm'
          : 'All $zoneTerm · ${totalCount - excludedCount} of $totalCount in shows';
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
            // #91 — provenance badge. The chips are fully interactive from a
            // cached list (per-channel writes carry `id` + intent only, never
            // bounds, so they are correct regardless of where the list came
            // from), but the user is told the SHAPE is remembered rather than
            // measured — which is what makes a wrong channel count explicable
            // instead of alarming.
            if (source != DisplayChannelSource.live)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'CACHED',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.55),
                      letterSpacing: 0.8,
                    ),
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
    Set<int>? participatingSet,
  ) {
    final isAllMode = selectedIds == null;

    // P1-43: live per-channel lit state for the per-chip power icons.
    final powerStates =
        ref.watch(channelPowerStatesProvider).valueOrNull ?? const <int, bool>{};

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
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
              // Individual channel/zone chips. Non-participating channels (U1)
              // render disabled — selecting one would be a silent no-op, since
              // participation is the outer gate. Tapping one instead offers to
              // change participation itself (see onTap below).
              for (final ch in channels)
                Builder(builder: (_) {
                  final isParticipating = participatingSet == null ||
                      participatingSet.contains(ch.id);
                  final chOn = powerStates[ch.id];
                  return _buildChip(
                    label: zoneLabels[ch.id] ?? ch.name,
                    selected: isAllMode || selectedIds.contains(ch.id),
                    disabled: !isParticipating,
                    // #95 item 1 — THE RE-ENTRY PATH. This used to be null,
                    // which is what made participation a one-way door: every
                    // writer of participation was a re-derivation from roofline
                    // geometry, so a channel the default policy excluded
                    // ("traced but no isPrimary segment") could not be put back
                    // from anywhere in the app. Tapping a dimmed chip now opens
                    // the include-back sheet, which writes a real explicit set.
                    onTap: isParticipating
                        ? () => _toggleChannel(ch.id, channels, selectedIds)
                        : () => _promptIncludeBack(
                              context,
                              ch,
                              zoneLabels[ch.id] ?? ch.name,
                              channels,
                              participatingSet,
                            ),
                    channelColor: kChannelColors[ch.id % kChannelColors.length],
                    channelOn: chOn,
                    // #95 — POWER IS NEVER GATED ON PARTICIPATION.
                    //
                    // Participation scopes SHOWS ("not in my shows"); it is not
                    // a claim that the channel is absent, and it must not remove
                    // manual control of hardware the user owns. This callback
                    // used to be null for a non-participating channel, and the
                    // icon was hidden as well — so such a channel had NO
                    // affordance at all.
                    //
                    // Harmless while those channels stayed lit. #89 made the
                    // full partition interactive, so an unused channel now
                    // correctly goes `{id, on:false}` — and a DARK channel with
                    // no control reads as a channel that is GONE, recoverable
                    // only by applying another design that targets it.
                    onPowerTap: () async {
                      final newOn = !(chOn ?? false);
                      await ref
                          .read(wledStateProvider.notifier)
                          .setChannelPower(ch.id, newOn);
                      // Refresh the chips from the device's new seg[] state.
                      ref.invalidate(channelPowerStatesProvider);
                    },
                  );
                }),
            ],
          ),
          // Reset affordance — only when an explicit set is in force. Without
          // it, include-back would be a one-way door in the opposite
          // direction: no screen could hand control back to the roofline.
          if (ref.watch(participationOverrideProvider) != null) ...[
            const SizedBox(height: 8),
            _buildOverrideFooter(context),
          ],
          const SizedBox(height: 10),
          // Recovery affordance: from a partial-on state (e.g. "1 on, 2 off")
          // there was no way to get every channel back on — and a colour
          // change only hit the lit channels because the selector filtered to
          // them. "All Channels On" re-selects all channels AND powers each
          // one on, so a subsequent colour change affects everything again.
          _buildAllOnButton(),
        ],
      ),
    );
  }

  Widget _buildAllOnButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _turnAllOn,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: NexGenPalette.cyan.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lightbulb_outline,
                size: 16,
                color: NexGenPalette.cyan,
              ),
              const SizedBox(width: 8),
              Text(
                'All Channels On',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: NexGenPalette.cyan,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Recover from a partial-on channel state: clear the selector filter so
  /// every channel is selected again (subsequent colour/effect changes hit
  /// all channels), then power every channel on through the EXISTING apply
  /// path. The empty seg template carries no fx/col, so applyChannelFilter
  /// just adds `{id, on:true}` per channel — lighting each one without
  /// altering its current colour. Honors participation (applyToDevice targets
  /// effectiveChannelIds), matching the rest of the dashboard.
  Future<void> _turnAllOn() async {
    ref.read(selectedChannelIdsProvider.notifier).state = null;
    await ref.read(wledStateProvider.notifier).applyToDevice(
      {
        'on': true,
        'seg': [<String, dynamic>{}],
      },
      labelHint: null,
    );
  }

  /// Footer shown while an explicit participation set is in force.
  Widget _buildOverrideFooter(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.push_pin_outlined,
            size: 13, color: Colors.white.withValues(alpha: 0.45)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Custom show channels',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ),
        GestureDetector(
          onTap: _resetOverride,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              'Reset',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: NexGenPalette.cyan.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Hand participation back to the roofline. Clearing the override does NOT
  /// restore the previous exclusion by itself — the next resolve re-derives
  /// from geometry, which is the correct authority once the user stops
  /// overriding it.
  Future<void> _resetOverride() async {
    await saveParticipationOverride(null);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Show channels reset to your roofline design'),
      ),
    );
  }

  /// The include-back sheet, shown when a user taps a dimmed chip.
  ///
  /// It explains the state before offering the action, because "dimmed" alone
  /// has never told the user WHY — and the two things it could mean ("this
  /// channel isn't on my roof" vs "skip it this once") have opposite fixes.
  /// This wording commits to the first, which is what participation was built
  /// to express; the per-apply meaning belongs to the selector filter, which is
  /// transient and already works.
  Future<void> _promptIncludeBack(
    BuildContext context,
    DeviceChannel channel,
    String label,
    List<DeviceChannel> channels,
    Set<int>? participatingSet,
  ) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label isn\'t in your shows',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Patterns, colours and designs skip this channel — including '
                'when you apply to All Zones. Its power switch still works.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This came from your roofline design, where this channel has no '
                'primary run. If it should be in your shows, include it here.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: const Text('Include in Shows',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: Text(
                    'Leave it out',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;
    await _includeChannel(channel.id, channels, participatingSet);
  }

  /// Write the explicit set: everything that participates today, plus the
  /// channel being re-included.
  ///
  /// Seeding from the CURRENT participation rather than from all device
  /// channels is deliberate — including one channel back must not silently
  /// re-include every other channel the roofline excluded.
  Future<void> _includeChannel(
    int channelId,
    List<DeviceChannel> channels,
    Set<int>? participatingSet,
  ) async {
    final base = participatingSet ?? channels.map((c) => c.id).toSet();
    final next = (Set<int>.from(base)..add(channelId)).toList()..sort();
    await saveParticipationOverride(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Channel added to your shows')),
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
    required VoidCallback? onTap,
    Color? channelColor,
    bool disabled = false,
    // P1-43: per-channel power. When [channelOn] is non-null a power icon is
    // rendered as a SEPARATE tap target ([onPowerTap]) — it never overloads the
    // selection tap. Reflects live seg[] state (channelPowerStatesProvider).
    bool? channelOn,
    VoidCallback? onPowerTap,
  }) {
    // Non-participating chips render dimmed and are not SELECTABLE for design
    // targeting — participation is the outer gate and `effectiveChannelIdsProvider`
    // would filter them out anyway, so offering selection would be a silent
    // no-op. Tapping one now opens the include-back sheet (#95 item 1), which
    // changes participation itself rather than pretending to select.
    //
    // #95 — "not in shows" MUST NOT read as "not there", and must never remove
    // the power control:
    //   • no strikethrough. Strikethrough is the typography of DELETED, and
    //     this channel is neither deleted nor absent — it is simply out of
    //     scope for shows. Dimming carries "out of scope" without claiming
    //     the channel is gone.
    //   • the power icon renders regardless of [disabled] (see [onPowerTap]),
    //     so every channel the device reports can always be woken by hand.
    final effectiveColor = disabled
        ? Colors.white.withValues(alpha: 0.25)
        : (channelColor ?? NexGenPalette.cyan);
    final showSelected = selected && !disabled;

    return Opacity(
      opacity: disabled ? 0.5 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: showSelected
                ? effectiveColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: showSelected
                  ? effectiveColor
                  : Colors.white.withValues(alpha: disabled ? 0.1 : 0.2),
              width: showSelected ? 1.5 : 1.0,
              style: disabled ? BorderStyle.solid : BorderStyle.solid,
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
                    color: disabled
                        ? Colors.white.withValues(alpha: 0.2)
                        : (showSelected
                            ? channelColor
                            : channelColor.withValues(alpha: 0.4)),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: showSelected ? FontWeight.w600 : FontWeight.w400,
                  color: disabled
                      ? Colors.white38
                      : (showSelected ? effectiveColor : Colors.white54),
                  // #95: never lineThrough — see the note in this method.
                ),
              ),
              // Per-channel power toggle (P1-43): a distinct tap target so the
              // chip body still selects/filters. Lit = cyan, dark = dim.
              //
              // #95: NOT gated on [disabled]. The `&& !disabled` that used to be
              // here is what left a dark, non-participating channel with no
              // control of any kind — the release-blocking lockout.
              if (channelOn != null && onPowerTap != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onPowerTap,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.power_settings_new,
                      size: 14,
                      color: channelOn
                          ? NexGenPalette.cyan
                          : Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ],
            ],
          ),
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
