import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/models/commercial/business_hours.dart';
import 'package:nexgen_command/models/commercial/channel_role.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';

class ReviewGoLiveScreen extends ConsumerStatefulWidget {
  const ReviewGoLiveScreen({super.key, required this.onGoToStep});
  final void Function(int step) onGoToStep;

  @override
  ConsumerState<ReviewGoLiveScreen> createState() => _ReviewGoLiveScreenState();
}

class _ReviewGoLiveScreenState extends ConsumerState<ReviewGoLiveScreen> {
  bool _weekPreviewExpanded = false;
  bool _isActivating = false;

  Future<void> _goLive() async {
    setState(() => _isActivating = true);

    // Simulate Firestore batch commit.
    await Future<void>.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    setState(() => _isActivating = false);

    // Success animation.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SuccessDialog(),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    Navigator.of(context)
      ..pop() // dismiss dialog
      ..pop(); // exit wizard
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(commercialOnboardingProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('Review & Go Live',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: NexGenPalette.textHigh)),
        const SizedBox(height: 16),

        // ── Business Profile ────────────────────────────────────────────
        _SummaryCard(
          title: 'Business Profile',
          onEdit: () => widget.onGoToStep(0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow('Type', draft.businessType.replaceAll('_', ' ')),
              _InfoRow('Name', draft.businessName),
              if (draft.primaryAddress.isNotEmpty)
                _InfoRow('Address', draft.primaryAddress),
            ],
          ),
        ),

