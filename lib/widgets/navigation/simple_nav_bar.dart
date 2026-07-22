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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final selected = NexGenPalette.cyan;
    const unselected = Color(0xFF808080);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 12 + bottomInset),
          decoration: const BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
    );
  }
}
