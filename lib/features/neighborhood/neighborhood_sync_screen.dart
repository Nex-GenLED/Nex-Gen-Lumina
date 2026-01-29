import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme.dart';
import 'neighborhood_models.dart';
import 'neighborhood_providers.dart';
import 'widgets/member_position_list.dart';
import 'widgets/neighborhood_onboarding.dart';
import 'widgets/schedule_list.dart';
import 'widgets/sync_control_panel.dart';

/// Main screen for Neighborhood Sync feature.
///
/// Architecture:
/// - The educational onboarding content is ALWAYS shown as the base layer
/// - When user has groups, a "My Crews" card appears at the top
/// - Tapping the crew card opens a bottom sheet with full controls
/// - This keeps users informed about the feature while providing easy access to their groups
class NeighborhoodSyncScreen extends ConsumerStatefulWidget {
  const NeighborhoodSyncScreen({super.key});

  @override
  ConsumerState<NeighborhoodSyncScreen> createState() => _NeighborhoodSyncScreenState();
}

class _NeighborhoodSyncScreenState extends ConsumerState<NeighborhoodSyncScreen> {
  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(userNeighborhoodsProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Base layer: Always show the onboarding/education content
          NeighborhoodOnboarding(
            onCreateGroup: _showCreateGroupDialog,
            onJoinGroup: _showJoinGroupDialog,
            onFindNearby: _showFindNearbyDialog,
          ),

          // Top layer: Show group card if user has groups (or error banner)
          SafeArea(
            child: groupsAsync.when(
              data: (groups) {
                if (groups.isEmpty) {
                  return const SizedBox.shrink(); // No card needed
                }

                // Auto-select first group if none selected
                final activeId = ref.read(activeNeighborhoodIdProvider);
                if (activeId == null && groups.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    ref.read(activeNeighborhoodIdProvider.notifier).state = groups.first.id;
                  });
                }

                return _buildActiveGroupCard(groups);
              },
              loading: () => const SizedBox.shrink(), // Don't block while loading
              error: (e, _) => _buildErrorBanner(),
            ),
          ),
        ],
      ),
    );
  }

  /// Floating card at the top showing user's active sync crew
  Widget _buildActiveGroupCard(List<NeighborhoodGroup> groups) {
    final activeGroup = ref.watch(activeNeighborhoodProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: GestureDetector(
        onTap: () => _showGroupControlsSheet(groups),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                NexGenPalette.gunmetal.withOpacity(0.95),
                NexGenPalette.midnightBlue.withOpacity(0.95),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NexGenPalette.cyan.withOpacity(0.4)),
            boxShadow: [
              BoxShadow(
                color: NexGenPalette.cyan.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Animated sync indicator
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [NexGenPalette.cyan, NexGenPalette.blue],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.sync,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'My Sync Crew',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (activeGroup.valueOrNull?.isActive == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.fiber_manual_record, color: Colors.green, size: 8),
                                    SizedBox(width: 4),
                                    Text(
                                      'LIVE',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        activeGroup.when(
                          data: (group) => group != null
                              ? Text(
                                  group.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : const Text(
                                  'Select a crew',
                                  style: TextStyle(color: Colors.grey),
                                ),
                          loading: () => const Text(
                            'Loading...',
                            style: TextStyle(color: Colors.grey),
                          ),
                          error: (_, __) => const Text(
                            'Error loading',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Members count
                  activeGroup.when(
                    data: (group) => group != null
                        ? Column(
                            children: [
                              Text(
                                '${group.memberCount}',
                                style: const TextStyle(
                                  color: NexGenPalette.cyan,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'homes',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
              // Quick hint
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.touch_app, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(
                      'Tap to open sync controls',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Subtle error banner that doesn't block the content
  Widget _buildErrorBanner() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GestureDetector(
        onTap: () => ref.invalidate(userNeighborhoodsProvider),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_off, color: Colors.orange.shade300, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Couldn\'t load your crews. Tap to retry.',
                  style: TextStyle(
                    color: Colors.orange.shade200,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(Icons.refresh, color: Colors.orange.shade300, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-featured bottom sheet with all group controls
  void _showGroupControlsSheet(List<NeighborhoodGroup> groups) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _GroupControlsSheet(
        groups: groups,
        onCreateGroup: _showCreateGroupDialog,
        onJoinGroup: _showJoinGroupDialog,
      ),
    );
  }

  void _showCreateGroupDialog() {
    showDialog(
      context: context,
      builder: (context) => const _CreateGroupDialog(),
    );
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
                    backgroundColor: Colors.green,
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
}

/// Full-screen bottom sheet with all group controls
class _GroupControlsSheet extends ConsumerStatefulWidget {
  final List<NeighborhoodGroup> groups;
  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;

  const _GroupControlsSheet({
    required this.groups,
    required this.onCreateGroup,
    required this.onJoinGroup,
  });

  @override
  ConsumerState<_GroupControlsSheet> createState() => _GroupControlsSheetState();
}

class _GroupControlsSheetState extends ConsumerState<_GroupControlsSheet> {
  @override
  Widget build(BuildContext context) {
    final activeGroup = ref.watch(activeNeighborhoodProvider);
    final membersAsync = ref.watch(neighborhoodMembersProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
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
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [NexGenPalette.cyan, NexGenPalette.blue],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.sync, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Sync Control Center',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Group selector (if multiple groups)
                    if (widget.groups.length > 1) ...[
                      _buildGroupSelector(widget.groups, activeGroup.valueOrNull),
                      const SizedBox(height: 20),
                    ],

                    // Active group content
                    activeGroup.when(
                      data: (group) {
                        if (group == null) {
                          return const Center(
                            child: Text(
                              'No group selected',
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Group header with invite code
                            _buildGroupHeader(group),
                            const SizedBox(height: 24),

                            // Member list
                            const Text(
                              'Homes in Sync Order',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Drag to reorder how the animation flows',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
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
                                group: group,
                              ),
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            ),

                            const SizedBox(height: 24),

                            // Schedule list
                            NeighborhoodScheduleList(group: group),

                            const SizedBox(height: 24),

                            // Actions
                            _buildGroupActions(group),

                            const SizedBox(height: 32),
                          ],
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: Colors.cyan),
                      ),
                      error: (e, _) => Center(
                        child: Text(
                          'Error loading group',
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGroupSelector(List<NeighborhoodGroup> groups, NeighborhoodGroup? activeGroup) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: groups.map((group) {
          final isActive = activeGroup?.id == group.id;
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
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
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
            Colors.cyan.withOpacity(0.15),
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
                    if (group.isActive) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'SYNCING',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
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
              const Row(
                children: [
                  Icon(Icons.share, color: Colors.cyan, size: 20),
                  SizedBox(width: 8),
                  Expanded(
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

        // Add another group / Join another
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onCreateGroup();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New Crew'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade400,
                  side: BorderSide(color: Colors.grey.shade700),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onJoinGroup();
                },
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Join Another'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade400,
                  side: BorderSide(color: Colors.grey.shade700),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
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

  void _showMemberConfigDialog(NeighborhoodMember member) {
    showDialog(
      context: context,
      builder: (context) => MemberConfigDialog(member: member),
    );
  }

  void _showLeaveGroupDialog(NeighborhoodGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Leave Crew?',
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
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close sheet
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

  void _copyInviteCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invite code "$code" copied!'),
        backgroundColor: Colors.cyan.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
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

    double? latitude;
    double? longitude;

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
      if (group != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${group.name} is ready! Invite your neighbors!'),
            backgroundColor: Colors.green,
          ),
        );
      }
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
  double _searchRadius = 10.0;

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
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

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
                'No sync crews found nearby yet. Be a trailblazer and start one!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade400, height: 1.4),
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
            backgroundColor: Colors.green,
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
                  ],
                ),
              ],
            ),
          ),
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
