// lib/features/neighborhood/widgets/schedule_list.dart
//
// Redesigned Schedule Patterns section for Neighborhood Sync Control Center.
// Uses the visual identity system from schedule_type_badge.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_colors.dart';
import '../../../widgets/schedule_type_badge.dart';
import '../../wled/pattern_explore_screen.dart';
import '../../wled/wled_providers.dart';
import '../neighborhood_models.dart';
import '../neighborhood_providers.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN WIDGET
// ═══════════════════════════════════════════════════════════════════════════════

/// Redesigned schedule patterns section for the Neighborhood Sync Control Center.
///
/// Features:
///  - Violet-themed header with dynamic subtitle count
///  - Sorted card list (active/today first, then chronological)
///  - Swipe-to-delete with confirmation
///  - Animated pulse dot on active cards
///  - Two-option "Create Schedule" chooser (Library / Game Day)
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
        // ── Header ────────────────────────────────────────────────────────
        _GroupScheduleHeader(
          scheduleCount: schedulesAsync.valueOrNull?.where((s) => s.isActive).length ?? 0,
          onAdd: () => _showCreateChooser(context, ref),
        ),
        const SizedBox(height: 12),

        // ── Schedule list ─────────────────────────────────────────────────
        schedulesAsync.when(
          data: (schedules) {
            if (schedules.isEmpty) {
              return _EmptyState(onCreateFirst: () => _showCreateChooser(context, ref));
            }
            return _ScheduleCardList(
              schedules: _sortSchedules(schedules),
              onTap: (s) => _showScheduleDetails(context, ref, s),
              onDelete: (s) => _deleteSchedule(context, ref, s),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: NexGenPalette.violet),
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

  // ── Sorting: active/today first, then upcoming chronologically ──────

  List<SyncSchedule> _sortSchedules(List<SyncSchedule> schedules) {
    final now = DateTime.now();
    final todayWeekday = now.weekday; // 1=Mon .. 7=Sun

    final sorted = List<SyncSchedule>.from(schedules);
    sorted.sort((a, b) {
      // Active + running today sorts first
      final aToday = a.isActive && a.isActiveOnDay(todayWeekday);
      final bToday = b.isActive && b.isActiveOnDay(todayWeekday);
      if (aToday && !bToday) return -1;
      if (!aToday && bToday) return 1;

      // Active before inactive
      if (a.isActive && !b.isActive) return -1;
      if (!a.isActive && b.isActive) return 1;

      // Chronological by start date
      return a.startDate.compareTo(b.startDate);
    });
    return sorted;
  }

  // ── Create schedule chooser ─────────────────────────────────────────

  void _showCreateChooser(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CreateScheduleChooser(
        groupId: group.id,
        onLibrarySelected: () {
          Navigator.pop(ctx);
          _openLibraryFlow(context, ref);
        },
        onGameDaySelected: () {
          Navigator.pop(ctx);
          _openGameDayFlow(context, ref);
        },
      ),
    );
  }

  void _openLibraryFlow(BuildContext context, WidgetRef ref) async {
    // Open Explore Patterns as a full-screen modal.
    // User browses and taps patterns to preview on device as normal.
    // "Use This Pattern" FAB captures the current WLED state as the selection.
    final result = await Navigator.of(context).push<_SelectedPatternResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ExplorePatternsPicker(groupId: group.id),
      ),
    );

    if (result != null && context.mounted) {
      // Pattern was selected — open time config sheet with pre-populated data
      showModalBottomSheet(
        context: context,
        backgroundColor: NexGenPalette.gunmetal,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _ScheduleTimeConfigSheet(
          groupId: group.id,
          patternName: result.patternName,
          effectId: result.effectId,
          colors: result.colors,
        ),
      );
    }
  }

  void _openGameDayFlow(BuildContext context, WidgetRef ref) {
    // Navigate to the existing GameDaySetupScreen
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const _GameDayScheduleWrapper(),
      ),
    );
  }

  void _showScheduleDetails(BuildContext context, WidgetRef ref, SyncSchedule schedule) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal,
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
        backgroundColor: NexGenPalette.gunmetal,
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

// ═══════════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════════

class _GroupScheduleHeader extends StatelessWidget {
  final int scheduleCount;
  final VoidCallback onAdd;

