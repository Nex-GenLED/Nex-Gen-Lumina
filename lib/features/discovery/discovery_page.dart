import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/permissions/welcome_wizard.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// Device discovery page for finding WLED controllers on the network
class DiscoveryPage extends ConsumerWidget {
  const DiscoveryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On first launch, redirect into Welcome Wizard
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Avoid redirect loops if we're not on discovery route
      final loc = GoRouter.of(context).routerDelegate.currentConfiguration.uri.toString();
      if (loc != AppRoutes.discovery) return;
      final completed = await isWelcomeCompleted();
      if (!completed && context.mounted) {
        context.go(AppRoutes.welcome);
      }
    });
    final asyncDevices = ref.watch(discoveredDevicesProvider);
    final selectedIp = ref.watch(selectedDeviceIpProvider);

    ref.listen<String?>(selectedDeviceIpProvider, (prev, next) {
      if (next != null && ModalRoute.of(context)?.isCurrent == true) {
        Future.microtask(() => context.go(AppRoutes.dashboard));
      }
    });

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Lumina'),
        actions: [
          IconButton(
            tooltip: 'Device Setup',
            icon: const Icon(Icons.bluetooth_searching),
            onPressed: () => context.push(AppRoutes.deviceSetup),
          ),
        ],
      ),
      // Show a subtle action to open settings even from welcome flow
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Device Discovery', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const _NeonDot(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  asyncDevices.isLoading ? 'Scanning local network for WLED devices…' : (selectedIp != null ? 'Connected to $selectedIp' : 'Select a device to continue'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              if (asyncDevices.isLoading) const SizedBox(width: 12),
              if (asyncDevices.isLoading) const CircularProgressIndicator(strokeWidth: 2),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: asyncDevices.when(
              data: (devices) {
                if (devices.isEmpty) {
                  return _EmptyState(onRetry: () => ref.refresh(discoveredDevicesProvider));
                }
                return ListView.separated(
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final d = devices[i];
                    final ip = d.address.address;
                    final isSel = ip == selectedIp;
                    return ListTile(
                      title: Text(d.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(ip),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isSel ? NexGenPalette.cyan : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2))),
                      tileColor: isSel ? NexGenPalette.cyan.withValues(alpha: 0.06) : null,
                      trailing: Icon(Icons.chevron_right, color: isSel ? NexGenPalette.cyan : Theme.of(context).colorScheme.onSurfaceVariant),
                      onTap: () => ref.read(selectedDeviceIpProvider.notifier).state = ip,
                    );
                  },
                );
              },
              error: (e, st) => _ErrorState(error: '$e', onRetry: () => ref.refresh(discoveredDevicesProvider)),
              loading: () => const SizedBox.shrink(),
            ),
          )
        ]),
      ),
    );
  }
}

/// Animated neon dot indicator
class _NeonDot extends StatelessWidget {
  const _NeonDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: NexGenPalette.cyan,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1)],
      ),
    );
  }
}

/// Empty state shown when no devices are found
class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wifi_find, size: 64, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 16),
        Text('No WLED devices found', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Make sure your device is powered on and connected to the same Wi-Fi network', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]),
    );
  }
}

/// Error state shown when discovery fails
class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 16),
        Text('Discovery failed', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(error, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]),
    );
  }
}
