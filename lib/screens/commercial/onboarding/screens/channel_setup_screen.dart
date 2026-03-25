import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/commercial/channel_role.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';

class ChannelSetupScreen extends ConsumerStatefulWidget {
  const ChannelSetupScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  ConsumerState<ChannelSetupScreen> createState() => _ChannelSetupScreenState();
}

class _ChannelSetupScreenState extends ConsumerState<ChannelSetupScreen> {
  @override
  void initState() {
    super.initState();
    // Seed channel configs from hardware if not already populated.
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedIfNeeded());
  }

  void _seedIfNeeded() {
    final draft = ref.read(commercialOnboardingProvider);
    if (draft.channelConfigs.isNotEmpty) return;
    final channels = ref.read(deviceChannelsProvider);
    if (channels.isEmpty) return;

    final configs = channels.map((ch) {
      return ChannelRoleConfig(
        channelId: ch.id.toString(),
        friendlyName: ch.name,
        role: ChannelRoleType.interior,
        coveragePolicy: CoveragePolicy.smartFill,
        daylightSuppression: false,
        daylightMode: DaylightMode.softDim,
      );
    }).toList();

    ref.read(commercialOnboardingProvider.notifier).update(
          (d) => d.copyWith(channelConfigs: configs),
        );
  }

  void _updateConfig(int index, ChannelRoleConfig updated) {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final list = List<ChannelRoleConfig>.from(d.channelConfigs);
      list[index] = updated;
      return d.copyWith(channelConfigs: list);
    });
  }

  void _showRolePicker(int index, ChannelRoleConfig config) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _RolePickerSheet(
        currentRole: config.role,
        onSelect: (role) {
          Navigator.pop(ctx);
          _updateConfig(
            index,
            config.copyWith(
              role: role,
              coveragePolicy: role.defaultCoveragePolicy,
              daylightSuppression: role.defaultDaylightSuppression,
            ),
          );
        },
      ),
    );
  }

  void _validate() {
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(commercialOnboardingProvider);
    final configs = draft.channelConfigs;

    if (configs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: NexGenPalette.textMedium),
            const SizedBox(height: 12),
            Text(
              'No channels detected.\nConnect to a WLED controller first.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _validate,
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
              ),
              child: const Text('Skip for now'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Channel Setup',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: NexGenPalette.textHigh),
        ),
        const SizedBox(height: 4),
        Text(
          'Assign a role to each lighting channel.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: NexGenPalette.textMedium),
        ),
        const SizedBox(height: 16),

        ...configs.asMap().entries.map((e) {
          final i = e.key;
          final cfg = e.value;
          return _ChannelCard(
            config: cfg,
            onUpdateName: (name) =>
                _updateConfig(i, cfg.copyWith(friendlyName: name)),
            onTapRole: () => _showRolePicker(i, cfg),
            onCoverageChanged: (p) =>
                _updateConfig(i, cfg.copyWith(coveragePolicy: p)),
            onDaylightToggle: (v) =>
                _updateConfig(i, cfg.copyWith(daylightSuppression: v)),
          );
        }),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _validate,
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Next', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Channel card
// ---------------------------------------------------------------------------

Color _roleAccent(ChannelRoleType role) {
  switch (role) {
    case ChannelRoleType.interior:
      return const Color(0xFF448AFF); // blue
    case ChannelRoleType.outdoorFacade:
    case ChannelRoleType.patio:
    case ChannelRoleType.canopy:
      return NexGenPalette.amber; // amber
    case ChannelRoleType.windowDisplay:
    case ChannelRoleType.signage:
      return NexGenPalette.green; // green
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.config,
    required this.onUpdateName,
    required this.onTapRole,
    required this.onCoverageChanged,
    required this.onDaylightToggle,
  });

  final ChannelRoleConfig config;
  final ValueChanged<String> onUpdateName;
  final VoidCallback onTapRole;
  final ValueChanged<CoveragePolicy> onCoverageChanged;
  final ValueChanged<bool> onDaylightToggle;

  @override
  Widget build(BuildContext context) {
    final accent = _roleAccent(config.role);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Friendly name
          TextField(
            controller: TextEditingController(text: config.friendlyName),
            style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 15),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Channel name',
              hintStyle: const TextStyle(color: NexGenPalette.textMedium),
              border: InputBorder.none,
              suffixIcon: Icon(Icons.edit, size: 16, color: accent),
            ),
            onChanged: onUpdateName,
          ),
          const Divider(color: NexGenPalette.line, height: 16),

          // Role selector
          GestureDetector(
            onTap: onTapRole,
            child: Row(
              children: [
                Icon(config.role.icon, size: 20, color: accent),
                const SizedBox(width: 8),
                Text(
                  config.role.displayName,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const Spacer(),
                Icon(Icons.chevron_right, size: 18, color: NexGenPalette.textMedium),
              ],
            ),
          ),

          // Smart default chip
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 14, color: NexGenPalette.textMedium),
                const SizedBox(width: 4),
                Text(
                  'Default: ${config.role.defaultCoveragePolicy.name.replaceAll('a', ' a').replaceAll('O', ' o').trim()} coverage',
                  style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Coverage policy chips
          Text('Coverage Policy', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: CoveragePolicy.values.map((p) {
              final isActive = config.coveragePolicy == p;
              final label = p == CoveragePolicy.alwaysOn
                  ? 'Always On'
                  : p == CoveragePolicy.smartFill
                      ? 'Smart Fill'
                      : 'Scheduled Only';
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 12)),
                    if (p == CoveragePolicy.smartFill) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: NexGenPalette.cyan.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Recommended',
                            style: TextStyle(fontSize: 9, color: NexGenPalette.cyan)),
                      ),
                    ],
                  ],
                ),
                selected: isActive,
                selectedColor: accent.withValues(alpha: 0.15),
                backgroundColor: NexGenPalette.gunmetal,
                labelStyle: TextStyle(
                  color: isActive ? accent : NexGenPalette.textMedium,
                ),
                side: BorderSide(color: isActive ? accent : NexGenPalette.line),
                onSelected: (_) => onCoverageChanged(p),
              );
            }).toList(),
          ),

          // Daylight suppression (outdoor roles only)
          if (config.role.defaultDaylightSuppression) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Daylight Suppression',
                    style: TextStyle(color: NexGenPalette.textHigh, fontSize: 13),
                  ),
                ),
                Tooltip(
                  message: 'Dims or turns off outdoor lights during daylight hours',
                  child: Icon(Icons.info_outline, size: 14, color: NexGenPalette.textMedium),
                ),
                const SizedBox(width: 6),
                Switch(
                  value: config.daylightSuppression,
                  activeTrackColor: accent.withValues(alpha: 0.4),
                  thumbColor: WidgetStatePropertyAll(accent),
                  onChanged: onDaylightToggle,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Role picker bottom sheet
// ---------------------------------------------------------------------------

class _RolePickerSheet extends StatelessWidget {
  const _RolePickerSheet({required this.currentRole, required this.onSelect});
  final ChannelRoleType currentRole;
  final ValueChanged<ChannelRoleType> onSelect;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42, height: 4,
                decoration: BoxDecoration(
                  color: NexGenPalette.textMedium.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Select Channel Role',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: NexGenPalette.textHigh),
            ),
            const SizedBox(height: 12),
            ...ChannelRoleType.values.map((role) {
              final isCurrent = role == currentRole;
              final accent = _roleAccent(role);
              return ListTile(
                leading: Icon(role.icon, color: accent),
                title: Text(
                  role.displayName,
                  style: TextStyle(
                    color: isCurrent ? accent : NexGenPalette.textHigh,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                trailing: isCurrent
                    ? Icon(Icons.check_circle, color: accent, size: 20)
                    : null,
                onTap: () => onSelect(role),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
