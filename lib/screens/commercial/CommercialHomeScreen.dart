import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/commercial/brand/brand_design_generator.dart';
import 'package:nexgen_command/features/commercial/events/events_screen.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/commercial/brand_color.dart';
import 'package:nexgen_command/models/commercial/commercial_brand_profile.dart';
import 'package:nexgen_command/models/commercial/commercial_event.dart';
import 'package:nexgen_command/models/commercial/commercial_location.dart';
import 'package:nexgen_command/models/commercial/commercial_organization.dart';
import 'package:nexgen_command/models/commercial/commercial_role.dart';
import 'package:nexgen_command/screens/commercial/commercial_mode_providers.dart';
import 'package:nexgen_command/screens/commercial/fleet/FleetDashboardScreen.dart';
import 'package:nexgen_command/screens/commercial/profile/BusinessProfileEditScreen.dart';
import 'package:nexgen_command/screens/commercial/schedule/CommercialScheduleScreen.dart';
import 'package:nexgen_command/services/commercial/brand_library_providers.dart';
import 'package:nexgen_command/services/commercial/commercial_events_providers.dart';

/// Index of the currently selected commercial bottom nav tab. Persists
/// across rebuilds so a tab switch survives navigation pops back to
/// the home screen.
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
// SINGLE-LOCATION SHELL — 5 tabs:
//   0 Dashboard · 1 Schedule · 2 Brand · 3 Events · 4 Profile
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

    final screens = <Widget>[
      const _DashboardTab(),
      CommercialScheduleScreen(
        locationId: location!.locationId,
        locationName: location!.locationName,
      ),
      const _BrandTab(),
      const EventsScreen(),
      BusinessProfileEditScreen(locationId: location!.locationId),
    ];

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: IndexedStack(index: tabIndex, children: screens),
      bottomNavigationBar: _CommercialBottomNav(
        currentIndex: tabIndex,
        onTap: (i) => ref.read(_commercialTabProvider.notifier).state = i,
        items: const [
          _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
          _NavItem(icon: Icons.timeline_rounded, label: 'Schedule'),
          _NavItem(icon: Icons.palette_outlined, label: 'Brand'),
          _NavItem(icon: Icons.event_outlined, label: 'Events'),
          _NavItem(icon: Icons.business_rounded, label: 'Profile'),
        ],
      ),
    );
  }
}

// =============================================================================
// MULTI-LOCATION SHELL — 6 tabs:
//   0 Dashboard · 1 Fleet · 2 Schedule · 3 Brand · 4 Events · 5 Profile
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

    final screens = <Widget>[
      const _DashboardTab(),
      FleetDashboardScreen(org: org!),
      location != null
          ? CommercialScheduleScreen(
              locationId: location.locationId,
              locationName: location.locationName,
              orgName: org!.orgName,
            )
          : const _LoadingTab(),
      const _BrandTab(),
      const EventsScreen(),
      location != null
          ? BusinessProfileEditScreen(locationId: location.locationId)
          : const _LoadingTab(),
    ];

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: IndexedStack(index: tabIndex, children: screens),
      bottomNavigationBar: _CommercialBottomNav(
        currentIndex: tabIndex,
        onTap: (i) => ref.read(_commercialTabProvider.notifier).state = i,
        items: const [
          _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
          _NavItem(icon: Icons.grid_view_rounded, label: 'Fleet'),
          _NavItem(icon: Icons.timeline_rounded, label: 'Schedule'),
          _NavItem(icon: Icons.palette_outlined, label: 'Brand'),
          _NavItem(icon: Icons.event_outlined, label: 'Events'),
          _NavItem(icon: Icons.business_rounded, label: 'Profile'),
        ],
      ),
    );
  }
}

