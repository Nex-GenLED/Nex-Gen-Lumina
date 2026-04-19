import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_colors.dart';
import '../../../theme.dart';
import '../../../widgets/glass_app_bar.dart';
import '../../../widgets/premium_card.dart';
import '../../../widgets/section_header.dart';
import '../../site/site_providers.dart';
import '../data/team_colors.dart';
import '../models/game_state.dart';
import '../models/score_alert_config.dart';
import '../models/score_alert_event.dart';
import '../models/sport_type.dart';
import '../providers/sports_alert_providers.dart';
import '../services/alert_trigger_service.dart';
import 'team_picker_screen.dart';

// ---------------------------------------------------------------------------
// Sport emoji helper
// ---------------------------------------------------------------------------

String _sportEmoji(SportType sport) => switch (sport) {
      SportType.nfl || SportType.ncaaFB => '\u{1F3C8}',
      SportType.nba || SportType.wnba || SportType.ncaaMB => '\u{1F3C0}',
      SportType.mlb => '\u26BE',
      SportType.nhl => '\u{1F3D2}',
      SportType.mls ||
      SportType.nwsl ||
      SportType.fifa ||
      SportType.championsLeague =>
        '\u26BD',
    };

/// Default test event type per sport.
AlertEventType _testEventType(SportType sport) => switch (sport) {
      SportType.nfl || SportType.ncaaFB => AlertEventType.touchdown,
      SportType.nba || SportType.wnba || SportType.ncaaMB =>
        AlertEventType.clutchBasket,
      SportType.mlb => AlertEventType.run,
      SportType.nhl => AlertEventType.goal,
      SportType.mls ||
      SportType.nwsl ||
      SportType.fifa ||
      SportType.championsLeague =>
        AlertEventType.soccerGoal,
    };

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

