import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:nexgen_command/nav.dart';

class UserProfileScreen extends ConsumerWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Profile')),
      body: auth.when(
        data: (fb.User? user) {
          if (user == null) return const _SignedOutState();
          final stream = ref.read(userServiceProvider).streamUser(user.uid);
          return StreamBuilder<UserModel?>(
            stream: stream,
            builder: (context, snap) {
              final model = snap.data;
              final displayName = (model?.displayName?.trim().isNotEmpty ?? false)
                  ? model!.displayName
                  : (user.displayName ?? 'User');
              final email = user.email ?? model?.email ?? '';
              final photoUrl = model?.photoUrl ?? user.photoURL;
              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  _ProfileHeader(
                    name: displayName,
                    email: email,
                    photoUrl: photoUrl,
                  ),
                  const SizedBox(height: 12),
                  _MenuTile(
                    icon: Icons.person_outline,
                    label: 'Edit Profile',
                    onTap: () => context.push(AppRoutes.profileEdit),
                  ),
                  _MenuTile(
                    icon: Icons.lock_outline,
                    label: 'Security & Password',
                    onTap: () => context.push(AppRoutes.security),
                  ),
                  // Show "Manage Users" for users with installation access
                  if (model?.installationId != null) ...[
                    _MenuTile(
                      icon: Icons.people_outline,
                      label: 'Manage Family Members',
                      onTap: () => context.push(AppRoutes.subUsers),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _MenuTile(
                    icon: Icons.logout,
                    label: 'Sign Out',
                    iconColor: const Color(0xFFFF6B6B),
                    labelColor: const Color(0xFFFF6B6B),
                    onTap: () async {
                      try {
                        await ref.read(authManagerProvider).signOut();
                        if (context.mounted) context.go(AppRoutes.login);
                      } catch (e) {
                        debugPrint('Sign out failed: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Sign out failed: $e')),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          );
        },
        error: (e, st) => Center(child: Text('Auth error: $e')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String name;
  final String email;
  final String? photoUrl;
  const _ProfileHeader({required this.name, required this.email, this.photoUrl});

  String _initials(String n) {
    final parts = n.trim().split(RegExp(r"\s+"));
    if (parts.isEmpty) return 'U';
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    final init = (first + last).toUpperCase();
    return init.isEmpty ? 'U' : init;
  }

  @override
  Widget build(BuildContext context) {
    final gradient = const LinearGradient(
      colors: [NexGenPalette.cyan, NexGenPalette.matteBlack],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      decoration: BoxDecoration(gradient: gradient),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: NexGenPalette.cyan, width: 2),
            boxShadow: [
              BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: 2),
            ],
          ),
          child: CircleAvatar(
            radius: 50,
            backgroundColor: Colors.black,
            backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty) ? NetworkImage(photoUrl!) : null,
            child: (photoUrl == null || photoUrl!.isEmpty)
                ? Text(_initials(name), style: Theme.of(context).textTheme.headlineMedium?.bold.withColor(NexGenPalette.cyan))
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Text(name, style: Theme.of(context).textTheme.headlineSmall?.bold),
        const SizedBox(height: 6),
        Text(email, style: Theme.of(context).textTheme.bodyMedium?.withColor(NexGenPalette.textMedium)),
      ]),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;
  const _MenuTile({required this.icon, required this.label, required this.onTap, this.iconColor, this.labelColor});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final baseIconColor = iconColor ?? NexGenPalette.textMedium;
    final baseLabelColor = labelColor ?? onSurface;
    return ListTile(
      leading: Icon(icon, color: baseIconColor),
      title: Text(label, style: Theme.of(context).textTheme.titleMedium?.withColor(baseLabelColor)),
      trailing: Icon(Icons.chevron_right, color: NexGenPalette.textMedium),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
    );
  }
}

class _SignedOutState extends StatelessWidget {
  const _SignedOutState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.person_off_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 40),
          const SizedBox(height: 12),
          Text('Sign in required', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Please sign in to view your profile.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        ]),
      ),
    );
  }
}
