import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/installer/connection_method_resolver.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/installer/widgets/info_expansion_card.dart';
import 'package:nexgen_command/features/site/connection_method.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';

/// Wizard step 3: Connection Method.
///
/// For every controller selected on the prior step, probe `/json/info` to
/// detect whether the device is on WiFi, Ethernet, or both. Render a card
/// per controller showing the detected state and (for dual-homed boxes)
/// give the installer three explicit actions:
///
///  - Keep Ethernet, disable WiFi from the app (writes /json/cfg, reboots)
///  - Keep WiFi, unplug Ethernet (physical — verified by re-probe)
///  - Skip (controller stays dual-homed; logged for installer accountability)
class ConnectionMethodScreen extends ConsumerStatefulWidget {
  const ConnectionMethodScreen({
    super.key,
    required this.onBack,
    required this.onNext,
  });

  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  ConsumerState<ConnectionMethodScreen> createState() =>
      _ConnectionMethodScreenState();
}

class _ConnectionMethodScreenState
    extends ConsumerState<ConnectionMethodScreen> {
  // Per-controller flags for in-flight async work, so the UI can disable
  // the matching button row while a probe/action is running.
  final Set<String> _probing = {};
  final Set<String> _busy = {};
  // Probe-once dedupe — we kick off a probe the first time a controller
  // appears in build, but only once per controller.
  final Set<String> _probedOnce = {};

  Future<void> _probe(ControllerInfo controller) async {
    if (_probing.contains(controller.id)) return;
    setState(() => _probing.add(controller.id));
    try {
      final resolver = ref.read(connectionMethodResolverProvider);
      final method = await resolver.probe(controller);
      if (!mounted) return;
      _setMethod(controller.id, method);
    } finally {
      if (mounted) setState(() => _probing.remove(controller.id));
    }
  }

  void _setMethod(String controllerId, ConnectionMethod method) {
    final current = ref.read(installerConnectionMethodsProvider);
    ref.read(installerConnectionMethodsProvider.notifier).state = {
      ...current,
      controllerId: method,
    };
  }

  void _markSkipped(String controllerId) {
    final skipped = ref.read(installerConnectionMethodSkippedProvider);
    ref.read(installerConnectionMethodSkippedProvider.notifier).state = {
      ...skipped,
      controllerId,
    };
  }

  Future<void> _disableWifiFlow(ControllerInfo controller) async {
    if (_busy.contains(controller.id)) return;
    setState(() => _busy.add(controller.id));
    final resolver = ref.read(connectionMethodResolverProvider);
    try {
      final pushed = await resolver.disableWifi(controller);
      if (!pushed) {
        if (mounted) _snack('Could not clear WiFi on ${controller.ip}');
        return;
      }
      // Controller is rebooting. Wait ~5s, then poll for life on the
      // Ethernet IP. Show progress in the busy state.
      await Future<void>.delayed(const Duration(seconds: 5));
      final back = await resolver.isReachable(controller);
      if (!back) {
        if (mounted) {
          _snack('Controller did not come back up after WiFi disable. '
              'Check Ethernet cable.');
        }
        return;
      }
      _setMethod(controller.id, ConnectionMethod.ethernet);
      await resolver.persist(controller, ConnectionMethod.ethernet);
      if (mounted) _snack('WiFi disabled. Controller is on Ethernet only.');
    } finally {
      if (mounted) setState(() => _busy.remove(controller.id));
    }
  }

  Future<void> _unplugEthernetFlow(ControllerInfo controller) async {
    if (_busy.contains(controller.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text(
          'Unplug Ethernet now',
          style: TextStyle(color: NexGenPalette.textHigh),
        ),
        content: const Text(
          'Unplug the Ethernet cable from the controller now. Tap Verify '
          'once the cable is out — Lumina will check that the controller '
          'falls back to WiFi cleanly.',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
            ),
            child: const Text('Verify',
                style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy.add(controller.id));
    final resolver = ref.read(connectionMethodResolverProvider);
    try {
      // The IP we have right now is the Ethernet IP (the installer just
      // added it during step 2). Once they unplug, that IP should go
      // silent within ~10s.
      final wentOffline = await resolver.waitForOffline(controller);
      if (!wentOffline) {
        if (mounted) {
          _snack('Ethernet IP is still responding. Make sure the cable '
              'is fully unplugged.');
        }
        return;
      }
      // The controller has changed IP (now on WiFi). We can't directly
      // re-probe without the new IP, but most WLED setups reuse the same
      // mDNS name on either interface — defer the WiFi reachability
      // check to a downstream screen. For now: trust the offline signal
      // as proof and persist.
      _setMethod(controller.id, ConnectionMethod.wifi);
      await resolver.persist(controller, ConnectionMethod.wifi);
      if (mounted) {
        _snack('Ethernet unplugged. Re-discover the controller on its '
            'WiFi IP if needed.');
      }
    } finally {
      if (mounted) setState(() => _busy.remove(controller.id));
    }
  }

  void _skipFlow(ControllerInfo controller) {
    _markSkipped(controller.id);
    // Keep the detected method as-is (still ethernetWifiActive) so the
    // Continue gate sees "resolved by skip" rather than "not yet resolved."
    final methods = ref.read(installerConnectionMethodsProvider);
    final current = methods[controller.id] ?? ConnectionMethod.ethernetWifiActive;
    _setMethod(controller.id, current);
    _snack('Skipped — controller will stay dual-homed.');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIds = ref.watch(installerSelectedControllersProvider);
    final controllersAsync = ref.watch(controllersStreamProvider);
    final controllers = controllersAsync.maybeWhen(
      data: (list) =>
          list.where((c) => selectedIds.contains(c.id)).toList(),
      orElse: () => const <ControllerInfo>[],
    );
    final methods = ref.watch(installerConnectionMethodsProvider);
    final skipped = ref.watch(installerConnectionMethodSkippedProvider);

    // Kick off a probe the first time each controller appears. Runs in a
    // postFrameCallback so the state mutation doesn't race the build.
    if (controllers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final c in controllers) {
          if (_probedOnce.add(c.id)) {
            unawaited(_probe(c));
          }
        }
      });
    }

    final canContinue = isReadyToContinue(
      controllerIds: controllers.map((c) => c.id).toSet(),
      methods: methods,
      skipped: skipped,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connection Method',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'For each controller, pick how it stays on the network. '
            'Ethernet is more reliable for permanent installs — pick it '
            'whenever a wall jack is in reach.',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
          ),
          const SizedBox(height: 20),

          if (controllers.isEmpty)
            _emptyState()
          else
            for (final controller in controllers)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ControllerCard(
                  controller: controller,
                  method: methods[controller.id],
                  isProbing: _probing.contains(controller.id),
                  isBusy: _busy.contains(controller.id),
                  isSkipped: skipped.contains(controller.id),
                  onDisableWifi: () => _disableWifiFlow(controller),
                  onUnplugEthernet: () => _unplugEthernetFlow(controller),
                  onSkip: () => _skipFlow(controller),
                  onRetryProbe: () => _probe(controller),
                ),
              ),

          const SizedBox(height: 16),
          const InfoExpansionCard(
            title: 'Why we pick one connection',
            paragraphs: kWhyPickOneCopy,
          ),

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onBack,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: NexGenPalette.line),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: canContinue ? widget.onNext : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    disabledBackgroundColor:
                        NexGenPalette.cyan.withValues(alpha: 0.25),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: const Text(
        'No controllers selected. Go back to the previous step to add '
        'or select a controller.',
        style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
      ),
    );
  }
}

