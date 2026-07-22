import 'dart:async' show unawaited;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/demo/demo_lead_service.dart';
import 'package:nexgen_command/features/demo/demo_models.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/demo/demo_stock_home.dart';
import 'package:nexgen_command/features/demo/widgets/demo_scaffold.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';

/// Demo completion screen - the conversion point.
///
/// Shows:
/// - Summary of demo experience
/// - Consultation request CTA
/// - Option to create account
class DemoCompletionScreen extends ConsumerStatefulWidget {
  const DemoCompletionScreen({super.key});

  @override
  ConsumerState<DemoCompletionScreen> createState() =>
      _DemoCompletionScreenState();
}

class _DemoCompletionScreenState extends ConsumerState<DemoCompletionScreen> {
  bool _showingContactForm = false;
  ContactMethod? _selectedContactMethod;
  ContactTime? _selectedContactTime;
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Mark demo as completed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(demoSessionProvider.notifier).completeDemo();
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitConsultationRequest() async {
    if (_selectedContactMethod == null || _selectedContactTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select your preferred contact method and time'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final lead = ref.read(demoLeadProvider);
      if (lead == null) {
        throw Exception('No lead data found');
      }

      final request = ContactRequest(
        method: _selectedContactMethod!,
        preferredTime: _selectedContactTime!,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        requestedAt: DateTime.now(),
      );

      final leadService = ref.read(demoLeadServiceProvider);
      await leadService.logContactRequest(lead.id, request);
      await leadService.logConsultationRequested(lead.id);

      if (!mounted) return;

      // Show success dialog
      await _showSuccessDialog();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting request: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showSuccessDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: NexGenPalette.cyan),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Success icon
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: NexGenPalette.cyan.withValues(alpha: 0.1),
                      border: Border.all(
                        color: NexGenPalette.cyan.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 48,
                      color: NexGenPalette.cyan,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Request Submitted!',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A Nex-Gen lighting specialist will contact you within 24 hours.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: NexGenPalette.textMedium,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        // End demo and go to login
                        ref.read(demoSessionProvider.notifier).endDemo();
                        context.go(AppRoutes.login);
                      },
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToSignup() {
    final lead = ref.read(demoLeadProvider);
    ref.read(demoSessionProvider.notifier).endDemo();
    // Navigate to signup with pre-filled email
    context.go(AppRoutes.signUp, extra: lead?.email);
  }

  @override
  Widget build(BuildContext context) {
    final lead = ref.watch(demoLeadProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: Container(
        decoration: const BoxDecoration(
          gradient: BrandGradients.atmosphere,
        ),
        child: SafeArea(
          child: _showingContactForm
              ? _buildContactForm()
              : _buildCompletionSummary(lead),
        ),
      ),
    );
  }

  Widget _buildCompletionSummary(DemoLead? lead) {
    final photoBytes = ref.watch(demoPhotoProvider);
    final usingStock = ref.watch(demoUsingStockPhotoProvider);
    final rooflineConfig = ref.watch(demoRooflineConfigProvider);
    final hasConfig = rooflineConfig != null &&
        rooflineConfig.segments.any((s) => s.points.length >= 2);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ═══ 1. Roofline hero — personalized moment ═══
          if (hasConfig) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 994 / 492,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Base image
                    if (usingStock)
                      Image.asset(
                        DemoStockHome.imageAssetPath,
                        fit: BoxFit.cover,
                      )
                    else if (photoBytes != null)
                      Image.memory(
                        photoBytes,
                        fit: BoxFit.cover,
                      )
                    else
                      Container(color: NexGenPalette.gunmetal),
                    // LED overlay — the money shot
                    const AnimatedRooflineOverlay(
                      useBoxFitCover: true,
                      targetAspectRatio: 994 / 492,
                      forceOn: true,
                      brightness: 255,
                    ),
                    // Subtle bottom gradient for title legibility
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 64,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0x99000000)],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
          ],

          // ═══ 2 & 3. Title + subtitle ═══
          Text(
            'This Could Be Your Home',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Ready to make it real?',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // ═══ 4. PRIMARY CTA: Consultation ═══
          DemoGlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        NexGenPalette.cyan,
                        NexGenPalette.blue,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: NexGenPalette.cyan.withValues(alpha: 0.35),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.calendar_today_rounded,
                    size: 32,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Get Your Free Consultation',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'A Nex-Gen specialist will design a lighting plan '
                  'tailored to your home',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: NexGenPalette.textMedium,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                DemoPrimaryButton(
                  label: 'Request Free Consultation',
                  icon: Icons.arrow_forward,
                  onPressed: () {
                    setState(() => _showingContactForm = true);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ═══ 5. SECONDARY CTA: Explore the app ═══
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                ref.read(demoModeProvider.notifier).state = true;
                ref.read(demoBrowsingProvider.notifier).state = true;
                isDemoBrowsingFlag = true;

                final leadService = ref.read(demoLeadServiceProvider);
                final leadId = ref.read(demoLeadProvider)?.id;
                if (leadId != null) {
                  unawaited(leadService.logDemoCompleted(leadId)
                      .catchError((e) => debugPrint('Demo analytics: $e')));
                  unawaited(leadService.logAppExploreStarted(leadId)
                      .catchError((e) => debugPrint('Demo analytics: $e')));
                }

                context.go(AppRoutes.dashboard);
              },
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: const Text('Explore the app first'),
              style: OutlinedButton.styleFrom(
                foregroundColor: NexGenPalette.cyan,
                side: BorderSide(
                  color: NexGenPalette.cyan.withValues(alpha: 0.6),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ═══ 6. Tertiary: Create Account ═══
          TextButton.icon(
            onPressed: _navigateToSignup,
            icon: const Icon(Icons.person_add_outlined, size: 16),
            label: const Text('Create an account'),
            style: TextButton.styleFrom(
              foregroundColor: NexGenPalette.textMedium,
            ),
          ),

          const SizedBox(height: 4),

          // ═══ Return to login (de-emphasized) ═══
          TextButton(
            onPressed: () {
              ref.read(demoSessionProvider.notifier).endDemo();
              context.go(AppRoutes.login);
            },
            style: TextButton.styleFrom(
              foregroundColor: NexGenPalette.textMedium.withValues(alpha: 0.7),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: const Text('Return to Login'),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildContactForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          TextButton.icon(
            onPressed: () {
              setState(() => _showingContactForm = false);
            },
            icon: const Icon(Icons.arrow_back_ios, size: 16),
            label: const Text('Back'),
          ),

          const SizedBox(height: 16),

          Text(
            'Request a Consultation',
            style: Theme.of(context).textTheme.headlineMedium,
          ),

          const SizedBox(height: 8),

          Text(
            'Tell us how you\'d like to be contacted',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),

          const SizedBox(height: 32),

          // Contact method selection
          Text(
            'Preferred Contact Method',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: ContactMethod.values.map((method) {
              final isSelected = _selectedContactMethod == method;
              return _buildSelectionChip(
                label: method.displayName,
                icon: _getContactMethodIcon(method),
                isSelected: isSelected,
                onTap: () {
                  setState(() => _selectedContactMethod = method);
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 32),

          // Contact time selection
          Text(
            'Best Time to Reach You',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: ContactTime.values.map((time) {
              final isSelected = _selectedContactTime == time;
              return _buildSelectionChip(
                label: time.displayName,
                icon: _getContactTimeIcon(time),
                isSelected: isSelected,
                onTap: () {
                  setState(() => _selectedContactTime = time);
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 32),

          // Notes field
          Text(
            'Additional Notes (Optional)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Anything else you\'d like us to know?',
            ),
          ),

          const SizedBox(height: 40),

          // Submit button
          DemoPrimaryButton(
            label: 'Submit Request',
            icon: Icons.send,
            isLoading: _isSubmitting,
            onPressed: _submitConsultationRequest,
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSelectionChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? NexGenPalette.cyan.withValues(alpha: 0.15)
              : NexGenPalette.gunmetal.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isSelected
                        ? NexGenPalette.cyan
                        : NexGenPalette.textHigh,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getContactMethodIcon(ContactMethod method) {
    switch (method) {
      case ContactMethod.phone:
        return Icons.phone;
      case ContactMethod.email:
        return Icons.email;
      case ContactMethod.text:
        return Icons.sms;
    }
  }

  IconData _getContactTimeIcon(ContactTime time) {
    switch (time) {
      case ContactTime.morning:
        return Icons.wb_sunny_outlined;
      case ContactTime.afternoon:
        return Icons.wb_cloudy_outlined;
      case ContactTime.evening:
        return Icons.nightlight_outlined;
    }
  }
}
