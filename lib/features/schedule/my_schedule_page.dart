import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/widgets/night_track_bar.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/schedule/sun_time_provider.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';

class MySchedulePage extends ConsumerWidget {
  const MySchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulesProvider);
    // Sun times used for rendering labels for Sunrise/Sunset triggers
    final userAsync = ref.watch(currentUserProfileProvider);
    final user = userAsync.maybeWhen(data: (u) => u, orElse: () => null);
    final hasCoords = (user?.latitude != null && user?.longitude != null);
    final sunAsync = hasCoords
        ? ref.watch(sunTimeProvider((lat: user!.latitude!, lon: user.longitude!)))
        : const AsyncValue.data(null);
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('My Schedule'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final ok = await ref.read(scheduleSyncServiceProvider).syncAll(ref, schedules);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? 'Schedules synced to controller'
                      : 'Could not sync to controller (schedules saved to cloud)'),
                  backgroundColor: ok ? Colors.green.shade700 : Colors.orange.shade700,
                ));
              }
            },
            icon: const Icon(Icons.cloud_upload_rounded, size: 18, color: Colors.white),
            label: const Text('Sync'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: ListView(
          children: [
            // Lumina AI card with autopilot toggle and schedule prompt
            const _AutopilotQuickToggle(),
            const SizedBox(height: 16),
            _WeeklyAgendaLarge(sunAsync: sunAsync),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: NexGenPalette.cyan,
        foregroundColor: Colors.black,
        onPressed: () => _openEditor(context, ref),
        child: const Icon(CupertinoIcons.add),
      ),
    );
  }

  void _openEditor(BuildContext context, WidgetRef ref) => showScheduleEditor(context, ref);
}

/// Unified Lumina AI card combining Autopilot controls and schedule prompt input.
/// Allows users to toggle autopilot, set preferences, and ask Lumina for schedule help.
class _AutopilotQuickToggle extends ConsumerStatefulWidget {
  const _AutopilotQuickToggle();

  @override
  ConsumerState<_AutopilotQuickToggle> createState() => _AutopilotQuickToggleState();
}

