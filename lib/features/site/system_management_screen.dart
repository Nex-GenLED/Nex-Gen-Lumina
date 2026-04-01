import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/widgets/premium_card.dart';
import 'dart:ui';

/// System Management hub: manage controllers, link devices, and configure hardware
class SystemManagementScreen extends ConsumerWidget {
  const SystemManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: GlassAppBar(
          title: const Text('System Management'),
          bottom: TabBar(
            isScrollable: true,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: const [
              Tab(icon: Icon(Icons.router_outlined, color: NexGenPalette.cyan), text: 'Controllers'),
              Tab(icon: Icon(Icons.layers_outlined, color: NexGenPalette.cyan), text: 'My Lights'),
              Tab(icon: Icon(Icons.cloud_outlined, color: NexGenPalette.cyan), text: 'Remote Access'),
              Tab(icon: Icon(Icons.tune_outlined, color: NexGenPalette.cyan), text: 'Mode'),
            ],
          ),
        ),
        body: const TabBarView(children: [
          _MyControllersTab(),
          _ZonesChannelsTab(),
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
      padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context)),
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

                  return _ControllerTile(
                    controller: c,
                    isActive: isActive,
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
                    onDetails: () => _showDetails(context, ref, c),
                    onDelete: () => _confirmDelete(context, c, deleteController),
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
            _DetailRow(label: 'Wi-Fi Configured', value: (item.wifiConfigured == true || item.ip.isNotEmpty) ? 'Yes' : 'No'),
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

/// Unified My Lights tab — inline areas, hardware config, effects, roofline
class _ZonesChannelsTab extends ConsumerStatefulWidget {
  const _ZonesChannelsTab();

  @override
  ConsumerState<_ZonesChannelsTab> createState() => _ZonesChannelsTabState();
}

class _ZonesChannelsTabState extends ConsumerState<_ZonesChannelsTab> {
  @override
  Widget build(BuildContext context) {
    final hwConfigAsync = ref.watch(deviceHardwareConfigProvider);
    final show2D = ref.watch(show2DEffectsProvider);
    final showAudio = ref.watch(showAudioEffectsProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context)),
      child: ListView(children: [
        // ── Lighting Areas (reflects hardware channel configuration) ──
        Row(children: [
          const Icon(Icons.layers, color: NexGenPalette.cyan),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Lighting Areas', style: Theme.of(context).textTheme.titleLarge),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => ref.invalidate(deviceHardwareConfigProvider),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Your lighting channels as configured in Hardware Config.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54),
        ),
        const SizedBox(height: 12),

        hwConfigAsync.when(
          data: (config) => (config == null || config.buses.isEmpty)
              ? _buildEmptyAreas()
              : Column(
                  children: [
                    for (var i = 0; i < config.buses.length; i++)
                      _buildBusAreaTile(context, config.buses[i], i),
                  ],
                ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Failed to load channel config: $e'),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),

        const SizedBox(height: 20),

        // ── Hardware Configuration ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.build_circle_outlined, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Hardware Configuration', style: Theme.of(context).textTheme.titleMedium),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Configure controller ports, LED counts, power limits, and LED type.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.hardwareConfig),
                icon: const Icon(Icons.settings, color: Colors.black),
                label: const Text('Open Hardware Config'),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // ── Advanced Effects ──
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
                'Enable additional effect categories for specialized hardware.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
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

        // ── Roofline Setup ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.roofing, color: NexGenPalette.violet),
                const SizedBox(width: 8),
                Text('Roofline Setup', style: Theme.of(context).textTheme.titleMedium),
              ]),
              const SizedBox(height: 8),
              Text(
                'Configure your roofline layout including peaks, valleys, and segment boundaries.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
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
      ]),
    );
  }

  Widget _buildBusAreaTile(BuildContext context, WledLedBus bus, int index) {
    final subtitle = bus.len > 0
        ? '${bus.len} lights (LEDs ${bus.start + 1}\u2013${bus.start + bus.len})'
        : 'No lights configured';
    final gpioLabel = 'GPIO ${bus.pin.isNotEmpty ? bus.pin.first : "?"}';

    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.light_mode, color: NexGenPalette.cyan, size: 20),
        ),
        title: Text('Channel ${index + 1}', overflow: TextOverflow.ellipsis),
        subtitle: Text('$subtitle  \u2022  $gpioLabel'),
      ),
    );
  }

  Widget _buildEmptyAreas() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(children: [
        Icon(Icons.view_week_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'No lighting areas found. Configure your hardware to create areas.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ]),
    );
  }

}


/// Enhanced controller tile with status indicators and glassmorphic styling
class _ControllerTile extends ConsumerWidget {
  final ControllerInfo controller;
  final bool isActive;
  final VoidCallback? onTap;
  final VoidCallback onDetails;
  final VoidCallback onDelete;

