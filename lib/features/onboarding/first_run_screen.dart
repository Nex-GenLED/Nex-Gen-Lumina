import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// First-run onboarding shown when welcomeCompleted == false.
///
/// Trusts the installer's handoff selections — does not re-ask the customer
/// for teams, holidays, or vibe (Bug 4a, 2026-05-07 tracker). Does not
/// auto-enable autopilot or generate a schedule (Bug 4c). The customer can
/// adjust preferences from Settings and turn on autopilot from the autopilot
/// screen whenever they choose.
class FirstRunScreen extends ConsumerStatefulWidget {
  const FirstRunScreen({super.key});

  @override
  ConsumerState<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends ConsumerState<FirstRunScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final profileAsync = ref.read(currentUserProfileProvider);
    final profile = profileAsync.maybeWhen(data: (p) => p, orElse: () => null);
    if (profile == null) return;

    // Mark welcome complete. Do NOT touch teams/holidays/vibe — those were
    // set by the installer during handoff and are authoritative. Do NOT
    // enable autopilot — that's an explicit user choice on the autopilot
    // screen.
    final userService = ref.read(userServiceProvider);
    await userService.updateUserProfile(profile.id, {
      'welcome_completed': true,
    });

    if (mounted) {
      context.go(AppRoutes.dashboard);
    }
  }

  void _nextPage() {
    if (_currentPage < 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
            // Page indicator (Welcome → Completion)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: List.generate(2, (i) {
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
            // Skip button only on the welcome page
            if (_currentPage < 1)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: TextButton(
                    onPressed: _completeOnboarding,
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
            'Your lights are ready to go. Auto-Pilot can take over your '
            'schedule with seasonal themes, game day colors, and holiday '
            'displays — turn it on from the Auto-Pilot tab whenever you\'re '
            'ready.',
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

  // ── Page 2: Completion ──

  Widget _buildCompletionPage() {
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
            'Your installer has set up your preferences. You can adjust them '
            'from Settings, and turn on Auto-Pilot from the Auto-Pilot tab '
            'whenever you\'re ready.',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 15, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _completeOnboarding,
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
}
