import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../../sports_alerts/data/team_colors.dart';
import '../../sports_alerts/models/sport_type.dart';
import '../models/sync_event.dart';
import '../neighborhood_providers.dart';
import '../providers/sync_event_providers.dart';
import 'battery_optimization_prompt.dart';
import 'season_schedule_picker.dart';

// ═════════════════════════════════════════════════════════════════════════════
// SYNC EVENT SETUP SCREEN
// ═════════════════════════════════════════════════════════════════════════════

/// Full setup flow for creating or editing an Autopilot Sync Event.
///
/// Steps:
/// 1. Select Neighborhood Sync group
/// 2. Select sport & team
/// 3. Choose trigger type (Game Start or Scheduled Time)
/// 4. Choose base pattern
/// 5. Choose celebration pattern + duration
/// 6. Set post-event behavior
/// 7. Review participants
/// 8. Save
class SyncEventSetupScreen extends ConsumerStatefulWidget {
  /// If non-null, we're editing an existing event.
  final SyncEvent? existingEvent;

  const SyncEventSetupScreen({super.key, this.existingEvent});

  @override
  ConsumerState<SyncEventSetupScreen> createState() =>
      _SyncEventSetupScreenState();
}

class _SyncEventSetupScreenState extends ConsumerState<SyncEventSetupScreen> {
  int _step = 0;
  final _nameController = TextEditingController();

  // Step 1 — Group
  String? _selectedGroupId;

  // Step 2 — Team
  SportType? _selectedSport;
  String? _selectedTeamSlug;
  String? _selectedTeamName;
  String? _selectedEspnTeamId;
  Color? _teamPrimaryColor;
  Color? _teamSecondaryColor;
  String _teamSearchQuery = '';

  // Step 3 — Trigger
  SyncEventTriggerType _triggerType = SyncEventTriggerType.gameStart;
  TimeOfDay _scheduledTimeOfDay = const TimeOfDay(hour: 19, minute: 0);
  DateTime _scheduledDate = DateTime.now();
  List<int> _repeatDays = [];

  // Step 4 — Base pattern
  int _baseEffectId = 0;
  int _baseSpeed = 128;
  int _baseIntensity = 128;
  int _baseBrightness = 200;

  // Step 5 — Celebration
  int _celebEffectId = 88; // Fireworks
  int _celebSpeed = 200;
  int _celebIntensity = 255;
  int _celebBrightness = 255;
  int _celebDuration = 15;

  // Step 6 — Post-event
  PostEventBehavior _postEventBehavior = PostEventBehavior.returnToAutopilot;

  // Step 7 — Recurring
  bool _isRecurring = false;

  // Season schedule
  bool _isSeasonSchedule = false;
  int? _seasonYear;
  Set<String> _excludedGameIds = {};

