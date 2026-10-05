import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/controller_selection.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/theme.dart';

/// #118 — the label of every "choose this controller" control.
const String kUseThisControllerLabel = 'Use this controller';

/// #118 — where the customer changes which controller this phone uses.
const String kChooseControllerWhere =
    'Settings → System & Device Management → Controllers';

/// "Which controller should this phone use?"
///
/// Shown once, by the app shell, when two or more of the account's
/// controllers answered on this network and nothing else says which one this
/// phone uses ([ControllerSelection.needsChoice]). One controller, or one that
/// answers, is chosen silently; this is only for a real choice.
class ControllerChoiceSheet extends ConsumerWidget {
  const ControllerChoiceSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choices = ref.watch(controllerSelectionProvider).choices;
    final records = ref.watch(controllersStreamProvider).valueOrNull ??
        const <ControllerInfo>[];
    final theme = Theme.of(context);
    final rows = [
      for (final id in choices)
        for (final r in records)
          if (r.id == id) r,
    ];
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          key: const ValueKey('controller-choice-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Which controller should this phone use?',
              style: theme.textTheme.titleLarge?.copyWith(
                color: NexGenPalette.textHigh,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'More than one of your controllers answered on this network. '
              'Choose the one this phone should control. You can change it '
              'later in $kChooseControllerWhere.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: NexGenPalette.textMedium),
            ),
            const SizedBox(height: 16),
            for (final r in rows) ...[
              _ChoiceRow(record: r),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChoiceRow extends ConsumerWidget {
  const _ChoiceRow({required this.record});
  final ControllerInfo record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('controller-choice-${record.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.router_outlined, color: NexGenPalette.cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  record.name ?? 'Controller',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            key: ValueKey('controller-choice-use-${record.id}'),
            onPressed: () {
              ref.read(controllerSelectionProvider.notifier).use(record.id);
              Navigator.of(context).maybePop();
            },
            child: const Text(kUseThisControllerLabel),
          ),
        ],
      ),
    );
  }
}

/// Shows [ControllerChoiceSheet]. The customer can dismiss it; nothing is
/// then selected until they choose in [kChooseControllerWhere].
Future<void> showControllerChoicePrompt(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: NexGenPalette.matteBlack,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const ControllerChoiceSheet(),
  );
}

/// Shows [ControllerChoiceSheet] when the selection turns into a real choice.
/// Called from the app shell's build (MainScaffold), once per transition: a
/// dismissed prompt is not shown again until the choice arises again.
void listenForControllerChoice(WidgetRef ref, BuildContext context) {
  ref.listen<bool>(
    controllerSelectionProvider.select((s) => s.needsChoice),
    (previous, next) {
      if (next && previous != true && context.mounted) {
        showControllerChoicePrompt(context);
      }
    },
  );
}

/// [listenForControllerChoice] around [child], for a host other than the app
/// shell.
class ControllerChoicePromptHost extends ConsumerWidget {
  const ControllerChoicePromptHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForControllerChoice(ref, context);
    return child;
  }
}

/// #118 — the account has a choice to make: two or more records with an
/// address. "Use this controller" is offered only then.
final controllerChoiceAvailableProvider = Provider<bool>((ref) {
  final records = ref.watch(controllersStreamProvider).valueOrNull ??
      const <ControllerInfo>[];
  return records.where((r) => r.ip.trim().isNotEmpty).length >= 2;
});
