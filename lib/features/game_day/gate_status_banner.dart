// The customer-facing half of the readiness gate.
//
// Eight of the ten live Game Day accounts are held in log-only, and until now
// every one of them saw a UI that looked armed. This banner is the difference
// between "Game Day is on" and "Game Day is on and will fire tonight" — the
// second is a promise, and for those accounts it was not true.
//
// TONE. It says the feature IS on, because it is; what is missing is the
// precondition. "Game Day is off" would be a lie in the other direction and
// would invite the customer to turn on something already on.
//
// ARMED RENDERS NOTHING, except once. A permanent green "you're all set" is
// noise on every visit; a one-time acknowledgement when the account graduates
// is the news. See [_GraduationMemory].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexgen_command/app_colors.dart';
import 'gate_status.dart';
import 'gate_status_provider.dart';

/// Remembers whether this device has already told the customer they graduated,
/// so "you're set" is said once rather than on every rebuild.
///
/// Device-local on purpose: it is a UI acknowledgement, not account state, and
/// writing it to Firestore would put a cosmetic flag on the critical path.
class _GraduationMemory {
  static const _key = 'gameday_gate_was_blocked';

  static Future<bool> wasBlocked() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setBlocked(bool v) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, v);
    } catch (_) {
      /* cosmetic — never worth failing a screen build */
    }
  }
}

/// Shows the gate verdict, or nothing when there is nothing to say.
class GateStatusBanner extends ConsumerStatefulWidget {
  /// Invoked by the one-tap fix when the block is a missing schedule.
  final VoidCallback? onCreateSchedule;

  const GateStatusBanner({super.key, this.onCreateSchedule});

  @override
  ConsumerState<GateStatusBanner> createState() => _GateStatusBannerState();
}

class _GateStatusBannerState extends ConsumerState<GateStatusBanner> {
  bool _showGraduated = false;

  Future<void> _reconcile(GateStatus status) async {
    final wasBlocked = await _GraduationMemory.wasBlocked();
    if (!status.armed) {
      if (wasBlocked) return;
      await _GraduationMemory.setBlocked(true);
      return;
    }
    // Armed now. If this device saw it blocked before, that is a graduation:
    // say so once, then forget, so it never repeats.
    if (wasBlocked) {
      await _GraduationMemory.setBlocked(false);
      if (mounted) setState(() => _showGraduated = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(gateStatusProvider);
    final status = async.value ?? GateStatus.unknown;

    // Fire-and-forget; never blocks the build.
    _reconcile(status);

    if (status.armed) {
      return _showGraduated
          ? _Banner(
              icon: Icons.check_circle_outline,
              tint: Colors.green,
              title: 'Game Day is ready',
              lines: const ['Your lights will fire for upcoming games.'],
              onDismiss: () => setState(() => _showGraduated = false),
            )
          : const SizedBox.shrink();
    }

    return _Banner(
      icon: Icons.pending_outlined,
      tint: NexGenPalette.cyan,
      title: status.headline,
      lines: status.reasons,
      // No action button. R1 was the only reason with a one-tap fix; the two
      // that remain (`no_facts`, `ladder_bad`) are not things a button can do.
      actionLabel: null,
      onAction: null,
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final List<String> lines;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  const _Banner({
    required this.icon,
    required this.tint,
    required this.title,
    required this.lines,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: tint,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (onDismiss != null)
                InkWell(
                  onTap: onDismiss,
                  child: Icon(Icons.close,
                      size: 16, color: NexGenPalette.textMedium),
                ),
            ],
          ),
          for (final l in lines) ...[
            const SizedBox(height: 6),
            Text(
              l,
              style: const TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  backgroundColor: tint.withValues(alpha: 0.16),
                  foregroundColor: tint,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