class _AutopilotQuickToggleState extends ConsumerState<_AutopilotQuickToggle> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _askLumina(BuildContext context) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Parse the user's natural language request to extract schedule parameters
      final scheduleData = await _parseScheduleRequest(text);

      if (scheduleData != null) {
        // Create the schedule item
        final newSchedule = ScheduleItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          timeLabel: scheduleData['timeLabel']!,
          repeatDays: scheduleData['repeatDays'] as List<String>,
          actionLabel: scheduleData['actionLabel']!,
          enabled: true,
        );

        // Add to schedules
        await ref.read(schedulesProvider.notifier).add(newSchedule);

        if (!mounted) return;

        // Show friendly confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(scheduleData['confirmation']!),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );

        _controller.clear();
      } else {
        // Fallback: couldn't parse the request automatically
        if (!mounted) return;
        setState(() => _error = 'I couldn\'t understand that request. Try something like "warm white every night at sunset"');
      }
    } catch (e) {
      debugPrint('Lumina schedule creation failed: $e');
      if (mounted) setState(() => _error = 'Lumina error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Parses natural language schedule requests into structured data
  Future<Map<String, dynamic>?> _parseScheduleRequest(String text) async {
    final lowerText = text.toLowerCase();

    // Determine time
    String timeLabel;
    if (lowerText.contains('sunset') || lowerText.contains('evening')) {
      timeLabel = 'Sunset';
    } else if (lowerText.contains('sunrise') || lowerText.contains('morning')) {
      timeLabel = 'Sunrise';
    } else if (lowerText.contains('midnight') || lowerText.contains('12:00 am')) {
      timeLabel = '12:00 AM';
    } else {
      // Default to sunset for evening requests
      timeLabel = 'Sunset';
    }

    // Determine repeat days
    List<String> repeatDays;
    if (lowerText.contains('every night') || lowerText.contains('nightly') ||
        lowerText.contains('every evening') || lowerText.contains('daily')) {
      repeatDays = ['Daily'];
    } else if (lowerText.contains('weeknight')) {
      repeatDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    } else if (lowerText.contains('weekend')) {
      repeatDays = ['Sat', 'Sun'];
    } else {
      // Default to daily
      repeatDays = ['Daily'];
    }

    // Determine action/pattern
    String actionLabel;
    String patternDescription;
    if (lowerText.contains('warm white') || lowerText.contains('warm')) {
      actionLabel = 'Pattern: Warm White';
      patternDescription = 'warm white';
    } else if (lowerText.contains('bright white') || lowerText.contains('bright')) {
      actionLabel = 'Pattern: Bright White';
      patternDescription = 'bright white';
    } else if (lowerText.contains('off') || lowerText.contains('turn off')) {
      actionLabel = 'Turn Off';
      patternDescription = 'off';
    } else if (lowerText.contains('on') || lowerText.contains('turn on')) {
      actionLabel = 'Turn On';
      patternDescription = 'on';
    } else {
      // Default to warm white for lighting requests
      actionLabel = 'Pattern: Warm White';
      patternDescription = 'warm white';
    }

    // Generate friendly confirmation message
    final timeName = timeLabel.toLowerCase();
    final daysDescription = repeatDays.contains('Daily')
        ? 'every evening'
        : repeatDays.length == 5
            ? 'on weeknights'
            : 'on ${repeatDays.join(", ")}';

    final confirmation = 'That sounds great! I\'ve set your system to $patternDescription $daysDescription at $timeName.';

    return {
      'timeLabel': timeLabel,
      'repeatDays': repeatDays,
      'actionLabel': actionLabel,
      'confirmation': confirmation,
    };
  }

  void _applyQuick(String s) {
    setState(() => _controller.text = s);
  }

  Future<bool?> _showAutopilotSetupDialog(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AutopilotSetupSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final autopilotEnabled = ref.watch(autopilotEnabledProvider);
    final autonomyLevel = ref.watch(autonomyLevelProvider);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: autopilotEnabled
                  ? [NexGenPalette.cyan.withValues(alpha: 0.15), NexGenPalette.violet.withValues(alpha: 0.1)]
                  : [NexGenPalette.gunmetal90, NexGenPalette.gunmetal90],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: autopilotEnabled ? NexGenPalette.cyan.withValues(alpha: 0.4) : NexGenPalette.line,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with icon, title, and toggle
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [NexGenPalette.cyan, NexGenPalette.violet],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lumina AI',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: NexGenPalette.textHigh,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Schedule assistant & autopilot',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: NexGenPalette.textMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Autopilot toggle section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: autopilotEnabled
                      ? NexGenPalette.cyan.withValues(alpha: 0.1)
                      : NexGenPalette.matteBlack.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: autopilotEnabled ? NexGenPalette.cyan.withValues(alpha: 0.3) : NexGenPalette.line,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.smart_toy_rounded,
                          color: autopilotEnabled ? NexGenPalette.cyan : NexGenPalette.textMedium,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Autopilot',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: autopilotEnabled ? NexGenPalette.cyan : NexGenPalette.textHigh,
                            ),
                          ),
                        ),
                        CupertinoSwitch(
                          value: autopilotEnabled,
                          activeColor: NexGenPalette.cyan,
                          onChanged: (value) async {
                            if (value) {
                              final confirmed = await _showAutopilotSetupDialog(context, ref);
                              if (confirmed == true) {
                                ref.read(autopilotSettingsServiceProvider).setEnabled(true);
                              }
                            } else {
                              ref.read(autopilotSettingsServiceProvider).setEnabled(false);
                            }
                          },
                        ),
                      ],
                    ),
                    if (!autopilotEnabled) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Auto-generate schedules based on your preferences, teams, and holidays.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: NexGenPalette.textMedium,
                        ),
                      ),
                    ],
                    if (autopilotEnabled) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _AutopilotModeChip(
                            label: 'Suggest',
                            selected: autonomyLevel == 1,
                            onTap: () async {
                              await ref.read(autopilotSettingsServiceProvider).setAutonomyLevel(1);
                            },
                          ),
                          const SizedBox(width: 8),
                          _AutopilotModeChip(
                            label: 'Proactive',
                            selected: autonomyLevel == 2,
                            onTap: () async {
                              final service = ref.read(autopilotSettingsServiceProvider);
                              await service.setAutonomyLevel(2);
                              await service.generateAndPopulateSchedules();
                            },
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => _showAutopilotSetupDialog(context, ref),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Settings', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Quick presets
              Text(
                'Quick prompts',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (_, i) {
                    final presets = autopilotEnabled
                        ? <String>[
                            'Prefer warm colors on weeknights',
                            'No bright patterns after 10pm',
                            'More festive on weekends',
                          ]
                        : <String>[
                            'Weeknights 8-11 PM • Warm White',
                            'Fri & Sat Dusk to Dawn • Festive',
                            'Daily Sunrise • Turn Off',
                          ];
                    final label = presets[i];
                    return ChoiceChip(
                      label: Text(label, overflow: TextOverflow.ellipsis),
                      selected: false,
                      onSelected: (_) => _applyQuick(label),
                      backgroundColor: NexGenPalette.matteBlack.withValues(alpha: 0.4),
                      labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textHigh),
                      shape: StadiumBorder(side: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.25))),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemCount: 3,
                ),
              ),

              const SizedBox(height: 12),

              // Text input
              Container(
                decoration: BoxDecoration(
                  color: NexGenPalette.matteBlack.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.35), width: 1.2),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded, color: NexGenPalette.violet, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 3,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: NexGenPalette.textHigh),
                        decoration: InputDecoration(
                          hintText: autopilotEnabled
                              ? 'Tell Lumina your preferences...'
                              : 'Describe schedule changes...',
                          hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(color: NexGenPalette.textMedium),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => _askLumina(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: NexGenPalette.cyan))
                        : IconButton(
                            onPressed: () => _askLumina(context),
                            icon: const Icon(Icons.send_rounded),
                            color: NexGenPalette.cyan,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AutopilotModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AutopilotModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? NexGenPalette.cyan.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? NexGenPalette.cyan : NexGenPalette.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for Autopilot setup and explanation.
class _AutopilotSetupSheet extends ConsumerStatefulWidget {
  const _AutopilotSetupSheet();

  @override
  ConsumerState<_AutopilotSetupSheet> createState() => _AutopilotSetupSheetState();
}

class _AutopilotSetupSheetState extends ConsumerState<_AutopilotSetupSheet> {
  int _autonomyLevel = 1;

  @override
  void initState() {
    super.initState();
    _autonomyLevel = ref.read(autonomyLevelProvider);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            border: Border(top: BorderSide(color: NexGenPalette.line)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [NexGenPalette.cyan, NexGenPalette.violet],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.smart_toy_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lumina Autopilot',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'AI-powered lighting automation',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: NexGenPalette.textMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // What is Autopilot
                  Text(
                    'What is Autopilot?',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Autopilot automatically generates and manages your lighting schedule based on:',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NexGenPalette.textMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FeatureRow(icon: Icons.sports_football, text: 'Your favorite sports teams\' game days'),
                  _FeatureRow(icon: Icons.celebration, text: 'Holidays and special occasions'),
                  _FeatureRow(icon: Icons.wb_twilight, text: 'Sunset and sunrise times at your location'),
                  _FeatureRow(icon: Icons.tune, text: 'Your vibe preferences and HOA restrictions'),
                  _FeatureRow(icon: Icons.psychology, text: 'Learned patterns from your feedback'),

                  const SizedBox(height: 24),

                  // Mode selection
                  Text(
                    'Choose Autopilot Mode',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Suggest mode
                  _ModeOption(
                    title: 'Suggest Mode',
                    description: 'Autopilot suggests patterns and you approve them before they\'re applied. Best for staying in control.',
                    icon: Icons.notifications_active_rounded,
                    selected: _autonomyLevel == 1,
                    onTap: () => setState(() => _autonomyLevel = 1),
                  ),
                  const SizedBox(height: 12),

                  // Proactive mode
                  _ModeOption(
                    title: 'Proactive Mode',
                    description: 'Autopilot automatically applies high-confidence patterns. You can always override or reject them later.',
                    icon: Icons.auto_awesome,
                    selected: _autonomyLevel == 2,
                    onTap: () => setState(() => _autonomyLevel = 2),
                    badge: 'Recommended',
                  ),

                  const SizedBox(height: 24),

                  // Setup checklist
                  Text(
                    'For Best Results',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SetupCheckItem(
                    text: 'Set your location for accurate sunrise/sunset times',
                    isComplete: _hasLocation(ref),
                  ),
                  _SetupCheckItem(
                    text: 'Add your favorite sports teams',
                    isComplete: _hasTeams(ref),
                  ),
                  _SetupCheckItem(
                    text: 'Select your favorite holidays',
                    isComplete: _hasHolidays(ref),
                  ),
                  _SetupCheckItem(
                    text: 'Set your vibe preferences',
                    isComplete: true, // Default is always set
                  ),

                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: NexGenPalette.textMedium,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () {
                            ref.read(autopilotSettingsServiceProvider).setAutonomyLevel(_autonomyLevel);
                            ref.read(autopilotSettingsServiceProvider).setEnabled(true);
                            Navigator.of(context).pop(true);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: NexGenPalette.cyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Enable Autopilot'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _hasLocation(WidgetRef ref) {
    final user = ref.read(currentUserProfileProvider).maybeWhen(
      data: (u) => u,
      orElse: () => null,
    );
    return user?.latitude != null && user?.longitude != null;
  }

  bool _hasTeams(WidgetRef ref) {
    final user = ref.read(currentUserProfileProvider).maybeWhen(
      data: (u) => u,
      orElse: () => null,
    );
    final teams = user?.sportsTeams;
    return teams != null && teams.isNotEmpty;
  }

  bool _hasHolidays(WidgetRef ref) {
    final user = ref.read(currentUserProfileProvider).maybeWhen(
      data: (u) => u,
      orElse: () => null,
    );
    final holidays = user?.favoriteHolidays;
    return holidays != null && holidays.isNotEmpty;
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: NexGenPalette.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: NexGenPalette.textHigh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  const _ModeOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? NexGenPalette.cyan.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? NexGenPalette.cyan : NexGenPalette.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected ? NexGenPalette.cyan.withValues(alpha: 0.2) : NexGenPalette.matteBlack,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected ? NexGenPalette.cyan : NexGenPalette.textHigh,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: NexGenPalette.cyan.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: NexGenPalette.cyan,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: NexGenPalette.textMedium,
                    ),
                  ),
                ],
              ),
            ),
            Radio<bool>(
              value: true,
              groupValue: selected,
              onChanged: (_) => onTap(),
              activeColor: NexGenPalette.cyan,
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupCheckItem extends StatelessWidget {
  final String text;
  final bool isComplete;

  const _SetupCheckItem({required this.text, required this.isComplete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: isComplete ? Colors.green : NexGenPalette.textMedium,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isComplete ? NexGenPalette.textHigh : NexGenPalette.textMedium,
                decoration: isComplete ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the Schedule Editor bottom sheet.
///
/// Optionally pass [preselectedDayIndex] (0..6 => Sun..Sat) to pre-check a day.
/// If [editing] is provided, the editor will load that schedule for modification.
void showScheduleEditor(BuildContext context, WidgetRef ref, {int? preselectedDayIndex, ScheduleItem? editing}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _ScheduleEditor(preselectedDayIndex: preselectedDayIndex, editing: editing),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.access_time_filled_rounded, color: NexGenPalette.textMedium, size: 56),
        const SizedBox(height: 12),
        Text('No Schedules Active.\nTap "+" to automate your lights.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );
  }
}

class _ScheduleCard extends ConsumerWidget {
  final ScheduleItem item;
  const _ScheduleCard({required this.item});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(schedulesProvider.notifier);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NexGenPalette.line, width: 1),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Left: Time + Days
            SizedBox(
              width: 110,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.timeLabel, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: NexGenPalette.textHigh)),
                const SizedBox(height: 4),
                Text(item.repeatDays.join(', '), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium)),
              ]),
            ),
            const SizedBox(width: 12),
            // Middle: Action
            Expanded(child: Text(item.actionLabel, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium)),
            const SizedBox(width: 12),
            // Edit / Delete actions
            IconButton(
              tooltip: 'Edit',
              onPressed: () => showScheduleEditor(context, ref, editing: item),
              icon: const Icon(Icons.edit_rounded, color: Colors.white70, size: 20),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete schedule?'),
                    content: const Text('This action cannot be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                      FilledButton.tonal(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  notifier.remove(item.id);
                }
              },
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 20),
            ),
            const SizedBox(width: 6),
            // Right: Toggle
            CupertinoSwitch(
              value: item.enabled,
              activeColor: NexGenPalette.cyan,
              onChanged: (v) => notifier.toggle(item.id, v),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ScheduleEditor extends ConsumerStatefulWidget {
  final int? preselectedDayIndex; // 0..6 => S..S
  final ScheduleItem? editing;
  const _ScheduleEditor({this.preselectedDayIndex, this.editing});
  @override
  ConsumerState<_ScheduleEditor> createState() => _ScheduleEditorState();
}

enum _TriggerType { specificTime, solarEvent }
enum _ActionType { powerOff, runPattern, brightness }

class _ScheduleEditorState extends ConsumerState<_ScheduleEditor> {
  _TriggerType _trigger = _TriggerType.specificTime;
  TimeOfDay _time = const TimeOfDay(hour: 19, minute: 0);
  String _solar = 'Sunset'; // 'Sunrise' or 'Sunset'

  _ActionType _action = _ActionType.runPattern;
  double _brightness = 70; // percentage 0..100
  PatternSelection? _selectedPattern;

  // Day selection represented as indices 0..6 => S M T W T F S
  final List<String> _dayLabelsShort = const ['S','M','T','W','T','F','S'];
  final List<String> _dayAbbr = const ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  late Set<int> _selectedDays;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    // Defaults
    _selectedDays = {1, 3, 5};
    _enabled = true;
    // If editing an existing item, hydrate state from it.
    final editing = widget.editing;
    if (editing != null) {
      _enabled = editing.enabled;
      // Days
      final daysLower = editing.repeatDays.map((e) => e.toLowerCase()).toList(growable: false);
      if (daysLower.any((d) => d.contains('daily'))) {
        _selectedDays = {0, 1, 2, 3, 4, 5, 6};
      } else {
        _selectedDays.clear();
        for (int i = 0; i < 7; i++) {
          final label = _dayAbbr[i].toLowerCase();
          if (daysLower.contains(label)) _selectedDays.add(i);
        }
        if (_selectedDays.isEmpty) {
          _selectedDays = {1, 3, 5};
        }
      }
      // Trigger
      final tl = editing.timeLabel.trim().toLowerCase();
      if (tl == 'sunset' || tl == 'sunrise') {
        _trigger = _TriggerType.solarEvent;
        _solar = tl == 'sunrise' ? 'Sunrise' : 'Sunset';
      } else {
        _trigger = _TriggerType.specificTime;
        final reg = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$', caseSensitive: false);
        final m = reg.firstMatch(editing.timeLabel.trim());
        if (m != null) {
          var hh = int.tryParse(m.group(1)!) ?? 7;
          final mm = int.tryParse(m.group(2)!) ?? 0;
          final ap = m.group(3)!.toLowerCase();
          if (ap == 'pm' && hh != 12) hh += 12;
          if (ap == 'am' && hh == 12) hh = 0;
          _time = TimeOfDay(hour: hh.clamp(0, 23), minute: mm.clamp(0, 59));
        }
      }
      // Action
      final a = editing.actionLabel.trim();
      final lower = a.toLowerCase();
      if (lower.startsWith('pattern')) {
        _action = _ActionType.runPattern;
        final idx = a.indexOf(':');
        final name = (idx != -1 && idx + 1 < a.length) ? a.substring(idx + 1).trim() : a.replaceFirst(RegExp(r'^(?i)pattern'), '').trim();
        _selectedPattern = PatternSelection(id: 'existing', name: name, imageUrl: '');
      } else if (lower.startsWith('brightness')) {
        _action = _ActionType.brightness;
        final mm = RegExp(r'(\d{1,3})%').firstMatch(lower);
        final val = int.tryParse(mm?.group(1) ?? '') ?? 70;
        _brightness = val.clamp(1, 100).toDouble();
      } else if (lower.contains('turn off')) {
        _action = _ActionType.powerOff;
      } else if (lower.contains('turn on')) {
        // Map "Turn On" to brightness 100%
        _action = _ActionType.brightness;
        _brightness = 100;
      }
    } else if (widget.preselectedDayIndex != null && widget.preselectedDayIndex! >= 0 && widget.preselectedDayIndex! <= 6) {
      _selectedDays = {widget.preselectedDayIndex!};
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedules = ref.watch(schedulesProvider);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(color: NexGenPalette.gunmetal90, border: Border(top: BorderSide(color: NexGenPalette.line)), boxShadow: [
            BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.06), blurRadius: 20),
          ]),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text(widget.editing == null ? 'New Schedule' : 'Edit Schedule', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  CupertinoSwitch(value: _enabled, activeColor: NexGenPalette.cyan, onChanged: (v) => setState(() => _enabled = v)),
                ]),
                const SizedBox(height: 16),
                // Trigger type segmented
                SegmentedButton<_TriggerType>(
                  segments: const [
                    ButtonSegment(value: _TriggerType.specificTime, icon: Icon(Icons.schedule_rounded), label: Text('Specific Time')),
                    ButtonSegment(value: _TriggerType.solarEvent, icon: Icon(Icons.wb_sunny_rounded), label: Text('Solar Event')),
                  ],
                  selected: {_trigger},
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: MaterialStateProperty.resolveWith((states) => states.contains(MaterialState.selected) ? NexGenPalette.cyan.withValues(alpha: 0.16) : Colors.transparent),
                    foregroundColor: MaterialStateProperty.resolveWith((states) => states.contains(MaterialState.selected) ? NexGenPalette.cyan : NexGenPalette.textHigh),
                    side: MaterialStatePropertyAll(BorderSide(color: NexGenPalette.line)),
                  ),
                  onSelectionChanged: (s) => setState(() => _trigger = s.first),
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _trigger == _TriggerType.specificTime
                      ? _TimeWheel(initial: _time, onChanged: (t) => setState(() => _time = t))
                      : _SolarEventPicker(selected: _solar, onChanged: (s) => setState(() => _solar = s)),
                ),
                const SizedBox(height: 16),
                Text('Repeat Days', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  for (int i = 0; i < 7; i++)
                    _DayCircleChip(
                      label: _dayLabelsShort[i],
                      selected: _selectedDays.contains(i),
                      onTap: () => setState(() {
                        if (_selectedDays.contains(i)) {
                          _selectedDays.remove(i);
                        } else {
                          _selectedDays.add(i);
                        }
                      }),
                    ),
                ]),
                const SizedBox(height: 16),
                Text('Action', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                DropdownButtonFormField<_ActionType>(
                  value: _action,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.bolt_rounded), labelText: 'What should the lights do?'),
                  items: const [
                    DropdownMenuItem(value: _ActionType.powerOff, child: Text('Turn Off')),
                    DropdownMenuItem(value: _ActionType.runPattern, child: Text('Run Pattern')),
                    DropdownMenuItem(value: _ActionType.brightness, child: Text('Set Brightness')),
                  ],
                  onChanged: (v) => setState(() => _action = v ?? _action),
                ),
                const SizedBox(height: 12),
                if (_action == _ActionType.runPattern)
                  _PatternPickerRow(
                    selection: _selectedPattern,
                    onPick: () async {
                      final picked = await showModalBottomSheet<PatternSelection>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _PatternPickerSheet(),
                      );
                      if (!mounted) return;
                      setState(() => _selectedPattern = picked ?? _selectedPattern);
                    },
                  ),
                if (_action == _ActionType.brightness)
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.brightness_6_rounded, size: 18, color: Colors.white70),
                      const SizedBox(width: 8),
                      Text('Brightness: ${_brightness.round()}%', style: Theme.of(context).textTheme.labelMedium),
                    ]),
                    Slider(
                      value: _brightness,
                      min: 1,
                      max: 100,
                      activeColor: NexGenPalette.cyan,
                      onChanged: (v) => setState(() => _brightness = v),
                    ),
                  ]),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    // Limit enforcement
                    if (widget.editing == null && schedules.length >= 20) {
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Maximum limit reached.'),
                          content: const Text('You can have up to 20 schedules.'),
                          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
                        ),
                      );
                      return;
                    }
                    if (_selectedDays.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one day')));
                      return;
                    }
                    if (_action == _ActionType.runPattern && _selectedPattern == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a pattern to run')));
                      return;
                    }

                    // Use the original ID when editing, or generate a new one
                    final id = widget.editing?.id ?? 'sch-${DateTime.now().millisecondsSinceEpoch}';
                    final timeLabel = _trigger == _TriggerType.specificTime ? _formatTime(_time) : _solar;
                    final days = _selectedDays.map((i) => _dayAbbr[i]).toList(growable: false);
                    String actionLabel;
                    switch (_action) {
                      case _ActionType.powerOff:
                        actionLabel = 'Turn Off';
                        break;
                      case _ActionType.runPattern:
                        actionLabel = 'Pattern: ${_selectedPattern!.name}';
                        break;
                      case _ActionType.brightness:
                        actionLabel = 'Brightness: ${_brightness.round()}%';
                        break;
                    }

                    final item = ScheduleItem(
                      id: id, // Use ID as-is to match existing schedule
                      timeLabel: timeLabel,
                      repeatDays: days,
                      actionLabel: actionLabel,
                      enabled: _enabled,
                    );

                    try {
                      if (widget.editing == null) {
                        await ref.read(schedulesProvider.notifier).add(item);
                      } else {
                        await ref.read(schedulesProvider.notifier).update(item);
                      }
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    } catch (e) {
                      debugPrint('Schedule save/update failed: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to save schedule: $e')),
                        );
                      }
                    }
                  },
                  child: Text(widget.editing == null ? 'Save Schedule' : 'Update Schedule'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = selected ? NexGenPalette.cyan.withValues(alpha: 0.18) : Colors.transparent;
    final border = selected ? NexGenPalette.cyan : NexGenPalette.line;
    final color = selected ? NexGenPalette.cyan : NexGenPalette.textMedium;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border, width: 1.2)),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
      ),
    );
  }
}