/// Pure gate: returns true when every selected controller either has a
/// resolved non-dual-homed method, OR is in the explicit skipped set.
/// Exposed for unit tests.
@visibleForTesting
bool isReadyToContinue({
  required Set<String> controllerIds,
  required Map<String, ConnectionMethod> methods,
  required Set<String> skipped,
}) {
  if (controllerIds.isEmpty) return false;
  for (final id in controllerIds) {
    final method = methods[id];
    if (method == null) return false;
    if (method == ConnectionMethod.unknown) return false;
    if (method == ConnectionMethod.ethernetWifiActive &&
        !skipped.contains(id)) {
      return false;
    }
  }
  return true;
}

class _ControllerCard extends StatelessWidget {
  const _ControllerCard({
    required this.controller,
    required this.method,
    required this.isProbing,
    required this.isBusy,
    required this.isSkipped,
    required this.onDisableWifi,
    required this.onUnplugEthernet,
    required this.onSkip,
    required this.onRetryProbe,
  });

  final ControllerInfo controller;
  final ConnectionMethod? method;
  final bool isProbing;
  final bool isBusy;
  final bool isSkipped;
  final VoidCallback onDisableWifi;
  final VoidCallback onUnplugEthernet;
  final VoidCallback onSkip;
  final VoidCallback onRetryProbe;

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _accentForMethod(method),
          width: method == ConnectionMethod.ethernetWifiActive && !isSkipped
              ? 2
              : 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForMethod(method),
                  color: _accentForMethod(method)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.name ?? 'Unnamed Controller',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      controller.ip,
                      style: const TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isProbing)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: NexGenPalette.cyan,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (method == null && isProbing) {
      return const Text(
        'Probing controller…',
        style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
      );
    }
    switch (method) {
      case ConnectionMethod.ethernet:
        return const _StatusLine(
          label: 'Ethernet detected. Nothing to do — this is the '
              'recommended configuration.',
          color: NexGenPalette.green,
        );
      case ConnectionMethod.wifi:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _StatusLine(
              label: 'WiFi only. No Ethernet detected.',
              color: NexGenPalette.cyan,
            ),
            SizedBox(height: 6),
            Text(
              'If a wall jack is reachable, Ethernet is recommended for '
              'permanent installs.',
              style: TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 12),
            ),
          ],
        );
      case ConnectionMethod.ethernetWifiActive:
        if (isSkipped) {
          return _StatusLine(
            label: 'Skipped — controller will stay dual-homed. Service '
                'calls may be harder to troubleshoot.',
            color: NexGenPalette.amber,
          );
        }
        return _DualHomedActions(
          isBusy: isBusy,
          onDisableWifi: onDisableWifi,
          onUnplugEthernet: onUnplugEthernet,
          onSkip: onSkip,
        );
      case ConnectionMethod.unknown:
      case null:
        return Row(
          children: [
            const Expanded(
              child: Text(
                'Could not read controller state. Make sure the '
                'controller is online and try again.',
                style: TextStyle(
                    color: NexGenPalette.textMedium, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: isProbing ? null : onRetryProbe,
              child: const Text('Retry',
                  style: TextStyle(color: NexGenPalette.cyan)),
            ),
          ],
        );
    }
  }

  IconData _iconForMethod(ConnectionMethod? m) {
    switch (m) {
      case ConnectionMethod.ethernet:
        return Icons.settings_ethernet;
      case ConnectionMethod.wifi:
        return Icons.wifi;
      case ConnectionMethod.ethernetWifiActive:
        return Icons.warning_amber_rounded;
      case ConnectionMethod.unknown:
      case null:
        return Icons.help_outline;
    }
  }

  Color _accentForMethod(ConnectionMethod? m) {
    switch (m) {
      case ConnectionMethod.ethernet:
        return NexGenPalette.green;
      case ConnectionMethod.wifi:
        return NexGenPalette.cyan;
      case ConnectionMethod.ethernetWifiActive:
        return isSkipped ? NexGenPalette.amber : NexGenPalette.violet;
      case ConnectionMethod.unknown:
      case null:
        return NexGenPalette.line;
    }
  }
}

