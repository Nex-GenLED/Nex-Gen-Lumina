import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';
import 'package:nexgen_command/services/autopilot_generation_service.dart';
import 'package:nexgen_command/theme.dart';

/// Provider for the generated weekly schedule.
final weeklyScheduleProvider =
    FutureProvider.autoDispose<List<AutopilotScheduleItem>>((ref) async {
  final profileAsync = ref.watch(currentUserProfileProvider);
  final profile = profileAsync.maybeWhen(
    data: (p) => p,
    orElse: () => null,
  );

  if (profile == null || !profile.autopilotEnabled) {
    return [];
  }

  final service = ref.watch(autopilotGenerationServiceProvider);
  return service.generateWeeklySchedule(profile: profile);
});

/// A weekly calendar preview of autopilot scheduled items.
///
/// Shows a 7-day view with scheduled patterns for each day.
class AutopilotWeeklyPreview extends ConsumerWidget {
  final VoidCallback? onDayTap;

  const AutopilotWeeklyPreview({super.key, this.onDayTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(autopilotEnabledProvider);

    if (!enabled) {
      return const SizedBox.shrink();
    }

    final scheduleAsync = ref.watch(weeklyScheduleProvider);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.calendar_month, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Autopilot Schedule',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => ref.invalidate(weeklyScheduleProvider),
                  tooltip: 'Regenerate schedule',
                ),
              ],
            ),
          ),

          // Week view
          scheduleAsync.when(
            data: (schedule) => _WeekView(
              schedule: schedule,
              onDayTap: onDayTap,
            ),
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Failed to generate schedule: $e',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 7-day week view component.
class _WeekView extends StatelessWidget {
  final List<AutopilotScheduleItem> schedule;
  final VoidCallback? onDayTap;

  const _WeekView({required this.schedule, this.onDayTap});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekDays = List.generate(7, (i) => now.add(Duration(days: i)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Row(
        children: weekDays.map((day) {
          final daySchedule = _getScheduleForDay(day);
          return Expanded(
            child: _DayColumn(
              date: day,
              items: daySchedule,
              isToday: _isSameDay(day, now),
              onTap: onDayTap,
            ),
          );
        }).toList(),
      ),
    );
  }

  List<AutopilotScheduleItem> _getScheduleForDay(DateTime day) {
    return schedule.where((item) => _isSameDay(item.scheduledTime, day)).toList();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

/// A single day column in the week view.
class _DayColumn extends StatelessWidget {
  final DateTime date;
  final List<AutopilotScheduleItem> items;
  final bool isToday;
  final VoidCallback? onTap;

  const _DayColumn({
    required this.date,
    required this.items,
    required this.isToday,
    this.onTap,
  });

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isToday ? NexGenPalette.cyan.withOpacity(0.1) : null,
          borderRadius: BorderRadius.circular(8),
          border: isToday
              ? Border.all(color: NexGenPalette.cyan.withOpacity(0.5))
              : null,
        ),
        child: Column(
          children: [
            // Day name
            Text(
              _dayNames[date.weekday - 1],
              style: TextStyle(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                color: isToday ? NexGenPalette.cyan : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            // Day number
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: isToday
                  ? const BoxDecoration(
                      color: NexGenPalette.cyan,
                      shape: BoxShape.circle,
                    )
                  : null,
              child: Text(
                date.day.toString(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isToday ? Colors.black : Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Schedule items
            if (items.isEmpty)
              _buildEmptyIndicator()
            else
              ...items.take(2).map((item) => _buildItemIndicator(item, context)),
            if (items.length > 2)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${items.length - 2}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyIndicator() {
    return Container(
      width: 32,
      height: 6,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _buildItemIndicator(AutopilotScheduleItem item, BuildContext context) {
    // Get color from WLED payload
    Color indicatorColor = NexGenPalette.cyan;
    final colors = item.wledPayload['seg']?[0]?['col'] as List?;
    if (colors != null && colors.isNotEmpty) {
      final firstColor = colors[0];
      if (firstColor is List && firstColor.length >= 3) {
        indicatorColor = Color.fromRGBO(
          firstColor[0] as int,
          firstColor[1] as int,
          firstColor[2] as int,
          1.0,
        );
      }
    }

    return Tooltip(
      message: '${item.patternName}\n${item.reason}',
      child: Container(
        width: 32,
        height: 6,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: indicatorColor,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

/// Full-screen autopilot schedule view with detailed day view.
class AutopilotScheduleScreen extends ConsumerWidget {
  const AutopilotScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(weeklyScheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Autopilot Schedule'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(weeklyScheduleProvider),
            tooltip: 'Regenerate',
          ),
        ],
      ),
      body: scheduleAsync.when(
        data: (schedule) => _ScheduleListView(schedule: schedule),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text('Failed to load schedule: $e'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(weeklyScheduleProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// List view of scheduled items grouped by day.
class _ScheduleListView extends StatelessWidget {
  final List<AutopilotScheduleItem> schedule;

  const _ScheduleListView({required this.schedule});

  @override
  Widget build(BuildContext context) {
    if (schedule.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No scheduled items',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Autopilot will generate a schedule based on your preferences.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Group by day
    final grouped = <DateTime, List<AutopilotScheduleItem>>{};
    for (final item in schedule) {
      final dayKey = DateTime(
        item.scheduledTime.year,
        item.scheduledTime.month,
        item.scheduledTime.day,
      );
      grouped.putIfAbsent(dayKey, () => []).add(item);
    }

    final sortedDays = grouped.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedDays.length,
      itemBuilder: (context, index) {
        final day = sortedDays[index];
        final dayItems = grouped[day]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _formatDayHeader(day),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: NexGenPalette.cyan,
                    ),
              ),
            ),
            // Items for this day
            ...dayItems.map((item) => _ScheduleItemCard(item: item)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  String _formatDayHeader(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    if (day == today) {
      return 'Today, ${_monthName(day.month)} ${day.day}';
    } else if (day == tomorrow) {
      return 'Tomorrow, ${_monthName(day.month)} ${day.day}';
    }

    const dayNames = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    return '${dayNames[day.weekday - 1]}, ${_monthName(day.month)} ${day.day}';
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }
}

/// Card displaying a single scheduled item.
class _ScheduleItemCard extends StatelessWidget {
  final AutopilotScheduleItem item;

  const _ScheduleItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: _buildColorPreview(),
        title: Text(
          item.patternName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(item.reason),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 4),
                Text(
                  _formatTime(item.scheduledTime),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  _getTriggerIcon(item.trigger),
                  size: 14,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 4),
                Text(
                  item.trigger.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: Icon(
          item.isApproved ? Icons.check_circle : Icons.pending,
          color: item.isApproved ? Colors.green : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildColorPreview() {
    final colors = item.wledPayload['seg']?[0]?['col'] as List?;
    final displayColors = <Color>[];

    if (colors != null) {
      for (final colorArray in colors.take(3)) {
        if (colorArray is List && colorArray.length >= 3) {
          displayColors.add(Color.fromRGBO(
            colorArray[0] as int,
            colorArray[1] as int,
            colorArray[2] as int,
            1.0,
          ));
        }
      }
    }

    if (displayColors.isEmpty) {
      displayColors.add(Colors.grey);
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: displayColors.length > 1
            ? LinearGradient(colors: displayColors)
            : null,
        color: displayColors.length == 1 ? displayColors.first : null,
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  IconData _getTriggerIcon(AutopilotTrigger trigger) {
    switch (trigger) {
      case AutopilotTrigger.holiday:
        return Icons.celebration;
      case AutopilotTrigger.gameDay:
        return Icons.sports_football;
      case AutopilotTrigger.sunset:
        return Icons.wb_twilight;
      case AutopilotTrigger.sunrise:
        return Icons.wb_sunny;
      case AutopilotTrigger.weeknight:
        return Icons.nights_stay;
      case AutopilotTrigger.weekend:
        return Icons.weekend;
      case AutopilotTrigger.seasonal:
        return Icons.eco;
      case AutopilotTrigger.learned:
        return Icons.psychology;
      case AutopilotTrigger.custom:
        return Icons.star;
    }
  }
}
