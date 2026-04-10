import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/autopilot/autopilot_weekly_preview.dart';
import 'package:nexgen_command/features/autopilot/autopilot_schedule_generator.dart';
import 'package:nexgen_command/features/autopilot/services/autopilot_event_repository.dart';
import 'package:nexgen_command/models/autopilot_schedule_item.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// First-run onboarding screen shown when welcomeCompleted == false.
/// Lets the customer review/adjust installer-set preferences before using the app.
class FirstRunScreen extends ConsumerStatefulWidget {
  const FirstRunScreen({super.key});

  @override
  ConsumerState<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends ConsumerState<FirstRunScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Editable copies of installer-set values (populated from profile on init)
  List<String> _sportsTeams = [];
  List<String> _favoriteHolidays = [];
  double _vibeLevel = 0.5;
  bool _prefsLoaded = false;

  static const _allSportsTeams = [
    'Chiefs',
    'Royals',
    'Sporting KC',
    'Kansas City Current',
    'Mavericks (STL)',
    'Cardinals (STL)',
    'Blues (STL)',
    'Seahawks',
    'Sounders',
    'Mariners',
  ];

  static const _allHolidays = [
    'Christmas',
    'Halloween',
    '4th of July',
    'New Year\'s',
    'St. Patrick\'s Day',
    'Thanksgiving',
    'Easter',
    'Valentine\'s Day',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _loadPrefsFromProfile() {
    if (_prefsLoaded) return;
    final profileAsync = ref.read(currentUserProfileProvider);
    profileAsync.whenData((profile) {
      if (profile == null) return;
      setState(() {
        _sportsTeams = List<String>.from(profile.sportsTeams);
        _favoriteHolidays = List<String>.from(profile.favoriteHolidays);
        _vibeLevel = profile.vibeLevel ?? 0.5;
        _prefsLoaded = true;
      });
    });
  }

  Future<void> _completeOnboarding({bool savePrefs = true}) async {
    final profileAsync = ref.read(currentUserProfileProvider);
    final profile = profileAsync.maybeWhen(data: (p) => p, orElse: () => null);
    if (profile == null) return;

    // Save adjusted preferences if the user went through page 2
    if (savePrefs) {
      final userService = ref.read(userServiceProvider);
      await userService.updateUserProfile(profile.id, {
        'sports_teams': _sportsTeams,
        'sports_team_priority': _sportsTeams,
        'favorite_holidays': _favoriteHolidays,
        'vibe_level': _vibeLevel,
        'welcome_completed': true,
      });
    } else {
      // Skip — just mark completed, don't overwrite installer prefs
      final userService = ref.read(userServiceProvider);
      await userService.updateUserProfile(profile.id, {
        'welcome_completed': true,
      });
    }

    // Ensure autopilot is enabled
    if (!profile.autopilotEnabled) {
      await ref.read(autopilotSettingsServiceProvider).setEnabled(true);
    }

    // ── Initial Schedule Generation ────────────────────────────────────────
    // Fire-and-forget: generate the first week in the background so the
    // FirstWeekRevealScreen has data ready when the user arrives.
    _triggerInitialScheduleGeneration();

    if (mounted) {
      // Navigate to the reveal screen instead of the dashboard so the user
      // sees their personalized first week before activating autopilot.
      context.go(AppRoutes.firstWeekReveal);
    }
  }

  /// Runs the initial schedule generation asynchronously.
  /// Errors are swallowed — the reveal screen handles the empty-state gracefully.
  Future<void> _triggerInitialScheduleGeneration() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Re-read the profile to get the freshly saved preferences.
      final profileAsync = ref.read(currentUserProfileProvider);
      final profile =
          profileAsync.maybeWhen(data: (p) => p, orElse: () => null);
      if (profile == null) return;

      final weekStart = upcomingWeekStart(DateTime.now());
      final weekEnd = weekEndFor(weekStart);

      final generator = AutopilotScheduleGenerator();
      final events = await generator.generateWeek(
        weekStart: weekStart,
        weekEnd: weekEnd,
        profile: profile,
        protectedBlocks: const [], // New user — no protected blocks yet
        sportingEvents: const [], // Sports events loaded by sports providers
        holidays: const [],       // Holiday events loaded by calendar providers
        weekGeneration: 0,
      );

      final repo = ref.read(autopilotEventRepositoryProvider);
      await repo.saveInitialWeekEvents(uid, events);
    } catch (e) {
      debugPrint('⚠️ Initial schedule generation failed (non-fatal): $e');
    }
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _vibeDescription(double value) {
    if (value <= 0.2) return 'Soft and tasteful — gentle fades, warm whites';
    if (value <= 0.4) return 'Relaxed — occasional color accents';
    if (value <= 0.6) return 'Balanced — seasonal colors and patterns';
    if (value <= 0.8) return 'Expressive — vivid colors, game day energy';
    return 'Maximum impact — full animations, celebration mode';
  }

