import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'neighborhood_models.dart';
import 'neighborhood_providers.dart';
import 'widgets/member_position_list.dart';
import 'widgets/neighborhood_onboarding.dart';
import 'widgets/schedule_list.dart';
import 'widgets/sync_control_panel.dart';

/// Main screen for Neighborhood Sync feature.
///
/// Allows users to:
/// - Create new neighborhood groups
/// - Join existing groups via invite code
/// - Configure their home's position and LED count
/// - Start/stop synchronized animations across all homes
class NeighborhoodSyncScreen extends ConsumerStatefulWidget {
  const NeighborhoodSyncScreen({super.key});

  @override
  ConsumerState<NeighborhoodSyncScreen> createState() => _NeighborhoodSyncScreenState();
}

class _NeighborhoodSyncScreenState extends ConsumerState<NeighborhoodSyncScreen> {
  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(userNeighborhoodsProvider);
    final activeGroup = ref.watch(activeNeighborhoodProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Neighborhood Sync'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (activeGroup.valueOrNull != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showGroupInfo(activeGroup.value!),
            ),
        ],
      ),
      body: groupsAsync.when(
        data: (groups) {
          if (groups.isEmpty) {
            // Show engaging onboarding experience
            return NeighborhoodOnboarding(
              onCreateGroup: _showCreateGroupDialog,
              onJoinGroup: _showJoinGroupDialog,
              onFindNearby: _showFindNearbyDialog,
            );
          }

          // Auto-select first group if none selected
          final activeId = ref.read(activeNeighborhoodIdProvider);
          if (activeId == null && groups.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(activeNeighborhoodIdProvider.notifier).state = groups.first.id;
            });
          }

          return _buildGroupContent(groups, activeGroup.valueOrNull);
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.cyan),
        ),
        error: (e, _) => NeighborhoodErrorState(
          onRetry: () => ref.invalidate(userNeighborhoodsProvider),
          onCreateGroup: _showCreateGroupDialog,
          errorMessage: e.toString().contains('permission')
              ? 'Please check your internet connection and try again.'
              : null,
        ),
      ),
    );
  }

  Widget _buildGroupContent(List<NeighborhoodGroup> groups, NeighborhoodGroup? activeGroup) {
    if (activeGroup == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }

    final membersAsync = ref.watch(neighborhoodMembersProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group selector (if multiple groups)
          if (groups.length > 1) ...[
            _buildGroupSelector(groups, activeGroup),
            const SizedBox(height: 16),
          ],

          // Group header with invite code
          _buildGroupHeader(activeGroup),
          const SizedBox(height: 24),

          // Member list
          const Text(
            'Homes in Sync Order',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Drag to reorder how the animation flows between homes',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          membersAsync.when(
            data: (members) => MemberPositionList(
              members: members,
              onReorder: (orderedIds) {
                ref.read(neighborhoodNotifierProvider.notifier).reorderMembers(orderedIds);
              },
              onMemberTap: (member) => _showMemberConfigDialog(member),
            ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: Colors.cyan),
              ),
            ),
            error: (e, _) => Center(
              child: Text(
                'Error loading members',
                style: TextStyle(color: Colors.grey.shade400),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Sync control panel
          membersAsync.when(
            data: (members) => SyncControlPanel(
              members: members,
              group: activeGroup,
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 24),

          // Schedule list
          NeighborhoodScheduleList(group: activeGroup),

          const SizedBox(height: 32),

          // Actions
          _buildGroupActions(activeGroup),
        ],
      ),
    );
  }

  Widget _buildGroupSelector(List<NeighborhoodGroup> groups, NeighborhoodGroup activeGroup) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: groups.map((group) {
          final isActive = group.id == activeGroup.id;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                ref.read(activeNeighborhoodIdProvider.notifier).state = group.id;
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isActive ? Colors.cyan.withOpacity(0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  group.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive ? Colors.cyan : Colors.grey.shade500,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGroupHeader(NeighborhoodGroup group) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.cyan.withOpacity(0.2),
            Colors.purple.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyan.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.cyan.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.home_work,
              color: Colors.cyan,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 14,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${group.memberCount} ${group.memberCount == 1 ? "home" : "homes"}',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Invite code
          GestureDetector(
            onTap: () => _copyInviteCode(group.inviteCode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    group.inviteCode,
                    style: const TextStyle(
                      color: Colors.cyan,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.copy,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupActions(NeighborhoodGroup group) {
    return Column(
      children: [
        // Share invite section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.cyan.withOpacity(0.1),
                Colors.purple.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.cyan.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.share, color: Colors.cyan, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Grow Your Crew',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Share your invite code with neighbors to expand the light show!',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _copyInviteCode(group.inviteCode),
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text('Copy Code: ${group.inviteCode}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyan,
                    side: const BorderSide(color: Colors.cyan),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Leave group
        TextButton.icon(
          onPressed: () => _showLeaveGroupDialog(group),
          icon: Icon(Icons.logout, size: 16, color: Colors.grey.shade600),
          label: Text(
            'Leave Crew',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }

  void _showCreateGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => const _CreateGroupDialog(),
    ).then((group) {
      // Group created successfully, it's auto-selected by the provider
    });
  }

  void _showJoinGroupDialog() {
    final controller = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.cyan.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.login, color: Colors.cyan, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Join the Party',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Got an invite code? Enter it below to join your neighbors\' light show crew.',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                letterSpacing: 4,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'Secret Code',
                hintText: 'XXXXXX',
                labelStyle: TextStyle(color: Colors.grey.shade500),
                hintStyle: TextStyle(color: Colors.grey.shade700),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade700),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyan),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(6),
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Your Home\'s Nickname',
                hintText: 'e.g., The Corner House, Casa de Lumina',
                labelStyle: TextStyle(color: Colors.grey.shade500),
                hintStyle: TextStyle(color: Colors.grey.shade700),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade700),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyan),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              if (controller.text.trim().length != 6) return;

              Navigator.pop(context);
              final group = await ref.read(neighborhoodNotifierProvider.notifier).joinGroup(
                controller.text.trim().toUpperCase(),
                displayName: nameController.text.trim().isNotEmpty
                    ? nameController.text.trim()
                    : null,
              );

              if (group == null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Hmm, that code didn\'t work. Double-check it and try again!'),
                    backgroundColor: Colors.orange,
                  ),
                );
              } else if (group != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Welcome to ${group.name}! Let\'s light it up!'),
                    backgroundColor: Colors.green.shade700,
                  ),
                );
              }
            },
            icon: const Icon(Icons.celebration, size: 18),
            label: const Text('Join In'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  void _showLeaveGroupDialog(NeighborhoodGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Leave Group?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to leave "${group.name}"? You\'ll need an invite code to rejoin.',
          style: TextStyle(color: Colors.grey.shade400),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(neighborhoodNotifierProvider.notifier).leaveCurrentGroup();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _showGroupInfo(NeighborhoodGroup group) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.cyan),
                const SizedBox(width: 12),
                Text(
                  group.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _infoRow('Invite Code', group.inviteCode),
            _infoRow('Members', '${group.memberCount} homes'),
            _infoRow('Created', _formatDate(group.createdAt)),
            _infoRow('Status', group.isActive ? 'Syncing' : 'Idle'),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _copyInviteCode(group.inviteCode),
                icon: const Icon(Icons.copy),
                label: const Text('Copy Invite Code'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyan,
                  side: const BorderSide(color: Colors.cyan),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade500),
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showMemberConfigDialog(NeighborhoodMember member) {
    showDialog(
      context: context,
      builder: (context) => MemberConfigDialog(member: member),
    );
  }

  void _showFindNearbyDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _FindNearbyGroupsSheet(),
    );
  }

  void _copyInviteCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invite code "$code" copied to clipboard'),
        backgroundColor: Colors.cyan.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}

