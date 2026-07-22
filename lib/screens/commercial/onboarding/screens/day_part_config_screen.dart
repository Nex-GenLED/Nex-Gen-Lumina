import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/models/commercial/business_hours.dart';
import 'package:nexgen_command/models/commercial/day_part.dart';
import 'package:nexgen_command/models/commercial/day_part_template.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';

/// Predefined colors for day-part blocks on the timeline.
const _kBlockColors = [
  Color(0xFF2196F3),
  Color(0xFF4CAF50),
  Color(0xFFFFC107),
  Color(0xFFFF5722),
  Color(0xFF9C27B0),
  Color(0xFF00BCD4),
  Color(0xFFE91E63),
  Color(0xFF607D8B),
];

class DayPartConfigScreen extends ConsumerStatefulWidget {
  const DayPartConfigScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  ConsumerState<DayPartConfigScreen> createState() => _DayPartConfigScreenState();
}

class _DayPartConfigScreenState extends ConsumerState<DayPartConfigScreen> {
  int _selectedDayIndex = 0; // 0=Mon
  int? _tappedBlockIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generateIfNeeded());
  }

  void _generateIfNeeded() {
    final draft = ref.read(commercialOnboardingProvider);
    if (draft.dayParts.isNotEmpty) return;

    final hours = BusinessHours(
      weeklySchedule: draft.weeklySchedule,
      preOpenBufferMinutes: draft.preOpenBufferMinutes,
      postCloseWindDownMinutes: draft.postCloseWindDownMinutes,
    );

    final parts = DayPartTemplate.forBusinessType(draft.businessType, hours);
    ref.read(commercialOnboardingProvider.notifier).update(
          (d) => d.copyWith(dayParts: parts),
        );
  }

  void _updatePart(int index, DayPart updated) {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final list = List<DayPart>.from(d.dayParts);
      list[index] = updated;
      return d.copyWith(dayParts: list);
    });
  }

  void _removePart(int index) {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final list = List<DayPart>.from(d.dayParts)..removeAt(index);
      return d.copyWith(dayParts: list);
    });
    setState(() => _tappedBlockIndex = null);
  }

  void _addCustomPart() {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final newPart = DayPart(
        id: 'dp_custom_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Custom Period',
        startTime: const TimeOfDay(hour: 12, minute: 0),
        endTime: const TimeOfDay(hour: 14, minute: 0),
        daysOfWeek: DayOfWeek.values,
      );
      return d.copyWith(dayParts: [...d.dayParts, newPart]);
    });
  }

  void _showEditSheet(int index, DayPart part) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _DayPartEditSheet(
        part: part,
        onSave: (updated) {
          Navigator.pop(ctx);
          _updatePart(index, updated);
        },
        onRemove: () {
          Navigator.pop(ctx);
          _removePart(index);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(commercialOnboardingProvider);
    final parts = draft.dayParts;
    final selectedDay = DayOfWeek.values[_selectedDayIndex];

    // Filter parts active on selected day.
    final dayParts = parts.where((p) {
      if (p.daysOfWeek.isEmpty) return true;
      return p.daysOfWeek.contains(selectedDay);
    }).toList();

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            Text('Day-Part Schedule',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: NexGenPalette.textHigh)),
            const SizedBox(height: 12),

            // Day selector
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: DayOfWeek.values.length,
                itemBuilder: (_, i) {
                  final isActive = i == _selectedDayIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(DayOfWeek.values[i].shortName),
                      selected: isActive,
                      selectedColor: NexGenPalette.cyan.withValues(alpha: 0.15),
                      backgroundColor: NexGenPalette.gunmetal,
                      labelStyle: TextStyle(
                        color: isActive ? NexGenPalette.cyan : NexGenPalette.textMedium,
                        fontSize: 13),
                      side: BorderSide(
                        color: isActive ? NexGenPalette.cyan : NexGenPalette.line),
                      onSelected: (_) => setState(() {
                        _selectedDayIndex = i;
                        _tappedBlockIndex = null;
                      }),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Timeline
            SizedBox(
              height: 70,
              child: dayParts.isEmpty
                  ? Center(
                      child: Text('No day-parts for ${selectedDay.displayName}',
                          style: const TextStyle(color: NexGenPalette.textMedium)))
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: dayParts.length,
                      itemBuilder: (_, i) {
                        final p = dayParts[i];
                        final origIndex = parts.indexOf(p);
                        final color = _kBlockColors[i % _kBlockColors.length];
                        final isTapped = _tappedBlockIndex == origIndex;
                        return GestureDetector(
                          onTap: () {
                            setState(() => _tappedBlockIndex =
                                isTapped ? null : origIndex);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 120,
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: isTapped ? 0.3 : 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isTapped ? color : color.withValues(alpha: 0.3),
                                width: isTapped ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(p.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: NexGenPalette.textHigh,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                if (isTapped) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_fmt(p.startTime)} – ${_fmt(p.endTime)}',
                                    style: TextStyle(
                                        color: color, fontSize: 10),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Tapped block details
            if (_tappedBlockIndex != null &&
                _tappedBlockIndex! < parts.length) ...[
              const SizedBox(height: 12),
              _DayPartDetail(
                part: parts[_tappedBlockIndex!],
                onEdit: () =>
                    _showEditSheet(_tappedBlockIndex!, parts[_tappedBlockIndex!]),
                onToggleBrandColors: (v) => _updatePart(
                  _tappedBlockIndex!,
                  parts[_tappedBlockIndex!].copyWith(useBrandColors: v),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Day-part list view
            ...parts.asMap().entries.map((e) {
              final color = _kBlockColors[e.key % _kBlockColors.length];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 8, height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                title: Text(e.value.name,
                    style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 14)),
                subtitle: Text(
                  '${_fmt(e.value.startTime)} – ${_fmt(e.value.endTime)}',
                  style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
                trailing: Text(
                  e.value.assignedDesignId ?? 'Default Ambient',
                  style: TextStyle(
                    color: e.value.assignedDesignId != null
                        ? NexGenPalette.cyan
                        : NexGenPalette.textMedium,
                    fontSize: 12),
                ),
                onTap: () => _showEditSheet(e.key, e.value),
              );
            }),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: widget.onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Next', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),

        // FAB
        Positioned(
          right: 20,
          bottom: 70,
          child: FloatingActionButton.small(
            backgroundColor: NexGenPalette.cyan,
            foregroundColor: Colors.black,
            onPressed: _addCustomPart,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Day-part detail card (shown when a block is tapped)
// ---------------------------------------------------------------------------

class _DayPartDetail extends StatelessWidget {
  const _DayPartDetail({
    required this.part,
    required this.onEdit,
    required this.onToggleBrandColors,
  });
  final DayPart part;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggleBrandColors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(part.name,
                    style: const TextStyle(
                        color: NexGenPalette.textHigh,
                        fontWeight: FontWeight.w600)),
              ),
              TextButton(onPressed: onEdit, child: const Text('Edit')),
            ],
          ),
          Text(
            'Design: ${part.assignedDesignId ?? 'Default Ambient'}',
            style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Use brand colors',
                  style: TextStyle(color: NexGenPalette.textHigh, fontSize: 13)),
              const Spacer(),
              Switch(
                value: part.useBrandColors,
                activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.4),
                thumbColor: const WidgetStatePropertyAll(NexGenPalette.cyan),
                onChanged: onToggleBrandColors,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit bottom sheet
// ---------------------------------------------------------------------------

class _DayPartEditSheet extends StatefulWidget {
  const _DayPartEditSheet({
    required this.part,
    required this.onSave,
    required this.onRemove,
  });
  final DayPart part;
  final ValueChanged<DayPart> onSave;
  final VoidCallback onRemove;

  @override
  State<_DayPartEditSheet> createState() => _DayPartEditSheetState();
}

class _DayPartEditSheetState extends State<_DayPartEditSheet> {
  late final TextEditingController _nameCtrl;
  late TimeOfDay _start;
  late TimeOfDay _end;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.part.name);
    _start = widget.part.startTime;
    _end = widget.part.endTime;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42, height: 4,
                decoration: BoxDecoration(
                  color: NexGenPalette.textMedium.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 16),
              decoration: const InputDecoration(
                labelText: 'Day-Part Name',
                labelStyle: TextStyle(color: NexGenPalette.textMedium),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _TimeChip(label: 'Start', time: _start, onTap: () async {
                  final t = await showTimePicker(
                      context: context, initialTime: _start);
                  if (t != null) setState(() => _start = t);
                }),
                const SizedBox(width: 12),
                _TimeChip(label: 'End', time: _end, onTap: () async {
                  final t = await showTimePicker(
                      context: context, initialTime: _end);
                  if (t != null) setState(() => _end = t);
                }),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onRemove,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                    ),
                    child: const Text('Remove'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => widget.onSave(widget.part.copyWith(
                      name: _nameCtrl.text.trim(),
                      startTime: _start,
                      endTime: _end,
                    )),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.time, required this.onTap});
  final String label;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: NexGenPalette.matteBlack,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Row(
            children: [
              Text(label,
                  style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
              const Spacer(),
              Text(
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                    color: NexGenPalette.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
