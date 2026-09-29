import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/theme.dart';

/// Row 70 (+110): names the controller a roofline screen loads from and
/// saves to, and lets the customer choose it. Shown on every roofline editor.
///
/// With a target: "Saving to: Front House" plus "Change" when the account has
/// more than one controller. Without one: the reason, and a button to choose.
class RooflineTargetBar extends ConsumerWidget {
  const RooflineTargetBar({
    super.key,
    this.onChanged,
    this.enabled = true,
    this.verb = 'Saving to',
  });

  /// Called after the customer picks a DIFFERENT controller, so the screen
  /// can reload that controller's roofline.
  final ValueChanged<ControllerInfo>? onChanged;

  /// False while the host screen has unsaved changes or is saving.
  final bool enabled;

  /// "Saving to", "Lighting", …
  final String verb;

  Future<void> _choose(BuildContext context, WidgetRef ref,
      List<ControllerInfo> controllers, String? currentId) async {
    final picked = await showModalBottomSheet<ControllerInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Which controller is this roofline for?',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final c in controllers)
                ListTile(
                  key: ValueKey('roofline-target-${c.id}'),
                  leading: Icon(
                    c.id == currentId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: NexGenPalette.cyan,
                  ),
                  title: Text(controllerDisplayName(c)),
                  subtitle: c.ip.isEmpty ? null : Text(c.ip),
                  onTap: () => Navigator.of(ctx).pop(c),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    ref.read(rooflineTargetControllerIdProvider.notifier).state = picked.id;
    if (picked.id != currentId) onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decision = ref.watch(rooflineEditTargetProvider);
    final controllers = ref.watch(controllersStreamProvider).valueOrNull ??
        const <ControllerInfo>[];
    final target = decision.value;
    final canChoose = enabled && controllers.isNotEmpty;

    return Container(
      key: const ValueKey('roofline-target-bar'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: target == null
            ? Colors.amber.withValues(alpha: 0.12)
            : NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: target == null
              ? Colors.amber.withValues(alpha: 0.5)
              : NexGenPalette.line,
        ),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Icon(target == null ? Icons.help_outline : Icons.settings_remote,
              size: 18,
              color: target == null ? Colors.amber : NexGenPalette.cyan),
          Text(
            target == null
                ? (decision.reason ?? 'Choose a controller.')
                : '$verb: ${controllerDisplayName(target)}',
            style: const TextStyle(color: Colors.white),
          ),
          if (target == null && canChoose)
            FilledButton(
              key: const ValueKey('roofline-target-choose'),
              onPressed: () => _choose(context, ref, controllers, null),
              child: const Text('Choose controller'),
            )
          else if (target != null && controllers.length > 1)
            TextButton(
              key: const ValueKey('roofline-target-change'),
              onPressed: canChoose
                  ? () => _choose(context, ref, controllers, target.id)
                  : null,
              child: const Text('Change'),
            ),
        ],
      ),
    );
  }
}
