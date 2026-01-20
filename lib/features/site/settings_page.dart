import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/features/onboarding/feature_tour.dart';
import 'package:nexgen_command/features/properties/properties_providers.dart';
import 'package:nexgen_command/features/permissions/welcome_wizard.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _zoneNameCtrl = TextEditingController(text: 'Main Zone');
  final _memberCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '4048');
  String? _selectedZone;

  @override
  void dispose() {
    _zoneNameCtrl.dispose();
    _memberCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(siteModeProvider);
    final zones = ref.watch(zonesProvider);
    final areasList = ref.watch(propertyAreasProvider);
    _selectedZone ??= zones.isNotEmpty ? zones.first.name : null;

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(tooltip: 'Refer a Friend', icon: const Icon(Icons.card_giftcard), onPressed: () => context.push(AppRoutes.referrals)),
          IconButton(tooltip: 'Shop Nex-Gen Store', icon: const Icon(Icons.shopping_bag_outlined), onPressed: () => context.push(AppRoutes.luminaStudio)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _UserProfileEntry(),
          // Keep spacing after profile entry
          const SizedBox(height: 16),
          if (areasList.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text('System Management', style: Theme.of(context).textTheme.headlineSmall),
            ),
          ] else ...[
            const SizedBox(height: 16),
          ],
          // Mode selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mode', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _ModeToggle(
                  value: mode,
                  onChanged: (m) => ref.read(siteModeProvider.notifier).state = m,
                ),
                const SizedBox(height: 8),
                Text(
                  mode == SiteMode.residential
                      ? 'Single-controller experience optimized for homes.'
                      : 'Group multiple controllers into Zones for large sites. Add members, set a primary, and enable DDP Sync.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              ]),
            ),
          ),
          // Unified System & Device Management entry
          const SizedBox(height: 16),
          const _SystemManagementButton(),
          const SizedBox(height: 16),
          const _MyPropertiesCard(),
          const SizedBox(height: 16),
          const _VoiceAssistantsCard(),
          const SizedBox(height: 16),
          const _GrowthCard(),
          const SizedBox(height: 16),
          const _SupportResourcesCard(),
          if (mode == SiteMode.commercial) ...[
            const SizedBox(height: 16),
            _buildZonesSection(context, zones),
          ]
        ],
      ),
    );
  }

  Widget _buildZonesSection(BuildContext context, List<ZoneModel> zones) {
    final zonesNotifier = ref.read(zonesProvider.notifier);
    final ddp = ref.read(ddpSyncControllerProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.hub_outlined, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Expanded(child: Text('Zones', style: Theme.of(context).textTheme.titleMedium)),
            FilledButton.icon(
              onPressed: () {
                final name = _zoneNameCtrl.text.trim();
                if (name.isEmpty) return;
                zonesNotifier.addZone(name);
                setState(() => _selectedZone = name);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add Zone'),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _zoneNameCtrl,
                decoration: const InputDecoration(labelText: 'Zone name'),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          if (zones.isEmpty)
            Text('No zones yet. Create one to begin.', style: Theme.of(context).textTheme.bodyMedium)
          else ...[
            DropdownButton<String>(
              value: _selectedZone,
              items: [for (final z in zones) DropdownMenuItem(value: z.name, child: Text(z.name))],
              onChanged: (v) => setState(() => _selectedZone = v),
            ),
            const SizedBox(height: 12),
            if (_selectedZone != null)
              Builder(builder: (context) {
                final zone = zones.firstWhere((z) => z.name == _selectedZone);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Members', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _memberCtrl,
                        decoration: const InputDecoration(labelText: 'Add controller IP (e.g. 192.168.1.51)'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final ip = _memberCtrl.text.trim();
                        if (ip.isEmpty) return;
                        zonesNotifier.addMember(zone.name, ip);
                        _memberCtrl.clear();
                      },
                      child: const Text('Add'),
                    )
                  ]),
                  const SizedBox(height: 8),
                  Column(
                    children: [
                      for (final ip in zone.members)
                        ListTile(
                          title: Text(ip),
                          leading: IconButton(
                            onPressed: () => zonesNotifier.setPrimary(zone.name, ip),
                            icon: Icon(zone.primaryIp == ip ? Icons.star : Icons.star_border, color: NexGenPalette.violet),
                            tooltip: 'Set as Primary',
                          ),
                          trailing: IconButton(
                            onPressed: () => zonesNotifier.removeMember(zone.name, ip),
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove',
                          ),
                        )
                    ],
                  ),
                  const Divider(),
                  Text('DDP Sync', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _portCtrl,
                        decoration: const InputDecoration(labelText: 'DDP Port'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: zone.ddpSyncEnabled,
                      onChanged: (v) => zonesNotifier.setDdpEnabled(zone.name, v),
                      activeColor: NexGenPalette.cyan,
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () async {
                        final port = int.tryParse(_portCtrl.text.trim()) ?? 4048;
                        zonesNotifier.setDdpPort(zone.name, port);
                        final success = await ddp.applyZoneSync(zone.copyWith(ddpPort: port));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(success ? 'DDP/Sync configured' : 'Failed to configure DDP/Sync'),
                          ));
                        }
                      },
                      icon: const Icon(Icons.sync_alt),
                      label: const Text('Apply'),
                    )
                  ]),
                ]);
              })
          ]
        ]),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.value, required this.onChanged});
  final SiteMode value;
  final ValueChanged<SiteMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final isRes = value == SiteMode.residential;
    final isCom = value == SiteMode.commercial;
    return Row(children: [
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onChanged(SiteMode.residential),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: isRes ? NexGenPalette.cyan : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isRes ? NexGenPalette.cyan : Theme.of(context).colorScheme.outline.withOpacity(0.6)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.home_outlined, color: isRes ? Colors.black : Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('Residential', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: isRes ? Colors.black : Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onChanged(SiteMode.commercial),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: isCom ? NexGenPalette.cyan : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isCom ? NexGenPalette.cyan : Theme.of(context).colorScheme.outline.withOpacity(0.6)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.apartment_outlined, color: isCom ? Colors.black : Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text('Commercial', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: isCom ? Colors.black : Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _SystemManagementButton extends StatelessWidget {
  const _SystemManagementButton();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 56,
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.push(AppRoutes.settingsSystem),
            icon: const Icon(Icons.tune, color: Colors.black),
            label: const Text('System & Device Management'),
          ),
        ),
      ),
    );
  }
}

