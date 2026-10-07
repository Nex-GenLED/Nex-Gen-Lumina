// lib/features/game_day/ladder_repair_action.dart
//
// #183 — "Repair base lighting": the customer's own repair of the base
// ladder, offered on the Game Day screen when the readiness status says the
// ladder needs it.
//
// WHY A BUTTON. The on-connect repair (base_ladder_repair.dart) is dry-run
// for the whole fleet unless a config flag says "repair", and it refuses for
// hours after a server start. A bus added outside the app — WLED's own LED
// settings page — leaves presets 1 and 2 naming fewer channels than the
// controller has, the server gate blocks the account, and nothing the
// customer could do fixed it; the owner repaired five presets by hand on
// 2026-10-06. Here the TAP is the consent: the fleet flag does not apply,
// and the run says in plain words what it does before it does it.
//
// WHAT IT STILL REFUSES. The same guards as the connect-time repair: only on
// the home network, only the account's own controller (never a customer an
// installer is viewing), never during or just before a Game Day, never within
// ten minutes of a timer, never with the controller's clock unset.
//
// Every view is split from its provider so the text-scale harness can lay it
// out at 1.0 / 1.75 / 2.0 with Bold Text on.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/schedule/widgets/ladder_repair_banner.dart'
    show ladderSlotLabel;
import 'package:nexgen_command/features/wled/base_ladder_repair.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair_providers.dart';

const String kLadderRepairNeedTitle = 'Your base lighting needs repair';
const String kLadderRepairNeedBody =
    "Your everyday lighting settings don't cover every channel on your "
    'controller. This usually happens after a channel was added or changed. '
    "Game Day stays off until they're repaired.";
const String kLadderRepairActionLabel = 'Repair base lighting';
const String kLadderRepairConfirmTitle = 'Repair base lighting?';
const List<String> kLadderRepairConfirmLines = [
  'This saves up to five presets on your controller — On, Off, Dim, Low and '
      'Medium — so each one covers every channel in Lumina Blue.',
  'It takes about a minute. Your lights will flicker and then return to how '
      'they are now.',
  'It never changes your schedules. We keep a copy of the old settings, and '
      'you can put them back.',
];
const String kLadderRepairRestoreLabel = 'Put back the previous settings';

/// PURE. What one progress step reads as.
String ladderRepairStepLabel(String step) {
  if (step.startsWith('save:')) {
    return 'Saving ${ladderSlotLabel(int.parse(step.substring(5)))}…';
  }
  if (step.startsWith('verify:')) {
    return 'Checking ${ladderSlotLabel(int.parse(step.substring(7)))}…';
  }
  return switch (step) {
    'backup' => 'Backing up your current settings…',
    'capture' => 'Reading your lights…',
    'restore' => 'Putting your lights back…',
    'done' => 'Finishing…',
    _ => 'Working…',
  };
}

/// PURE. The title and lines for a finished run, and whether to offer the
/// backup restore.
({String title, List<String> lines, bool offerRestore}) ladderRepairResultCopy(
    LadderRepairRun run) {
  switch (run.outcome) {
    case LadderRepairOutcome.repaired:
      return (
        title: 'Base lighting repaired',
        lines: const [
          'Your On, Off, Dim, Low and Medium settings now cover every channel '
              'on your controller. Game Day can run again within a few minutes.',
        ],
        offerRestore: false,
      );
    case LadderRepairOutcome.notNeeded:
      return (
        title: 'Nothing to repair',
        lines: const ['Your base lighting already covers every channel.'],
        offerRestore: false,
      );
    case LadderRepairOutcome.deferred:
      return (
        title: 'Not right now',
        lines: [_deferredLine(run.reason)],
        offerRestore: false,
      );
    case LadderRepairOutcome.cancelled:
      return (
        title: 'Repair cancelled',
        lines: const [
          'The signed-in account changed, so nothing was saved.',
        ],
        offerRestore: false,
      );
    case LadderRepairOutcome.modeOff:
      return (
        title: 'Repair is switched off',
        lines: const [
          'Repairs are switched off for everyone right now. Contact support.',
        ],
        offerRestore: false,
      );
    case LadderRepairOutcome.inFlight:
      return (
        title: 'Already running',
        lines: const ['A repair is already in progress.'],
        offerRestore: false,
      );
    case LadderRepairOutcome.partial:
    case LadderRepairOutcome.failed:
      final at = run.stoppedAtId;
      return (
        title: 'Repair stopped',
        lines: [
          at == null
              ? 'A setting did not save, so we stopped.'
              : 'Saving ${ladderSlotLabel(at)} did not work, so we stopped '
                  'there. Nothing after it was changed.',
          if (run.repairedIds.isNotEmpty)
            'Repaired: ${run.repairedIds.map(ladderSlotLabel).join(', ')}.',
          'You can put back the settings we backed up, or try again.',
        ],
        offerRestore: true,
      );
    case LadderRepairOutcome.aborted:
    case LadderRepairOutcome.alreadyRan:
    case LadderRepairOutcome.dryRun:
      return (
        title: 'Repair could not start',
        lines: [
          run.reason.startsWith('Only') ||
                  run.reason.startsWith('Connect') ||
                  run.reason.startsWith('Choose')
              ? run.reason
              : "We couldn't read your controller. Check you're on your home "
                  'Wi-Fi and try again.',
        ],
        offerRestore: false,
      );
  }
}