// Circular single-letter day chip used in editor
class _DayCircleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayCircleChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = selected ? NexGenPalette.cyan.withValues(alpha: 0.18) : Colors.transparent;
    final border = selected ? NexGenPalette.cyan : NexGenPalette.line;
    final color = selected ? NexGenPalette.cyan : NexGenPalette.textMedium;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: ShapeDecoration(shape: CircleBorder(side: BorderSide(color: border, width: 1.2)), color: bg),
        child: Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
      ),
    );
  }
}

// Time wheel picker wrapper
class _TimeWheel extends StatelessWidget {
  final TimeOfDay initial;
  final ValueChanged<TimeOfDay> onChanged;
  const _TimeWheel({required this.initial, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.time,
        initialDateTime: DateTime(2020, 1, 1, initial.hour, initial.minute),
        use24hFormat: false,
        onDateTimeChanged: (dt) => onChanged(TimeOfDay(hour: dt.hour, minute: dt.minute)),
      ),
    );
  }
}

class _SolarEventPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _SolarEventPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget buildBtn(String label, IconData icon) => Expanded(
      child: InkWell(
        onTap: () => onChanged(label),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected == label ? NexGenPalette.cyan : NexGenPalette.line, width: 1.2),
            color: selected == label ? NexGenPalette.cyan.withValues(alpha: 0.12) : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: selected == label ? NexGenPalette.cyan : NexGenPalette.textHigh),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: selected == label ? NexGenPalette.cyan : NexGenPalette.textHigh)),
          ]),
        ),
      ),
    );

    return Row(children: [
      buildBtn('Sunrise', Icons.wb_sunny_outlined),
      const SizedBox(width: 12),
      buildBtn('Sunset', Icons.wb_sunny_rounded),
    ]);
  }
}

