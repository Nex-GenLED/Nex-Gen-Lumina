// lib/features/schedule/my_schedule_page.dart
//
// My Schedule screen — rebuilt with:
//   • Day Hero card as the primary view (selected-day full detail)
//   • 7-day week strip (always visible, large cells with color/pattern/times)
//   • Calendar zoom views: 1 Mo / 3 Mo / 6 Mo / Full Year
//   • Lumina AI wired to calendarScheduleProvider — changes now actually apply
//   • Pending changes preview with Apply / Discard before committing

import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_dialog.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_overload_banner.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/autopilot/autopilot_suggestions_card.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/audio/services/audio_capability_detector.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/schedule/sun_time_provider.dart';
import 'package:nexgen_command/features/ai/light_effect_animator.dart';
import 'package:nexgen_command/features/ai/pixel_strip_preview.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/widgets/schedule_type_badge.dart';
import 'package:nexgen_command/widgets/section_header.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// ─── Constants ────────────────────────────────────────────────────────────────

const _kMonthNames = [
  '', 'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _kMonthShort = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _kDayFull  = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _kDayShort = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _fmt(DateTime d) => calendarDateKey(d);
DateTime _startOfWeek(DateTime d) =>
    DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday % 7));

// Returns the recurring ScheduleItems active on a given weekday (0=Sun..6=Sat).
List<ScheduleItem> _itemsForWeekday(List<ScheduleItem> all, int wd) {
  const map = {
    0: {'sun', 'sunday'},
    1: {'mon', 'monday'},
    2: {'tue', 'tues', 'tuesday'},
    3: {'wed', 'wednesday'},
    4: {'thu', 'thurs', 'thursday'},
    5: {'fri', 'friday'},
    6: {'sat', 'saturday'},
  };
  return all.where((s) {
    if (!s.enabled) return false;
    final dl = s.repeatDays.map((e) => e.toLowerCase()).toSet();
    if (dl.contains('daily')) return true;
    return (map[wd] ?? {}).any(dl.contains);
  }).toList();
}

// ─── Root Page ────────────────────────────────────────────────────────────────

class MySchedulePage extends ConsumerStatefulWidget {
  const MySchedulePage({super.key});

  @override
  ConsumerState<MySchedulePage> createState() => _MySchedulePageState();
}

class _MySchedulePageState extends ConsumerState<MySchedulePage> {
  late DateTime _weekStart;
  late DateTime _calStart; // first day of the calendar zoom range

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _weekStart = _startOfWeek(today);
    _calStart = DateTime(today.year, today.month, 1);
  }

  // ── View mode toggle ──

  void _setViewMode(String mode) {
    ref.read(calendarViewModeProvider.notifier).state = mode;
    if (mode == 'week') {
      setState(() => _weekStart = _startOfWeek(DateTime.now()));
    } else {
      final t = DateTime.now();
      setState(() => _calStart = DateTime(t.year, t.month, 1));
    }
  }

  void _shiftWeek(int dir) =>
      setState(() => _weekStart = _weekStart.add(Duration(days: dir * 7)));

  void _shiftCal(int dir) {
    final steps = {'month': 1, '3month': 3, '6month': 6, 'year': 12};
    final mode = ref.read(calendarViewModeProvider);
    setState(() {
      _calStart = DateTime(
        _calStart.year,
        _calStart.month + dir * (steps[mode] ?? 1),
        1,
      );
    });
  }

  void _goToday() {
    final t = DateTime.now();
    ref.read(selectedCalendarDateProvider.notifier).state = _fmt(t);
    setState(() {
      _weekStart = _startOfWeek(t);
      _calStart = DateTime(t.year, t.month, 1);
    });
  }

  // ── Week range label ──
  String get _weekLabel {
    final end = _weekStart.add(const Duration(days: 6));
    final sm = _kMonthShort[_weekStart.month];
    final em = _kMonthShort[end.month];
    final sameMonth = _weekStart.month == end.month;
    return sameMonth
        ? '$sm ${_weekStart.day} – ${end.day}, ${end.year}'
        : '$sm ${_weekStart.day} – $em ${end.day}, ${end.year}';
  }

  // ── Calendar zoom range label ──
  String get _calLabel {
    final mode = ref.read(calendarViewModeProvider);
    if (mode == 'year') return '${_calStart.year}';
    final steps = {'month': 1, '3month': 3, '6month': 6}[mode] ?? 1;
    final end = DateTime(_calStart.year, _calStart.month + steps - 1, 1);
    if (steps == 1) return '${_kMonthNames[_calStart.month]} ${_calStart.year}';
    return '${_kMonthShort[_calStart.month]} – ${_kMonthShort[end.month]} ${end.year}';
  }

  @override
  Widget build(BuildContext context) {
    final schedules  = ref.watch(schedulesProvider);
    final viewMode   = ref.watch(calendarViewModeProvider);
    final selectedKey= ref.watch(selectedCalendarDateProvider);
    final calEntries = ref.watch(calendarScheduleProvider);
    final pending    = ref.watch(pendingCalendarProvider);

    final userAsync  = ref.watch(currentUserProfileProvider);
    final user       = userAsync.maybeWhen(data: (u) => u, orElse: () => null);
    final hasCoords  = user?.latitude != null && user?.longitude != null;
    final sunAsync   = hasCoords
        ? ref.watch(sunTimeProvider((lat: user!.latitude!, lon: user.longitude!)))
        : const AsyncValue.data(null);

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('My Schedule'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _ViewModeBar(
            current: viewMode,
            onSelect: _setViewMode,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final result = await ref
                  .read(scheduleSyncServiceProvider)
                  .syncAll(ref, schedules);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(result.success
                      ? 'Schedules synced to controller'
                      : 'Could not sync (schedules saved to cloud)'),
                  backgroundColor: result.success
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ));
              }
            },
            icon: const Icon(Icons.cloud_upload_rounded, size: 18, color: Colors.white),
            label: const Text('Sync'),
          ),
        ],
      ),

      body: Column(
        children: [
          // ── Pending changes banner ──────────────────────────────────────
          if (pending != null)
            _PendingChangesBanner(pending: pending),

          // ── Schedule overload warning ──────────────────────────────────
          const ScheduleOverloadBanner(),

          // ── Main scroll area ────────────────────────────────────────────
          // Bottom padding is intentionally small here — the manual
          // _GenerateThisWeekButton sits below this Expanded and provides its
          // own SafeArea + nav-bar offset.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
              children: [
                // ── Lumina AI card (with fixed schedule creation) ──
                const _LuminaAICard(),
                const SizedBox(height: 14),

                // ── Autopilot suggestions ──
                const AutopilotSuggestionsCard(),
                const SizedBox(height: 14),

                // ── Day Hero: selected-day full detail ──
                _DayHeroCard(
                  dateKey: selectedKey,
                  calEntry: calEntries[selectedKey],
                  scheduleItems: schedules,
                  sunAsync: sunAsync,
                ),
                const SizedBox(height: 14),

                // ── Week strip (always visible) ──
                _WeekStripSection(
                  weekStart: _weekStart,
                  selectedKey: selectedKey,
                  calEntries: calEntries,
                  scheduleItems: schedules,
                  pendingEntries: {for (final c in pending?.changes ?? <CalendarEntry>[]) c.dateKey: c},
                  onDayTap: (k) =>
                      ref.read(selectedCalendarDateProvider.notifier).state = k,
                  onPrevWeek: () => _shiftWeek(-1),
                  onNextWeek: () => _shiftWeek(1),
                  onToday: _goToday,
                  weekLabel: _weekLabel,
                ),

                // ── Calendar zoom view (month / 3mo / 6mo / year) ──
                if (viewMode != 'week') ...[
                  const SizedBox(height: 14),
                  _ZoomedCalendarSection(
                    viewMode: viewMode,
                    calStart: _calStart,
                    selectedKey: selectedKey,
                    calEntries: calEntries,
                    pendingEntries: {for (final c in pending?.changes ?? <CalendarEntry>[]) c.dateKey: c},
                    onDayTap: (k) =>
                        ref.read(selectedCalendarDateProvider.notifier).state = k,
                    onPrev: () => _shiftCal(-1),
                    onNext: () => _shiftCal(1),
                    rangeLabel: _calLabel,
                  ),
                ],

                // ── All recurring schedules list (or empty state) ──
                if (schedules.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(
                      child: MajorSectionHeader(
                        title: 'Recurring Schedules',
                        subtitle: '${schedules.length} total',
                        icon: Icons.repeat_rounded,
                        iconColor: NexGenPalette.cyan,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    if (schedules.length > 5)
                      TextButton.icon(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: NexGenPalette.gunmetal90,
                              title: const Text('Clear All Schedules?'),
                              content: Text(
                                  'Delete all ${schedules.length} schedules? Cannot be undone.'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red.shade700),
                                    child: const Text('Clear All')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            ref.read(schedulesProvider.notifier).replaceAll([]);
                          }
                        },
                        icon: Icon(Icons.delete_sweep_rounded,
                            size: 18, color: Colors.red.shade400),
                        label: Text('Clear All',
                            style: TextStyle(
                                color: Colors.red.shade400, fontSize: 12)),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  ...schedules.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ScheduleCard(item: s),
                      )),
                ] else ...[
                  const SizedBox(height: 24),
                  if (ref.watch(autopilotEnabledProvider))
                    const _AutopilotGeneratingState()
                  else
                    const _AutopilotOffInvitation(),
                ],
              ],
            ),
          ),

          // ── Manual generate button ──────────────────────────────────────
          // Sits above the bottom nav so it's always reachable. Tapping it
          // forces a fresh schedule generation regardless of the weekly
          // refresh gate.
          const _GenerateThisWeekButton(),
        ],
      ),

      floatingActionButton: Padding(
        // Lift the FAB above the glass dock nav bar overlay so it isn't
        // hidden behind it. The parent shell's Scaffold uses extendBody:true
        // and overlays the dock via a Stack (it's not a bottomNavigationBar),
        // so default FAB positioning would otherwise sit underneath the dock.
        // Use navBarTotalHeight() so the offset also includes the device
        // bottom safe-area inset (e.g. iPhone home indicator).
        padding: EdgeInsets.only(bottom: navBarTotalHeight(context)),
        child: FloatingActionButton(
          backgroundColor: NexGenPalette.cyan,
          foregroundColor: Colors.black,
          onPressed: () => showScheduleEditor(context, ref),
          child: const Icon(CupertinoIcons.add),
        ),
      ),
    );
  }
}

