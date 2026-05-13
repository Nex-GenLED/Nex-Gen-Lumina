import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/simple/simple_providers.dart';
import 'package:nexgen_command/features/installer/connection_method_resolver.dart';
import 'package:nexgen_command/features/installer/connection_method_verification.dart';
import 'package:nexgen_command/features/installer/installer_preference_draft.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/site/connection_method.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/widgets/team_autocomplete.dart';

/// Test-visible key for the pre-flight verification section. Tests use
/// `find.descendant(of: find.byKey(handoffVerificationSectionKey), ...)`
/// to scope icon/text finds and avoid colliding with similarly-styled
/// widgets elsewhere on the screen (autonomy tiles, Simple Mode list).
const Key handoffVerificationSectionKey = ValueKey('handoff-verification');

/// Customer handoff screen for installer setup wizard.
/// Allows installer to configure user preferences before handing off.
class HandoffScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final ValueChanged<InstallerPreferenceDraft>? onNext;

  const HandoffScreen({
    super.key,
    this.onBack,
    this.onNext,
  });

  @override
  ConsumerState<HandoffScreen> createState() => _HandoffScreenState();
}

class _HandoffScreenState extends ConsumerState<HandoffScreen> {
  // State fields
  bool _useSimpleMode = false;
  String _profileType = 'residential';
  String? _managerEmail;
  final List<String> _selectedSportsTeams = [];
  final List<String> _selectedHolidays = [];
  double _vibeLevel = 0.5;
  int _autonomyLevel = 1;

  final _managerEmailController = TextEditingController();
  final _teamInputCtrl = TextEditingController();

