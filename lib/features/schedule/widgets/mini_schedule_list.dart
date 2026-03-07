import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/schedule/widgets/night_track_bar.dart';

/// Compact 7-day schedule list for the dashboard/home screen.
/// Merges both data sources:
///   - calendarScheduleProvider (date-specific CalendarEntry overrides)
///   - schedulesProvider (recurring ScheduleItem from Firestore)
/// Calendar entries take priority over recurring schedules for the same day.
class MiniScheduleList extends ConsumerWidget {
  final double height;
  const MiniScheduleList({super.key, this.height = 300});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulesProvider);
    final calEntries = ref.watch(calendarScheduleProvider);

    // If both sources are empty, show placeholder
    if (schedules.isEmpty && calEntries.isEmpty) {
      return const Center(child: Text('No Schedule Set', style: TextStyle(color: Colors.grey)));
    }

    // Build list of 7 days starting from today
    final now = DateTime.now();
    final List<DateTime> days = List.generate(7, (i) => DateTime(now.year, now.month, now.day).add(Duration(days: i)));
    const List<String> abbr = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    bool appliesTo(ScheduleItem s, int weekdayIndex0Sun) {
      final dl = s.repeatDays.map((e) => e.toLowerCase()).toList(growable: false);
      if (dl.contains('daily')) return true;
      Set<String> keys;
      switch (weekdayIndex0Sun) {
        case 0:
          keys = {'sun', 'sunday'};
          break;
        case 1:
          keys = {'mon', 'monday'};
          break;
        case 2:
          keys = {'tue', 'tues', 'tuesday'};
          break;
        case 3:
          keys = {'wed', 'wednesday'};
          break;
        case 4:
          keys = {'thu', 'thurs', 'thursday'};
          break;
        case 5:
          keys = {'fri', 'friday'};
          break;
        case 6:
          keys = {'sat', 'saturday'};
          break;
        default:
          keys = {};
      }
      return dl.any(keys.contains);
    }

    List<ScheduleItem> recurringForDay(int weekdayIndex0Sun) =>
        schedules.where((s) => s.enabled && appliesTo(s, weekdayIndex0Sun)).toList(growable: false);

    String labelFromAction(String actionLabel) {
      final a = actionLabel.trim();
      if (a.toLowerCase().startsWith('pattern')) {
        final idx = a.indexOf(':');
        return idx != -1 && idx + 1 < a.length ? a.substring(idx + 1).trim() : a;
      }
      return a;
    }

    return Column(children: [
      // Header (Time Axis)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const SizedBox(width: 50),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 22,
              child: Stack(children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [
                        NexGenPalette.matteBlack.withValues(alpha: 0.15),
                        NexGenPalette.matteBlack.withValues(alpha: 0.05),
                      ]),
                    ),
                  ),
                ),
                Align(alignment: Alignment.center, child: Container(width: 1, color: NexGenPalette.textMedium.withValues(alpha: 0.25))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('SUNSET', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                    Text('SUNRISE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),

      // Days list
      ListView.builder(
        itemCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, i) {
          final d = days[i];
          final int weekdayIndex0Sun = d.weekday % 7; // Sun=0..Sat=6
          final isToday = i == 0;

          // Check for a date-specific calendar entry first
          final dateKey = calendarDateKey(d);
          final CalendarEntry? calEntry = calEntries[dateKey];

          // Fall back to recurring schedules
          final dayItems = recurringForDay(weekdayIndex0Sun);

          // Calendar entry overrides recurring schedule
          String barLabel;
          if (calEntry != null) {
            barLabel = calEntry.brightness == 0
                ? 'Off'
                : calEntry.patternName;
          } else if (dayItems.isNotEmpty) {
            barLabel = labelFromAction(dayItems.first.actionLabel);
          } else {
            barLabel = 'No schedule';
          }

          // Build effective items list for NightTrackBar
          // If we have a calendar entry, synthesize a ScheduleItem so the bar renders
          final List<ScheduleItem> effectiveItems;
          if (calEntry != null && calEntry.brightness > 0) {
            effectiveItems = [
              ScheduleItem(
                id: 'cal_$dateKey',
                timeLabel: calEntry.onTime ?? '17:30',
                offTimeLabel: calEntry.offTime ?? '23:30',
                repeatDays: const ['daily'],
                actionLabel: calEntry.patternName,
                enabled: true,
              ),
            ];
          } else if (calEntry != null && calEntry.brightness == 0) {
            // Explicitly off — show empty bar
            effectiveItems = [];
          } else {
            effectiveItems = dayItems;
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                width: 50,
                child: Text(
                  abbr[weekdayIndex0Sun],
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: isToday ? NexGenPalette.cyan : NexGenPalette.textMedium, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: SizedBox(height: 44, child: NightTrackBar(label: barLabel, items: effectiveItems))),
            ]),
          );
        },
      ),
    ]);
  }
}
