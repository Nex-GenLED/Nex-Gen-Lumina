import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexgen_command/features/autopilot/base_layer_gate.dart';
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_banner.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_colors.dart';
import '../../theme.dart';
import '../../widgets/glass_app_bar.dart';
import '../../widgets/section_header.dart';
import '../autopilot/game_day_autopilot_config.dart';
import '../autopilot/game_day_autopilot_providers.dart';
import '../sports_alerts/data/team_colors.dart';
import '../sports_alerts/models/score_alert_config.dart';
import '../sports_alerts/models/game_state.dart';
import '../sports_alerts/models/sport_type.dart';
import '../autopilot/game_day_background_persistence.dart';
import '../sports_alerts/providers/sports_alert_providers.dart';
import 'ephemeral_session/ephemeral_game_session_providers.dart';
import '../sports_alerts/services/sports_background_service.dart';
import '../wled/colorway_effect_selector.dart';
import '../wled/library_hierarchy_models.dart';
import '../wled/wled_effects_catalog.dart';
import '../wled/sports_library_builder.dart';
import '../wled/wled_providers.dart';
import '../wled/zone_providers.dart';
import 'game_day_apply.dart';
import 'game_day_crew_models.dart';
import 'game_day_providers.dart';

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
              topPadding: MediaQuery.of(context).padding.top,
              child: GlassAppBar(
                title: const Text('Game Day'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () => context.pop(),
                ),
              ),
            ),
          ),

          // ── Body ──
          SliverPadding(
            // Bottom padding clears the GlassDockNavBar so the last
            // section ("Join a Crew" / Add Team button) isn't hidden
            // behind the dock on devices with a home indicator.
            padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context) + 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // W2 — the readiness gate, as the customer sees it. Renders
                // nothing when the account is armed (and once, on graduating).
                // Eight of ten live accounts are held in log-only and until now
                // saw a UI that looked armed.
                GateStatusBanner(
                  onCreateSchedule: () => context.push(AppRoutes.schedule),
                ),
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
                ] else
                  _buildEmptyTeamsState(),

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

  Widget _buildEmptyTeamsState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: NexGenPalette.cyan.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.sports_rounded,
              size: 36, color: NexGenPalette.cyan.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text(
            'No teams added yet',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: NexGenPalette.textHigh,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the + button below to add your first team.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: NexGenPalette.textMedium,
              height: 1.4,
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

class _TeamCard extends ConsumerStatefulWidget {
  final GameDayTeamEntry entry;

  const _TeamCard({required this.entry});

  @override
  ConsumerState<_TeamCard> createState() => _TeamCardState();
}

class _TeamCardState extends ConsumerState<_TeamCard> {
  Timer? _motionStyleDebounce;
  double? _motionStyleLocal;

  @override
  void dispose() {
    _motionStyleDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
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
                      ? _GameStatusBadge(
                          game: game,
                          // W3 — only the PRE-GAME promise consults the gate.
                          // Read here, not polled by the badge: the badge keeps
                          // its own cadence, which is what stopped it freezing
                          // for celebrations-off users.
                          gate: ref.watch(gateStatusProvider).value ??
                              GateStatus.unknown,
                        )
                      : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: NexGenPalette.textMedium,
                  tooltip: 'Remove team',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _confirmRemove(context, ref, config),
                ),
              ],
            ),
          ),

          // ── Light Up Now (immediate, standalone action) ──
          // Sits above the config rows so it stays accessible regardless
          // of the Autopilot toggle state.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _activateNow(context, ref, config),
                icon: const Icon(Icons.bolt_rounded, color: Colors.black),
                label: const Text('Light Up Now'),
                style: FilledButton.styleFrom(
                  backgroundColor: _lightUpButtonColor(config),
                  foregroundColor: Colors.black,
                ),
              ),
            ),
          ),

          // ── Config section ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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

                // ── Alerts (folded in from the retired Sports Alerts screen) ─
                // Live Scoring is the alerts ON/OFF — a second arming switch is
                // exactly the redundancy this consolidation removes. What the
                // retired screen owned that the card did not is SENSITIVITY,
                // so that is what moves here. Greyed-not-hidden when Live
                // Scoring is off, the same treatment Skip Day Games gets under
                // Autopilot, so the user can see what Live Scoring configures.
                if (!entry.isCrewMember) ...[
                  const SizedBox(height: 4),
                  AnimatedOpacity(
                    opacity: config.scoreCelebrationEnabled ? 1.0 : 0.4,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !config.scoreCelebrationEnabled,
                      child: Column(
                        children: [
                          _ConfigRow(
                            icon: Icons.notifications_active_outlined,
                            label: 'Alerts',
                            value: _sensitivityLabel(config.alertSensitivity),
                            onTap: () =>
                                _openSensitivityPicker(context, ref, config),
                          ),
                          // The celebration effect itself — the motion that
                          // fires on a score or a win. Sits with Alerts because
                          // it is the same concern: Alerts says WHEN, this says
                          // WHAT. Distinct from the Design row above, which is
                          // the base look the house runs during the game.
                          _ConfigRow(
                            icon: Icons.auto_awesome_outlined,
                            label: 'Celebration',
                            value: _celebrationLabel(config),
                            onTap: () =>
                                _openCelebrationPicker(context, ref, config),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const Divider(
                    height: 24, color: NexGenPalette.line),

                // ── Autopilot Settings ─────────────────────────────────
                // Primary Autopilot ON/OFF toggle. Dependent controls
                // below are greyed out (Opacity + IgnorePointer) when
                // off — still visible so the user can see what autopilot
                // will configure.
                _ToggleRow(
                  icon: Icons.auto_mode_rounded,
                  label: 'Autopilot',
                  value: config.enabled,
                  enabled: !entry.isCrewMember,
                  onChanged: entry.isCrewMember
                      ? null
                      : (val) => _toggleAutopilot(context, ref, config, val),
                ),

                if (!entry.isCrewMember) ...[
                  const SizedBox(height: 4),
                  AnimatedOpacity(
                    opacity: config.enabled ? 1.0 : 0.4,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !config.enabled,
                      child: _buildSettingsContent(context, ref, config),
                    ),
                  ),
                ],
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
    // Item #64 fix 2026-05-09: route via /dashboard/game-day/picker/:nodeId
    // (parentNavigatorKey: _rootNavigatorKey) instead of the explore-branch
    // route /explore/library/:nodeId. The dashboard-branch route pushes onto
    // the root navigator so the picker's back-arrow returns to Game Day,
    // not the Explore tab root. Other callers of /explore/library/:nodeId
    // (in-explore browsing) keep their branch-local navigation.
    //
    // Resolve the real catalog leaf node id from the team identity instead of
    // minting `team_<slug>` — the kTeamColors-key namespace only coincidentally
    // matched the catalog id for single-name domestic teams and never for
    // soccer / MLS city-strip / NCAA, landing those on an empty folder.
    final nodeId = SportsLibraryBuilder.resolveTeamNodeId(
      teamName: config.teamName,
      sport: config.sport,
      espnTeamId: config.espnTeamId,
    );
    if (nodeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "Couldn't find ${config.teamName}'s designs in the library."),
        ),
      );
      return;
    }
    // teamSlug is passed EXPLICITLY (extra) now that the path param is the
    // real catalog node id — it still flows to ColorwayEffectSelectorPage's
    // saveDesign side-channel via LibraryBrowserScreen.
    context.push('/dashboard/game-day/picker/$nodeId',
        extra: {'teamSlug': config.teamSlug});
  }

  /// Falls back to cyan if the team's primary color is too dark to read
  /// the black foregrounded button label/icon against.
  Color _lightUpButtonColor(GameDayAutopilotConfig config) {
    final primary = Color(config.primaryColorValue);
    return primary.computeLuminance() < 0.2 ? NexGenPalette.cyan : primary;
  }

  Future<void> _activateNow(
    BuildContext context,
    WidgetRef ref,
    GameDayAutopilotConfig config,
  ) async {
    if (ref.read(wledRepositoryProvider) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Controller not connected. Make sure you are on the '
            'same WiFi as your controller.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Capture messenger up-front because the awaits below can unmount this
    // widget before we get to show the result snackbar.
    final messenger = ScaffoldMessenger.of(context);

    // Snapshot what the house is showing BEFORE we overwrite it — this is what
    // the ephemeral session puts back when the game ends. Captured here rather
    // than inside the session because by the time the session exists the team
    // design has already been applied, and capturing then would "revert" to
    // the Game Day look forever.
    Map<String, dynamic> revertPayload = const {};
    try {
      revertPayload =
          await ref.read(wledRepositoryProvider)?.getState() ?? const {};
    } catch (e) {
      debugPrint('[GameDay] Light Up Now: revert capture failed: $e');
    }
    // Null when nothing named is showing — the session needs a concrete label
    // to restore the Now Playing chip to, so fall back to the neutral one.
    final revertLabel = ref.read(activePresetLabelProvider) ?? 'Custom';

    // Convergence-Phase-2b: the payload build + apply routes through
    // the shared [applyGameDayConfigToDevice] helper. The Path 2
    // unified "Light it Up Now" button calls the SAME helper — both
    // call sites must produce identical WLED payloads + labelHint
    // shape so the .250 participation hardware probe's PASS holds.
    final ok = await applyGameDayConfigToDevice(
      applyPayloadWithLabel:
          ref.read(wledStateProvider.notifier).applyPayloadWithLabel,
      config: config,
      participatingChannels: ref.read(effectiveChannelIdsProvider),
      deviceChannels: ref.read(deviceChannelsProvider),
    );
    if (!context.mounted) return;

    if (ok) {
      await _startManualSession(ref, config, revertPayload, revertLabel);
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${config.teamName} lights activated!'
              : 'Failed to activate lights. Check controller connection.',
        ),
        backgroundColor: ok ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );

    // Pop back to whatever pushed this screen so the user immediately
    // sees the Now Playing change on the home dashboard. No-op when the
    // screen sits at the root (e.g. opened as a tab destination).
    if (ok && context.mounted && context.canPop()) {
      context.pop();
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    GameDayAutopilotConfig config,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: Text('Remove ${config.teamName} from My Teams?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(gameDayAutopilotNotifierProvider.notifier).removeTeam(
            teamSlug: config.teamSlug,
            teamName: config.teamName,
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text('${config.teamName} removed.'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e, st) {
      debugPrint('[GameDay] removeTeam failed: $e\n$st');
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not remove ${config.teamName}: $e'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Arm a manual mid-game join WITHOUT touching `config.enabled`.
  ///
  /// "Light Up Now" used to flip `enabled:true`, because the background
  /// worker's session map is what `onScoreAlertEvent` looks in and only the
  /// scheduled path ever wrote it. But `enabled` is the field the SERVER
  /// planner queries (`planGameDayFires.ts`), so joining ONE live game silently
  /// opted the team into every future scheduled show
  /// (audit/GAME_DAY_SPEC_AUDIT.md §3.5).
  ///
  /// Two writes replace that flip, neither touching `enabled`:
  ///   1. [registerManualGameDaySession] — the isolate crossing that arms
  ///      celebrations for this team from this second. Purpose-built for
  ///      exactly this, and previously called from one unrelated screen only.
  ///   2. an ephemeral session — the phase machine that detects the real final
  ///      whistle, reverts, and disarms, so the join SELF-EXPIRES rather than
  ///      running until the user notices.
  ///
  /// Ordering is deliberate. Arming comes first and is not conditional on the
  /// session: ESPN lookups fail, and a celebration that fires without an
  /// auto-revert is a far better outcome than a silent house. The session is
  /// best-effort on top.
  static Future<void> _startManualSession(
    WidgetRef ref,
    GameDayAutopilotConfig config,
    Map<String, dynamic> revertPayload,
    String revertLabel,
  ) async {
    // Bind the game id when we can — it lets the worker's phase machine track
    // THIS game rather than guessing from a timer.
    String? gameId;
    try {
      gameId = (await ref.read(activeGameProvider(config.teamSlug).future))
          ?.gameId;
    } catch (e) {
      debugPrint('[GameDay] Light Up Now: game lookup failed: $e');
    }

    try {
      await registerManualGameDaySession(
        teamSlug: config.teamSlug,
        activeGameId: gameId,
      );
      // Nothing else guarantees the poller is up for a manual join. The
      // scheduled path starts it when a game is within 60 minutes
      // (autopilot_scheduler.dart), which is precisely the path a mid-game
      // join is NOT on. Idempotent when already running.
      await startSportsService();
    } catch (e, st) {
      debugPrint('[GameDay] Light Up Now: arming failed: $e\n$st');
      // Non-fatal — the lights are already on, celebrations just won't fire.
    }

    if (gameId == null) {
      debugPrint('[GameDay] Light Up Now: no live game for ${config.teamSlug} '
          '— armed without an auto-expiring session');
      return;
    }

    try {
      final svc = ref.read(ephemeralGameSessionServiceProvider);
      if (svc == null) return; // signed out
      final session = await svc.createSession(
        teamSlug: config.teamSlug,
        gameId: gameId,
        revertWledPayload: revertPayload,
        revertLabel: revertLabel,
      );
      await svc.startTracking(session.sessionId);
    } catch (e, st) {
      // createSession throws when the game is not in the fetched season
      // schedule. The house stays lit and armed; it just will not self-revert.
      debugPrint('[GameDay] Light Up Now: session create failed: $e\n$st');
    }
  }

  // ── Celebration effect ───────────────────────────────────────────────────

  static String _celebrationLabel(GameDayAutopilotConfig config) {
    final id = config.celebrationEffectId;
    if (id == null) return 'Default';
    return WledEffectsCatalog.getById(id)?.name ?? 'Effect $id';
  }

  /// Open the celebration picker: [ColorwayEffectSelectorPage] in celebration
  /// mode, so it shows only the attention-grabbing subset and hands the choice
  /// back instead of persisting a base design.
  ///
  /// The palette node is SYNTHESIZED from the team's own colours rather than
  /// resolved from the sports library. A celebration should preview in team
  /// colours no matter which library colorway the base design came from, and
  /// this avoids depending on `resolveTeamNodeId` finding a leaf — which it
  /// cannot for every team.
  Future<void> _openCelebrationPicker(
    BuildContext context,
    WidgetRef ref,
    GameDayAutopilotConfig config,
  ) async {
    final node = LibraryNode(
      id: 'celebration_${config.teamSlug}',
      name: '${config.teamName} Celebration',
      nodeType: LibraryNodeType.palette,
      themeColors: [
        Color(config.primaryColorValue),
        Color(config.secondaryColorValue),
      ],
    );

    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    await navigator.push<void>(MaterialPageRoute(
      builder: (_) => ColorwayEffectSelectorPage(
        paletteNode: node,
        celebrationMode: true,
        onDesignSelected: (selection) async {
          final picked = _celebrationFromPayload(selection.wledPayload);
          navigator.pop();
          if (picked == null) return;
          try {
            await ref
                .read(gameDayAutopilotNotifierProvider.notifier)
                .setCelebrationEffect(
                  teamSlug: config.teamSlug,
                  effectId: picked.fx,
                  speed: picked.sx,
                  intensity: picked.ix,
                );
          } catch (e, st) {
            debugPrint('[GameDay] setCelebrationEffect failed: $e\n$st');
            messenger.showSnackBar(const SnackBar(
              content: Text("Couldn't save that celebration effect."),
            ));
          }
        },
      ),
    ));
  }

  /// Pull `fx` / `sx` / `ix` out of the selector's returned WLED payload.
  /// Returns null when the payload has no segment to read — better to keep the
  /// existing choice than to write a fabricated effect id.
  static ({int fx, int sx, int ix})? _celebrationFromPayload(
    Map<String, dynamic> payload,
  ) {
    final seg = payload['seg'];
    if (seg is! List || seg.isEmpty) return null;
    final first = seg.first;
    if (first is! Map) return null;
    final fx = (first['fx'] as num?)?.toInt();
    if (fx == null) return null;
    return (
      fx: fx,
      sx: (first['sx'] as num?)?.toInt() ?? 240,
      ix: (first['ix'] as num?)?.toInt() ?? 240,
    );
  }

  // ── Alert sensitivity (folded in from the retired Sports Alerts screen) ──

  static String _sensitivityLabel(AlertSensitivity s) => switch (s) {
        AlertSensitivity.allEvents => 'All Events',
        AlertSensitivity.majorOnly => 'Major Only',
        AlertSensitivity.clutchOnly => 'Clutch Only',
      };

  static String _sensitivityDescription(AlertSensitivity s) => switch (s) {
        AlertSensitivity.allEvents => 'Celebrate every scoring play',
        AlertSensitivity.majorOnly =>
          'Only touchdowns, home runs, goals and the like',
        AlertSensitivity.clutchOnly =>
          'Only late-game and go-ahead moments',
      };

  Future<void> _openSensitivityPicker(
    BuildContext context,
    WidgetRef ref,
    GameDayAutopilotConfig config,
  ) async {
    final picked = await showModalBottomSheet<AlertSensitivity>(
      context: context,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                'Alert Sensitivity',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: NexGenPalette.textHigh,
                ),
              ),
            ),
            for (final s in AlertSensitivity.values)
              ListTile(
                title: Text(
                  _sensitivityLabel(s),
                  style: const TextStyle(color: NexGenPalette.textHigh),
                ),
                subtitle: Text(
                  _sensitivityDescription(s),
                  style: TextStyle(color: NexGenPalette.textMedium),
                ),
                trailing: s == config.alertSensitivity
                    ? const Icon(Icons.check, color: NexGenPalette.cyan)
                    : null,
                onTap: () => Navigator.of(ctx).pop(s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked == null || picked == config.alertSensitivity) return;
    try {
      await ref
          .read(gameDayAutopilotNotifierProvider.notifier)
          .setAlertSensitivity(teamSlug: config.teamSlug, sensitivity: picked);
    } catch (e, st) {
      debugPrint('[GameDay] setAlertSensitivity failed: $e\n$st');
    }
  }

  void _toggleLiveScoring(
      WidgetRef ref, GameDayAutopilotConfig config, bool value) {
    ref
        .read(gameDayAutopilotNotifierProvider.notifier)
        .setLiveScoring(teamSlug: config.teamSlug, enabled: value)
        .catchError((e, st) {
      debugPrint('[GameDay] setLiveScoring failed: $e\n$st');
    });
  }

  Future<void> _toggleAutopilot(
    BuildContext context,
    WidgetRef ref,
    GameDayAutopilotConfig config,
    bool value,
  ) async {
    debugPrint(
      '\u{1F3DF}\u{FE0F} Game Day Autopilot set to: $value for team: ${config.teamSlug}',
    );
    // BASE-LAYER GATE (audit/BASE_LAYER_GATE.md). Fires only on ENABLE, and
    // only when no everyday schedule is visible. Informational: 'Enable
    // anyway' proceeds, a dismissal proceeds, and ANY failure proceeds. It
    // must never block a customer from a feature they already use.
    if (value) {
      final gateUid = ref.read(authStateProvider).maybeWhen(
            data: (u) => u?.uid ?? '',
            orElse: () => '',
          );
      if (gateUid.isNotEmpty && context.mounted) {
        final proceed = await maybeWarnNoBaseLayer(
          context: context,
          ref: ref,
          uid: gateUid,
          onSetUpSchedule: () => context.push(AppRoutes.schedule),
        );
        if (!proceed) return;
      }
    }
    try {
      await ref
          .read(gameDayAutopilotNotifierProvider.notifier)
          .toggleAutopilot(
            teamSlug: config.teamSlug,
            enabled: value,
          );
    } catch (e, st) {
      debugPrint('[GameDayAutopilot] toggleAutopilot failed: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not update Game Day Autopilot for ${config.teamName}.',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  // ── Settings content (always visible; greyed by parent when autopilot off) ─

  Widget _buildSettingsContent(
    BuildContext context,
    WidgetRef ref,
    GameDayAutopilotConfig config,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Skip day games toggle
          _ToggleRow(
            icon: Icons.wb_sunny_outlined,
            label: 'Skip day games',
            value: config.skipDayGames,
            onChanged: (val) {
              ref
                  .read(gameDayAutopilotNotifierProvider.notifier)
                  .updateTeamSettings(
                    teamSlug: config.teamSlug,
                    skipDayGames: val,
                  );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 8),
            child: Text(
              'Skip games that are fully in daylight at your location',
              style: TextStyle(
                fontSize: 11,
                color: NexGenPalette.textMedium.withValues(alpha: 0.7),
              ),
            ),
          ),
          const Divider(height: 16, color: NexGenPalette.line),

          // 2. Design variety
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 18, color: NexGenPalette.cyan),
                const SizedBox(width: 10),
                const Text(
                  'Design variety',
                  style: TextStyle(
                    fontSize: 14,
                    color: NexGenPalette.textMedium,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: 'Autopilot generates 6 team-themed designs\n'
                      '(Solid, Chase, Breathe, Twinkle, etc.)\n'
                      'using your team\'s colors.',
                  child: Icon(Icons.help_outline,
                      size: 16,
                      color:
                          NexGenPalette.textMedium.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          _buildVarietyRadio(ref, config, AutopilotVarietyMode.rotating,
              'Rotate through team designs'),
          _buildVarietyRadio(ref, config, AutopilotVarietyMode.fixed,
              'Same pattern each game'),
          const Divider(height: 16, color: NexGenPalette.line),

          // 3. Motion style slider (storage-only for now; see config TODO)
          _buildMotionStyleSlider(ref, config),
          const Divider(height: 16, color: NexGenPalette.line),

          // 4. Lead time
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 18, color: NexGenPalette.cyan),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Lead time before game',
                    style: TextStyle(
                      fontSize: 14,
                      color: NexGenPalette.textMedium,
                    ),
                  ),
                ),
                _buildLeadTimePicker(ref, config),
              ],
            ),
          ),
          const Divider(height: 16, color: NexGenPalette.line),

          // 5. Refresh schedule button
          Center(
            child: TextButton.icon(
              onPressed: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Refreshing game schedule...'),
                    duration: Duration(seconds: 2),
                  ),
                );
                // Manual Refresh — bypass the 7-day weekly gate (#63 E5
                // Sub-Change D). Background timer + post-launch refresh
                // stay force:false so the gate fires as intended for
                // implicit refreshes.
                await ref
                    .read(gameDayAutopilotNotifierProvider.notifier)
                    .refreshAllCalendars(force: true);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Schedule refreshed!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh Schedule'),
              style: TextButton.styleFrom(
                foregroundColor: NexGenPalette.cyan,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMotionStyleSlider(
    WidgetRef ref,
    GameDayAutopilotConfig config,
  ) {
    final value = _motionStyleLocal ?? config.motionStyle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.speed_rounded,
                  size: 18, color: NexGenPalette.cyan),
              const SizedBox(width: 10),
              const Text(
                'Motion style',
                style: TextStyle(
                  fontSize: 14,
                  color: NexGenPalette.textMedium,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 4),
          child: Slider(
            value: value.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            activeColor: NexGenPalette.cyan,
            inactiveColor:
                NexGenPalette.textMedium.withValues(alpha: 0.3),
            onChanged: (v) => setState(() => _motionStyleLocal = v),
            onChangeEnd: (v) {
              _motionStyleDebounce?.cancel();
              _motionStyleDebounce =
                  Timer(const Duration(milliseconds: 300), () {
                ref
                    .read(gameDayAutopilotNotifierProvider.notifier)
                    .setMotionStyle(teamSlug: config.teamSlug, value: v)
                    .catchError((e, st) {
                  debugPrint('[GameDay] setMotionStyle failed: $e\n$st');
                });
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 28, right: 16, bottom: 4),
          child: Row(
            children: [
              Text(
                'Static',
                style: TextStyle(
                  fontSize: 11,
                  color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              Text(
                'Fast Motion',
                style: TextStyle(
                  fontSize: 11,
                  color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVarietyRadio(
    WidgetRef ref,
    GameDayAutopilotConfig config,
    AutopilotVarietyMode mode,
    String label,
  ) {
    return InkWell(
      onTap: () {
        ref
            .read(gameDayAutopilotNotifierProvider.notifier)
            .updateTeamSettings(
              teamSlug: config.teamSlug,
              designVariety: mode,
            );
      },
      child: Padding(
        padding: const EdgeInsets.only(left: 28),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 32,
              child: Radio<AutopilotVarietyMode>(
                value: mode,
                groupValue: config.designVariety,
                onChanged: (val) {
                  if (val == null) return;
                  ref
                      .read(gameDayAutopilotNotifierProvider.notifier)
                      .updateTeamSettings(
                        teamSlug: config.teamSlug,
                        designVariety: val,
                      );
                },
                activeColor: NexGenPalette.cyan,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: config.designVariety == mode
                    ? NexGenPalette.textHigh
                    : NexGenPalette.textMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeadTimePicker(
    WidgetRef ref,
    GameDayAutopilotConfig config,
  ) {
    final minutes = config.effectiveLeadTimeMinutes;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: minutes > 0
                ? () => _setLeadTime(ref, config, (minutes - 15).clamp(0, 180))
                : null,
            child: Icon(Icons.remove,
                size: 16,
                color: minutes > 0
                    ? NexGenPalette.textHigh
                    : NexGenPalette.textMedium.withValues(alpha: 0.3)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${minutes}m',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: NexGenPalette.textHigh,
              ),
            ),
          ),
          InkWell(
            onTap: minutes < 180
                ? () =>
                    _setLeadTime(ref, config, (minutes + 15).clamp(0, 180))
                : null,
            child: Icon(Icons.add,
                size: 16,
                color: minutes < 180
                    ? NexGenPalette.textHigh
                    : NexGenPalette.textMedium.withValues(alpha: 0.3)),
          ),
        ],
      ),
    );
  }

  void _setLeadTime(
    WidgetRef ref,
    GameDayAutopilotConfig config,
    int minutes,
  ) {
    ref
        .read(gameDayAutopilotNotifierProvider.notifier)
        .updateTeamSettings(
          teamSlug: config.teamSlug,
          leadTimeMinutesOverride: minutes,
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

  /// W3 — the account's readiness verdict.
  ///
  /// Consulted for the UPCOMING branch ONLY. Live and final are reports of
  /// fact and cannot be wrong about the future; the pre-game text is the only
  /// promise this badge makes, so it is the only one the gate can withdraw.
  final GateStatus gate;

  const _GameStatusBadge({required this.game, this.gate = GateStatus.unknown});

  @override
  Widget build(BuildContext context) {
    final isLive =
        game.status == GameStatus.inProgress ||
        game.status == GameStatus.halftime;
    final isFinal = game.status == GameStatus.final_;
    // Only an upcoming game can be gated — see the field doc.
    final gatedUpcoming = !isLive &&
        !isFinal &&
        upcomingPromiseFor(gate) == UpcomingPromise.gated;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isLive
            ? Colors.green.withValues(alpha: 0.2)
            : isFinal || gatedUpcoming
                ? NexGenPalette.textMedium.withValues(alpha: 0.15)
                : NexGenPalette.cyan.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLive
              ? Colors.green.withValues(alpha: 0.4)
              : isFinal || gatedUpcoming
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
                    : gatedUpcoming
                        ? kGatedBadgeLabel
                        : 'Today',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isLive
                  ? Colors.green
                  : isFinal
                      ? NexGenPalette.textMedium
                      // Gated reads as muted, not as the confident cyan that
                      // says "this is happening tonight".
                      : gatedUpcoming
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
  String? _categoryFilter;

  // Category chips group leagues by sport so WNBA sits next to NBA under
  // "Basketball" and NWSL next to MLS under "Soccer".
  static final List<({String label, Set<SportType> sports})> _categories = [
    (label: 'Football', sports: {SportType.nfl, SportType.ncaaFB}),
    (
      label: 'Basketball',
      sports: {SportType.nba, SportType.wnba, SportType.ncaaMB},
    ),
    (label: 'Baseball', sports: {SportType.mlb}),
    (label: 'Hockey', sports: {SportType.nhl}),
    (
      label: 'Soccer',
      sports: {
        SportType.mls,
        SportType.nwsl,
        SportType.fifa,
        SportType.championsLeague,
      },
    ),
  ];

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
    if (_categoryFilter != null) {
      final allowed = _categories
              .firstWhere((c) => c.label == _categoryFilter)
              .sports;
      teams = teams.where((e) => allowed.contains(e.value.sport)).toList();
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
                selected: _categoryFilter == null,
                onTap: () => setState(() => _categoryFilter = null),
              ),
              for (final category in _categories)
                _FilterChip(
                  label: category.label,
                  selected: _categoryFilter == category.label,
                  onTap: () =>
                      setState(() => _categoryFilter = category.label),
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
            // Bottom padding clears the persistent GlassDockNavBar so the
            // last team rows (e.g. the bottom Tigers entries) aren't
            // hidden behind it and can be tapped.
            padding: EdgeInsets.fromLTRB(
                16, 0, 16, navBarTotalHeight(context) + 16),
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
    // Capture messenger before any awaits — context may be unmounted by the
    // time the future resolves if the bottom sheet is dismissed mid-flight.
    final messenger = ScaffoldMessenger.of(context);
    try {
      debugPrint('[GameDay] Adding team: $slug (${team.teamName})');
      // Add the team with autopilot OFF — user must explicitly opt in
      // via the Autopilot toggle on the team card.
      await ref
          .read(gameDayAutopilotNotifierProvider.notifier)
          .toggleAutopilot(teamSlug: slug, enabled: false);

      if (!context.mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${team.teamName} added to Game Day!'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e, st) {
      debugPrint('[GameDay] Failed to add team $slug: $e\n$st');
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not add ${team.teamName}: $e'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }
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
// Glass app bar delegate (pinned header that keeps its blur under scroll)
// ===========================================================================

class _GlassAppBarDelegate extends SliverPersistentHeaderDelegate {
  final GlassAppBar child;
  final double topPadding;

  _GlassAppBarDelegate({required this.child, required this.topPadding});

  @override
  double get minExtent => child.preferredSize.height + topPadding;

  @override
  double get maxExtent => child.preferredSize.height + topPadding;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Pad the AppBar down by the system status bar height so the leading
    // back button isn't hidden under the notch / status bar.
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _GlassAppBarDelegate oldDelegate) =>
      child != oldDelegate.child || topPadding != oldDelegate.topPadding;
}