  bool get _isEditing => widget.existingEvent != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _populateFromExisting(widget.existingEvent!);
    }
  }

  void _populateFromExisting(SyncEvent event) {
    _nameController.text = event.name;
    _selectedGroupId = event.syncGroupId;
    _triggerType = event.triggerType;
    _selectedTeamSlug = event.teamId;
    _selectedEspnTeamId = event.espnTeamId;
    _baseEffectId = event.basePattern.effectId;
    _baseSpeed = event.basePattern.speed;
    _baseIntensity = event.basePattern.intensity;
    _baseBrightness = event.basePattern.brightness;
    _celebEffectId = event.celebrationPattern.effectId;
    _celebSpeed = event.celebrationPattern.speed;
    _celebIntensity = event.celebrationPattern.intensity;
    _celebBrightness = event.celebrationPattern.brightness;
    _celebDuration = event.celebrationDurationSeconds;
    _postEventBehavior = event.postEventBehavior;
    _repeatDays = List.from(event.repeatDays);
    _isRecurring = event.repeatDays.isNotEmpty;
    _isSeasonSchedule = event.isSeasonSchedule;
    _seasonYear = event.seasonYear;
    _excludedGameIds = Set.from(event.excludedGameIds);
    if (event.scheduledTime != null) {
      _scheduledDate = event.scheduledTime!;
      _scheduledTimeOfDay = TimeOfDay.fromDateTime(event.scheduledTime!);
    }

    // Look up team info
    if (event.teamId != null && kTeamColors.containsKey(event.teamId)) {
      final tc = kTeamColors[event.teamId]!;
      _selectedTeamName = tc.teamName;
      _teamPrimaryColor = tc.primary;
      _teamSecondaryColor = tc.secondary;
      // Parse sport from league string
      if (event.sportLeague != null) {
        _selectedSport = SportType.values.firstWhere(
          (s) => s.name.toUpperCase() == event.sportLeague!.toUpperCase(),
          orElse: () => SportType.nfl,
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Sync Event' : 'New Sync Event'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Step indicator
          _buildStepIndicator(),
          // Step content
          Expanded(child: _buildCurrentStep()),
          // Navigation buttons
          _buildNavButtons(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    const steps = [
      'Group',
      'Team',
      'Trigger',
      'Pattern',
      'Celebration',
      'Post-Event',
      'Review',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: List.generate(steps.length, (i) {
          final isActive = i == _step;
          final isDone = i < _step;
          return Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isDone
                      ? NexGenPalette.cyan
                      : isActive
                          ? NexGenPalette.cyan.withValues(alpha: 0.6)
                          : Colors.white12,
                  child: isDone
                      ? const Icon(Icons.check, size: 14, color: Colors.black)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isActive ? Colors.black : Colors.white54,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  steps[i],
                  style: TextStyle(
                    fontSize: 9,
                    color: isActive ? NexGenPalette.cyan : Colors.white38,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _buildGroupStep();
      case 1:
        return _buildTeamStep();
      case 2:
        return _buildTriggerStep();
      case 3:
        return _buildBasePatternStep();
      case 4:
        return _buildCelebrationStep();
      case 5:
        return _buildPostEventStep();
      case 6:
        return _buildReviewStep();
      default:
        return const SizedBox();
    }
  }

  // ── Step 0: Group Selection ────────────────────────────────────────

  Widget _buildGroupStep() {
    final groups = ref.watch(userNeighborhoodsProvider).valueOrNull ?? [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Event name
        TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Event Name',
            hintText: 'e.g., Chiefs Game Day',
            labelStyle: const TextStyle(color: Colors.white60),
            hintStyle: const TextStyle(color: Colors.white30),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.white24),
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: NexGenPalette.cyan),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Select Neighborhood Sync Group',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...groups.map((group) => _buildGroupTile(group)),
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'No neighborhood groups found.\nCreate or join a group first.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38),
            ),
          ),
      ],
    );
  }

  Widget _buildGroupTile(group) {
    final isSelected = _selectedGroupId == group.id;
    return Card(
      color: isSelected ? NexGenPalette.cyan.withValues(alpha: 0.15) : Colors.white10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: NexGenPalette.cyan)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Icon(
          Icons.home_work,
          color: isSelected ? NexGenPalette.cyan : Colors.white54,
        ),
        title: Text(
          group.name,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          '${group.memberCount} homes',
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: NexGenPalette.cyan)
            : null,
        onTap: () => setState(() => _selectedGroupId = group.id),
      ),
    );
  }

  // ── Step 1: Team Selection ─────────────────────────────────────────

  Widget _buildTeamStep() {
    final filteredTeams = kTeamColors.entries.where((entry) {
      if (_selectedSport != null) {
        if (!entry.key.startsWith(_selectedSport!.name)) return false;
      }
      if (_teamSearchQuery.isNotEmpty) {
        final q = _teamSearchQuery.toLowerCase();
        return entry.value.teamName.toLowerCase().contains(q) ||
            entry.key.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Sport filter chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: SportType.values.map((sport) {
                final isSelected = _selectedSport == sport;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(sport.displayName),
                    selected: isSelected,
                    selectedColor: NexGenPalette.cyan.withValues(alpha: 0.3),
                    checkmarkColor: NexGenPalette.cyan,
                    labelStyle: TextStyle(
                      color: isSelected ? NexGenPalette.cyan : Colors.white70,
                    ),
                    backgroundColor: Colors.white10,
                    onSelected: (_) => setState(() {
                      _selectedSport = isSelected ? null : sport;
                    }),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search teams...',
              hintStyle: const TextStyle(color: Colors.white30),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.white24),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: NexGenPalette.cyan),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (v) => setState(() => _teamSearchQuery = v),
          ),
        ),
        const SizedBox(height: 8),
        // Team list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filteredTeams.length,
            itemBuilder: (context, index) {
              final entry = filteredTeams[index];
              final slug = entry.key;
              final tc = entry.value;
              final isSelected = _selectedTeamSlug == slug;
              return Card(
                color: isSelected
                    ? NexGenPalette.cyan.withValues(alpha: 0.15)
                    : Colors.white10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: isSelected
                      ? const BorderSide(color: NexGenPalette.cyan)
                      : BorderSide.none,
                ),
                child: ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: tc.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: tc.secondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  title: Text(
                    tc.teamName,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    tc.sport.displayName,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle,
                          color: NexGenPalette.cyan)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedTeamSlug = slug;
                      _selectedTeamName = tc.teamName;
                      _selectedEspnTeamId = tc.espnTeamId;
                      _teamPrimaryColor = tc.primary;
                      _teamSecondaryColor = tc.secondary;
                      _selectedSport = tc.sport;
                      // Auto-set event name if empty
                      if (_nameController.text.isEmpty) {
                        _nameController.text = '${tc.teamName} Game Day';
                      }
                    });
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Step 2: Trigger Type ───────────────────────────────────────────

  Widget _buildTriggerStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'When should the sync start?',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 16),
        _buildTriggerOption(
          SyncEventTriggerType.gameStart,
          'Game Start',
          'Automatically starts when the game begins (recommended)',
          Icons.sports_football,
        ),
        _buildTriggerOption(
          SyncEventTriggerType.scheduledTime,
          'Specific Time',
          'Start at a fixed time you choose',
          Icons.schedule,
        ),
        _buildTriggerOption(
          SyncEventTriggerType.manual,
          'Manual',
          'Start manually from the app',
          Icons.touch_app,
        ),
        // ── Game Start: Season schedule option ──
        if (_triggerType == SyncEventTriggerType.gameStart &&
            _selectedEspnTeamId != null &&
            _selectedSport != null) ...[
          const SizedBox(height: 24),
          _buildSeasonScheduleSection(),
        ],

        if (_triggerType == SyncEventTriggerType.scheduledTime) ...[
          const SizedBox(height: 24),
          const Text(
            'Select Date & Time',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    '${_scheduledDate.month}/${_scheduledDate.day}/${_scheduledDate.year}',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _scheduledDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _scheduledDate = picked);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: Text(_scheduledTimeOfDay.format(context)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _scheduledTimeOfDay,
                    );
                    if (picked != null) {
                      setState(() => _scheduledTimeOfDay = picked);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Recurring toggle
          SwitchListTile(
            title: const Text(
              'Recurring',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              _isRecurring
                  ? 'Every game / selected days'
                  : 'One-time event',
              style: const TextStyle(color: Colors.white38),
            ),
            value: _isRecurring,
            activeColor: NexGenPalette.cyan,
            onChanged: (v) => setState(() => _isRecurring = v),
          ),
          if (_isRecurring) _buildDaySelector(),
        ],
      ],
    );
  }

  Widget _buildTriggerOption(
    SyncEventTriggerType type,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final isSelected = _triggerType == type;
    return Card(
      color: isSelected ? NexGenPalette.cyan.withValues(alpha: 0.15) : Colors.white10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: NexGenPalette.cyan)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Icon(icon,
            color: isSelected ? NexGenPalette.cyan : Colors.white54),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: NexGenPalette.cyan)
            : null,
        onTap: () => setState(() => _triggerType = type),
      ),
    );
  }

  Widget _buildDaySelector() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(7, (i) {
          final dayNum = i + 1;
          final isSelected = _repeatDays.contains(dayNum);
          return GestureDetector(
            onTap: () {
              setState(() {
                if (isSelected) {
                  _repeatDays.remove(dayNum);
                } else {
                  _repeatDays.add(dayNum);
                }
              });
            },
            child: CircleAvatar(
              radius: 18,
              backgroundColor:
                  isSelected ? NexGenPalette.cyan : Colors.white12,
              child: Text(
                days[i],
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? Colors.black : Colors.white54,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Season Schedule Section ──────────────────────────────────────────

  Widget _buildSeasonScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle: Every home game this season
        Container(
          decoration: BoxDecoration(
            color: _isSeasonSchedule
                ? (_teamPrimaryColor ?? NexGenPalette.cyan)
                    .withValues(alpha: 0.1)
                : Colors.white10,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isSeasonSchedule
                  ? (_teamPrimaryColor ?? NexGenPalette.cyan)
                      .withValues(alpha: 0.4)
                  : Colors.white12,
            ),
          ),
          child: SwitchListTile(
            title: const Text(
              'Every home game this season',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            subtitle: Text(
              _isSeasonSchedule
                  ? 'Auto-syncs on every home game day'
                  : 'Sync for next game only',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            secondary: Icon(
              Icons.calendar_month,
              color: _isSeasonSchedule
                  ? (_teamPrimaryColor ?? NexGenPalette.cyan)
                  : Colors.white38,
            ),
            value: _isSeasonSchedule,
            activeColor: _teamPrimaryColor ?? NexGenPalette.cyan,
            onChanged: (v) {
              setState(() {
                _isSeasonSchedule = v;
                if (v) {
                  _seasonYear =
                      currentSeasonYear(_selectedSport ?? SportType.nfl);
                }
              });
            },
          ),
        ),

        // Season schedule picker (when enabled)
        if (_isSeasonSchedule &&
            _selectedEspnTeamId != null &&
            _selectedSport != null) ...[
          const SizedBox(height: 16),
          SeasonSchedulePicker(
            espnTeamId: _selectedEspnTeamId!,
            teamName: _selectedTeamName ?? 'Team',
            sport: _selectedSport!,
            teamColor: _teamPrimaryColor ?? NexGenPalette.cyan,
            excludedGameIds: _excludedGameIds,
            onExcludedChanged: (excluded) {
              setState(() => _excludedGameIds = excluded);
            },
          ),
        ],
      ],
    );
  }

  // ── Step 3: Base Pattern ───────────────────────────────────────────

  Widget _buildBasePatternStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Base Pattern',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const Text(
          'This pattern plays on all homes during the event.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (_teamPrimaryColor != null) ...[
          // Show team color preview
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _teamPrimaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _teamSecondaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _selectedTeamName ?? 'Team Colors',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        _buildEffectPicker('Effect', _baseEffectId, (v) {
          setState(() => _baseEffectId = v);
        }),
        _buildSlider('Speed', _baseSpeed, (v) {
          setState(() => _baseSpeed = v);
        }),
        _buildSlider('Intensity', _baseIntensity, (v) {
          setState(() => _baseIntensity = v);
        }),
        _buildSlider('Brightness', _baseBrightness, (v) {
          setState(() => _baseBrightness = v);
        }),
      ],
    );
  }

  // ── Step 4: Celebration Pattern ────────────────────────────────────

  Widget _buildCelebrationStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Celebration Pattern',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const Text(
          'Fires when your team scores. All homes flash simultaneously.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _buildEffectPicker('Celebration Effect', _celebEffectId, (v) {
          setState(() => _celebEffectId = v);
        }),
        _buildSlider('Speed', _celebSpeed, (v) {
          setState(() => _celebSpeed = v);
        }),
        _buildSlider('Intensity', _celebIntensity, (v) {
          setState(() => _celebIntensity = v);
        }),
        _buildSlider('Brightness', _celebBrightness, (v) {
          setState(() => _celebBrightness = v);
        }),
        const SizedBox(height: 16),
        const Text(
          'Celebration Duration',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _celebDuration.toDouble(),
                min: 5,
                max: 30,
                divisions: 5,
                activeColor: NexGenPalette.cyan,
                inactiveColor: Colors.white12,
                onChanged: (v) =>
                    setState(() => _celebDuration = v.round()),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                '${_celebDuration}s',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Step 5: Post-Event Behavior ────────────────────────────────────

  Widget _buildPostEventStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'After the Event',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const Text(
          'What should happen when the game ends?',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 16),
        ...PostEventBehavior.values.map((behavior) {
          final isSelected = _postEventBehavior == behavior;
          String subtitle;
          IconData icon;
          switch (behavior) {
            case PostEventBehavior.returnToAutopilot:
              subtitle = 'Resume individual Autopilot schedules';
              icon = Icons.auto_awesome;
              break;
            case PostEventBehavior.stayOn:
              subtitle = 'Keep the last sync pattern running';
              icon = Icons.lightbulb;
              break;
            case PostEventBehavior.turnOff:
              subtitle = 'Turn off all lights';
              icon = Icons.power_settings_new;
              break;
          }
          return Card(
            color: isSelected
                ? NexGenPalette.cyan.withValues(alpha: 0.15)
                : Colors.white10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isSelected
                  ? const BorderSide(color: NexGenPalette.cyan)
                  : BorderSide.none,
            ),
            child: ListTile(
              leading: Icon(icon,
                  color: isSelected ? NexGenPalette.cyan : Colors.white54),
              title: Text(behavior.displayName,
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(subtitle,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
              trailing: isSelected
                  ? const Icon(Icons.check_circle, color: NexGenPalette.cyan)
                  : null,
              onTap: () => setState(() => _postEventBehavior = behavior),
            ),
          );
        }),
      ],
    );
  }

  // ── Step 6: Review ─────────────────────────────────────────────────

  Widget _buildReviewStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Review Sync Event',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 16),
        _buildReviewRow('Name', _nameController.text),
        _buildReviewRow('Team', _selectedTeamName ?? 'None'),
        _buildReviewRow('Trigger', _triggerType.displayName),
        if (_triggerType == SyncEventTriggerType.scheduledTime)
          _buildReviewRow('Time', _scheduledTimeOfDay.format(context)),
        _buildReviewRow('Celebration Duration', '${_celebDuration}s'),
        _buildReviewRow('Post-Event', _postEventBehavior.displayName),
        if (_isRecurring)
          _buildReviewRow('Repeat Days', _repeatDays.join(', ')),
        if (_isSeasonSchedule) ...[
          _buildReviewRow('Season', 'Every home game ($_seasonYear)'),
          if (_excludedGameIds.isNotEmpty)
            _buildReviewRow(
              'Excluded',
              '${_excludedGameIds.length} games skipped',
            ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Participants',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const SizedBox(height: 8),
        const Text(
          'Members who have opted in to Game Day syncs will automatically join this session.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildReviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Common Widgets ─────────────────────────────────────────────────

  Widget _buildEffectPicker(
    String label,
    int currentId,
    ValueChanged<int> onChanged,
  ) {
    // Simplified effect picker — shows common effects
    const effects = {
      0: 'Solid',
      2: 'Breathe',
      9: 'Chase',
      11: 'Rainbow',
      38: 'Chase Rainbow',
      44: 'Colorful',
      63: 'Pride',
      65: 'Running',
      88: 'Fireworks',
      101: 'Twinkle',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: effects.entries.map((e) {
            final isSelected = currentId == e.key;
            return ChoiceChip(
              label: Text(e.value),
              selected: isSelected,
              selectedColor: NexGenPalette.cyan.withValues(alpha: 0.3),
              checkmarkColor: NexGenPalette.cyan,
              labelStyle: TextStyle(
                color: isSelected ? NexGenPalette.cyan : Colors.white70,
                fontSize: 12,
              ),
              backgroundColor: Colors.white10,
              onSelected: (_) => onChanged(e.key),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSlider(String label, int value, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(color: Colors.white54)),
            const Spacer(),
            Text('$value', style: const TextStyle(color: Colors.white70)),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: 255,
          activeColor: NexGenPalette.cyan,
          inactiveColor: Colors.white12,
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────

  Widget _buildNavButtons() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (_step > 0)
            TextButton(
              onPressed: () => setState(() => _step--),
              child: const Text('Back', style: TextStyle(color: Colors.white54)),
            ),
          const Spacer(),
          if (_step < 6)
            FilledButton(
              onPressed: _canAdvance() ? () => setState(() => _step++) : null,
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
              ),
              child: const Text('Next'),
            ),
          if (_step == 6)
            FilledButton(
              onPressed: _saveEvent,
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
              ),
              child: Text(_isEditing ? 'Update' : 'Create Event'),
            ),
        ],
      ),
    );
  }

  bool _canAdvance() {
    switch (_step) {
      case 0:
        return _nameController.text.isNotEmpty && _selectedGroupId != null;
      case 1:
        return _selectedTeamSlug != null;
      case 2:
        if (_triggerType == SyncEventTriggerType.scheduledTime) {
          return true; // Date/time always have defaults
        }
        return true;
      default:
        return true;
    }
  }

  Future<void> _saveEvent() async {
    // Build scheduled time from date + time of day
    DateTime? scheduledTime;
    if (_triggerType == SyncEventTriggerType.scheduledTime) {
      scheduledTime = DateTime(
        _scheduledDate.year,
        _scheduledDate.month,
        _scheduledDate.day,
        _scheduledTimeOfDay.hour,
        _scheduledTimeOfDay.minute,
      );
    }

    // Build colors from team
    final colors = <int>[];
    if (_teamPrimaryColor != null) {
      colors.add(_teamPrimaryColor!.value & 0xFFFFFF);
    }
    if (_teamSecondaryColor != null) {
      colors.add(_teamSecondaryColor!.value & 0xFFFFFF);
    }
    if (colors.isEmpty) colors.add(0xFFFFFF);

    final event = SyncEvent(
      id: widget.existingEvent?.id ?? '',
      name: _nameController.text,
      syncGroupId: _selectedGroupId!,
      triggerType: _triggerType,
      sportLeague: _selectedSport?.name.toUpperCase(),
      teamId: _selectedTeamSlug,
      basePattern: PatternRef(
        name: '${_selectedTeamName ?? 'Team'} Base',
        effectId: _baseEffectId,
        colors: colors,
        speed: _baseSpeed,
        intensity: _baseIntensity,
        brightness: _baseBrightness,
      ),
      celebrationPattern: PatternRef(
        name: '${_selectedTeamName ?? 'Team'} Celebration',
        effectId: _celebEffectId,
        colors: colors,
        speed: _celebSpeed,
        intensity: _celebIntensity,
        brightness: _celebBrightness,
      ),
      celebrationDurationSeconds: _celebDuration,
      postEventBehavior: _postEventBehavior,
      scheduledTime: scheduledTime,
      repeatDays: _isRecurring ? _repeatDays : [],
      createdBy: '',
      createdAt: widget.existingEvent?.createdAt ?? DateTime.now(),
      espnTeamId: _selectedEspnTeamId,
      category: SyncEventCategory.gameDay,
      isSeasonSchedule: _isSeasonSchedule,
      seasonYear: _isSeasonSchedule ? _seasonYear : null,
      excludedGameIds: _isSeasonSchedule ? _excludedGameIds.toList() : [],
    );

    if (_isEditing) {
      await ref.read(syncEventNotifierProvider.notifier).updateSyncEvent(event);
    } else {
      await ref.read(syncEventNotifierProvider.notifier).createSyncEvent(event);
      // Show battery optimization prompt on first sync event creation (Android)
      if (mounted) {
        await showBatteryOptimizationPrompt(context);
      }
    }

    if (mounted) Navigator.of(context).pop(event);
  }
}

/// Convenience function to push the setup screen.
Future<SyncEvent?> showSyncEventSetup(
  BuildContext context, {
  SyncEvent? existingEvent,
}) {
  return Navigator.of(context).push<SyncEvent>(
    MaterialPageRoute(
      builder: (_) => SyncEventSetupScreen(existingEvent: existingEvent),
    ),
  );
}
