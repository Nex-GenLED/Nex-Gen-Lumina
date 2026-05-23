// lib/features/neighborhood/widgets/game_day_setup_screen.dart
//
// Path 2 (Sync→Complement→Game Day) entry point. Convergence-Phase-2b
// rewrites this file from a config builder into a Path 1 reader: the
// canonical [GameDayAutopilotConfig] is the single source of truth for
// team Game Day settings. This screen lets the user pick a team that
// already has Path 1 configured (deep-linking to Path 1 setup when not)
// and surfaces ONE "Light it Up Now" button + (for hosts) an explicit
// "also broadcast" checkbox that defaults OFF (DECISION 1: never
// auto-fanout).
//
// What the previous shape did and why it's gone:
//   - Built an in-memory GameDaySyncConfig (effect/colors/sliders) that
//     could diverge from the user's Path 1. Phase 2b deletes the
//     duplicate; users edit Game Day settings ONLY in Path 1.
//   - Had three buttons (Apply to My House / Set for Group / Set for
//     Whole Neighborhood). Phase 2b collapses to one apply path with
//     a host-only broadcast checkbox.
//   - The Score Celebration toggle and the Game Day Autopilot toggle
//     lived in Step 2. The autopilot toggle relocates into the new
//     Step 2 preview (still useful: a host can enable/disable autopilot
//     for the team while looking at the Light-it-Up confirm). The
//     score-celebration toggle moves to Path 1's Game Day Fan Zone
//     where the rest of the team config lives (no UI change needed —
//     Path 1 already exposes it; the Path 2 duplicate is dropped).
//
// Decision 2 holds by construction: lightItUpNow routes the apply
// through applyPayloadWithLabel — the same participation-respecting
// chokepoint validated by the 2026-05-22 .250 hardware probe.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_colors.dart';
import '../../../app_router.dart';
import '../../../theme.dart';
import '../../../utils/time_format.dart';
import '../../autopilot/game_day_autopilot_providers.dart';
import '../../autopilot/game_day_autopilot_service.dart';
import '../../game_day/light_it_up_now.dart';
import '../../sports_alerts/data/team_colors.dart';
import '../../sports_alerts/models/sport_type.dart';
import '../../wled/wled_providers.dart';
import '../neighborhood_models.dart';
import '../neighborhood_providers.dart';
import '../providers/group_autopilot_providers.dart';
import '../services/path1_game_day_snapshot.dart';
import '../services/path2_setup_resolution.dart';

// ═════════════════════════════════════════════════════════════════════════════
// PROVIDERS — kept from the legacy screen so the team-picker UI behaves the same
// ═════════════════════════════════════════════════════════════════════════════

/// Sport filter for the Game Day team picker.
final _gameDaySportFilterProvider = StateProvider<SportType?>((ref) => null);

/// Search query for the Game Day team picker.
final _gameDaySearchProvider = StateProvider<String>((ref) => '');

/// Filtered teams for Game Day picker.
final _gameDayFilteredTeamsProvider =
    Provider<List<MapEntry<String, TeamColors>>>((ref) {
  final query = ref.watch(_gameDaySearchProvider).toLowerCase().trim();
  final sport = ref.watch(_gameDaySportFilterProvider);

  var entries = kTeamColors.entries.toList()
    ..sort((a, b) => a.value.teamName.compareTo(b.value.teamName));

  if (sport != null) {
    entries = entries.where((e) => e.value.sport == sport).toList();
  }

  if (query.isEmpty) return entries;

  return entries.where((entry) {
    final slug = entry.key.toLowerCase();
    final name = entry.value.teamName.toLowerCase();
    final sportName = entry.value.sport.displayName.toLowerCase();
    return name.contains(query) ||
        slug.contains(query) ||
        sportName.contains(query);
  }).toList();
});

// ═════════════════════════════════════════════════════════════════════════════
// GAME DAY PATH 2 SCREEN
// ═════════════════════════════════════════════════════════════════════════════