        // ── Brand Colors ────────────────────────────────────────────────
        _SummaryCard(
          title: 'Brand Colors',
          onEdit: () => widget.onGoToStep(1),
          child: draft.brandColors.isEmpty
              ? const Text('None set',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13))
              : Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: draft.brandColors.map((c) {
                    final color = _parseHex(c.hexCode);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 16, height: 16,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: NexGenPalette.line),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(c.colorName.isEmpty ? '#${c.hexCode}' : c.colorName,
                            style: const TextStyle(
                                color: NexGenPalette.textHigh, fontSize: 12)),
                        const SizedBox(width: 8),
                      ],
                    );
                  }).toList(),
                ),
        ),

        // ── Hours ───────────────────────────────────────────────────────
        _SummaryCard(
          title: 'Hours',
          onEdit: () => widget.onGoToStep(2),
          child: draft.hoursVary
              ? const Text('Flexible hours',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13))
              : _WeekGlanceMini(schedule: draft.weeklySchedule),
        ),

        // ── Channels ────────────────────────────────────────────────────
        _SummaryCard(
          title: 'Channels',
          onEdit: () => widget.onGoToStep(3),
          child: draft.channelConfigs.isEmpty
              ? const Text('Not configured',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13))
              : Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: draft.channelConfigs.map((c) {
                    return Chip(
                      label: Text(
                        '${c.friendlyName} — ${c.role.displayName}',
                        style: const TextStyle(fontSize: 11, color: NexGenPalette.textHigh),
                      ),
                      backgroundColor: NexGenPalette.gunmetal,
                      side: const BorderSide(color: NexGenPalette.line),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
        ),

        // ── Your Teams ──────────────────────────────────────────────────
        _SummaryCard(
          title: 'Your Teams',
          onEdit: () => widget.onGoToStep(4),
          child: draft.teams.isEmpty
              ? const Text('None',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13))
              : Column(
                  children: draft.teams.map((t) {
                    final primary = _parseHex(t.primaryColor);
                    final secondary = _parseHex(t.secondaryColor);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(color: primary, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 2),
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(color: secondary, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(t.teamName,
                              style: const TextStyle(
                                  color: NexGenPalette.textHigh, fontSize: 13)),
                          const Spacer(),
                          Text('#${t.priorityRank}',
                              style: const TextStyle(
                                  color: NexGenPalette.textMedium, fontSize: 12)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),

        // ── Day-Parts ───────────────────────────────────────────────────
        _SummaryCard(
          title: 'Day-Parts',
          onEdit: () => widget.onGoToStep(5),
          child: draft.dayParts.isEmpty
              ? const Text('None',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13))
              : SizedBox(
                  height: 32,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: draft.dayParts.length,
                    itemBuilder: (_, i) {
                      final colors = [
                        const Color(0xFF2196F3),
                        const Color(0xFF4CAF50),
                        const Color(0xFFFFC107),
                        const Color(0xFFFF5722),
                        const Color(0xFF9C27B0),
                        const Color(0xFF00BCD4),
                        const Color(0xFFE91E63),
                        const Color(0xFF607D8B),
                      ];
                      return Container(
                        margin: const EdgeInsets.only(right: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors[i % colors.length].withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: colors[i % colors.length].withValues(alpha: 0.3)),
                        ),
                        child: Center(
                          child: Text(draft.dayParts[i].name,
                              style: const TextStyle(
                                  color: NexGenPalette.textHigh, fontSize: 10)),
                        ),
                      );
                    },
                  ),
                ),
        ),

        // ── Preview Your Week ───────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _weekPreviewExpanded = !_weekPreviewExpanded),
          child: Container(
            margin: const EdgeInsets.only(top: 4, bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_view_week,
                    size: 18, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Preview Your Week',
                      style: TextStyle(color: NexGenPalette.textHigh, fontSize: 14)),
                ),
                Icon(
                  _weekPreviewExpanded ? Icons.expand_less : Icons.expand_more,
                  color: NexGenPalette.textMedium,
                ),
              ],
            ),
          ),
        ),
        if (_weekPreviewExpanded)
          _WeekPreview(draft: draft),

        const SizedBox(height: 8),

        // ── Pro Tier Banner ─────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: NexGenPalette.cyan, width: 3)),
          ),
          child: Text(
            'Multi-location management and advanced commercial features are '
            'currently included in Lumina at no additional cost. A Lumina '
            'Commercial subscription is coming \u2014 users who set up now '
            'will be grandfathered.',
            style: TextStyle(color: NexGenPalette.textHigh.withValues(alpha: 0.85), fontSize: 13),
          ),
        ),

        const SizedBox(height: 24),

        // ── Go Live button ──────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isActivating ? null : _goLive,
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              disabledBackgroundColor: NexGenPalette.cyan.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isActivating
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Text('Activate Commercial Mode',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card wrapper
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.onEdit, required this.child});
  final String title;
  final VoidCallback onEdit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: NexGenPalette.textHigh,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ),
              GestureDetector(
                onTap: onEdit,
                child: const Text('Edit',
                    style: TextStyle(color: NexGenPalette.cyan, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info row
// ---------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label,
                style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Week-at-a-glance mini strip
// ---------------------------------------------------------------------------

class _WeekGlanceMini extends StatelessWidget {
  const _WeekGlanceMini({required this.schedule});
  final Map<DayOfWeek, DaySchedule> schedule;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: DayOfWeek.values.map((d) {
        final open = schedule[d]?.isOpen ?? false;
        return Column(
          children: [
            Container(
              width: 30, height: 5,
              decoration: BoxDecoration(
                color: open ? NexGenPalette.cyan : NexGenPalette.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 3),
            Text(d.shortName,
                style: TextStyle(
                    color: open ? NexGenPalette.textHigh : NexGenPalette.textMedium,
                    fontSize: 10)),
          ],
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Week preview
// ---------------------------------------------------------------------------

class _WeekPreview extends StatelessWidget {
  const _WeekPreview({required this.draft});
  final CommercialOnboardingDraft draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: DayOfWeek.values.map((day) {
          final sched = draft.weeklySchedule[day];
          final open = sched?.isOpen ?? false;
          final dayParts = draft.dayParts.where((p) {
            if (p.daysOfWeek.isEmpty) return true;
            return p.daysOfWeek.contains(day);
          }).toList();

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(day.shortName,
                      style: TextStyle(
                          color: open ? NexGenPalette.textHigh : NexGenPalette.textMedium,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                if (!open)
                  const Text('Closed',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11))
                else
                  Expanded(
                    child: SizedBox(
                      height: 18,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: dayParts.length,
                        itemBuilder: (_, i) {
                          final colors = [
                            const Color(0xFF2196F3), const Color(0xFF4CAF50),
                            const Color(0xFFFFC107), const Color(0xFFFF5722),
                            const Color(0xFF9C27B0), const Color(0xFF00BCD4),
                          ];
                          return Container(
                            margin: const EdgeInsets.only(right: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: colors[i % colors.length].withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Center(
                              child: Text(dayParts[i].name,
                                  style: const TextStyle(
                                      color: NexGenPalette.textHigh, fontSize: 9)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Success dialog
// ---------------------------------------------------------------------------

class _SuccessDialog extends StatelessWidget {
  const _SuccessDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NexGenPalette.gunmetal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NexGenPalette.cyan.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.check_circle, size: 48, color: NexGenPalette.cyan),
            ),
            const SizedBox(height: 20),
            const Text(
              'Commercial Mode Active!',
              style: TextStyle(
                color: NexGenPalette.textHigh,
                fontSize: 20,
                fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your schedule is now running on autopilot.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Color _parseHex(String hex) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length == 6) {
    final v = int.tryParse('FF$cleaned', radix: 16);
    if (v != null) return Color(v);
  }
  return Colors.grey;
}
