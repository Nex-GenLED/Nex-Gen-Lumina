import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/auth/account_session.dart';
import 'package:nexgen_command/theme.dart';

/// "Sign out" for screens the router otherwise holds the customer on (forced
/// password reset, first run). Signs out, then goes to the login page; a
/// failed sign-out is shown, not swallowed.
class AccountSignOutButton extends ConsumerStatefulWidget {
  const AccountSignOutButton({super.key, this.enabled = true});

  /// False while the host screen is mid-write, so the two cannot race.
  final bool enabled;

  @override
  ConsumerState<AccountSignOutButton> createState() =>
      _AccountSignOutButtonState();
}

class _AccountSignOutButtonState extends ConsumerState<AccountSignOutButton> {
  bool _busy = false;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await ref.read(accountSessionProvider).signOut();
      if (mounted) context.go(AppRoutes.login);
    } catch (e) {
      debugPrint('Sign out failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't sign out: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const ValueKey('account-sign-out'),
      onPressed: widget.enabled && !_busy ? _signOut : null,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.logout, size: 18),
      label: const Text('Sign out'),
      style: TextButton.styleFrom(foregroundColor: NexGenPalette.textMedium),
    );
  }
}