/// Path 2 entry: pick a Path 1-configured team, preview its current
/// design, and Light it Up (optionally broadcasting to the
/// neighborhood). Returns the [Path1GameDaySnapshot] of the team the
/// user lit up via Navigator.pop, or null if backed out.
class GameDayPath2Screen extends ConsumerStatefulWidget {
  /// When true, the broadcast checkbox is shown on the Step 2 confirm.
  final bool isHost;

  const GameDayPath2Screen({super.key, this.isHost = false});

  @override
  ConsumerState<GameDayPath2Screen> createState() =>
      _GameDayPath2ScreenState();
}

class _GameDayPath2ScreenState extends ConsumerState<GameDayPath2Screen> {
  final _searchController = TextEditingController();

  // Step 1 → 2 transition state. Both set when the user picks a team
  // that has Path 1 configured; both null on Step 1.
  Path1GameDaySnapshot? _selectedSnapshot;
  TeamColors? _selectedTeam;

  // DECISION 1: host broadcast checkbox defaults OFF, never auto-fanout.
  bool _broadcastToGroup = false;

  // Re-entry guard for the apply button so a slow controller doesn't
  // produce duplicate writes when the user double-taps.
  bool _applying = false;

  bool get _isStep2 => _selectedSnapshot != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(_gameDaySearchProvider.notifier).state = '';
      ref.read(_gameDaySportFilterProvider.notifier).state = null;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (_isStep2) {
              setState(() {
                _selectedSnapshot = null;
                _selectedTeam = null;
                _broadcastToGroup = false;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          _isStep2 ? _selectedTeam!.teamName : 'Game Day',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isStep2 ? _buildStep2() : _buildStep1(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1: Team picker — surfaces Path 1 status per team, deep-links
  // unconfigured teams into Path 1 setup before allowing Light-it-Up.
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep1() {
    final teams = ref.watch(_gameDayFilteredTeamsProvider);
    final activeSport = ref.watch(_gameDaySportFilterProvider);

    return Column(
      children: [
        // Header prompt
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            'Who are we lighting up for today?',
            style: TextStyle(
              color: Colors.grey.shade300,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (v) =>
                ref.read(_gameDaySearchProvider.notifier).state = v,
            decoration: InputDecoration(
              hintText: 'Search teams...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(_gameDaySearchProvider.notifier).state = '';
                      },
                    )
                  : null,
              filled: true,
              fillColor: NexGenPalette.gunmetal,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: NexGenPalette.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: NexGenPalette.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: NexGenPalette.cyan),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            style: const TextStyle(color: Colors.white),
          ),
        ),

        // Sport filter chips — multi-row Wrap, parity with the Fan Zone
        // picker (601f888) so all ~11 leagues are visible at once.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GameDaySportFilterChips(
            activeSport: activeSport,
            onSportChanged: (s) =>
                ref.read(_gameDaySportFilterProvider.notifier).state = s,
          ),
        ),

        const SizedBox(height: 4),

        // Team list
        Expanded(
          child: teams.isEmpty
              ? Center(
                  child: Text(
                    'No teams found',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                      16, 4, 16, navBarTotalHeight(context) + 16),
                  itemCount: teams.length,
                  itemBuilder: (context, i) {
                    final entry = teams[i];
                    return _GameDayTeamRow(
                      slug: entry.key,
                      team: entry.value,
                      onTap: () => _handleTeamTap(entry.key, entry.value),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Decide whether the chosen team has Path 1 set up. Branches on the
  /// 3-state [Path1SnapshotResolution]:
  ///   - Loading → no-op (the row's tap is already disabled in this
  ///     state; this is defense-in-depth in case the user somehow
  ///     fires the tap mid-load).
  ///   - Ready   → advance to Step 2 read-only preview.
  ///   - Absent  → deep-link to the Path 1 Fan Zone.
  ///
  /// The 3-state resolution is the same signal the row badge reads, so
  /// badge-shown ⇔ tap-advances. They can never disagree.
  void _handleTeamTap(String slug, TeamColors team) {
    final resolution = resolvePath2GameDaySetup(
      resolution:
          ref.read(path1GameDaySnapshotResolutionProvider(slug)),
    );
    switch (resolution) {
      case Path2SetupLoading():
        // Should be unreachable because the row disables its onTap while
        // loading. Keep an explicit branch (no-op) so the switch is
        // exhaustive and a regression here is caught at the type level.
        return;
      case Path2SetupReady(:final snapshot):
        setState(() {
          _selectedSnapshot = snapshot;
          _selectedTeam = team;
        });
      case Path2SetupNeedsPath1():
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Set up Game Day Autopilot for ${team.teamName} first.',
            ),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 3),
          ),
        );
        // Pop this Path 2 screen so the user lands cleanly in the Fan
        // Zone rather than stacking screens. Coming back through Path 2
        // after adding a team is a one-tap return.
        Navigator.of(context).pop();
        context.push(AppRoutes.gameDay);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2: Read-only preview of the team's Path 1 design + Light it Up
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    final team = _selectedTeam!;
    final snap = _selectedSnapshot!;
    final isAvailable = ref.watch(wledRepositoryProvider) != null;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, navBarTotalHeight(context) + 16),
      children: [
        // Team color banner
        Container(
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [team.primary, team.secondary],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: team.primary.withValues(alpha: 0.3),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            team.teamName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Read-only Path 1 design label
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade900.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: Row(
            children: [
              Icon(Icons.palette, color: team.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Design',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      snap.designLabel,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  // Deep-link to Path 1 for design edits — the only
                  // surface where Game Day team config is changed.
                  context.push(AppRoutes.gameDay);
                },
                child: const Text('Edit'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Color preview swatch (driven by the Path 1 snapshot's effectId)
        Container(
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: snap.effectId == 0
                  ? [team.primary, team.primary, team.secondary, team.secondary]
                  : [
                      team.primary,
                      team.secondary,
                      team.primary,
                      team.secondary,
                    ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
        const SizedBox(height: 20),

        // ── Game Day Autopilot toggle (RELOCATED from the legacy Step 2) ──
        _GameDayAutopilotSection(
          teamSlug: snap.teamSlug,
          team: team,
        ),
        const SizedBox(height: 24),

        // ── Host broadcast checkbox (DECISION 1: default OFF) ──
        if (widget.isHost) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade900.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _broadcastToGroup
                    ? team.primary.withValues(alpha: 0.5)
                    : Colors.grey.shade800,
              ),
            ),
            child: CheckboxListTile(
              value: _broadcastToGroup,
              onChanged: (v) => setState(() => _broadcastToGroup = v ?? false),
              activeColor: team.primary,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Also broadcast to my neighborhood',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Sets the group Game Day for opted-in neighbors.',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Single unified action: Light it Up Now ──
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: !isAvailable || _applying ? null : _lightItUpNow,
            icon: _applying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.flash_on),
            label: Text(_applying ? 'Lighting up...' : 'Light it Up Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: team.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (!isAvailable) ...[
          const SizedBox(height: 8),
          Text(
            'Controller not connected — check that you are on the same '
            'Wi-Fi as your controller.',
            style: TextStyle(color: Colors.red.shade300, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Future<void> _lightItUpNow() async {
    final snap = _selectedSnapshot!;
    final messenger = ScaffoldMessenger.of(context);

    // Look up the FULL Path 1 config — the snapshot omits
    // savedDesignPayload (broadcast-shaped view-model). The apply
    // helper prefers savedDesignPayload over the basic config-derived
    // payload, matching Path 1 _activateNow's precedence.
    final config = ref.read(teamAutopilotConfigProvider(snap.teamSlug));
    if (config == null) {
      // Race: snapshot existed at picker time but the underlying config
      // was removed since. Surface and bail.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Game Day Autopilot for ${snap.teamName} is no longer '
            'configured. Set it up again to continue.',
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    setState(() => _applying = true);
    final notifier = ref.read(wledStateProvider.notifier);
    final service = ref.read(groupAutopilotServiceProvider);
    final groupId = ref.read(activeNeighborhoodIdProvider);

    final outcome = await lightItUpNow(
      applyPayloadWithLabel: notifier.applyPayloadWithLabel,
      configureForTeam: service.configureForTeam,
      config: config,
      broadcastToGroup: _broadcastToGroup,
      groupId: groupId,
    );

    if (!mounted) return;
    setState(() => _applying = false);

    switch (outcome) {
      case LightItUpApplied():
        messenger.showSnackBar(
          SnackBar(
            content: Text('${snap.teamName} lights activated!'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop(snap);
      case LightItUpAppliedAndBroadcasted(:final assembled):
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${snap.teamName} lights activated + broadcast to '
              '${assembled.activeMemberIds.length} '
              '${assembled.activeMemberIds.length == 1 ? "house" : "houses"}.',
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pop(snap);
      case LightItUpApplyFailed():
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to activate lights. Check controller connection.',
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      case LightItUpAppliedButBroadcastFailed(:final error):
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${snap.teamName} lights lit, but broadcast failed: $error',
            ),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.of(context).pop(snap);
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// GAME DAY AUTOPILOT SECTION
// ═════════════════════════════════════════════════════════════════════════════
//
// RELOCATION NOTE: this section moved from the legacy Step 2 (where it
// sat under the effect picker + sliders) into the new Path 2 Step 2 —
// the read-only confirm screen. Users who picked a team can still
// enable/disable Game Day Autopilot for it from here while reviewing
// the design. The widget itself is unchanged.

class _GameDayAutopilotSection extends ConsumerStatefulWidget {
  final String teamSlug;
  final TeamColors team;

  const _GameDayAutopilotSection({
    required this.teamSlug,
    required this.team,
  });

  @override
  ConsumerState<_GameDayAutopilotSection> createState() =>
      _GameDayAutopilotSectionState();
}

class _GameDayAutopilotSectionState
    extends ConsumerState<_GameDayAutopilotSection> {
  DateTime? _nextGameDate;
  bool _loadingNextGame = false;

  @override
  void initState() {
    super.initState();
    _fetchNextGame();
  }

  Future<void> _fetchNextGame() async {
    setState(() => _loadingNextGame = true);
    try {
      final date = await ref
          .read(gameDayAutopilotNotifierProvider.notifier)
          .fetchNextGame(widget.teamSlug);
      if (mounted) {
        setState(() {
          _nextGameDate = date;
          _loadingNextGame = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingNextGame = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = ref.watch(teamAutopilotEnabledProvider(widget.teamSlug));
    final config = ref.watch(teamAutopilotConfigProvider(widget.teamSlug));
    final session =
        ref.watch(teamAutopilotSessionProvider(widget.teamSlug));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEnabled
              ? widget.team.primary.withValues(alpha: 0.4)
              : Colors.grey.shade800,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt,
                color: isEnabled
                    ? widget.team.primary
                    : Colors.grey.shade500,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Game Day Autopilot',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Lights activate 30 min before game start, off 30 min after.',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                onChanged: (v) {
                  ref
                      .read(gameDayAutopilotNotifierProvider.notifier)
                      .toggleAutopilot(teamSlug: widget.teamSlug, enabled: v);
                },
                activeColor: widget.team.primary,
              ),
            ],
          ),
          if (isEnabled) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.team.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.team.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          color: Colors.grey.shade400, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        'Next game: ',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                      if (_loadingNextGame)
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: widget.team.primary,
                          ),
                        )
                      else
                        Text(
                          _nextGameDate != null
                              ? _formatGameDate(_nextGameDate!)
                              : 'No upcoming games',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.palette,
                          color: Colors.grey.shade400, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        'Design: ',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        config?.designLabel ?? 'Auto-selected',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (session != null && session.isActive) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.team.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _sessionIcon(session.phase),
                            color: widget.team.primary,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _sessionLabel(session.phase),
                            style: TextStyle(
                              color: widget.team.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatGameDate(DateTime date) {
    final timeFormat = ref.read(timeFormatPreferenceProvider);
    final local = date.toLocal();
    final now = DateTime.now();
    final diff = date.difference(now);
    final time = formatTime(local, timeFormat: timeFormat);

    if (diff.inDays == 0 && diff.inMinutes > -120) {
      return 'Today at $time';
    } else if (diff.inDays == 1 || (diff.inDays == 0 && local.day != now.day)) {
      return 'Tomorrow at $time';
    } else {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${weekdays[local.weekday - 1]}, ${months[local.month - 1]} ${local.day} at $time';
    }
  }

  IconData _sessionIcon(AutopilotSessionPhase phase) => switch (phase) {
        AutopilotSessionPhase.preGame => Icons.timer,
        AutopilotSessionPhase.liveGame => Icons.sports,
        AutopilotSessionPhase.postGame => Icons.timelapse,
        _ => Icons.bolt,
      };

  String _sessionLabel(AutopilotSessionPhase phase) => switch (phase) {
        AutopilotSessionPhase.preGame => 'PRE-GAME ACTIVE',
        AutopilotSessionPhase.liveGame => 'LIVE GAME',
        AutopilotSessionPhase.postGame => 'POST-GAME COUNTDOWN',
        _ => 'AUTOPILOT',
      };
}

// ═════════════════════════════════════════════════════════════════════════════
// SCORE CELEBRATION
// ═════════════════════════════════════════════════════════════════════════════
//
// NOTE FOR PHASE 2b-PART-2: this function and its hardcoded fx=88 +
// member-fanout logic are the celebration broadcast slated for rework
// in Phase 2b-part-2. Left intact here so the score-monitoring
// pipeline keeps working through the part-1 review window.

/// Triggers a score celebration animation across all Neighborhood Sync members
/// who have the same team selected in Game Day mode.
///
/// Live pipeline: ScoreMonitorService detects scoring events → notifies
/// SyncEventBackgroundWorker.onScoreAlertEvent() → fires celebrations on
/// all active sync participants. This function handles the UI-layer broadcast.
/// Also used by the debug "Test Score Trigger" button for manual QA testing.
Future<void> triggerScoreCelebration(String teamSlug, WidgetRef ref) async {
  final teamColors = kTeamColors[teamSlug];
  if (teamColors == null) return;

  debugPrint('[GameDay] Score celebration triggered for $teamSlug');

  final groupId = ref.read(activeNeighborhoodIdProvider);
  if (groupId == null) {
    debugPrint('[GameDay] No active neighborhood group for celebration');
    return;
  }

  final service = ref.read(neighborhoodServiceProvider);
  final members =
      ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
  if (members.isEmpty) return;

  final celebrationCommand = SyncCommand(
    id: '',
    groupId: groupId,
    effectId: 88, // Fireworks
    colors: [
      teamColors.primary.value & 0xFFFFFF,
      teamColors.secondary.value & 0xFFFFFF,
    ],
    speed: 200,
    intensity: 220,
    brightness: 255,
    startTimestamp: DateTime.now().add(const Duration(seconds: 1)),
    memberDelays: {for (var m in members) m.oderId: 0},
    timingConfig: const SyncTimingConfig(),
    syncType: SyncType.simultaneous,
    patternName: '${teamColors.teamName} SCORES!',
  );

  try {
    await service.broadcastSyncCommand(celebrationCommand);
    debugPrint('[GameDay] Celebration broadcast sent for ${teamColors.teamName}');
  } catch (e) {
    debugPrint('[GameDay] Celebration broadcast failed: $e');
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

/// Multi-row Wrap of per-league sport filter chips for the Path 2 team
/// picker. Pure presentation — takes the active sport + selection
/// callback; the Riverpod state plumbing lives at the call site.
///
/// Layout (Wrap, not horizontal ListView) is the symmetry match with
/// the Fan Zone picker after 601f888. With ~11 leagues, horizontal
/// scrolling required swiping to reach NHL/Soccer leagues; Wrap shows
/// them all at once on a typical phone width.
///
/// This widget is intentionally public + Riverpod-free so the widget
/// test (game_day_path2_sport_chips_test.dart) can exercise it
/// directly without spinning up the screen's Firestore-dependent
/// providers.
class GameDaySportFilterChips extends StatelessWidget {
  /// Currently selected sport, or null when "ALL" is active.
  final SportType? activeSport;

  /// Called with the new sport selection (null for "ALL").
  final ValueChanged<SportType?> onSportChanged;

  const GameDaySportFilterChips({
    super.key,
    required this.activeSport,
    required this.onSportChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      runSpacing: 6,
      children: [
        _SportChip(
          label: 'ALL',
          selected: activeSport == null,
          onTap: () => onSportChanged(null),
        ),
        for (final sport in SportType.values)
          _SportChip(
            label: sport.displayName,
            selected: activeSport == sport,
            onTap: () => onSportChanged(sport),
          ),
      ],
    );
  }
}

class _SportChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SportChip({
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? NexGenPalette.cyan.withValues(alpha: 0.15)
                : NexGenPalette.gunmetal,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? NexGenPalette.cyan.withValues(alpha: 0.6)
                  : NexGenPalette.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Team row in Step 1. Renders one of three states from the same
/// upstream [path1GameDaySnapshotResolutionProvider] the tap handler
/// reads, so the badge and tap-routing CAN NEVER DISAGREE:
///
///   - Loading → muted row, spinner trailing icon, tap DISABLED.
///                Prevents the 1b configure-twice gap where mid-load
///                taps deep-linked to the Fan Zone builder.
///   - Ready   → "Configured" check + chevron, tap advances to Step 2.
///   - Absent  → no badge, plus-icon trailing, tap deep-links to setup.
class _GameDayTeamRow extends ConsumerWidget {
  final String slug;
  final TeamColors team;
  final VoidCallback onTap;

  const _GameDayTeamRow({
    required this.slug,
    required this.team,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolution =
        ref.watch(path1GameDaySnapshotResolutionProvider(slug));
    final isLoading = resolution is Path1SnapshotLoading;
    final hasPath1 = resolution is Path1SnapshotReady;
    final sportEmoji = switch (team.sport) {
      SportType.nfl || SportType.ncaaFB => '\u{1F3C8}',
      SportType.nba || SportType.wnba || SportType.ncaaMB => '\u{1F3C0}',
      SportType.mlb => '\u{26BE}',
      SportType.nhl => '\u{1F3D2}',
      SportType.mls ||
      SportType.nwsl ||
      SportType.fifa ||
      SportType.championsLeague =>
        '\u{26BD}',
    };

    return InkWell(
      // Tap is DISABLED while the resolution is Loading — gates the
      // 1b configure-twice race (badge + tap derive from the same
      // signal, so a configured team's tap can never collapse to
      // "needs setup" mid-load).
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasPath1
                  ? team.primary.withValues(alpha: 0.35)
                  : NexGenPalette.line,
            ),
          ),
          child: Opacity(
            opacity: isLoading ? 0.55 : 1.0,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [team.primary, team.secondary],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    sportEmoji,
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team.teamName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            team.sport.displayName,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 11,
                            ),
                          ),
                          if (hasPath1) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_circle,
                              color: team.primary,
                              size: 12,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'Configured',
                              style: TextStyle(
                                color: team.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: team.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: team.secondary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.grey.shade500,
                    ),
                  )
                else
                  Icon(
                    hasPath1 ? Icons.chevron_right : Icons.add_circle_outline,
                    color: hasPath1 ? Colors.grey.shade400 : Colors.grey.shade600,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PUBLIC API
// ═════════════════════════════════════════════════════════════════════════════

/// Opens the Path 2 Game Day screen and returns the
/// [Path1GameDaySnapshot] of the team the user lit up (or null if they
/// backed out without applying). The apply + optional broadcast are
/// already complete by the time this future resolves — the caller
/// only needs the snapshot for its own sync-session state.
Future<Path1GameDaySnapshot?> showGameDayPath2Setup(
  BuildContext context, {
  required bool isHost,
}) async {
  return Navigator.of(context).push<Path1GameDaySnapshot>(
    MaterialPageRoute(
      builder: (_) => GameDayPath2Screen(isHost: isHost),
    ),
  );
}

// Note for grep-archaeology: the legacy `showGameDaySetup`,
// `showGameDaySetupFull`, `GameDaySetupScreen`, and the
// `GameDaySyncConfig` shape (with `toComplementTheme` /
// `toPatternAssignment`) were the Path 2 duplicate that diverged from
// Path 1. They were removed in Convergence-Phase-2b. Replacement
// public API: [showGameDayPath2Setup] (above). Replacement of
// `GameDaySyncConfig.toComplementTheme`:
// `path1ToComplementTheme(snapshot)` in
// `lib/features/neighborhood/services/path1_complement_theme.dart`.
