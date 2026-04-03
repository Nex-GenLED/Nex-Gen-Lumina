import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../../widgets/glass_app_bar.dart';
import '../../widgets/section_header.dart';
import '../autopilot/game_day_autopilot_config.dart';
import '../autopilot/game_day_autopilot_providers.dart';
import '../sports_alerts/data/team_colors.dart';
import '../sports_alerts/models/game_state.dart';
import '../sports_alerts/models/sport_type.dart';
import 'game_day_crew_models.dart';
import 'game_day_providers.dart';

// ---------------------------------------------------------------------------
// Sport emoji helper
// ---------------------------------------------------------------------------

String _sportEmoji(SportType sport) => switch (sport) {
      SportType.nfl || SportType.ncaaFB => '\u{1F3C8}',
      SportType.nba || SportType.ncaaMB => '\u{1F3C0}',
      SportType.mlb => '\u26BE',
      SportType.nhl => '\u{1F3D2}',
      SportType.mls || SportType.fifa || SportType.championsLeague => '\u26BD',
    };

// ===========================================================================
// Game Day Screen
// ===========================================================================

class GameDayScreen extends ConsumerWidget {
  const GameDayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamEntries = ref.watch(gameDayTeamsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── App bar ──
          SliverPersistentHeader(
            pinned: true,
            delegate: _GlassAppBarDelegate(
              child: GlassAppBar(
                title: const Text('Game Day'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => context.pop(),
                ),
              ),
            ),
          ),

          // ── Body ──
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Hero description
                _buildHeroCard(context),
                const SizedBox(height: 20),

                // My Teams section
                if (teamEntries.isNotEmpty) ...[
                  const SectionHeader(
                    title: 'My Teams',
                    icon: Icons.sports,
                  ),
                  const SizedBox(height: 8),
                  ...teamEntries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TeamCard(entry: entry),
                      )),
                ],

                // Add a team button
                const SizedBox(height: 8),
                _AddTeamButton(existingTeamSlugs:
                    teamEntries.map((e) => e.config.teamSlug).toSet()),
                const SizedBox(height: 24),

                // Join a crew section
                const SectionHeader(
                  title: 'Join a Crew',
                  icon: Icons.group_add_rounded,
                ),
                const SizedBox(height: 8),
                _JoinCrewCard(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            NexGenPalette.gunmetal90.withValues(alpha: 0.8),
            NexGenPalette.matteBlack.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: NexGenPalette.cyan.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.stadium_rounded,
                  color: NexGenPalette.cyan, size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Game Day',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: NexGenPalette.textHigh,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Set up your teams, choose a design, and let your lights '
            'automatically come alive on game day. Turn on live scoring '
            'to celebrate every point, or keep it simple with a static '
            'team design.',
            style: TextStyle(
              fontSize: 14,
              color: NexGenPalette.textMedium,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Team Card — shows one team's full Game Day config
// ===========================================================================

class _TeamCard extends ConsumerWidget {
  final GameDayTeamEntry entry;

  const _TeamCard({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = entry.config;
    final crew = entry.crew;
    final gameAsync = ref.watch(upcomingGameProvider(config.teamSlug));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            NexGenPalette.gunmetal90.withValues(alpha: 0.8),
            NexGenPalette.matteBlack.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Color(config.primaryColorValue).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Team header with color accent ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(config.primaryColorValue).withValues(alpha: 0.2),
                  Colors.transparent,
                ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                // Team color dots
                _TeamColorDots(
                  primary: Color(config.primaryColorValue),
                  secondary: Color(config.secondaryColorValue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_sportEmoji(config.sport)} ${config.teamName}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: NexGenPalette.textHigh,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        config.sport.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          color: NexGenPalette.textMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                // Live game indicator
                gameAsync.when(
                  data: (game) => game != null
                      ? _GameStatusBadge(game: game)
                      : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // ── Config section ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              children: [
                // Design row
                _ConfigRow(
                  icon: Icons.palette_outlined,
                  label: 'Design',
                  value: config.designLabel,
                  onTap: entry.isCrewMember
                      ? null
                      : () => _openDesignPicker(context, ref, config),
                ),
                const Divider(
                    height: 24, color: NexGenPalette.line),

                // Live Scoring toggle
                _ToggleRow(
                  icon: Icons.celebration_outlined,
                  label: 'Live Scoring',
                  value: entry.isCrewMember
                      ? (crew?.liveScoring ?? false)
                      : config.scoreCelebrationEnabled,
                  enabled: !entry.isCrewMember,
                  onChanged: entry.isCrewMember
                      ? null
                      : (val) => _toggleLiveScoring(ref, config, val),
                ),
                const Divider(
                    height: 24, color: NexGenPalette.line),

                // Autopilot toggle
                _ToggleRow(
                  icon: Icons.auto_mode_rounded,
                  label: 'Autopilot',
                  value: config.enabled,
                  enabled: !entry.isCrewMember,
                  onChanged: entry.isCrewMember
                      ? null
                      : (val) => _toggleAutopilot(ref, config, val),
                ),
              ],
            ),
          ),

          // ── Crew section ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal.withValues(alpha: 0.5),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(15)),
            ),
            child: crew != null
                ? _CrewStatusSection(crew: crew, isHost: entry.isHost)
                : _CreateCrewButton(config: config),
          ),
        ],
      ),
    );
  }

  void _openDesignPicker(
      BuildContext context, WidgetRef ref, GameDayAutopilotConfig config) {
    // Navigate to explore with the team's category pre-selected.
    // The team slug maps to a library node in the sports hierarchy.
    final nodeId = 'team_${config.teamSlug}';
    context.push('/explore/library/$nodeId');
  }

  void _toggleLiveScoring(
      WidgetRef ref, GameDayAutopilotConfig config, bool value) {
    ref.read(gameDayAutopilotNotifierProvider.notifier).toggleAutopilot(
      teamSlug: config.teamSlug,
      enabled: config.enabled,
    );
    // Update the score celebration field specifically.
    ref.read(gameDayAutopilotNotifierProvider.notifier).saveDesign(
      teamSlug: config.teamSlug,
      designName: config.savedDesignName ?? config.designLabel,
      wledPayload: config.savedDesignPayload ?? {},
      effectId: config.effectId,
      speed: config.speed,
      intensity: config.intensity,
      brightness: config.brightness,
    );
  }

  void _toggleAutopilot(
      WidgetRef ref, GameDayAutopilotConfig config, bool value) {
    ref.read(gameDayAutopilotNotifierProvider.notifier).toggleAutopilot(
          teamSlug: config.teamSlug,
          enabled: value,
        );
  }
}

