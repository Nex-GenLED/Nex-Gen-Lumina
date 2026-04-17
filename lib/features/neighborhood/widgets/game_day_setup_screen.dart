import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app_colors.dart';
import '../../../theme.dart';
import '../../../utils/time_format.dart';
import '../../autopilot/game_day_autopilot_config.dart';
import '../../autopilot/game_day_autopilot_providers.dart';
import '../../autopilot/game_day_autopilot_service.dart';
import '../../sports_alerts/data/team_colors.dart';
import '../../sports_alerts/models/sport_type.dart';
import '../../wled/wled_models.dart';
import '../neighborhood_models.dart';
import '../neighborhood_providers.dart';

// ═════════════════════════════════════════════════════════════════════════════
// GAME DAY SYNC CONFIGURATION
// ═════════════════════════════════════════════════════════════════════════════

/// Configuration for a Game Day sync session.
class GameDaySyncConfig {
  final String teamSlug;
  final String teamName;
  final Color primaryColor;
  final Color secondaryColor;
  final SportType sport;
  final String espnTeamId;
  final int effectId;
  final int speed;
  final int intensity;
  final int brightness;
  final bool scoreCelebrationEnabled;
  final int celebrationDurationSeconds;

  const GameDaySyncConfig({
    required this.teamSlug,
    required this.teamName,
    required this.primaryColor,
    required this.secondaryColor,
    required this.sport,
    required this.espnTeamId,
    this.effectId = 0,
    this.speed = 128,
    this.intensity = 128,
    this.brightness = 200,
    this.scoreCelebrationEnabled = true,
    this.celebrationDurationSeconds = 15,
  });

  GameDaySyncConfig copyWith({
    int? effectId,
    int? speed,
    int? intensity,
    int? brightness,
    bool? scoreCelebrationEnabled,
    int? celebrationDurationSeconds,
  }) {
    return GameDaySyncConfig(
      teamSlug: teamSlug,
      teamName: teamName,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      sport: sport,
      espnTeamId: espnTeamId,
      effectId: effectId ?? this.effectId,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      brightness: brightness ?? this.brightness,
      scoreCelebrationEnabled:
          scoreCelebrationEnabled ?? this.scoreCelebrationEnabled,
      celebrationDurationSeconds:
          celebrationDurationSeconds ?? this.celebrationDurationSeconds,
    );
  }

  /// Build a ComplementTheme from the team colors.
  ComplementTheme toComplementTheme() {
    return ComplementTheme(
      id: 'gameday_$teamSlug',
      name: 'Game Day - $teamName',
      description: '${sport.displayName} team colors',
      icon: _sportIcon(sport),
      themeColors: [
        primaryColor.value & 0xFFFFFF,
        secondaryColor.value & 0xFFFFFF,
      ],
      recommendedEffectId: effectId,
    );
  }

  /// Build a SyncPatternAssignment from this config.
  SyncPatternAssignment toPatternAssignment() {
    return SyncPatternAssignment(
      name: 'Game Day - $teamName',
      effectId: effectId,
      colors: [
        primaryColor.value & 0xFFFFFF,
        secondaryColor.value & 0xFFFFFF,
      ],
      speed: speed,
      intensity: intensity,
      brightness: brightness,
    );
  }

  Map<String, dynamic> toJson() => {
        'teamSlug': teamSlug,
        'teamName': teamName,
        'primaryColor': primaryColor.value,
        'secondaryColor': secondaryColor.value,
        'sport': sport.toJson(),
        'espnTeamId': espnTeamId,
        'effectId': effectId,
        'speed': speed,
        'intensity': intensity,
        'brightness': brightness,
        'scoreCelebrationEnabled': scoreCelebrationEnabled,
        'celebrationDurationSeconds': celebrationDurationSeconds,
      };

  factory GameDaySyncConfig.fromJson(Map<String, dynamic> json) {
    return GameDaySyncConfig(
      teamSlug: json['teamSlug'] as String,
      teamName: json['teamName'] as String,
      primaryColor: Color(json['primaryColor'] as int),
      secondaryColor: Color(json['secondaryColor'] as int),
      sport: SportType.fromJson(json['sport'] as String),
      espnTeamId: json['espnTeamId'] as String,
      effectId: json['effectId'] as int? ?? 0,
      speed: json['speed'] as int? ?? 128,
      intensity: json['intensity'] as int? ?? 128,
      brightness: json['brightness'] as int? ?? 200,
      scoreCelebrationEnabled:
          json['scoreCelebrationEnabled'] as bool? ?? true,
      celebrationDurationSeconds:
          json['celebrationDurationSeconds'] as int? ?? 15,
    );
  }

  static IconData _sportIcon(SportType sport) => switch (sport) {
        SportType.nfl || SportType.ncaaFB => Icons.sports_football,
        SportType.nba || SportType.ncaaMB => Icons.sports_basketball,
        SportType.mlb => Icons.sports_baseball,
        SportType.nhl => Icons.sports_hockey,
        SportType.mls || SportType.fifa || SportType.championsLeague => Icons.sports_soccer,
      };
}

