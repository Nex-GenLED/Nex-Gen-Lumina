import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/navigation/dock_item.dart';
import 'package:nexgen_command/widgets/navigation/dock_center.dart';

/// Glassmorphic bottom navigation dock with 5 items
/// Supports long-press on the center Lumina button for voice input
class GlassDockNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback? onLuminaLongPress;
  final bool isVoiceListening;

  const GlassDockNavBar({
    super.key,
    required this.index,
    required this.onTap,
    this.onLuminaLongPress,
    this.isVoiceListening = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = NexGenPalette.cyan;
    const unselected = Color(0xFF808080);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                DockItem(
                  label: 'Home',
                  icon: Icons.home_filled,
                  active: index == 0,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(0),
                ),
                DockItem(
                  label: 'Schedule',
                  icon: Icons.schedule_rounded,
                  active: index == 1,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(1),
                ),
                DockCenter(
                  active: index == 2,
                  selected: selected,
                  onTap: () => onTap(2),
                  onLongPress: onLuminaLongPress,
                  isListening: isVoiceListening,
                ),
                DockItem(
                  label: 'Explore',
                  icon: Icons.explore_rounded,
                  active: index == 3,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(3),
                ),
                DockItem(
                  label: 'System',
                  icon: Icons.tune_rounded,
                  active: index == 4,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
