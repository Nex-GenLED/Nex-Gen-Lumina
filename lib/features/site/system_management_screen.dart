import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// System Management hub: manage controllers, link devices, and configure hardware
class SystemManagementScreen extends ConsumerWidget {
  const SystemManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: GlassAppBar(
          title: const Text('System Management'),
          bottom: TabBar(
            isScrollable: true,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: const [
              Tab(icon: Icon(Icons.router_outlined, color: NexGenPalette.cyan), text: 'Controllers'),
              Tab(icon: Icon(Icons.layers_outlined, color: NexGenPalette.cyan), text: 'Zones & Channels'),
              Tab(icon: Icon(Icons.build_circle_outlined, color: NexGenPalette.cyan), text: 'Hardware'),
              Tab(icon: Icon(Icons.cloud_outlined, color: NexGenPalette.cyan), text: 'Remote Access'),
              Tab(icon: Icon(Icons.tune_outlined, color: NexGenPalette.cyan), text: 'Mode'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _MyControllersTab(),
          _ZonesChannelsTab(),
          _HardwareTab(),
          _RemoteAccessTab(),
          _ModeTab(),
        ]),
      ),
    );
  }
}

/// Simplified tab showing user's saved controllers with manage/delete/activate options
class _MyControllersTab extends ConsumerWidget {
  const _MyControllersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncControllers = ref.watch(controllersStreamProvider);
    final selectedIp = ref.watch(selectedDeviceIpProvider);
    final deleteController = ref.watch(deleteControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: asyncControllers.when(
        data: (items) {
          if (items.isEmpty) {
            return _EmptyControllersState(onAdd: () => context.push(AppRoutes.wifiConnect));
          }
          return Column(children: [
            // Header with Add Controller button
            Row(children: [
              Expanded(
                child: Text(
                  'Manage your controllers',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.wifiConnect),
                icon: const Icon(Icons.add, color: Colors.black),
                label: const Text('Add Controller'),
              ),
            ]),
            const SizedBox(height: 16),

            // Controllers list
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final c = items[i];
                  final isActive = c.ip == selectedIp;

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.router_outlined,
                        color: isActive ? NexGenPalette.cyan : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.name ?? 'Controller',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: NexGenPalette.cyan,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('IP: ${c.ip}', overflow: TextOverflow.ellipsis),
                          if (c.wifiConfigured == true && c.ssid != null)
                            Text(
                              'Network: ${c.ssid}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      isThreeLine: c.wifiConfigured == true && c.ssid != null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Details',
                            onPressed: () => _showDetails(context, ref, c),
                            icon: const Icon(Icons.info_outline),
                          ),
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: () => _confirmDelete(context, c, deleteController),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      onTap: isActive
                          ? null
                          : () {
                              ref.read(selectedDeviceIpProvider.notifier).state = c.ip;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${c.name ?? "Controller"} is now active'),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                    ),
                  );
                },
              ),
            ),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, st) => Center(child: Text('Failed to load controllers: $e')),
      ),
    );
  }

  void _showDetails(BuildContext context, WidgetRef ref, ControllerInfo item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.name ?? 'Controller Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(label: 'Name', value: item.name ?? 'Unnamed'),
            _DetailRow(label: 'IP Address', value: item.ip),
            _DetailRow(label: 'Serial', value: item.serial ?? 'N/A'),
            if (item.ssid != null) _DetailRow(label: 'Wi-Fi Network', value: item.ssid!),
            _DetailRow(label: 'Wi-Fi Configured', value: item.wifiConfigured == true ? 'Yes' : 'No'),
            if (item.createdAt != null)
              _DetailRow(label: 'Added', value: _formatDate(item.createdAt!)),
            if (item.updatedAt != null)
              _DetailRow(label: 'Last Updated', value: _formatDate(item.updatedAt!)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          if (ref.read(selectedDeviceIpProvider) != item.ip)
            FilledButton(
              onPressed: () {
                ref.read(selectedDeviceIpProvider.notifier).state = item.ip;
                Navigator.of(ctx).pop();
              },
              child: const Text('Set as Active'),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ControllerInfo item,
    Future<bool> Function(String) deleteController,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Controller'),
        content: Text(
          'Remove ${item.name ?? 'this controller'} from your account?\n\n'
          'This will delete all saved settings for this controller.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      final res = await deleteController(item.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res ? 'Controller removed successfully' : 'Failed to remove controller',
            ),
            backgroundColor: res ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

/// Centralized Zones & Channels management tab
class _ZonesChannelsTab extends ConsumerWidget {
  const _ZonesChannelsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        // Zone Control Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.layers, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Text('Zone Control', style: Theme.of(context).textTheme.titleLarge),
              ]),
              const SizedBox(height: 8),
              Text(
                'Select and manage your lighting channels. Rename channels, select multiple for batch control, and organize your lighting zones.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.wledZones),
                icon: const Icon(Icons.tune, color: Colors.black),
                label: const Text('Manage Channels'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Roofline Configuration Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.roofing, color: NexGenPalette.violet),
                const SizedBox(width: 8),
                Text('Roofline Setup', style: Theme.of(context).textTheme.titleLarge),
              ]),
              const SizedBox(height: 8),
              Text(
                'Configure your roofline layout including peaks, valleys, and segment boundaries for precise lighting control.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push(AppRoutes.rooflineSetupWizard),
                    icon: const Icon(Icons.auto_fix_high, color: Colors.black),
                    label: const Text('Setup Wizard'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.rooflineEditor),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Layout'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Segment Setup Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.straighten, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Text('Segment Configuration', style: Theme.of(context).textTheme.titleLarge),
              ]),
              const SizedBox(height: 8),
              Text(
                'Define pixel ranges for each segment of your lighting installation. Map physical LED positions to logical zones.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.segmentSetup),
                icon: const Icon(Icons.view_column, color: Colors.black),
                label: const Text('Configure Segments'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Info Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.info_outline, color: NexGenPalette.textMedium),
                const SizedBox(width: 8),
                Text('Understanding Zones & Channels', style: Theme.of(context).textTheme.titleMedium),
              ]),
              const SizedBox(height: 12),
              Text(
                '• Channels: Physical LED ports on your controller (up to 8 on Dig-Octa)\n'
                '• Segments: Logical groups of pixels within channels\n'
                '• Zones: Named areas combining multiple segments (e.g., "Front Peak", "Garage")\n'
                '• Roofline: The overall layout defining how your house is outlined',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _HardwareTab extends ConsumerWidget {
  const _HardwareTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show2D = ref.watch(show2DEffectsProvider);
    final showAudio = ref.watch(showAudioEffectsProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.build_circle_outlined, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Text('Hardware Configuration', style: Theme.of(context).textTheme.titleLarge),
              ]),
              const SizedBox(height: 8),
              Text('Configure Dig‑Octa ports, LED counts, power limits, and LED type. Apply and reboot to take effect.', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.hardwareConfig),
                icon: const Icon(Icons.settings, color: Colors.black),
                label: const Text('Open Hardware Configuration'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        // Advanced Effects Settings Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.auto_awesome, color: NexGenPalette.violet),
                const SizedBox(width: 8),
                Expanded(child: Text('Advanced Effects', style: Theme.of(context).textTheme.titleMedium)),
              ]),
              const SizedBox(height: 8),
              Text(
                'Enable additional effect categories for specialized hardware setups.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              // 2D Matrix Effects Toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: show2D ? NexGenPalette.cyan.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('2D', style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: show2D ? NexGenPalette.cyan : Colors.grey,
                  )),
                ),
                title: const Text('2D Matrix Effects'),
                subtitle: const Text('For LED matrix/grid installations'),
                value: show2D,
                activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.5),
                activeThumbColor: NexGenPalette.cyan,
                onChanged: (v) => ref.read(show2DEffectsProvider.notifier).state = v,
              ),
              const Divider(height: 24),
              // Audio-Reactive Effects Toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: showAudio ? NexGenPalette.violet.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.music_note,
                    color: showAudio ? NexGenPalette.violet : Colors.grey,
                    size: 20,
                  ),
                ),
                title: const Text('Audio-Reactive Effects'),
                subtitle: const Text('Requires microphone/line-in on controller'),
                value: showAudio,
                activeTrackColor: NexGenPalette.violet.withValues(alpha: 0.5),
                activeThumbColor: NexGenPalette.violet,
                onChanged: (v) => ref.read(showAudioEffectsProvider.notifier).state = v,
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.hub_outlined, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Text('Tips', style: Theme.of(context).textTheme.titleMedium),
              ]),
              const SizedBox(height: 8),
              Text('• Enable only the ports you use.\n• RGBW requires SK6812 strips.\n• Save & Reboot after changes.', style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyControllersState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyControllersState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.router_outlined, color: NexGenPalette.violet, size: 64),
        const SizedBox(height: 16),
        Text('No Controllers Yet', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Add your first Nex-Gen controller to get started with smart lighting control.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, color: Colors.black),
          label: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('Add Your First Controller'),
          ),
        ),
      ]),
    );
  }
}