// ===========================================================================
// Sub-widgets
// ===========================================================================

class _TeamColorDots extends StatelessWidget {
  final Color primary;
  final Color secondary;

  const _TeamColorDots({required this.primary, required this.secondary});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: primary,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3)),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: secondary,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GameStatusBadge extends StatelessWidget {
  final GameState game;

  const _GameStatusBadge({required this.game});

  @override
  Widget build(BuildContext context) {
    final isLive =
        game.status == GameStatus.inProgress ||
        game.status == GameStatus.halftime;
    final isFinal = game.status == GameStatus.final_;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isLive
            ? Colors.green.withValues(alpha: 0.2)
            : isFinal
                ? NexGenPalette.textMedium.withValues(alpha: 0.15)
                : NexGenPalette.cyan.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLive
              ? Colors.green.withValues(alpha: 0.4)
              : isFinal
                  ? NexGenPalette.textMedium.withValues(alpha: 0.3)
                  : NexGenPalette.cyan.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            isLive
                ? '${game.homeScore} - ${game.awayScore}'
                : isFinal
                    ? 'Final ${game.homeScore}-${game.awayScore}'
                    : 'Today',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isLive
                  ? Colors.green
                  : isFinal
                      ? NexGenPalette.textMedium
                      : NexGenPalette.cyan,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _ConfigRow({
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

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    this.enabled = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: NexGenPalette.cyan),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: NexGenPalette.textMedium,
            ),
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeColor: NexGenPalette.cyan,
          inactiveThumbColor:
              NexGenPalette.textMedium.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

// ===========================================================================
// Crew section widgets
// ===========================================================================

class _CrewStatusSection extends StatelessWidget {
  final GameDayCrew crew;
  final bool isHost;

  const _CrewStatusSection({required this.crew, required this.isHost});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.groups_rounded,
                size: 18, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isHost
                    ? 'Game Day Crew \u2022 ${crew.memberCount} member${crew.memberCount == 1 ? '' : 's'}'
                    : 'In ${crew.hostDisplayName}\'s Crew',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: NexGenPalette.textHigh,
                ),
              ),
            ),
            if (isHost)
              _SmallActionButton(
                label: 'Manage',
                onTap: () => _showCrewManagement(context, crew),
              )
            else
              _SmallActionButton(
                label: 'Leave',
                color: Colors.red.withValues(alpha: 0.8),
                onTap: () => _confirmLeave(context, crew),
              ),
          ],
        ),
        if (isHost) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.link_rounded,
                  size: 14, color: NexGenPalette.textMedium),
              const SizedBox(width: 6),
              Text(
                'Invite code: ${crew.inviteCode}',
                style: TextStyle(
                  fontSize: 12,
                  color: NexGenPalette.textMedium,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: crew.inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Invite code copied!'),
                        duration: Duration(seconds: 2)),
                  );
                },
                child: Icon(Icons.copy_rounded,
                    size: 14, color: NexGenPalette.cyan),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _showCrewManagement(BuildContext context, GameDayCrew crew) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CrewManagementSheet(crew: crew),
    );
  }

  void _confirmLeave(BuildContext context, GameDayCrew crew) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: const Text('Leave Crew?'),
        content: Text(
          'You\'ll stop receiving ${crew.teamName} game day designs '
          'from this crew. Your personal Game Day setup will resume.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Leave crew via provider.
            },
            child: const Text('Leave',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _CreateCrewButton extends ConsumerWidget {
  final GameDayAutopilotConfig config;

  const _CreateCrewButton({required this.config});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => _createCrew(context, ref),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Icon(Icons.groups_rounded,
              size: 18, color: NexGenPalette.textMedium),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Share with neighbors',
              style: TextStyle(
                fontSize: 13,
                color: NexGenPalette.textMedium,
              ),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: NexGenPalette.cyan.withValues(alpha: 0.3)),
            ),
            child: const Text(
              'Create Crew',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: NexGenPalette.cyan,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createCrew(BuildContext context, WidgetRef ref) async {
    final service = ref.read(gameDayCrewServiceProvider);
    try {
      final crew = await service.createCrew(
        teamSlug: config.teamSlug,
        teamName: config.teamName,
        sport: config.sport.toJson(),
        hostDisplayName: 'My House', // TODO: pull from user profile
        espnTeamId: config.espnTeamId,
        primaryColorValue: config.primaryColorValue,
        secondaryColorValue: config.secondaryColorValue,
        designPayload: config.savedDesignPayload,
        designName: config.designLabel,
        effectId: config.effectId,
        speed: config.speed,
        intensity: config.intensity,
        brightness: config.brightness,
        liveScoring: config.scoreCelebrationEnabled,
        autopilotEnabled: config.enabled,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Crew created! Invite code: ${crew.inviteCode}'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create crew: $e')),
      );
    }
  }
}

