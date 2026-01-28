import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// Visual weekly bar chart showing schedule intensity for each day
class WeeklyScheduleOverview extends StatelessWidget {
  /// 7 entries for Sunday..Saturday, values 0..1 representing schedule "intensity"
  final List<double> values;

  const WeeklyScheduleOverview({super.key, required this.values});

  @override
  Widget build(BuildContext context) {
    final letters = const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final todayIndex = DateTime.now().weekday % 7; // Sun=0
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(7, (i) {
      final v = values[i].clamp(0.0, 1.0);
      final isToday = i == todayIndex;
      return Column(children: [
        Container(
          width: 12,
          height: 60,
          decoration: BoxDecoration(color: NexGenPalette.gunmetal50, borderRadius: BorderRadius.circular(6)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 12,
              height: 60 * v,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [NexGenPalette.cyan, NexGenPalette.blue]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          letters[i],
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: isToday ? NexGenPalette.cyan : Colors.white, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500),
        )
      ]);
    }));
  }
}
