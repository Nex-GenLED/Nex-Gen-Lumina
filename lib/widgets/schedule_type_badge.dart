// lib/widgets/schedule_type_badge.dart
//
// Visual identity system for schedule cards across all scheduling surfaces.
// Provides consistent badge, accent, and background styling for every
// schedule entry type: personal autopilot, neighborhood sync, game day, etc.

import 'package:flutter/material.dart';

import '../app_colors.dart';

// ─── Schedule entry type enum ────────────────────────────────────────────────

/// The five visual identity types for schedule entries.
enum ScheduleEntryType {
  /// Personal autopilot — cyan badge, cyan accent.
  personalAutopilot,

  /// Neighborhood manual sync schedule — violet badge, violet accent.
  neighborhoodSync,

  /// Neighborhood sync running on autopilot — split violet/cyan badge.
  neighborhoodSyncAutopilot,

  /// Individual game day autopilot — team-color badge.
  gameDayAutopilot,

  /// Group game day autopilot (synced) — split violet/team-color badge.
  gameDaySyncAutopilot,
}

// ─── Visual spec helpers ─────────────────────────────────────────────────────

/// Returns the left-border accent color(s) for a given type.
/// For gradient types, returns two colors; for solid types, both are the same.
({Color start, Color end}) scheduleAccentColors(
  ScheduleEntryType type, {
  Color? teamColor,
}) {
  switch (type) {
    case ScheduleEntryType.personalAutopilot:
      return (start: NexGenPalette.cyan, end: NexGenPalette.cyan);
    case ScheduleEntryType.neighborhoodSync:
      return (start: NexGenPalette.violet, end: NexGenPalette.violet);
    case ScheduleEntryType.neighborhoodSyncAutopilot:
      return (start: NexGenPalette.violet, end: NexGenPalette.cyan);
    case ScheduleEntryType.gameDayAutopilot:
      final c = teamColor ?? NexGenPalette.amber;
      return (start: c, end: c);
    case ScheduleEntryType.gameDaySyncAutopilot:
      return (start: NexGenPalette.violet, end: teamColor ?? NexGenPalette.amber);
  }
}

/// Returns the subtle card background color/gradient for a given type.
BoxDecoration scheduleCardBackground(
  ScheduleEntryType type, {
  Color? teamColor,
}) {
  switch (type) {
    case ScheduleEntryType.personalAutopilot:
      return BoxDecoration(
        color: NexGenPalette.cyan.withValues(alpha: 0.05),
      );
    case ScheduleEntryType.neighborhoodSync:
      return BoxDecoration(
        color: NexGenPalette.violet.withValues(alpha: 0.05),
      );
    case ScheduleEntryType.neighborhoodSyncAutopilot:
      return BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NexGenPalette.violet.withValues(alpha: 0.05),
            NexGenPalette.cyan.withValues(alpha: 0.05),
          ],
        ),
      );
    case ScheduleEntryType.gameDayAutopilot:
      return BoxDecoration(
        color: (teamColor ?? NexGenPalette.amber).withValues(alpha: 0.08),
      );
    case ScheduleEntryType.gameDaySyncAutopilot:
      return BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NexGenPalette.violet.withValues(alpha: 0.06),
            (teamColor ?? NexGenPalette.amber).withValues(alpha: 0.06),
          ],
        ),
      );
  }
}

// ─── ScheduleTypeBadge ───────────────────────────────────────────────────────

/// Pill-shaped badge that visually identifies a schedule entry type.
///
/// For single-color types (personal autopilot, neighborhood sync, game day)
/// renders a solid pill. For hybrid types (sync+auto, sync+game day) renders
/// a split pill with a 1 px white divider.
class ScheduleTypeBadge extends StatelessWidget {
  final ScheduleEntryType type;

  /// Team primary color — required for [gameDayAutopilot] and
  /// [gameDaySyncAutopilot] types.
  final Color? teamColor;

  /// Sport emoji string (e.g. '🏈') — shown as the icon for game day types.
  final String? sportEmoji;

  /// Number of synced homes — shown as a trailing count for sync types.
  final int? memberCount;

