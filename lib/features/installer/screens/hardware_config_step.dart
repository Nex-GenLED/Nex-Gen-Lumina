import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/hardware_config_screen.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';
import 'package:nexgen_command/models/controller_type.dart';
import 'package:nexgen_command/theme.dart';

/// Wizard step: lets the installer apply the Nex-Gen Standard hardware
/// profile to the selected controller, drop into the full custom editor,
/// or skip and configure later. Without this step the installer had to
/// log in as the customer to reach hardware bus settings.
class HardwareConfigStep extends ConsumerStatefulWidget {
  const HardwareConfigStep({
    super.key,
    required this.onBack,
    required this.onNext,
  });

  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  ConsumerState<HardwareConfigStep> createState() => _HardwareConfigStepState();
}

class _HardwareConfigStepState extends ConsumerState<HardwareConfigStep> {
  bool _applying = false;
  String? _result;

  Future<void> _applyStandard() async {
    final ip = ref.read(selectedDeviceIpProvider);
    if (ip == null) {
      setState(() => _result = 'No controller selected — go back and pick one.');
      return;
    }

    setState(() {
      _applying = true;
      _result = null;
    });

    try {
      final pushed = await pushDefaultsForControllerType(
        ip,
        ControllerType.skikbily, // Use the SKIKBILY profile for all types.
      );
      setState(() {
        _applying = false;
        _result = pushed.success
            ? 'Nex-Gen Standard applied'
            : 'Configuration failed${pushed.warnings.isEmpty ? '' : ' with ${pushed.warnings.length} warning(s)'}';
      });
    } catch (e) {
      setState(() {
        _applying = false;
        _result = 'Error: $e';
      });
    }
  }

  void _openCustom() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const HardwareConfigScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hardware Configuration',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Set the LED type, color order, and per-channel bus assignments '
            'before handing off to the customer. Most installs use the '
            'Nex-Gen Standard.',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
          ),
          const SizedBox(height: 24),

          _OptionCard(
            icon: Icons.check_circle_outline,
            title: 'Apply Nex-Gen Standard',
            subtitle:
                'SK6812 / WS2814 RGBW · GRBW order · 100 px per channel · '
                'preserves existing GPIO pins',
            onTap: _applying ? null : _applyStandard,
            trailing: _applying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right, color: Colors.white54),
          ),
          const SizedBox(height: 12),
          _OptionCard(
            icon: Icons.tune,
            title: 'Custom configuration',
            subtitle:
                'Open the full hardware editor — pick LED type, color order, '
                'pixel counts, and GPIO pins per channel.',
            onTap: _applying ? null : _openCustom,
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          ),
          const SizedBox(height: 12),
          _OptionCard(
            icon: Icons.skip_next,
            title: 'Skip for now',
            subtitle:
                'Use whatever the controller is already configured for. '
                'You can come back to this from System → Hardware.',
            onTap: _applying ? null : widget.onNext,
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          ),

          if (_result != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _result!,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _applying ? null : widget.onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _applying ? null : widget.onNext,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: NexGenPalette.cyan, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