String _deferredLine(String reason) {
  if (reason.contains('game_day_live')) {
    return 'A game is on or about to start. Try again after it ends.';
  }
  if (reason.contains('game_day_unknown')) {
    return "Game Day information hasn't loaded yet. Try again in a moment.";
  }
  if (reason.contains('timer_near')) {
    return 'Your schedule changes your lights in the next few minutes. Try '
        'again shortly.';
  }
  if (reason.contains('clock')) {
    return "Your controller's clock isn't set, so we can't tell when your "
        'schedule fires. Check its time settings first.';
  }
  if (reason.contains('changed')) {
    return 'Your lighting changed while we were getting ready. Try again.';
  }
  return 'Try again in a few minutes.';
}

/// The card on the Game Day screen. Renders nothing unless the readiness
/// status says the ladder needs repair.
class LadderRepairActionCard extends ConsumerWidget {
  const LadderRepairActionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(ladderRepairNeededProvider)) return const SizedBox.shrink();
    final repair = ref.watch(userLadderRepairProvider);
    return LadderRepairActionView(
      blockedReason: repair.blockedReason(),
      onRepair: () => startLadderRepair(context, ref),
    );
  }
}

/// The card's layout, provider-free.
class LadderRepairActionView extends StatelessWidget {
  const LadderRepairActionView({
    super.key,
    required this.blockedReason,
    required this.onRepair,
  });

  final String? blockedReason;
  final VoidCallback onRepair;

