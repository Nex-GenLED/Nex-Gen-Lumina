import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme.dart';
import '../../../widgets/glass_app_bar.dart';
import '../../../widgets/premium_card.dart';
import '../../../widgets/section_header.dart';
import '../../site/site_providers.dart';
import '../../wled/zone_providers.dart';
import '../data/team_colors.dart';
import '../models/score_alert_config.dart';
import '../models/score_alert_event.dart';
import '../models/sport_type.dart';
import '../providers/sports_alert_providers.dart';
import '../services/alert_trigger_service.dart';

// ---------------------------------------------------------------------------
// Sport-specific sensitivity options
// ---------------------------------------------------------------------------

/// Returns the available sensitivity choices for a given sport.
List<_SensitivityOption> _sensitivityOptions(SportType sport) => switch (sport) {
      SportType.nfl => [
          const _SensitivityOption(
            value: AlertSensitivity.allEvents,
            label: 'All Events',
            description: 'Touchdowns, field goals, safeties',
          ),
          const _SensitivityOption(
            value: AlertSensitivity.majorOnly,
            label: 'Scores Only',
            description: 'All scoring plays',
          ),
          const _SensitivityOption(
            value: AlertSensitivity.clutchOnly,
            label: 'Touchdowns Only',
            description: 'Only touchdowns trigger lights',
          ),
        ],
      SportType.nba => [
          const _SensitivityOption(
            value: AlertSensitivity.allEvents,
            label: 'Quarter Wins + Clutch',
            description: 'Quarter-end leads and clutch baskets',
          ),
          const _SensitivityOption(
            value: AlertSensitivity.clutchOnly,
            label: 'Clutch Time Only',
            description: 'Only during close, late-game moments',
          ),
        ],
      SportType.mlb => [
          const _SensitivityOption(
            value: AlertSensitivity.allEvents,
            label: 'Every Run',
            description: 'Light up on every run scored',
          ),
          const _SensitivityOption(
            value: AlertSensitivity.majorOnly,
            label: 'Major Plays Only',
            description: 'Multi-run innings and big moments',
          ),
        ],
      SportType.nhl || SportType.mls => [
          const _SensitivityOption(
            value: AlertSensitivity.allEvents,
            label: 'Every Goal',
            description: 'Light show on every goal',
          ),
        ],
    };

class _SensitivityOption {
  final AlertSensitivity value;
  final String label;
  final String description;
  const _SensitivityOption({
    required this.value,
    required this.label,
    required this.description,
  });
}

/// Default preview event type per sport.
AlertEventType _previewEventType(SportType sport) => switch (sport) {
      SportType.nfl => AlertEventType.touchdown,
      SportType.nba => AlertEventType.clutchBasket,
      SportType.mlb => AlertEventType.run,
      SportType.nhl => AlertEventType.goal,
      SportType.mls => AlertEventType.goal,
    };

String _previewLabel(SportType sport) => switch (sport) {
      SportType.nfl => 'Preview Touchdown Animation',
      SportType.nba => 'Preview Clutch Basket Animation',
      SportType.mlb => 'Preview Run Animation',
      SportType.nhl => 'Preview Goal Animation',
      SportType.mls => 'Preview Goal Animation',
    };

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ZoneAssignmentScreen extends ConsumerStatefulWidget {
  const ZoneAssignmentScreen({super.key, required this.teamSlug});
  final String teamSlug;

  @override
  ConsumerState<ZoneAssignmentScreen> createState() =>
      _ZoneAssignmentScreenState();
}

class _ZoneAssignmentScreenState extends ConsumerState<ZoneAssignmentScreen> {
  late AlertSensitivity _sensitivity;
  final Set<int> _selectedChannelIds = {};
  bool _allZones = true;

  @override
  void initState() {
    super.initState();
    final team = kTeamColors[widget.teamSlug];
    final options = _sensitivityOptions(team?.sport ?? SportType.nfl);
    _sensitivity = options.first.value;
  }