// ─── View Mode Bar ─────────────────────────────────────────────────────────────

class _ViewModeBar extends StatelessWidget {
  final String current;
  final ValueChanged<String> onSelect;
  const _ViewModeBar({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const modes = [
      ('week', 'Week'), ('month', '1 Mo'), ('3month', '3 Mo'),
      ('6month', '6 Mo'), ('year', 'Year'),
    ];
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: modes.map((entry) {
          final (mode, label) = entry;
          final selected = mode == current;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => onSelect(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: selected
                      ? NexGenPalette.cyan.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? NexGenPalette.cyan
                        : NexGenPalette.line,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Pending Changes Banner ───────────────────────────────────────────────────

class _PendingChangesBanner extends ConsumerWidget {
  final PendingCalendarChanges pending;
  const _PendingChangesBanner({required this.pending});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = pending.changes.length;
    final firstNames = pending.changes
        .take(2)
        .map((e) => e.patternName)
        .join(', ');
    final summary = count <= 2
        ? firstNames
        : '$firstNames +${count - 2} more';

    return GestureDetector(
      onTap: () => _showPendingPreviewSheet(context, ref, pending),
      child: Container(
        decoration: BoxDecoration(
          color: NexGenPalette.amber.withValues(alpha: 0.10),
          border: Border(
            bottom: BorderSide(
                color: NexGenPalette.amber.withValues(alpha: 0.3)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.auto_awesome,
                color: NexGenPalette.amber, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count design${count == 1 ? '' : 's'} across $count night${count == 1 ? '' : 's'}',
                    style: TextStyle(
                      color: NexGenPalette.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: NexGenPalette.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: NexGenPalette.amber.withValues(alpha: 0.4)),
              ),
              child: Text(
                'Review',
                style: TextStyle(
                  color: NexGenPalette.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () =>
                  ref.read(pendingCalendarProvider.notifier).state = null,
              child: Icon(Icons.close,
                  color: NexGenPalette.textMedium.withValues(alpha: 0.6),
                  size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Pending Preview Bottom Sheet ─────────────────────────────────────────────

/// Shows a preview bottom sheet summarizing Lumina's proposed changes.
/// "Lumina wants to schedule X designs across Y nights."
/// Previews the first 3 entries, then Confirm or Cancel.
Future<void> _showPendingPreviewSheet(
  BuildContext context,
  WidgetRef ref,
  PendingCalendarChanges pending,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PendingPreviewSheet(pending: pending),
  );

  if (result == true) {
    // Confirm — check for recurring schedule conflicts, then apply
    final conflicts = ref
        .read(calendarScheduleProvider.notifier)
        .checkConflictsForEntries(pending.changes);
    ConflictResolution? resolution;
    if (conflicts.hasConflicts && context.mounted) {
      resolution =
          await showScheduleConflictDialog(context, conflicts);
      if (resolution == ConflictResolution.cancel) return;
    }

    final ok = await ref
        .read(calendarScheduleProvider.notifier)
        .applyEntries(pending.changes, resolution: resolution);
    if (pending.changes.isNotEmpty) {
      ref.read(selectedCalendarDateProvider.notifier).state =
          pending.changes.first.dateKey;
    }
    ref.read(pendingCalendarProvider.notifier).state = null;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Schedule saved'
            : 'Schedule could not be saved. Please try again.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
  // null or false → user cancelled, keep pending state for banner
}

class _PendingPreviewSheet extends StatelessWidget {
  final PendingCalendarChanges pending;
  const _PendingPreviewSheet({required this.pending});

  @override
  Widget build(BuildContext context) {
    final count = pending.changes.length;
    final preview = pending.changes.take(3).toList();
    final remaining = count - preview.length;

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
                  Icon(Icons.auto_awesome,
                      color: NexGenPalette.cyan, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Lumina wants to schedule $count design${count == 1 ? '' : 's'} '
                      'across $count night${count == 1 ? '' : 's'}',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: NexGenPalette.textHigh,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                  ),
                ],
              ),

              if (pending.message.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  pending.message,
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 14),

              // Preview tiles (first 3)
              ...preview.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _PendingEntryTile(entry: entry),
                  )),

              // "and N more" indicator
              if (remaining > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: Text(
                      '+ $remaining more night${remaining == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 8),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        foregroundColor: NexGenPalette.textMedium,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon:
                          const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                          'Confirm ${count == 1 ? '' : 'All '}$count'),
                      style: FilledButton.styleFrom(
                        backgroundColor: NexGenPalette.cyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Trailing space clears the glass dock nav bar overlay so
              // the Confirm/Cancel buttons aren't hidden behind the dock.
              const SizedBox(height: 16 + kBottomNavBarPadding),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single preview tile for a pending calendar entry.
class _PendingEntryTile extends StatelessWidget {
  final CalendarEntry entry;
  const _PendingEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(entry.dateKey);
    final dayLabel = date != null
        ? '${_kDayFull[date.weekday % 7]}, ${_kMonthShort[date.month]} ${date.day}'
        : entry.dateKey;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: entry.color?.withValues(alpha: 0.35) ??
              NexGenPalette.line,
        ),
      ),
      child: Row(
        children: [
          // Color swatch
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: entry.color ?? NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(8),
              boxShadow: entry.color != null
                  ? [
                      BoxShadow(
                        color: entry.color!.withValues(alpha: 0.4),
                        blurRadius: 8,
                      )
                    ]
                  : null,
            ),
            child: entry.color == null
                ? Icon(Icons.power_off_outlined,
                    color: NexGenPalette.textMedium, size: 16)
                : null,
          ),
          const SizedBox(width: 10),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.patternName,
                  style: TextStyle(
                    color: NexGenPalette.textHigh,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  dayLabel,
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Time + brightness
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (entry.onTime != null)
                Text(
                  entry.offTime != null
                      ? '${entry.onTime} → ${entry.offTime}'
                      : entry.onTime!,
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              if (entry.brightness > 0)
                Text(
                  '${entry.brightness}%',
                  style: TextStyle(
                    color: NexGenPalette.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Day Hero Card ─────────────────────────────────────────────────────────────

class _DayHeroCard extends StatelessWidget {
  final String dateKey;
  final CalendarEntry? calEntry;
  final List<ScheduleItem> scheduleItems;
  final AsyncValue<SunTimeStrings?> sunAsync;

  const _DayHeroCard({
    required this.dateKey,
    required this.calEntry,
    required this.scheduleItems,
    required this.sunAsync,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final selDate = DateTime.parse(dateKey);
    final isToday = _fmt(today) == dateKey;
    final isPast = selDate.isBefore(DateTime(today.year, today.month, today.day));

    // Resolve the best available entry
    final wd = selDate.weekday % 7; // 0=Sun..6=Sat
    final recurringItems = _itemsForWeekday(scheduleItems, wd);
    final recurringFirst = recurringItems.isNotEmpty ? recurringItems.first : null;

    final patternName = calEntry?.patternName ??
        (recurringFirst != null ? _labelFromAction(recurringFirst.actionLabel) : null);
    final color = calEntry?.color;
    final onTime = calEntry?.onTime ??
        (recurringFirst?.hasOffTime == true ? recurringFirst?.timeLabel : recurringFirst?.timeLabel);
    final offTime = calEntry?.offTime ?? recurringFirst?.offTimeLabel;
    final brightness = calEntry?.brightness;

    final typeLabel = calEntry?.type == CalendarEntryType.holiday
        ? '🎉 Holiday'
        : calEntry?.type == CalendarEntryType.user
            ? '👤 User Set'
            : calEntry?.type == CalendarEntryType.autopilot
                ? '⚡ Game Day'
                : recurringFirst != null
                    ? '🔁 Recurring'
                    : isPast
                        ? '—'
                        : '⚡ Auto-Pilot';

    final typeColor = calEntry?.type == CalendarEntryType.holiday
        ? NexGenPalette.amber
        : calEntry?.type == CalendarEntryType.user
            ? NexGenPalette.cyan
            : calEntry?.type == CalendarEntryType.autopilot
                ? NexGenPalette.cyan
                : recurringFirst != null
                    ? NexGenPalette.violet
                    : NexGenPalette.textMedium;

    // Extract WLED effect info for the pixel strip
    final wledPayload = calEntry != null ? null : recurringFirst?.wledPayload;
    final stripColors = _extractStripColors(color, wledPayload);
    final effectId = _extractEffectId(wledPayload);
    final effectType = effectId != null ? effectTypeFromWledId(effectId) : EffectType.solid;
    final speed = _extractNormalized(wledPayload, 'sx');
    final bri = brightness != null ? brightness / 100.0 : 1.0;

    // Source label for detail sheet
    final sourceLabel = calEntry?.type == CalendarEntryType.holiday
        ? 'Holiday'
        : calEntry?.type == CalendarEntryType.user
            ? calEntry!.autopilot ? 'AI-Generated' : 'Manual'
            : calEntry?.type == CalendarEntryType.autopilot
                ? 'Game Day Autopilot'
                : recurringFirst != null
                    ? 'Recurring Schedule'
                    : 'Autopilot';

    final effectLabel = effectId != null
        ? _wledEffectName(effectId)
        : patternName ?? 'Solid';

    return GestureDetector(
      onTap: (patternName != null || color != null)
          ? () => _showScheduleDetailSheet(
                context,
                colors: stripColors,
                effectType: effectType,
                speed: speed,
                brightness: bri,
                patternName: patternName ?? 'No Schedule',
                effectName: effectLabel,
                onTime: onTime,
                offTime: offTime,
                brightnessPercent: brightness,
                source: sourceLabel,
              )
          : null,
      child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: color != null
                  ? [
                      color.withValues(alpha: 0.18),
                      NexGenPalette.matteBlack.withValues(alpha: 0.9),
                    ]
                  : [NexGenPalette.gunmetal90, NexGenPalette.matteBlack],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color != null
                  ? color.withValues(alpha: 0.45)
                  : NexGenPalette.line,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Animated pixel strip at top
              if (stripColors.isNotEmpty)
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(14)),
                  child: PixelStripPreview(
                    colors: stripColors,
                    effectType: effectType,
                    speed: speed,
                    brightness: bri,
                    pixelCount: 24,
                    height: 28,
                    borderRadius: 0,
                    backgroundColor: const Color(0xFF0A0E14),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date + type badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selDate.toLocal().toString().split(' ')[0] == dateKey
                                    ? selDate.weekday != 0
                                        ? _kDayFull[selDate.weekday % 7]
                                        : 'Sunday'
                                    : '',
                                // Weekday name
                              ),
                              Text(
                                _weekdayName(selDate),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: isToday
                                          ? NexGenPalette.cyan
                                          : NexGenPalette.textHigh,
                                      fontWeight: FontWeight.w800,
                                      height: 1.1,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _fullDateLabel(selDate),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: NexGenPalette.textMedium),
                              ),
                              if (isToday)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: NexGenPalette.cyan.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: NexGenPalette.cyan.withValues(alpha: 0.5)),
                                  ),
                                  child: Text(
                                    'TODAY',
                                    style: TextStyle(
                                      color: NexGenPalette.cyan,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: typeColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            typeLabel,
                            style: TextStyle(
                              color: typeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Pattern swatch row
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NexGenPalette.matteBlack.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: NexGenPalette.line),
                      ),
                      child: Row(
                        children: [
                          // Color swatch
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: color ?? NexGenPalette.gunmetal90,
                              gradient: color != null
                                  ? RadialGradient(colors: [
                                      color.withValues(alpha: 0.9),
                                      color.withValues(alpha: 0.4),
                                    ])
                                  : null,
                              border: Border.all(color: NexGenPalette.line),
                              boxShadow: color != null
                                  ? [
                                      BoxShadow(
                                          color: color.withValues(alpha: 0.5),
                                          blurRadius: 12)
                                    ]
                                  : null,
                            ),
                            child: color == null
                                ? Icon(Icons.power_off_outlined,
                                    color: NexGenPalette.textMedium, size: 22)
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  patternName ?? 'No Schedule',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: NexGenPalette.textHigh,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                if (calEntry?.note != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    calEntry!.note!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: NexGenPalette.textMedium,
                                          fontStyle: FontStyle.italic,
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Stats row: On / Off / Brightness
                    Row(
                      children: [
                        _StatChip(
                          icon: Icons.wb_sunny_rounded,
                          label: 'On',
                          value: onTime ?? '—',
                          color: NexGenPalette.cyan,
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          icon: Icons.nightlight_round,
                          label: 'Off',
                          value: offTime ?? '—',
                          color: NexGenPalette.violet,
                        ),
                        const SizedBox(width: 8),
                        _StatChip(
                          icon: Icons.brightness_6_rounded,
                          label: 'Brightness',
                          value: brightness != null ? '$brightness%' : '—',
                          color: NexGenPalette.amber,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  String _weekdayName(DateTime d) {
    const names = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return names[d.weekday - 1];
  }

  String _fullDateLabel(DateTime d) {
    return '${_kMonthNames[d.month]} ${d.day}, ${d.year}';
  }

  String _labelFromAction(String a) {
    final lower = a.trim().toLowerCase();
    if (lower.startsWith('pattern')) {
      final idx = a.indexOf(':');
      return idx != -1 ? a.substring(idx + 1).trim() : a;
    }
    return a.trim();
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 9,
                    letterSpacing: 0.6,
                  )),
            ]),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                  color: NexGenPalette.textHigh,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                )),
          ],
        ),
      ),
    );
  }
}

// ─── Shared helpers for PixelStripPreview in schedule cards ──────────────────

/// Extract preview colors from a CalendarEntry color and/or WLED payload.
List<Color> _extractStripColors(Color? entryColor, Map<String, dynamic>? wledPayload) {
  // Try extracting from WLED payload first (multi-color)
  if (wledPayload != null) {
    final seg = wledPayload['seg'];
    if (seg is List && seg.isNotEmpty) {
      final col = seg[0] is Map ? (seg[0] as Map)['col'] : null;
      if (col is List) {
        final colors = col
            .whereType<List>()
            .where((c) => c.length >= 3)
            .map((c) => Color.fromARGB(
                  255,
                  (c[0] as num).toInt().clamp(0, 255),
                  (c[1] as num).toInt().clamp(0, 255),
                  (c[2] as num).toInt().clamp(0, 255),
                ))
            .toList();
        if (colors.isNotEmpty) return colors;
      }
    }
  }
  // Fall back to single entry color
  if (entryColor != null) return [entryColor];
  return const [];
}

/// Extract effect ID from WLED payload.
int? _extractEffectId(Map<String, dynamic>? payload) {
  if (payload == null) return null;
  final seg = payload['seg'];
  if (seg is List && seg.isNotEmpty && seg[0] is Map) {
    final fx = (seg[0] as Map)['fx'];
    if (fx is num) return fx.toInt();
  }
  return null;
}

/// Extract and normalize a 0-255 WLED field to 0.0-1.0.
double _extractNormalized(Map<String, dynamic>? payload, String key) {
  if (payload == null) return 0.5;
  final seg = payload['seg'];
  if (seg is List && seg.isNotEmpty && seg[0] is Map) {
    final val = (seg[0] as Map)[key];
    if (val is num) return (val / 255.0).clamp(0.0, 1.0);
  }
  return 0.5;
}

/// Map a WLED effect ID to its human-readable name.
String _wledEffectName(int id) {
  const names = {
    0: 'Solid', 2: 'Breathe', 12: 'Fade', 13: 'Theater Chase',
    15: 'Running', 17: 'Twinkle', 20: 'Sparkle', 28: 'Chase',
    37: 'Candle', 38: 'Fire', 39: 'Fireworks', 41: 'Running Dual',
    43: 'Tricolor Chase', 46: 'Lightning', 49: 'Fairy',
    52: 'Fireworks Starburst', 76: 'Meteor', 79: 'Ripple',
    80: 'Twinklefox', 87: 'Glitter', 95: 'Flow',
    9: 'Rainbow', 10: 'Rainbow Cycle',
  };
  return names[id] ?? 'Effect $id';
}

/// Bottom sheet showing full schedule detail for a card.
void _showScheduleDetailSheet(
  BuildContext context, {
  required List<Color> colors,
  required EffectType effectType,
  required double speed,
  required double brightness,
  required String patternName,
  required String effectName,
  required String? onTime,
  required String? offTime,
  required int? brightnessPercent,
  required String source,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      // Bottom padding clears the glass dock nav bar overlay so the
      // last detail row isn't hidden behind the dock.
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32 + kBottomNavBarPadding),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: NexGenPalette.textMedium.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Full-width pixel strip
          if (colors.isNotEmpty)
            PixelStripPreview(
              colors: colors,
              effectType: effectType,
              speed: speed,
              brightness: brightness,
              pixelCount: 32,
              height: 48,
              borderRadius: 10,
            ),

          const SizedBox(height: 16),

          // Pattern name
          Text(
            patternName,
            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                  color: NexGenPalette.textHigh,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),

          // Effect name
          Text(
            effectName,
            style: TextStyle(
              color: NexGenPalette.cyan,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 16),

          // Detail rows
          _DetailRow(
            icon: Icons.wb_sunny_rounded,
            label: 'On',
            value: onTime ?? '—',
            color: NexGenPalette.cyan,
          ),
          const SizedBox(height: 8),
          _DetailRow(
            icon: Icons.nightlight_round,
            label: 'Off',
            value: offTime ?? '—',
            color: NexGenPalette.violet,
          ),
          const SizedBox(height: 8),
          _DetailRow(
            icon: Icons.brightness_6_rounded,
            label: 'Brightness',
            value: brightnessPercent != null ? '$brightnessPercent%' : '—',
            color: NexGenPalette.amber,
          ),
          const SizedBox(height: 8),
          _DetailRow(
            icon: Icons.source_rounded,
            label: 'Source',
            value: source,
            color: NexGenPalette.textMedium,
          ),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: NexGenPalette.textMedium,
            fontSize: 12,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: NexGenPalette.textHigh,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Week Strip ───────────────────────────────────────────────────────────────

class _WeekStripSection extends StatelessWidget {
  final DateTime weekStart;
  final String selectedKey;
  final Map<String, CalendarEntry> calEntries;
  final List<ScheduleItem> scheduleItems;
  final Map<String, CalendarEntry> pendingEntries;
  final ValueChanged<String> onDayTap;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onToday;
  final String weekLabel;

  const _WeekStripSection({
    required this.weekStart,
    required this.selectedKey,
    required this.calEntries,
    required this.scheduleItems,
    required this.pendingEntries,
    required this.onDayTap,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.onToday,
    required this.weekLabel,
  });

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      7,
      (i) => _fmt(weekStart.add(Duration(days: i))),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Navigation row
              Row(
                children: [
                  _NavBtn(icon: Icons.chevron_left_rounded, onTap: onPrevWeek),
                  const SizedBox(width: 6),
                  _NavBtn(icon: Icons.chevron_right_rounded, onTap: onNextWeek),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onToday,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: NexGenPalette.cyan.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('Today',
                          style: TextStyle(
                              color: NexGenPalette.cyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(weekLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: NexGenPalette.textMedium)),
                  ),
                  // Legend
                  _LegendDot(color: NexGenPalette.green, label: 'Auto'),
                  const SizedBox(width: 8),
                  _LegendDot(color: NexGenPalette.cyan, label: 'User'),
                  const SizedBox(width: 8),
                  _LegendDot(color: NexGenPalette.amber, label: 'Pending'),
                ],
              ),
              const SizedBox(height: 10),

              // Day header row
              Row(
                children: List.generate(7, (i) {
                  final key = days[i];
                  final d = DateTime.parse(key);
                  return Expanded(
                    child: Center(
                      child: Text(
                        _kDayFull[d.weekday % 7],
                        style: TextStyle(
                          color: NexGenPalette.textMedium,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 6),

              // Day cells — horizontally laid out, equal width
              SizedBox(
                height: 118,
                child: Row(
                  children: List.generate(7, (i) {
                    final key = days[i];
                    final d = DateTime.parse(key);
                    final calEntry = pendingEntries[key] ?? calEntries[key];
                    final wd = d.weekday % 7;
                    final recurringItems = _itemsForWeekday(scheduleItems, wd);
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i < 6 ? 5 : 0),
                        child: _WeekDayCell(
                          dateKey: key,
                          calEntry: calEntry,
                          recurringItems: recurringItems,
                          isSelected: key == selectedKey,
                          isPending: pendingEntries.containsKey(key),
                          onTap: () => onDayTap(key),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekDayCell extends StatelessWidget {
  final String dateKey;
  final CalendarEntry? calEntry;
  final List<ScheduleItem> recurringItems;
  final bool isSelected;
  final bool isPending;
  final VoidCallback onTap;

  const _WeekDayCell({
    required this.dateKey,
    required this.calEntry,
    required this.recurringItems,
    required this.isSelected,
    required this.isPending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final d = DateTime.parse(dateKey);
    final isToday = _fmt(today) == dateKey;
    final isPast = d.isBefore(DateTime(today.year, today.month, today.day));
    final isWeekend = d.weekday == 6 || d.weekday == 7;

    // Resolve color from calEntry first, then recurring
    final color = calEntry?.color ??
        (recurringItems.isNotEmpty ? null : null); // Recurring has no color

    final patternName = calEntry?.patternName ??
        (recurringItems.isNotEmpty
            ? _labelFromAction(recurringItems.first.actionLabel)
            : null);

    final onTime = calEntry?.onTime ?? recurringItems.firstOrNull?.timeLabel;
    final offTime = calEntry?.offTime ?? recurringItems.firstOrNull?.offTimeLabel;

    final borderColor = isSelected
        ? NexGenPalette.cyan
        : isToday
            ? NexGenPalette.cyan.withValues(alpha: 0.5)
            : isPending
                ? NexGenPalette.amber
                : NexGenPalette.line;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isPending
              ? NexGenPalette.amber.withValues(alpha: 0.08)
              : color != null
                  ? color.withValues(alpha: 0.12)
                  : NexGenPalette.matteBlack.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
          boxShadow: isSelected
              ? [BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.2), blurRadius: 8)]
              : null,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Day number
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isToday
                          ? NexGenPalette.cyan
                          : isPast
                              ? NexGenPalette.textMedium
                              : isWeekend
                                  ? NexGenPalette.amber
                                  : NexGenPalette.textHigh,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),

                  // Color bar or Off pill
                  if (calEntry?.brightness == 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: NexGenPalette.textMedium.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.nightlight_round, size: 9, color: NexGenPalette.textMedium),
                          const SizedBox(width: 2),
                          Text('Off', style: TextStyle(fontSize: 8, color: NexGenPalette.textMedium, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )
                  else
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: color ?? NexGenPalette.line,
                        boxShadow: color != null
                            ? [
                                BoxShadow(
                                    color: color.withValues(alpha: 0.6),
                                    blurRadius: 4)
                              ]
                            : null,
                      ),
                    ),
                  const SizedBox(height: 5),

                  // Pattern name
                  Text(
                    patternName ?? (recurringItems.isNotEmpty ? '—' : 'Empty'),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      color: isPast
                          ? NexGenPalette.textMedium
                          : NexGenPalette.textMedium,
                      height: 1.3,
                    ),
                  ),

                  const Spacer(),

                  // Time
                  if (onTime != null)
                    Text(
                      offTime != null ? '$onTime–$offTime' : onTime,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 7,
                        color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                        fontFamily: 'monospace',
                      ),
                    ),
                ],
              ),
            ),

            // Status pip (top right)
            Positioned(
              top: 4,
              right: 4,
              child: _statusPip(calEntry, recurringItems),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPip(CalendarEntry? entry, List<ScheduleItem> recurring) {
    if (entry?.type == CalendarEntryType.holiday) {
      return const Text('🎉', style: TextStyle(fontSize: 8));
    }
    if (entry?.type == CalendarEntryType.user) {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: NexGenPalette.cyan,
          shape: BoxShape.circle,
        ),
      );
    }
    if (entry?.type == CalendarEntryType.autopilot) {
      return Icon(Icons.auto_awesome,
          size: 8, color: NexGenPalette.cyan);
    }
    if (entry?.autopilot == true) {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: NexGenPalette.green,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: NexGenPalette.green.withValues(alpha: 0.6), blurRadius: 4)],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  String _labelFromAction(String a) {
    final idx = a.indexOf(':');
    return idx != -1 ? a.substring(idx + 1).trim() : a.trim();
  }
}

// ─── Zoomed Calendar Section ──────────────────────────────────────────────────

class _ZoomedCalendarSection extends StatelessWidget {
  final String viewMode;
  final DateTime calStart;
  final String selectedKey;
  final Map<String, CalendarEntry> calEntries;
  final Map<String, CalendarEntry> pendingEntries;
  final ValueChanged<String> onDayTap;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final String rangeLabel;

  const _ZoomedCalendarSection({
    required this.viewMode,
    required this.calStart,
    required this.selectedKey,
    required this.calEntries,
    required this.pendingEntries,
    required this.onDayTap,
    required this.onPrev,
    required this.onNext,
    required this.rangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final months = {'month': 1, '3month': 3, '6month': 6, 'year': 12}[viewMode]!;
    final cols   = viewMode == 'year' ? 4 : viewMode == '6month' ? 3 : viewMode == '3month' ? 3 : 1;
    final size   = viewMode == 'year' ? _CalDaySize.tiny : _CalDaySize.compact;

    final monthList = List.generate(months, (i) {
      return DateTime(calStart.year, calStart.month + i, 1);
    });

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nav
              Row(children: [
                _NavBtn(icon: Icons.chevron_left_rounded, onTap: onPrev),
                const SizedBox(width: 6),
                _NavBtn(icon: Icons.chevron_right_rounded, onTap: onNext),
                const SizedBox(width: 10),
                Text(rangeLabel,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: NexGenPalette.textHigh,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),

              // Month grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 14,
                  childAspectRatio: viewMode == 'year' ? 0.9 : 0.72,
                ),
                itemCount: monthList.length,
                itemBuilder: (_, i) => _CalendarMonthBlock(
                  firstDay: monthList[i],
                  selectedKey: selectedKey,
                  calEntries: calEntries,
                  pendingEntries: pendingEntries,
                  size: size,
                  onDayTap: onDayTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CalDaySize { compact, tiny }

class _CalendarMonthBlock extends StatelessWidget {
  final DateTime firstDay;
  final String selectedKey;
  final Map<String, CalendarEntry> calEntries;
  final Map<String, CalendarEntry> pendingEntries;
  final _CalDaySize size;
  final ValueChanged<String> onDayTap;

  const _CalendarMonthBlock({
    required this.firstDay,
    required this.selectedKey,
    required this.calEntries,
    required this.pendingEntries,
    required this.size,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final daysInMonth =
        DateTime(firstDay.year, firstDay.month + 1, 0).day;
    final startOffset = firstDay.weekday % 7; // 0=Sun
    final cells = <String?>[
      ...List.filled(startOffset, null),
      ...List.generate(daysInMonth, (i) {
        final d = DateTime(firstDay.year, firstDay.month, i + 1);
        return _fmt(d);
      }),
    ];
    final cellSize = size == _CalDaySize.tiny ? 20.0 : 28.0;
    final fontSize = size == _CalDaySize.tiny ? 7.0 : 9.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_kMonthShort[firstDay.month]} ${firstDay.year}',
          style: TextStyle(
            color: NexGenPalette.cyan,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        // Day-of-week header
        Row(
          children: _kDayShort.map((l) => Expanded(
            child: Center(
              child: Text(l,
                  style: TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 7)),
            ),
          )).toList(),
        ),
        const SizedBox(height: 3),
        // Grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: 1,
          ),
          itemCount: cells.length,
          itemBuilder: (_, i) {
            final key = cells[i];
            if (key == null) return const SizedBox.shrink();
            return _CalDayCell(
              dateKey: key,
              calEntry: pendingEntries[key] ?? calEntries[key],
              isPending: pendingEntries.containsKey(key),
              isSelected: key == selectedKey,
              size: cellSize,
              fontSize: fontSize,
              onTap: () => onDayTap(key),
            );
          },
        ),
      ],
    );
  }
}

class _CalDayCell extends StatelessWidget {
  final String dateKey;
  final CalendarEntry? calEntry;
  final bool isPending;
  final bool isSelected;
  final double size;
  final double fontSize;
  final VoidCallback onTap;

  const _CalDayCell({
    required this.dateKey,
    required this.calEntry,
    required this.isPending,
    required this.isSelected,
    required this.size,
    required this.fontSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final d = DateTime.parse(dateKey);
    final isToday = _fmt(today) == dateKey;
    final isPast = d.isBefore(DateTime(today.year, today.month, today.day));
    final color = calEntry?.color;

    final borderColor = isSelected
        ? NexGenPalette.cyan
        : isToday
            ? NexGenPalette.cyan.withValues(alpha: 0.5)
            : isPending
                ? NexGenPalette.amber
                : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isPending
              ? NexGenPalette.amber.withValues(alpha: 0.12)
              : color != null
                  ? color.withValues(alpha: 0.2)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${d.day}',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w400,
                color: isToday
                    ? NexGenPalette.cyan
                    : isPast
                        ? NexGenPalette.textMedium.withValues(alpha: 0.5)
                        : NexGenPalette.textHigh,
              ),
            ),
            if (calEntry?.brightness == 0 && size >= 24)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.nightlight_round, size: 8, color: NexGenPalette.textMedium),
              )
            else if (color != null && size >= 24)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 3)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Lumina AI Card (FIXED — now writes to calendarScheduleProvider) ──────────

class _LuminaAICard extends ConsumerStatefulWidget {
  const _LuminaAICard();

  @override
  ConsumerState<_LuminaAICard> createState() => _LuminaAICardState();
}

class _LuminaAICardState extends ConsumerState<_LuminaAICard>
    with SingleTickerProviderStateMixin {
  final TextEditingController _ctrl = TextEditingController();
  bool _loading = false;
  String? _lastResponse;

  late final stt.SpeechToText _speech;
  bool _listening = false;

  late final AnimationController _glowController;
  late final Animation<double> _glowAnim;

  static const _quickActions = [
    'July 4th → Independence Blue 100%',
    'Christmas week → red and green',
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    _speech.stop();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    try {
      final available = await _speech.initialize(
        onStatus: (_) {},
        onError: (e) => debugPrint('speech: ${e.errorMsg}'),
      );
      if (!available) return;
      setState(() => _listening = true);
      await _speech.listen(
        onResult: (res) {
          if (!mounted) return;
          if (res.recognizedWords.isNotEmpty) {
            _ctrl.text = res.recognizedWords;
            _ctrl.selection =
                TextSelection.fromPosition(TextPosition(offset: _ctrl.text.length));
          }
          if (res.finalResult) setState(() => _listening = false);
        },
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
      );
    } catch (e) {
      debugPrint('Voice init: $e');
    }
  }

  // ── Core fix: calls LuminaCalendarService → sets pendingCalendarProvider ──

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _lastResponse = null;
    });

    try {
      final result = await LuminaCalendarService.parseRequest(ref, text);

      if (!mounted) return;

      if (result == null || result.changes.isEmpty) {
        setState(() {
          _lastResponse = result?.message ??
              "Lumina couldn't find specific dates to update. Try something like "
              '"every Friday in April" or "turn off December 1st".';
        });
        return;
      }

      // Show preview sheet — user confirms before committing
      ref.read(pendingCalendarProvider.notifier).state = result;
      _ctrl.clear();
      if (!context.mounted) return;
      await _showPendingPreviewSheet(context, ref, result);
      if (mounted) setState(() => _lastResponse = result.message);
    } catch (e) {
      debugPrint('LuminaCalendarService error: $e');
      if (mounted) setState(() => _lastResponse = 'Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final autopilotOn = ref.watch(autopilotEnabledProvider);
    final schedules = ref.watch(schedulesProvider);
    final pending = ref.watch(pendingCalendarProvider);

    // Highlight the AI bar when schedule is empty and autopilot is off
    final bool showHighlight = schedules.isEmpty && !autopilotOn;

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) {
        final glowAlpha = showHighlight ? 0.25 + (_glowAnim.value * 0.35) : 0.0;
        return Container(
          decoration: showHighlight
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: NexGenPalette.cyan.withValues(alpha: glowAlpha),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                )
              : null,
          child: child!,
        );
      },
      child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                NexGenPalette.cyan.withValues(alpha: showHighlight ? 0.18 : 0.12),
                NexGenPalette.violet.withValues(alpha: showHighlight ? 0.12 : 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: NexGenPalette.cyan.withValues(alpha: showHighlight ? 0.55 : 0.35)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [NexGenPalette.violet, NexGenPalette.cyan],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.35), blurRadius: 10),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome_rounded,
                      color: Colors.black, size: 16),
                ),
                const SizedBox(width: 8),
                Text('Lumina AI',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: NexGenPalette.textHigh)),
                const SizedBox(width: 6),
                Text('• Schedule Assistant',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: NexGenPalette.textMedium)),
              ]),

              const SizedBox(height: 10),

              // Input row
              Container(
                decoration: BoxDecoration(
                  color: NexGenPalette.matteBlack.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: NexGenPalette.cyan.withValues(alpha: 0.4),
                      width: 1.5),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _toggleVoice,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _listening
                              ? NexGenPalette.cyan.withValues(alpha: 0.2)
                              : NexGenPalette.gunmetal90,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _listening
                                ? NexGenPalette.cyan
                                : NexGenPalette.line,
                          ),
                        ),
                        child: Icon(
                          _listening ? Icons.mic : Icons.mic_none,
                          color: _listening
                              ? NexGenPalette.cyan
                              : NexGenPalette.violet,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: NexGenPalette.textHigh, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Schedule lights by date, week, or holiday…',
                          hintStyle: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                  color: NexGenPalette.textMedium, fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 4),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _loading
                        ? SizedBox(
                            width: 34,
                            height: 34,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: NexGenPalette.cyan),
                            ),
                          )
                        : GestureDetector(
                            onTap: _submit,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: NexGenPalette.cyan,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_upward_rounded,
                                  size: 18, color: Colors.black),
                            ),
                          ),
                  ],
                ),
              ),

              // Lumina response / error
              if (_lastResponse != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: pending != null
                        ? NexGenPalette.amber.withValues(alpha: 0.1)
                        : NexGenPalette.gunmetal90,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: pending != null
                          ? NexGenPalette.amber.withValues(alpha: 0.4)
                          : NexGenPalette.line,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        pending != null
                            ? Icons.pending_actions_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 16,
                        color: pending != null
                            ? NexGenPalette.amber
                            : NexGenPalette.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _lastResponse!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: NexGenPalette.textHigh),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Quick-action chips
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _quickActions
                    .map((q) => GestureDetector(
                          onTap: () => setState(() => _ctrl.text = q),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: NexGenPalette.matteBlack,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: NexGenPalette.line),
                            ),
                            child: Text(q,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                        color: NexGenPalette.textMedium,
                                        fontSize: 10)),
                          ),
                        ))
                    .toList(),
              ),

              const SizedBox(height: 10),

              // Autopilot toggle (unchanged from original)
              _AutopilotRow(),
            ],
          ),
        ),
      ),
    ), // end AnimatedBuilder child (ClipRRect)
    ); // end AnimatedBuilder
  }
}

