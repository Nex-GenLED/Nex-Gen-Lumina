import 'package:flutter/material.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/theme.dart';

/// Night timeline bar with active fill color/gradient based on pattern and centered label.
/// Public reusable widget used on both My Schedule page and Home landing.
class NightTrackBar extends StatelessWidget {
  final String label;
  final List<ScheduleItem> items;
  const NightTrackBar({super.key, required this.label, required this.items});

  String _patternNameFromItems() {
    if (items.isEmpty) return '';
    final a = items.first.actionLabel.trim();
    if (a.toLowerCase().startsWith('pattern')) {
      final idx = a.indexOf(':');
      return idx != -1 && idx + 1 < a.length ? a.substring(idx + 1).trim() : a;
    }
    return '';
  }

  Color _idealTextOn(Color bg) => bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;

  _PatternStyle _styleForPattern(BuildContext context, String name) {
    final lower = name.toLowerCase();
    if (lower.contains('candy') || lower.contains('cane')) {
      return const _PatternStyle(
        gradient: LinearGradient(colors: [Colors.red, Colors.white, Colors.red, Colors.white, Colors.red], stops: [0.0, 0.25, 0.5, 0.75, 1.0]),
        textColor: Colors.white,
      );
    }
    if (lower.contains('chiefs')) {
      return const _PatternStyle(gradient: LinearGradient(colors: [Colors.red, Colors.amber]), textColor: Colors.white);
    }
    if (lower.contains('warm white') || lower.contains('warm')) {
      final c = Colors.amber;
      return _PatternStyle(color: c, textColor: _idealTextOn(c));
    }
    if (lower.contains('holiday')) {
      return const _PatternStyle(gradient: LinearGradient(colors: [Colors.red, Colors.green]), textColor: Colors.white);
    }
    if (lower.contains('off')) {
      return const _PatternStyle(color: NexGenPalette.trackDark, textColor: NexGenPalette.textHigh);
    }
    // Default to app accent gradient
    return _PatternStyle(gradient: LinearGradient(colors: [NexGenPalette.violet, NexGenPalette.cyan]), textColor: Colors.white);
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = items.isNotEmpty;
    final patternName = _patternNameFromItems();
    final style = hasItems && patternName.isNotEmpty
        ? _styleForPattern(context, patternName)
        : const _PatternStyle(color: NexGenPalette.trackDark, textColor: NexGenPalette.textHigh);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        decoration: BoxDecoration(color: NexGenPalette.trackDark, border: Border.all(color: NexGenPalette.line), borderRadius: BorderRadius.circular(14)),
        child: Stack(children: [
          // Midnight grid line at 50%
          Align(alignment: Alignment.center, child: Container(width: 1, color: NexGenPalette.textMedium.withValues(alpha: 0.18))),
          // Active fill (full width for now)
          if (hasItems)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: style.color, gradient: style.gradient, borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          // Centered label
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: hasItems ? style.textColor : NexGenPalette.textMedium, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PatternStyle {
  final Gradient? gradient;
  final Color? color;
  final Color textColor;
  const _PatternStyle({this.gradient, this.color, required this.textColor});
}
