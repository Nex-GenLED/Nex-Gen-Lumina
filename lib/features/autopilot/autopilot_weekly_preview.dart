import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
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
  final ValueChanged<DateTime>? onDayTap;

  const AutopilotWeeklyPreview({super.key, this.onDayTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(autopilotEnabledProvider);

    if (!enabled) {
      return const SizedBox.shrink();
    }

    final scheduleAsync = ref.watch(weeklyScheduleProvider);
    final isCommercial = ref.watch(isCommercialProfileProvider);
    final happyHourLocks = ref.watch(happyHourLocksProvider);

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

          // Happy hour lock banner (commercial only)
          if (isCommercial && happyHourLocks.isNotEmpty)
            _HappyHourBanner(locks: happyHourLocks),

          // Week view
          scheduleAsync.when(
            data: (schedule) => Column(
              children: [
                _WeekView(
                  schedule: schedule,
                  onDayTap: (date) {
                    // Show day detail bottom sheet
                    _showDayDetailSheet(context, ref, date, schedule);
                    // Also forward to parent callback
                    onDayTap?.call(date);
                  },
                ),
                // Game day chips row (commercial only)
                if (isCommercial)
                  _GameDayChipsRow(
                    schedule: schedule,
                    onDayTap: (date) {
                      _showDayDetailSheet(context, ref, date, schedule);
                      onDayTap?.call(date);
                    },
                  ),
              ],
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

  /// Show a bottom sheet with the day's schedule items and action buttons.
  void _showDayDetailSheet(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
    List<AutopilotScheduleItem> fullSchedule,
  ) {
    final dayItems = fullSchedule
        .where((item) =>
            item.scheduledTime.year == date.year &&
            item.scheduledTime.month == date.month &&
            item.scheduledTime.day == date.day)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => _DayDetailSheet(
          date: date,
          items: dayItems,
          scrollController: scrollController,
          parentRef: ref,
        ),
      ),
    );
  }
}

/// Bottom sheet content for a single day's schedule detail.
class _DayDetailSheet extends ConsumerWidget {
  final DateTime date;
  final List<AutopilotScheduleItem> items;
  final ScrollController scrollController;
  final WidgetRef parentRef;

  const _DayDetailSheet({
    required this.date,
    required this.items,
    required this.scrollController,
    required this.parentRef,
  });

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'
  ];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Drag handle
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          decoration: BoxDecoration(
            color: Colors.grey[600],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Day header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_dayNames[date.weekday - 1]}, ${_monthNames[date.month - 1]} ${date.day}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ),
        // Items list
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'No events scheduled',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _ScheduleItemCard(
                    item: items[index],
                    onEdit: () => _showEditDialog(context, ref, items[index]),
                    onApprove: () => _approveItem(ref, items[index]),
                  ),
                ),
        ),
        // "Looks good" button
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  for (final item in items) {
                    _approveItem(ref, item);
                  }
                  Navigator.of(context).pop();
                },
                icon: const Text('\u{1F44D}'),
                label: const Text('Looks good'),
              ),
            ),
          ),
      ],
    );
  }

  void _approveItem(WidgetRef ref, AutopilotScheduleItem item) {
    try {
      final schedulesNotifier = ref.read(schedulesProvider.notifier);
      schedulesNotifier.markApproved('autopilot-${item.id}');
    } catch (e) {
      debugPrint('Failed to approve item: $e');
    }
  }

  void _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    AutopilotScheduleItem item,
  ) {
    final nameController = TextEditingController(text: item.patternName);
    final colors = <Color>[
      ...?_extractColors(item.wledPayload),
    ];
    // Ensure 3 color slots
    while (colors.length < 3) {
      colors.add(Colors.grey);
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Override Pattern'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Pattern Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Colors', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: List.generate(3, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => _pickColor(ctx, colors[i], (newColor) {
                        setDialogState(() => colors[i] = newColor);
                      }),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors[i],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(Icons.edit, size: 16, color: Colors.white70),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final settingsService = ref.read(autopilotSettingsServiceProvider);
                // Build override payload
                final colorArrays = colors
                    .map((c) => [c.red, c.green, c.blue, 0])
                    .toList();
                final overridePayload = <String, dynamic>{
                  'on': true,
                  'bri': 200,
                  'seg': [
                    {
                      'fx': 0,
                      'sx': 128,
                      'ix': 128,
                      'pal': 0,
                      'col': colorArrays,
                    }
                  ],
                };
                // Save override by generating a new schedule item
                settingsService.generateAndPopulateSchedules();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _pickColor(BuildContext context, Color current, ValueChanged<Color> onPick) {
    // Simple color grid picker
    final presetColors = [
      Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
      Colors.indigo, Colors.blue, Colors.cyan, Colors.teal,
      Colors.green, Colors.lime, Colors.yellow, Colors.orange,
      Colors.deepOrange, Colors.brown, Colors.white, Colors.grey,
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick Color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presetColors.map((color) {
            return GestureDetector(
              onTap: () {
                onPick(color);
                Navigator.of(ctx).pop();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: color == current ? NexGenPalette.cyan : Colors.white24,
                    width: color == current ? 2 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<Color>? _extractColors(Map<String, dynamic> payload) {
    final seg = payload['seg'];
    if (seg is! List || seg.isEmpty) return null;
    final col = seg[0]['col'];
    if (col is! List) return null;
    return col.take(3).map((c) {
      if (c is List && c.length >= 3) {
        return Color.fromRGBO(c[0] as int, c[1] as int, c[2] as int, 1.0);
      }
      return Colors.grey;
    }).toList();
  }
}

/// The 7-day week view component.
class _WeekView extends StatelessWidget {
  final List<AutopilotScheduleItem> schedule;
  final ValueChanged<DateTime>? onDayTap;

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
  final ValueChanged<DateTime>? onTap;

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
      onTap: () => onTap?.call(date),
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

/// Amber banner showing active happy hour lock windows.
class _HappyHourBanner extends StatelessWidget {
  final List<Map<String, dynamic>> locks;

  const _HappyHourBanner({required this.locks});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: locks.map((lock) {
        final startHour = (lock['startHour'] as num?)?.toInt() ?? 0;
        final endHour = (lock['endHour'] as num?)?.toInt() ?? 0;
        final days = (lock['days'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final daysStr = days.join(', ');
        final startStr = _formatHour(startHour);
        final endStr = _formatHour(endHour);

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.withOpacity(0.4)),
          ),
          child: Text(
            'Happy Hour Lock active $daysStr $startStr\u2013$endStr',
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatHour(int hour) {
    if (hour == 0) return '12 AM';
    if (hour < 12) return '$hour AM';
    if (hour == 12) return '12 PM';
    return '${hour - 12} PM';
  }
}

/// Horizontal chip list of game day times for commercial profiles.
class _GameDayChipsRow extends StatelessWidget {
  final List<AutopilotScheduleItem> schedule;
  final ValueChanged<DateTime>? onDayTap;

  const _GameDayChipsRow({required this.schedule, this.onDayTap});

  static const _dayAbbreviations = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final gameDayItems = schedule
        .where((item) => item.trigger == AutopilotTrigger.gameDay)
        .toList()
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

    if (gameDayItems.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: gameDayItems.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final item = gameDayItems[index];
            final dayAbbr = _dayAbbreviations[item.scheduledTime.weekday - 1];
            final timeStr = _formatTime(item.scheduledTime);

            return ActionChip(
              avatar: const Text('\u{1F3C8}', style: TextStyle(fontSize: 14)),
              label: Text(
                '$dayAbbr $timeStr',
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: () => onDayTap?.call(item.scheduledTime),
              backgroundColor: NexGenPalette.cyan.withOpacity(0.15),
              side: BorderSide(color: NexGenPalette.cyan.withOpacity(0.3)),
              tooltip: item.eventName ?? item.patternName,
            );
          },
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

/// Full-screen autopilot schedule view with detailed day view.
class AutopilotScheduleScreen extends ConsumerWidget {
  /// Optional date to scroll to on open (e.g. from notification deep link).
  final DateTime? initialDate;

  const AutopilotScheduleScreen({super.key, this.initialDate});

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
        data: (schedule) => _ScheduleListView(
          schedule: schedule,
          initialDate: initialDate,
        ),
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
class _ScheduleListView extends StatefulWidget {
  final List<AutopilotScheduleItem> schedule;
  final DateTime? initialDate;

  const _ScheduleListView({required this.schedule, this.initialDate});

  @override
  State<_ScheduleListView> createState() => _ScheduleListViewState();
}

class _ScheduleListViewState extends State<_ScheduleListView> {
  final _scrollController = ScrollController();
  final _dayKeys = <DateTime, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToDate(widget.initialDate!));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToDate(DateTime target) {
    final normalizedTarget = DateTime(target.year, target.month, target.day);
    final key = _dayKeys[normalizedTarget];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.schedule.isEmpty) {
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
    for (final item in widget.schedule) {
      final dayKey = DateTime(
        item.scheduledTime.year,
        item.scheduledTime.month,
        item.scheduledTime.day,
      );
      grouped.putIfAbsent(dayKey, () => []).add(item);
    }

    final sortedDays = grouped.keys.toList()..sort();

    // Create GlobalKeys for scroll-to support
    for (final day in sortedDays) {
      _dayKeys.putIfAbsent(day, () => GlobalKey());
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: sortedDays.length,
      itemBuilder: (context, index) {
        final day = sortedDays[index];
        final dayItems = grouped[day]!;

        return Column(
          key: _dayKeys[day],
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
///
/// When [item.isApproved] is true, the card shows a glowing shadow using the
/// item's primary WLED color.
class _ScheduleItemCard extends StatelessWidget {
  final AutopilotScheduleItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onApprove;

  const _ScheduleItemCard({
    required this.item,
    this.onEdit,
    this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = _getPrimaryColor();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: item.isApproved
            ? [
                BoxShadow(
                  color: primaryColor.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Card(
        margin: EdgeInsets.zero,
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
          trailing: (onEdit != null || onApprove != null)
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEdit != null)
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: onEdit,
                        tooltip: 'Override pattern',
                        constraints: const BoxConstraints(minWidth: 36),
                        padding: EdgeInsets.zero,
                      ),
                    if (onApprove != null)
                      IconButton(
                        icon: Icon(
                          item.isApproved ? Icons.check_circle : Icons.check_circle_outline,
                          size: 20,
                          color: item.isApproved ? Colors.green : Colors.grey,
                        ),
                        onPressed: onApprove,
                        tooltip: item.isApproved ? 'Approved' : 'Approve',
                        constraints: const BoxConstraints(minWidth: 36),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                )
              : Icon(
                  item.isApproved ? Icons.check_circle : Icons.pending,
                  color: item.isApproved ? Colors.green : Colors.grey,
                ),
        ),
      ),
    );
  }

  Color _getPrimaryColor() {
    final colors = item.wledPayload['seg']?[0]?['col'] as List?;
    if (colors != null && colors.isNotEmpty) {
      final first = colors[0];
      if (first is List && first.length >= 3) {
        return Color.fromRGBO(first[0] as int, first[1] as int, first[2] as int, 1.0);
      }
    }
    return NexGenPalette.cyan;
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
      case AutopilotTrigger.sportsScoreAlert:
        return Icons.notifications_active;
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