  const ScheduleTypeBadge({
    super.key,
    required this.type,
    this.teamColor,
    this.sportEmoji,
    this.memberCount,
  });

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      ScheduleEntryType.personalAutopilot => _solidPill(
          label: 'AUTOPILOT',
          bg: NexGenPalette.cyan,
          fg: Colors.black,
          icon: Icons.auto_awesome,
        ),
      ScheduleEntryType.neighborhoodSync => _solidPill(
          label: 'SYNC',
          bg: NexGenPalette.violet,
          fg: Colors.white,
          icon: Icons.people_alt,
        ),
      ScheduleEntryType.neighborhoodSyncAutopilot => _splitPill(),
      ScheduleEntryType.gameDayAutopilot => _gameDayPill(),
      ScheduleEntryType.gameDaySyncAutopilot => _gameDaySyncPill(),
    };
  }

  // ── Solid pill ─────────────────────────────────────────────────────────

  Widget _solidPill({
    required String label,
    required Color bg,
    required Color fg,
    required IconData icon,
  }) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ── Split pill: SYNC · AUTO ────────────────────────────────────────────

  Widget _splitPill() {
    return Container(
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Left half — violet SYNC
          Container(
            height: 22,
            padding: const EdgeInsets.only(left: 8, right: 6),
            color: NexGenPalette.violet,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_alt, size: 12, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'SYNC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          // 1 px divider
          Container(width: 1, height: 22, color: Colors.white),
          // Right half — cyan AUTO
          Container(
            height: 22,
            padding: const EdgeInsets.only(left: 6, right: 8),
            color: NexGenPalette.cyan,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 12, color: Colors.black),
                SizedBox(width: 4),
                Text(
                  'AUTO',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Game day pill ──────────────────────────────────────────────────────

  Widget _gameDayPill() {
    final bg = teamColor ?? NexGenPalette.amber;
    final fg = _contrastFor(bg);
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sportEmoji != null) ...[
            Text(sportEmoji!, style: const TextStyle(fontSize: 11, height: 1)),
            const SizedBox(width: 4),
          ],
          Text(
            'GAME DAY',
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ── Split pill: SYNC · GAME DAY ───────────────────────────────────────

  Widget _gameDaySyncPill() {
    final bg = teamColor ?? NexGenPalette.amber;
    final fg = _contrastFor(bg);
    return Container(
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Left half — violet SYNC
          Container(
            height: 22,
            padding: const EdgeInsets.only(left: 8, right: 6),
            color: NexGenPalette.violet,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_alt, size: 12, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'SYNC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          // 1 px divider
          Container(width: 1, height: 22, color: Colors.white),
          // Right half — team color GAME DAY
          Container(
            height: 22,
            padding: const EdgeInsets.only(left: 6, right: 8),
            color: bg,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (sportEmoji != null) ...[
                  Text(sportEmoji!, style: const TextStyle(fontSize: 11, height: 1)),
                  const SizedBox(width: 4),
                ],
                Text(
                  'GAME DAY',
                  style: TextStyle(
                    color: fg,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Returns black or white depending on background luminance.
  static Color _contrastFor(Color bg) {
    return bg.computeLuminance() > 0.45 ? Colors.black : Colors.white;
  }
}

// ─── ScheduleIdentityCard ────────────────────────────────────────────────────

/// Wrapper that applies the visual identity system to any schedule card.
///
/// Provides:
/// - Left accent border (solid or gradient)
/// - Subtle tinted background
/// - Badge positioned in the top-right corner
/// - Consistent card structure: pattern name, color dots, time, extras
class ScheduleIdentityCard extends StatelessWidget {
  final ScheduleEntryType type;
  final Color? teamColor;
  final String? sportEmoji;
  final int? memberCount;

  /// Row 1 — pattern/design name.
  final String patternName;

  /// Row 2 — color preview swatches (up to 3 ARGB ints).
  final List<Color> previewColors;

  /// Row 2 — effect name shown next to color dots.
  final String? effectName;

  /// Row 3 — schedule time string (e.g. "7:00 PM → 11:00 PM").
  final String timeLabel;

  /// Row 3 — recurrence label (e.g. "Every Tuesday", "Weekly").
  final String? recurrenceLabel;

  /// Row 4 (sync types) — "X homes synced".
  /// Auto-populated from [memberCount] if provided.

  /// Row 5 (game day types) — team name.
  final String? teamName;

  /// Row 5 — timing detail (e.g. "30 min pre-game • 30 min post-game").
  final String? gameDayTiming;

  /// Optional trailing widget (toggle, buttons, etc.).
  final Widget? trailing;

  /// Called when the card is tapped.
  final VoidCallback? onTap;

  const ScheduleIdentityCard({
    super.key,
    required this.type,
    this.teamColor,
    this.sportEmoji,
    this.memberCount,
    required this.patternName,
    this.previewColors = const [],
    this.effectName,
    required this.timeLabel,
    this.recurrenceLabel,
    this.teamName,
    this.gameDayTiming,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = scheduleAccentColors(type, teamColor: teamColor);
    final bgDeco = scheduleCardBackground(type, teamColor: teamColor);
    final isGradientBorder = accent.start != accent.end;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NexGenPalette.line, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Tinted background
            Positioned.fill(
              child: Container(
                decoration: bgDeco.copyWith(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
            // Glassmorphic base
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
            // Re-apply tinted background on top of glass
            Positioned.fill(
              child: Container(
                decoration: bgDeco.copyWith(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
            // Left accent border (4 px)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(13),
                    bottomLeft: Radius.circular(13),
                  ),
                  gradient: isGradientBorder
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [accent.start, accent.end],
                        )
                      : null,
                  color: isGradientBorder ? null : accent.start,
                ),
              ),
            ),
            // Card content
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRow1(),
                  if (previewColors.isNotEmpty || effectName != null) ...[
                    const SizedBox(height: 6),
                    _buildRow2(),
                  ],
                  const SizedBox(height: 6),
                  _buildRow3(),
                  if (_showMemberCount) ...[
                    const SizedBox(height: 6),
                    _buildRow4(),
                  ],
                  if (_showGameDayInfo) ...[
                    const SizedBox(height: 6),
                    _buildRow5(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Row builders ───────────────────────────────────────────────────────

  /// Row 1: Pattern name + badge (top right).
  Widget _buildRow1() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              patternName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ScheduleTypeBadge(
          type: type,
          teamColor: teamColor,
          sportEmoji: sportEmoji,
          memberCount: memberCount,
        ),
        if (trailing != null) ...[
          const SizedBox(width: 4),
          trailing!,
        ],
      ],
    );
  }

  /// Row 2: Color dots + effect name.
  Widget _buildRow2() {
    return Row(
      children: [
        if (previewColors.isNotEmpty) ...[
          ...previewColors.take(3).map((c) => Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              )),
        ],
        if (effectName != null)
          Expanded(
            child: Text(
              effectName!,
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  /// Row 3: Time + recurrence.
  Widget _buildRow3() {
    return Row(
      children: [
        const Icon(Icons.schedule, size: 14, color: NexGenPalette.cyan),
        const SizedBox(width: 4),
        Text(
          timeLabel,
          style: const TextStyle(
            color: NexGenPalette.cyan,
            fontSize: 13,
          ),
        ),
        if (recurrenceLabel != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              recurrenceLabel!,
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  /// Row 4: Member count chip (sync types only).
  Widget _buildRow4() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: NexGenPalette.violet.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_alt, size: 12, color: NexGenPalette.violet),
              const SizedBox(width: 4),
              Text(
                '$memberCount home${memberCount == 1 ? '' : 's'} synced',
                style: const TextStyle(
                  color: NexGenPalette.violet,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Row 5: Team name + pre/post-game timing (game day types).
  Widget _buildRow5() {
    return Row(
      children: [
        if (teamName != null) ...[
          Text(
            teamName!,
            style: const TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (gameDayTiming != null) ...[
            const SizedBox(width: 8),
            Text(
              '•',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
            ),
            const SizedBox(width: 8),
          ],
        ],
        if (gameDayTiming != null)
          Expanded(
            child: Text(
              gameDayTiming!,
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  // ── Visibility helpers ─────────────────────────────────────────────────

  bool get _showMemberCount =>
      memberCount != null &&
      memberCount! > 0 &&
      (type == ScheduleEntryType.neighborhoodSync ||
          type == ScheduleEntryType.neighborhoodSyncAutopilot ||
          type == ScheduleEntryType.gameDaySyncAutopilot);

  bool get _showGameDayInfo =>
      (teamName != null || gameDayTiming != null) &&
      (type == ScheduleEntryType.gameDayAutopilot ||
          type == ScheduleEntryType.gameDaySyncAutopilot);
}