// Holds selected pattern info for the editor
class PatternSelection {
  final String id;
  final String name;
  final String imageUrl;
  const PatternSelection({required this.id, required this.name, required this.imageUrl});
}

class _PatternPickerRow extends StatelessWidget {
  final PatternSelection? selection;
  final VoidCallback onPick;
  const _PatternPickerRow({required this.selection, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(border: Border.all(color: NexGenPalette.line), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
                child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: NexGenPalette.matteBlack.withValues(alpha: 0.2)),
                  child: selection == null || selection!.imageUrl.isEmpty
                      ? Icon(Icons.image_rounded, color: NexGenPalette.textMedium)
                      : Image.network(selection!.imageUrl, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(selection?.name ?? 'Choose a pattern', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: NexGenPalette.textHigh)),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 12),
      FilledButton.tonal(onPressed: onPick, child: const Text('Pick')),
    ]);
  }
}

// Full-screen bottom sheet pattern picker
class _PatternPickerSheet extends ConsumerWidget {
  const _PatternPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(color: NexGenPalette.gunmetal90, border: Border(top: BorderSide(color: NexGenPalette.line))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Text('Select Pattern', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: _AggregatedPatternGrid(onSelect: (sel) => Navigator.of(context).pop(sel)),
            ),
          ]),
        ),
      ),
    );
  }
}

