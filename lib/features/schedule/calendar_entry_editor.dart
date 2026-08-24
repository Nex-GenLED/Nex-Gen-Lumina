// lib/features/schedule/calendar_entry_editor.dart
//
// Bottom-sheet editor for calendar entries. When editing an autopilot-type
// entry, shows a scope choice on save: "this game only" vs "all future
// [Team] games".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import '../autopilot/game_day_autopilot_config.dart';
import '../autopilot/game_day_autopilot_providers.dart';
import 'calendar_entry.dart';
import 'calendar_providers.dart';
import 'package:nexgen_command/features/schedule/dated_overwrite_dialog.dart';

/// Show the calendar entry editor bottom sheet.
///
/// [teamConfig] is required only for autopilot entries so the scope-choice
/// dialog can name the team and push settings updates.
void showCalendarEntryEditor(
  BuildContext context,
  WidgetRef ref, {
  required CalendarEntry entry,
  GameDayAutopilotConfig? teamConfig,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CalendarEntryEditor(
      entry: entry,
      teamConfig: teamConfig,
    ),
  );
}

class _CalendarEntryEditor extends ConsumerStatefulWidget {
  final CalendarEntry entry;
  final GameDayAutopilotConfig? teamConfig;

  const _CalendarEntryEditor({
    required this.entry,
    this.teamConfig,
  });

  @override
  ConsumerState<_CalendarEntryEditor> createState() =>
      _CalendarEntryEditorState();
}