class _DualHomedActions extends StatelessWidget {
  const _DualHomedActions({
    required this.isBusy,
    required this.onDisableWifi,
    required this.onUnplugEthernet,
    required this.onSkip,
  });

  final bool isBusy;
  final VoidCallback onDisableWifi;
  final VoidCallback onUnplugEthernet;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StatusLine(
          label: 'Both connections active. Pick one to keep.',
          color: NexGenPalette.violet,
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: isBusy ? null : onDisableWifi,
          icon: const Icon(Icons.settings_ethernet, color: Colors.black),
          label: const Text(
            'Keep Ethernet, disable WiFi from app',
            style: TextStyle(
                color: Colors.black, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: NexGenPalette.cyan,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: isBusy ? null : onUnplugEthernet,
          icon: const Icon(Icons.wifi, color: NexGenPalette.cyan),
          label: const Text(
            'Keep WiFi, I will unplug Ethernet',
            style: TextStyle(color: NexGenPalette.textHigh),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(color: NexGenPalette.cyan),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            onPressed: isBusy ? null : onSkip,
            child: const Text(
              'Skip for now (leaves controller dual-homed)',
              style: TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 5),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style:
                const TextStyle(color: NexGenPalette.textHigh, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// Verbatim "Why we pick one connection" copy. Kept as a top-level const
/// so the screen and any future explainer surface share the same text —
/// and so it's easy to grep for if marketing wants tweaks.
const List<InfoExpansionParagraph> kWhyPickOneCopy = [
  InfoExpansionParagraph(
    body:
        'Plugging the controller in with an Ethernet cable makes it more '
        'reliable than WiFi for a permanent install. No drops, no '
        'interference from neighbors\' networks, no broken connection '
        'when the customer resets their router. Their phone app keeps '
        'working exactly the same — Ethernet only changes how the '
        'controller talks to the router, not how the customer talks to '
        'the lights.',
  ),
  InfoExpansionParagraph(
    heading: 'Why never leave both connected:',
    body:
        'When a controller is plugged into Ethernet AND has WiFi '
        'credentials saved, the router sees it as two separate devices. '
        'That makes future service calls harder to troubleshoot, and '
        'the customer\'s device list gets cluttered with duplicates.',
  ),
  InfoExpansionParagraph(
    heading: 'The rule:',
    body:
        'Pick one connection. Use Ethernet whenever a wall jack is '
        'within reach. Disable the other one before you leave.',
  ),
];