  const _ControllerTile({
    required this.controller,
    required this.isActive,
    this.onTap,
    required this.onDetails,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Check connectivity status for this controller
    final connectionState = ref.watch(wledStateProvider);
    final isConnected = isActive && connectionState.connected;

    final accentColor = isActive ? NexGenPalette.cyan : NexGenPalette.violet;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? NexGenPalette.cyan.withValues(alpha: 0.4)
                  : NexGenPalette.line,
              width: isActive ? 1.5 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: NexGenPalette.cyan.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isActive
                        ? [
                            NexGenPalette.cyan.withValues(alpha: 0.1),
                            NexGenPalette.gunmetal90.withValues(alpha: 0.9),
                          ]
                        : [
                            NexGenPalette.gunmetal90.withValues(alpha: 0.85),
                            NexGenPalette.matteBlack.withValues(alpha: 0.9),
                          ],
                  ),
                ),
                child: Row(
                  children: [
                    // Icon with gradient background and status indicator
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                accentColor,
                                accentColor.withValues(alpha: 0.6),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.router,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        // Status dot
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: NexGenPalette.matteBlack,
                              shape: BoxShape.circle,
                            ),
                            child: StatusDot(
                              isOnline: isActive && isConnected,
                              size: 10,
                              animate: isActive && isConnected,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),

                    // Controller info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  controller.name ?? 'Controller',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isActive) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [NexGenPalette.cyan, NexGenPalette.cyan.withValues(alpha: 0.7)],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          // IP and network info
                          Row(
                            children: [
                              Icon(
                                Icons.lan_outlined,
                                size: 12,
                                color: NexGenPalette.textMedium,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                controller.ip,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: NexGenPalette.textMedium,
                                ),
                              ),
                              if (controller.wifiConfigured == true && controller.ssid != null) ...[
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.wifi,
                                  size: 12,
                                  color: isConnected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    controller.ssid!,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: NexGenPalette.textMedium,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // Connection status text
                          if (isActive) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  isConnected ? Icons.check_circle : Icons.error_outline,
                                  size: 12,
                                  color: isConnected ? const Color(0xFF4CAF50) : Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isConnected ? 'Connected' : 'Connecting...',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: isConnected ? const Color(0xFF4CAF50) : Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Action buttons
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Details',
                          onPressed: onDetails,
                          icon: Icon(
                            Icons.info_outline,
                            color: NexGenPalette.textMedium,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: onDelete,
                          icon: Icon(
                            Icons.delete_outline,
                            color: Colors.red.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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

/// Remote Access tab — navigates directly to the full Remote Access screen.
///
/// Previously this was a summary card + "Configure" button, which felt
/// redundant since the tab itself is already labelled "Remote Access".
/// Now it shows a slim status bar and opens the config screen immediately.
class _RemoteAccessTab extends ConsumerWidget {
  const _RemoteAccessTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivityStatus = ref.watch(wledConnectivityStatusProvider).maybeWhen(
      data: (s) => s,
      orElse: () => ConnectivityStatus.local,
    );
    final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
      data: (u) => u,
      orElse: () => null,
    );
    final isEnabled = userProfile?.remoteAccessEnabled ?? false;
    final homeSsid = userProfile?.homeSsid;
    final hasWebhookUrl = userProfile?.webhookUrl?.isNotEmpty ?? false;
    final bridgeAlive = ref.watch(bridgeReachableProvider);

    // Derive a single status line
    String statusLabel;
    Color statusColor;
    IconData statusIcon;

    if (connectivityStatus == ConnectivityStatus.local) {
      statusLabel = 'On Home Network — direct connection';
      statusColor = Colors.green;
      statusIcon = Icons.home;
    } else if (connectivityStatus == ConnectivityStatus.remote && isEnabled) {
      statusLabel = bridgeAlive == true
          ? 'Remote — bridge connected'
          : 'Remote — bridge offline';
      statusColor = bridgeAlive == true ? NexGenPalette.cyan : Colors.orange;
      statusIcon = bridgeAlive == true ? Icons.cloud_done : Icons.cloud_off;
    } else if (connectivityStatus == ConnectivityStatus.offline) {
      statusLabel = 'Offline';
      statusColor = Colors.red;
      statusIcon = Icons.signal_wifi_off;
    } else {
      statusLabel = 'Away from home — remote access disabled';
      statusColor = Colors.orange;
      statusIcon = Icons.cloud_off;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context)),
      child: ListView(children: [
        // ── Compact status banner ──────────────────────────────────────
        Card(
          color: statusColor.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    statusLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Quick-glance config chips ──────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _ConfigItem(
                  icon: Icons.power_settings_new,
                  label: 'Remote Access',
                  value: isEnabled ? 'Enabled' : 'Disabled',
                  valueColor: isEnabled ? Colors.green : Colors.grey,
                ),
                const Divider(height: 24),
                _ConfigItem(
                  icon: Icons.home,
                  label: 'Home Network',
                  value: homeSsid ?? 'Not Set',
                  valueColor: homeSsid != null ? Colors.green : Colors.orange,
                ),
                const Divider(height: 24),
                _ConfigItem(
                  icon: Icons.router_outlined,
                  label: 'Bridge / Webhook',
                  value: hasWebhookUrl ? 'Webhook' : (isEnabled ? 'ESP32 Bridge' : 'Not Set'),
                  valueColor: (isEnabled || hasWebhookUrl) ? Colors.green : Colors.orange,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ── Single action button ──────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.push(AppRoutes.remoteAccess),
            icon: const Icon(Icons.settings, color: Colors.black),
            label: Text(isEnabled ? 'Remote Access Settings' : 'Set Up Remote Access'),
          ),
        ),
      ]),
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
      padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context)),
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
