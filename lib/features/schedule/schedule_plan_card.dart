import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/schedule/schedule_day_row.dart';
import 'package:nexgen_command/features/schedule/schedule_plan_controller.dart';
import 'package:nexgen_command/theme.dart';

/// Multi-day schedule plan card for the Lumina bottom sheet.
///
/// Appears when the scheduling AI proposes a multi-day plan (e.g. "KC Royals
/// Week"). Displays a header with plan metadata, a scrollable list of
/// [ScheduleDayRow] cards with animated pixel previews, and footer actions
/// for confirming, editing, or saving the plan.
///
/// All day previews animate simultaneously. Tapping the edit icon on a day
/// opens inline adjustment scoped to that day.
class SchedulePlanCard extends ConsumerStatefulWidget {
  /// Called after the user successfully schedules all events.
  /// The parent (Lumina sheet) can use this to dismiss the card, show
  /// confirmation, and refresh the My Schedule screen.
  final VoidCallback? onScheduled;

  /// Called when the user wants to save the plan as a reusable template.
  final VoidCallback? onSaveTemplate;

  const SchedulePlanCard({
    super.key,
    this.onScheduled,
    this.onSaveTemplate,
  });

  @override
  ConsumerState<SchedulePlanCard> createState() => _SchedulePlanCardState();
}

class _SchedulePlanCardState extends ConsumerState<SchedulePlanCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _headerAnim;

  @override
  void initState() {
    super.initState();
    _headerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
  }

  @override
  void dispose() {
    _headerAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final planState = ref.watch(schedulePlanProvider);
    final plan = planState.plan;

    if (plan == null) return const SizedBox.shrink();

    // After successful submission, show confirmation then auto-dismiss.
    if (planState.isSuccess) {
      return _buildSuccessState(planState);
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: const Color(0xFF131920),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: NexGenPalette.line.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Header ----
          _buildHeader(plan),

          // ---- Day list ----
          _buildDayList(plan, planState.editingDayIndex),

          // ---- Footer actions ----
          _buildFooterActions(planState),

          // ---- Voice / text input hint ----
          _buildInputHint(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(SchedulePlan plan) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan name
            Text(
              plan.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: NexGenPalette.textHigh,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),

            // Date range + trigger time
            Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 12,
                  color: NexGenPalette.textMedium.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  plan.dateRange,
                  style: TextStyle(
                    fontSize: 12,
                    color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.schedule_rounded,
                  size: 12,
                  color: NexGenPalette.textMedium.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  plan.triggerTime,
                  style: TextStyle(
                    fontSize: 12,
                    color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Separator
            Container(
              height: 0.5,
              color: NexGenPalette.line.withValues(alpha: 0.35),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Day list (scrollable)
  // ---------------------------------------------------------------------------

  Widget _buildDayList(SchedulePlan plan, int editingIndex) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: ConstrainedBox(
        // Cap at ~4.5 visible rows before scrolling
        constraints: const BoxConstraints(maxHeight: 360),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: plan.days.length,
          itemBuilder: (context, index) {
            final day = plan.days[index];
            return ScheduleDayRow(
              day: day,
              dayIndex: index,
              isEditing: editingIndex == index,
              onEdit: () => _onEditDay(index, editingIndex),
              animationDelay: Duration(milliseconds: 100 * index),
            );
          },
        ),
      ),
    );
  }

  void _onEditDay(int index, int currentEditing) {
    HapticFeedback.selectionClick();
    final notifier = ref.read(schedulePlanProvider.notifier);
    if (currentEditing == index) {
      notifier.stopEditing();
    } else {
      notifier.beginEditingDay(index);
    }
  }

  // ---------------------------------------------------------------------------
  // Footer actions
  // ---------------------------------------------------------------------------

  Widget _buildFooterActions(SchedulePlanState planState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      child: Column(
        children: [
          // Separator
          Container(
            height: 0.5,
            color: NexGenPalette.line.withValues(alpha: 0.35),
            margin: const EdgeInsets.only(bottom: 10),
          ),

          // Primary actions row
          Row(
            children: [
              // Schedule All — primary CTA
              Expanded(
                child: _PlanActionButton(
                  label: planState.isSubmitting ? 'Scheduling...' : 'Schedule All',
                  icon: planState.isSubmitting
                      ? Icons.hourglass_top_rounded
                      : Icons.check_circle_outline_rounded,
                  primary: true,
                  enabled: !planState.isSubmitting,
                  onTap: _onScheduleAll,
                ),
              ),
              const SizedBox(width: 8),

              // Save as Template
              _PlanActionButton(
                label: 'Save Template',
                icon: Icons.bookmark_outline_rounded,
                onTap: widget.onSaveTemplate ?? () {},
                enabled: !planState.isSubmitting,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onScheduleAll() async {
    HapticFeedback.mediumImpact();
    await ref.read(schedulePlanProvider.notifier).scheduleAll();

    // Brief delay to let the success state render, then notify parent.
    if (mounted) {
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) widget.onScheduled?.call();
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Input hint
  // ---------------------------------------------------------------------------

  Widget _buildInputHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
      child: Row(
        children: [
          Icon(
            Icons.mic_none_rounded,
            size: 14,
            color: NexGenPalette.textMedium.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 6),
          Text(
            'Or tell me what to change\u2026',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: NexGenPalette.textMedium.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Success state
  // ---------------------------------------------------------------------------

  Widget _buildSuccessState(SchedulePlanState planState) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF131920),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: NexGenPalette.cyan.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Success icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NexGenPalette.cyan.withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: NexGenPalette.cyan,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),

          // Confirmation message
          Text(
            planState.submission.confirmationMessage ?? 'All events scheduled!',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: NexGenPalette.textHigh,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),

          // Follow-up prompt
          Text(
            'Want me to set a reminder to change it back after the week?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: NexGenPalette.textMedium.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Plan action button (private)
// =============================================================================

class _PlanActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final bool enabled;

  const _PlanActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAlpha = enabled ? 1.0 : 0.4;

    return Opacity(
      opacity: effectiveAlpha,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: primary
                  ? NexGenPalette.cyan.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: primary
                    ? NexGenPalette.cyan.withValues(alpha: 0.5)
                    : NexGenPalette.line.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: primary
                      ? NexGenPalette.cyan
                      : NexGenPalette.textMedium,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: primary
                        ? NexGenPalette.cyan
                        : NexGenPalette.textHigh,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