  @override
  Widget build(BuildContext context) {
    final team = kTeamColors[widget.teamSlug];
    if (team == null) {
      return Scaffold(
        appBar: const GlassAppBar(title: Text('Team Not Found')),
        body: const Center(child: Text('Unknown team')),
      );
    }

    final channels = ref.watch(deviceChannelsProvider);
    final options = _sensitivityOptions(team.sport);

    return Scaffold(
      appBar: GlassAppBar(title: Text('Set Up ${team.teamName}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          // ── Color preview bar ──
          _ColorPreviewBar(team: team),

          const SizedBox(height: 24),

          // ── Zones section ──
          if (channels.length > 1) ...[
            SectionHeader(
              title: 'Zones',
              icon: Icons.lightbulb_outline,
              iconColor: NexGenPalette.cyan,
              padding: const EdgeInsets.only(bottom: 12),
            ),

            PremiumCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // "All zones" toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('All zones'),
                    subtitle: Text(
                      'Light up every channel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: NexGenPalette.textMedium,
                          ),
                    ),
                    value: _allZones,
                    activeThumbColor: NexGenPalette.cyan,
                    activeTrackColor:
                        NexGenPalette.cyan.withValues(alpha: 0.3),
                    onChanged: (v) {
                      setState(() {
                        _allZones = v;
                        if (v) _selectedChannelIds.clear();
                      });
                    },
                  ),

                  // Individual channel checkboxes (when "all zones" is off)
                  if (!_allZones) ...[
                    const Divider(color: NexGenPalette.line, height: 16),
                    ...channels.map((ch) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(ch.name),
                          subtitle: Text(
                            '${ch.stop - ch.start} LEDs',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: NexGenPalette.textMedium),
                          ),
                          value: _selectedChannelIds.contains(ch.id),
                          activeColor: NexGenPalette.cyan,
                          checkColor: Colors.black,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedChannelIds.add(ch.id);
                              } else {
                                _selectedChannelIds.remove(ch.id);
                              }
                            });
                          },
                        )),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],

          // ── Alert sensitivity section ──
          if (options.length > 1) ...[
            SectionHeader(
              title: 'Alert Sensitivity',
              icon: Icons.tune,
              iconColor: NexGenPalette.violet,
              padding: const EdgeInsets.only(bottom: 12),
            ),

            PremiumCard(
              child: RadioGroup<AlertSensitivity>(
                groupValue: _sensitivity,
                onChanged: (v) {
                  if (v != null) setState(() => _sensitivity = v);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: options
                      .map((opt) => RadioListTile<AlertSensitivity>(
                            contentPadding: EdgeInsets.zero,
                            title: Text(opt.label),
                            subtitle: Text(
                              opt.description,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: NexGenPalette.textMedium),
                            ),
                            value: opt.value,
                          ))
                      .toList(),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],

          // ── Preview section ──
          SectionHeader(
            title: 'Preview',
            icon: Icons.play_circle_outline,
            iconColor: NexGenPalette.amber,
            padding: const EdgeInsets.only(bottom: 12),
          ),

          OutlinedButton.icon(
            onPressed: () => _firePreview(team),
            icon: const Icon(Icons.flash_on, size: 18),
            label: Text(_previewLabel(team.sport)),
            style: OutlinedButton.styleFrom(
              foregroundColor: NexGenPalette.amber,
              side: BorderSide(
                  color: NexGenPalette.amber.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),

          const SizedBox(height: 32),

          // ── Save button ──
          FilledButton.icon(
            onPressed: () => _save(team),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Save Alert'),
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              minimumSize: const Size(double.infinity, 52),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Preview animation ──

  void _firePreview(TeamColors team) {
    final ips = ref.read(activeAreaControllerIpsProvider);
    if (ips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No controllers connected')),
      );
      return;
    }

    final trigger = AlertTriggerService(controllerIps: ips);
    final event = ScoreAlertEvent(
      teamSlug: widget.teamSlug,
      sport: team.sport,
      eventType: _previewEventType(team.sport),
      pointsScored: team.sport == SportType.nfl ? 6 : 1,
      gameId: 'preview_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
    );

    final config = ScoreAlertConfig(
      id: 'preview',
      teamSlug: widget.teamSlug,
      sport: team.sport,
      sensitivity: _sensitivity,
      assignedZoneIds: _resolveZoneIds(),
    );

    trigger.handleAlertEvent(event, config);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Playing ${team.teamName} animation...'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Save ──

  void _save(TeamColors team) {
    final config = ScoreAlertConfig(
      id: '${widget.teamSlug}_${DateTime.now().millisecondsSinceEpoch}',
      teamSlug: widget.teamSlug,
      sport: team.sport,
      sensitivity: _sensitivity,
      assignedZoneIds: _resolveZoneIds(),
      createdAt: DateTime.now(),
    );

    ref.read(sportsAlertConfigsProvider.notifier).addConfig(config);

    // Pop back to the sports alerts screen (pop team picker + this screen).
    Navigator.of(context)
      ..pop() // pop ZoneAssignmentScreen
      ..pop(); // pop TeamPickerScreen (if navigated from there)
  }

  List<String> _resolveZoneIds() {
    if (_allZones) return const [];
    return _selectedChannelIds.map((id) => id.toString()).toList();
  }
}

// ---------------------------------------------------------------------------
// Color preview bar
// ---------------------------------------------------------------------------

class _ColorPreviewBar extends StatelessWidget {
  const _ColorPreviewBar({required this.team});
  final TeamColors team;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: team.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            // Primary color half
            Expanded(
              child: Container(
                color: team.primary,
                alignment: Alignment.center,
                child: Text(
                  'PRIMARY',
                  style: TextStyle(
                    color: _contrastText(team.primary),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            // Secondary color half
            Expanded(
              child: Container(
                color: team.secondary,
                alignment: Alignment.center,
                child: Text(
                  'SECONDARY',
                  style: TextStyle(
                    color: _contrastText(team.secondary),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns black or white text depending on color luminance.
  Color _contrastText(Color color) {
    return color.computeLuminance() > 0.4 ? Colors.black : Colors.white;
  }
}
