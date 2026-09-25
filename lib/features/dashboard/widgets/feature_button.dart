// lib/features/dashboard/widgets/feature_button.dart
//
// The home dashboard's feature tile (Design Studio, Neighborhood Sync, Game
// Day, My Designs). Lived as a private class inside wled_dashboard_page.dart
// until the Game Day tile needed to be testable on its own
// (game_day_entry_button.dart).

import 'package:flutter/material.dart';

import '../../../theme.dart';

/// One tile of the dashboard's feature rows. Fills its share of the parent
/// [Row] (it returns an [Expanded]), so it must be placed directly in a Row.
class FeatureButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// When non-null, replaces the default solid background with a gradient
  /// fill. Used by the Game Day button to surface active ephemeral session
  /// state with the team's primary→secondary colors (Item #51 Prompt 4).
  final Gradient? gradient;

  const FeatureButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final hasGradient = gradient != null;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: hasGradient
                  ? null
                  : NexGenPalette.gunmetal90.withValues(alpha: 0.7),
              gradient: gradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: hasGradient
                    ? Colors.white.withValues(alpha: 0.25)
                    : NexGenPalette.cyan.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: hasGradient ? Colors.white : NexGenPalette.cyan,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: hasGradient
                          ? Colors.white
                          : NexGenPalette.textPrimary,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
