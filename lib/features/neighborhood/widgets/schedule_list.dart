import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wled/wled_models.dart';
import '../neighborhood_models.dart';
import '../neighborhood_providers.dart';

/// Widget displaying scheduled sync patterns for the neighborhood group.
class NeighborhoodScheduleList extends ConsumerWidget {
  final NeighborhoodGroup group;

  const NeighborhoodScheduleList({
    super.key,
    required this.group,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync = ref.watch(neighborhoodSchedulesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Scheduled Patterns',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showCreateScheduleDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              style: TextButton.styleFrom(foregroundColor: Colors.cyan),
            ),
          ],
        ),
        const SizedBox(height: 8),
        schedulesAsync.when(
          data: (schedules) {
            if (schedules.isEmpty) {
              return _buildEmptyState(context, ref);
            }
            return Column(
              children: schedules.map((schedule) {
                return _ScheduleTile(
                  schedule: schedule,
                  onTap: () => _showScheduleDetails(context, ref, schedule),
                  onDelete: () => _deleteSchedule(context, ref, schedule),
                );
              }).toList(),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: Colors.cyan),
            ),
          ),
          error: (e, _) => Center(
            child: Text(
              'Error loading schedules',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Column(
        children: [
          Icon(Icons.event_note, size: 40, color: Colors.grey.shade600),
          const SizedBox(height: 12),
          Text(
            'No scheduled patterns',
            style: TextStyle(color: Colors.grey.shade400),
          ),
          const SizedBox(height: 8),
          Text(
            'Schedule patterns to automatically sync with your neighbors',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _showCreateScheduleDialog(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Create Schedule'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.cyan,
              side: const BorderSide(color: Colors.cyan),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateScheduleDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => CreateScheduleSheet(groupId: group.id),
    );
  }

  void _showScheduleDetails(BuildContext context, WidgetRef ref, SyncSchedule schedule) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ScheduleDetailsSheet(schedule: schedule),
    );
  }

  void _deleteSchedule(BuildContext context, WidgetRef ref, SyncSchedule schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Schedule?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${schedule.patternName}"?',
          style: TextStyle(color: Colors.grey.shade400),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(neighborhoodNotifierProvider.notifier).deleteSchedule(schedule.id);
    }
  }
}

class _ScheduleTile extends StatelessWidget {
  final SyncSchedule schedule;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ScheduleTile({
    required this.schedule,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = schedule.isActive;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? Colors.cyan.withOpacity(0.5) : Colors.grey.shade800,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Pattern icon/color indicator
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: schedule.colors.isEmpty
                          ? [Colors.cyan, Colors.purple]
                          : schedule.colors.take(2).map((c) => Color(c | 0xFF000000)).toList(),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    schedule.syncType.icon,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),

                // Schedule info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              schedule.patternName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (!isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Paused',
                                style: TextStyle(color: Colors.grey, fontSize: 10),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            schedule.dateRangeString,
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            schedule.timeRangeString,
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _buildDaysChips(schedule.daysOfWeek),
                    ],
                  ),
                ),

                // Delete button
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: Colors.grey.shade600, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDaysChips(List<int> days) {
    const dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: List.generate(7, (i) {
        final isActive = days.contains(i + 1);
        return Container(
          margin: const EdgeInsets.only(right: 4),
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: isActive ? Colors.cyan.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              dayNames[i],
              style: TextStyle(
                color: isActive ? Colors.cyan : Colors.grey.shade600,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _ScheduleDetailsSheet extends ConsumerWidget {
  final SyncSchedule schedule;

  const _ScheduleDetailsSheet({required this.schedule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMember = ref.watch(currentUserMemberProvider);
    final isOptedOut = currentMember?.isOptedOutOf(schedule.id) ?? false;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: schedule.colors.isEmpty
                        ? [Colors.cyan, Colors.purple]
                        : schedule.colors.take(2).map((c) => Color(c | 0xFF000000)).toList(),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(schedule.syncType.icon, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.patternName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      schedule.syncType.displayName,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Details
          _detailRow(Icons.calendar_today, 'Dates', schedule.dateRangeString),
          _detailRow(Icons.access_time, 'Time', schedule.timeRangeString),
          _detailRow(Icons.repeat, 'Repeat', _formatDays(schedule.daysOfWeek)),

          if (schedule.notificationMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_outlined, color: Colors.cyan, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      schedule.notificationMessage!,
                      style: TextStyle(color: Colors.cyan.shade300, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Opt out button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                if (isOptedOut) {
                  ref.read(neighborhoodNotifierProvider.notifier).optInToSchedule(schedule.id);
                } else {
                  ref.read(neighborhoodNotifierProvider.notifier).optOutOfSchedule(schedule.id);
                }
                Navigator.pop(context);
              },
              icon: Icon(isOptedOut ? Icons.check_circle_outline : Icons.do_not_disturb_on_outlined),
              label: Text(isOptedOut ? 'Opt Back In' : 'Opt Out of This Event'),
              style: OutlinedButton.styleFrom(
                foregroundColor: isOptedOut ? Colors.green : Colors.orange,
                side: BorderSide(color: isOptedOut ? Colors.green : Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: Colors.grey.shade500)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  String _formatDays(List<int> days) {
    if (days.length == 7) return 'Every day';
    if (days.length == 5 && !days.contains(6) && !days.contains(7)) return 'Weekdays';
    if (days.length == 2 && days.contains(6) && days.contains(7)) return 'Weekends';

    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days.map((d) => dayNames[d - 1]).join(', ');
  }
}

/// Sheet for creating a new schedule.
class CreateScheduleSheet extends ConsumerStatefulWidget {
  final String groupId;

  const CreateScheduleSheet({super.key, required this.groupId});

  @override
  ConsumerState<CreateScheduleSheet> createState() => _CreateScheduleSheetState();
}

class _CreateScheduleSheetState extends ConsumerState<CreateScheduleSheet> {
  int _selectedEffectId = 28;
  List<Color> _selectedColors = [const Color(0xFF00BCD4), const Color(0xFFFFFFFF)];
  SyncType _syncType = SyncType.sequentialFlow;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _startTime = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 23, minute: 0);
  bool _useSunset = false;
  List<int> _selectedDays = [1, 2, 3, 4, 5, 6, 7];
  String _notificationMessage = '';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.event, color: Colors.cyan),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Create Schedule',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: Colors.grey.shade500)),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // Effect Selector
                  _buildSectionHeader('Pattern'),
                  _buildEffectSelector(),
                  const SizedBox(height: 20),

                  // Sync Type
                  _buildSectionHeader('Sync Mode'),
                  _buildSyncTypeSelector(),
                  const SizedBox(height: 20),

                  // Date Range
                  _buildSectionHeader('Date Range'),
                  _buildDateRangePicker(),
                  const SizedBox(height: 20),

                  // Time Range
                  _buildSectionHeader('Daily Time'),
                  _buildTimeRangePicker(),
                  const SizedBox(height: 20),

                  // Days of Week
                  _buildSectionHeader('Days'),
                  _buildDaySelector(),
                  const SizedBox(height: 20),

                  // Notification Message
                  _buildSectionHeader('Notify Group (optional)'),
                  TextField(
                    onChanged: (v) => _notificationMessage = v,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g., "Chiefs game tonight! Let\'s go red!"',
                      hintStyle: TextStyle(color: Colors.grey.shade700),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade700),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.cyan),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Create Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _createSchedule,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Text('Create Schedule', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEffectSelector() {
    final effects = <int, String>{
      28: 'Chase',
      77: 'Meteor',
      3: 'Wipe',
      15: 'Running',
      80: 'Ripple',
      106: 'Flow',
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: effects.entries.map((entry) {
        final isSelected = _selectedEffectId == entry.key;
        return ChoiceChip(
          label: Text(entry.value),
          selected: isSelected,
          onSelected: (selected) {
            if (selected) setState(() => _selectedEffectId = entry.key);
          },
          selectedColor: Colors.cyan.withOpacity(0.3),
          backgroundColor: Colors.grey.shade800,
          labelStyle: TextStyle(color: isSelected ? Colors.cyan : Colors.grey.shade400),
          side: BorderSide(color: isSelected ? Colors.cyan : Colors.grey.shade700),
        );
      }).toList(),
    );
  }

  Widget _buildSyncTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: SyncType.values.map((type) {
          final isSelected = _syncType == type;
          return InkWell(
            onTap: () => setState(() => _syncType = type),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.cyan.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(type.icon, color: isSelected ? Colors.cyan : Colors.grey.shade500, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      type.displayName,
                      style: TextStyle(
                        color: isSelected ? Colors.cyan : Colors.white,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isSelected) const Icon(Icons.check, color: Colors.cyan, size: 18),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateRangePicker() {
    return Row(
      children: [
        Expanded(
          child: _buildDateButton('Start', _startDate, (date) => setState(() => _startDate = date)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.arrow_forward, color: Colors.grey.shade600, size: 20),
        ),
        Expanded(
          child: _buildDateButton('End', _endDate, (date) => setState(() => _endDate = date)),
        ),
      ],
    );
  }

  Widget _buildDateButton(String label, DateTime date, Function(DateTime) onSelect) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onSelect(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade700),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Text(
              '${date.month}/${date.day}/${date.year}',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRangePicker() {
    return Column(
      children: [
        // Use sunset toggle
        Row(
          children: [
            Checkbox(
              value: _useSunset,
              onChanged: (v) => setState(() => _useSunset = v ?? false),
              activeColor: Colors.cyan,
            ),
            const Text('Start at sunset', style: TextStyle(color: Colors.white)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildTimeButton(
                _useSunset ? 'Sunset' : _formatTime(_startTime),
                _useSunset ? null : () => _pickTime(true),
                enabled: !_useSunset,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.arrow_forward, color: Colors.grey.shade600, size: 20),
            ),
            Expanded(
              child: _buildTimeButton(
                _formatTime(_endTime),
                () => _pickTime(false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeButton(String text, VoidCallback? onTap, {bool enabled = true}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: enabled ? Colors.black26 : Colors.grey.shade900,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade700),
        ),
        child: Row(
          children: [
            Icon(
              enabled ? Icons.access_time : Icons.wb_twilight,
              size: 16,
              color: enabled ? Colors.grey.shade500 : Colors.orange.shade300,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(color: enabled ? Colors.white : Colors.orange.shade300),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Widget _buildDaySelector() {
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final day = i + 1;
        final isSelected = _selectedDays.contains(day);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedDays.remove(day);
              } else {
                _selectedDays.add(day);
              }
            });
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected ? Colors.cyan.withOpacity(0.3) : Colors.grey.shade800,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.cyan : Colors.grey.shade700,
              ),
            ),
            child: Center(
              child: Text(
                dayNames[i],
                style: TextStyle(
                  color: isSelected ? Colors.cyan : Colors.grey.shade500,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _createSchedule() async {
    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one day'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final schedule = SyncSchedule(
      id: '',
      groupId: widget.groupId,
      patternName: kEffectNames[_selectedEffectId] ?? 'Effect #$_selectedEffectId',
      effectId: _selectedEffectId,
      colors: _selectedColors.map((c) => c.value).toList(),
      speed: 128,
      intensity: 128,
      brightness: 200,
      syncType: _syncType,
      timingConfig: const SyncTimingConfig(),
      startDate: _startDate,
      endDate: _endDate,
      dailyStartTime: _startTime,
      dailyEndTime: _endTime,
      useSunset: _useSunset,
      daysOfWeek: _selectedDays,
      createdBy: '',
      createdAt: DateTime.now(),
      notificationMessage: _notificationMessage.isNotEmpty ? _notificationMessage : null,
    );

    final result = await ref.read(neighborhoodNotifierProvider.notifier).createSchedule(schedule);

    if (mounted) {
      if (result != null) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Schedule created!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create schedule'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
