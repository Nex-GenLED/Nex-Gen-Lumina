import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/models/sub_user_permissions.dart';
import 'package:nexgen_command/services/invitation_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// Screen for managing sub-users (family members) of an installation.
///
/// Accessible from the My Profile page. Allows primary users to:
/// - View current sub-users
/// - Invite new sub-users via email
/// - Revoke access
/// - Modify permissions
class SubUsersScreen extends ConsumerStatefulWidget {
  const SubUsersScreen({super.key});

  @override
  ConsumerState<SubUsersScreen> createState() => _SubUsersScreenState();
}

class _SubUsersScreenState extends ConsumerState<SubUsersScreen> {
  String? _installationId;
  int? _maxSubUsers;
  bool _isLoading = true;
  bool _isPrimaryUser = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final installationId = data['installation_id'] as String?;
        final role = data['installation_role'] as String?;

        if (installationId != null) {
          final installDoc = await FirebaseFirestore.instance
              .collection('installations')
              .doc(installationId)
              .get();

          if (installDoc.exists) {
            setState(() {
              _installationId = installationId;
              _maxSubUsers = installDoc.data()?['max_sub_users'] as int? ?? 5;
              _isPrimaryUser = role == 'primary';
              _isLoading = false;
            });
            return;
          }
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: const GlassAppBar(title: Text('Manage Users')),
        body: const Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan),
        ),
      );
    }

    if (_installationId == null) {
      return Scaffold(
        appBar: const GlassAppBar(title: Text('Manage Users')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.warning_amber, size: 64, color: Colors.amber.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              Text(
                'No installation found',
                style: TextStyle(color: NexGenPalette.textMedium, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final subUsersAsync = ref.watch(subUsersProvider(_installationId!));
    final pendingInvitesAsync = ref.watch(pendingInvitationsProvider(_installationId!));

    return Scaffold(
      appBar: const GlassAppBar(title: Text('Manage Users')),
      floatingActionButton: _isPrimaryUser
          ? FloatingActionButton.extended(
              onPressed: () => _showInviteDialog(context),
              backgroundColor: NexGenPalette.cyan,
              icon: const Icon(Icons.person_add, color: Colors.black),
              label: const Text('Invite', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sub-user count
          subUsersAsync.when(
            data: (subUsers) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.people, color: NexGenPalette.cyan),
                  const SizedBox(width: 12),
                  Text(
                    'Family Members',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const Spacer(),
                  Text(
                    '${subUsers.length} / $_maxSubUsers',
                    style: TextStyle(
                      color: subUsers.length >= (_maxSubUsers ?? 5)
                          ? Colors.amber
                          : NexGenPalette.cyan,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),

          // Current sub-users
          const Text(
            'CURRENT MEMBERS',
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          subUsersAsync.when(
            data: (subUsers) {
              if (subUsers.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: NexGenPalette.gunmetal90,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.group_off, size: 48, color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text(
                        'No family members yet',
                        style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
                      ),
                      if (_isPrimaryUser) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Tap "Invite" to add someone',
                          style: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.7), fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return Column(
                children: subUsers.map((subUser) => _SubUserTile(
                  subUser: subUser,
                  isPrimaryUser: _isPrimaryUser,
                  installationId: _installationId!,
                  onRevoke: () => _revokeAccess(subUser),
                )).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator(color: NexGenPalette.cyan)),
            error: (e, _) => Text('Error loading members: $e', style: const TextStyle(color: Colors.red)),
          ),
          const SizedBox(height: 24),

          // Pending invitations
          pendingInvitesAsync.when(
            data: (invites) {
              if (invites.isEmpty) return const SizedBox.shrink();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PENDING INVITATIONS',
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...invites.map((invite) => _PendingInviteTile(
                    invite: invite,
                    isPrimaryUser: _isPrimaryUser,
                    onRevoke: () => _revokeInvite(invite.id),
                    onResend: () => _resendInvite(invite.id),
                  )),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _showInviteDialog(BuildContext context) async {
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    SubUserPermissions permissions = SubUserPermissions.basic;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: NexGenPalette.gunmetal90,
          title: const Text('Invite Family Member', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Email Address *',
                    labelStyle: TextStyle(color: NexGenPalette.textMedium),
                    hintText: 'name@example.com',
                    hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: NexGenPalette.line.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Name (optional)',
                    labelStyle: TextStyle(color: NexGenPalette.textMedium),
                    hintText: 'John',
                    hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: NexGenPalette.line.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'PERMISSIONS',
                  style: TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                _PermissionToggle(
                  label: 'Control Lights',
                  value: permissions.canControl,
                  enabled: false, // Always enabled for sub-users
                  onChanged: null,
                ),
                _PermissionToggle(
                  label: 'Change Patterns',
                  value: permissions.canChangePatterns,
                  onChanged: (v) => setDialogState(() =>
                      permissions = permissions.copyWith(canChangePatterns: v)),
                ),
                _PermissionToggle(
                  label: 'Edit Schedules',
                  value: permissions.canEditSchedules,
                  onChanged: (v) => setDialogState(() =>
                      permissions = permissions.copyWith(canEditSchedules: v)),
                ),
                _PermissionToggle(
                  label: 'Invite Others',
                  value: permissions.canInvite,
                  onChanged: (v) => setDialogState(() =>
                      permissions = permissions.copyWith(canInvite: v)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
            ),
            ElevatedButton(
              onPressed: () {
                final email = emailController.text.trim();
                if (email.isEmpty || !email.contains('@')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid email'), backgroundColor: Colors.red),
                  );
                  return;
                }
                Navigator.of(context).pop({
                  'email': email,
                  'name': nameController.text.trim(),
                  'permissions': permissions,
                });
              },
              style: ElevatedButton.styleFrom(backgroundColor: NexGenPalette.cyan),
              child: const Text('Send Invite', style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    await _sendInvite(
      email: result['email'] as String,
      name: result['name'] as String?,
      permissions: result['permissions'] as SubUserPermissions,
    );
  }

  Future<void> _sendInvite({
    required String email,
    String? name,
    required SubUserPermissions permissions,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _installationId == null) return;

    try {
      final invite = await ref.read(invitationServiceProvider).createInvitation(
        installationId: _installationId!,
        primaryUserId: user.uid,
        inviteeEmail: email,
        inviteeName: name?.isNotEmpty == true ? name : null,
        permissions: permissions,
      );

      if (mounted) {
        // Show success with the invitation code
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: NexGenPalette.gunmetal90,
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                const Text('Invitation Sent', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Share this code with $email:',
                  style: TextStyle(color: NexGenPalette.textMedium),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: NexGenPalette.line.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        invite.token,
                        style: const TextStyle(
                          color: NexGenPalette.cyan,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.copy, color: NexGenPalette.cyan),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: invite.token));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Code copied!'),
                              backgroundColor: NexGenPalette.cyan,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This code expires in 7 days.',
                  style: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.7), fontSize: 12),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(backgroundColor: NexGenPalette.cyan),
                child: const Text('Done', style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send invite: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _revokeAccess(SubUser subUser) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Remove Access?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to remove ${subUser.name}\'s access to this system?',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true || _installationId == null) return;

    try {
      await ref.read(invitationServiceProvider).revokeAccess(
        installationId: _installationId!,
        userId: subUser.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access removed'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove access: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _revokeInvite(String inviteId) async {
    try {
      await ref.read(invitationServiceProvider).revokeInvitation(inviteId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation revoked'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to revoke: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _resendInvite(String inviteId) async {
    try {
      final newInvite = await ref.read(invitationServiceProvider).resendInvitation(inviteId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('New code: ${newInvite.token}'), backgroundColor: NexGenPalette.cyan),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resend: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _SubUserTile extends StatelessWidget {
  final SubUser subUser;
  final bool isPrimaryUser;
  final String installationId;
  final VoidCallback onRevoke;

  const _SubUserTile({
    required this.subUser,
    required this.isPrimaryUser,
    required this.installationId,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: NexGenPalette.cyan.withValues(alpha: 0.2),
            child: Text(
              subUser.name.isNotEmpty ? subUser.name[0].toUpperCase() : 'U',
              style: const TextStyle(color: NexGenPalette.cyan, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subUser.name,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                Text(
                  subUser.email,
                  style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                ),
              ],
            ),
          ),
          if (isPrimaryUser)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              onPressed: onRevoke,
            ),
        ],
      ),
    );
  }
}

class _PendingInviteTile extends StatelessWidget {
  final dynamic invite;
  final bool isPrimaryUser;
  final VoidCallback onRevoke;
  final VoidCallback onResend;

  const _PendingInviteTile({
    required this.invite,
    required this.isPrimaryUser,
    required this.onRevoke,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.amber.withValues(alpha: 0.2),
            child: const Icon(Icons.hourglass_empty, color: Colors.amber, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.inviteeEmail,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                Row(
                  children: [
                    Text(
                      'Code: ',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                    ),
                    Text(
                      invite.token,
                      style: const TextStyle(color: NexGenPalette.cyan, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      ' • ${invite.daysRemaining}d left',
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isPrimaryUser) ...[
            IconButton(
              icon: const Icon(Icons.refresh, color: NexGenPalette.cyan, size: 20),
              onPressed: onResend,
              tooltip: 'Resend',
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red, size: 20),
              onPressed: onRevoke,
              tooltip: 'Revoke',
            ),
          ],
        ],
      ),
    );
  }
}

class _PermissionToggle extends StatelessWidget {
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  const _PermissionToggle({
    required this.label,
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : NexGenPalette.textMedium,
                fontSize: 14,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeColor: NexGenPalette.cyan,
          ),
        ],
      ),
    );
  }
}