/// Enhanced dialog for creating a new neighborhood group with full configuration.
class _CreateGroupDialog extends ConsumerStatefulWidget {
  const _CreateGroupDialog();

  @override
  ConsumerState<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends ConsumerState<_CreateGroupDialog> {
  final _groupNameController = TextEditingController();
  final _homeNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  bool _isPublic = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _groupNameController.dispose();
    _homeNameController.dispose();
    _descriptionController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey.shade900,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.cyan.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.celebration, color: Colors.cyan, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Start Your Block Party',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group Name
              _buildTextField(
                controller: _groupNameController,
                label: 'Give Your Crew a Name',
                hint: 'e.g., Maple Street Lights, The Block Squad',
                autofocus: true,
              ),
              const SizedBox(height: 16),

              // Your Home Name
              _buildTextField(
                controller: _homeNameController,
                label: 'Your Home\'s Nickname',
                hint: 'e.g., Casa de Lumina, The Corner House',
              ),
              const SizedBox(height: 16),

              // Description (optional)
              _buildTextField(
                controller: _descriptionController,
                label: 'Hype It Up (optional)',
                hint: 'What makes your crew special?',
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Street Name
              _buildTextField(
                controller: _streetController,
                label: 'Street Name (optional)',
                hint: 'e.g., Maple Street',
              ),
              const SizedBox(height: 16),

              // City
              _buildTextField(
                controller: _cityController,
                label: 'City (optional)',
                hint: 'e.g., Kansas City',
              ),
              const SizedBox(height: 20),

              // Public/Private Toggle
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade700),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Public Group',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Allow nearby neighbors to find and request to join',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isPublic,
                      onChanged: (v) => setState(() => _isPublic = v),
                      activeColor: Colors.cyan,
                    ),
                  ],
                ),
              ),

              if (_isPublic) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.cyan.shade300, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your approximate location will be used to help neighbors find your group.',
                          style: TextStyle(
                            color: Colors.cyan.shade300,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _createGroup,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Icon(Icons.rocket_launch, size: 18),
          label: const Text('Let\'s Go!'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.cyan,
            foregroundColor: Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool autofocus = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(color: Colors.grey.shade500),
        hintStyle: TextStyle(color: Colors.grey.shade700),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.shade700),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.cyan),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Future<void> _createGroup() async {
    if (_groupNameController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);

    // Get location if public
    double? latitude;
    double? longitude;
    if (_isPublic) {
      // In a real implementation, you would get the user's location here
      // For now, we'll leave it null and let users set it later
      // final position = await Geolocator.getCurrentPosition();
      // latitude = position.latitude;
      // longitude = position.longitude;
    }

    final group = await ref.read(neighborhoodNotifierProvider.notifier).createGroup(
      _groupNameController.text.trim(),
      displayName: _homeNameController.text.trim().isNotEmpty
          ? _homeNameController.text.trim()
          : null,
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : null,
      streetName: _streetController.text.trim().isNotEmpty
          ? _streetController.text.trim()
          : null,
      city: _cityController.text.trim().isNotEmpty
          ? _cityController.text.trim()
          : null,
      isPublic: _isPublic,
      latitude: latitude,
      longitude: longitude,
    );

    if (mounted) {
      Navigator.pop(context, group);
    }
  }
}

