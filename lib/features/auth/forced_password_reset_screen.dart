import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/theme.dart';

/// One-time forced password reset shown the first time a customer logs in
/// with the temp password issued during installer handoff. Cleared by
/// flipping `users/{uid}.must_reset_password` to `false` after a successful
/// Firebase Auth password update.
///
/// Navigation in/out is gated by `appRedirect` in route_guards.dart — this
/// screen does not render its own back button and ignores system back.
class ForcedPasswordResetScreen extends ConsumerStatefulWidget {
  const ForcedPasswordResetScreen({super.key});

  @override
  ConsumerState<ForcedPasswordResetScreen> createState() =>
      _ForcedPasswordResetScreenState();
}

class _ForcedPasswordResetScreenState
    extends ConsumerState<ForcedPasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _formError;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validateNewPassword(String? v) {
    if (v == null || v.isEmpty) return 'New password is required';
    if (v.length < 8) return 'New password must be at least 8 characters';
    if (v == _currentCtrl.text) {
      return 'New password must be different from your current password';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'Please confirm your new password';
    if (v != _newCtrl.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      setState(() => _formError = 'Not signed in. Please log in again.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentCtrl.text,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(_newCtrl.text);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'must_reset_password': false});

      if (!mounted) return;
      context.go(AppRoutes.dashboard);
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'wrong-password':
        case 'invalid-credential':
          msg = 'Current password is incorrect.';
          break;
        case 'weak-password':
          msg = 'New password is too weak. Use at least 8 characters.';
          break;
        case 'requires-recent-login':
          msg = 'Please sign in again, then retry.';
          break;
        case 'network-request-failed':
          msg = 'Network error. Check your connection and try again.';
          break;
        default:
          msg = e.message ?? 'Could not update password (${e.code}).';
      }
      if (mounted) setState(() => _formError = msg);
    } catch (e) {
      if (mounted) setState(() => _formError = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Stack(children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, NexGenPalette.midnightBlue],
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(color: Colors.transparent),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.hub,
                        size: 60, color: NexGenPalette.cyan),
                    const SizedBox(height: 12),
                    Text(
                      'LUMINA',
                      style: TextStyle(
                        fontFamily: GoogleFonts.exo2().fontFamily,
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 32),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Welcome to Lumina!',
                              style: TextStyle(
                                fontFamily: GoogleFonts.exo2().fontFamily,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'For your security, please set a new '
                              'password before continuing.',
                              style: TextStyle(
                                fontFamily: GoogleFonts.dmSans().fontFamily,
                                fontSize: 14,
                                color: NexGenPalette.textMedium,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            _buildPasswordField(
                              controller: _currentCtrl,
                              hint: 'Current Password (temp password)',
                              obscure: _obscureCurrent,
                              onToggle: () => setState(
                                  () => _obscureCurrent = !_obscureCurrent),
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'Current password is required'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            _buildPasswordField(
                              controller: _newCtrl,
                              hint: 'New Password (min 8 characters)',
                              obscure: _obscureNew,
                              onToggle: () =>
                                  setState(() => _obscureNew = !_obscureNew),
                              validator: _validateNewPassword,
                            ),
                            const SizedBox(height: 12),
                            _buildPasswordField(
                              controller: _confirmCtrl,
                              hint: 'Confirm New Password',
                              obscure: _obscureConfirm,
                              onToggle: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
                              validator: _validateConfirm,
                            ),
                            if (_formError != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.redAccent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: Colors.redAccent
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Colors.redAccent, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _formError!,
                                        style: TextStyle(
                                          fontFamily:
                                              GoogleFonts.dmSans().fontFamily,
                                          color: Colors.redAccent,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            Container(
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  NexGenPalette.cyan,
                                  NexGenPalette.blue,
                                ]),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                splashColor: Colors.transparent,
                                highlightColor: Colors.transparent,
                                onTap: _submitting ? null : _submit,
                                child: Center(
                                  child: _submitting
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                            color: Colors.black,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          'SET NEW PASSWORD',
                                          style: TextStyle(
                                            fontFamily:
                                                GoogleFonts.exo2().fontFamily,
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
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      enabled: !_submitting,
      style: TextStyle(
          color: Colors.white, fontFamily: GoogleFonts.dmSans().fontFamily),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontFamily: GoogleFonts.dmSans().fontFamily,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        prefixIcon:
            const Icon(Icons.lock_outline, color: NexGenPalette.cyan),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility : Icons.visibility_off,
            color: NexGenPalette.cyan,
          ),
          onPressed: onToggle,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NexGenPalette.cyan),
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
      validator: validator,
    );
  }
}