class _LinkedControllersTile extends ConsumerWidget {
  const _LinkedControllersTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linked = ref.watch(linkedControllersProvider);
    return Card(
      child: ListTile(
        leading: Icon(Icons.hub_outlined, color: NexGenPalette.cyan),
        title: const Text('Linked Controllers'),
        subtitle: const Text('Sync multiple devices (e.g., Roof + Patio) to act as one system.'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (linked.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.6)),
              ),
              child: Text('${linked.length} linked', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.cyan)),
            ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ]),
        onTap: () => _openMultiControllerSetupSheet(context),
      ),
    );
  }

  Future<void> _openMultiControllerSetupSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => const MultiControllerSetupSheet(),
    );
  }
}

class MultiControllerSetupSheet extends ConsumerWidget {
  const MultiControllerSetupSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controllersAsync = ref.watch(controllersStreamProvider);
    final linked = ref.watch(linkedControllersProvider);

    return DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.4,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(999))),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.hub_outlined, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Expanded(child: Text('Link Controllers', style: Theme.of(context).textTheme.titleLarge)),
          ]),
          const SizedBox(height: 6),
          Text('Choose which controllers should act as one system.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Expanded(
            child: controllersAsync.when(
              data: (list) {
                if (list.isEmpty) {
                  return ListView(controller: scrollController, children: [
                    const SizedBox(height: 12),
                    Text('No controllers found.', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Text('Add devices in Settings > Controllers & Devices.', style: Theme.of(context).textTheme.bodyMedium),
                  ]);
                }
                return ListView.builder(
                  controller: scrollController,
                  itemCount: list.length,
                  itemBuilder: (c, i) {
                    final cInfo = list[i];
                    final isChecked = linked.contains(cInfo.id);
                    final label = cInfo.name?.isNotEmpty == true ? cInfo.name! : cInfo.ip;
                    return CheckboxListTile(
                      value: isChecked,
                      onChanged: (_) => ref.read(linkedControllersProvider.notifier).toggle(cInfo.id),
                      title: Text(label),
                      subtitle: Text(cInfo.ip),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => ListView(controller: scrollController, children: [
                Text('Failed to load controllers', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(e.toString(), style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(onPressed: () => ref.read(linkedControllersProvider.notifier).clear(), icon: const Icon(Icons.clear), label: const Text('Clear')),
            const Spacer(),
            FilledButton.icon(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.check), label: const Text('Done')),
          ])
        ]),
      ),
    );
  }
}

class _ControllerHardwareTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(CupertinoIcons.device_laptop, color: NexGenPalette.violet),
        title: const Text('Controller Hardware Setup'),
        subtitle: const Text('Configure ports, pixel counts, and power.'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.6)),
            ),
            child: Text('Advanced', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.cyan)),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ]),
        onTap: () async {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Warning'),
              content: const Text('Changing pixel counts will reset your current map. Proceed?'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continue')),
              ],
            ),
          );
          if (proceed == true && context.mounted) {
            context.push(AppRoutes.hardwareConfig);
          }
        },
      ),
    );
  }
}