  @override
  Widget build(BuildContext context) {
    _loadPrefsFromProfile();

    final profileAsync = ref.watch(currentUserProfileProvider);
    final firstName = profileAsync.maybeWhen(
      data: (p) => p?.displayName.split(' ').first ?? 'there',
      orElse: () => 'there',
    );

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: SafeArea(
        child: Column(
          children: [
            // Page indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i <= _currentPage
                            ? NexGenPalette.cyan
                            : NexGenPalette.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),
            // Skip button
            if (_currentPage < 2)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: TextButton(
                    onPressed: () => _completeOnboarding(savePrefs: false),
                    child: const Text(
                      'Skip',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildWelcomePage(firstName),
                  _buildPreferencesPage(),
                  _buildCompletionPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Page 1: Welcome ──

  Widget _buildWelcomePage(String firstName) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NexGenPalette.gunmetal90,
              border: Border.all(color: NexGenPalette.line),
            ),
            child: const Icon(Icons.auto_awesome, size: 56, color: NexGenPalette.cyan),
          ),
          const SizedBox(height: 40),
          Text(
            'Welcome to Lumina, $firstName!',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          const Text(
            'Auto-Pilot keeps your lights fresh — it learns your style and '
            'automatically schedules seasonal themes, game day colors, and '
            'holiday displays.',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 15, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Let\'s get you set up',
                style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _handleForgotPassword,
            child: const Text(
              'Forgot password? Send reset email',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleForgotPassword() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email != null && email.isNotEmpty) {
      // User is signed in — send reset to their email directly
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Password reset email sent to $email'),
              backgroundColor: NexGenPalette.cyan,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send reset email: $e')),
          );
        }
      }
    } else {
      // No email on current user — show a text field dialog
      final emailCtrl = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: NexGenPalette.gunmetal90,
          title: const Text('Reset Password', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: emailCtrl,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Email address',
              labelStyle: const TextStyle(color: NexGenPalette.textMedium),
              filled: true,
              fillColor: NexGenPalette.matteBlack,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: NexGenPalette.cyan),
              child: const Text('Send', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
      if (confirmed == true && emailCtrl.text.trim().isNotEmpty) {
        try {
          await FirebaseAuth.instance.sendPasswordResetEmail(
            email: emailCtrl.text.trim(),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Password reset email sent to ${emailCtrl.text.trim()}'),
                backgroundColor: NexGenPalette.cyan,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to send reset email: $e')),
            );
          }
        }
      }
    }
  }

  // ── Page 2: Preferences ──

  Widget _buildPreferencesPage() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                const Text(
                  'Your preferences',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The installer set these up for you — feel free to adjust anything.',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                ),
                const SizedBox(height: 28),

                // Sports teams
                const Text(
                  'Favorite Teams',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allSportsTeams.map((team) {
                    final selected = _sportsTeams.contains(team);
                    return GestureDetector(
                      onTap: () => setState(() {
                        selected ? _sportsTeams.remove(team) : _sportsTeams.add(team);
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? NexGenPalette.cyan : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: selected ? NexGenPalette.cyan : NexGenPalette.line),
                        ),
                        child: Text(
                          team,
                          style: TextStyle(
                            color: selected ? Colors.black : Colors.white,
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),

                // Holidays
                const Text(
                  'Favorite Holidays',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allHolidays.map((holiday) {
                    final selected = _favoriteHolidays.contains(holiday);
                    return GestureDetector(
                      onTap: () => setState(() {
                        selected ? _favoriteHolidays.remove(holiday) : _favoriteHolidays.add(holiday);
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? NexGenPalette.cyan : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: selected ? NexGenPalette.cyan : NexGenPalette.line),
                        ),
                        child: Text(
                          holiday,
                          style: TextStyle(
                            color: selected ? Colors.black : Colors.white,
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),

                // Vibe level
                const Text(
                  'Lighting Style',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: NexGenPalette.gunmetal90,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: NexGenPalette.line),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Subtle & Elegant',
                              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
                          Text('Bold & Energetic',
                              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: NexGenPalette.cyan,
                          inactiveTrackColor: NexGenPalette.line,
                          thumbColor: NexGenPalette.cyan,
                        ),
                        child: Slider(
                          value: _vibeLevel,
                          onChanged: (v) => setState(() => _vibeLevel = v),
                          divisions: 4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _vibeDescription(_vibeLevel),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Looks good',
                style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Page 3: Completion ──

  Widget _buildCompletionPage() {
    final scheduleAsync = ref.watch(weeklyScheduleProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NexGenPalette.gunmetal90,
              border: Border.all(color: NexGenPalette.line),
            ),
            child: const Icon(Icons.check_circle_outline, size: 56, color: NexGenPalette.cyan),
          ),
          const SizedBox(height: 32),
          const Text(
            'You\'re all set!',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Your first weekly schedule arrives this Sunday at 7 PM.',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // Weekly preview card
          scheduleAsync.when(
            data: (items) => _buildWeekPreviewCard(items),
            loading: () => Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: NexGenPalette.cyan),
                ),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _completeOnboarding(savePrefs: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Go to my lights',
                style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildWeekPreviewCard(List<AutopilotScheduleItem> items) {
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    // Group items by day of week
    final byDay = <int, List<AutopilotScheduleItem>>{};
    for (final item in items) {
      final dow = item.scheduledTime.weekday; // 1=Mon..7=Sun
      byDay.putIfAbsent(dow, () => []).add(item);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This Week\'s Preview',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const Text(
              'Schedule generating — check back Sunday evening.',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
            )
          else
            ...List.generate(7, (i) {
              final dow = i + 1;
              final dayItems = byDay[dow] ?? [];
              final label = dayItems.isNotEmpty
                  ? dayItems.map((e) => e.patternName).join(', ')
                  : '—';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        dayNames[i],
                        style: const TextStyle(
                          color: NexGenPalette.textMedium,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
