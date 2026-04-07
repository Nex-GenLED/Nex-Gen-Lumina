// lib/features/schedule/schedule_overload_banner.dart
//
// One-time dismissible warning banner for users with an excessive number
// of active schedules accumulated before conflict detection existed.
// Includes a "Clean Up" bottom sheet to review and batch-delete conflicts.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_detector.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/theme.dart';

const _kDismissedKey = 'schedule_warning_dismissed_at';

// ─── Banner widget ───────────────────────────────────────────────────────────

class ScheduleOverloadBanner extends ConsumerStatefulWidget {
  const ScheduleOverloadBanner({super.key});

  @override
  ConsumerState<ScheduleOverloadBanner> createState() =>
      _ScheduleOverloadBannerState();
}

class _ScheduleOverloadBannerState
    extends ConsumerState<ScheduleOverloadBanner> {
  int _dismissedAt = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _dismissedAt = prefs.getInt(_kDismissedKey) ?? 0;
      _loaded = true;
    });
  }

  Future<void> _dismiss(int totalActive) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDismissedKey, totalActive);
    if (!mounted) return;
    setState(() => _dismissedAt = totalActive);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    final schedules = ref.watch(schedulesProvider);
    final calEntries = ref.watch(calendarScheduleProvider);

    // Rule 3: only count recurring (enabled) ScheduleItems toward the
    // overload threshold. CalendarEntry holiday records are excluded
    // entirely, regardless of how many exist — a user with 50 holiday
    // CalendarEntries across the year should never trigger this banner.
    final activeCount = schedules.where((s) => s.enabled).length;

    if (activeCount <= 8 || activeCount <= _dismissedAt) {
      return const SizedBox.shrink();
    }

    // Rule 4: even when the count is high, only show the banner if there
    // is at least one genuine conflict the cleanup sheet can surface. An
    // empty cleanup sheet is a silent failure state — never reach it.
    final conflicts = ScheduleConflictDetector.computeAllConflicts(
      schedules: schedules,
      calendarEntries: calEntries,
    );
    if (conflicts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: NexGenPalette.amber.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: NexGenPalette.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'You have $activeCount active schedules with '
              '${conflicts.totalCount} overlap${conflicts.totalCount == 1 ? '' : 's'}. '
              'Overlapping schedules can cause unpredictable lighting.',
              style: const TextStyle(
                color: NexGenPalette.amber,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: NexGenPalette.cyan,
              visualDensity: VisualDensity.compact,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: () => _showCleanupSheet(
                context, ref, schedules, calEntries, conflicts),
            child: const Text('Clean Up',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          GestureDetector(
            onTap: () => _dismiss(activeCount),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: NexGenPalette.amber),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Clean Up bottom sheet launcher ──────────────────────────────────────────

void _showCleanupSheet(
  BuildContext context,
  WidgetRef ref,
  List<ScheduleItem> schedules,
  Map<String, CalendarEntry> calEntries,
  ScheduleConflicts conflicts,
) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CleanupSheet(
      schedules: schedules,
      calEntries: calEntries,
      conflicts: conflicts,
      ref: ref,
    ),
  );
}

// ─── Clean Up bottom sheet ───────────────────────────────────────────────────

class _CleanupSheet extends StatefulWidget {
  final List<ScheduleItem> schedules;
  final Map<String, CalendarEntry> calEntries;
  final ScheduleConflicts conflicts;
  final WidgetRef ref;

  const _CleanupSheet({
    required this.schedules,
    required this.calEntries,
    required this.conflicts,
    required this.ref,
  });

  @override
  State<_CleanupSheet> createState() => _CleanupSheetState();
}

class _CleanupSheetState extends State<_CleanupSheet> {
  final _selectedItemIds = <String>{};
  final _selectedEntryKeys = <String>{};

  // Only conflicting rows are shown in the sheet — non-conflicting
  // recurring schedules and holiday CalendarEntries that don't overlap
  // anything are intentionally excluded (Rule 4). Conflict sets are
  // precomputed by the banner via [ScheduleConflictDetector.computeAllConflicts]
  // and passed in here so both views always agree.
  late final List<ScheduleItem> _conflictingItems;
  late final List<MapEntry<String, CalendarEntry>> _conflictingEntries;

  @override
  void initState() {
    super.initState();
    _conflictingItems = widget.schedules
        .where((s) => s.enabled && widget.conflicts.itemIds.contains(s.id))
        .toList();

    _conflictingEntries = widget.calEntries.entries
        .where((e) => widget.conflicts.entryKeys.contains(e.key))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  }

  int get _selectedCount =>
      _selectedItemIds.length + _selectedEntryKeys.length;

  void _selectAllConflicts() {
    setState(() {
      _selectedItemIds.addAll(_conflictingItems.map((e) => e.id));
      _selectedEntryKeys.addAll(_conflictingEntries.map((e) => e.key));
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedCount;
    if (count == 0) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Delete schedules?'),
        content: Text('Delete $count schedule${count == 1 ? '' : 's'}? '
            'This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // Batch delete via existing notifier methods
    final schedNotifier = widget.ref.read(schedulesProvider.notifier);
    for (final id in _selectedItemIds) {
      await schedNotifier.remove(id);
    }

    final calNotifier =
        widget.ref.read(calendarScheduleProvider.notifier);
    for (final key in _selectedEntryKeys) {
      await calNotifier.removeEntry(key);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: NexGenPalette.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'Resolve Schedule Conflicts',
                    style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_conflictingItems.length + _conflictingEntries.length} '
                    'conflict${_conflictingItems.length + _conflictingEntries.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Scrollable list — only conflicting rows, grouped by type.
            Flexible(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shrinkWrap: true,
                children: [
                  if (_conflictingItems.isNotEmpty) ...[
                    const _SectionHeader(
                      label: 'Recurring Schedule Conflicts',
                    ),
                    for (final item in _conflictingItems)
                      _ItemRow(
                        item: item,
                        isConflicting: true,
                        isSelected: _selectedItemIds.contains(item.id),
                        onChanged: (v) => setState(() {
                          v == true
                              ? _selectedItemIds.add(item.id)
                              : _selectedItemIds.remove(item.id);
                        }),
                      ),
                  ],
                  if (_conflictingEntries.isNotEmpty) ...[
                    const _SectionHeader(label: 'Holiday Conflicts'),
                    for (final e in _conflictingEntries)
                      _EntryRow(
                        dateKey: e.key,
                        entry: e.value,
                        isConflicting: true,
                        isSelected: _selectedEntryKeys.contains(e.key),
                        onChanged: (v) => setState(() {
                          v == true
                              ? _selectedEntryKeys.add(e.key)
                              : _selectedEntryKeys.remove(e.key);
                        }),
                      ),
                  ],
                ],
              ),
            ),

            // Buttons
            Padding(
              // Bottom padding includes kBottomNavBarPadding so the action
              // buttons sit above the glass dock nav bar overlay (which
              // remains visible on top of modal sheets opened from the
              // inner navigator).
              padding: const EdgeInsets.fromLTRB(
                  20, 12, 20, 8 + kBottomNavBarPadding),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NexGenPalette.amber,
                        side: BorderSide(
                            color:
                                NexGenPalette.amber.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _selectAllConflicts,
                      child: const Text('Select All',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selectedCount > 0
                            ? Colors.red.shade700
                            : NexGenPalette.gunmetal90,
                        foregroundColor: _selectedCount > 0
                            ? Colors.white
                            : NexGenPalette.textMedium,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(12)),
                      ),
                      onPressed:
                          _selectedCount > 0 ? _deleteSelected : null,
                      child: Text(
                        'Delete Selected ($_selectedCount)',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: NexGenPalette.textMedium,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done',
                          style: TextStyle(fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Row widgets ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: NexGenPalette.textMedium,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final ScheduleItem item;
  final bool isConflicting;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const _ItemRow({
    required this.item,
    required this.isConflicting,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final days = item.repeatDays.join(', ');
    final time = item.hasOffTime
        ? '${item.timeLabel} \u2013 ${item.offTimeLabel}'
        : item.timeLabel;

    return _RowShell(
      isConflicting: isConflicting,
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: onChanged,
            activeColor: NexGenPalette.cyan,
            side: BorderSide(
                color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.actionLabel,
                  style: const TextStyle(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$days \u2022 $time',
                  style: const TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final String dateKey;
  final CalendarEntry entry;
  final bool isConflicting;
  final bool isSelected;
  final ValueChanged<bool?> onChanged;

  const _EntryRow({
    required this.dateKey,
    required this.entry,
    required this.isConflicting,
    required this.isSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(dateKey);
    final dateStr = date != null ? _fmtDate(date) : dateKey;
    final time = entry.onTime != null
        ? '${entry.onTime} \u2013 ${entry.offTime ?? '\u2014'}'
        : '\u2014';

    return _RowShell(
      isConflicting: isConflicting,
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: onChanged,
            activeColor: NexGenPalette.cyan,
            side: BorderSide(
                color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.patternName,
                  style: const TextStyle(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$dateStr \u2022 $time',
                  style: const TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${wd[d.weekday - 1]} ${mo[d.month - 1]} ${d.day}';
  }
}

class _RowShell extends StatelessWidget {
  final bool isConflicting;
  final Widget child;
  const _RowShell({required this.isConflicting, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: isConflicting
              ? NexGenPalette.amber.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isConflicting
              ? Border.all(
                  color: NexGenPalette.amber.withValues(alpha: 0.25))
              : null,
        ),
        child: child,
      ),
    );
  }
}
