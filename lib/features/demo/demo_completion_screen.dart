import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/demo/demo_lead_service.dart';
import 'package:nexgen_command/features/demo/demo_models.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/demo/widgets/demo_scaffold.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/theme.dart';

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
                color: NexGenPalette.gunmetal.withOpacity(0.95),
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
                      color: NexGenPalette.cyan.withOpacity(0.1),
                      border: Border.all(
                        color: NexGenPalette.cyan.withOpacity(0.5),
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
    final patternsViewed = ref.watch(demoPatternsViewedProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: Container(
        decoration: const BoxDecoration(
          gradient: NexGenPalette.atmosphere,
        ),
        child: SafeArea(
          child: _showingContactForm
              ? _buildContactForm()
              : _buildCompletionSummary(lead, patternsViewed),
        ),
      ),
    );
  }

  Widget _buildCompletionSummary(DemoLead? lead, List<String> patternsViewed) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Success header
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  NexGenPalette.cyan,
                  NexGenPalette.blue,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: NexGenPalette.cyan.withOpacity(0.4),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Icon(
              Icons.celebration,
              size: 50,
              color: Colors.black,
            ),
          ),

          const SizedBox(height: 32),

          Text(
            'Demo Complete!',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          Text(
            'You\'ve experienced the Nex-Gen difference',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Summary stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard(
                Icons.palette_outlined,
                '${patternsViewed.length}',
                'Patterns\nViewed',
              ),
              _buildStatCard(
                Icons.schedule_outlined,
                '3',
                'Schedules\nPreviewed',
              ),
              _buildStatCard(
                Icons.auto_awesome_outlined,
                '1',
                'AI\nSession',
              ),
            ],
          ),

          const SizedBox(height: 40),

          // CTA Card
          DemoGlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(
                  Icons.lightbulb,
                  size: 48,
                  color: NexGenPalette.cyan,
                ),
                const SizedBox(height: 16),
                Text(
                  'Ready to Transform Your Home?',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Get a free consultation with a Nex-Gen lighting specialist',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: NexGenPalette.textMedium,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                DemoPrimaryButton(
                  label: 'Request Free Consultation',
                  icon: Icons.calendar_today,
                  onPressed: () {
                    setState(() => _showingContactForm = true);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Secondary options
          Row(
            children: [
              Expanded(
                child: DemoSecondaryButton(
                  label: 'Create Account',
                  icon: Icons.person_add_outlined,
                  onPressed: _navigateToSignup,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          TextButton(
            onPressed: () {
              ref.read(demoSessionProvider.notifier).endDemo();
              context.go(AppRoutes.login);
            },
            child: const Text('Return to Login'),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label) {
    return DemoGlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          Icon(
            icon,
            size: 28,
            color: NexGenPalette.cyan,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: NexGenPalette.cyan,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
            textAlign: TextAlign.center,
          ),
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
              ? NexGenPalette.cyan.withOpacity(0.15)
              : NexGenPalette.gunmetal.withOpacity(0.5),
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
