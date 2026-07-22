import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/navigation/dock_item.dart';
import 'package:nexgen_command/widgets/navigation/lumina_nav_button.dart';

/// Glassmorphic bottom navigation dock with 5 items.
/// The center Lumina button opens a voice assistant bottom sheet
/// instead of navigating to a dedicated tab.
class GlassDockNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback? onLuminaTap;
  final VoidCallback? onLuminaLongPress;
  final bool isVoiceListening;
  final bool hasActiveSession;

  const GlassDockNavBar({
    super.key,
    required this.index,
    required this.onTap,
    this.onLuminaTap,
    this.onLuminaLongPress,
    this.isVoiceListening = false,
    this.hasActiveSession = false,
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
          padding: EdgeInsets.fromLTRB(14, 8, 14, 8 + bottomInset),
          decoration: const BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              LuminaNavButton(
                onTap: () => onLuminaTap?.call(),
                onLongPress: onLuminaLongPress,
                isListening: isVoiceListening,
                hasActiveSession: hasActiveSession,
              ),
              DockItem(
                label: 'Explore',
                icon: Icons.explore_rounded,
                active: index == 2,
                selected: selected,
                unselected: unselected,
                onTap: () => onTap(2),
              ),
              DockItem(
                label: 'System',
                icon: Icons.tune_rounded,
                active: index == 3,
                selected: selected,
                unselected: unselected,
                onTap: () => onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
