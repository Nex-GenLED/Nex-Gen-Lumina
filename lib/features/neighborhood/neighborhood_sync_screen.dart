import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme.dart';
import '../../widgets/glass_app_bar.dart';
import 'neighborhood_models.dart';
import 'neighborhood_providers.dart';
import 'neighborhood_sync_engine.dart';
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
    // Activate the sync engine controller so this device listens for
    // incoming sync commands when belonging to an active group.
    ref.watch(syncEngineControllerProvider);

    final groupsAsync = ref.watch(userNeighborhoodsProvider);
    final onboardingAsync = ref.watch(neighborhoodSyncOnboardingCompleteProvider);

    // Show loading shimmer while either check is in progress.
    if (groupsAsync.isLoading || onboardingAsync.isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(context),
        body: const _NeighborhoodLoadingShimmer(),
      );
    }

    final groups = groupsAsync.valueOrNull ?? [];
    final onboardingComplete = onboardingAsync.valueOrNull ?? false;

    // Auto-migrate existing users: if they already have groups, silently mark
    // onboarding complete so they never see onboarding screens again.
    if (groups.isNotEmpty && !onboardingComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) markNeighborhoodSyncOnboardingComplete();
      });
    }

    final isReturningUser = onboardingComplete || groups.isNotEmpty;

    if (isReturningUser) {
      // Returning user — show group list view directly, no onboarding.
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(context),
        body: _NeighborhoodGroupListView(
          groups: groups,
          onGroupTap: (group) {
            ref.read(activeNeighborhoodIdProvider.notifier).state = group.id;
            _showGroupControlsSheet(groups);
          },
          onCreateGroup: _showCreateGroupDialog,
          onJoinGroup: _showJoinGroupDialog,
        ),
      );
    }

    // New user — show 4-page onboarding. Mark complete when they tap any CTA.
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          NeighborhoodOnboarding(
            onCreateGroup: () {
              markNeighborhoodSyncOnboardingComplete();
              _showCreateGroupDialog();
            },
            onJoinGroup: () {
              markNeighborhoodSyncOnboardingComplete();
              _showJoinGroupDialog();
            },
            onFindNearby: _showFindNearbyDialog,
          ),
          if (groupsAsync.hasError)
            SafeArea(child: _buildErrorBanner()),
        ],
      ),
    );
  }

  /// Shared GlassAppBar with a visible back button. The screen is now pushed
  /// from the home dashboard inside the home shell branch, so context.pop()
  /// returns to the dashboard with the bottom nav bar still visible.
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return GlassAppBar(
      title: const Text('Neighborhood Sync'),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            // Fallback for deep-links / edge cases where there's nothing to
            // pop within the home branch — return to the dashboard root.
            context.go('/dashboard');
          }
        },
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
            color: Colors.orange.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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

  Future<void> _showCreateGroupDialog() async {
    final group = await showDialog<NeighborhoodGroup>(
      context: context,
      builder: (context) => const _CreateGroupDialog(),
    );

    if (group != null && mounted) {
      ref.read(activeNeighborhoodIdProvider.notifier).state = group.id;
      // Refresh the groups list then show controls
      ref.invalidate(userNeighborhoodsProvider);
      await ref.read(userNeighborhoodsProvider.future);
      if (!mounted) return;
      final groups = ref.read(userNeighborhoodsProvider).valueOrNull ?? [];
      _showGroupControlsSheet(groups);
    }
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
                color: Colors.cyan.withValues(alpha: 0.2),
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

// ─────────────────────────────────────────────────────────────────────────────
// Loading Shimmer — shown while checking onboarding flag + group membership
// ─────────────────────────────────────────────────────────────────────────────

class _NeighborhoodLoadingShimmer extends StatelessWidget {
  const _NeighborhoodLoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title shimmer
            Container(height: 28, width: 220, decoration: _shimmerDecor()),
            const SizedBox(height: 8),
            Container(height: 16, width: 80, decoration: _shimmerDecor()),
            const SizedBox(height: 28),
            // Card shimmers
            for (int i = 0; i < 3; i++) ...[
              Container(
                height: 88,
                decoration: _shimmerDecor(radius: 16),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  BoxDecoration _shimmerDecor({double radius = 8}) => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(radius),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Returning-User Group List View
// ─────────────────────────────────────────────────────────────────────────────

class _NeighborhoodGroupListView extends ConsumerStatefulWidget {
  final List<NeighborhoodGroup> groups;
  final void Function(NeighborhoodGroup) onGroupTap;
  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;

  const _NeighborhoodGroupListView({
    required this.groups,
    required this.onGroupTap,
    required this.onCreateGroup,
    required this.onJoinGroup,
  });

  @override
  ConsumerState<_NeighborhoodGroupListView> createState() =>
      _NeighborhoodGroupListViewState();
}

class _NeighborhoodGroupListViewState
    extends ConsumerState<_NeighborhoodGroupListView>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previousAsync = ref.watch(previousGroupsProvider);
    final previousGroups = previousAsync.valueOrNull ?? [];

    // Sort: active sessions first, then by member count
    final sorted = [...widget.groups]..sort((a, b) {
        if (a.isActive && !b.isActive) return -1;
        if (!a.isActive && b.isActive) return 1;
        return b.memberUids.length.compareTo(a.memberUids.length);
      });

    final anyActive = widget.groups.any((g) => g.isActive);
    final subtitle = widget.groups.isEmpty
        ? 'Your Sync Crews'
        : widget.groups.length == 1
            ? (anyActive ? '1 Active Group' : '1 Group')
            : (anyActive
                ? '${widget.groups.length} Groups Syncing'
                : '${widget.groups.length} Groups');

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black,
            NexGenPalette.midnightBlue.withValues(alpha: 0.8),
            Colors.black,
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ── Compact animated hero header ──────────────────────────────
            _buildHeroHeader(subtitle),

            // ── Group list / empty state ──────────────────────────────────
            Expanded(
              child: widget.groups.isEmpty
                  ? _buildEmptyState(previousGroups)
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                          16, 8, 16, navBarTotalHeight(context) + 88),
                      children: [
                        for (int i = 0; i < sorted.length; i++)
                          _buildGroupCard(sorted[i], i + 1),
                        if (previousGroups.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          _buildPreviousGroupsSection(previousGroups),
                        ],
                      ],
                    ),
            ),

            // ── Bottom action buttons ─────────────────────────────────────
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  // ── Hero header ────────────────────────────────────────────────────────────

  Widget _buildHeroHeader(String subtitle) {
    return Stack(
      children: [
        Column(
          children: [
            // Compact 120px animated hero (reuses NeighborhoodHeroPainter)
            SizedBox(
              height: 120,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: Listenable.merge([_pulseController, _waveController]),
                builder: (context, child) => CustomPaint(
                  size: const Size(double.infinity, 120),
                  painter: NeighborhoodHeroPainter(
                    pulseValue: _pulseController.value,
                    waveValue: _waveController.value,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Gradient title
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [NexGenPalette.cyan, Colors.white, NexGenPalette.violet],
              ).createShader(bounds),
              child: const Text(
                'Neighborhood Sync',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: NexGenPalette.cyan.withValues(alpha: 0.9),
                fontWeight: FontWeight.w500,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
        // "+" button top-right
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => _showAddMenu(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.35)),
              ),
              child: const Icon(Icons.add, color: NexGenPalette.cyan, size: 20),
            ),
          ),
        ),
      ],
    );
  }

  // ── Group card ─────────────────────────────────────────────────────────────

  Widget _buildGroupCard(NeighborhoodGroup group, int rank) {
    final colors = _syncTypeColors(group.activeSyncType);
    final emoji = _syncTypeEmoji(group.activeSyncType);
    final accent = colors[0];

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final borderOpacity =
            group.isActive ? 0.4 + _pulseController.value * 0.4 : 0.3;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => widget.onGroupTap(group),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.12),
                    colors[1].withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: borderOpacity)),
                boxShadow: group.isActive
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 
                              0.18 + _pulseController.value * 0.14),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sync-mode icon container (onboarding card style)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: colors),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child:
                          Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                group.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // LIVE chip — cyan styled (onboarding feature chip)
                            if (group.isActive)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: NexGenPalette.cyan.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: NexGenPalette.cyan
                                          .withValues(alpha: 0.5)),
                                ),
                                child: const Text(
                                  'LIVE',
                                  style: TextStyle(
                                    color: NexGenPalette.cyan,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),

                        // Sync type pill + member count (sync mode card style)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                group.activeSyncType.displayName,
                                style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.home,
                                size: 12, color: Colors.grey.shade600),
                            const SizedBox(width: 3),
                            Text(
                              '${group.memberUids.length} '
                              '${group.memberUids.length == 1 ? "home" : "homes"}',
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Animated status row
                        _buildStatusRow(group),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Rank badge + chevron (step-circle from onboarding)
                  Column(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [NexGenPalette.cyan, NexGenPalette.blue],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '$rank',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Icon(Icons.chevron_right,
                          color: Colors.grey.shade600, size: 18),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusRow(NeighborhoodGroup group) {
    if (group.isActive) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) => Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NexGenPalette.cyan
                    .withValues(alpha: 0.5 + _pulseController.value * 0.5),
                boxShadow: [
                  BoxShadow(
                    color: NexGenPalette.cyan.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                group.activePatternName != null
                    ? 'Syncing · ${group.activePatternName}'
                    : 'Syncing Now',
                style: const TextStyle(
                  color: NexGenPalette.cyan,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: Colors.grey.shade700),
        ),
        const SizedBox(width: 6),
        Text('Idle',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
      ],
    );
  }

  // ── Empty state ─────────────────────────────────────────────────────────────

  Widget _buildEmptyState(List<PreviousGroup> previousGroups) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, navBarTotalHeight(context) + 88),
      children: [
        // Animated glow circle (matches _buildGetStartedPage in onboarding)
        Center(
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    NexGenPalette.cyan
                        .withValues(alpha: 0.3 + _pulseController.value * 0.2),
                    NexGenPalette.cyan.withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: NexGenPalette.cyan
                        .withValues(alpha: 0.3 + _pulseController.value * 0.2),
                    blurRadius: 30 + _pulseController.value * 10,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child:
                  const Icon(Icons.celebration, size: 56, color: Colors.white),
            ),
          ),
        ),

        const SizedBox(height: 28),

        const Center(
          child: Text(
            'Ready to Light Up\nYour Street?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
          ),
        ),

        const SizedBox(height: 12),

        Center(
          child: Text(
            "Create a new crew or join one that's already syncing nearby.",
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14, color: Colors.grey.shade400, height: 1.5),
          ),
        ),

        const SizedBox(height: 32),

        // Setup steps (matching _buildSetupStep from onboarding)
        _buildSetupStep(
            1, 'Create or Join', 'Start a new sync group or enter an invite code'),
        const SizedBox(height: 14),
        _buildSetupStep(
            2, 'Configure Your Home', 'Set your LED count and position on the street'),
        const SizedBox(height: 14),
        _buildSetupStep(
            3, 'Sync & Celebrate', 'Pick a pattern and watch the magic happen'),

        const SizedBox(height: 28),

        // Pro tip callout (onboarding style)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lightbulb_outline,
                  color: NexGenPalette.cyan, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Pro tip: Share your invite code via text or social media to grow your group quickly!',
                  style:
                      TextStyle(color: Colors.grey.shade300, fontSize: 13),
                ),
              ),
            ],
          ),
        ),

        if (previousGroups.isNotEmpty) ...[
          const SizedBox(height: 32),
          _buildPreviousGroupsSection(previousGroups),
        ],
      ],
    );
  }

  Widget _buildSetupStep(int number, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: const BoxDecoration(
            gradient:
                LinearGradient(colors: [NexGenPalette.cyan, NexGenPalette.blue]),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number.toString(),
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
              Text(subtitle,
                  style:
                      TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Previous groups section ────────────────────────────────────────────────

  Widget _buildPreviousGroupsSection(List<PreviousGroup> previousGroups) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history,
                size: 16, color: NexGenPalette.cyan.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Text(
              'Previous Groups',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...previousGroups.map(
          (prev) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () async {
                final group = await ref
                    .read(neighborhoodNotifierProvider.notifier)
                    .joinGroup(prev.inviteCode);
                if (!context.mounted) return;
                if (group != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Welcome back to ${group.name}!'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ));
                } else {
                  await removePreviousGroup(prev.id);
                  ref.invalidate(previousGroupsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('This group no longer exists.'),
                      backgroundColor: Colors.orange.shade700,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                }
              },
              borderRadius: BorderRadius.circular(12),
              // Use case card style from onboarding
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: NexGenPalette.cyan.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: NexGenPalette.cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text('🏘️', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        prev.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: NexGenPalette.cyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: NexGenPalette.cyan.withValues(alpha: 0.3)),
                      ),
                      child: const Text(
                        'Rejoin',
                        style: TextStyle(
                          color: NexGenPalette.cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Action buttons ─────────────────────────────────────────────────────────

  Widget _buildActionButtons() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, navBarTotalHeight(context) + 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        border: Border(
            top: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.1))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Primary — matches "Start a Block Party" in onboarding
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onCreateGroup,
              icon:
                  const Icon(Icons.add_circle_outline, size: 20),
              label: const Text(
                'Start a Block Party',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 8,
                shadowColor:
                    NexGenPalette.cyan.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Secondary — matches "Join the Party" in onboarding
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onJoinGroup,
              icon: const Icon(Icons.login, size: 20),
              label: const Text('Join the Party'),
              style: OutlinedButton.styleFrom(
                foregroundColor: NexGenPalette.cyan,
                side: const BorderSide(color: NexGenPalette.cyan),
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Add menu ───────────────────────────────────────────────────────────────

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade700,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      const Icon(Icons.add_home, color: NexGenPalette.cyan),
                ),
                title: const Text('New Crew',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
                subtitle: Text('Start a new neighborhood sync group',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onCreateGroup();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.login, color: Colors.green.shade400),
                ),
                title: const Text('Join Group',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Enter an invite code to join an existing crew',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onJoinGroup();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sync type theming helpers ──────────────────────────────────────────────

  List<Color> _syncTypeColors(SyncType type) {
    switch (type) {
      case SyncType.sequentialFlow:
        return [NexGenPalette.cyan, NexGenPalette.blue];
      case SyncType.simultaneous:
        return [Colors.red.shade400, Colors.pink.shade300];
      case SyncType.patternMatch:
        return [Colors.green.shade400, Colors.teal.shade300];
      case SyncType.complement:
        return [Colors.purple.shade400, NexGenPalette.violet];
    }
  }

  String _syncTypeEmoji(SyncType type) {
    switch (type) {
      case SyncType.sequentialFlow:
        return '🌊';
      case SyncType.simultaneous:
        return '❤️';
      case SyncType.patternMatch:
        return '🔄';
      case SyncType.complement:
        return '🎨';
    }
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
                  padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).padding.bottom + 88),
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
                  color: isActive ? Colors.cyan.withValues(alpha: 0.2) : Colors.transparent,
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
            Colors.cyan.withValues(alpha: 0.15),
            Colors.purple.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.2),
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
                          color: Colors.green.withValues(alpha: 0.2),
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
                Colors.cyan.withValues(alpha: 0.1),
                Colors.purple.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.cyan.withValues(alpha: 0.2)),
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

        const SizedBox(height: 24),

        // Leave group — destructive but not irreversible, use red outline
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showLeaveGroupDialog(group),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Leave Group'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isHost = uid != null && group.creatorUid == uid;

    if (isHost) {
      _showHostLeaveGroupDialog(group);
    } else {
      _showMemberLeaveGroupDialog(group);
    }
  }

  void _showMemberLeaveGroupDialog(NeighborhoodGroup group) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Leave ${group.name}?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          'You\'ll stop receiving sync commands from this group. '
          'You can rejoin anytime with the group code.',
          style: TextStyle(color: Colors.grey.shade400),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ),
          TextButton(
            onPressed: () {
              // Capture messenger before any pops — context is deactivated after sheet closes.
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(dialogContext); // Close dialog
              Navigator.pop(context);       // Close sheet
              ref.read(neighborhoodNotifierProvider.notifier).leaveCurrentGroup();
              messenger.showSnackBar(
                SnackBar(
                  content: Text('You\'ve left ${group.name}'),
                  backgroundColor: Colors.grey.shade800,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text(
              'Leave Group',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showHostLeaveGroupDialog(NeighborhoodGroup group) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Leave ${group.name}?',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You\'ll stop receiving sync commands from this group. '
              'You can rejoin anytime with the group code.',
              style: TextStyle(color: Colors.grey.shade400),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You\'re the host of this group. Leaving will end the group '
                      'for all members unless you transfer ownership first.',
                      style: TextStyle(color: Colors.orange.shade300, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showTransferOwnershipDialog(group);
            },
            child: const Text(
              'Transfer Ownership',
              style: TextStyle(color: Colors.cyan),
            ),
          ),
          TextButton(
            onPressed: () {
              // Capture messenger before any pops — context is deactivated after sheet closes.
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(dialogContext); // Close dialog
              Navigator.pop(context);       // Close sheet
              final member = ref.read(currentUserMemberProvider);
              ref.read(neighborhoodNotifierProvider.notifier).dissolveGroupAsHost(
                hostDisplayName: member?.displayName ?? 'The host',
              );
              messenger.showSnackBar(
                SnackBar(
                  content: Text('You\'ve left ${group.name}'),
                  backgroundColor: Colors.grey.shade800,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text(
              'Leave Group',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _showTransferOwnershipDialog(NeighborhoodGroup group) {
    final members = ref.read(neighborhoodMembersProvider).valueOrNull ?? [];
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final otherMembers = members.where((m) => m.oderId != uid).toList();

    if (otherMembers.isEmpty) {
      // No other members to transfer to — just show leave dialog
      _showMemberLeaveGroupDialog(group);
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Transfer Ownership',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select the new host for ${group.name}:',
                style: TextStyle(color: Colors.grey.shade400),
              ),
              const SizedBox(height: 16),
              ...otherMembers.map((member) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Colors.cyan.withValues(alpha: 0.2),
                  child: const Icon(Icons.home, color: Colors.cyan, size: 20),
                ),
                title: Text(
                  member.displayName,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  // Capture messenger before any pops — context is deactivated after sheet closes.
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(dialogContext); // Close transfer dialog
                  Navigator.pop(context);       // Close sheet
                  ref.read(neighborhoodNotifierProvider.notifier)
                      .transferOwnershipAndLeave(member.oderId);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('You\'ve left ${group.name}'),
                      backgroundColor: Colors.grey.shade800,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade500),
            ),
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
              color: Colors.cyan.withValues(alpha: 0.2),
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
                    color: Colors.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
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
    debugPrint('🏘️ [NeighborhoodSync] Create group tapped');
    final name = _groupNameController.text.trim();
    debugPrint('🏘️ Group name: "$name"');

    if (name.isEmpty) {
      debugPrint('🏘️ ABORT: name is empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name for your crew.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    debugPrint('🏘️ Current user UID: ${user?.uid}');
    debugPrint('🏘️ Current user null: ${user == null}');
    debugPrint('🏘️ Current user anonymous: ${user?.isAnonymous}');
    debugPrint('🏘️ Current user emailVerified: ${user?.emailVerified}');

    if (user == null) {
      debugPrint('🏘️ ERROR: user is null — aborting');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to create a group.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    double? latitude;
    double? longitude;

    try {
      debugPrint('🏘️ Calling NeighborhoodNotifier.createGroup...');
      debugPrint('🏘️   displayName: ${_homeNameController.text.trim()}');
      debugPrint('🏘️   isPublic: $_isPublic');
      debugPrint('🏘️   street/city: ${_streetController.text.trim()} / ${_cityController.text.trim()}');

      final group = await ref.read(neighborhoodNotifierProvider.notifier).createGroup(
        name,
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

      debugPrint('🏘️ Notifier returned: ${group == null ? "null (failed)" : "group ${group.id}"}');

      if (!mounted) {
        debugPrint('🏘️ Widget unmounted — bailing');
        return;
      }

      if (group == null) {
        // Notifier swallows exceptions and returns null on failure.
        // Surface the underlying error so the user knows what happened.
        final notifierState = ref.read(neighborhoodNotifierProvider);
        final errorMsg = notifierState.hasError
            ? 'Could not create your crew: ${notifierState.error}'
            : 'Could not create your crew. Please try again.';
        debugPrint('🏘️ ERROR: Block party creation failed: $errorMsg');
        if (notifierState.hasError) {
          debugPrint('🏘️ Notifier error stack: ${notifierState.stackTrace}');
        }
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
          ),
        );
        return;
      }

      debugPrint('🏘️ Write succeeded, popping dialog and navigating');
      Navigator.pop(context, group);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${group.name} is ready! Invite your neighbors!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e, stack) {
      debugPrint('🏘️ ERROR during group creation: $e');
      debugPrint('🏘️ Stack: $stack');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create your crew: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
        ),
      );
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
                      color: Colors.cyan.withValues(alpha: 0.2),
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
                  color: Colors.cyan.withValues(alpha: 0.1),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
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
        color: Colors.grey.shade900.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.2),
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