// ─── Autopilot Row (extracted from original _AutopilotQuickToggle) ─────────────

class _AutopilotRow extends ConsumerWidget {
  const _AutopilotRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autopilotEnabled = ref.watch(autopilotEnabledProvider);
    final autonomyLevel = ref.watch(autonomyLevelProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: autopilotEnabled
            ? NexGenPalette.cyan.withValues(alpha: 0.1)
            : NexGenPalette.matteBlack.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: autopilotEnabled
              ? NexGenPalette.cyan.withValues(alpha: 0.3)
              : NexGenPalette.line,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.smart_toy_rounded,
              color:
                  autopilotEnabled ? NexGenPalette.cyan : NexGenPalette.textMedium,
              size: 18),
          const SizedBox(width: 8),
          Text('Autopilot',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: autopilotEnabled
                      ? NexGenPalette.cyan
                      : NexGenPalette.textHigh)),
          if (autopilotEnabled) ...[
            const SizedBox(width: 10),
            _AutopilotModeChip(
              label: 'Suggest',
              selected: autonomyLevel == 1,
              onTap: () async => ref.read(autopilotSettingsServiceProvider).setAutonomyLevel(1),
            ),
            const SizedBox(width: 6),
            _AutopilotModeChip(
              label: 'Proactive',
              selected: autonomyLevel == 2,
              onTap: () async {
                final svc = ref.read(autopilotSettingsServiceProvider);
                await svc.setAutonomyLevel(2);
                await svc.generateAndPopulateSchedules();
              },
            ),
          ],
          const Spacer(),
          Transform.scale(
            scale: 0.8,
            child: CupertinoSwitch(
              value: autopilotEnabled,
              activeColor: NexGenPalette.cyan,
              onChanged: (v) async {
                await ref.read(autopilotSettingsServiceProvider).setEnabled(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty States ─────────────────────────────────────────────────────────────

/// State 1: Autopilot OFF, no schedules — invite user to use Lumina AI.
class _AutopilotOffInvitation extends StatelessWidget {
  const _AutopilotOffInvitation();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                NexGenPalette.cyan.withValues(alpha: 0.06),
                NexGenPalette.violet.withValues(alpha: 0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: NexGenPalette.cyan.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // Icon with gradient background
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      NexGenPalette.violet.withValues(alpha: 0.25),
                      NexGenPalette.cyan.withValues(alpha: 0.25),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.auto_awesome_rounded,
                    color: NexGenPalette.cyan, size: 24),
              ),
              const SizedBox(height: 16),

              // Headline
              Text(
                'Your week is wide open',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: NexGenPalette.textHigh,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 6),

              // CTA pointing to Lumina AI bar
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [NexGenPalette.cyan, NexGenPalette.violet],
                ).createShader(bounds),
                child: Text(
                  'Ask Lumina to fill your week',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_upward_rounded,
                      size: 14, color: NexGenPalette.cyan.withValues(alpha: 0.6)),
                  const SizedBox(width: 4),
                  Text(
                    'Use the Lumina AI bar above',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: NexGenPalette.textMedium,
                        ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // Example prompts
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: const [
                  _ExampleChip('"Warm white every night at sunset"'),
                  _ExampleChip('"Christmas week — red & green chase"'),
                ],
              ),

              const SizedBox(height: 18),

              // Divider with "or"
              Row(
                children: [
                  Expanded(child: Divider(color: NexGenPalette.line, height: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: NexGenPalette.textMedium)),
                  ),
                  Expanded(child: Divider(color: NexGenPalette.line, height: 1)),
                ],
              ),

              const SizedBox(height: 14),

              // Autopilot nudge
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy_rounded,
                      size: 16, color: NexGenPalette.textMedium),
                  const SizedBox(width: 6),
                  Text(
                    'Turn on Autopilot and let Lumina handle it',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: NexGenPalette.textMedium,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// State 2: Autopilot ON, schedule generation pending, in progress, or failed.
///
/// Drives off [autopilotGenerationStateProvider] for the *real* loading state
/// (loading / error / idle) and falls back to a "ready to generate" prompt
/// when idle. Auto-triggers a generation on first build if autopilot is on,
/// no schedules exist, no generation is in flight, and no error is set.
class _AutopilotGeneratingState extends ConsumerStatefulWidget {
  const _AutopilotGeneratingState();

  @override
  ConsumerState<_AutopilotGeneratingState> createState() =>
      _AutopilotGeneratingStateState();
}

class _AutopilotGeneratingStateState
    extends ConsumerState<_AutopilotGeneratingState> {
  bool _autoTriggered = false;

  void _maybeAutoTrigger() {
    if (_autoTriggered) return;
    final genState = ref.read(autopilotGenerationStateProvider);
    if (genState.status != AutopilotGenerationStatus.idle) return;
    _autoTriggered = true;
    // Defer past the current build frame so we don't mutate provider state
    // while widgets are still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(autopilotSettingsServiceProvider)
          .generateAndPopulateSchedules(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final genState = ref.watch(autopilotGenerationStateProvider);
    final lastGenerated = ref.watch(autopilotLastGeneratedProvider);
    final bool isFirstRun = lastGenerated == null;

    // Compute next expected generation time (7 days after last successful run)
    final DateTime? nextFire = lastGenerated?.add(const Duration(days: 7));

    // Auto-kick a generation if we're idle and there are still no schedules.
    // Skip if there's an active error so the user has a chance to read it.
    if (genState.status == AutopilotGenerationStatus.idle) {
      _maybeAutoTrigger();
    }

    final isError = genState.hasError;
    final isLoading = genState.isLoading;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isError
                  ? [
                      Colors.red.withValues(alpha: 0.10),
                      Colors.orange.withValues(alpha: 0.06),
                    ]
                  : [
                      NexGenPalette.cyan.withValues(alpha: 0.10),
                      NexGenPalette.violet.withValues(alpha: 0.06),
                    ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isError
                  ? Colors.red.withValues(alpha: 0.4)
                  : NexGenPalette.cyan.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              // ── Status icon / progress ring ──
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isLoading)
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(
                            NexGenPalette.cyan.withValues(alpha: 0.7),
                          ),
                          backgroundColor: NexGenPalette.line,
                        ),
                      ),
                    Icon(
                      isError
                          ? Icons.error_outline_rounded
                          : Icons.smart_toy_rounded,
                      color:
                          isError ? Colors.red.shade300 : NexGenPalette.cyan,
                      size: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Headline ──
              Text(
                isError
                    ? 'Couldn\u2019t generate schedule'
                    : (isLoading
                        ? 'Generating your schedule\u2026'
                        : 'Ready to generate your schedule'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: NexGenPalette.textHigh,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),

              // ── Subtext ──
              Text(
                isError
                    ? (genState.errorMessage ??
                        'Schedule generation failed. Please try again.')
                    : isFirstRun
                        ? 'Lumina is crafting your first lighting plan based on '
                            'your holidays, teams, and preferences.'
                        : 'Lumina is refreshing your weekly lighting plan.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: NexGenPalette.textMedium,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 16),

              // ── Retry button (error state only) ──
              if (isError) ...[
                FilledButton.icon(
                  onPressed: () {
                    ref
                        .read(autopilotSettingsServiceProvider)
                        .generateAndPopulateSchedules(force: true);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again'),
                ),
                const SizedBox(height: 12),
              ],

              // ── Last generated / next refresh chip ──
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: NexGenPalette.cyan.withValues(alpha: 0.2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (lastGenerated != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_rounded,
                              size: 14, color: NexGenPalette.cyan),
                          const SizedBox(width: 6),
                          Text(
                            'Last generated: ${_formatLastGenerated(lastGenerated)}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: NexGenPalette.cyan,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    if (lastGenerated != null) const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.update_rounded,
                            size: 14, color: NexGenPalette.cyan),
                        const SizedBox(width: 6),
                        Text(
                          nextFire != null
                              ? 'Next refresh: ${_kMonthShort[nextFire.month]} ${nextFire.day}, ${nextFire.year}'
                              : 'Building your first week\u2026',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: NexGenPalette.cyan,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Format a last-generated timestamp as "Today" / "Yesterday" / "Apr 7, 2026".
String _formatLastGenerated(DateTime when) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final whenDay = DateTime(when.year, when.month, when.day);
  final diff = today.difference(whenDay).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${_kMonthShort[when.month]} ${when.day}, ${when.year}';
}

// ─── Manual Generate Button ──────────────────────────────────────────────────

/// Full-width primary CTA at the bottom of My Schedule. Forces a fresh
/// autopilot schedule generation, bypassing the weekly refresh gate. Reflects
/// the live state of [autopilotGenerationStateProvider] (idle / loading /
/// error) and surfaces success or failure via SnackBar.
class _GenerateThisWeekButton extends ConsumerWidget {
  const _GenerateThisWeekButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genState = ref.watch(autopilotGenerationStateProvider);
    final isLoading = genState.isLoading;

    Future<void> handleTap() async {
      if (isLoading) return;
      final messenger = ScaffoldMessenger.of(context);
      final beforeStatus =
          ref.read(autopilotGenerationStateProvider).status;
      await ref
          .read(autopilotSettingsServiceProvider)
          .generateAndPopulateSchedules(force: true);
      if (!context.mounted) return;
      final afterState = ref.read(autopilotGenerationStateProvider);
      // Skipped because already in progress — no toast needed.
      if (beforeStatus == AutopilotGenerationStatus.loading) return;
      if (afterState.hasError) {
        messenger.showSnackBar(SnackBar(
          content: Text(
            afterState.errorMessage ??
                'Couldn\u2019t generate schedule. Try again.',
          ),
          backgroundColor: Colors.red.shade700,
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: const Text('Schedule generated for this week.'),
          backgroundColor: Colors.green.shade700,
        ));
      }
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(16, 8, 16, navBarTotalHeight(context) + 8),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: isLoading ? null : handleTap,
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              disabledBackgroundColor:
                  NexGenPalette.cyan.withValues(alpha: 0.4),
              disabledForegroundColor: Colors.black54,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            icon: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.black),
                    ),
                  )
                : const Icon(Icons.auto_awesome_rounded, size: 20),
            label: Text(
              isLoading
                  ? 'Generating\u2026'
                  : 'Generate This Week\u2019s Schedule',
            ),
          ),
        ),
      ),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  final String text;
  const _ExampleChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: NexGenPalette.textMedium,
              fontStyle: FontStyle.italic,
              fontSize: 11,
            ),
      ),
    );
  }
}

