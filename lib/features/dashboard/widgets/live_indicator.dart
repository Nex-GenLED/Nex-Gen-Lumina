import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// Animated "ON" indicator with pulsing dot
class LiveIndicator extends StatefulWidget {
  const LiveIndicator({super.key});

  @override
  State<LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<LiveIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ScaleTransition(
        scale: _scale,
        child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: NexGenPalette.cyan, shape: BoxShape.circle)),
      ),
      const SizedBox(width: 6),
      Text('ON', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: NexGenPalette.cyan)),
    ]);
  }
}