  @override
  Widget build(BuildContext context) {
    const tint = NexGenPalette.amber;
    return Semantics(
      container: true,
      child: Container(
        key: const ValueKey('ladder-repair-card'),
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tint.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.build_circle_outlined, size: 18, color: tint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kLadderRepairNeedTitle,
                    style: const TextStyle(
                      color: tint,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              kLadderRepairNeedBody,
              style: const TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('ladder-repair-action'),
              onPressed: blockedReason == null ? onRepair : null,
              icon: const Icon(Icons.handyman_outlined, size: 18),
              label: const Text(kLadderRepairActionLabel),
              style: FilledButton.styleFrom(
                backgroundColor: tint,
                foregroundColor: NexGenPalette.matteBlack,
              ),
            ),
            if (blockedReason != null) ...[
              const SizedBox(height: 6),
              Text(
                blockedReason!,
                key: const ValueKey('ladder-repair-blocked'),
                style: const TextStyle(
                  color: NexGenPalette.textMedium,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Confirmation, then the run with its progress. Nothing is written before
/// "Repair" is tapped in the dialog.
Future<void> startLadderRepair(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const LadderRepairConfirmDialog(),
  );
  if (ok != true || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: NexGenPalette.matteBlack,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const LadderRepairProgressSheet(),
  );
}

/// "Repair base lighting?" — what it does, in plain words.
class LadderRepairConfirmDialog extends StatelessWidget {
  const LadderRepairConfirmDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('ladder-repair-confirm'),
      title: const Text(kLadderRepairConfirmTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < kLadderRepairConfirmLines.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              Text(kLadderRepairConfirmLines[i],
                  style: const TextStyle(height: 1.35)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('ladder-repair-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const ValueKey('ladder-repair-go'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Repair'),
        ),
      ],
    );
  }
}

/// Runs the repair when shown and reports each step; offers the backup
/// restore when it stopped.
class LadderRepairProgressSheet extends ConsumerStatefulWidget {
  const LadderRepairProgressSheet({super.key});

  @override
  ConsumerState<LadderRepairProgressSheet> createState() =>
      _LadderRepairProgressSheetState();
}

class _LadderRepairProgressSheetState
    extends ConsumerState<LadderRepairProgressSheet> {
  String _step = 'backup';
  LadderRepairRun? _run;
  bool _restoring = false;
  LadderRepairRun? _restored;

  @override
  void initState() {
    super.initState();
    // The provider is read here, before any await, and the run holds its
    // own container reference — nothing below touches `ref` after a gap.
    final repair = ref.read(userLadderRepairProvider);
    repair.run(onProgress: (s) {
      if (mounted) setState(() => _step = s);
    }).then((run) {
      if (mounted) setState(() => _run = run);
    });
  }

  Future<void> _restore(LadderRepairAction repair) async {
    setState(() {
      _restoring = true;
      _step = 'capture';
    });
    final out = await repair.restore(onProgress: (s) {
      if (mounted) setState(() => _step = s);
    });
    if (mounted) {
      setState(() {
        _restoring = false;
        _restored = out;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final repair = ref.read(userLadderRepairProvider);
    return LadderRepairProgressView(
      step: _step,
      run: _run,
      restoring: _restoring,
      restored: _restored,
      onRestore: () => _restore(repair),
      onClose: () => Navigator.of(context).maybePop(),
    );
  }
}

/// The sheet's layout, provider-free.
class LadderRepairProgressView extends StatelessWidget {
  const LadderRepairProgressView({
    super.key,
    required this.step,
    required this.run,
    required this.onRestore,
    required this.onClose,
    this.restoring = false,
    this.restored,
  });

  final String step;
  final LadderRepairRun? run;
  final bool restoring;
  final LadderRepairRun? restored;
  final VoidCallback onRestore;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleLarge?.copyWith(
      color: NexGenPalette.textHigh,
      fontWeight: FontWeight.w700,
    );
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: NexGenPalette.textMedium,
      height: 1.35,
    );
    final Widget body;
    if (run == null || restoring) {
      body = Column(
        key: const ValueKey('ladder-repair-running'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(restoring ? 'Putting back your settings' : kLadderRepairActionLabel,
              style: titleStyle),
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(height: 16),
          Text(ladderRepairStepLabel(step),
              key: const ValueKey('ladder-repair-step'),
              style: bodyStyle,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Please keep the app open.',
              style: bodyStyle, textAlign: TextAlign.center),
        ],
      );
    } else if (restored != null) {
      final ok = restored!.outcome == LadderRepairOutcome.repaired;
      body = Column(
        key: const ValueKey('ladder-repair-restored'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ok ? 'Previous settings restored' : 'Could not put everything back',
              style: titleStyle),
          const SizedBox(height: 10),
          Text(
            ok
                ? 'Your controller holds the settings it had before the repair.'
                : 'Some settings did not save. Contact support if your lights '
                    'come on with nothing showing.',
            style: bodyStyle,
          ),
          const SizedBox(height: 16),
          FilledButton(
              key: const ValueKey('ladder-repair-close'),
              onPressed: onClose,
              child: const Text('Done')),
        ],
      );
    } else {
      final copy = ladderRepairResultCopy(run!);
      body = Column(
        key: const ValueKey('ladder-repair-result'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(copy.title, style: titleStyle),
          for (final l in copy.lines) ...[
            const SizedBox(height: 10),
            Text(l, style: bodyStyle),
          ],
          const SizedBox(height: 16),
          if (copy.offerRestore) ...[
            OutlinedButton(
              key: const ValueKey('ladder-repair-restore'),
              onPressed: onRestore,
              child: const Text(kLadderRepairRestoreLabel),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
              key: const ValueKey('ladder-repair-close'),
              onPressed: onClose,
              child: const Text('Done')),
        ],
      );
    }
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: body,
      ),
    );
  }
}
