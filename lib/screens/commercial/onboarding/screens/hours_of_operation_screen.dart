import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/models/commercial/business_hours.dart';
import 'package:nexgen_command/models/commercial/holiday_calendar.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';

class HoursOfOperationScreen extends ConsumerStatefulWidget {
  const HoursOfOperationScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  ConsumerState<HoursOfOperationScreen> createState() =>
      _HoursOfOperationScreenState();
}

class _HoursOfOperationScreenState
    extends ConsumerState<HoursOfOperationScreen> {
  final _expandedDays = <DayOfWeek>{};

  DaySchedule _schedFor(DayOfWeek day) {
    final draft = ref.read(commercialOnboardingProvider);
    return draft.weeklySchedule[day] ?? const DaySchedule();
  }

  void _updateDay(DayOfWeek day, DaySchedule sched) {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final map = Map<DayOfWeek, DaySchedule>.from(d.weeklySchedule);
      map[day] = sched;
      return d.copyWith(weeklySchedule: map);
    });
  }

  void _copyToWeekdays(DayOfWeek source) {
    final sched = _schedFor(source);
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final map = Map<DayOfWeek, DaySchedule>.from(d.weeklySchedule);
      for (final day in [
        DayOfWeek.monday,
        DayOfWeek.tuesday,
        DayOfWeek.wednesday,
        DayOfWeek.thursday,
        DayOfWeek.friday,
      ]) {
        map[day] = sched;
      }
      return d.copyWith(weeklySchedule: map);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to weekdays'), duration: Duration(seconds: 1)),
    );
  }

  void _copyToAll(DayOfWeek source) {
    final sched = _schedFor(source);
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final map = <DayOfWeek, DaySchedule>{};
      for (final day in DayOfWeek.values) {
        map[day] = sched;
      }
      return d.copyWith(weeklySchedule: map);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to all days'), duration: Duration(seconds: 1)),
    );
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) {
    return showTimePicker(context: context, initialTime: initial);
  }

  void _validate() {
    final draft = ref.read(commercialOnboardingProvider);
    if (!draft.hoursVary && draft.weeklySchedule.values.every((s) => !s.isOpen)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set at least one day as open, or select "Our hours vary".'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
      return;
    }
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(commercialOnboardingProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Hours of Operation',
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: NexGenPalette.textHigh),
        ),
        const SizedBox(height: 16),

        // ── "Our hours vary" toggle ─────────────────────────────────────
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: draft.hoursVary,
          activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.4),
          thumbColor: const WidgetStatePropertyAll(NexGenPalette.cyan),
          onChanged: (v) => ref
              .read(commercialOnboardingProvider.notifier)
              .update((d) => d.copyWith(hoursVary: v)),
          title: const Text('Our hours vary',
              style: TextStyle(color: NexGenPalette.textHigh, fontSize: 14)),
          subtitle: const Text('Skip structured hours for now',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
        ),
        const SizedBox(height: 8),

        // ── Day rows ────────────────────────────────────────────────────
        if (!draft.hoursVary)
          ...DayOfWeek.values.map((day) =>
              _DayTile(
                day: day,
                schedule: draft.weeklySchedule[day] ?? const DaySchedule(),
                isExpanded: _expandedDays.contains(day),
                onToggleExpand: () => setState(() {
                  if (_expandedDays.contains(day)) {
                    _expandedDays.remove(day);
                  } else {
                    _expandedDays.add(day);
                  }
                }),
                onUpdate: (s) => _updateDay(day, s),
                onPickTime: _pickTime,
                onCopyToWeekdays: () => _copyToWeekdays(day),
                onCopyToAll: () => _copyToAll(day),
              )),

        if (!draft.hoursVary) ...[
          const SizedBox(height: 16),
          const Divider(color: NexGenPalette.line),
          const SizedBox(height: 12),

          // ── Buffers ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _BufferField(
                  label: 'Pre-open buffer',
                  value: draft.preOpenBufferMinutes,
                  onChanged: (v) => ref
                      .read(commercialOnboardingProvider.notifier)
                      .update((d) => d.copyWith(preOpenBufferMinutes: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BufferField(
                  label: 'Post-close wind-down',
                  value: draft.postCloseWindDownMinutes,
                  onChanged: (v) => ref
                      .read(commercialOnboardingProvider.notifier)
                      .update((d) => d.copyWith(postCloseWindDownMinutes: v)),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 16),
        const Divider(color: NexGenPalette.line),
        const SizedBox(height: 12),

        // ── Holidays ────────────────────────────────────────────────────
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: draft.observeStandardHolidays,
          activeColor: NexGenPalette.cyan,
          onChanged: (v) => ref
              .read(commercialOnboardingProvider.notifier)
              .update((d) => d.copyWith(observeStandardHolidays: v ?? true)),
          title: const Text('We observe standard US holidays',
              style: TextStyle(color: NexGenPalette.textHigh, fontSize: 14)),
        ),

        if (draft.observeStandardHolidays)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: StandardHoliday.values.map((h) {
              final key = h.name;
              final isChecked = draft.observedHolidays.contains(key);
              return FilterChip(
                label: Text(h.displayName, style: const TextStyle(fontSize: 12)),
                selected: isChecked,
                selectedColor: NexGenPalette.cyan.withValues(alpha: 0.15),
                backgroundColor: NexGenPalette.gunmetal,
                checkmarkColor: NexGenPalette.cyan,
                labelStyle: TextStyle(
                  color: isChecked ? NexGenPalette.cyan : NexGenPalette.textMedium,
                ),
                side: BorderSide(
                  color: isChecked ? NexGenPalette.cyan : NexGenPalette.line,
                ),
                onSelected: (v) {
                  ref.read(commercialOnboardingProvider.notifier).update((d) {
                    final list = List<String>.from(d.observedHolidays);
                    v ? list.add(key) : list.remove(key);
                    return d.copyWith(observedHolidays: list);
                  });
                },
              );
            }).toList(),
          ),

        const SizedBox(height: 16),

        // ── Week-at-a-glance ────────────────────────────────────────────
        if (!draft.hoursVary) _WeekGlance(schedule: draft.weeklySchedule),

        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _validate,
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Next', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Day tile — expandable
// ---------------------------------------------------------------------------

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.schedule,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onUpdate,
    required this.onPickTime,
    required this.onCopyToWeekdays,
    required this.onCopyToAll,
  });

  final DayOfWeek day;
  final DaySchedule schedule;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final ValueChanged<DaySchedule> onUpdate;
  final Future<TimeOfDay?> Function(TimeOfDay) onPickTime;
  final VoidCallback onCopyToWeekdays;
  final VoidCallback onCopyToAll;

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      day.displayName,
                      style: const TextStyle(
                          color: NexGenPalette.textHigh, fontSize: 15),
                    ),
                  ),
                  Text(
                    schedule.isOpen
                        ? '${_fmt(schedule.openTime)} – ${_fmt(schedule.closeTime)}'
                        : 'Closed',
                    style: TextStyle(
                      color: schedule.isOpen
                          ? NexGenPalette.cyan
                          : NexGenPalette.textMedium,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: NexGenPalette.textMedium,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                children: [
                  const Divider(color: NexGenPalette.line, height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('Open', style: TextStyle(color: NexGenPalette.textHigh, fontSize: 13)),
                      const Spacer(),
                      Switch(
                        value: schedule.isOpen,
                        activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.4),
                        thumbColor: const WidgetStatePropertyAll(NexGenPalette.cyan),
                        onChanged: (v) =>
                            onUpdate(schedule.copyWith(isOpen: v)),
                      ),
                    ],
                  ),
                  if (schedule.isOpen) ...[
                    Row(
                      children: [
                        _TimeButton(
                          label: 'Opens',
                          time: schedule.openTime,
                          onTap: () async {
                            final t = await onPickTime(schedule.openTime);
                            if (t != null) onUpdate(schedule.copyWith(openTime: t));
                          },
                        ),
                        const SizedBox(width: 12),
                        _TimeButton(
                          label: 'Closes',
                          time: schedule.closeTime,
                          onTap: () async {
                            final t = await onPickTime(schedule.closeTime);
                            if (t != null) onUpdate(schedule.copyWith(closeTime: t));
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _SmallBtn(
                          label: 'Copy to weekdays',
                          onTap: onCopyToWeekdays,
                        ),
                        const SizedBox(width: 8),
                        _SmallBtn(label: 'Copy to all', onTap: onCopyToAll),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.label, required this.time, required this.onTap});
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: NexGenPalette.matteBlack,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Row(
            children: [
              Text(label, style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
              const Spacer(),
              Text(
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                color: NexGenPalette.cyan.withValues(alpha: 0.8), fontSize: 11)),
      ),
    );
  }
}

class _BufferField extends StatelessWidget {
  const _BufferField({required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
        const SizedBox(height: 4),
        Row(
          children: [
            GestureDetector(
              onTap: () => onChanged((value - 5).clamp(0, 120)),
              child: Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: const Icon(Icons.remove, size: 16, color: NexGenPalette.textMedium),
              ),
            ),
            const SizedBox(width: 8),
            Text('$value min',
                style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 14)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => onChanged((value + 5).clamp(0, 120)),
              child: Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: const Icon(Icons.add, size: 16, color: NexGenPalette.textMedium),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Week-at-a-glance strip
// ---------------------------------------------------------------------------

class _WeekGlance extends StatelessWidget {
  const _WeekGlance({required this.schedule});
  final Map<DayOfWeek, DaySchedule> schedule;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: DayOfWeek.values.map((d) {
        final s = schedule[d];
        final open = s?.isOpen ?? false;
        return Column(
          children: [
            Container(
              width: 36,
              height: 6,
              decoration: BoxDecoration(
                color: open ? NexGenPalette.cyan : NexGenPalette.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              d.shortName,
              style: TextStyle(
                color: open ? NexGenPalette.textHigh : NexGenPalette.textMedium,
                fontSize: 11,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
