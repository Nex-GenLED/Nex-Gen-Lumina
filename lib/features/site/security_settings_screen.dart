import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends ConsumerState<SecuritySettingsScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _changing = false;
  bool _deleting = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleChangePassword() async {
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not signed in')));
      return;
    }
    final email = user.email;
    if (email == null || email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account missing email.')));
      return;
    }
    final current = _currentCtrl.text.trim();
    final next = _newCtrl.text.trim();
    if (current.isEmpty || next.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter current and new password.')));
      return;
    }
    if (next.length < 6) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('New password must be at least 6 characters.')));
      return;
    }
    setState(() => _changing = true);
    try {
      final cred = fb.EmailAuthProvider.credential(email: email, password: current);
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.green.shade600, content: const Text('Password updated successfully')));
      _currentCtrl.clear();
      _newCtrl.clear();
    } catch (e) {
      debugPrint('Change password error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red.shade600, content: Text('Failed to change password: $e')));
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Future<void> _confirmAndDeleteAccount() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('This will wipe your saved patterns and cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF6B6B))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not signed in')));
      return;
    }

    setState(() => _deleting = true);
    try {
      // Delete Firestore doc
      final svc = ref.read(userServiceProvider);
      await svc.deleteUser(user.uid);
      // Delete auth user
      await user.delete();
      if (!mounted) return;
      context.go(AppRoutes.login);
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('Delete account error: ${e.code} $e');
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in again to delete your account.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red.shade600, content: Text('Delete failed: ${e.message ?? e.code}')));
      }
    } catch (e) {
      debugPrint('Delete account error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red.shade600, content: Text('Delete failed: $e')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Change Password', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
            ),
            child: Column(children: [
              _PasswordField(
                controller: _currentCtrl,
                label: 'Current Password',
                obscure: _obscureCurrent,
                onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
              ),
              const SizedBox(height: 12),
              _PasswordField(
                controller: _newCtrl,
                label: 'New Password',
                obscure: _obscureNew,
                onToggle: () => setState(() => _obscureNew = !_obscureNew),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: _changing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock_reset),
                  label: Text(_changing ? 'Updating…' : 'Change Password'),
                  onPressed: _changing ? null : _handleChangePassword,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 28),
          Text('Danger Zone', style: Theme.of(context).textTheme.titleLarge?.withColor(const Color(0xFFFF6B6B))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFFF6B6B).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Delete Account', style: Theme.of(context).textTheme.titleMedium?.withColor(const Color(0xFFFF6B6B))),
              const SizedBox(height: 8),
              Text('This permanently deletes your profile and saved patterns.', style: Theme.of(context).textTheme.bodyMedium?.withColor(NexGenPalette.textMedium)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF6B6B), side: const BorderSide(color: Color(0xFFFF6B6B))),
                    onPressed: _deleting ? null : _confirmAndDeleteAccount,
                    icon: _deleting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_forever),
                    label: Text(_deleting ? 'Deleting…' : 'Delete Account'),
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  const _PasswordField({required this.controller, required this.label, required this.obscure, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: obscure ? 'Show' : 'Hide',
          icon: Icon(obscure ? Icons.visibility : Icons.visibility_off, color: Theme.of(context).colorScheme.onSurfaceVariant),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