class SportsAlertsScreen extends ConsumerWidget {
  const SportsAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(sportsAlertConfigsProvider);
    final isActive = ref.watch(sportsAlertActiveProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── App bar ──
          SliverPersistentHeader(
            pinned: true,
            delegate: _GlassAppBarDelegate(
              child: GlassAppBar(
                title: const Text('Sports Alerts'),
                actions: [
                  // Pulsing service indicator
                  if (isActive)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: StatusDot(isOnline: true, size: 8),
                    ),
                  // Overflow menu
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) => _handleOverflow(context, ref, v),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'test',
                        child: Text('Test Alert'),
                      ),
                      const PopupMenuItem(
                        value: 'help',
                        child: Text('How it works'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            // Bottom padding clears the GlassDockNavBar so the last
            // team card / "Add Team" button isn't hidden behind it.
            padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context) + 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Master toggle card ──
                _MasterToggleCard(configs: configs, isActive: isActive),

                const SizedBox(height: 24),

                // ── Your teams section ──
                SectionHeader(
                  title: 'Your Teams',
                  icon: Icons.groups,
                  iconColor: NexGenPalette.cyan,
                  padding: const EdgeInsets.only(bottom: 12),
                ),

                if (configs.isEmpty)
                  _EmptyTeamsCard()
                else
                  ...configs.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TeamCard(config: c),
                      )),

                const SizedBox(height: 12),

                // ── Add team button ──
                _AddTeamButton(),

                const SizedBox(height: 24),

                // ── Today's games section ──
                SectionHeader(
                  title: "Today's Games",
                  icon: Icons.sports,
                  iconColor: NexGenPalette.amber,
                  padding: const EdgeInsets.only(bottom: 12),
                ),

                ...configs.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _GameStatusTile(config: c),
                    )),

                if (configs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'Add a team to see game statuses',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NexGenPalette.textMedium,
                            ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Overflow menu handlers ──

  void _handleOverflow(BuildContext context, WidgetRef ref, String value) {
    switch (value) {
      case 'test':
        _fireTestAlert(context, ref);
      case 'help':
        _showHelp(context);
    }
  }

  void _fireTestAlert(BuildContext context, WidgetRef ref) {
    final configs = ref.read(sportsAlertConfigsProvider);
    if (configs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a team first')),
      );
      return;
    }

    final config = configs.first;
    final teamInfo = kTeamColors[config.teamSlug];
    if (teamInfo == null) return;

    final ips = ref.read(activeAreaControllerIpsProvider);
    final trigger = AlertTriggerService(controllerIps: ips);
    final event = ScoreAlertEvent(
      teamSlug: config.teamSlug,
      sport: config.sport,
      eventType: _testEventType(config.sport),
      pointsScored: config.sport == SportType.nfl ? 6 : 1,
      gameId: 'test_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
    );

    trigger.handleAlertEvent(event, config);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Test alert fired for ${teamInfo.teamName}!',
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.sports_football, color: NexGenPalette.cyan),
                  const SizedBox(width: 8),
                  Text(
                    'How Sports Alerts Work',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _helpRow(context, '1', 'Add your favorite teams'),
              _helpRow(context, '2',
                  'When your team scores, your lights celebrate with team colors'),
              _helpRow(context, '3',
                  'Touchdowns get a big light show, field goals a smaller one'),
              _helpRow(context, '4',
                  'Use "Test Alert" to preview the effect'),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _helpRow(BuildContext context, String num, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              num,
              style: TextStyle(
                color: NexGenPalette.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Master toggle card
// ---------------------------------------------------------------------------

class _MasterToggleCard extends ConsumerWidget {
  const _MasterToggleCard({
    required this.configs,
    required this.isActive,
  });

  final List<ScoreAlertConfig> configs;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PremiumCard(
      showAccentBar: true,
      accentColor: isActive ? NexGenPalette.cyan : Colors.grey,
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isActive
                    ? [NexGenPalette.cyan, NexGenPalette.cyan.withValues(alpha: 0.6)]
                    : [Colors.grey, Colors.grey.withValues(alpha: 0.6)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: NexGenPalette.cyan.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),

          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sports Alerts',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Get light shows when your team scores',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: NexGenPalette.textMedium,
                      ),
                ),
              ],
            ),
          ),

          // Toggle
          Switch(
            value: isActive,
            onChanged: (v) {
              final notifier =
                  ref.read(sportsAlertConfigsProvider.notifier);
              // Toggle all configs on/off
              for (final c in configs) {
                if (c.isEnabled != v) {
                  notifier.toggleConfig(c.id);
                }
              }
            },
            activeThumbColor: NexGenPalette.cyan,
            activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyTeamsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      child: Column(
        children: [
          Icon(
            Icons.sports_football,
            size: 48,
            color: NexGenPalette.textMedium.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'No teams added yet',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add your favorite teams to get score alerts',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team card
// ---------------------------------------------------------------------------

class _TeamCard extends ConsumerWidget {
  const _TeamCard({required this.config});

  final ScoreAlertConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamInfo = kTeamColors[config.teamSlug];
    if (teamInfo == null) return const SizedBox.shrink();

    final primary = teamInfo.primary;
    final secondary = teamInfo.secondary;

    return PremiumCard(
      showAccentBar: true,
      accentColor: primary,
      onTap: () => _showEditSheet(context, ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: emoji + name + edit
          Row(
            children: [
              Text(
                _sportEmoji(config.sport),
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  teamInfo.teamName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(
                Icons.edit_outlined,
                size: 18,
                color: NexGenPalette.textMedium,
              ),
            ],
          ),

          const SizedBox(height: 6),

          // Subtitle: sensitivity
          Row(
            children: [
              _InfoPill(
                label: config.sensitivity.name == 'allEvents'
                    ? 'All events'
                    : config.sensitivity.name == 'majorOnly'
                        ? 'Major only'
                        : 'Clutch only',
              ),
              if (!config.isEnabled) ...[
                const SizedBox(width: 8),
                _InfoPill(label: 'Paused', color: NexGenPalette.amber),
              ],
            ],
          ),

          const SizedBox(height: 8),

          // Color preview dots
          Row(
            children: [
              _ColorDot(color: primary),
              const SizedBox(width: 6),
              _ColorDot(color: secondary),
              const SizedBox(width: 10),
              Text(
                'Preview colors',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditAlertConfigSheet(config: config),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit config bottom sheet
// ---------------------------------------------------------------------------

class _EditAlertConfigSheet extends ConsumerStatefulWidget {
  const _EditAlertConfigSheet({required this.config});
  final ScoreAlertConfig config;

  @override
  ConsumerState<_EditAlertConfigSheet> createState() =>
      _EditAlertConfigSheetState();
}

class _EditAlertConfigSheetState extends ConsumerState<_EditAlertConfigSheet> {
  late AlertSensitivity _sensitivity;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _sensitivity = widget.config.sensitivity;
    _enabled = widget.config.isEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final teamInfo = kTeamColors[widget.config.teamSlug];
    final teamName = teamInfo?.teamName ?? widget.config.teamSlug;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Text(
                  _sportEmoji(widget.config.sport),
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    teamName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Enabled toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              subtitle: Text(_enabled ? 'Alerts active' : 'Paused'),
              value: _enabled,
              activeThumbColor: NexGenPalette.cyan,
              activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.3),
              onChanged: (v) => setState(() => _enabled = v),
            ),

            const Divider(color: NexGenPalette.line),
            const SizedBox(height: 8),

            // Sensitivity selector
            Text(
              'Alert Sensitivity',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            RadioGroup<AlertSensitivity>(
              groupValue: _sensitivity,
              onChanged: (v) {
                if (v != null) setState(() => _sensitivity = v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: AlertSensitivity.values.map((s) => RadioListTile<AlertSensitivity>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_sensitivityLabel(s)),
                      subtitle: Text(
                        _sensitivityDescription(s),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NexGenPalette.textMedium,
                            ),
                      ),
                      value: s,
                    )).toList(),
              ),
            ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                // Delete button
                OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(sportsAlertConfigsProvider.notifier)
                        .removeConfig(widget.config.id);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B6B),
                    side: const BorderSide(
                      color: Color(0xFFFF6B6B),
                      width: 1,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),

                const Spacer(),

                // Save button
                FilledButton.icon(
                  onPressed: () {
                    final updated = widget.config.copyWith(
                      isEnabled: _enabled,
                      sensitivity: _sensitivity,
                    );
                    ref
                        .read(sportsAlertConfigsProvider.notifier)
                        .updateConfig(updated);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _sensitivityLabel(AlertSensitivity s) => switch (s) {
        AlertSensitivity.allEvents => 'All Events',
        AlertSensitivity.majorOnly => 'Major Only',
        AlertSensitivity.clutchOnly => 'Clutch Only',
      };

  String _sensitivityDescription(AlertSensitivity s) => switch (s) {
        AlertSensitivity.allEvents =>
          'Flash on every scoring play',
        AlertSensitivity.majorOnly =>
          'Touchdowns, goals, and home runs only',
        AlertSensitivity.clutchOnly =>
          'Only during close, late-game moments',
      };
}

// ---------------------------------------------------------------------------
// Add Team button
// ---------------------------------------------------------------------------

class _AddTeamButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TeamPickerScreen()),
      ),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add Team'),
      style: OutlinedButton.styleFrom(
        foregroundColor: NexGenPalette.cyan,
        side: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        minimumSize: const Size(double.infinity, 48),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Game status tile
// ---------------------------------------------------------------------------

class _GameStatusTile extends ConsumerWidget {
  const _GameStatusTile({required this.config});
  final ScoreAlertConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamInfo = kTeamColors[config.teamSlug];
    if (teamInfo == null) return const SizedBox.shrink();

    final gameAsync = ref.watch(activeGameProvider(config.teamSlug));

    return gameAsync.when(
      data: (game) {
        if (game == null) {
          return _noGameTile(context, teamInfo);
        }
        return _gameTile(context, teamInfo, game);
      },
      loading: () => _loadingTile(context, teamInfo),
      error: (_, __) => _noGameTile(context, teamInfo),
    );
  }

  Widget _gameTile(BuildContext context, TeamColors team, GameState game) {
    final isLive = game.status == GameStatus.inProgress ||
        game.status == GameStatus.halftime;
    final isFinal = game.status == GameStatus.final_;

    String statusText;
    Color statusColor;
    if (isLive) {
      final period = game.period ?? '';
      final clock = game.clock ?? '';
      statusText = game.status == GameStatus.halftime
          ? 'Halftime'
          : 'Q$period $clock';
      statusColor = const Color(0xFFFF4444);
    } else if (isFinal) {
      statusText = 'Final';
      statusColor = NexGenPalette.textMedium;
    } else {
      statusText = 'Scheduled';
      statusColor = NexGenPalette.cyan;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLive
              ? const Color(0xFFFF4444).withValues(alpha: 0.3)
              : NexGenPalette.line,
        ),
      ),
      child: Row(
        children: [
          // Teams matchup
          Expanded(
            child: Text(
              '${game.awayTeam} @ ${game.homeTeam}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Score (if in progress or final)
          if (isLive || isFinal) ...[
            Text(
              '${game.awayScore}-${game.homeScore}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 10),
          ],

          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLive) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noGameTile(BuildContext context, TeamColors team) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          _ColorDot(color: team.primary, size: 10),
          const SizedBox(width: 8),
          Text(
            team.teamName,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),
          const Spacer(),
          Text(
            'No game today',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: NexGenPalette.textMedium.withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }

  Widget _loadingTile(BuildContext context, TeamColors team) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          _ColorDot(color: team.primary, size: 10),
          const SizedBox(width: 8),
          Text(
            team.teamName,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),
          const Spacer(),
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: NexGenPalette.cyan.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared widgets
// ---------------------------------------------------------------------------

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, this.size = 18});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? NexGenPalette.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sliver-persistent-header delegate for GlassAppBar
// ---------------------------------------------------------------------------

class _GlassAppBarDelegate extends SliverPersistentHeaderDelegate {
  _GlassAppBarDelegate({required this.child});
  final PreferredSizeWidget child;

  @override
  double get minExtent => kToolbarHeight + 24; // toolbar + status bar approx
  @override
  double get maxExtent => kToolbarHeight + 24;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _GlassAppBarDelegate oldDelegate) =>
      child != oldDelegate.child;
}
