import 'package:flutter/material.dart';
import 'package:nexgen_command/app_colors.dart';

enum AmbassadorTier { bronze, silver, gold, platinum }

extension AmbassadorTierX on AmbassadorTier {
  String get label => const ['Bronze', 'Silver', 'Gold', 'Platinum'][index];

  /// Cumulative installs required to reach this tier.
  int get threshold => const [0, 3, 8, 15][index];

  /// Installs required to reach the next tier, or null if platinum.
  int? get nextThreshold =>
      index < AmbassadorTier.values.length - 1
          ? AmbassadorTier.values[index + 1].threshold
          : null;

  Color get color {
    switch (this) {
      case AmbassadorTier.bronze:
        return NexGenPalette.amber;
      case AmbassadorTier.silver:
        return NexGenPalette.textMedium;
      case AmbassadorTier.gold:
        return NexGenPalette.gold;
      case AmbassadorTier.platinum:
        return NexGenPalette.cyan;
    }
  }

  /// Returns the highest tier whose threshold is <= [count].
  static AmbassadorTier fromInstallCount(int count) {
    var result = AmbassadorTier.bronze;
    for (final tier in AmbassadorTier.values) {
      if (count >= tier.threshold) {
        result = tier;
      } else {
        break;
      }
    }
    return result;
  }
}