// ─── Shared small widgets ─────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: NexGenPalette.matteBlack,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Icon(icon, size: 18, color: NexGenPalette.textMedium),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
              color: color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 3)])),
      const SizedBox(width: 3),
      Text(label,
          style: TextStyle(
              color: NexGenPalette.textMedium, fontSize: 8, letterSpacing: 0.4)),
    ]);
  }
}

// ─── All original widgets kept exactly as-is below ────────────────────────────
// _AutopilotModeChip, _AutopilotSetupSheet, _ScheduleCard, _ScheduleEditor,
// _DayChip, _DayCircleChip, _TimeWheel, _SolarEventPicker,
// PatternSelection, _PatternPickerRow, _PatternPickerSheet,
// _AggregatedPatternGrid, showScheduleEditor
// (copy these verbatim from the original my_schedule_page.dart)

class _AutopilotModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AutopilotModeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? NexGenPalette.cyan.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? NexGenPalette.cyan : NexGenPalette.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Opens the Schedule Editor bottom sheet.
void showScheduleEditor(
  BuildContext context,
  WidgetRef ref, {
  int? preselectedDayIndex,
  ScheduleItem? editing,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _ScheduleEditor(
        preselectedDayIndex: preselectedDayIndex,
        editing: editing,
        scrollController: scroll,
      ),
    ),
  );
}

