import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/widgets/night_track_bar.dart';
import 'package:nexgen_command/features/schedule/sun_time_provider.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';

/// 7-day vertical agenda showing schedule items for each day
class VerticalAgenda extends ConsumerWidget {
  const VerticalAgenda({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wledStateProvider);
    final schedules = ref.watch(schedulesProvider);
    final String fallbackPatternLabel = (state.supportsRgbw && state.warmWhite > 0) ? 'Warm White' : 'Active Pattern';
    // Get user coordinates (if available) to fetch sunrise/sunset times
    final userAsync = ref.watch(currentUserProfileProvider);
    final user = userAsync.maybeWhen(data: (u) => u, orElse: () => null);
    final hasCoords = (user?.latitude != null && user?.longitude != null);
    final sunAsync = hasCoords
        ? ref.watch(sunTimeProvider((lat: user!.latitude!, lon: user.longitude!)))
        : const AsyncValue.data(null);

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

    // Build list of 7 days starting from today
    final now = DateTime.now();
    final List<DateTime> days = List.generate(7, (i) => DateTime(now.year, now.month, now.day).add(Duration(days: i)));
    final List<String> abbr = const ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Time Axis Header to mirror My Schedule page
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
                      gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [NexGenPalette.matteBlack.withValues(alpha: 0.15), NexGenPalette.matteBlack.withValues(alpha: 0.05)]),
                    ),
                  ),
                ),
                Align(alignment: Alignment.center, child: Container(width: 1, color: NexGenPalette.textMedium.withValues(alpha: 0.25))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    sunAsync.when(
                      data: (s) => Text(
                        (s?.sunsetLabel ?? 'Sunset (—)').toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8),
                      ),
                      loading: () => Text('SUNSET (…)'.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                      error: (e, st) => Text('SUNSET (—)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                    ),
                    sunAsync.when(
                      data: (s) => Text(
                        (s?.sunriseLabel ?? 'Sunrise (—)').toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8),
                      ),
                      loading: () => Text('SUNRISE (…)'.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                      error: (e, st) => Text('SUNRISE (—)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
      ...List.generate(7, (i) {
      final d = days[i];
      final isToday = i == 0;
      final int weekdayIndex0Sun = d.weekday % 7; // Sun=0..Sat=6
        final dayItems = itemsForDay(weekdayIndex0Sun);
        final String label = dayItems.isNotEmpty ? labelFromAction(dayItems.first.actionLabel) : fallbackPatternLabel;

      return InkWell(
        onTap: () => showScheduleEditor(context, ref, preselectedDayIndex: weekdayIndex0Sun),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            // Leading Day Abbreviation
            SizedBox(
              width: 50,
              child: Text(
                abbr[weekdayIndex0Sun],
                textAlign: TextAlign.left,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: isToday ? NexGenPalette.cyan : NexGenPalette.textMedium, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
            const SizedBox(width: 10),
              // Night Track Bar
              Expanded(child: NightTrackBar(label: label, items: dayItems)),
          ]),
        ),
      );
      }),
    ]);
  }
}
