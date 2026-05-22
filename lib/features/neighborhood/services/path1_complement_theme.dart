// lib/features/neighborhood/services/path1_complement_theme.dart
//
// Convergence-Phase-2b: replaces [GameDaySyncConfig.toComplementTheme]
// with a pure converter that derives a [ComplementTheme] from a
// [Path1GameDaySnapshot].
//
// Path 2 (Sync→Complement→Game Day) needs a [ComplementTheme] to feed
// the neighborhood-sync engine's createComplementCommand. The previous
// shape went GameDaySyncConfig → ComplementTheme; Phase 2b's reader
// flow goes Path1GameDaySnapshot → ComplementTheme (one fewer hop).

import 'package:flutter/material.dart';

import '../../sports_alerts/models/sport_type.dart';
import '../neighborhood_models.dart';
import 'path1_game_day_snapshot.dart';

/// Build a [ComplementTheme] from a [Path1GameDaySnapshot]. Field
/// derivation matches the legacy [GameDaySyncConfig.toComplementTheme]
/// contract exactly so the Path 2 swap is behaviorally identical.
ComplementTheme path1ToComplementTheme(Path1GameDaySnapshot snap) {
  return ComplementTheme(
    id: 'gameday_${snap.teamSlug}',
    name: 'Game Day - ${snap.teamName}',
    description: '${snap.sport.displayName} team colors',
    icon: _sportIcon(snap.sport),
    themeColors: [
      snap.primaryColorValue & 0xFFFFFF,
      snap.secondaryColorValue & 0xFFFFFF,
    ],
    recommendedEffectId: snap.effectId,
  );
}

IconData _sportIcon(SportType sport) => switch (sport) {
      SportType.nfl || SportType.ncaaFB => Icons.sports_football,
      SportType.nba || SportType.wnba || SportType.ncaaMB =>
        Icons.sports_basketball,
      SportType.mlb => Icons.sports_baseball,
      SportType.nhl => Icons.sports_hockey,
      SportType.mls ||
      SportType.nwsl ||
      SportType.fifa ||
      SportType.championsLeague =>
        Icons.sports_soccer,
    };