// ─── _ScheduleCard, _ScheduleEditor, and all supporting widgets ───────────────
// These are 100% unchanged from the original my_schedule_page.dart.

class _ScheduleCard extends ConsumerWidget {
  final ScheduleItem item;
  const _ScheduleCard({required this.item});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Build time display string
    final timeDisplay = item.hasOffTime
        ? '${item.timeLabel} → ${item.offTimeLabel}'
        : item.timeLabel;

    // Extract preview colors from WLED payload
    final previewColors = _extractStripColors(null, item.wledPayload);
    final effectId = _extractEffectId(item.wledPayload);
    final effectType = effectId != null ? effectTypeFromWledId(effectId) : EffectType.solid;
    final speed = _extractNormalized(item.wledPayload, 'sx');

    // Extract brightness from payload (top-level bri, 0-255)
    final payloadBri = item.wledPayload?['bri'];
    final briFraction = payloadBri is num ? (payloadBri / 255.0).clamp(0.0, 1.0) : 1.0;
    final briPercent = payloadBri is num ? (payloadBri / 255.0 * 100).round() : null;

    // Extract effect name from action label
    final effectName = item.actionLabel.startsWith('Pattern: ')
        ? item.actionLabel.substring(9)
        : null;

    final effectLabel = effectId != null
        ? _wledEffectName(effectId)
        : effectName ?? item.actionLabel;

