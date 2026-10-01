// lib/features/schedule/widgets/dated_schedule_controls.dart
//
// +112 (#124) — the three new controls of the "+" editor and the day sheet,
// kept as small widgets so the text-scale harness can lay each one out alone:
//   • [ScheduleModeToggle]   "Just this day" / "Repeats weekly"
//   • [ScheduleDateRow]      the chosen date, with a day/month/year picker
//   • [AddForThisDayButton]  the day sheet's add action (every day, empty or not)

import 'package:flutter/material.dart';

import 'package:nexgen_command/features/schedule/dated_entry_compose.dart';
import 'package:nexgen_command/theme.dart';

/// Whether a schedule being composed is one night or a weekly routine.
enum ScheduleEditorMode { justThisDay, repeatsWeekly }

class ScheduleModeToggle extends StatelessWidget {
  const ScheduleModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final ScheduleEditorMode mode;
  final ValueChanged<ScheduleEditorMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ScheduleEditorMode>(
      segments: const [
        ButtonSegment(
          value: ScheduleEditorMode.justThisDay,
          icon: Icon(Icons.today_rounded, size: 18),
          label: Text('Just this day'),
        ),
        ButtonSegment(
          value: ScheduleEditorMode.repeatsWeekly,
          icon: Icon(Icons.repeat_rounded, size: 18),
          label: Text('Repeats weekly'),
        ),
      ],
      selected: {mode},
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? NexGenPalette.cyan.withValues(alpha: 0.16)
                : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? NexGenPalette.cyan
                : NexGenPalette.textHigh),
        side: WidgetStatePropertyAll(BorderSide(color: NexGenPalette.line)),
      ),
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class ScheduleDateRow extends StatelessWidget {
  const ScheduleDateRow({
    super.key,
    required this.date,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: date.isBefore(today) ? today : date,
      firstDate: firstDate ?? today,
      lastDate: lastDate ?? today.add(const Duration(days: 365)),
      helpText: 'Pick the day',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: NexGenPalette.cyan,
            surface: NexGenPalette.gunmetal90,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) onChanged(DateTime(picked.year, picked.month, picked.day));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Day: ${formatDatedDate(date)}. Change the day',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pick(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_month_rounded,
                  color: NexGenPalette.cyan, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Day',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: NexGenPalette.textMedium)),
                    const SizedBox(height: 2),
                    Text(formatDatedDate(date),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: NexGenPalette.textHigh,
                              fontWeight: FontWeight.w600,
                            )),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('Change',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: NexGenPalette.cyan)),
            ],
          ),
        ),
      ),
    );
  }
}

class AddForThisDayButton extends StatelessWidget {
  const AddForThisDayButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: NexGenPalette.cyan,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        icon: const Icon(Icons.add_alarm_rounded, size: 18),
        label: const Text('Add for this day',
            style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: onPressed,
      ),
    );
  }
}

/// One-line note under the dated controls — a solar time that was resolved
/// for the chosen day, or the reason it could not be.
class DatedScheduleNote extends StatelessWidget {
  const DatedScheduleNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: NexGenPalette.textMedium),
      ),
    );
  }
}