// =============================================================================
// DASHBOARD TAB — first tab; commercial-mode equivalent of the residential
// wled_dashboard_page.dart. Shows active event, brand quick actions,
// Now Playing label, and controller status.
// =============================================================================

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeEvent = ref.watch(activeCommercialEventProvider);
    final brand = ref.watch(commercialBrandProfileProvider).valueOrNull;
    final wled = ref.watch(wledStateProvider);
    final nowPlaying = ref.watch(activePresetLabelProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: Text(
          brand?.companyName.isNotEmpty == true
              ? brand!.companyName
              : 'Dashboard',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _ControllerStatusPill(connected: wled.connected),
            const SizedBox(height: 16),
            if (activeEvent != null) ...[
              _ActiveEventBanner(event: activeEvent),
              const SizedBox(height: 20),
            ],
            _QuickActionsSection(brand: brand),
            const SizedBox(height: 20),
            _NowPlayingSection(label: nowPlaying, connected: wled.connected),
          ],
        ),
      ),
    );
  }
}

// ─── Controller status pill ───────────────────────────────────────────────

class _ControllerStatusPill extends StatelessWidget {
  const _ControllerStatusPill({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = connected ? NexGenPalette.green : NexGenPalette.amber;
    final label = connected ? 'Online' : 'Offline';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Controller · $label',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Active event banner ──────────────────────────────────────────────────

class _ActiveEventBanner extends ConsumerWidget {
  const _ActiveEventBanner({required this.event});
  final CommercialEvent event;

  Future<void> _applyDesign(BuildContext context, WidgetRef ref) async {
    final payload = event.designPayload;
    if (payload == null) {
      _toast(context, 'No design attached to this event.',
          color: NexGenPalette.amber);
      return;
    }
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      _toast(context, 'No controller connected — apply unavailable.',
          color: NexGenPalette.amber);
      return;
    }
    try {
      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state =
          event.designName ?? event.name;
      if (!context.mounted) return;
      _toast(context, 'Applied "${event.designName ?? event.name}".',
          color: NexGenPalette.cyan);
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, 'Apply failed: $e', color: Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NexGenPalette.cyan.withValues(alpha: 0.18),
            NexGenPalette.gunmetal90,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: NexGenPalette.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '● ACTIVE NOW',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5),
                ),
              ),
              const Spacer(),
              Text(_eventDateRange(event),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          Text(event.name,
              style: Theme.of(context).textTheme.titleLarge),
          if (event.designName != null && event.designName!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(event.designName!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: NexGenPalette.cyan)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _applyDesign(context, ref),
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('Apply Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.push(AppRoutes.commercialEvents),
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: const Text('View Event'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NexGenPalette.cyan,
                    side: const BorderSide(color: NexGenPalette.cyan),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Quick actions row ────────────────────────────────────────────────────

class _QuickActionsSection extends ConsumerWidget {
  const _QuickActionsSection({required this.brand});
  final CommercialBrandProfile? brand;

  Future<void> _applyPayload(
    BuildContext context,
    WidgetRef ref, {
    required Map<String, dynamic>? payload,
    required String label,
  }) async {
    if (payload == null) {
      _toast(context, 'Set up your brand profile first.',
          color: NexGenPalette.amber);
      return;
    }
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      _toast(context, 'No controller connected — apply unavailable.',
          color: NexGenPalette.amber);
      return;
    }
    try {
      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = label;
      if (!context.mounted) return;
      _toast(context, 'Applied "$label".', color: NexGenPalette.cyan);
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, 'Apply failed: $e', color: Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final companyName = brand?.companyName.isNotEmpty == true
        ? brand!.companyName
        : 'Brand';
    final hasBrand = brand != null && brand!.colors.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.lightbulb_outline,
                label: '$companyName Default',
                enabled: hasBrand,
                onTap: () {
                  if (brand == null) return;
                  final gen = ref.read(brandDesignGeneratorProvider);
                  _applyPayload(
                    context,
                    ref,
                    payload: gen.welcomePayloadFor(brand!),
                    label: '$companyName Welcome',
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.celebration_outlined,
                label: 'Event Mode',
                enabled: hasBrand,
                onTap: () {
                  if (brand == null) return;
                  final gen = ref.read(brandDesignGeneratorProvider);
                  _applyPayload(
                    context,
                    ref,
                    payload: gen.eventModePayloadFor(brand!),
                    label: '$companyName Event Mode',
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.add,
                label: 'New Event',
                enabled: true,
                onTap: () =>
                    context.push(AppRoutes.commercialEventsCreate),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.auto_awesome,
                label: 'Lumina AI',
                enabled: true,
                onTap: () => context.push(AppRoutes.luminaAI),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: enabled
                    ? NexGenPalette.cyan.withValues(alpha: 0.4)
                    : NexGenPalette.line),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 22,
                  color: enabled
                      ? NexGenPalette.cyan
                      : NexGenPalette.textMedium),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: enabled
                            ? NexGenPalette.textHigh
                            : NexGenPalette.textMedium,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Now Playing section ──────────────────────────────────────────────────

class _NowPlayingSection extends StatelessWidget {
  const _NowPlayingSection({required this.label, required this.connected});
  final String? label;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final dotColor =
        connected ? NexGenPalette.cyan : NexGenPalette.textMedium;
    final text = (label == null || label!.isEmpty)
        ? 'Nothing playing'
        : label!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            'Now playing',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BRAND TAB — read-only brand profile view + design quick-apply.
// =============================================================================

class _BrandTab extends ConsumerWidget {
  const _BrandTab();

  Future<void> _applyDesign(
    BuildContext context,
    WidgetRef ref, {
    required Map<String, dynamic>? payload,
    required String label,
  }) async {
    if (payload == null) return;
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      _toast(context, 'No controller connected — apply unavailable.',
          color: NexGenPalette.amber);
      return;
    }
    try {
      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = label;
      if (!context.mounted) return;
      _toast(context, 'Applied "$label".', color: NexGenPalette.cyan);
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, 'Apply failed: $e', color: Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandAsync = ref.watch(commercialBrandProfileProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        title: const Text('Brand'),
      ),
      body: brandAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Failed to load brand profile: $e',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ),
        data: (brand) {
          if (brand == null) {
            return const _BrandSetupCta();
          }
          return _BrandProfileView(
            brand: brand,
            onApply: (payload, label) =>
                _applyDesign(context, ref, payload: payload, label: label),
          );
        },
      ),
    );
  }
}

class _BrandSetupCta extends StatelessWidget {
  const _BrandSetupCta();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.palette_outlined,
                size: 64, color: NexGenPalette.cyan),
            const SizedBox(height: 16),
            Text('No Brand Profile Yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Set up your brand profile to unlock auto-generated '
              'lighting designs that match your colors.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  context.push(AppRoutes.commercialBrandSearch),
              icon: const Icon(Icons.search),
              label: const Text('Find Your Brand'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  context.push(AppRoutes.commercialBrandSetup),
              child: const Text('Or set up manually',
                  style: TextStyle(color: NexGenPalette.textMedium)),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandProfileView extends ConsumerWidget {
  const _BrandProfileView({required this.brand, required this.onApply});
  final CommercialBrandProfile brand;
  final void Function(Map<String, dynamic>? payload, String label) onApply;

  /// Owner check per Part-7 spec — for the current schema, the brand
  /// profile lives at /users/{uid}/brand_profile/brand so the viewing
  /// user is always the owner. Wiring the check defensively keeps the
  /// gate ready for future multi-user commercial accounts.
  bool _isOwner() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid != null && uid.isNotEmpty;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gen = ref.read(brandDesignGeneratorProvider);
    final payloads = gen.allPayloadsFor(brand);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _BrandHeaderCard(brand: brand, isOwner: _isOwner()),
        const SizedBox(height: 20),
        Text('Brand Colors',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        _BrandColorsRow(colors: brand.colors),
        const SizedBox(height: 24),
        Text('Brand Designs',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          payloads.isEmpty
              ? 'Add at least one brand color to generate designs.'
              : 'Tap a card to apply the design to your lights.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 110,
          child: payloads.isEmpty
              ? const SizedBox.shrink()
              : ListView(
                  scrollDirection: Axis.horizontal,
                  children: payloads.entries.map((entry) {
                    final fullName = '${brand.companyName} ${entry.key}';
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _BrandDesignCard(
                        variantLabel: entry.key,
                        colors: brand.colors,
                        onTap: () => onApply(entry.value, fullName),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _BrandHeaderCard extends StatelessWidget {
  const _BrandHeaderCard({required this.brand, required this.isOwner});
  final CommercialBrandProfile brand;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final flutterColors =
        brand.colors.map((c) => c.toColor()).toList(growable: false);
    final gradient = flutterColors.length >= 2
        ? LinearGradient(
            colors: [
              flutterColors.first.withValues(alpha: 0.25),
              flutterColors[1].withValues(alpha: 0.25),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              (flutterColors.isNotEmpty
                      ? flutterColors.first
                      : NexGenPalette.cyan)
                  .withValues(alpha: 0.18),
              NexGenPalette.gunmetal90,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(brand.companyName,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  brand.brandLibraryId != null
                      ? 'Brand Library · verified'
                      : 'Manual brand profile',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: NexGenPalette.cyan),
                ),
              ],
            ),
          ),
          if (isOwner)
            IconButton(
              icon:
                  const Icon(Icons.edit_outlined, color: NexGenPalette.cyan),
              tooltip: 'Edit brand profile',
              onPressed: () => context.push(
                AppRoutes.commercialBrandSetup,
                extra: {'isEditing': true},
              ),
            ),
        ],
      ),
    );
  }
}

class _BrandColorsRow extends StatelessWidget {
  const _BrandColorsRow({required this.colors});
  final List<BrandColor> colors;

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) {
      return Text('No colors defined.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: colors
          .map((c) => SizedBox(
                width: 80,
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: c.toColor(),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: NexGenPalette.line, width: 1.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      c.colorName.isNotEmpty ? c.colorName : c.roleTag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: NexGenPalette.textHigh),
                    ),
                    Text(
                      '#${c.hexCode.toUpperCase()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: NexGenPalette.textMedium,
                          ),
                    ),
                  ],
                ),
              ))
          .toList(growable: false),
    );
  }
}

class _BrandDesignCard extends StatelessWidget {
  const _BrandDesignCard({
    required this.variantLabel,
    required this.colors,
    required this.onTap,
  });

  final String variantLabel;
  final List<BrandColor> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 38,
                child: Row(
                  children: colors.take(4).map((c) {
                    return Expanded(
                      child: Container(
                        margin:
                            const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: c.toColor(),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                variantLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                'Tap to apply',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
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
// Loading placeholder (shown while a sub-screen waits on its location/org).
// =============================================================================

class _LoadingTab extends StatelessWidget {
  const _LoadingTab();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan)),
    );
  }
}

// =============================================================================
// Local helpers
// =============================================================================

void _toast(BuildContext context, String message, {required Color color}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: color,
      duration: const Duration(seconds: 3),
    ),
  );
}

/// Compact event date range — same logic as events_screen.dart's helper,
/// duplicated here to keep that file self-contained instead of exporting
/// a private utility.
String _eventDateRange(CommercialEvent e) {
  final s = e.startDate;
  final t = e.endDate;
  final sameDay = s.year == t.year && s.month == t.month && s.day == t.day;
  if (sameDay) return _formatDate(s);
  final sameYear = s.year == t.year;
  if (sameYear) {
    return '${_formatMonthDay(s)} – ${_formatMonthDay(t)}, ${t.year}';
  }
  return '${_formatDate(s)} – ${_formatDate(t)}';
}

String _formatDate(DateTime dt) =>
    '${_monthAbbr(dt.month)} ${dt.day}, ${dt.year}';

String _formatMonthDay(DateTime dt) =>
    '${_monthAbbr(dt.month)} ${dt.day}';

String _monthAbbr(int month) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return months[month - 1];
}
