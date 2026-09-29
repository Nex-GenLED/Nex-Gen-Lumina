import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
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
    // Row 68 (+110): "Connected to <address>" used to be printed for any
    // selection, connected or not. The header now comes from the connection.
    final connected =
        ref.watch(wledStateProvider.select((s) => s.connected));
    final header = discoveryHeader(
      scanning: asyncDevices.isLoading,
      found: asyncDevices.valueOrNull?.length ?? 0,
      selectedIp: selectedIp,
      connected: connected,
    );

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
          // ESCAPE HATCH (S-0, docs/audits Apple submission audit 2026-09-17).
          //
          // This page had no back button, no Skip and no bottom nav. It is
          // reached by context.go — from WelcomeWizard._finishWizard and from
          // signup — so the nav stack is empty and Flutter renders no
          // automatic back arrow. The only exit was selectedDeviceIpProvider
          // going non-null, which requires tapping a discovered controller.
          // With no hardware on the network that is a room with no door:
          // force-quit was the only way out.
          //
          // Going to the dashboard with no controller is a supported state,
          // not a new dead end — WledDashboardPage raises a dismissible
          // "We can't find your lights" banner whose action pushes
          // AppRoutes.wifiConnect, so setup stays one tap away. That banner
          // deliberately replaced an earlier force-navigate for the same
          // reason this button exists.
          TextButton(
            onPressed: () => context.go(AppRoutes.dashboard),
            // An app-bar action cannot wrap: the one word scales down to fit
            // the toolbar at the largest text sizes instead of being clipped.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Skip',
                style: TextStyle(color: NexGenPalette.textMedium),
              ),
            ),
          ),
        ],
      ),
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
                  header,
                  key: const ValueKey('discovery-header'),
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
                      title: Text(d.name),
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

/// The discovery status line, from what is actually known: scanning, how
/// many controllers answered, and whether the selected one is connected.
@visibleForTesting
String discoveryHeader({
  required bool scanning,
  required int found,
  required String? selectedIp,
  required bool connected,
}) {
  if (scanning) return 'Scanning local network for Lumina controllers…';
  if (selectedIp != null) {
    return connected ? 'Connected to $selectedIp' : 'Connecting to $selectedIp…';
  }
  if (found == 0) return 'No controllers found yet';
  return found == 1
      ? 'Found 1 controller — tap it to continue'
      : 'Found $found controllers — tap yours to continue';
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
        Text('No controllers found', style: Theme.of(context).textTheme.titleMedium),
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