// ===========================================================================
// Crew Management Bottom Sheet
// ===========================================================================

class _CrewManagementSheet extends ConsumerWidget {
  final GameDayCrew crew;

  const _CrewManagementSheet({required this.crew});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: NexGenPalette.textMedium.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              '${crew.sportEmoji} ${crew.teamName} Crew',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: NexGenPalette.textHigh,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${crew.memberCount} member${crew.memberCount == 1 ? '' : 's'} \u2022 Code: ${crew.inviteCode}',
              style: TextStyle(
                fontSize: 13,
                color: NexGenPalette.textMedium,
              ),
            ),
            const SizedBox(height: 20),

            // Live scoring toggle (host control)
            _ToggleRow(
              icon: Icons.celebration_outlined,
              label: 'Live Scoring (all members)',
              value: crew.liveScoring,
              onChanged: (val) {
                ref.read(gameDayCrewServiceProvider).setLiveScoring(
                    crew.id, val);
              },
            ),
            const Divider(height: 24, color: NexGenPalette.line),

            // Autopilot toggle (host control)
            _ToggleRow(
              icon: Icons.auto_mode_rounded,
              label: 'Autopilot (all members)',
              value: crew.autopilotEnabled,
              onChanged: (val) {
                ref.read(gameDayCrewServiceProvider).setAutopilot(
                    crew.id, val);
              },
            ),
            const Divider(height: 24, color: NexGenPalette.line),

            // Copy invite code
            ListTile(
              leading: const Icon(Icons.share_rounded,
                  color: NexGenPalette.cyan),
              title: const Text('Share Invite Code'),
              trailing: Text(crew.inviteCode,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      color: NexGenPalette.textHigh)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: crew.inviteCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite code copied!')),
                );
              },
            ),

            // Regenerate invite code
            ListTile(
              leading: const Icon(Icons.refresh_rounded,
                  color: NexGenPalette.textMedium),
              title: const Text('Regenerate Invite Code'),
              onTap: () async {
                final newCode = await ref
                    .read(gameDayCrewServiceProvider)
                    .regenerateInviteCode(crew.id);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('New code: $newCode')),
                );
                Navigator.pop(context);
              },
            ),

            // Dissolve crew
            ListTile(
              leading:
                  Icon(Icons.delete_outline, color: Colors.red.shade300),
              title: Text('Dissolve Crew',
                  style: TextStyle(color: Colors.red.shade300)),
              onTap: () => _confirmDissolve(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDissolve(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: const Text('Dissolve Crew?'),
        content: Text(
          'All ${crew.memberCount} member${crew.memberCount == 1 ? '' : 's'} '
          'will be removed and the crew will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx); // Close dialog
              Navigator.pop(context); // Close bottom sheet
              await ref
                  .read(gameDayCrewServiceProvider)
                  .dissolveCrew(crew.id);
            },
            child: const Text('Dissolve',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Add Team button
// ===========================================================================

class _AddTeamButton extends ConsumerWidget {
  final Set<String> existingTeamSlugs;

  const _AddTeamButton({required this.existingTeamSlugs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => _showTeamPicker(context, ref),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: NexGenPalette.cyan.withValues(alpha: 0.2),
            style: BorderStyle.solid,
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 20, color: NexGenPalette.cyan),
            SizedBox(width: 8),
            Text(
              'Add a Team',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: NexGenPalette.cyan,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTeamPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => _TeamPickerSheet(
          scrollController: scrollController,
          existingTeamSlugs: existingTeamSlugs,
        ),
      ),
    );
  }
}

// ===========================================================================
// Team Picker Bottom Sheet
// ===========================================================================

class _TeamPickerSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final Set<String> existingTeamSlugs;

  const _TeamPickerSheet({
    required this.scrollController,
    required this.existingTeamSlugs,
  });

  @override
  ConsumerState<_TeamPickerSheet> createState() => _TeamPickerSheetState();
}

class _TeamPickerSheetState extends ConsumerState<_TeamPickerSheet> {
  final _searchController = TextEditingController();
  SportType? _sportFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameDayTeamSearchProvider.notifier).state = '';
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var teams = ref.watch(gameDayFilteredTeamsProvider);
    if (_sportFilter != null) {
      teams = teams.where((e) => e.value.sport == _sportFilter).toList();
    }

    return Column(
      children: [
        // Handle bar
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: NexGenPalette.textMedium.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Choose a Team',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: NexGenPalette.textHigh,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            onChanged: (v) =>
                ref.read(gameDayTeamSearchProvider.notifier).state = v,
            decoration: InputDecoration(
              hintText: 'Search teams...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(gameDayTeamSearchProvider.notifier).state =
                            '';
                      },
                    )
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Sport filter chips
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChip(
                label: 'All',
                selected: _sportFilter == null,
                onTap: () => setState(() => _sportFilter = null),
              ),
              for (final sport in SportType.values)
                _FilterChip(
                  label: sport.displayName,
                  selected: _sportFilter == sport,
                  onTap: () => setState(() => _sportFilter = sport),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Team list
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            itemCount: teams.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              final entry = teams[index];
              final slug = entry.key;
              final team = entry.value;
              final alreadyAdded = widget.existingTeamSlugs.contains(slug);

              return ListTile(
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: team.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: team.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                title: Text(
                  team.teamName,
                  style: TextStyle(
                    color: alreadyAdded
                        ? NexGenPalette.textMedium
                        : NexGenPalette.textHigh,
                  ),
                ),
                subtitle: Text(
                  team.sport.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    color: NexGenPalette.textMedium,
                  ),
                ),
                trailing: alreadyAdded
                    ? Icon(Icons.check_circle,
                        color: NexGenPalette.green, size: 20)
                    : Icon(Icons.add_circle_outline,
                        color: NexGenPalette.cyan, size: 20),
                onTap: alreadyAdded
                    ? null
                    : () => _addTeam(context, ref, slug, team),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addTeam(BuildContext context, WidgetRef ref, String slug,
      TeamColors team) async {
    // Create a GameDayAutopilotConfig for this team with defaults.
    await ref.read(gameDayAutopilotNotifierProvider.notifier).toggleAutopilot(teamSlug: slug, enabled: true);

    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${team.teamName} added to Game Day!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ===========================================================================
// Join Crew Card
// ===========================================================================

class _JoinCrewCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_JoinCrewCard> createState() => _JoinCrewCardState();
}

class _JoinCrewCardState extends ConsumerState<_JoinCrewCard> {
  final _codeController = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Have an invite code from a neighbor?',
            style: TextStyle(
              fontSize: 14,
              color: NexGenPalette.textMedium,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  decoration: InputDecoration(
                    hintText: 'Enter code',
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _joining ? null : _joinCrew,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: NexGenPalette.matteBlack,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _joining
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Join',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _joinCrew() async {
    final code = _codeController.text.trim();
    if (code.length < 6) return;

    setState(() => _joining = true);

    try {
      final service = ref.read(gameDayCrewServiceProvider);
      final crew = await service.joinCrew(code);

      if (!mounted) return;
      setState(() => _joining = false);

      if (crew != null) {
        _codeController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Joined ${crew.teamName} crew hosted by ${crew.hostDisplayName}!'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid invite code.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _joining = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error joining crew: $e')),
      );
    }
  }
}

// ===========================================================================
// Filter chip
// ===========================================================================

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? NexGenPalette.cyan.withValues(alpha: 0.2)
                : NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? NexGenPalette.cyan.withValues(alpha: 0.5)
                  : NexGenPalette.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? NexGenPalette.cyan
                  : NexGenPalette.textMedium,
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Small action button
// ===========================================================================

class _SmallActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _SmallActionButton({
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? NexGenPalette.cyan;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c,
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Glass app bar delegate (same pattern as SportsAlertsScreen)
// ===========================================================================

class _GlassAppBarDelegate extends SliverPersistentHeaderDelegate {
  final GlassAppBar child;

  _GlassAppBarDelegate({required this.child});

  @override
  double get minExtent => child.preferredSize.height;

  @override
  double get maxExtent => child.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _GlassAppBarDelegate oldDelegate) => false;
}