// Aggregated grid showing all predefined patterns (Architectural + Holidays + Sports)
class _AggregatedPatternGrid extends ConsumerWidget {
  final ValueChanged<PatternSelection> onSelect;
  const _AggregatedPatternGrid({required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(publicPatternLibraryProvider);
    final all = lib.all;
    if (all.isEmpty) return const Center(child: Text('No patterns'));
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.9),
      itemCount: all.length,
      itemBuilder: (_, i) {
        final p = all[i];
        return InkWell(
          onTap: () => onSelect(PatternSelection(id: p.name.toLowerCase().replaceAll(' ', '_'), name: p.name, imageUrl: '')),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Stack(children: [
              // Gradient preview background using the pattern's colors
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: p.colors),
                  ),
                ),
              ),
              // Readability overlay + border
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        NexGenPalette.matteBlack.withValues(alpha: 0.06),
                        NexGenPalette.matteBlack.withValues(alpha: 0.60),
                      ],
                    ),
                    border: Border.all(color: NexGenPalette.line),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(p.name, style: Theme.of(context).textTheme.labelLarge),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// =====================
// Weekly Agenda (Large)
// =====================

class _WeeklyAgendaLarge extends ConsumerWidget {
  final AsyncValue<SunTimeStrings?> sunAsync;
  const _WeeklyAgendaLarge({required this.sunAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulesProvider);

    // Build list of 7 days starting from today
    final now = DateTime.now();
    final List<DateTime> days = List.generate(7, (i) => DateTime(now.year, now.month, now.day).add(Duration(days: i)));
    final List<String> abbr = const ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    // Helper: does schedule apply to a given weekday index (0=Sun..6=Sat)
    bool appliesTo(ScheduleItem s, int weekdayIndex0Sun) {
      final dl = s.repeatDays.map((e) => e.toLowerCase()).toList(growable: false);
      if (dl.contains('daily')) return true;
      Set<String> keys;
      switch (weekdayIndex0Sun) {
        case 0:
          keys = {'sun', 'sunday'};
          break;
        case 1:
          keys = {'mon', 'monday'};
          break;
        case 2:
          keys = {'tue', 'tues', 'tuesday'};
          break;
        case 3:
          keys = {'wed', 'wednesday'};
          break;
        case 4:
          keys = {'thu', 'thurs', 'thursday'};
          break;
        case 5:
          keys = {'fri', 'friday'};
          break;
        case 6:
          keys = {'sat', 'saturday'};
          break;
        default:
          keys = {};
      }
      return dl.any(keys.contains);
    }

    List<ScheduleItem> itemsForDay(int weekdayIndex0Sun) => schedules.where((s) => s.enabled && appliesTo(s, weekdayIndex0Sun)).toList(growable: false);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('Weekly Schedule', style: Theme.of(context).textTheme.titleLarge),
      ),
      // Time Axis Header: [ 50px spacer ] [ Sunset .... Sunrise ]
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const SizedBox(width: 50),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 22,
              child: Stack(children: [
                // Optional gradient bar representing "Night"
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          NexGenPalette.matteBlack.withValues(alpha: 0.15),
                          NexGenPalette.matteBlack.withValues(alpha: 0.05),
                        ],
                      ),
                    ),
                  ),
                ),
                // Midnight grid line at 50%
                Align(
                  alignment: Alignment.center,
                  child: Container(width: 1, color: NexGenPalette.textMedium.withValues(alpha: 0.25)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    sunAsync.when(
                      data: (s) => Text(
                        ((s?.sunsetLabel ?? 'Sunset (—)')).toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8),
                      ),
                      loading: () => Text('SUNSET (…)'.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                      error: (e, st) => Text('SUNSET (—)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                    ),
                    sunAsync.when(
                      data: (s) => Text(
                        ((s?.sunriseLabel ?? 'Sunrise (—)')).toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8),
                      ),
                      loading: () => Text('SUNRISE (…)'.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                      error: (e, st) => Text('SUNRISE (—)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
      ...List.generate(7, (i) {
        final d = days[i];
        final isToday = i == 0;
        final int weekdayIndex0Sun = d.weekday % 7; // Sun=0..Sat=6
        final dayItems = itemsForDay(weekdayIndex0Sun);
        final String barLabel = dayItems.isNotEmpty ? _labelFromAction(dayItems.first.actionLabel) : 'No schedule';

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 50,
              child: Text(
                abbr[weekdayIndex0Sun],
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: isToday ? NexGenPalette.cyan : NexGenPalette.textMedium, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Track bar (tap to add/edit) with active fill, centered label, and midnight grid
                GestureDetector(
                  onTap: () => showScheduleEditor(context, ref, preselectedDayIndex: weekdayIndex0Sun),
                  child: NightTrackBar(label: barLabel, items: dayItems),
                ),
                const SizedBox(height: 8),
                if (dayItems.isEmpty)
                  Text('No schedule yet', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: NexGenPalette.textMedium))
                else
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final it in dayItems)
                      _AgendaDetailChip(
                        label: '${(() {
                          final tl = it.timeLabel.trim();
                          final lower = tl.toLowerCase();
                          if (lower != 'sunset' && lower != 'sunrise') return tl;
                          return sunAsync.when(
                            data: (s) => lower == 'sunset' ? (s?.sunsetLabel ?? 'Sunset (—)') : (s?.sunriseLabel ?? 'Sunrise (—)'),
                            loading: () => lower == 'sunset' ? 'Sunset (…)': 'Sunrise (…) ',
                            error: (e, st) => lower == 'sunset' ? 'Sunset (—)' : 'Sunrise (—)',
                          );
                        }())} • ${it.actionLabel}',
                        onTap: () => showScheduleEditor(context, ref, editing: it),
                        onDelete: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: NexGenPalette.gunmetal90,
                              title: const Text('Delete Schedule?'),
                              content: Text('Delete "${_labelFromAction(it.actionLabel)}" schedule?\n\nThis will remove it from all selected days.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red.shade700,
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            ref.read(schedulesProvider.notifier).remove(it.id);
                          }
                        },
                      ),
                  ]),
              ]),
            ),
            const SizedBox(width: 8),
            // Per-day add
            IconButton(
              onPressed: () => showScheduleEditor(context, ref, preselectedDayIndex: weekdayIndex0Sun),
              icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white),
              tooltip: 'Add',
            ),
          ]),
        );
      }),
    ]);
  }

  String _labelFromAction(String actionLabel) {
    final a = actionLabel.trim();
    if (a.toLowerCase().startsWith('pattern')) {
      final idx = a.indexOf(':');
      return idx != -1 && idx + 1 < a.length ? a.substring(idx + 1).trim() : a;
    }
    return a;
  }
}

class _AgendaDetailChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _AgendaDetailChip({required this.label, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(border: Border.all(color: NexGenPalette.line), borderRadius: BorderRadius.circular(12), color: NexGenPalette.gunmetal90),
          child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: NexGenPalette.textHigh)),
        ),
      ),
      const SizedBox(width: 4),
      InkWell(
        onTap: onDelete,
        customBorder: const CircleBorder(),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: ShapeDecoration(shape: const CircleBorder(), color: NexGenPalette.matteBlack.withValues(alpha: 0.3)),
          child: const Icon(Icons.close_rounded, size: 16, color: Colors.white70),
        ),
      ),
    ]);
  }
}

// NightTrackBar now shared in widgets/night_track_bar.dart
