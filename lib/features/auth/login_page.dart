import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/auth/auth_manager.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/services/reviewer_seed_service.dart';
import 'package:nexgen_command/theme.dart';

/// Lumina Login Screen (complete rewrite)
/// - Gradient background (black -> midnight blue)
/// - Blur layer to smooth gradient
/// - Glass card with email/password inputs
/// - Gradient CTA button using InkWell
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  // ── Hidden gestures ────────────────────────────────────────────────────
  //
  // Two completely separate invisible 5-tap targets on the login screen.
  // Both are intentionally unlabeled, no visual feedback during the
  // sequence, no counter display, no haptics. A casual observer should
  // see nothing.
  //
  // 1. Lumina logo (Icon + LUMINA wordmark) → 5 taps inside a 3-second
  //    sliding window → navigate to /staff/pin (the unified staff PIN
  //    screen that handles Corporate / Sales / Installer modes).
  //
  // 2. "POWERED BY NEX-GEN" subtitle text → 5 taps with no time window
  //    → reveal the App Store reviewer button (autofills the reviewer
  //    test account email). This used to live on the logo; moved here
  //    so the staff PIN gesture can own the logo unambiguously.

  int _logoTapCount = 0;
  Timer? _logoTapResetTimer;
  static const Duration _logoTapWindow = Duration(seconds: 3);
  static const int _logoTapTarget = 5;

  int _subtitleTapCount = 0;
  bool _showReviewerButton = false;
  static const int _subtitleTapTarget = 5;

  @override
  void dispose() {
    _logoTapResetTimer?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Logo tap handler — staff PIN entry gesture ─────────────────────────
  //
  // Counts taps on the Lumina logo within a rolling 3-second window. Each
  // tap resets the timer. After 5 taps inside the window, navigate to the
  // staff PIN screen and reset the counter. After 3 seconds of no taps,
  // the counter resets silently.

  void _onLogoTap() {
    _logoTapCount++;
    _logoTapResetTimer?.cancel();

    if (_logoTapCount >= _logoTapTarget) {
      _logoTapCount = 0;
      // Defer navigation slightly so the tap event finishes propagating
      // before we push a new route. Avoids any chance of the gesture
      // arena getting confused mid-tap.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.push(AppRoutes.staffPin);
      });
      return;
    }

    _logoTapResetTimer = Timer(_logoTapWindow, () {
      _logoTapCount = 0;
    });
  }

  // ── Subtitle tap handler — App Store reviewer reveal ──────────────────
  //
  // Counts taps on the "POWERED BY NEX-GEN" subtitle. Once revealed, the
  // reviewer button stays visible (no auto-hide) so the App Store
  // reviewer can use it without re-tapping. No time window — the
  // reviewer flow doesn't need rate limiting.

  void _onSubtitleTap() {
    if (_showReviewerButton) return;
    _subtitleTapCount++;
    if (_subtitleTapCount >= _subtitleTapTarget) {
      setState(() => _showReviewerButton = true);
    }
  }

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    final pass = _passwordCtrl.text;
    final AuthManager auth = ref.read(authManagerProvider);
    setState(() => _loading = true);
    try {
      await auth.signInWithEmailAndPassword(email, pass);
      if (!mounted) return;
      context.go(AppRoutes.dashboard);
    } catch (e) {
      debugPrint('Login error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1B2A).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Reset Password',
                        style: GoogleFonts.montserrat(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your email address and we\'ll send you a link to reset your password.',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      color: Colors.white70,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Email',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      prefixIcon: const Icon(Icons.mail_outline, color: Colors.cyanAccent),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.cyanAccent),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required';
                      if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Colors.cyanAccent, Colors.blueAccent]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        if (!formKey.currentState!.validate()) return;
                        final email = emailController.text.trim();
                        final auth = ref.read(authManagerProvider);

                        try {
                          await auth.sendPasswordResetEmail(email);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Password reset email sent to $email'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to send reset email: $e'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        }
                      },
                      child: Center(
                        child: Text(
                          'SEND RESET LINK',
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final midnightBlue = const Color(0xFF0D1B2A);
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(children: [
        // Layer 1: Background Gradient
        Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, midnightBlue],
            ),
          ),
        ),
        // Layer 2: Blur
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        // Layer 3: Content
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Lumina logo cluster — Icon + LUMINA wordmark wrapped
                  // in a single GestureDetector so the staff-PIN gesture
                  // (5 taps inside 3 seconds) recognizes anywhere on the
                  // visible logo, not just the Icon hitbox. Behavior is
                  // invisible to a casual observer — no ripple, no
                  // animation, no counter display.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onLogoTap,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hub,
                            size: 60, color: Colors.cyanAccent),
                        const SizedBox(height: 12),
                        Text(
                          'LUMINA',
                          style: GoogleFonts.montserrat(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // "POWERED BY NEX-GEN" subtitle — separate hidden 5-tap
                  // gesture that reveals the App Store reviewer button.
                  // Stays invisible to casual observers; no ripple.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onSubtitleTap,
                    child: Text(
                      'POWERED BY NEX-GEN',
                      style: GoogleFonts.montserrat(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.cyanAccent,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Glass Card
                  Container(
                    width: 640,
                    constraints: const BoxConstraints(maxWidth: 640),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('Welcome back', style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                        const SizedBox(height: 14),

                        // Email
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Email',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            prefixIcon: const Icon(Icons.mail_outline, color: Colors.cyanAccent),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.cyanAccent)),
                            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.redAccent)),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Email is required';
                            if (!v.contains('@') || !v.contains('.')) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Password
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Password',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.06),
                            prefixIcon: const Icon(Icons.lock_outline, color: Colors.cyanAccent),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.cyanAccent)),
                            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.redAccent)),
                          ),
                          validator: (v) => (v == null || v.isEmpty) ? 'Password is required' : null,
                        ),

                        const SizedBox(height: 8),

                        // Forgot Password link
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _loading ? null : _handleForgotPassword,
                            child: Text(
                              'Forgot Password?',
                              style: GoogleFonts.montserrat(
                                color: Colors.cyanAccent,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // CTA Button (Gradient)
                        Container(
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Colors.cyanAccent, Colors.blueAccent]),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            onTap: _loading ? null : _handleSignIn,
                            child: Center(
                              child: _loading
                                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                                  : Text(
                                      'ENTER LUMINA',
                                      style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, color: Colors.black, letterSpacing: 1.2),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Create Account link row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don't have an account? ",
                              style: GoogleFonts.montserrat(color: Colors.white70, fontWeight: FontWeight.w500),
                            ),
                            TextButton(
                              onPressed: _loading ? null : () => context.push(AppRoutes.signUp),
                              child: Text(
                                'Create One',
                                style: GoogleFonts.montserrat(color: Colors.cyanAccent, fontWeight: FontWeight.w700),
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Demo Experience link
                        Center(
                          child: TextButton.icon(
                            onPressed: _loading ? null : () => context.push(AppRoutes.demoCode),
                            icon: Icon(
                              Icons.play_circle_outline,
                              size: 18,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            label: Text(
                              'Experience Nex-Gen Demo',
                              style: GoogleFonts.montserrat(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        // Staff access (Installer / Dealer / Sales / Corporate)
                        // is now reachable only via the hidden 5-tap gesture
                        // on the Lumina logo above. No visible button.
                        if (_showReviewerButton)
                          Center(
                            child: TextButton(
                              onPressed: () {
                                _emailCtrl.text = ReviewerSeedService.reviewerEmail;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Review credentials applied'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Text(
                                'App Store Review',
                                style: GoogleFonts.montserrat(
                                  color: NexGenPalette.textMedium,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Adapter to keep existing routes (AppRouter) working without changes.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override
  Widget build(BuildContext context) => const LoginScreen();
}
