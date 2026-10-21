import 'package:flutter/material.dart';

/// Individual dock item for the bottom navigation bar
class DockItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color selected;
  final Color unselected;
  final VoidCallback onTap;

  const DockItem({
    super.key,
    required this.label,
    required this.icon,
    required this.active,
    required this.selected,
    required this.unselected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? selected : unselected;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            // +120 large-text slice: the dock is a fixed-height strip, so its
            // labels scale to 1.3x and stay on one line ("Sche/dule" wrapped
            // at 320 pt and 2.0x); the app-wide 2.0 clamp is untouched.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10, color: color)),
            ),
          ]),
        ),
      ),
    );
  }
}
