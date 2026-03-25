import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/schedule_type_badge.dart';
import '../models/group_game_day_autopilot.dart';
import '../providers/group_autopilot_providers.dart';

/// Schedule card for a Group Game Day Autopilot entry.
///
/// Uses the unified visual identity system with [ScheduleEntryType.gameDaySyncAutopilot].
class GroupAutopilotScheduleCard extends ConsumerWidget {
  /// The autopilot config to display.
  final GroupGameDayAutopilot config;

  /// Optional game date/time for the next scheduled game.
  final DateTime? gameDateTime;

  /// Optional design name (resolved from hostDesignId).
  final String? designName;

  /// Called when the card is tapped.
  final VoidCallback? onTap;

  const GroupAutopilotScheduleCard({
    super.key,
    required this.config,
    this.gameDateTime,
    this.designName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberCount = ref.watch(groupAutopilotMemberCountProvider);

    return ScheduleIdentityCard(
      type: ScheduleEntryType.gameDaySyncAutopilot,
      teamColor: null, // team color not stored on GroupGameDayAutopilot yet
      sportEmoji: config.sportEmoji,
      memberCount: memberCount,
      patternName: designName ?? config.teamName,
      previewColors: const [],
      effectName: designName != null ? config.teamName : null,
      timeLabel: gameDateTime != null
          ? _formatGameDateTime(gameDateTime!)
          : 'Game Days Only',
      recurrenceLabel: 'Game Days Only',
      teamName: config.teamName,
      gameDayTiming: '30 min pre-game \u2022 30 min post-game',
      onTap: onTap,
    );
  }

  String _formatGameDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final gameDay = DateTime(dt.year, dt.month, dt.day);
    final diff = gameDay.difference(today).inDays;

    final timeFmt = _formatTime(dt);
    if (diff == 0) return 'Today at $timeFmt';
    if (diff == 1) return 'Tomorrow at $timeFmt';
    if (diff < 7) return '${_weekdayName(dt.weekday)} at $timeFmt';

    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month]} ${dt.day} at $timeFmt';
  }

  static String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour < 12 ? 'AM' : 'PM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min $period';
  }

  static String _weekdayName(int weekday) {
    const days = [
      '', 'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    return days[weekday];
  }
}

/// Combined Neighborhood Sync + Autopilot badge.
///
/// Now delegates to the unified [ScheduleTypeBadge] with
/// [ScheduleEntryType.neighborhoodSyncAutopilot] for visual consistency.
class NeighborhoodSyncAutopilotBadge extends StatelessWidget {
  const NeighborhoodSyncAutopilotBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScheduleTypeBadge(
      type: ScheduleEntryType.neighborhoodSyncAutopilot,
    );
  }
}
