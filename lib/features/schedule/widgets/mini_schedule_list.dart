import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/schedule/widgets/night_track_bar.dart';

/// Compact 7-day schedule list for the dashboard/home screen.
/// - Safe against empty data (shows a neutral message)
/// - Includes a simple time axis header (Sunset .. Sunrise)
/// - Each day renders a track with an active bar and centered label
/// - Constrained height to avoid pushing bottom UI off-screen
class MiniScheduleList extends ConsumerWidget {
  final double height;
  // height kept for backward compatibility but no longer constrains layout.
  const MiniScheduleList({super.key, this.height = 300});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulesProvider);

    // Data safety: empty list means nothing configured yet.
    if (schedules.isEmpty) {
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

    List<ScheduleItem> itemsForDay(int weekdayIndex0Sun) => schedules.where((s) => s.enabled && appliesTo(s, weekdayIndex0Sun)).toList(growable: false);

    String labelFromAction(String actionLabel) {
      final a = actionLabel.trim();
      if (a.toLowerCase().startsWith('pattern')) {
        final idx = a.indexOf(':');
        return idx != -1 && idx + 1 < a.length ? a.substring(idx + 1).trim() : a;
      }
      return a;
    }

    return Column(children: [
      // Header (Time Axis) — match My Schedule page style
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

      // Days list — use ListView with shrinkWrap so the page can scroll, not this list
      ListView.builder(
        itemCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, i) {
          final d = days[i];
          final int weekdayIndex0Sun = d.weekday % 7; // Sun=0..Sat=6
          final isToday = i == 0;
          final dayItems = itemsForDay(weekdayIndex0Sun);
          final String barLabel = dayItems.isNotEmpty ? labelFromAction(dayItems.first.actionLabel) : 'No schedule';

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
              Expanded(child: SizedBox(height: 44, child: NightTrackBar(label: barLabel, items: dayItems))),
            ]),
          );
        },
      ),
    ]);
  }
}
