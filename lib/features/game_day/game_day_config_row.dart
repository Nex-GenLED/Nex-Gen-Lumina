// lib/features/game_day/game_day_config_row.dart
//
// One labelled row of a Game Day team card (Design, Celebration, ...). Public
// so the Design row - whose value is GameDayAutopilotConfig.designLabel,
// derived from the stored plan payload - can be pumped in a widget test
// without the whole card.

import 'package:flutter/material.dart';

import '../../theme.dart';

class GameDayConfigRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const GameDayConfigRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: NexGenPalette.cyan),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: NexGenPalette.textMedium,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: NexGenPalette.textHigh,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right,
                  size: 18, color: NexGenPalette.textMedium),
            ],
          ],
        ),
      ),
    );
  }
}
