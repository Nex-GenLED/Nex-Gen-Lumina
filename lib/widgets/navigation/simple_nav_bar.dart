import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/navigation/simple_nav_item.dart';

/// Simplified 2-tab navigation bar for Simple Mode
class SimpleNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const SimpleNavBar({
    super.key,
    required this.index,
    required this.onTap,
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                SimpleNavItem(
                  label: 'Home',
                  icon: Icons.home_filled,
                  active: index == 0,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(0),
                ),
                SimpleNavItem(
                  label: 'Settings',
                  icon: Icons.settings_rounded,
                  active: index == 1,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