    // Build recurrence label
    final recurrence = item.repeatDays.length == 7
        ? 'Daily'
        : item.repeatDays.length == 5 &&
                item.repeatDays.every((d) => ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'].contains(d))
            ? 'Weekdays'
            : item.repeatDays.join(', ');

    return GestureDetector(
      onTap: () => _showScheduleDetailSheet(
        context,
        colors: previewColors.isNotEmpty ? previewColors : const [NexGenPalette.cyan],
        effectType: effectType,
        speed: speed,
        brightness: briFraction,
        patternName: effectName ?? item.actionLabel,
        effectName: effectLabel,
        onTime: item.timeLabel,
        offTime: item.offTimeLabel,
        brightnessPercent: briPercent,
        source: 'Recurring Schedule',
      ),
      child: Column(
        children: [
          // Pixel strip above the identity card
          if (previewColors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 0),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: PixelStripPreview(
                  colors: previewColors,
                  effectType: effectType,
                  speed: speed,
                  brightness: briFraction,
                  pixelCount: 20,
                  height: 24,
                  borderRadius: 0,
                  backgroundColor: const Color(0xFF0A0E14),
                ),
              ),
            ),
          ScheduleIdentityCard(
            type: ScheduleEntryType.personalAutopilot,
            patternName: effectName ?? item.actionLabel,
            previewColors: previewColors,
            effectName: effectName != null ? item.actionLabel : null,
            timeLabel: timeDisplay,
            recurrenceLabel: recurrence,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => showScheduleEditor(context, ref, editing: item),
                  icon: const Icon(Icons.edit_rounded, color: Colors.white70, size: 18),
                  constraints: const BoxConstraints(minWidth: 32),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  tooltip: 'Delete',
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete schedule?'),
                        content: const Text('This action cannot be undone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                          FilledButton.tonal(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      ref.read(schedulesProvider.notifier).remove(item.id);
                    }
                  },
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 18),
                  constraints: const BoxConstraints(minWidth: 32),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 4),
                CupertinoSwitch(
                  value: item.enabled,
                  activeColor: NexGenPalette.cyan,
                  onChanged: (v) => ref.read(schedulesProvider.notifier).toggle(item.id, v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleEditor extends ConsumerStatefulWidget {
  final int? preselectedDayIndex; // 0..6 => S..S
  final ScheduleItem? editing;
  final ScrollController? scrollController;
  const _ScheduleEditor({this.preselectedDayIndex, this.editing, this.scrollController});
  @override
  ConsumerState<_ScheduleEditor> createState() => _ScheduleEditorState();
}

enum _TriggerType { specificTime, solarEvent }
enum _ActionType { powerOff, runPattern, brightness }

class _ScheduleEditorState extends ConsumerState<_ScheduleEditor> {
  // ON time settings
  _TriggerType _onTrigger = _TriggerType.specificTime;
  TimeOfDay _onTime = const TimeOfDay(hour: 19, minute: 0);
  String _onSolar = 'Sunset'; // 'Sunrise' or 'Sunset'

  // OFF time settings
  bool _hasOffTime = true; // Default to having an off time
  _TriggerType _offTrigger = _TriggerType.solarEvent;
  TimeOfDay _offTime = const TimeOfDay(hour: 23, minute: 0);
  String _offSolar = 'Sunrise'; // 'Sunrise' or 'Sunset'

  _ActionType _action = _ActionType.runPattern;
  double _brightness = 70; // percentage 0..100
  PatternSelection? _selectedPattern;
  bool _useAudioReactive = false;

  // Day selection represented as indices 0..6 => S M T W T F S
  final List<String> _dayLabelsShort = const ['S','M','T','W','T','F','S'];
  final List<String> _dayAbbr = const ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  late Set<int> _selectedDays;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    // Defaults: all days (Daily) unless a specific day was preselected
    _selectedDays = {0, 1, 2, 3, 4, 5, 6};
    _enabled = true;
    // If editing an existing item, hydrate state from it.
    final editing = widget.editing;
    if (editing != null) {
      _enabled = editing.enabled;
      // Days
      final daysLower = editing.repeatDays.map((e) => e.toLowerCase()).toList(growable: false);
      if (daysLower.any((d) => d.contains('daily'))) {
        _selectedDays = {0, 1, 2, 3, 4, 5, 6};
      } else {
        _selectedDays.clear();
        for (int i = 0; i < 7; i++) {
          final label = _dayAbbr[i].toLowerCase();
          if (daysLower.contains(label)) _selectedDays.add(i);
        }
        if (_selectedDays.isEmpty) {
          _selectedDays = {1, 3, 5};
        }
      }
      // ON Trigger
      final tl = editing.timeLabel.trim().toLowerCase();
      if (tl == 'sunset' || tl == 'sunrise') {
        _onTrigger = _TriggerType.solarEvent;
        _onSolar = tl == 'sunrise' ? 'Sunrise' : 'Sunset';
      } else {
        _onTrigger = _TriggerType.specificTime;
        final reg = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$', caseSensitive: false);
        final m = reg.firstMatch(editing.timeLabel.trim());
        if (m != null) {
          var hh = int.tryParse(m.group(1)!) ?? 7;
          final mm = int.tryParse(m.group(2)!) ?? 0;
          final ap = m.group(3)!.toLowerCase();
          if (ap == 'pm' && hh != 12) hh += 12;
          if (ap == 'am' && hh == 12) hh = 0;
          _onTime = TimeOfDay(hour: hh.clamp(0, 23), minute: mm.clamp(0, 59));
        }
      }
      // OFF Trigger
      _hasOffTime = editing.hasOffTime;
      if (editing.offTimeLabel != null) {
        final otl = editing.offTimeLabel!.trim().toLowerCase();
        if (otl == 'sunset' || otl == 'sunrise') {
          _offTrigger = _TriggerType.solarEvent;
          _offSolar = otl == 'sunrise' ? 'Sunrise' : 'Sunset';
        } else {
          _offTrigger = _TriggerType.specificTime;
          final reg = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$', caseSensitive: false);
          final m = reg.firstMatch(editing.offTimeLabel!.trim());
          if (m != null) {
            var hh = int.tryParse(m.group(1)!) ?? 23;
            final mm = int.tryParse(m.group(2)!) ?? 0;
            final ap = m.group(3)!.toLowerCase();
            if (ap == 'pm' && hh != 12) hh += 12;
            if (ap == 'am' && hh == 12) hh = 0;
            _offTime = TimeOfDay(hour: hh.clamp(0, 23), minute: mm.clamp(0, 59));
          }
        }
      }
      // Action
      final a = editing.actionLabel.trim();
      final lower = a.toLowerCase();
      if (lower == 'react to music' || (editing.useAudioReactive == true)) {
        _action = _ActionType.runPattern;
        _useAudioReactive = true;
      } else if (lower.startsWith('pattern')) {
        _action = _ActionType.runPattern;
        final idx = a.indexOf(':');
        final name = (idx != -1 && idx + 1 < a.length) ? a.substring(idx + 1).trim() : a.replaceFirst(RegExp(r'^pattern', caseSensitive: false), '').trim();
        _selectedPattern = PatternSelection(id: 'existing', name: name, imageUrl: '');
      } else if (lower.startsWith('brightness')) {
        _action = _ActionType.brightness;
        final mm = RegExp(r'(\d{1,3})%').firstMatch(lower);
        final val = int.tryParse(mm?.group(1) ?? '') ?? 70;
        _brightness = val.clamp(1, 100).toDouble();
      } else if (lower.contains('turn off')) {
        _action = _ActionType.powerOff;
      } else if (lower.contains('turn on')) {
        // Map "Turn On" to brightness 100%
        _action = _ActionType.brightness;
        _brightness = 100;
      }
      // Hydrate audio reactive state
      _useAudioReactive = editing.useAudioReactive ?? false;
    } else if (widget.preselectedDayIndex != null && widget.preselectedDayIndex! >= 0 && widget.preselectedDayIndex! <= 6) {
      _selectedDays = {widget.preselectedDayIndex!};
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedules = ref.watch(schedulesProvider);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(color: NexGenPalette.gunmetal90, border: Border(top: BorderSide(color: NexGenPalette.line)), boxShadow: [
            BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.06), blurRadius: 20),
          ]),
          child: SafeArea(
            top: false,
            child: ListView(
              controller: widget.scrollController,
              // Bottom padding clears the glass dock nav bar overlay.
              // The dock sits in the parent Stack and is NOT pushed aside
              // by modal sheets opened from the inner navigator, so the
              // last action button (Save/Delete) would otherwise sit
              // behind the dock when the sheet is fully expanded.
              padding: EdgeInsets.fromLTRB(16, 16, 16, kBottomNavBarPadding + 16),
              children: [
                Row(children: [
                  Text(widget.editing == null ? 'New Schedule' : 'Edit Schedule', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  CupertinoSwitch(value: _enabled, activeColor: NexGenPalette.cyan, onChanged: (v) => setState(() => _enabled = v)),
                ]),
                const SizedBox(height: 16),

                // ON TIME Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.power_settings_new_rounded, color: NexGenPalette.cyan, size: 20),
                          const SizedBox(width: 8),
                          Text('Turn On', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: NexGenPalette.cyan, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<_TriggerType>(
                        segments: const [
                          ButtonSegment(value: _TriggerType.specificTime, icon: Icon(Icons.schedule_rounded, size: 18), label: Text('Time')),
                          ButtonSegment(value: _TriggerType.solarEvent, icon: Icon(Icons.wb_sunny_rounded, size: 18), label: Text('Solar')),
                        ],
                        selected: {_onTrigger},
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? NexGenPalette.cyan.withValues(alpha: 0.16) : Colors.transparent),
                          foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? NexGenPalette.cyan : NexGenPalette.textHigh),
                          side: WidgetStatePropertyAll(BorderSide(color: NexGenPalette.line)),
                        ),
                        onSelectionChanged: (s) => setState(() => _onTrigger = s.first),
                      ),
                      const SizedBox(height: 12),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _onTrigger == _TriggerType.specificTime
                            ? _TimeWheel(key: const ValueKey('on_time'), initial: _onTime, onChanged: (t) => setState(() => _onTime = t))
                            : _SolarEventPicker(key: const ValueKey('on_solar'), selected: _onSolar, onChanged: (s) => setState(() => _onSolar = s)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // OFF TIME Section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _hasOffTime ? NexGenPalette.violet.withValues(alpha: 0.08) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _hasOffTime ? NexGenPalette.violet.withValues(alpha: 0.3) : NexGenPalette.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.power_off_rounded, color: _hasOffTime ? NexGenPalette.violet : NexGenPalette.textMedium, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Turn Off', style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: _hasOffTime ? NexGenPalette.violet : NexGenPalette.textMedium,
                              fontWeight: FontWeight.w600,
                            )),
                          ),
                          CupertinoSwitch(
                            value: _hasOffTime,
                            activeColor: NexGenPalette.violet,
                            onChanged: (v) => setState(() => _hasOffTime = v),
                          ),
                        ],
                      ),
                      if (_hasOffTime) ...[
                        const SizedBox(height: 12),
                        SegmentedButton<_TriggerType>(
                          segments: const [
                            ButtonSegment(value: _TriggerType.specificTime, icon: Icon(Icons.schedule_rounded, size: 18), label: Text('Time')),
                            ButtonSegment(value: _TriggerType.solarEvent, icon: Icon(Icons.wb_sunny_rounded, size: 18), label: Text('Solar')),
                          ],
                          selected: {_offTrigger},
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? NexGenPalette.violet.withValues(alpha: 0.16) : Colors.transparent),
                            foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? NexGenPalette.violet : NexGenPalette.textHigh),
                            side: WidgetStatePropertyAll(BorderSide(color: NexGenPalette.line)),
                          ),
                          onSelectionChanged: (s) => setState(() => _offTrigger = s.first),
                        ),
                        const SizedBox(height: 12),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _offTrigger == _TriggerType.specificTime
                              ? _TimeWheel(key: const ValueKey('off_time'), initial: _offTime, onChanged: (t) => setState(() => _offTime = t))
                              : _SolarEventPicker(key: const ValueKey('off_solar'), selected: _offSolar, onChanged: (s) => setState(() => _offSolar = s)),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                Text('Repeat Days', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  for (int i = 0; i < 7; i++)
                    _DayCircleChip(
                      label: _dayLabelsShort[i],
                      selected: _selectedDays.contains(i),
                      onTap: () => setState(() {
                        if (_selectedDays.contains(i)) {
                          _selectedDays.remove(i);
                        } else {
                          _selectedDays.add(i);
                        }
                      }),
                    ),
                ]),
                const SizedBox(height: 16),
                Text('Action', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                DropdownButtonFormField<_ActionType>(
                  value: _action,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.bolt_rounded), labelText: 'What should the lights do?'),
                  items: const [
                    DropdownMenuItem(value: _ActionType.powerOff, child: Text('Turn Off')),
                    DropdownMenuItem(value: _ActionType.runPattern, child: Text('Run Pattern')),
                    DropdownMenuItem(value: _ActionType.brightness, child: Text('Set Brightness')),
                  ],
                  onChanged: (v) => setState(() => _action = v ?? _action),
                ),
                const SizedBox(height: 12),
                // React to Music toggle — only shown when audio reactivity is
                // available on the connected controller and action is runPattern
                if (_action == _ActionType.runPattern)
                  Builder(builder: (context) {
                    final ip = ref.watch(selectedDeviceIpProvider);
                    if (ip == null) return const SizedBox.shrink();
                    final capAsync = ref.watch(audioCapabilityProvider(ip));
                    return capAsync.maybeWhen(
                      data: (cap) {
                        if (!cap.isSupported) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _useAudioReactive
                                  ? NexGenPalette.cyan.withValues(alpha: 0.08)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _useAudioReactive
                                    ? NexGenPalette.cyan.withValues(alpha: 0.3)
                                    : NexGenPalette.line,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.mic, size: 20, color: _useAudioReactive ? NexGenPalette.cyan : NexGenPalette.textMedium),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'React to Music',
                                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          color: _useAudioReactive ? NexGenPalette.cyan : NexGenPalette.textHigh,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'Use a random audio-reactive effect',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: NexGenPalette.textMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                CupertinoSwitch(
                                  value: _useAudioReactive,
                                  activeColor: NexGenPalette.cyan,
                                  onChanged: (v) => setState(() => _useAudioReactive = v),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    );
                  }),
                if (_action == _ActionType.runPattern && !_useAudioReactive)
                  _PatternPickerRow(
                    selection: _selectedPattern,
                    onPick: () async {
                      final picked = await showModalBottomSheet<PatternSelection>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _PatternPickerSheet(),
                      );
                      if (!mounted) return;
                      setState(() => _selectedPattern = picked ?? _selectedPattern);
                    },
                  ),
                if (_action == _ActionType.brightness)
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.brightness_6_rounded, size: 18, color: Colors.white70),
                      const SizedBox(width: 8),
                      Text('Brightness: ${_brightness.round()}%', style: Theme.of(context).textTheme.labelMedium),
                    ]),
                    Slider(
                      value: _brightness,
                      min: 1,
                      max: 100,
                      activeColor: NexGenPalette.cyan,
                      onChanged: (v) => setState(() => _brightness = v),
                    ),
                  ]),
                const SizedBox(height: 20),
                // Delete button (only when editing existing schedule)
                if (widget.editing != null) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: NexGenPalette.gunmetal90,
                          title: const Text('Delete Schedule?'),
                          content: const Text('This action cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        ref.read(schedulesProvider.notifier).remove(widget.editing!.id);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete Schedule'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      side: BorderSide(color: Colors.red.shade400),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: () async {
                    // Limit enforcement
                    if (widget.editing == null && schedules.length >= 20) {
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Maximum limit reached.'),
                          content: const Text('You can have up to 20 schedules.'),
                          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
                        ),
                      );
                      return;
                    }
                    if (_selectedDays.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one day')));
                      return;
                    }
                    if (_action == _ActionType.runPattern && !_useAudioReactive && _selectedPattern == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a pattern to run')));
                      return;
                    }

                    // Use the original ID when editing, or generate a new one
                    final id = widget.editing?.id ?? 'sch-${DateTime.now().millisecondsSinceEpoch}';
                    final timeLabel = _onTrigger == _TriggerType.specificTime ? _formatTime(_onTime) : _onSolar;
                    final offTimeLabel = _hasOffTime
                        ? (_offTrigger == _TriggerType.specificTime ? _formatTime(_offTime) : _offSolar)
                        : null;
                    final days = _selectedDays.map((i) => _dayAbbr[i]).toList(growable: false);
                    String actionLabel;
                    switch (_action) {
                      case _ActionType.powerOff:
                        actionLabel = 'Turn Off';
                        break;
                      case _ActionType.runPattern:
                        actionLabel = _useAudioReactive
                            ? 'React to Music'
                            : 'Pattern: ${_selectedPattern!.name}';
                        break;
                      case _ActionType.brightness:
                        actionLabel = 'Brightness: ${_brightness.round()}%';
                        break;
                    }

                    final item = ScheduleItem(
                      id: id, // Use ID as-is to match existing schedule
                      timeLabel: timeLabel,
                      offTimeLabel: offTimeLabel,
                      repeatDays: days,
                      actionLabel: actionLabel,
                      enabled: _enabled,
                      wledPayload: widget.editing?.wledPayload,
                      presetId: widget.editing?.presetId,
                      useAudioReactive: _useAudioReactive ? true : null,
                    );

                    try {
                      if (widget.editing == null) {
                        await ref.read(schedulesProvider.notifier).add(item);
                      } else {
                        await ref.read(schedulesProvider.notifier).update(item);
                      }
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    } catch (e) {
                      debugPrint('Schedule save/update failed: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save schedule: $e')),
                        );
                      }
                    }
                  },
                  child: Text(widget.editing == null ? 'Save Schedule' : 'Update Schedule'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }
}