/// Remote Access tab - quick overview with link to full settings page
class _RemoteAccessTab extends ConsumerWidget {
  const _RemoteAccessTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
      data: (u) => u,
      orElse: () => null,
    );
    final connectivityStatus = ref.watch(wledConnectivityStatusProvider).maybeWhen(
      data: (s) => s,
      orElse: () => ConnectivityStatus.local,
    );

    final isEnabled = userProfile?.remoteAccessEnabled ?? false;
    final hasWebhookUrl = userProfile?.webhookUrl?.isNotEmpty ?? false;
    final homeSsid = userProfile?.homeSsid;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        // Status Card
        _buildStatusCard(context, connectivityStatus, isEnabled),
        const SizedBox(height: 16),

        // Configuration Status
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.settings_outlined, color: NexGenPalette.cyan),
                    const SizedBox(width: 8),
                    Text('Configuration', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 16),
                _ConfigItem(
                  icon: Icons.power_settings_new,
                  label: 'Remote Access',
                  value: isEnabled ? 'Enabled' : 'Disabled',
                  valueColor: isEnabled ? Colors.green : Colors.grey,
                ),
                const Divider(height: 24),
                _ConfigItem(
                  icon: Icons.link,
                  label: 'Webhook URL',
                  value: hasWebhookUrl ? 'Configured' : 'Not Set',
                  valueColor: hasWebhookUrl ? Colors.green : Colors.orange,
                ),
                const Divider(height: 24),
                _ConfigItem(
                  icon: Icons.home,
                  label: 'Home Network',
                  value: homeSsid ?? 'Not Set',
                  valueColor: homeSsid != null ? Colors.green : Colors.orange,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Configure Button
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_outlined, color: NexGenPalette.cyan),
                    const SizedBox(width: 8),
                    Text('Remote Access Settings', style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Configure your webhook URL and home network to control your lights from anywhere.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push(AppRoutes.remoteAccess),
                    icon: const Icon(Icons.settings, color: Colors.black),
                    label: const Text('Configure Remote Access'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Info Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: NexGenPalette.violet),
                    const SizedBox(width: 8),
                    Text('How It Works', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Remote access allows you to control your WLED lights when you\'re away from home. '
                  'Commands are sent through a secure cloud relay to your home network.\n\n'
                  'Requirements:\n'
                  '• Dynamic DNS service (e.g., DuckDNS)\n'
                  '• Port forwarding configured on your router\n'
                  '• Home network saved in the app',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildStatusCard(BuildContext context, ConnectivityStatus status, bool isEnabled) {
    IconData icon;
    Color color;
    String title;
    String subtitle;

    switch (status) {
      case ConnectivityStatus.local:
        icon = Icons.home;
        color = Colors.green;
        title = 'On Home Network';
        subtitle = 'Using direct local connection';
        break;
      case ConnectivityStatus.remote:
        if (isEnabled) {
          icon = Icons.cloud;
          color = NexGenPalette.cyan;
          title = 'Remote Mode Active';
          subtitle = 'Using cloud relay';
        } else {
          icon = Icons.cloud_off;
          color = Colors.orange;
          title = 'Away from Home';
          subtitle = 'Remote access not enabled';
        }
        break;
      case ConnectivityStatus.offline:
        icon = Icons.signal_wifi_off;
        color = Colors.red;
        title = 'Offline';
        subtitle = 'No network connection';
        break;
    }

    return Card(
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  const _ConfigItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: valueColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

/// Mode selection tab - Residential vs Commercial
class _ModeTab extends ConsumerWidget {
  const _ModeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(siteModeProvider);
    final isRes = mode == SiteMode.residential;
    final isCom = mode == SiteMode.commercial;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        // Mode Selection Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.tune, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Text('Installation Mode', style: Theme.of(context).textTheme.titleLarge),
              ]),
              const SizedBox(height: 8),
              Text(
                'Choose the mode that best fits your lighting installation.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),

              // Mode Toggle Buttons
              Row(children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => ref.read(siteModeProvider.notifier).state = SiteMode.residential,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: isRes ? NexGenPalette.cyan : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isRes ? NexGenPalette.cyan : Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.home_outlined, color: isRes ? Colors.black : Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          'Residential',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: isRes ? Colors.black : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => ref.read(siteModeProvider.notifier).state = SiteMode.commercial,
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: isCom ? NexGenPalette.cyan : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isCom ? NexGenPalette.cyan : Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.apartment_outlined, color: isCom ? Colors.black : Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text(
                          'Commercial',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: isCom ? Colors.black : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),

        // Residential Info Card
        Card(
          color: isRes ? NexGenPalette.cyan.withValues(alpha: 0.1) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.home, color: isRes ? NexGenPalette.cyan : Colors.grey),
                const SizedBox(width: 8),
                Text('Residential Mode', style: Theme.of(context).textTheme.titleMedium),
                if (isRes) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: NexGenPalette.cyan,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              Text(
                '• Optimized for single homes\n'
                '• One primary controller with optional linked controllers\n'
                '• All controllers act as a unified system\n'
                '• Simplified interface focused on ease of use',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Commercial Info Card
        Card(
          color: isCom ? NexGenPalette.cyan.withValues(alpha: 0.1) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.apartment, color: isCom ? NexGenPalette.cyan : Colors.grey),
                const SizedBox(width: 8),
                Text('Commercial Mode', style: Theme.of(context).textTheme.titleMedium),
                if (isCom) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: NexGenPalette.cyan,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              Text(
                '• Designed for large installations & businesses\n'
                '• Group multiple controllers into named Zones\n'
                '• Set primary controllers with secondary members\n'
                '• Enable DDP Sync for multi-controller coordination\n'
                '• Advanced zone-based scheduling & control',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