// ═════════════════════════════════════════════════════════════════════════════
// PROVIDERS
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
// GAME DAY SETUP SCREEN
// ═════════════════════════════════════════════════════════════════════════════

/// Full-screen Game Day setup flow:
///   Step 1: Team selection
///   Step 2: Effect picker + score celebration toggle
///
/// Returns a [GameDaySyncConfig] via Navigator.pop when the user confirms.
class GameDaySetupScreen extends ConsumerStatefulWidget {
  /// If true, the host can push the team to the whole group.
  final bool isHost;

  const GameDaySetupScreen({super.key, this.isHost = false});

  @override
  ConsumerState<GameDaySetupScreen> createState() => _GameDaySetupScreenState();
}

class _GameDaySetupScreenState extends ConsumerState<GameDaySetupScreen> {
  final _searchController = TextEditingController();

  // Step 1: Team selection
  String? _selectedSlug;
  TeamColors? _selectedTeam;

  // Step 2: Effect + celebration config
  int _selectedEffectId = 0; // Solid
  int _speed = 128;
  int _intensity = 128;
  int _brightness = 200;
  bool _scoreCelebration = true;
  int _celebrationDuration = 15;

  bool get _isStep2 => _selectedTeam != null;

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
                _selectedSlug = null;
                _selectedTeam = null;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          _isStep2 ? _selectedTeam!.teamName : 'Game Day Setup',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _isStep2 ? _buildStep2() : _buildStep1(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1: Team selection
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

        // Sport filter chips
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _SportChip(
                label: 'ALL',
                selected: activeSport == null,
                onTap: () =>
                    ref.read(_gameDaySportFilterProvider.notifier).state = null,
              ),
              ...SportType.values.map((s) => _SportChip(
                    label: s.displayName,
                    selected: activeSport == s,
                    onTap: () => ref
                        .read(_gameDaySportFilterProvider.notifier)
                        .state = s,
                  )),
            ],
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
                  // Bottom padding clears the GlassDockNavBar so the
                  // last team row isn't hidden behind the dock.
                  padding: EdgeInsets.fromLTRB(
                      16, 4, 16, navBarTotalHeight(context) + 16),
                  itemCount: teams.length,
                  itemBuilder: (context, i) {
                    final entry = teams[i];
                    return _GameDayTeamRow(
                      slug: entry.key,
                      team: entry.value,
                      onTap: () {
                        setState(() {
                          _selectedSlug = entry.key;
                          _selectedTeam = entry.value;
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2: Effect picker + Score celebration
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStep2() {
    final team = _selectedTeam!;

    // Effects well-suited for team colors on rooflines
    final effects = <int, String>{
      0: 'Solid',
      2: 'Breathe',
      28: 'Chase',
      77: 'Meteor',
      3: 'Wipe',
      15: 'Running',
      80: 'Ripple',
      106: 'Flow',
      10: 'Scan',
      65: 'Colorloop',
    };

    return ListView(
      // Bottom padding clears the GlassDockNavBar so step 2's CTA
      // ("Continue") at the end of this list isn't hidden behind it.
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

        // Effect selector
        Text(
          'Choose an Effect',
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: effects.entries.map((e) {
            final isSelected = _selectedEffectId == e.key;
            return ChoiceChip(
              label: Text(e.value),
              selected: isSelected,
              onSelected: (sel) {
                if (sel) setState(() => _selectedEffectId = e.key);
              },
              selectedColor: team.primary.withValues(alpha: 0.3),
              backgroundColor: Colors.grey.shade800,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade400,
              ),
              side: BorderSide(
                color: isSelected ? team.primary : Colors.grey.shade700,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Preview swatch
        Text(
          'Preview',
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _selectedEffectId == 0
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
          alignment: Alignment.center,
          child: Text(
            kEffectNames[_selectedEffectId] ?? 'Effect',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Speed / Intensity / Brightness sliders
        if (_selectedEffectId != 0) ...[
          _buildSlider('Speed', _speed, (v) => setState(() => _speed = v)),
          _buildSlider(
              'Intensity', _intensity, (v) => setState(() => _intensity = v)),
        ],
        _buildSlider(
            'Brightness', _brightness, (v) => setState(() => _brightness = v)),
        const SizedBox(height: 20),

        // ── Score Celebration toggle ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.grey.shade900.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _scoreCelebration
                  ? team.primary.withValues(alpha: 0.4)
                  : Colors.grey.shade800,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.celebration,
                      color:
                          _scoreCelebration ? team.primary : Colors.grey.shade500,
                      size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Score Celebration',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Flash team colors when ${team.teamName} scores',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _scoreCelebration,
                    onChanged: (v) => setState(() => _scoreCelebration = v),
                    activeColor: team.primary,
                  ),
                ],
              ),
              if (_scoreCelebration) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Duration',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12),
                    ),
                    Expanded(
                      child: Slider(
                        value: _celebrationDuration.toDouble(),
                        min: 5,
                        max: 30,
                        divisions: 5,
                        activeColor: team.primary,
                        inactiveColor: Colors.grey.shade800,
                        onChanged: (v) =>
                            setState(() => _celebrationDuration = v.round()),
                      ),
                    ),
                    Text(
                      '${_celebrationDuration}s',
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 12),
                    ),
                  ],
                ),
                // Test button (debug mode only)
                if (kDebugMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => triggerScoreCelebration(
                        _selectedSlug!,
                        ref,
                      ),
                      icon: const Icon(Icons.bug_report, size: 16),
                      label: const Text('Test Score Trigger'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Game Day Autopilot toggle ──
        _GameDayAutopilotSection(
          teamSlug: _selectedSlug!,
          team: team,
        ),
        const SizedBox(height: 24),

        // ── Action buttons ──
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check),
            label: Text(
              widget.isHost ? 'Set for Group' : 'Apply to My House',
            ),
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

        // Host: push to whole neighborhood
        if (widget.isHost) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _confirm(pushToGroup: true),
              icon: const Icon(Icons.groups, size: 20),
              label: const Text('Set Game Day for Whole Neighborhood'),
              style: OutlinedButton.styleFrom(
                foregroundColor: team.primary,
                side: BorderSide(color: team.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSlider(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(label,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            activeColor: _selectedTeam?.primary ?? Colors.cyan,
            inactiveColor: Colors.grey.shade800,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('$value',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              textAlign: TextAlign.end),
        ),
      ],
    );
  }

  void _confirm({bool pushToGroup = false}) {
    final config = GameDaySyncConfig(
      teamSlug: _selectedSlug!,
      teamName: _selectedTeam!.teamName,
      primaryColor: _selectedTeam!.primary,
      secondaryColor: _selectedTeam!.secondary,
      sport: _selectedTeam!.sport,
      espnTeamId: _selectedTeam!.espnTeamId,
      effectId: _selectedEffectId,
      speed: _speed,
      intensity: _intensity,
      brightness: _brightness,
      scoreCelebrationEnabled: _scoreCelebration,
      celebrationDurationSeconds: _celebrationDuration,
    );

    Navigator.of(context).pop(_GameDayResult(config, pushToGroup));
  }
}

/// Return value from GameDaySetupScreen.
class _GameDayResult {
  final GameDaySyncConfig config;
  final bool pushToGroup;
  const _GameDayResult(this.config, this.pushToGroup);
}

// ═════════════════════════════════════════════════════════════════════════════
// GAME DAY AUTOPILOT SECTION
// ═════════════════════════════════════════════════════════════════════════════

/// Autopilot toggle section shown in Step 2 of GameDaySetupScreen.
///
/// When toggled ON, shows a confirmation card with next game info and
/// the selected design. Writes a [GameDayAutopilotConfig] to Firestore.
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
          // Header row with toggle
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

          // Expanded details when enabled
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
                  // Next game info
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

                  // Design info
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

                  // Active session status
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

  // Build a celebration sync command: rapid flash of team colors
  final groupId = ref.read(activeNeighborhoodIdProvider);
  if (groupId == null) {
    debugPrint('[GameDay] No active neighborhood group for celebration');
    return;
  }

  final service = ref.read(neighborhoodServiceProvider);
  final members =
      ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
  if (members.isEmpty) return;

  // Celebration effect: Fireworks (fx:88) with team colors
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
    memberDelays: {for (var m in members) m.oderId: 0}, // Simultaneous
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

class _GameDayTeamRow extends StatelessWidget {
  final String slug;
  final TeamColors team;
  final VoidCallback onTap;

  const _GameDayTeamRow({
    required this.slug,
    required this.team,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sportEmoji = switch (team.sport) {
      SportType.nfl || SportType.ncaaFB => '\u{1F3C8}',
      SportType.nba || SportType.ncaaMB => '\u{1F3C0}',
      SportType.mlb => '\u{26BE}',
      SportType.nhl => '\u{1F3D2}',
      SportType.mls || SportType.fifa || SportType.championsLeague => '\u{26BD}',
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Row(
            children: [
              // Team color icon
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
              // Team name + sport
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
                    Text(
                      team.sport.displayName,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Color swatches
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
              Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PUBLIC API: Launch Game Day setup and return config
// ═════════════════════════════════════════════════════════════════════════════

/// Opens the Game Day Setup screen and returns the selected config.
/// Returns null if the user backs out.
Future<GameDaySyncConfig?> showGameDaySetup(
  BuildContext context, {
  bool isHost = false,
}) async {
  final result = await Navigator.of(context).push<_GameDayResult>(
    MaterialPageRoute(
      builder: (_) => GameDaySetupScreen(isHost: isHost),
    ),
  );
  return result?.config;
}

/// Opens Game Day setup and returns both config and whether to push to group.
Future<({GameDaySyncConfig? config, bool pushToGroup})> showGameDaySetupFull(
  BuildContext context, {
  bool isHost = false,
}) async {
  final result = await Navigator.of(context).push<_GameDayResult>(
    MaterialPageRoute(
      builder: (_) => GameDaySetupScreen(isHost: isHost),
    ),
  );
  return (
    config: result?.config,
    pushToGroup: result?.pushToGroup ?? false,
  );
}