// Circular single-letter day chip used in editor
class _DayCircleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayCircleChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = selected ? NexGenPalette.cyan.withValues(alpha: 0.18) : Colors.transparent;
    final border = selected ? NexGenPalette.cyan : NexGenPalette.line;
    final color = selected ? NexGenPalette.cyan : NexGenPalette.textMedium;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: ShapeDecoration(shape: CircleBorder(side: BorderSide(color: border, width: 1.2)), color: bg),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
      ),
    );
  }
}

// Time wheel picker wrapper
class _TimeWheel extends StatelessWidget {
  final TimeOfDay initial;
  final ValueChanged<TimeOfDay> onChanged;
  const _TimeWheel({super.key, required this.initial, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.time,
        initialDateTime: DateTime(2020, 1, 1, initial.hour, initial.minute),
        use24hFormat: false,
        onDateTimeChanged: (dt) => onChanged(TimeOfDay(hour: dt.hour, minute: dt.minute)),
      ),
    );
  }
}

class _SolarEventPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _SolarEventPicker({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget buildBtn(String label, IconData icon) => Expanded(
      child: InkWell(
        onTap: () => onChanged(label),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected == label ? NexGenPalette.cyan : NexGenPalette.line, width: 1.2),
            color: selected == label ? NexGenPalette.cyan.withValues(alpha: 0.12) : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: selected == label ? NexGenPalette.cyan : NexGenPalette.textHigh),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: selected == label ? NexGenPalette.cyan : NexGenPalette.textHigh)),
          ]),
        ),
      ),
    );

    return Row(children: [
      buildBtn('Sunrise', Icons.wb_sunny_outlined),
      const SizedBox(width: 12),
      buildBtn('Sunset', Icons.wb_sunny_rounded),
    ]);
  }
}