class _UserProfileEntry extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final email = auth.asData?.value?.email ?? 'Not signed in';
    return Card(
      child: ListTile(
        leading: Icon(Icons.person_outline, color: NexGenPalette.cyan),
          title: const Text('My Profile'),
        subtitle: Text(email),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/settings/profile'),
      ),
    );
  }
}

class _ControllersTile extends StatelessWidget {
  const _ControllersTile();
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.router_outlined, color: NexGenPalette.cyan),
        title: const Text('Controllers & Devices'),
        subtitle: const Text('Add, remove, and select your controllers.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(AppRoutes.controllersSettings),
      ),
    );
  }
}

class _SupportResourcesCard extends StatefulWidget {
  const _SupportResourcesCard();

  @override
  State<_SupportResourcesCard> createState() => _SupportResourcesCardState();
}

class _SupportResourcesCardState extends State<_SupportResourcesCard> {
  bool _isExpanded = false;

  Future<void> _openSupportSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(999)))),
              const SizedBox(height: 12),
              Row(children: [
                Icon(Icons.support_agent, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Expanded(child: Text('Contact Nex-Gen Support', style: Theme.of(context).textTheme.titleLarge)),
              ]),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Email Us'),
                subtitle: const Text('support@nex-gen.io'),
                onTap: () async {
                  final uri = Uri(scheme: 'mailto', path: 'support@nex-gen.io', queryParameters: {'subject': 'Nex-Gen Support Request'});
                  await _safeLaunch(context, uri);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: const Text('Submit Support Request'),
                subtitle: const Text('Send a request without email'),
                onTap: () async {
                  if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                  await showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                    builder: (ctx) => const SupportRequestFormSheet(),
                  );
                },
              ),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _openHelpCenter(BuildContext context) async => context.push(AppRoutes.helpCenter);

  Future<void> _openVideos(BuildContext context) async {
    final uri = Uri.parse('https://www.youtube.com/@nexgen');
    await _safeLaunch(context, uri);
  }

  Future<void> _uploadDiagnostics(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Uploading Controller Logs...'),
        content: Row(children: const [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Expanded(child: Text('Please wait while we prepare diagnostics.')),
        ]),
      ),
    );
  }

  Future<void> _simulateUpload(BuildContext context) async {
    await Future.delayed(const Duration(milliseconds: 1600));
    Navigator.of(context).pop();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Success'),
        content: const Text('Success. Ref ID: #8821.'),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _safeLaunch(BuildContext context, Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to launch: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row with expand/collapse
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.help_outline, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Expanded(child: Text('Support & Resources', style: Theme.of(context).textTheme.titleMedium)),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ]),
            ),
          ),
          // Expandable content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(children: [
                // Contact Support
                ListTile(
                  leading: Icon(Icons.support_agent, color: NexGenPalette.cyan),
                  title: const Text('Contact Nex-Gen Support'),
                  subtitle: const Text('Email us or submit an in-app request.'),
                  trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  onTap: () async => _openSupportSheet(context),
                ),
                const Divider(height: 1),
                // Troubleshooting & FAQ
                ListTile(
                  leading: const Icon(Icons.quiz),
                  title: const Text('Troubleshooting & FAQ'),
                  subtitle: const Text('Self-serve solutions for common issues.'),
                  trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  onTap: () => _openHelpCenter(context),
                ),
                const Divider(height: 1),
                // Video Tutorials
                ListTile(
                  leading: Icon(Icons.ondemand_video, color: Theme.of(context).colorScheme.error),
                  title: const Text('Video Tutorials'),
                  subtitle: const Text('Step-by-step guides for creating patterns and scheduling.'),
                  trailing: Icon(Icons.open_in_new, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  onTap: () => _openVideos(context),
                ),
                const Divider(height: 1),
                // Take the Tour
                const _TakeTourTile(),
                const Divider(height: 1),
                // Welcome Tutorial (Permissions Setup)
                const _WelcomeTutorialTile(),
                const Divider(height: 1),
                // Remote Diagnostics
                ListTile(
                  leading: Icon(Icons.medical_services_outlined, color: NexGenPalette.violet),
                  title: const Text('Remote Diagnostics (Pro)'),
                  subtitle: const Text('Upload system logs to help our team diagnose hardware issues.'),
                  trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  onTap: () async {
                    await _uploadDiagnostics(context);
                    await _simulateUpload(context);
                  },
                ),
              ]),
            ),
            crossFadeState: _isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _TakeTourTile extends ConsumerWidget {
  const _TakeTourTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [NexGenPalette.violet, NexGenPalette.cyan],
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.school, color: Colors.white, size: 18),
      ),
      title: const Text('Take the Tour'),
      subtitle: const Text('Learn about all Lumina features.'),
      trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
      onTap: () {
        // Reset tour and start it
        resetFeatureTour().then((_) {
          ref.read(featureTourProvider.notifier).startTour(getDefaultTourSteps());
          // Navigate back to home so tour can play properly
          // The tour will show as an overlay
        });
      },
    );
  }
}

