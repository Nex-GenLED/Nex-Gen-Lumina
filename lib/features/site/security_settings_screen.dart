import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/services/account_deletion_service.dart';
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

  /// Collects the account password so the session can be refreshed before any
  /// data is touched. Returns null if the user backs out.
  Future<String?> _promptForPassword() async {
    final ctrl = TextEditingController();
    var obscure = true;
    try {
      return await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Confirm your password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter your password to confirm. Nothing is deleted until '
                  'this succeeds.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  obscureText: obscure,
                  autofocus: true,
                  onSubmitted: (v) => Navigator.of(context).pop(v),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setDialogState(() => obscure = !obscure),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(ctrl.text),
                child: const Text('Confirm', style: TextStyle(color: Color(0xFFFF6B6B))),
              ),
            ],
          ),
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  /// Everything account deletion now removes.
  ///
  /// The old copy — "This will wipe your saved patterns and cannot be undone."
  /// — was wrong in both directions at once
  /// ([audit/OVERNIGHT_DATA_LIFECYCLE_AUDIT.md](audit/OVERNIGHT_DATA_LIFECYCLE_AUDIT.md)
  /// §1.1): it *understated* the intent (the button claims to delete the
  /// account, not a pattern list) while *overstating* the effect (the flow
  /// deleted one Firestore document and orphaned ~34 subcollections). Now that
  /// `purgeUserAccount` genuinely sweeps all of it, the dialog says so.
  static const List<String> _deletionInventory = [
    'Your profile, address and contact details',
    'Every controller, property and geofence you have set up',
    'All schedules, scenes, designs, favourites and saved patterns',
    'Your house photo',
    'Game Day, Autopilot and Neighborhood Sync settings',
    'Usage history and diagnostic reports',
  ];

  Future<void> _confirmAndDeleteAccount() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This permanently deletes:'),
            const SizedBox(height: 8),
            for (final item in _deletionInventory)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('•  $item'),
              ),
            const SizedBox(height: 12),
            const Text(
              'Your lights will keep running whatever schedule is already '
              'stored on the controller until it is reset by an installer.',
            ),
            const SizedBox(height: 12),
            const Text(
              'This cannot be undone.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
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

    // ── F-2 (P0): password FIRST, before anything is deleted. ──────────────
    // The old flow deleted `users/{uid}`, then called `user.delete()`, then
    // caught `requires-recent-login` and told the user to sign in again — by
    // which point their profile document was already gone and nothing
    // recreates it. Collecting the password up front turns that unrecoverable
    // state into a cancellable dialog.
    final password = await _promptForPassword();
    if (password == null || password.isEmpty) return;

    setState(() => _deleting = true);
    try {
      final result = await ref.read(accountDeletionServiceProvider).deleteAccount(
            account: FirebaseDeletableAccount(user),
            password: password,
          );
      if (!mounted) return;
      if (result.success) {
        context.go(AppRoutes.login);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 6),
        content: Text(result.message ?? 'Delete failed.'),
      ));
      // Data gone but Auth alive: the session is now pointing at nothing, so
      // send them to the login screen rather than back into an empty app.
      if (result.dataWasDeleted) {
        await fb.FirebaseAuth.instance.signOut();
        if (!mounted) return;
        context.go(AppRoutes.login);
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
        padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context)),
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