/// Bottom sheet for finding nearby public groups.
class _FindNearbyGroupsSheet extends ConsumerStatefulWidget {
  const _FindNearbyGroupsSheet();

  @override
  ConsumerState<_FindNearbyGroupsSheet> createState() => _FindNearbyGroupsSheetState();
}

class _FindNearbyGroupsSheetState extends ConsumerState<_FindNearbyGroupsSheet> {
  bool _isSearching = false;
  List<NeighborhoodGroup>? _nearbyGroups;
  String? _error;
  double _searchRadius = 10.0; // km

  @override
  void initState() {
    super.initState();
    _searchNearby();
  }

  Future<void> _searchNearby() async {
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      // In a real implementation, get user's location
      // For now, use placeholder coordinates (Kansas City)
      const latitude = 39.0997;
      const longitude = -94.5786;

      final service = ref.read(neighborhoodServiceProvider);
      final groups = await service.findNearbyGroups(
        latitude: latitude,
        longitude: longitude,
        radiusKm: _searchRadius,
      );

      if (mounted) {
        setState(() {
          _nearbyGroups = groups;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to search nearby groups. Please try again.';
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.explore, color: Colors.cyan, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Discover Nearby Crews',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'See who\'s already syncing in your area',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Radius selector
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: DropdownButton<double>(
                      value: _searchRadius,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      dropdownColor: Colors.grey.shade800,
                      style: const TextStyle(color: Colors.cyan, fontSize: 14),
                      items: const [
                        DropdownMenuItem(value: 5.0, child: Text('5 km')),
                        DropdownMenuItem(value: 10.0, child: Text('10 km')),
                        DropdownMenuItem(value: 25.0, child: Text('25 km')),
                        DropdownMenuItem(value: 50.0, child: Text('50 km')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _searchRadius = v);
                          _searchNearby();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _buildContent(scrollController),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent(ScrollController scrollController) {
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.cyan),
            SizedBox(height: 16),
            Text(
              'Searching nearby...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade300, size: 48),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _searchNearby,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_nearbyGroups == null || _nearbyGroups!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.cyan.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag, color: Colors.cyan, size: 40),
              ),
              const SizedBox(height: 20),
              const Text(
                'You Could Be First!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No sync crews found nearby yet. Be a trailblazer and start one — your neighbors will thank you!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, height: 1.4),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  // Trigger create group dialog
                },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Start a Block Party'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.cyan,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _nearbyGroups!.length,
      itemBuilder: (context, index) {
        final group = _nearbyGroups![index];
        return _NearbyGroupTile(
          group: group,
          onJoin: () => _joinGroup(group),
        );
      },
    );
  }

  Future<void> _joinGroup(NeighborhoodGroup group) async {
    // Show join confirmation dialog
    final nameController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Join "${group.name}"?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (group.description != null) ...[
              Text(
                group.description!,
                style: TextStyle(color: Colors.grey.shade400),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              '${group.memberCount} homes • ${group.streetName ?? "Unknown street"}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Your Home Name',
                hintText: 'e.g., The Smith House',
                labelStyle: TextStyle(color: Colors.grey.shade500),
                hintStyle: TextStyle(color: Colors.grey.shade700),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade700),
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyan),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.black,
            ),
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final result = await ref.read(neighborhoodNotifierProvider.notifier).joinGroup(
        group.inviteCode,
        displayName: nameController.text.trim().isNotEmpty
            ? nameController.text.trim()
            : null,
      );

      if (result != null && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Joined "${group.name}"!'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    }
  }
}

class _NearbyGroupTile extends StatelessWidget {
  final NeighborhoodGroup group;
  final VoidCallback onJoin;

  const _NearbyGroupTile({
    required this.group,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.cyan.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.home_work, color: Colors.cyan),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.people_outline, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(
                      '${group.memberCount} homes',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                    ),
                    if (group.streetName != null) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.location_on, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          group.streetName!,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                if (group.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    group.description!,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: onJoin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}