class _WelcomeTutorialTile extends StatelessWidget {
  const _WelcomeTutorialTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: NexGenPalette.cyan.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.waving_hand, color: NexGenPalette.cyan, size: 18),
      ),
      title: const Text('Welcome Tutorial'),
      subtitle: const Text('Review app permissions and initial setup.'),
      trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
      onTap: () {
        // Reset and show the welcome wizard
        resetWelcomeWizard().then((_) {
          context.push(AppRoutes.welcome);
        });
      },
    );
  }
}

class _MyPropertiesCard extends ConsumerWidget {
  const _MyPropertiesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertiesAsync = ref.watch(userPropertiesProvider);
    final selectedProperty = ref.watch(selectedPropertyProvider);

    final propertyCount = propertiesAsync.whenOrNull(data: (p) => p.length) ?? 0;
    final propertyName = selectedProperty?.name ?? 'No properties';

    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [NexGenPalette.cyan, NexGenPalette.violet],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.home_work, color: Colors.white, size: 20),
        ),
        title: const Text('My Properties'),
        subtitle: Text(
          propertyCount == 0
              ? 'Add your first property'
              : propertyCount == 1
                  ? propertyName
                  : '$propertyName (+${propertyCount - 1} more)',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.6)),
              ),
              child: Text(
                'New',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.cyan),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
        onTap: () => context.push(AppRoutes.myProperties),
      ),
    );
  }
}