class _CalendarEntryEditorState extends ConsumerState<_CalendarEntryEditor> {
  late String _onTime;
  late String _offTime;
  late int _brightness;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _onTime = widget.entry.onTime ?? '18:00';
    _offTime = widget.entry.offTime ?? '23:00';
    _brightness = widget.entry.brightness;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomPad),
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
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: NexGenPalette.textMedium.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Row(
            children: [
              if (widget.entry.type == CalendarEntryType.autopilot)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.auto_awesome,
                      size: 18, color: NexGenPalette.cyan),
                ),
              Expanded(
                child: Text(
                  'Edit ${widget.entry.displayName}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: NexGenPalette.textHigh,
                  ),
                ),
              ),
            ],
          ),
          if (widget.entry.note != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.entry.note!,
              style: TextStyle(
                fontSize: 12,
                color: NexGenPalette.textMedium,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            widget.entry.dateKey,
            style: TextStyle(
              fontSize: 13,
              color: NexGenPalette.textMedium.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 20),

          // On-time picker
          _buildTimePicker(
            icon: Icons.wb_sunny_rounded,
            label: 'On time',
            value: _onTime,
            color: NexGenPalette.cyan,
            onTap: () => _pickTime(isOn: true),
          ),
          const SizedBox(height: 12),

          // Off time — OR the end CONDITION, for an open-ended entry.
          //
          // Scheduling V3 B1. A Game Day entry has no clock end: the real end
          // is an ESPN final, server-side. Offering an editable "Off time" for
          // it would let the user set a value nothing reads — which is how the
          // fabricated off-time came to be trusted in the first place. So an
          // open-ended entry shows its condition read-only instead.
          if (widget.entry.isOpenEnded)
            _buildEndConditionRow()
          else
            _buildTimePicker(
              icon: Icons.nightlight_round,
              label: 'Off time',
              value: _offTime,
              color: NexGenPalette.violet,
              onTap: () => _pickTime(isOn: false),
            ),
          const SizedBox(height: 16),

          // Brightness slider
          Row(
            children: [
              Icon(Icons.brightness_6_rounded,
                  size: 18, color: NexGenPalette.amber),
              const SizedBox(width: 10),
              const Text(
                'Brightness',
                style: TextStyle(
                  fontSize: 14,
                  color: NexGenPalette.textMedium,
                ),
              ),
              const Spacer(),
              Text(
                '$_brightness%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: NexGenPalette.textHigh,
                ),
              ),
            ],
          ),
          Slider(
            value: _brightness.toDouble(),
            min: 0,
            max: 100,
            divisions: 20,
            activeColor: NexGenPalette.cyan,
            inactiveColor: NexGenPalette.line,
            onChanged: (v) => setState(() => _brightness = v.round()),
          ),
          const SizedBox(height: 20),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: NexGenPalette.matteBlack,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: NexGenPalette.textMedium,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: NexGenPalette.textHigh,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right,
                size: 18, color: NexGenPalette.textMedium),
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime({required bool isOn}) async {
    final current = isOn ? _onTime : _offTime;
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 18,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: NexGenPalette.cyan,
            surface: NexGenPalette.gunmetal,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (isOn) {
        _onTime = formatted;
      } else {
        _offTime = formatted;
      }
    });
  }

  /// Read-only end display for an open-ended entry (V3 B1).
  ///
  /// Shows what actually ends the show, the display estimate, and — when one is
  /// stored — the fail-safe cap. **`hardCapAt` is deliberately NOT editable.**
  /// It is a client-side display value; under Policy B the authoritative cap
  /// will be a server-side fire job written by the planner, so an editable
  /// field here would be a control that changes nothing on the controller.
  Widget _buildEndConditionRow() {
    final entry = widget.entry;
    final cap = entry.hardCapAt;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NexGenPalette.violet.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.violet.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.nightlight_round, size: 18, color: NexGenPalette.violet),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ends',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.endConditionLabel(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: NexGenPalette.textHigh,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  cap == null
                      ? 'The game decides. The estimate is a guess, not a '
                          'setting.'
                      : 'The game decides. If it never reports final, the '
                          'show stops by '
                          '${cap.hour.toString().padLeft(2, '0')}:'
                          '${cap.minute.toString().padLeft(2, '0')}.',
                  style: TextStyle(
                    fontSize: 10,
                    color: NexGenPalette.textMedium,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSave() async {
    // An open-ended entry keeps its endMode and gets NO offTime written back —
    // the picker for it was never shown, so `_offTime` holds only its default.
    final edited = widget.entry.isOpenEnded
        ? widget.entry.copyWith(onTime: _onTime, brightness: _brightness)
        : widget.entry.copyWith(
            onTime: _onTime,
            offTime: _offTime,
            brightness: _brightness,
          );

    // If this is a user or holiday entry, save directly — no scope choice.
    if (widget.entry.type != CalendarEntryType.autopilot) {
      await _saveThisGameOnly(edited);
      return;
    }

    // Autopilot entry — show scope choice
    if (!mounted) return;
    _showScopeChoice(edited);
  }

  void _showScopeChoice(CalendarEntry edited) {
    final teamName = widget.teamConfig?.teamName ?? 'this team';

    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
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
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color:
                        NexGenPalette.textMedium.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Save changes for...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: NexGenPalette.textHigh,
                ),
              ),
              const SizedBox(height: 16),

              // Option 1: This game only
              _ScopeOption(
                icon: Icons.today_rounded,
                label: 'This game only',
                subtitle: 'Override just ${edited.dateKey}',
                onTap: () {
                  Navigator.pop(ctx);
                  _saveThisGameOnly(edited);
                },
              ),
              const SizedBox(height: 8),

              // Option 2: All future games
              _ScopeOption(
                icon: Icons.date_range_rounded,
                label: 'All future $teamName games',
                subtitle:
                    'Update autopilot settings and regenerate schedule',
                onTap: () {
                  Navigator.pop(ctx);
                  _saveAllFutureGames(edited);
                },
              ),
              const SizedBox(height: 12),

              // Cancel
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: NexGenPalette.textMedium),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Save as a per-date user override. Converts the entry type from
  /// .autopilot to .user so it takes priority over auto-generated entries.
  Future<void> _saveThisGameOnly(CalendarEntry edited) async {
    setState(() => _saving = true);
    try {
      final userEntry = edited.copyWith(
        type: CalendarEntryType.user,
        autopilot: false,
      );
      final notifier = ref.read(calendarScheduleProvider.notifier);
      // A3 — ask BEFORE destroying a user-authored dated entry.
      //
      // NOTE (V3 A1): storage no longer holds one entry per date. This save
      // upserts by (dateKey, entryId), so it replaces THIS entry and leaves the
      // rest of the night alone. The prompt is still right, because the entry
      // being replaced can itself be user-authored.
      final overwrites = notifier.findDatedOverwrites([userEntry]);
      var acknowledged = false;
      if (overwrites.isNotEmpty) {
        if (!mounted) return;
        final choice = await showDatedOverwriteDialog(context, overwrites);
        if (choice == DatedOverwriteChoice.cancel) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        acknowledged = true;
      }
      await notifier.applyEntries([userEntry],
          overwriteAcknowledged: acknowledged);
      if (!mounted) return;
      Navigator.pop(context); // Close editor
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved for this game'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Update the team's autopilot config with the new on/off times and
  /// trigger re-population of all future calendar entries.
  Future<void> _saveAllFutureGames(CalendarEntry edited) async {
    if (widget.teamConfig == null) {
      // Fallback: save as single-game override
      await _saveThisGameOnly(edited);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(gameDayAutopilotNotifierProvider.notifier)
          .updateTeamSettings(
            teamSlug: widget.teamConfig!.teamSlug,
            onTimeOverride: edited.onTime,
            offTimeOverride: edited.offTime,
          );
      if (!mounted) return;
      Navigator.pop(context); // Close editor
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Updated all future ${widget.teamConfig!.teamName} games'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// A single scope-choice option row.
class _ScopeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ScopeOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: NexGenPalette.cyan),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: NexGenPalette.textHigh,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: NexGenPalette.textMedium,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 20, color: NexGenPalette.textMedium),
          ],
        ),
      ),
    );
  }
}
