// lib/features/autopilot/autopilot_conflict_dialog.dart
//
// Conflict resolution UI shown when autopilot wants to write an event
// to a date that already has a CalendarEntryType.user record.
//
// Surfaces a bottom sheet with three options: Keep Mine, Use Autopilot's,
// or Merge.  An optional "Remember this choice" checkbox persists the
// decision to the user's autopilotConflictPolicy field.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/autopilot_event.dart';
import 'package:nexgen_command/theme.dart';

// ─── Data types ──────────────────────────────────────────────────────────────

/// One autopilot event that conflicts with an existing user calendar entry.
class AutopilotConflict {
  final AutopilotEvent autopilotEvent;
  final CalendarEntry userEntry;

  const AutopilotConflict({
    required this.autopilotEvent,
    required this.userEntry,
  });

  /// Formatted date key for the conflict (YYYY-MM-DD).
  String get dateKey => userEntry.dateKey;
}

/// The user's per-conflict resolution choice.
enum AutopilotConflictChoice {
  /// Keep the user's manual entry — skip autopilot for this date.
  keepMine,
  /// Use autopilot's suggestion — overwrite the user entry.
  useAutopilot,
  /// Merge: keep user's times + autopilot's colors/pattern.
  merge,
  /// User dismissed without choosing — treat as keep mine.
  cancel,
}

/// Result returned from the conflict dialog.
class AutopilotConflictResult {
  final AutopilotConflictChoice choice;

  /// If true, the user checked "Remember this choice" and the policy should
  /// be persisted to their profile.
  final bool remember;

  const AutopilotConflictResult({
    required this.choice,
    this.remember = false,
  });
}

// ─── Conflict detection helper ──────────────────────────────────────────────

/// Given a list of autopilot events and the current calendar entries,
/// returns only those events that conflict with user-set entries.
List<AutopilotConflict> detectAutopilotConflicts(
  List<AutopilotEvent> events,
  Map<String, CalendarEntry> calendarEntries,
) {
  final conflicts = <AutopilotConflict>[];
  for (final event in events) {
    final dateKey =
        '${event.startTime.year}-${event.startTime.month.toString().padLeft(2, '0')}-${event.startTime.day.toString().padLeft(2, '0')}';
    final existing = calendarEntries[dateKey];
    if (existing != null && existing.type == CalendarEntryType.user) {
      conflicts.add(AutopilotConflict(
        autopilotEvent: event,
        userEntry: existing,
      ));
    }
  }
  return conflicts;
}

// ─── Public entry point ─────────────────────────────────────────────────────

/// Shows the autopilot conflict resolution bottom sheet.
/// Returns [AutopilotConflictResult] with the user's choice.
Future<AutopilotConflictResult> showAutopilotConflictDialog(
  BuildContext context,
  List<AutopilotConflict> conflicts,
) async {
  final result = await showModalBottomSheet<AutopilotConflictResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AutopilotConflictSheet(conflicts: conflicts),
  );
  return result ??
      const AutopilotConflictResult(choice: AutopilotConflictChoice.cancel);
}

/// Persists the user's remembered policy choice to Firestore.
Future<void> saveConflictPolicy(
  WidgetRef ref,
  AutopilotConflictPolicy policy,
) async {
  final userService = ref.read(userServiceProvider);
  final profile = ref.read(currentUserProfileProvider).maybeWhen(
        data: (u) => u,
        orElse: () => null,
      );
  if (profile == null) return;
  await userService.updateUserProfile(profile.id, {
    'autopilot_conflict_policy': policy.toJson(),
  });
}

// ─── Sheet widget ───────────────────────────────────────────────────────────

class _AutopilotConflictSheet extends StatefulWidget {
  final List<AutopilotConflict> conflicts;
  const _AutopilotConflictSheet({required this.conflicts});

  @override
  State<_AutopilotConflictSheet> createState() =>
      _AutopilotConflictSheetState();
}

class _AutopilotConflictSheetState extends State<_AutopilotConflictSheet> {
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.conflicts.length;
    final first = widget.conflicts.first;

    // Build a friendly description of the first conflict
    final apName = first.autopilotEvent.patternName;
    final apDay = _weekdayFromDate(first.autopilotEvent.startTime);
    final userPattern = first.userEntry.patternName;

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
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 14),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: NexGenPalette.amber, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      count == 1
                          ? 'Schedule Conflict'
                          : '$count Schedule Conflicts',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: NexGenPalette.textHigh,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Conflict description
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NexGenPalette.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: NexGenPalette.amber.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Autopilot wants to set $apName on $apDay',
                      style: TextStyle(
                        color: NexGenPalette.textHigh,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You have "$userPattern" scheduled.',
                      style: TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 13,
                      ),
                    ),
                    if (count > 1) ...[
                      const SizedBox(height: 6),
                      Text(
                        '+ ${count - 1} more conflict${count > 2 ? 's' : ''}',
                        style: TextStyle(
                          color: NexGenPalette.textMedium,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Conflict tiles (show up to 3)
              ...widget.conflicts.take(3).map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _ConflictTile(conflict: c),
                  )),

              const SizedBox(height: 12),

              // Remember checkbox
              GestureDetector(
                onTap: () => setState(() => _remember = !_remember),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _remember,
                        onChanged: (v) =>
                            setState(() => _remember = v ?? false),
                        activeColor: NexGenPalette.cyan,
                        side: BorderSide(
                            color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Remember this choice',
                      style: TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Keep Mine',
                      icon: Icons.person,
                      color: NexGenPalette.cyan,
                      onTap: () => Navigator.of(context).pop(
                        AutopilotConflictResult(
                          choice: AutopilotConflictChoice.keepMine,
                          remember: _remember,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      label: "Use Autopilot's",
                      icon: Icons.auto_awesome,
                      color: NexGenPalette.violet,
                      onTap: () => Navigator.of(context).pop(
                        AutopilotConflictResult(
                          choice: AutopilotConflictChoice.useAutopilot,
                          remember: _remember,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      label: 'Merge',
                      icon: Icons.merge_type,
                      color: NexGenPalette.amber,
                      onTap: () => Navigator.of(context).pop(
                        AutopilotConflictResult(
                          choice: AutopilotConflictChoice.merge,
                          remember: _remember,
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

  static String _weekdayFromDate(DateTime d) {
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return names[d.weekday - 1];
  }
}

// ─── Supporting widgets ─────────────────────────────────────────────────────

class _ConflictTile extends StatelessWidget {
  final AutopilotConflict conflict;
  const _ConflictTile({required this.conflict});

  @override
  Widget build(BuildContext context) {
    final ap = conflict.autopilotEvent;
    final user = conflict.userEntry;
    final apColor = ap.displayColor ?? ap.eventType.accentColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          // Autopilot color dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: apColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: apColor.withValues(alpha: 0.5), blurRadius: 4)
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ap.patternName,
              style: TextStyle(
                color: NexGenPalette.textHigh,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.swap_horiz,
              color: NexGenPalette.textMedium.withValues(alpha: 0.5), size: 16),
          Expanded(
            child: Text(
              user.patternName,
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 8),
          // User color dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: user.color ?? NexGenPalette.textMedium,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