class _VoiceAssistantsCard extends StatelessWidget {
  const _VoiceAssistantsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [NexGenPalette.violet, NexGenPalette.cyan],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.mic, color: Colors.white, size: 20),
        ),
        title: const Text('Voice Assistants'),
        subtitle: const Text('Set up Siri, Google, or Alexa control'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.6)),
              ),
              child: Text(
                'New',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.cyan),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
        onTap: () => context.push(AppRoutes.voiceAssistants),
      ),
    );
  }
}

class _GrowthCard extends StatelessWidget {
  const _GrowthCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.trending_up, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Expanded(child: Text("Let's Grow", style: Theme.of(context).textTheme.titleMedium)),
          ]),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.card_giftcard, color: NexGenPalette.cyan),
            title: const Text('Refer a Friend'),
            subtitle: const Text('Share Lumina and earn rewards.'),
            trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
            onTap: () => context.push(AppRoutes.referrals),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.shopping_bag_outlined, color: NexGenPalette.violet),
            title: const Text('Shop Nex-Gen Store'),
            subtitle: const Text('Design upgrades in the virtual showroom.'),
            trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
            onTap: () => context.push(AppRoutes.luminaStudio),
          ),
        ]),
      ),
    );
  }
}

class SupportRequestFormSheet extends ConsumerStatefulWidget {
  const SupportRequestFormSheet({super.key});

  @override
  ConsumerState<SupportRequestFormSheet> createState() => _SupportRequestFormSheetState();
}

class _SupportRequestFormSheetState extends ConsumerState<SupportRequestFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _category = 'Technical issue';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authStateProvider).asData?.value;
    if (user != null) {
      _emailCtrl.text = user.email ?? '';
      _nameCtrl.text = user.displayName ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      final authUser = ref.read(authStateProvider).asData?.value;
      final now = DateTime.now();
      await FirebaseFirestore.instance.collection('support_requests').add({
        'user_id': authUser?.uid,
        'email': _emailCtrl.text.trim(),
        'name': _nameCtrl.text.trim(),
        'subject': _subjectCtrl.text.trim(),
        'category': _category,
        'message': _messageCtrl.text.trim(),
        'status': 'open',
        'created_at': Timestamp.fromDate(now),
        'platform': Theme.of(context).platform.name,
        'app': 'Lumina',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Support request submitted. We\'ll be in touch soon.')));
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      debugPrint('Failed to submit support request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: bottomInset + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.3), borderRadius: BorderRadius.circular(999)))),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.assignment_outlined, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Expanded(child: Text('Submit Support Request', style: Theme.of(context).textTheme.titleLarge)),
          ]),
          const SizedBox(height: 6),
          Text('Prefer not to email? Send your request here, and our team will follow up.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name (optional)'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email (optional)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    DropdownMenuItem(value: 'Technical issue', child: Text('Technical issue')),
                    DropdownMenuItem(value: 'Billing', child: Text('Billing')),
                    DropdownMenuItem(value: 'Feature request', child: Text('Feature request')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? 'Technical issue'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _subjectCtrl,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Subject is required' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _messageCtrl,
                  decoration: const InputDecoration(labelText: 'Message'),
                  minLines: 5,
                  maxLines: 10,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Message is required' : null,
                ),
                const SizedBox(height: 16),
                Row(children: [
                  TextButton(onPressed: _isSubmitting ? null : () => Navigator.of(context).maybePop(), child: const Text('Cancel')),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                    label: const Text('Submit'),
                  ),
                ])
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