// Holds selected pattern info for the editor
class PatternSelection {
  final String id;
  final String name;
  final String imageUrl;
  const PatternSelection({required this.id, required this.name, required this.imageUrl});
}

class _PatternPickerRow extends StatelessWidget {
  final PatternSelection? selection;
  final VoidCallback onPick;
  const _PatternPickerRow({required this.selection, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(border: Border.all(color: NexGenPalette.line), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
                child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: NexGenPalette.matteBlack.withValues(alpha: 0.2)),
                  child: selection == null || selection!.imageUrl.isEmpty
                      ? Icon(Icons.image_rounded, color: NexGenPalette.textMedium)
                      : Image.network(selection!.imageUrl, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(selection?.name ?? 'Choose a pattern', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: NexGenPalette.textHigh)),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 12),
      FilledButton.tonal(onPressed: onPick, child: const Text('Pick')),
    ]);
  }
}

// Full-screen bottom sheet pattern picker
class _PatternPickerSheet extends ConsumerWidget {
  const _PatternPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(color: NexGenPalette.gunmetal90, border: Border(top: BorderSide(color: NexGenPalette.line))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Text('Select Pattern', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: _AggregatedPatternGrid(onSelect: (sel) => Navigator.of(context).pop(sel)),
            ),
          ]),
        ),
      ),
    );
  }
}

// Aggregated grid showing all predefined patterns (Architectural + Holidays + Sports)
class _AggregatedPatternGrid extends ConsumerWidget {
  final ValueChanged<PatternSelection> onSelect;
  const _AggregatedPatternGrid({required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(publicPatternLibraryProvider);
    final all = lib.all;
    if (all.isEmpty) return const Center(child: Text('No patterns'));
    return GridView.builder(
      // Bottom padding clears the glass dock nav bar overlay so the
      // last row of pattern tiles is reachable when this picker sheet
      // is opened from the schedule editor.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, kBottomNavBarPadding + 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.9),
      itemCount: all.length,
      itemBuilder: (_, i) {
        final p = all[i];
        return InkWell(
          onTap: () => onSelect(PatternSelection(id: p.name.toLowerCase().replaceAll(' ', '_'), name: p.name, imageUrl: '')),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Stack(children: [
              // Gradient preview background using the pattern's colors
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: p.colors),
                  ),
                ),
              ),
              // Readability overlay + border
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        NexGenPalette.matteBlack.withValues(alpha: 0.06),
                        NexGenPalette.matteBlack.withValues(alpha: 0.60),
                      ],
                    ),
                    border: Border.all(color: NexGenPalette.line),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(p.name, style: Theme.of(context).textTheme.labelLarge),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
