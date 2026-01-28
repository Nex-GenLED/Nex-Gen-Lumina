import 'package:flutter/material.dart';

/// Larger nav item for Simple Mode (easier to tap)
class SimpleNavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color selected;
  final Color unselected;
  final VoidCallback onTap;

  const SimpleNavItem({
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: active ? selected.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? selected : unselected,
              size: 32,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? selected : unselected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
