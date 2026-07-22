import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/models/commercial/business_hours.dart';
import 'package:nexgen_command/models/commercial/channel_role.dart';
import 'package:nexgen_command/models/commercial/commercial_role.dart';
import 'package:nexgen_command/models/commercial/commercial_schedule.dart';
import 'package:nexgen_command/models/commercial/day_part.dart';
import 'package:nexgen_command/models/commercial/holiday_calendar.dart';
import 'package:nexgen_command/services/commercial/commercial_providers.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

// =============================================================================
// PROVIDERS — local state for the schedule screen
// =============================================================================

/// Currently selected day-of-week tab.
final _selectedDayProvider =
    StateProvider<DayOfWeek>((ref) => dayOfWeekFromIso(DateTime.now().weekday));

/// Local working copy of the commercial schedule for optimistic updates.
/// Initialise from Firestore; mutate locally, then write-behind.
final _workingScheduleProvider =
    StateProvider<CommercialSchedule?>((ref) => null);

/// Channel role configs for the current location.
final _channelConfigsProvider =
    StateProvider<List<ChannelRoleConfig>>((ref) => []);

/// Business hours for the current location.
final _businessHoursProvider = StateProvider<BusinessHours?>((ref) => null);

/// Holiday calendar for the current location.
final _holidayCalendarProvider = StateProvider<HolidayCalendar?>((ref) => null);

/// User's commercial role at this location.
final _userRoleProvider = StateProvider<CommercialRole?>((ref) => null);

/// Whether the quick-actions panel is expanded.
final _quickActionsExpandedProvider = StateProvider<bool>((ref) => true);

// =============================================================================
// CommercialScheduleScreen
// =============================================================================

class CommercialScheduleScreen extends ConsumerStatefulWidget {
  final String locationId;
  final String locationName;
  final String? orgName;

  const CommercialScheduleScreen({
    super.key,
    required this.locationId,
    required this.locationName,
    this.orgName,
  });

  @override
  ConsumerState<CommercialScheduleScreen> createState() =>
      _CommercialScheduleScreenState();
}

class _CommercialScheduleScreenState
    extends ConsumerState<CommercialScheduleScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      final db = FirebaseFirestore.instance;
      final uid = _currentUid();
      if (uid == null) return;

      // Parallel fetches
      final schedDoc = db
          .collection('users')
          .doc(uid)
          .collection('commercial_schedule')
          .doc(widget.locationId)
          .get();
      final locDoc = db
          .collection('users')
          .doc(uid)
          .collection('commercial_locations')
          .doc(widget.locationId)
          .get();

      final results = await Future.wait([schedDoc, locDoc]);

      // Schedule
      final schedSnap = results[0];
      if (schedSnap.exists && schedSnap.data() != null) {
        ref.read(_workingScheduleProvider.notifier).state =
            CommercialSchedule.fromJson(schedSnap.data()!);
      } else {
        ref.read(_workingScheduleProvider.notifier).state = CommercialSchedule(
          locationId: widget.locationId,
        );
      }

      // Location → channel configs, business hours, holiday calendar
      final locSnap = results[1];
      if (locSnap.exists && locSnap.data() != null) {
        final locData = locSnap.data()!;
        final channels = (locData['channel_configs'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map((e) => ChannelRoleConfig.fromJson(e))
                .toList() ??
            [];
        ref.read(_channelConfigsProvider.notifier).state = channels;

        if (locData['business_hours'] is Map<String, dynamic>) {
          ref.read(_businessHoursProvider.notifier).state =
              BusinessHours.fromJson(
                  locData['business_hours'] as Map<String, dynamic>);
        }

        if (locData['holiday_calendar'] is Map<String, dynamic>) {
          ref.read(_holidayCalendarProvider.notifier).state =
              HolidayCalendar.fromJson(
                  locData['holiday_calendar'] as Map<String, dynamic>);
        }
      }

      // Resolve user role
      final permService =
          ref.read(commercialPermissionsServiceProvider);
      final role = await permService.getCurrentUserRole(widget.locationId);
      ref.read(_userRoleProvider.notifier).state = role;
    } catch (e) {
      debugPrint('CommercialScheduleScreen load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _currentUid() => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(_workingScheduleProvider);
    final isLocked = schedule?.isLockedByCorporate ?? false;

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: GlassAppBar(
        title: Text(
          widget.locationName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (!isLocked)
            IconButton(
              icon: const Icon(Icons.undo_rounded, size: 20),
              tooltip: 'Undo last change',
              onPressed: () {
                // TODO: undo stack
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: NexGenPalette.cyan))
          : Column(
              children: [
                // Corporate lock banner
                if (isLocked) _CorporateLockBanner(orgName: widget.orgName),
                // Day selector
                const _DaySelectorRow(),
                // Holiday banner (if applicable)
                _HolidayBanner(day: ref.watch(_selectedDayProvider)),
                // Timeline content
                Expanded(
                  child: _TimelineBody(
                    isLocked: isLocked,
                    onScheduleChanged: _onScheduleChanged,
                  ),
                ),
                // Quick actions
                _QuickActionsPanel(
                  locationId: widget.locationId,
                  isLocked: isLocked,
                  onScheduleChanged: _onScheduleChanged,
                ),
              ],
            ),
    );
  }

  void _onScheduleChanged(CommercialSchedule updated) {
    // Optimistic local update
    ref.read(_workingScheduleProvider.notifier).state = updated;
    // Write-behind to Firestore
    _persistSchedule(updated);
  }

  Future<void> _persistSchedule(CommercialSchedule schedule) async {
    try {
      final uid = _currentUid();
      if (uid == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('commercial_schedule')
          .doc(widget.locationId)
          .set(schedule.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Schedule persist error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save schedule. Reverting...'),
            backgroundColor: Colors.red.shade800,
          ),
        );
        // Revert — reload from Firestore
        _loadData();
      }
    }
  }
}

// =============================================================================
// CORPORATE LOCK BANNER
// =============================================================================

class _CorporateLockBanner extends StatelessWidget {
  final String? orgName;
  const _CorporateLockBanner({this.orgName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: NexGenPalette.amber.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, size: 16, color: NexGenPalette.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              orgName != null
                  ? 'This schedule is managed by $orgName. Contact your admin.'
                  : 'This schedule is locked by corporate. Contact your admin.',
              style: const TextStyle(
                color: NexGenPalette.amber,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DAY SELECTOR ROW
// =============================================================================

class _DaySelectorRow extends ConsumerWidget {
  const _DaySelectorRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(_selectedDayProvider);

    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        border: Border(
          bottom: BorderSide(color: NexGenPalette.line, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: DayOfWeek.values.length,
              itemBuilder: (context, i) {
                final day = DayOfWeek.values[i];
                final isSelected = day == selected;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _DayTab(
                    day: day,
                    isSelected: isSelected,
                    onTap: () =>
                        ref.read(_selectedDayProvider.notifier).state = day,
                  ),
                );
              },
            ),
          ),
          _CopyDayButton(selectedDay: selected),
        ],
      ),
    );
  }
}

