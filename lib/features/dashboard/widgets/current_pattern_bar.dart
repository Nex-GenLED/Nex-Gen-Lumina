import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/dashboard/widgets/live_indicator.dart';

/// Bar displaying the currently active pattern name
class CurrentPatternBar extends ConsumerWidget {
  const CurrentPatternBar({super.key});

  String _labelFromAction(String actionLabel) {
    final a = actionLabel.trim();
    if (a.toLowerCase().startsWith('pattern')) {
      final idx = a.indexOf(':');
      return idx != -1 && idx + 1 < a.length ? a.substring(idx + 1).trim() : a;
    }
    return a;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wledStateProvider);
    final schedules = ref.watch(schedulesProvider);
    final activePreset = ref.watch(activePresetLabelProvider);

    String valueText;
    if (!state.connected) {
      valueText = 'System Offline';
    } else if (activePreset != null) {
      // If user manually selected a preset, show that
      valueText = activePreset;
    } else {
      // Try to infer from today's first schedule item
      final now = DateTime.now();
      final weekdayIndex0Sun = now.weekday % 7; // Sun=0..Sat=6
      List<String> keys;
      switch (weekdayIndex0Sun) {
        case 0:
          keys = const ['sun', 'sunday'];
          break;
        case 1:
          keys = const ['mon', 'monday'];
          break;
        case 2:
          keys = const ['tue', 'tues', 'tuesday'];
          break;
        case 3:
          keys = const ['wed', 'wednesday'];
          break;
        case 4:
          keys = const ['thu', 'thurs', 'thursday'];
          break;
        case 5:
          keys = const ['fri', 'friday'];
          break;
        case 6:
        default:
          keys = const ['sat', 'saturday'];
      }
      final dayItems = schedules.where((s) {
        if (!s.enabled) return false;
        final dl = s.repeatDays.map((e) => e.toLowerCase());
        return dl.contains('daily') || dl.any(keys.contains);
      }).toList(growable: false);

      if (dayItems.isNotEmpty) {
        valueText = _labelFromAction(dayItems.first.actionLabel);
      } else if (state.supportsRgbw && state.warmWhite > 0) {
        valueText = 'Warm White';
      } else {
        valueText = 'Active Pattern';
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(children: [
        Icon(Icons.palette, color: state.color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('ACTIVE PATTERN', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 2),
            Text(valueText, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
        ),
        if (state.connected && state.isOn) const LiveIndicator(),
      ]),
    );
  }
}
