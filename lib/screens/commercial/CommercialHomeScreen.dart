import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/models/commercial/commercial_location.dart';
import 'package:nexgen_command/models/commercial/commercial_organization.dart';
import 'package:nexgen_command/models/commercial/commercial_role.dart';
import 'package:nexgen_command/screens/commercial/commercial_mode_providers.dart';
import 'package:nexgen_command/screens/commercial/fleet/FleetDashboardScreen.dart';
import 'package:nexgen_command/screens/commercial/schedule/CommercialScheduleScreen.dart';
import 'package:nexgen_command/screens/commercial/profile/BusinessProfileEditScreen.dart';

/// Index of the currently selected commercial bottom nav tab.
final _commercialTabProvider = StateProvider<int>((ref) => 0);

// =============================================================================
// CommercialHomeScreen — entry point for commercial mode
// =============================================================================

class CommercialHomeScreen extends ConsumerWidget {
  const CommercialHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMultiLoc = ref.watch(isMultiLocationProvider);
    final roleAsync = ref.watch(commercialUserRoleProvider);
    final orgAsync = ref.watch(commercialOrgProvider);
    final primaryLoc = ref.watch(primaryCommercialLocationProvider);

    return isMultiLoc.when(
      loading: () => _loadingScaffold(),
      error: (_, __) => _errorScaffold('Failed to load commercial profile'),
      data: (multi) {
        final role = roleAsync.valueOrNull;
        final isFleetUser = multi &&
            (role == CommercialRole.corporateAdmin ||
                role == CommercialRole.regionalManager);

        if (isFleetUser) {
          return _MultiLocationShell(org: orgAsync.valueOrNull);
        }
        return _SingleLocationShell(
          location: primaryLoc.valueOrNull,
        );
      },
    );
  }

  Widget _loadingScaffold() => const Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      );

  Widget _errorScaffold(String msg) => Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: Center(
          child: Text(msg,
              style: const TextStyle(color: NexGenPalette.textMedium)),
        ),
      );
}

// =============================================================================
// SINGLE-LOCATION SHELL — 4-tab bottom nav
// =============================================================================

class _SingleLocationShell extends ConsumerWidget {
  final CommercialLocation? location;

  const _SingleLocationShell({this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = ref.watch(_commercialTabProvider);

    if (location == null) {
      return const Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      );
    }

    final screens = [
      CommercialScheduleScreen(
        locationId: location!.locationId,
        locationName: location!.locationName,
      ),
      _PlaceholderScreen(title: 'Your Teams', icon: Icons.sports_rounded),
      _PlaceholderScreen(title: 'Channels', icon: Icons.lightbulb_outline_rounded),
      BusinessProfileEditScreen(locationId: location!.locationId),
    ];

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: IndexedStack(index: tabIndex, children: screens),
      bottomNavigationBar: _CommercialBottomNav(
        currentIndex: tabIndex,
        onTap: (i) => ref.read(_commercialTabProvider.notifier).state = i,
        items: const [
          _NavItem(icon: Icons.timeline_rounded, label: 'Schedule'),
          _NavItem(icon: Icons.sports_rounded, label: 'Teams'),
          _NavItem(icon: Icons.lightbulb_outline_rounded, label: 'Channels'),
          _NavItem(icon: Icons.business_rounded, label: 'Profile'),
        ],
      ),
    );
  }
}

// =============================================================================
// MULTI-LOCATION SHELL — 5-tab bottom nav with Fleet first
// =============================================================================

class _MultiLocationShell extends ConsumerWidget {
  final CommercialOrganization? org;

  const _MultiLocationShell({this.org});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = ref.watch(_commercialTabProvider);
    final primaryLoc = ref.watch(primaryCommercialLocationProvider);
    final location = primaryLoc.valueOrNull;

    if (org == null) {
      return const Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      );
    }

    final screens = [
      FleetDashboardScreen(org: org!),
      location != null
          ? CommercialScheduleScreen(
              locationId: location.locationId,
              locationName: location.locationName,
              orgName: org!.orgName,
            )
          : _PlaceholderScreen(
              title: 'Schedule', icon: Icons.timeline_rounded),
      _PlaceholderScreen(title: 'Your Teams', icon: Icons.sports_rounded),
      _PlaceholderScreen(
          title: 'Channels', icon: Icons.lightbulb_outline_rounded),
      location != null
          ? BusinessProfileEditScreen(locationId: location.locationId)
          : _PlaceholderScreen(
              title: 'Profile', icon: Icons.business_rounded),
    ];

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: IndexedStack(index: tabIndex, children: screens),
      bottomNavigationBar: _CommercialBottomNav(
        currentIndex: tabIndex,
        onTap: (i) => ref.read(_commercialTabProvider.notifier).state = i,
        items: const [
          _NavItem(icon: Icons.grid_view_rounded, label: 'Fleet'),
          _NavItem(icon: Icons.timeline_rounded, label: 'Schedule'),
          _NavItem(icon: Icons.sports_rounded, label: 'Teams'),
          _NavItem(icon: Icons.lightbulb_outline_rounded, label: 'Channels'),
          _NavItem(icon: Icons.business_rounded, label: 'Profile'),
        ],
      ),
    );
  }
}

// =============================================================================
// GLASS BOTTOM NAV — matches Lumina dark theme
// =============================================================================

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _CommercialBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;

  const _CommercialBottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal.withValues(alpha: 0.85),
            border: const Border(
              top: BorderSide(color: NexGenPalette.line, width: 1),
            ),
          ),
          padding: EdgeInsets.only(bottom: bottomPadding, top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final item = items[i];
              final selected = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          size: 22,
                          color: selected
                              ? NexGenPalette.cyan
                              : NexGenPalette.textMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: selected
                                ? NexGenPalette.cyan
                                : NexGenPalette.textMedium,
                            fontSize: 10,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PLACEHOLDER SCREEN — for tabs not yet wired
// =============================================================================

class _PlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;

  const _PlaceholderScreen({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 48,
                color: NexGenPalette.textMedium.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    color: NexGenPalette.textHigh,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Coming soon',
                style:
                    TextStyle(color: NexGenPalette.textMedium, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