class _DayTab extends StatelessWidget {
  final DayOfWeek day;
  final bool isSelected;
  final VoidCallback onTap;

  const _DayTab({
    required this.day,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? NexGenPalette.cyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: isSelected
              ? Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.4))
              : null,
        ),
        child: Text(
          day.shortName,
          style: TextStyle(
            color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _CopyDayButton extends ConsumerWidget {
  final DayOfWeek selectedDay;
  const _CopyDayButton({required this.selectedDay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => _showCopyDaySheet(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(
              color: NexGenPalette.line,
            ),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.copy_rounded, size: 14, color: NexGenPalette.textMedium),
              SizedBox(width: 4),
              Text(
                'Copy',
                style: TextStyle(
                  color: NexGenPalette.textMedium,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCopyDaySheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CopyDaySheet(sourceDay: selectedDay),
    );
  }
}

// =============================================================================
// COPY DAY BOTTOM SHEET
// =============================================================================

class _CopyDaySheet extends ConsumerWidget {
  final DayOfWeek sourceDay;
  const _CopyDaySheet({required this.sourceDay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetDays =
        DayOfWeek.values.where((d) => d != sourceDay).toList();

    return Container(
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDragHandle(),
              const SizedBox(height: 8),
              Text(
                'Copy ${sourceDay.displayName} to...',
                style: const TextStyle(
                  color: NexGenPalette.textHigh,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ...targetDays.map((day) => ListTile(
                    title: Text(day.displayName,
                        style:
                            const TextStyle(color: NexGenPalette.textHigh)),
                    leading: const Icon(Icons.calendar_today_rounded,
                        size: 18, color: NexGenPalette.textMedium),
                    onTap: () {
                      _copyScheduleToDay(ref, day);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Copied ${sourceDay.shortName} schedule to ${day.shortName}'),
                          backgroundColor: NexGenPalette.gunmetal,
                        ),
                      );
                    },
                  )),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _copyScheduleToDay(WidgetRef ref, DayOfWeek targetDay) {
    final schedule = ref.read(_workingScheduleProvider);
    if (schedule == null) return;

    // Find day-parts that include the source day
    final sourceParts = schedule.dayParts
        .where((dp) =>
            dp.daysOfWeek.isEmpty || dp.daysOfWeek.contains(sourceDay))
        .toList();

    // For each source part, ensure the target day is also included
    final updatedParts = List<DayPart>.from(schedule.dayParts);
    for (final sp in sourceParts) {
      if (sp.daysOfWeek.isEmpty) continue; // applies to all days already
      final idx = updatedParts.indexWhere((p) => p.id == sp.id);
      if (idx < 0) continue;
      final existing = updatedParts[idx];
      if (!existing.daysOfWeek.contains(targetDay)) {
        updatedParts[idx] = existing.copyWith(
          daysOfWeek: [...existing.daysOfWeek, targetDay],
        );
      }
    }

    ref.read(_workingScheduleProvider.notifier).state =
        schedule.copyWith(dayParts: updatedParts);
  }

  Widget _buildDragHandle() => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: NexGenPalette.textSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

// =============================================================================
// HOLIDAY BANNER
// =============================================================================

class _HolidayBanner extends ConsumerWidget {
  final DayOfWeek day;
  const _HolidayBanner({required this.day});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendar = ref.watch(_holidayCalendarProvider);
    if (calendar == null) return const SizedBox.shrink();

    // Check if the selected day has a holiday this week
    final now = DateTime.now();
    final dayDelta = day.isoWeekday - now.weekday;
    final targetDate = now.add(Duration(days: dayDelta));

    String? holidayName;
    if (calendar.isStandardHoliday(targetDate)) {
      for (final h in StandardHoliday.values) {
        if (_sameDay(h.dateForYear(targetDate.year), targetDate)) {
          holidayName = h.displayName;
          break;
        }
      }
    }
    if (calendar.isCustomClosure(targetDate)) {
      holidayName ??= 'Custom Closure';
    }
    final event = calendar.activeSpecialEvent(targetDate);
    if (event != null) {
      holidayName = event.name;
    }

    if (holidayName == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: NexGenPalette.amber.withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.celebration_rounded,
              size: 16, color: NexGenPalette.amber),
          const SizedBox(width: 8),
          Text(
            holidayName,
            style: const TextStyle(
              color: NexGenPalette.amber,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: NexGenPalette.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'HOLIDAY',
              style: TextStyle(
                color: NexGenPalette.amber,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// =============================================================================
// TIMELINE BODY — horizontal scrollable, vertical per channel
// =============================================================================

class _TimelineBody extends ConsumerWidget {
  final bool isLocked;
  final ValueChanged<CommercialSchedule> onScheduleChanged;

  const _TimelineBody({
    required this.isLocked,
    required this.onScheduleChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(_channelConfigsProvider);
    final schedule = ref.watch(_workingScheduleProvider);
    final hours = ref.watch(_businessHoursProvider);
    final selectedDay = ref.watch(_selectedDayProvider);

    if (schedule == null || hours == null) {
      return const Center(
        child: Text('No schedule data',
            style: TextStyle(color: NexGenPalette.textMedium)),
      );
    }

    // Calculate timeline window from business hours
    final daySchedule = hours.weeklySchedule[selectedDay];
    final isOpen = daySchedule?.isOpen ?? false;

    if (!isOpen) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_rounded,
                size: 48, color: NexGenPalette.textMedium.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('Closed',
                style: TextStyle(
                    color: NexGenPalette.textHigh,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('${selectedDay.displayName} — No business hours configured',
                style: const TextStyle(
                    color: NexGenPalette.textMedium, fontSize: 13)),
          ],
        ),
      );
    }

    // Determine timeline range: pre-open buffer → post-close buffer
    final openMin = daySchedule!.openTime.hour * 60 + daySchedule.openTime.minute;
    final closeMin = daySchedule.closeTime.hour * 60 + daySchedule.closeTime.minute;
    final effectiveClose = closeMin > openMin ? closeMin : closeMin + 24 * 60;
    final timelineStartMin =
        (openMin - hours.preOpenBufferMinutes).clamp(0, 24 * 60);
    final timelineEndMin = (effectiveClose + hours.postCloseWindDownMinutes)
        .clamp(0, 24 * 60 + hours.postCloseWindDownMinutes);
    final totalMinutes = timelineEndMin - timelineStartMin;

    // Filter day-parts for selected day
    final dayParts = schedule.dayParts
        .where((dp) =>
            dp.daysOfWeek.isEmpty || dp.daysOfWeek.contains(selectedDay))
        .toList()
      ..sort((a, b) {
        final aMin = a.startTime.hour * 60 + a.startTime.minute;
        final bMin = b.startTime.hour * 60 + b.startTime.minute;
        return aMin.compareTo(bMin);
      });

    // Pixel-per-minute: 4px/min for comfortable horizontal scrolling
    const pxPerMin = 4.0;
    final totalWidth = totalMinutes * pxPerMin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Time ruler
        SizedBox(
          height: 28,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 100),
            child: _TimeRuler(
              startMin: timelineStartMin,
              endMin: timelineEndMin,
              pxPerMin: pxPerMin,
            ),
          ),
        ),
        const Divider(color: NexGenPalette.line, height: 1),
        // Channel rows
        Expanded(
          child: channels.isEmpty
              ? const Center(
                  child: Text('No channels configured',
                      style: TextStyle(color: NexGenPalette.textMedium)))
              : ListView.builder(
                  itemCount: channels.length,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemBuilder: (context, i) {
                    final channel = channels[i];
                    return _ChannelTimelineRow(
                      channel: channel,
                      dayParts: dayParts,
                      schedule: schedule,
                      timelineStartMin: timelineStartMin,
                      timelineEndMin: timelineEndMin,
                      totalWidth: totalWidth,
                      pxPerMin: pxPerMin,
                      isLocked: isLocked,
                      coveragePolicy: schedule.coveragePolicy,
                      onScheduleChanged: onScheduleChanged,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// =============================================================================
// TIME RULER
// =============================================================================

class _TimeRuler extends StatelessWidget {
  final int startMin;
  final int endMin;
  final double pxPerMin;

  const _TimeRuler({
    required this.startMin,
    required this.endMin,
    required this.pxPerMin,
  });

  @override
  Widget build(BuildContext context) {
    final ticks = <Widget>[];
    // Place a label every 60 minutes, aligned to the hour
    final firstHour = ((startMin + 59) ~/ 60) * 60;
    for (var min = firstHour; min <= endMin; min += 60) {
      final offset = (min - startMin) * pxPerMin;
      final hour = (min ~/ 60) % 24;
      final label = hour == 0
          ? '12a'
          : hour < 12
              ? '${hour}a'
              : hour == 12
                  ? '12p'
                  : '${hour - 12}p';
      ticks.add(Positioned(
        left: offset - 12,
        top: 0,
        child: SizedBox(
          width: 24,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ));
    }

    final totalWidth = (endMin - startMin) * pxPerMin;
    return SizedBox(
      width: totalWidth,
      child: Stack(children: ticks),
    );
  }
}

// =============================================================================
// CHANNEL TIMELINE ROW
// =============================================================================

class _ChannelTimelineRow extends ConsumerWidget {
  final ChannelRoleConfig channel;
  final List<DayPart> dayParts;
  final CommercialSchedule schedule;
  final int timelineStartMin;
  final int timelineEndMin;
  final double totalWidth;
  final double pxPerMin;
  final bool isLocked;
  final CoveragePolicy coveragePolicy;
  final ValueChanged<CommercialSchedule> onScheduleChanged;

  const _ChannelTimelineRow({
    required this.channel,
    required this.dayParts,
    required this.schedule,
    required this.timelineStartMin,
    required this.timelineEndMin,
    required this.totalWidth,
    required this.pxPerMin,
    required this.isLocked,
    required this.coveragePolicy,
    required this.onScheduleChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowHeight = 56.0;
    final roleColor = _roleColor(channel.role);

    return Container(
      height: rowHeight,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: NexGenPalette.line, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Channel label
          SizedBox(
            width: 100,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(channel.role.icon,
                      size: 14, color: roleColor.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      channel.friendlyName,
                      style: const TextStyle(
                        color: NexGenPalette.textHigh,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Vertical divider
          Container(width: 1, color: NexGenPalette.line),
          // Timeline blocks
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                height: rowHeight,
                child: Stack(
                  children: _buildBlocks(context, ref, roleColor, rowHeight),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBlocks(
      BuildContext context, WidgetRef ref, Color roleColor, double rowHeight) {
    final widgets = <Widget>[];

    // Sort day-parts by start time
    final sorted = List<DayPart>.from(dayParts)
      ..sort((a, b) {
        final aMin = a.startTime.hour * 60 + a.startTime.minute;
        final bMin = b.startTime.hour * 60 + b.startTime.minute;
        return aMin.compareTo(bMin);
      });

    int lastEndMin = timelineStartMin;

    for (final dp in sorted) {
      final dpStartMin = dp.startTime.hour * 60 + dp.startTime.minute;
      final dpEndMin = dp.endTime.hour * 60 + dp.endTime.minute;
      final effectiveDpEnd = dpEndMin > dpStartMin ? dpEndMin : dpEndMin + 24 * 60;

      // Clamp to timeline bounds
      final blockStart = dpStartMin.clamp(timelineStartMin, timelineEndMin);
      final blockEnd = effectiveDpEnd.clamp(timelineStartMin, timelineEndMin);

      // Gap before this block
      if (blockStart > lastEndMin) {
        widgets.add(_buildGapBlock(
          context,
          ref,
          lastEndMin,
          blockStart,
          rowHeight,
        ));
      }

      // Scheduled block
      final left = (blockStart - timelineStartMin) * pxPerMin;
      final width = (blockEnd - blockStart) * pxPerMin;

      if (width > 0) {
        widgets.add(Positioned(
          left: left,
          top: 4,
          width: width,
          height: rowHeight - 8,
          child: _ScheduledBlock(
            dayPart: dp,
            roleColor: roleColor,
            isLocked: isLocked,
            onTap: () => _showBlockDetail(context, ref, dp),
            onLongPress: isLocked ? null : () => _enterDragMode(context, dp),
          ),
        ));
      }

      lastEndMin = blockEnd;
    }

    // Trailing gap
    if (lastEndMin < timelineEndMin) {
      widgets.add(_buildGapBlock(
        context,
        ref,
        lastEndMin,
        timelineEndMin,
        rowHeight,
      ));
    }

    return widgets;
  }

  Widget _buildGapBlock(
    BuildContext context,
    WidgetRef ref,
    int gapStartMin,
    int gapEndMin,
    double rowHeight,
  ) {
    final left = (gapStartMin - timelineStartMin) * pxPerMin;
    final width = (gapEndMin - gapStartMin) * pxPerMin;

    final isSmartFill = coveragePolicy == CoveragePolicy.smartFill;
    final isScheduledOnly = coveragePolicy == CoveragePolicy.scheduledOnly;

    return Positioned(
      left: left,
      top: 4,
      width: width,
      height: rowHeight - 8,
      child: GestureDetector(
        onTap: isLocked
            ? null
            : () => _showGapAssignSheet(context, ref, gapStartMin, gapEndMin),
        child: isSmartFill
            ? _SmartFillBlock(width: width, height: rowHeight - 8)
            : isScheduledOnly
                ? _EmptyGapBlock(width: width, height: rowHeight - 8)
                : const SizedBox.shrink(), // alwaysOn has no visual gap
      ),
    );
  }

  void _showBlockDetail(BuildContext context, WidgetRef ref, DayPart dp) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BlockDetailSheet(
        dayPart: dp,
        isLocked: isLocked,
        schedule: schedule,
        onDelete: () {
          final updated = schedule.copyWith(
            dayParts: schedule.dayParts.where((p) => p.id != dp.id).toList(),
          );
          onScheduleChanged(updated);
          Navigator.pop(context);
        },
        onEdit: () {
          Navigator.pop(context);
          // TODO: open day-part edit screen
        },
      ),
    );
  }

  void _showGapAssignSheet(
      BuildContext context, WidgetRef ref, int startMin, int endMin) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _GapAssignSheet(
        startMin: startMin,
        endMin: endMin,
        schedule: schedule,
        onScheduleChanged: onScheduleChanged,
      ),
    );
  }

  void _enterDragMode(BuildContext context, DayPart dp) {
    HapticFeedback.mediumImpact();
    // TODO: implement drag/resize with 15-min snap
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Drag to resize — snap to 15 min increments'),
        duration: Duration(seconds: 2),
        backgroundColor: NexGenPalette.gunmetal,
      ),
    );
  }

  Color _roleColor(ChannelRoleType role) {
    switch (role) {
      case ChannelRoleType.interior:
        return NexGenPalette.cyan;
      case ChannelRoleType.outdoorFacade:
        return NexGenPalette.green;
      case ChannelRoleType.windowDisplay:
        return NexGenPalette.violet;
      case ChannelRoleType.patio:
        return const Color(0xFFFF8A50);
      case ChannelRoleType.canopy:
        return const Color(0xFF64B5F6);
      case ChannelRoleType.signage:
        return NexGenPalette.amber;
    }
  }
}

// =============================================================================
// SCHEDULED BLOCK — solid tile with role-color fill
// =============================================================================

class _ScheduledBlock extends StatelessWidget {
  final DayPart dayPart;
  final Color roleColor;
  final bool isLocked;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ScheduledBlock({
    required this.dayPart,
    required this.roleColor,
    required this.isLocked,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isGameDay = dayPart.isGameDayOverride;
    final hasBrandColor = dayPart.useBrandColors;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: roleColor.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isGameDay
                ? NexGenPalette.gold
                : roleColor.withValues(alpha: 0.5),
            width: isGameDay ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Stack(
          children: [
            // Design name
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dayPart.name,
                  style: TextStyle(
                    color: NexGenPalette.textHigh,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (dayPart.assignedDesignId != null)
                  Text(
                    dayPart.assignedDesignId!,
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 9,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            // Brand color badge
            if (hasBrandColor)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: roleColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: NexGenPalette.matteBlack, width: 0.5),
                  ),
                ),
              ),
            // Game Day badge
            if (isGameDay)
              Positioned(
                top: 0,
                right: hasBrandColor ? 10 : 0,
                child: Icon(Icons.sports_football_rounded,
                    size: 10, color: NexGenPalette.gold),
              ),
            // Corporate lock overlay
            if (isLocked)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Icon(Icons.lock_rounded,
                        size: 14, color: NexGenPalette.textMedium),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// SMART FILL BLOCK — hatched/striped pattern
// =============================================================================

class _SmartFillBlock extends StatelessWidget {
  final double width;
  final double height;
  const _SmartFillBlock({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        painter: _HatchPainter(
          color: NexGenPalette.cyan.withValues(alpha: 0.1),
          lineColor: NexGenPalette.cyan.withValues(alpha: 0.15),
        ),
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          child: const Text(
            'Auto',
            style: TextStyle(
              color: NexGenPalette.cyan,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _HatchPainter extends CustomPainter {
  final Color color;
  final Color lineColor;

  _HatchPainter({required this.color, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Background fill
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = color,
    );

    // Diagonal stripes
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    const spacing = 8.0;
    for (var x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.lineColor != lineColor;
}

// =============================================================================
// EMPTY GAP BLOCK — dashed border, dark background
// =============================================================================

class _EmptyGapBlock extends StatelessWidget {
  final double width;
  final double height;
  const _EmptyGapBlock({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: NexGenPalette.textMedium.withValues(alpha: 0.25),
      ),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: NexGenPalette.matteBlack.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const dashWidth = 4.0;
    const dashSpace = 3.0;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(6),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(
          metric.extractPath(distance, end),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

// =============================================================================
// BLOCK DETAIL BOTTOM SHEET
// =============================================================================

class _BlockDetailSheet extends StatelessWidget {
  final DayPart dayPart;
  final bool isLocked;
  final CommercialSchedule schedule;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _BlockDetailSheet({
    required this.dayPart,
    required this.isLocked,
    required this.schedule,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final startStr = _formatTime(dayPart.startTime);
    final endStr = _formatTime(dayPart.endTime);

    return Container(
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDragHandle(),
              const SizedBox(height: 12),
              // Day-part name
              Text(
                dayPart.name,
                style: const TextStyle(
                  color: NexGenPalette.textHigh,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              // Time range
              Text(
                '$startStr – $endStr',
                style: const TextStyle(
                  color: NexGenPalette.cyan,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              // Details
              _DetailRow(
                icon: Icons.palette_rounded,
                label: 'Design',
                value: dayPart.assignedDesignId ?? 'None assigned',
              ),
              _DetailRow(
                icon: Icons.color_lens_rounded,
                label: 'Brand Colors',
                value: dayPart.useBrandColors ? 'Active' : 'Off',
              ),
              if (dayPart.isGameDayOverride)
                _DetailRow(
                  icon: Icons.sports_football_rounded,
                  label: 'Override',
                  value: 'Game Day',
                  valueColor: NexGenPalette.gold,
                ),
              if (isLocked)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Locked by corporate — view only',
                    style: TextStyle(
                        color: NexGenPalette.amber, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),
              // Actions
              if (!isLocked)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_rounded, size: 16),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: NexGenPalette.cyan,
                          side: BorderSide(
                              color: NexGenPalette.cyan.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onDelete,
                        icon: const Icon(Icons.delete_rounded, size: 16),
                        label: const Text('Delete'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: BorderSide(
                              color: Colors.redAccent.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:${t.minute.toString().padLeft(2, '0')} $period';
  }

  Widget _buildDragHandle() => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: NexGenPalette.textSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: NexGenPalette.textMedium),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 13)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                color: valueColor ?? NexGenPalette.textHigh,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              )),
        ],
      ),
    );
  }
}

// =============================================================================
// GAP ASSIGN BOTTOM SHEET
// =============================================================================

class _GapAssignSheet extends ConsumerStatefulWidget {
  final int startMin;
  final int endMin;
  final CommercialSchedule schedule;
  final ValueChanged<CommercialSchedule> onScheduleChanged;

  const _GapAssignSheet({
    required this.startMin,
    required this.endMin,
    required this.schedule,
    required this.onScheduleChanged,
  });

  @override
  ConsumerState<_GapAssignSheet> createState() => _GapAssignSheetState();
}

class _GapAssignSheetState extends ConsumerState<_GapAssignSheet> {
  String _name = '';
  String _designId = '';

  @override
  Widget build(BuildContext context) {
    final startTime = TimeOfDay(
        hour: widget.startMin ~/ 60, minute: widget.startMin % 60);
    final endTime =
        TimeOfDay(hour: widget.endMin ~/ 60, minute: widget.endMin % 60);

    return Container(
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDragHandle(),
              const SizedBox(height: 12),
              const Text(
                'Assign Design',
                style: TextStyle(
                  color: NexGenPalette.textHigh,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_formatTime(startTime)} – ${_formatTime(endTime)}',
                style: const TextStyle(
                    color: NexGenPalette.cyan, fontSize: 14),
              ),
              const SizedBox(height: 16),
              // Name field
              TextField(
                onChanged: (v) => setState(() => _name = v),
                style: const TextStyle(color: NexGenPalette.textHigh),
                decoration: InputDecoration(
                  labelText: 'Day-Part Name',
                  labelStyle: const TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: NexGenPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: NexGenPalette.cyan),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              // Design ID field
              TextField(
                onChanged: (v) => setState(() => _designId = v),
                style: const TextStyle(color: NexGenPalette.textHigh),
                decoration: InputDecoration(
                  labelText: 'Design ID (or leave empty for Smart Fill)',
                  labelStyle: const TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: NexGenPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: NexGenPalette.cyan),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NexGenPalette.textMedium,
                        side: const BorderSide(color: NexGenPalette.line),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _name.trim().isEmpty ? null : _assign,
                      style: FilledButton.styleFrom(
                        backgroundColor: NexGenPalette.cyan,
                        foregroundColor: NexGenPalette.matteBlack,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                      child: const Text('Assign'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _assign() {
    final selectedDay = ref.read(_selectedDayProvider);
    final newPart = DayPart(
      id: 'dp_${DateTime.now().millisecondsSinceEpoch}',
      name: _name.trim(),
      startTime: TimeOfDay(
          hour: widget.startMin ~/ 60, minute: widget.startMin % 60),
      endTime: TimeOfDay(
          hour: widget.endMin ~/ 60, minute: widget.endMin % 60),
      assignedDesignId: _designId.trim().isEmpty ? null : _designId.trim(),
      daysOfWeek: [selectedDay],
    );

    final updated = widget.schedule.copyWith(
      dayParts: [...widget.schedule.dayParts, newPart],
    );
    widget.onScheduleChanged(updated);
    Navigator.pop(context);
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:${t.minute.toString().padLeft(2, '0')} $period';
  }

  Widget _buildDragHandle() => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: NexGenPalette.textSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

// =============================================================================
// QUICK ACTIONS PANEL — pinned bottom, collapsible
// =============================================================================

class _QuickActionsPanel extends ConsumerWidget {
  final String locationId;
  final bool isLocked;
  final ValueChanged<CommercialSchedule> onScheduleChanged;

  const _QuickActionsPanel({
    required this.locationId,
    required this.isLocked,
    required this.onScheduleChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(_quickActionsExpandedProvider);
    final role = ref.watch(_userRoleProvider);
    final isCorporateAdmin = role == CommercialRole.corporateAdmin;
    final canEdit = role?.hasPermission('canEditOwnSchedule') ?? false;
    final canOverride = role?.hasPermission('canOverrideNow') ?? false;

    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        border: const Border(
          top: BorderSide(color: NexGenPalette.line, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header / toggle
            InkWell(
              onTap: () => ref
                  .read(_quickActionsExpandedProvider.notifier)
                  .state = !expanded,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded,
                        size: 16, color: NexGenPalette.cyan),
                    const SizedBox(width: 8),
                    const Text(
                      'QUICK ACTIONS',
                      style: TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 20,
                      color: NexGenPalette.textMedium,
                    ),
                  ],
                ),
              ),
            ),
            // Expandable content
            AnimatedCrossFade(
              firstChild: Padding(
                padding:
                    const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canOverride && !isLocked)
                      _QuickActionChip(
                        icon: Icons.play_arrow_rounded,
                        label: 'Override Now',
                        color: NexGenPalette.cyan,
                        onTap: () =>
                            _showOverrideSheet(context, ref),
                      ),
                    if (canOverride && !isLocked)
                      _QuickActionChip(
                        icon: Icons.pause_rounded,
                        label: 'Pause All',
                        color: NexGenPalette.amber,
                        onTap: () => _pauseAll(context, ref),
                      ),
                    if (canEdit && !isLocked)
                      _QuickActionChip(
                        icon: Icons.lightbulb_rounded,
                        label: 'Run Default',
                        color: NexGenPalette.green,
                        onTap: () => _runDefault(context, ref),
                      ),
                    if (canEdit && !isLocked)
                      _QuickActionChip(
                        icon: Icons.copy_rounded,
                        label: 'Copy Day',
                        color: NexGenPalette.violet,
                        onTap: () => _showCopyDaySheet(context, ref),
                      ),
                    if (isCorporateAdmin)
                      _QuickActionChip(
                        icon: Icons.push_pin_rounded,
                        label: 'Push to All',
                        color: NexGenPalette.gold,
                        onTap: () =>
                            _showPushToLocationsSheet(context, ref),
                      ),
                  ],
                ),
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }

  void _showOverrideSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _OverrideNowSheet(locationId: locationId),
    );
  }

  void _pauseAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: const Text('Pause All Channels',
            style: TextStyle(color: NexGenPalette.textHigh)),
        content: const Text(
          'This will turn off all channels immediately. '
          'They will resume with the next scheduled day-part.',
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All channels paused'),
                  backgroundColor: NexGenPalette.gunmetal,
                ),
              );
              // TODO: send pause command to all controllers
            },
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.amber,
              foregroundColor: NexGenPalette.matteBlack,
            ),
            child: const Text('Pause All'),
          ),
        ],
      ),
    );
  }

  void _runDefault(BuildContext context, WidgetRef ref) {
    final schedule = ref.read(_workingScheduleProvider);
    if (schedule?.defaultAmbientDesignId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No default ambient design configured'),
          backgroundColor: NexGenPalette.gunmetal,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Running default: ${schedule!.defaultAmbientDesignId}'),
        backgroundColor: NexGenPalette.gunmetal,
      ),
    );
    // TODO: push defaultAmbientDesignId to all active channels
  }

  void _showCopyDaySheet(BuildContext context, WidgetRef ref) {
    final selectedDay = ref.read(_selectedDayProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CopyDaySheet(sourceDay: selectedDay),
    );
  }

  void _showPushToLocationsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PushToLocationsSheet(
        locationId: locationId,
        schedule: ref.read(_workingScheduleProvider),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// OVERRIDE NOW BOTTOM SHEET
// =============================================================================

class _OverrideNowSheet extends ConsumerStatefulWidget {
  final String locationId;
  const _OverrideNowSheet({required this.locationId});

  @override
  ConsumerState<_OverrideNowSheet> createState() => _OverrideNowSheetState();
}

class _OverrideNowSheetState extends ConsumerState<_OverrideNowSheet> {
  String _designId = '';
  _OverrideExpiry _expiry = _OverrideExpiry.nextDayPart;
  TimeOfDay? _customEndTime;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDragHandle(),
              const SizedBox(height: 12),
              const Text(
                'Override Now',
                style: TextStyle(
                  color: NexGenPalette.textHigh,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Run a design immediately on selected channels',
                style: TextStyle(
                    color: NexGenPalette.textMedium, fontSize: 13),
              ),
              const SizedBox(height: 16),
              // Design picker
              TextField(
                onChanged: (v) => setState(() => _designId = v),
                style: const TextStyle(color: NexGenPalette.textHigh),
                decoration: InputDecoration(
                  labelText: 'Design ID',
                  labelStyle: const TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: NexGenPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: NexGenPalette.cyan),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              // Expiry selector
              const Text('Expires',
                  style: TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ExpiryOption(
                    label: 'Next Day-Part',
                    isSelected: _expiry == _OverrideExpiry.nextDayPart,
                    onTap: () => setState(
                        () => _expiry = _OverrideExpiry.nextDayPart),
                  ),
                  const SizedBox(width: 8),
                  _ExpiryOption(
                    label: 'Custom Time',
                    isSelected: _expiry == _OverrideExpiry.customTime,
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          _expiry = _OverrideExpiry.customTime;
                          _customEndTime = picked;
                        });
                      }
                    },
                  ),
                ],
              ),
              if (_expiry == _OverrideExpiry.customTime &&
                  _customEndTime != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Until ${_customEndTime!.format(context)}',
                    style: const TextStyle(
                        color: NexGenPalette.cyan, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _designId.trim().isEmpty ? null : _applyOverride,
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: NexGenPalette.matteBlack,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: const Text('Apply Override',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _applyOverride() {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Override applied: $_designId'),
        backgroundColor: NexGenPalette.gunmetal,
      ),
    );
    // TODO: push override to controllers via WledService
  }

  Widget _buildDragHandle() => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: NexGenPalette.textSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

enum _OverrideExpiry { nextDayPart, customTime }

class _ExpiryOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ExpiryOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? NexGenPalette.cyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: isSelected
                ? NexGenPalette.cyan.withValues(alpha: 0.5)
                : NexGenPalette.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PUSH TO LOCATIONS BOTTOM SHEET
// =============================================================================

class _PushToLocationsSheet extends ConsumerStatefulWidget {
  final String locationId;
  final CommercialSchedule? schedule;

  const _PushToLocationsSheet({
    required this.locationId,
    this.schedule,
  });

  @override
  ConsumerState<_PushToLocationsSheet> createState() =>
      _PushToLocationsSheetState();
}

class _PushToLocationsSheetState
    extends ConsumerState<_PushToLocationsSheet> {
  final Set<String> _selectedLocationIds = {};
  bool _lockAfterPush = false;
  bool _pushing = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDragHandle(),
              const SizedBox(height: 12),
              const Text(
                'Push to Locations',
                style: TextStyle(
                  color: NexGenPalette.textHigh,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Push this schedule to other locations in your organization',
                style: TextStyle(
                    color: NexGenPalette.textMedium, fontSize: 13),
              ),
              const SizedBox(height: 16),
              // Location selector placeholder
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NexGenPalette.matteBlack,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: const Center(
                  child: Text(
                    'Location list loads from organization',
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Lock toggle
              Row(
                children: [
                  Switch(
                    value: _lockAfterPush,
                    onChanged: (v) =>
                        setState(() => _lockAfterPush = v),
                    activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.4),
                    activeThumbColor: NexGenPalette.cyan,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Lock locations after push (prevents local edits)',
                      style: TextStyle(
                          color: NexGenPalette.textMedium, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _pushing ? null : _pushSchedule,
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.gold,
                    foregroundColor: NexGenPalette.matteBlack,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: _pushing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: NexGenPalette.matteBlack),
                        )
                      : const Text('Push Schedule',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pushSchedule() async {
    if (widget.schedule == null) return;
    setState(() => _pushing = true);

    try {
      final pushService = ref.read(corporatePushServiceProvider);
      await pushService.pushScheduleToLocations(
        widget.schedule!,
        _selectedLocationIds.toList(),
        locked: _lockAfterPush,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Schedule pushed to ${_selectedLocationIds.length} locations'),
            backgroundColor: NexGenPalette.gunmetal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Push failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  Widget _buildDragHandle() => Center(
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 6),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: NexGenPalette.textSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}