  const _GroupScheduleHeader({
    required this.scheduleCount,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (scheduleCount) {
      0 => 'No schedules set',
      1 => '1 active schedule',
      _ => '$scheduleCount schedules active',
    };

    return Row(
      children: [
        const Icon(Icons.calendar_month, color: NexGenPalette.violet, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Group Schedule',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: NexGenPalette.violet,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
          style: TextButton.styleFrom(foregroundColor: NexGenPalette.violet),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateFirst;

  const _EmptyState({required this.onCreateFirst});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: NexGenPalette.violet.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexGenPalette.violet.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.calendar_month,
            size: 48,
            color: NexGenPalette.violet.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Group Schedules Yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a schedule to automatically sync\nyour group\'s lights for any occasion.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onCreateFirst,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create First Schedule'),
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.violet,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCHEDULE CARD LIST (with swipe-to-delete)
// ═══════════════════════════════════════════════════════════════════════════════

class _ScheduleCardList extends StatelessWidget {
  final List<SyncSchedule> schedules;
  final void Function(SyncSchedule) onTap;
  final void Function(SyncSchedule) onDelete;

  const _ScheduleCardList({
    required this.schedules,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: schedules.map((schedule) {
        return Dismissible(
          key: ValueKey(schedule.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            onDelete(schedule);
            return false; // dialog handles actual deletion
          },
          background: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
          ),
          child: _SyncScheduleCard(
            schedule: schedule,
            onTap: () => onTap(schedule),
          ),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// INDIVIDUAL SCHEDULE CARD (with active pulse dot)
// ═══════════════════════════════════════════════════════════════════════════════

class _SyncScheduleCard extends StatefulWidget {
  final SyncSchedule schedule;
  final VoidCallback onTap;

  const _SyncScheduleCard({
    required this.schedule,
    required this.onTap,
  });

  @override
  State<_SyncScheduleCard> createState() => _SyncScheduleCardState();
}

class _SyncScheduleCardState extends State<_SyncScheduleCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;

  bool get _isActiveToday {
    final now = DateTime.now();
    return widget.schedule.isActive && widget.schedule.isActiveOnDay(now.weekday);
  }

  @override
  void initState() {
    super.initState();
    if (_isActiveToday) {
      _pulseController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previewColors = widget.schedule.colors.isEmpty
        ? <Color>[]
        : widget.schedule.colors.take(3).map((c) => Color(c | 0xFF000000)).toList();

    final recurrence = _formatDays(widget.schedule.daysOfWeek);

    // Build the trailing widget with optional pulse dot + paused badge
    Widget trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isActiveToday && _pulseController != null)
          AnimatedBuilder(
            animation: _pulseController!,
            builder: (_, __) {
              return Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NexGenPalette.violet,
                  boxShadow: [
                    BoxShadow(
                      color: NexGenPalette.violet.withValues(
                        alpha: 0.3 + _pulseController!.value * 0.4,
                      ),
                      blurRadius: 4 + _pulseController!.value * 4,
                      spreadRadius: _pulseController!.value * 2,
                    ),
                  ],
                ),
              );
            },
          ),
        if (!widget.schedule.isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Paused',
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ),
        const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      ],
    );

    return ScheduleIdentityCard(
      type: ScheduleEntryType.neighborhoodSync,
      patternName: widget.schedule.patternName,
      previewColors: previewColors,
      effectName: widget.schedule.syncType.displayName,
      timeLabel: widget.schedule.timeRangeString,
      recurrenceLabel: recurrence,
      onTap: widget.onTap,
      trailing: trailing,
    );
  }

  String _formatDays(List<int> days) {
    if (days.length == 7) return 'Daily';
    if (days.length == 5 && !days.contains(6) && !days.contains(7)) return 'Weekdays';
    if (days.length == 2 && days.contains(6) && days.contains(7)) return 'Weekends';
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days.map((d) => dayNames[d - 1]).join(', ');
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// CREATE SCHEDULE CHOOSER (two-option bottom sheet)
// ═══════════════════════════════════════════════════════════════════════════════

class _CreateScheduleChooser extends StatelessWidget {
  final String groupId;
  final VoidCallback onLibrarySelected;
  final VoidCallback onGameDaySelected;

  const _CreateScheduleChooser({
    required this.groupId,
    required this.onLibrarySelected,
    required this.onGameDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            const Row(
              children: [
                Icon(Icons.calendar_month, color: NexGenPalette.violet, size: 22),
                SizedBox(width: 10),
                Text(
                  'Create Schedule',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Option 1: Choose from Library
            _ChooserOption(
              icon: Icons.palette_outlined,
              iconColor: NexGenPalette.violet,
              title: 'Choose from Library',
              subtitle: 'Browse Explore Patterns',
              onTap: onLibrarySelected,
            ),

            const SizedBox(height: 12),

            // Option 2: Game Day Autopilot
            _ChooserOption(
              icon: Icons.sports_football,
              iconColor: NexGenPalette.cyan,
              title: 'Game Day Autopilot',
              subtitle: 'Auto-schedule around game times',
              onTap: onGameDaySelected,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChooserOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChooserOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SELECTED PATTERN RESULT
// ═══════════════════════════════════════════════════════════════════════════════

/// Data returned from the Explore Patterns picker when a pattern is confirmed.
class _SelectedPatternResult {
  final String patternName;
  final int effectId;
  final List<int> colors;

  const _SelectedPatternResult({
    required this.patternName,
    required this.effectId,
    required this.colors,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
// EXPLORE PATTERNS PICKER (full library browser in a modal route)
// ═══════════════════════════════════════════════════════════════════════════════

/// Full-screen modal that wraps [ExplorePatternsScreen] with a "Use This
/// Pattern" FAB. The user browses and taps patterns to preview on device
/// as normal. Tapping the FAB captures the current WLED state and returns
/// it as a [_SelectedPatternResult].
class _ExplorePatternsPicker extends ConsumerWidget {
  final String groupId;

  const _ExplorePatternsPicker({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: Stack(
        children: [
          // The full Explore Patterns library, unmodified
          const ExplorePatternsScreen(),

          // Close button overlaid at top-left (above the library's own app bar)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: Material(
              color: Colors.transparent,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: NexGenPalette.gunmetal90,
                    shape: BoxShape.circle,
                    border: Border.all(color: NexGenPalette.line),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),

      // FAB: "Use This Pattern" — reads current WLED state and pops with result
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton.extended(
          onPressed: () => _confirmSelection(context, ref),
          backgroundColor: NexGenPalette.violet,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.check, size: 20),
          label: const Text(
            'Use This Pattern',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _confirmSelection(BuildContext context, WidgetRef ref) {
    final wledState = ref.read(wledStateProvider);

    // Extract colors as ARGB ints from the current device state
    final colors = wledState.displayColors
        .take(3)
        .map((c) => ((c.a * 255).round() << 24) |
            ((c.r * 255).round() << 16) |
            ((c.g * 255).round() << 8) |
            (c.b * 255).round())
        .toList();

    Navigator.pop(
      context,
      _SelectedPatternResult(
        patternName: wledState.effectName,
        effectId: wledState.effectId,
        colors: colors,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCHEDULE TIME CONFIG SHEET (Step 2: days/time/recurrence)
// ═══════════════════════════════════════════════════════════════════════════════

/// Bottom sheet for configuring schedule timing after a pattern has been
/// selected from the Explore Patterns library. The back arrow re-opens the
/// library picker (by closing this sheet and letting the caller re-trigger).
class _ScheduleTimeConfigSheet extends ConsumerStatefulWidget {
  final String groupId;
  final String patternName;
  final int effectId;
  final List<int> colors;

  const _ScheduleTimeConfigSheet({
    required this.groupId,
    required this.patternName,
    required this.effectId,
    required this.colors,
  });

  @override
  ConsumerState<_ScheduleTimeConfigSheet> createState() =>
      _ScheduleTimeConfigSheetState();
}

class _ScheduleTimeConfigSheetState
    extends ConsumerState<_ScheduleTimeConfigSheet> {
  SyncType _syncType = SyncType.sequentialFlow;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 30));
  TimeOfDay _startTime = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 23, minute: 0);
  bool _useSunset = false;
  final List<int> _selectedDays = [1, 2, 3, 4, 5, 6, 7];
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
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Back arrow returns to library (closes this sheet)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    constraints: const BoxConstraints(minWidth: 36),
                    padding: EdgeInsets.zero,
                    tooltip: 'Back to library',
                  ),
                  const Icon(Icons.calendar_month, color: NexGenPalette.violet),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Schedule "${widget.patternName}"',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: Colors.grey.shade500)),
                  ),
                ],
              ),
            ),

            // Time configuration form
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // Sync Mode
                  _buildSectionLabel('Sync Mode'),
                  _buildSyncTypeSelector(),
                  const SizedBox(height: 20),

                  // Date Range
                  _buildSectionLabel('Date Range'),
                  _buildDateRangePicker(),
                  const SizedBox(height: 20),

                  // Time Range
                  _buildSectionLabel('Daily Time'),
                  _buildTimeRangePicker(),
                  const SizedBox(height: 20),

                  // Days of Week
                  _buildSectionLabel('Days'),
                  _buildDaySelector(),
                  const SizedBox(height: 20),

                  // Notification Message
                  _buildSectionLabel('Notify Group (optional)'),
                  TextField(
                    onChanged: (v) => _notificationMessage = v,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'e.g., "Holiday lights week!"',
                      hintStyle: TextStyle(color: Colors.grey.shade700),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade700),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: NexGenPalette.violet),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Create Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _createSchedule,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: NexGenPalette.violet,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Create Schedule',
                              style: TextStyle(fontWeight: FontWeight.bold)),
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

  // ── Form helpers ────────────────────────────────────────────────────

  Widget _buildSectionLabel(String title) {
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
                color: isSelected
                    ? NexGenPalette.violet.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(type.icon,
                      color: isSelected
                          ? NexGenPalette.violet
                          : Colors.grey.shade500,
                      size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      type.displayName,
                      style: TextStyle(
                        color: isSelected ? NexGenPalette.violet : Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check, color: NexGenPalette.violet, size: 18),
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
            child: _buildDateButton(
                'Start', _startDate, (d) => setState(() => _startDate = d))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.arrow_forward,
              color: Colors.grey.shade600, size: 20),
        ),
        Expanded(
            child: _buildDateButton(
                'End', _endDate, (d) => setState(() => _endDate = d))),
      ],
    );
  }

  Widget _buildDateButton(
      String label, DateTime date, Function(DateTime) onSelect) {
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
        Row(
          children: [
            Checkbox(
              value: _useSunset,
              onChanged: (v) => setState(() => _useSunset = v ?? false),
              activeColor: NexGenPalette.violet,
            ),
            const Text('Start at sunset',
                style: TextStyle(color: Colors.white)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildTimeButton(
                _useSunset ? 'Sunset' : _formatTimeOfDay(_startTime),
                _useSunset ? null : () => _pickTime(true),
                enabled: !_useSunset,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.arrow_forward,
                  color: Colors.grey.shade600, size: 20),
            ),
            Expanded(
              child: _buildTimeButton(
                _formatTimeOfDay(_endTime),
                () => _pickTime(false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeButton(String text, VoidCallback? onTap,
      {bool enabled = true}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: enabled ? Colors.black26 : NexGenPalette.gunmetal,
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
              style: TextStyle(
                  color: enabled ? Colors.white : Colors.orange.shade300),
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
              color: isSelected
                  ? NexGenPalette.violet.withValues(alpha: 0.3)
                  : Colors.grey.shade800,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? NexGenPalette.violet : Colors.grey.shade700,
              ),
            ),
            child: Center(
              child: Text(
                dayNames[i],
                style: TextStyle(
                  color: isSelected
                      ? NexGenPalette.violet
                      : Colors.grey.shade500,
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

  String _formatTimeOfDay(TimeOfDay time) {
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
      patternName: widget.patternName,
      effectId: widget.effectId,
      colors: widget.colors,
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
      daysOfWeek: List<int>.from(_selectedDays),
      createdBy: '',
      createdAt: DateTime.now(),
      notificationMessage:
          _notificationMessage.isNotEmpty ? _notificationMessage : null,
    );

    final result = await ref
        .read(neighborhoodNotifierProvider.notifier)
        .createSchedule(schedule);

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

// ═══════════════════════════════════════════════════════════════════════════════
// GAME DAY SCHEDULE WRAPPER
// ═══════════════════════════════════════════════════════════════════════════════

/// Placeholder wrapper that navigates to the existing Game Day Fan Zone
/// team selection flow. When configuration is complete, it returns to the
/// sync control center.
class _GameDayScheduleWrapper extends StatelessWidget {
  const _GameDayScheduleWrapper();

  @override
  Widget build(BuildContext context) {
    // Use the existing GameDaySetupScreen from the neighborhood widgets
    // This import is already available transitively
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Game Day Autopilot'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sports_football, size: 48, color: NexGenPalette.cyan),
              SizedBox(height: 16),
              Text(
                'Game Day Autopilot',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Configure via the Game Day Fan Zone\nin your team settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SCHEDULE DETAILS SHEET
// ═══════════════════════════════════════════════════════════════════════════════

class _ScheduleDetailsSheet extends ConsumerWidget {
  final SyncSchedule schedule;

  const _ScheduleDetailsSheet({required this.schedule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMember = ref.watch(currentUserMemberProvider);
    final isOptedOut = currentMember?.isOptedOutOf(schedule.id) ?? false;

    final previewColors = schedule.colors.isEmpty
        ? [NexGenPalette.violet, NexGenPalette.cyan]
        : schedule.colors.take(2).map((c) => Color(c | 0xFF000000)).toList();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with color preview + badge
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: previewColors),
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
              const ScheduleTypeBadge(type: ScheduleEntryType.neighborhoodSync),
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
                color: NexGenPalette.violet.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_outlined, color: NexGenPalette.violet, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      schedule.notificationMessage!,
                      style: const TextStyle(color: NexGenPalette.violet, fontSize: 13),
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