  // Verification state — keyed by controller doc id. Starts empty; the
  // sweep fills entries as probes resolve. Complete Setup stays disabled
  // until every selected controller has a non-pending entry and none are
  // in the fail bucket.
  final Map<String, VerificationResult> _verifications = {};
  bool _sweepStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startSweep();
    });
  }

  static const _holidays = [
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
    _managerEmailController.dispose();
    _teamInputCtrl.dispose();
    super.dispose();
  }

  List<ControllerInfo> _selectedControllers() {
    final selectedIds = ref.read(installerSelectedControllersProvider);
    final controllersAsync = ref.read(controllersStreamProvider);
    return controllersAsync.maybeWhen(
      data: (list) =>
          list.where((c) => selectedIds.contains(c.id)).toList(),
      orElse: () => const <ControllerInfo>[],
    );
  }

  Future<void> _startSweep() async {
    if (_sweepStarted) return;
    _sweepStarted = true;
    final controllers = _selectedControllers();
    if (controllers.isEmpty) {
      // Stream may still be loading; reschedule once and bail otherwise
      // so the screen doesn't get stuck waiting forever in a test where
      // the stream emits nothing.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final retry = _selectedControllers();
        if (retry.isNotEmpty) {
          _sweepStarted = false;
          _startSweep();
        }
      });
      return;
    }
    setState(() {
      for (final c in controllers) {
        _verifications[c.id] = const VerificationResult.pending();
      }
    });
    final resolver = ref.read(connectionMethodResolverProvider);
    final persistedMethods = ref.read(installerConnectionMethodsProvider);
    final skipped = ref.read(installerConnectionMethodSkippedProvider);

    for (final controller in controllers) {
      unawaited(_verifyOne(
        controller: controller,
        resolver: resolver,
        persisted: persistedMethods[controller.id],
        isSkipped: skipped.contains(controller.id),
      ));
    }
  }

  Future<void> _verifyOne({
    required ControllerInfo controller,
    required ConnectionMethodResolver resolver,
    required ConnectionMethod? persisted,
    required bool isSkipped,
  }) async {
    final observed = await resolver.probeOrNull(controller);
    if (!mounted) return;
    final result = verifyController(
      persisted: persisted,
      isSkipped: isSkipped,
      observed: observed,
    );
    setState(() {
      _verifications[controller.id] = result;
    });
  }

  bool get _canCompleteSetup {
    final selected = _selectedControllers();
    if (selected.isEmpty) return false;
    if (_verifications.length < selected.length) return false;
    return isAllVerifiedAcceptable(_verifications.values);
  }

  void _showBlockingFailureDialog() {
    final controllers = _selectedControllers();
    final fails = <ControllerInfo>[];
    for (final c in controllers) {
      final r = _verifications[c.id];
      if (r != null && r.status == VerificationStatus.fail) {
        fails.add(c);
      }
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text(
          'Cannot complete install',
          style: TextStyle(color: NexGenPalette.textHigh),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in fails)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${c.name ?? c.ip} — ${_verifications[c.id]?.reason ?? 'verification failed'}',
                  style:
                      const TextStyle(color: NexGenPalette.textMedium),
                ),
              ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // State (selected controllers, resolved methods, skipped
              // set) is preserved — the wizard reads them from providers,
              // not from screen-local state.
              ref.read(installerWizardStepProvider.notifier).state =
                  InstallerWizardStep.connectionMethod;
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
            ),
            child: const Text(
              'Back to Connection Step',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
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
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: NexGenPalette.gunmetal90,
                      border: Border.all(color: NexGenPalette.line),
                    ),
                    child: const Icon(Icons.handshake_outlined, size: 64, color: NexGenPalette.cyan),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Customer Handoff',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Configure user preferences before completing setup.',
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 16),
                ),
                const SizedBox(height: 24),

                // ── Pre-flight: connection-method verification ──
                _buildVerificationSection(),
                const SizedBox(height: 24),

                // ── SECTION 1: Profile Type ──
                _buildSectionLabel('Profile Type'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildProfileCard('residential', 'Residential', Icons.home_rounded)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildProfileCard('commercial', 'Commercial', Icons.store_rounded)),
                  ],
                ),
                if (_profileType == 'commercial') ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _managerEmailController,
                    onChanged: (v) => _managerEmail = v.trim().isEmpty ? null : v.trim(),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Manager Email',
                      labelStyle: const TextStyle(color: NexGenPalette.textMedium),
                      filled: true,
                      fillColor: NexGenPalette.gunmetal90,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: NexGenPalette.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: NexGenPalette.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: NexGenPalette.cyan),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
                const SizedBox(height: 28),

                // ── SECTION 2: Sports Teams ──
                _buildSectionLabel('Favorite Teams'),
                const SizedBox(height: 8),
                const Text(
                  'Search for your customer’s favorite teams. They '
                  'can add more later from their profile.',
                  style: TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TeamSelector(
                  controller: _teamInputCtrl,
                  selectedTeams: _selectedSportsTeams,
                  onAddTeam: (name) =>
                      setState(() => _selectedSportsTeams.add(name)),
                  onRemoveTeam: (name) =>
                      setState(() => _selectedSportsTeams.remove(name)),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {},
                    child: const Text(
                      'Skip — customer will add later',
                      style: TextStyle(
                          color: NexGenPalette.textMedium, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── SECTION 3: Favorite Holidays ──
                _buildSectionLabel('Favorite Holidays'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _holidays
                      .map((holiday) => _buildSelectableChip(
                            label: holiday,
                            selected: _selectedHolidays.contains(holiday),
                            onTap: () => setState(() {
                              _selectedHolidays.contains(holiday)
                                  ? _selectedHolidays.remove(holiday)
                                  : _selectedHolidays.add(holiday);
                            }),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 28),

                // ── SECTION 4: Vibe Level ──
                _buildSectionLabel('Lighting Style'),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
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
                const SizedBox(height: 28),

                // ── SECTION 5: Auto-Pilot Autonomy ──
                _buildSectionLabel('How should Lumina handle changes?'),
                const SizedBox(height: 12),
                _buildAutonomyTile(
                  level: 0,
                  title: 'Ask me first',
                  subtitle: 'Passive: suggests changes, waits for approval',
                  icon: Icons.front_hand_rounded,
                ),
                const SizedBox(height: 8),
                _buildAutonomyTile(
                  level: 1,
                  title: 'Smart suggestions',
                  subtitle: 'Shows a weekly preview, auto-applies if no response in 24hrs',
                  icon: Icons.lightbulb_outline_rounded,
                ),
                const SizedBox(height: 8),
                _buildAutonomyTile(
                  level: 2,
                  title: 'Full auto-pilot',
                  subtitle: 'Automatically applies the best schedule — no approval needed',
                  icon: Icons.rocket_launch_rounded,
                ),
                const SizedBox(height: 28),

                // ── Simple Mode Card ──
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: NexGenPalette.gunmetal90,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: NexGenPalette.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [NexGenPalette.cyan, NexGenPalette.violet],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Simple Mode',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Switch(
                            value: _useSimpleMode,
                            onChanged: (value) => setState(() => _useSimpleMode = value),
                            activeTrackColor: NexGenPalette.cyan,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Recommended for:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildRecommendationItem('Older users who prefer simplicity'),
                      _buildRecommendationItem('First-time smart home users'),
                      _buildRecommendationItem('Users who want easy, one-tap control'),
                      const SizedBox(height: 16),
                      const Divider(color: NexGenPalette.line),
                      const SizedBox(height: 16),
                      const Text(
                        'Simple Mode Features:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildFeatureItem(Icons.check_circle_outline, 'Large, easy-to-tap buttons', NexGenPalette.cyan),
                      _buildFeatureItem(Icons.check_circle_outline, 'Only Home & Settings tabs', NexGenPalette.cyan),
                      _buildFeatureItem(Icons.check_circle_outline, '3-5 favorite patterns for quick access', NexGenPalette.cyan),
                      _buildFeatureItem(Icons.check_circle_outline, 'Simple brightness control with haptic feedback', NexGenPalette.cyan),
                      _buildFeatureItem(Icons.check_circle_outline, 'Voice assistant setup guides', NexGenPalette.cyan),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: NexGenPalette.cyan.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: NexGenPalette.cyan.withValues(alpha:0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: NexGenPalette.cyan, size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Users can always switch between Simple and Full modes in Settings.',
                                style: TextStyle(
                                  color: NexGenPalette.cyan,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),

        // Navigation buttons pinned to bottom
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Row(
            children: [
              if (widget.onBack != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onBack,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: NexGenPalette.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Back', style: TextStyle(color: Colors.white)),
                  ),
                ),
              if (widget.onBack != null) const SizedBox(width: 16),
              if (widget.onNext != null)
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canCompleteSetup ? _completeHandoff : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      disabledBackgroundColor:
                          NexGenPalette.cyan.withValues(alpha: 0.25),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Complete Setup',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Profile Type Card ──

  Widget _buildProfileCard(String type, String label, IconData icon) {
    final selected = _profileType == type;
    return GestureDetector(
      onTap: () => setState(() => _profileType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? NexGenPalette.cyan.withValues(alpha:0.12) : NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? NexGenPalette.cyan : NexGenPalette.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium, size: 36),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? NexGenPalette.cyan : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Selectable Chip ──

  Widget _buildSelectableChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? NexGenPalette.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? NexGenPalette.cyan : NexGenPalette.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ── "+ Add Other" Chip ──

  // ── Autonomy Tile ──

  Widget _buildAutonomyTile({
    required int level,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _autonomyLevel == level;
    return GestureDetector(
      onTap: () => setState(() => _autonomyLevel = level),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? NexGenPalette.cyan.withValues(alpha:0.12) : NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? NexGenPalette.cyan : NexGenPalette.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected ? NexGenPalette.cyan : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: NexGenPalette.cyan, size: 22),
          ],
        ),
      ),
    );
  }

  // ── Section Label ──

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  // ── Existing helpers ──

  Widget _buildRecommendationItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: NexGenPalette.cyan, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationSection() {
    final controllers = _selectedControllers();
    return Container(
      key: handoffVerificationSectionKey,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.fact_check_outlined,
                  color: NexGenPalette.cyan, size: 20),
              SizedBox(width: 8),
              Text(
                'Pre-flight check',
                style: TextStyle(
                  color: NexGenPalette.textHigh,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Verifying every controller is on the connection method '
            'you picked. Complete Setup unlocks once this passes.',
            style:
                TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (controllers.isEmpty)
            const Text(
              'No controllers selected — go back to add one.',
              style:
                  TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
            )
          else
            for (final c in controllers)
              _VerificationRow(
                controller: c,
                result: _verifications[c.id] ??
                    const VerificationResult.pending(),
              ),
        ],
      ),
    );
  }

  void _completeHandoff() {
    // Defensive failure guard — the button is gated by _canCompleteSetup,
    // but if anything bypasses that (state race, hot-reload) we still
    // block the install with the same dialog the gate would prevent.
    final hasFail = _verifications.values
        .any((r) => r.status == VerificationStatus.fail);
    if (hasFail) {
      _showBlockingFailureDialog();
      return;
    }

    // Apply Simple Mode preference
    if (_useSimpleMode) {
      ref.read(simpleModeProvider.notifier).enable();
    } else {
      ref.read(simpleModeProvider.notifier).disable();
    }

    final draft = InstallerPreferenceDraft(
      useSimpleMode: _useSimpleMode,
      sportsTeams: List.unmodifiable(_selectedSportsTeams),
      favoriteHolidays: List.unmodifiable(_selectedHolidays),
      vibeLevel: _vibeLevel,
      changeToleranceLevel: 3,
      autonomyLevel: _autonomyLevel,
      profileType: _profileType,
      managerEmail: _profileType == 'commercial' ? _managerEmail : null,
    );

    widget.onNext?.call(draft);
  }
}

/// One row inside the pre-flight section. Renders the controller name +
/// IP and a status pill (pending spinner, green check, amber warning, or
/// red X) plus an inline reason for warn/fail.
class _VerificationRow extends StatelessWidget {
  const _VerificationRow({required this.controller, required this.result});

  final ControllerInfo controller;
  final VerificationResult result;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusIcon(status: result.status),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.name ?? controller.ip,
                  style: const TextStyle(
                    color: NexGenPalette.textHigh,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  controller.ip,
                  style: const TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 11,
                  ),
                ),
                if (result.reason != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    result.reason!,
                    style: TextStyle(
                      color: _reasonColor(result.status),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _reasonColor(VerificationStatus status) {
    switch (status) {
      case VerificationStatus.fail:
        return Colors.red;
      case VerificationStatus.warn:
        return NexGenPalette.amber;
      case VerificationStatus.pass:
      case VerificationStatus.pending:
        return NexGenPalette.textMedium;
    }
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final VerificationStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case VerificationStatus.pending:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: NexGenPalette.cyan,
          ),
        );
      case VerificationStatus.pass:
        return const Icon(Icons.check_circle,
            color: NexGenPalette.green, size: 18);
      case VerificationStatus.warn:
        return const Icon(Icons.warning_amber_rounded,
            color: NexGenPalette.amber, size: 18);
      case VerificationStatus.fail:
        return const Icon(Icons.cancel, color: Colors.red, size: 18);
    }
  }
}
