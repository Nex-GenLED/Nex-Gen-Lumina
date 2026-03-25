import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/app_theme.dart';
import 'package:nexgen_command/models/commercial/channel_role.dart';
import 'package:nexgen_command/models/commercial/commercial_location.dart';
import 'package:nexgen_command/models/commercial/commercial_organization.dart';
import 'package:nexgen_command/models/commercial/commercial_role.dart';
import 'package:nexgen_command/models/commercial/commercial_schedule.dart';
import 'package:nexgen_command/services/commercial/commercial_providers.dart';
import 'package:nexgen_command/services/commercial/corporate_push_service.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

// =============================================================================
// ENUMS & STATUS MODEL
// =============================================================================

enum _FleetViewMode { list, map }

enum LocationStatus { online, warning, offline, inactive }

enum _SortMode { alphabetical, statusFirst, region }

class _StatusFilter {
  bool online;
  bool warning;
  bool offline;
  bool activeOverride;
  bool gameDay;

  _StatusFilter({
    this.online = true,
    this.warning = true,
    this.offline = true,
    this.activeOverride = false,
    this.gameDay = false,
  });

  _StatusFilter copyWith({
    bool? online,
    bool? warning,
    bool? offline,
    bool? activeOverride,
    bool? gameDay,
  }) =>
      _StatusFilter(
        online: online ?? this.online,
        warning: warning ?? this.warning,
        offline: offline ?? this.offline,
        activeOverride: activeOverride ?? this.activeOverride,
        gameDay: gameDay ?? this.gameDay,
      );
}

/// Composite runtime status for a location derived from Firestore snapshots.
class _LocationState {
  final CommercialLocation location;
  final CommercialSchedule? schedule;
  final LocationStatus status;
  final String? currentDesign;
  final String? nextEvent;
  final bool isGameDay;
  final bool hasOverride;
  final bool isLocked;
  final DateTime? lastSync;
  final Map<String, String> channelDesigns; // channelId → designName

  const _LocationState({
    required this.location,
    this.schedule,
    this.status = LocationStatus.offline,
    this.currentDesign,
    this.nextEvent,
    this.isGameDay = false,
    this.hasOverride = false,
    this.isLocked = false,
    this.lastSync,
    this.channelDesigns = const {},
  });
}

// =============================================================================
// PROVIDERS
// =============================================================================

final _viewModeProvider =
    StateProvider<_FleetViewMode>((ref) => _FleetViewMode.list);

final _sortModeProvider =
    StateProvider<_SortMode>((ref) => _SortMode.alphabetical);

final _filterProvider = StateProvider<_StatusFilter>((ref) => _StatusFilter());

/// Stream of all locations belonging to the org, with real-time updates.
final _locationsStreamProvider =
    StreamProvider.family<List<CommercialLocation>, String>(
        (ref, orgId) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('commercial_locations')
      .where('org_id', isEqualTo: orgId)
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) => CommercialLocation.fromJson(doc.data()))
          .toList());
});

/// Stream of all commercial schedules for the user's locations.
final _schedulesStreamProvider =
    StreamProvider<Map<String, CommercialSchedule>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('commercial_schedule')
      .snapshots()
      .map((snap) {
    final map = <String, CommercialSchedule>{};
    for (final doc in snap.docs) {
      try {
        final sched = CommercialSchedule.fromJson(doc.data());
        map[sched.locationId] = sched;
      } catch (_) {}
    }
    return map;
  });
});

// =============================================================================
// FLEET DASHBOARD SCREEN
// =============================================================================

class FleetDashboardScreen extends ConsumerStatefulWidget {
  final CommercialOrganization org;

  const FleetDashboardScreen({super.key, required this.org});

  @override
  ConsumerState<FleetDashboardScreen> createState() =>
      _FleetDashboardScreenState();
}

class _FleetDashboardScreenState
    extends ConsumerState<FleetDashboardScreen> {
  CommercialRole? _userRole;

  @override
  void initState() {
    super.initState();
    _resolveRole();
  }

  Future<void> _resolveRole() async {
    final permService = ref.read(commercialPermissionsServiceProvider);
    final canPush = await permService.canPushToAll();
    if (mounted) {
      setState(() {
        _userRole =
            canPush ? CommercialRole.corporateAdmin : CommercialRole.regionalManager;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewMode = ref.watch(_viewModeProvider);
    final locationsAsync = ref.watch(_locationsStreamProvider(widget.org.orgId));
    final schedulesAsync = ref.watch(_schedulesStreamProvider);
    final isCorporateAdmin = _userRole == CommercialRole.corporateAdmin;

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: GlassAppBar(
        title: Text(
          widget.org.orgName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // View toggle
          _ViewToggle(
            mode: viewMode,
            onChanged: (m) =>
                ref.read(_viewModeProvider.notifier).state = m,
          ),
          // Filter
          IconButton(
            icon: const Icon(Icons.filter_list_rounded, size: 20),
            tooltip: 'Filter',
            onPressed: () => _showFilterSheet(context),
          ),
          // Sort (list only)
          if (viewMode == _FleetViewMode.list)
            IconButton(
              icon: const Icon(Icons.sort_rounded, size: 20),
              tooltip: 'Sort',
              onPressed: () => _showSortSheet(context),
            ),
          // Overflow menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            color: NexGenPalette.gunmetal,
            onSelected: (v) {
              if (v == 'locks') _showLocksPanel(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'locks',
                child: Text('Manage Locks',
                    style: TextStyle(color: NexGenPalette.textHigh)),
              ),
            ],
          ),
        ],
      ),
      body: locationsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
        error: (e, _) => Center(
          child: Text('Error loading locations: $e',
              style: const TextStyle(color: NexGenPalette.textMedium)),
        ),
        data: (locations) {
          final schedules = schedulesAsync.valueOrNull ?? {};
          final states = _buildLocationStates(locations, schedules);
          final filtered = _applyFilters(states, ref.watch(_filterProvider));
          final sorted = _applySort(filtered, ref.watch(_sortModeProvider));

          if (viewMode == _FleetViewMode.map) {
            return _FleetMapView(
              locationStates: sorted,
              orgName: widget.org.orgName,
            );
          }
          return _FleetListView(locationStates: sorted);
        },
      ),
      floatingActionButton: isCorporateAdmin
          ? _FleetFab(org: widget.org)
          : null,
    );
  }

  List<_LocationState> _buildLocationStates(
    List<CommercialLocation> locations,
    Map<String, CommercialSchedule> schedules,
  ) {
    return locations.map((loc) {
      final sched = schedules[loc.locationId];

      // Derive status
      LocationStatus status = LocationStatus.offline;
      bool hasOverride = false;
      bool isGameDay = false;
      String? currentDesign;
      Map<String, String> channelDesigns = {};

      // Simple heuristic: if controller exists → online
      if (loc.controllerId.isNotEmpty) {
        status = LocationStatus.online;
      }

      // Check schedule
      if (sched != null) {
        if (sched.defaultAmbientDesignId != null) {
          currentDesign = sched.defaultAmbientDesignId;
        }
        // Populate channel designs from day-parts
        for (final dp in sched.dayParts) {
          if (dp.assignedDesignId != null && dp.isActiveAt(DateTime.now())) {
            currentDesign = dp.assignedDesignId;
            if (dp.isGameDayOverride) isGameDay = true;
          }
        }
      }

      // Build channel design map
      for (final ch in loc.channelConfigs) {
        channelDesigns[ch.channelId] =
            currentDesign ?? ch.defaultDesignId ?? 'Default';
      }

      // Determine next event
      String? nextEvent;
      if (sched != null) {
        final now = DateTime.now();
        for (final dp in sched.dayParts) {
          final dpStartMin = dp.startTime.hour * 60 + dp.startTime.minute;
          final nowMin = now.hour * 60 + now.minute;
          if (dpStartMin > nowMin) {
            nextEvent = dp.name;
            break;
          }
        }
      }

      return _LocationState(
        location: loc,
        schedule: sched,
        status: status,
        currentDesign: currentDesign,
        nextEvent: nextEvent,
        isGameDay: isGameDay,
        hasOverride: hasOverride,
        isLocked: sched?.isLockedByCorporate ?? false,
        channelDesigns: channelDesigns,
        lastSync: DateTime.now(), // placeholder until controller sync data wired
      );
    }).toList();
  }

  List<_LocationState> _applyFilters(
      List<_LocationState> states, _StatusFilter filter) {
    return states.where((s) {
      if (s.status == LocationStatus.online && !filter.online) return false;
      if (s.status == LocationStatus.warning && !filter.warning) return false;
      if (s.status == LocationStatus.offline && !filter.offline) return false;
      if (filter.activeOverride && !s.hasOverride) return false;
      if (filter.gameDay && !s.isGameDay) return false;
      return true;
    }).toList();
  }

  List<_LocationState> _applySort(
      List<_LocationState> states, _SortMode mode) {
    final sorted = List<_LocationState>.from(states);
    switch (mode) {
      case _SortMode.alphabetical:
        sorted.sort(
            (a, b) => a.location.locationName.compareTo(b.location.locationName));
        break;
      case _SortMode.statusFirst:
        sorted.sort((a, b) {
          final aP = _statusPriority(a.status);
          final bP = _statusPriority(b.status);
          if (aP != bP) return aP.compareTo(bP);
          return a.location.locationName.compareTo(b.location.locationName);
        });
        break;
      case _SortMode.region:
        sorted.sort(
            (a, b) => a.location.address.compareTo(b.location.address));
        break;
    }
    return sorted;
  }

  int _statusPriority(LocationStatus s) {
    switch (s) {
      case LocationStatus.offline:
        return 0;
      case LocationStatus.warning:
        return 1;
      case LocationStatus.online:
        return 2;
      case LocationStatus.inactive:
        return 3;
    }
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FilterSheet(),
    );
  }

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SortSheet(),
    );
  }

  void _showLocksPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _ManageLocksSheet(),
    );
  }
}

// =============================================================================
// VIEW TOGGLE
// =============================================================================

class _ViewToggle extends StatelessWidget {
  final _FleetViewMode mode;
  final ValueChanged<_FleetViewMode> onChanged;

  const _ViewToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleBtn(
            icon: Icons.list_rounded,
            selected: mode == _FleetViewMode.list,
            onTap: () => onChanged(_FleetViewMode.list),
          ),
          _ToggleBtn(
            icon: Icons.map_rounded,
            selected: mode == _FleetViewMode.map,
            onTap: () => onChanged(_FleetViewMode.map),
          ),
        ],
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleBtn({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color:
              selected ? NexGenPalette.cyan.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm - 2),
        ),
        child: Icon(icon,
            size: 18,
            color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium),
      ),
    );
  }
}

// =============================================================================
// FILTER SHEET
// =============================================================================

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_filterProvider);

    return Container(
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dragHandle(),
              const SizedBox(height: 8),
              const Text('Filter Locations',
                  style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              _FilterToggle(
                label: 'Online',
                color: _statusColor(LocationStatus.online),
                value: filter.online,
                onChanged: (v) =>
                    ref.read(_filterProvider.notifier).state =
                        filter.copyWith(online: v),
              ),
              _FilterToggle(
                label: 'Warning',
                color: _statusColor(LocationStatus.warning),
                value: filter.warning,
                onChanged: (v) =>
                    ref.read(_filterProvider.notifier).state =
                        filter.copyWith(warning: v),
              ),
              _FilterToggle(
                label: 'Offline',
                color: _statusColor(LocationStatus.offline),
                value: filter.offline,
                onChanged: (v) =>
                    ref.read(_filterProvider.notifier).state =
                        filter.copyWith(offline: v),
              ),
              const Divider(color: NexGenPalette.line, height: 24),
              _FilterToggle(
                label: 'Active Override Only',
                color: NexGenPalette.amber,
                value: filter.activeOverride,
                onChanged: (v) =>
                    ref.read(_filterProvider.notifier).state =
                        filter.copyWith(activeOverride: v),
              ),
              _FilterToggle(
                label: 'Game Day Mode Only',
                color: NexGenPalette.gold,
                value: filter.gameDay,
                onChanged: (v) =>
                    ref.read(_filterProvider.notifier).state =
                        filter.copyWith(gameDay: v),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  final String label;
  final Color color;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FilterToggle({
    required this.label,
    required this.color,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: NexGenPalette.textHigh, fontSize: 14)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.4),
            activeThumbColor: NexGenPalette.cyan,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SORT SHEET
// =============================================================================

class _SortSheet extends ConsumerWidget {
  const _SortSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(_sortModeProvider);

    return Container(
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dragHandle(),
              const SizedBox(height: 8),
              const Text('Sort By',
                  style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _SortOption(
                label: 'Alphabetical',
                icon: Icons.sort_by_alpha_rounded,
                selected: current == _SortMode.alphabetical,
                onTap: () {
                  ref.read(_sortModeProvider.notifier).state =
                      _SortMode.alphabetical;
                  Navigator.pop(context);
                },
              ),
              _SortOption(
                label: 'Status (Alerts First)',
                icon: Icons.warning_amber_rounded,
                selected: current == _SortMode.statusFirst,
                onTap: () {
                  ref.read(_sortModeProvider.notifier).state =
                      _SortMode.statusFirst;
                  Navigator.pop(context);
                },
              ),
              _SortOption(
                label: 'Region',
                icon: Icons.location_on_rounded,
                selected: current == _SortMode.region,
                onTap: () {
                  ref.read(_sortModeProvider.notifier).state = _SortMode.region;
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SortOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          size: 20,
          color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium),
      title: Text(label,
          style: TextStyle(
            color: selected ? NexGenPalette.cyan : NexGenPalette.textHigh,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          )),
      trailing: selected
          ? const Icon(Icons.check_rounded, size: 18, color: NexGenPalette.cyan)
          : null,
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }
}

// =============================================================================
// LIST VIEW
// =============================================================================

class _FleetListView extends StatelessWidget {
  final List<_LocationState> locationStates;

  const _FleetListView({required this.locationStates});

  @override
  Widget build(BuildContext context) {
    if (locationStates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_rounded,
                size: 48, color: NexGenPalette.textMedium.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No locations match filters',
                style: TextStyle(
                    color: NexGenPalette.textMedium, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      itemCount: locationStates.length,
      itemBuilder: (context, i) =>
          _LocationCard(state: locationStates[i]),
    );
  }
}

// =============================================================================
// LOCATION CARD — expandable
// =============================================================================

class _LocationCard extends StatefulWidget {
  final _LocationState state;
  const _LocationCard({required this.state});

  @override
  State<_LocationCard> createState() => _LocationCardState();
}

class _LocationCardState extends State<_LocationCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final loc = widget.state.location;
    final status = widget.state.status;
    final statusColor = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: widget.state.isGameDay
              ? NexGenPalette.gold.withValues(alpha: 0.5)
              : NexGenPalette.line,
        ),
      ),
      child: Column(
        children: [
          // Collapsed header — always visible
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Status dot
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Name + city
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.locationName,
                              style: const TextStyle(
                                color: NexGenPalette.textHigh,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              loc.address,
                              style: const TextStyle(
                                color: NexGenPalette.textMedium,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Badges
                      if (widget.state.isLocked)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.lock_rounded,
                              size: 14, color: NexGenPalette.amber),
                        ),
                      if (widget.state.isGameDay)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.sports_football_rounded,
                              size: 14, color: NexGenPalette.gold),
                        ),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: NexGenPalette.textMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Channel summary row
                  _ChannelSummaryRow(
                    channels: loc.channelConfigs,
                    designs: widget.state.channelDesigns,
                  ),
                  // Next event
                  if (widget.state.nextEvent != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 12, color: NexGenPalette.textMedium),
                        const SizedBox(width: 4),
                        Text(
                          'Next: ${widget.state.nextEvent}',
                          style: const TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expanded detail
          AnimatedCrossFade(
            firstChild: _ExpandedDetail(state: widget.state),
            secondChild: const SizedBox.shrink(),
            crossFadeState:
                _expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// CHANNEL SUMMARY ROW (collapsed)
// =============================================================================

class _ChannelSummaryRow extends StatelessWidget {
  final List<ChannelRoleConfig> channels;
  final Map<String, String> designs;

  const _ChannelSummaryRow({required this.channels, required this.designs});

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) return const SizedBox.shrink();

    // Show first 3 channels as compact chips
    final display = channels.take(3).toList();
    final remaining = channels.length - 3;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final ch in display)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _roleColor(ch.role).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: _roleColor(ch.role).withValues(alpha: 0.25)),
            ),
            child: Text(
              '${ch.friendlyName}: ${designs[ch.channelId] ?? "Off"}',
              style: TextStyle(
                color: _roleColor(ch.role),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (remaining > 0)
          Text(
            '+$remaining more',
            style: const TextStyle(
                color: NexGenPalette.textMedium, fontSize: 10),
          ),
      ],
    );
  }
}

// =============================================================================
// EXPANDED DETAIL
// =============================================================================

class _ExpandedDetail extends StatelessWidget {
  final _LocationState state;
  const _ExpandedDetail({required this.state});

  @override
  Widget build(BuildContext context) {
    final loc = state.location;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: NexGenPalette.line, height: 16),
          // Full channel list
          const Text('CHANNELS',
              style: TextStyle(
                  color: NexGenPalette.textMedium,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
          for (final ch in loc.channelConfigs)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(ch.role.icon,
                      size: 14,
                      color: _roleColor(ch.role).withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(ch.friendlyName,
                        style: const TextStyle(
                            color: NexGenPalette.textHigh, fontSize: 12)),
                  ),
                  Text(
                    state.channelDesigns[ch.channelId] ?? 'Off',
                    style: const TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 11),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          // Last sync
          if (state.lastSync != null)
            _InfoRow(
              icon: Icons.sync_rounded,
              label: 'Last Sync',
              value: _formatTime(state.lastSync!),
            ),
          // Status label
          _InfoRow(
            icon: Icons.circle,
            iconColor: _statusColor(state.status),
            iconSize: 10,
            label: 'Status',
            value: _statusLabel(state.status),
          ),
          // Game day
          if (state.isGameDay)
            _InfoRow(
              icon: Icons.sports_football_rounded,
              iconColor: NexGenPalette.gold,
              label: 'Game Day',
              value: 'Active',
              valueColor: NexGenPalette.gold,
            ),
          // Lock
          if (state.isLocked)
            _InfoRow(
              icon: Icons.lock_rounded,
              iconColor: NexGenPalette.amber,
              label: 'Corporate Lock',
              value: 'Active',
              valueColor: NexGenPalette.amber,
            ),
          const SizedBox(height: 12),
          // Quick action buttons
          Row(
            children: [
              _MiniAction(
                icon: Icons.play_arrow_rounded,
                label: 'Override',
                color: NexGenPalette.cyan,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Override — open design picker'),
                      backgroundColor: NexGenPalette.gunmetal,
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              _MiniAction(
                icon: Icons.calendar_today_rounded,
                label: 'Schedule',
                color: NexGenPalette.violet,
                onTap: () {
                  // TODO: navigate to CommercialScheduleScreen for this location
                },
              ),
              const SizedBox(width: 8),
              _MiniAction(
                icon: Icons.edit_rounded,
                label: 'Edit',
                color: NexGenPalette.textMedium,
                onTap: () {
                  // TODO: navigate to location settings
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:${dt.minute.toString().padLeft(2, '0')} $period';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final double iconSize;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    this.iconColor,
    this.iconSize = 14,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon,
              size: iconSize, color: iconColor ?? NexGenPalette.textMedium),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 12)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                color: valueColor ?? NexGenPalette.textHigh,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              )),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MiniAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// MAP VIEW
// =============================================================================

class _FleetMapView extends StatefulWidget {
  final List<_LocationState> locationStates;
  final String orgName;

  const _FleetMapView({required this.locationStates, required this.orgName});

  @override
  State<_FleetMapView> createState() => _FleetMapViewState();
}

class _FleetMapViewState extends State<_FleetMapView> {
  GoogleMapController? _mapController;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.locationStates.isEmpty) {
      return const Center(
        child: Text('No locations to display',
            style: TextStyle(color: NexGenPalette.textMedium)),
      );
    }

    final markers = widget.locationStates.map((ls) {
      final color = _statusHue(ls.status);
      return Marker(
        markerId: MarkerId(ls.location.locationId),
        position: LatLng(ls.location.lat, ls.location.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(color),
        infoWindow: InfoWindow(title: ls.location.locationName),
        onTap: () => _showPinSheet(context, ls),
      );
    }).toSet();

    // Calculate bounds
    final lats = widget.locationStates.map((s) => s.location.lat);
    final lngs = widget.locationStates.map((s) => s.location.lng);
    final sw = LatLng(
      lats.reduce((a, b) => a < b ? a : b),
      lngs.reduce((a, b) => a < b ? a : b),
    );
    final ne = LatLng(
      lats.reduce((a, b) => a > b ? a : b),
      lngs.reduce((a, b) => a > b ? a : b),
    );

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(
          (sw.latitude + ne.latitude) / 2,
          (sw.longitude + ne.longitude) / 2,
        ),
        zoom: 10,
      ),
      markers: markers,
      style: _darkMapStyle,
      onMapCreated: (controller) {
        _mapController = controller;
        // Auto-fit bounds after map loads
        if (widget.locationStates.length > 1) {
          Future.delayed(const Duration(milliseconds: 300), () {
            _mapController?.animateCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(southwest: sw, northeast: ne),
                60, // padding
              ),
            );
          });
        }
      },
      myLocationEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }

  void _showPinSheet(BuildContext context, _LocationState ls) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MapPinSheet(state: ls),
    );
  }

  double _statusHue(LocationStatus s) {
    switch (s) {
      case LocationStatus.online:
        return BitmapDescriptor.hueGreen;
      case LocationStatus.warning:
        return BitmapDescriptor.hueYellow;
      case LocationStatus.offline:
        return BitmapDescriptor.hueRed;
      case LocationStatus.inactive:
        return BitmapDescriptor.hueViolet;
    }
  }

  // Minimal dark map style for the Lumina theme
  static const _darkMapStyle = '''[
    {"elementType":"geometry","stylers":[{"color":"#0d1117"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#8b949e"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#0d1117"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#161b22"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#07091a"}]}
  ]''';
}

// =============================================================================
// MAP PIN BOTTOM SHEET
// =============================================================================

class _MapPinSheet extends StatelessWidget {
  final _LocationState state;
  const _MapPinSheet({required this.state});

  @override
  Widget build(BuildContext context) {
    final loc = state.location;
    final statusColor = _statusColor(state.status);

    return Container(
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dragHandle(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(loc.locationName,
                        style: const TextStyle(
                            color: NexGenPalette.textHigh,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                  if (state.isLocked)
                    Icon(Icons.lock_rounded,
                        size: 16, color: NexGenPalette.amber),
                  if (state.isGameDay)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.sports_football_rounded,
                          size: 16, color: NexGenPalette.gold),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(loc.address,
                  style: const TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 12)),
              const SizedBox(height: 12),
              _ChannelSummaryRow(
                channels: loc.channelConfigs,
                designs: state.channelDesigns,
              ),
              if (state.nextEvent != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 14, color: NexGenPalette.textMedium),
                    const SizedBox(width: 4),
                    Text('Next: ${state.nextEvent}',
                        style: const TextStyle(
                            color: NexGenPalette.textMedium, fontSize: 12)),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text(_statusLabel(state.status),
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// FLEET FAB — Push Schedule / Push Campaign
// =============================================================================

class _FleetFab extends ConsumerWidget {
  final CommercialOrganization org;
  const _FleetFab({required this.org});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton.extended(
      onPressed: () => _showPushOptions(context, ref),
      backgroundColor: NexGenPalette.cyan,
      foregroundColor: NexGenPalette.matteBlack,
      icon: const Icon(Icons.send_rounded, size: 18),
      label: const Text('Push',
          style: TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  void _showPushOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PushOptionsSheet(org: org),
    );
  }
}

class _PushOptionsSheet extends StatelessWidget {
  final CommercialOrganization org;
  const _PushOptionsSheet({required this.org});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dragHandle(),
              const SizedBox(height: 8),
              const Text('Push to Fleet',
                  style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              _PushOptionTile(
                icon: Icons.calendar_today_rounded,
                title: 'Push Schedule',
                subtitle: 'Push a schedule to selected locations',
                color: NexGenPalette.cyan,
                onTap: () {
                  Navigator.pop(context);
                  _openPushScheduleFlow(context);
                },
              ),
              const SizedBox(height: 8),
              _PushOptionTile(
                icon: Icons.campaign_rounded,
                title: 'Push Campaign',
                subtitle: 'Create a timed campaign across locations',
                color: NexGenPalette.gold,
                onTap: () {
                  Navigator.pop(context);
                  _openPushCampaignFlow(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _openPushScheduleFlow(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PushScheduleWizard(org: org),
    );
  }

  void _openPushCampaignFlow(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PushCampaignWizard(org: org),
    );
  }
}

class _PushOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PushOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: NexGenPalette.textHigh,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: NexGenPalette.textMedium, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: NexGenPalette.textMedium),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PUSH SCHEDULE WIZARD (5-step)
// =============================================================================

class _PushScheduleWizard extends ConsumerStatefulWidget {
  final CommercialOrganization org;
  const _PushScheduleWizard({required this.org});

  @override
  ConsumerState<_PushScheduleWizard> createState() =>
      _PushScheduleWizardState();
}

class _PushScheduleWizardState extends ConsumerState<_PushScheduleWizard> {
  int _step = 0;
  String? _selectedScheduleId;
  bool _allLocations = true;
  final Set<String> _selectedLocationIds = {};
  bool _locked = false;
  DateTime? _lockExpiry;
  bool _pushing = false;

  static const _stepTitles = [
    'Select Schedule',
    'Select Scope',
    'Lock Options',
    'Impact Summary',
    'Confirm',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dragHandle(),
            // Step indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Text(
                    'Step ${_step + 1} of 5',
                    style: const TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_step + 1) / 5,
                      backgroundColor: NexGenPalette.line,
                      color: NexGenPalette.cyan,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _stepTitles[_step],
                  style: const TextStyle(
                    color: NexGenPalette.textHigh,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Step content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildStep(),
              ),
            ),
            // Navigation
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: () => setState(() => _step--),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NexGenPalette.textMedium,
                        side: const BorderSide(color: NexGenPalette.line),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  if (_step < 4)
                    FilledButton(
                      onPressed: _canAdvance() ? () => setState(() => _step++) : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: NexGenPalette.cyan,
                        foregroundColor: NexGenPalette.matteBlack,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                      child: const Text('Next'),
                    ),
                  if (_step == 4)
                    FilledButton(
                      onPressed: _pushing ? null : _executePush,
                      style: FilledButton.styleFrom(
                        backgroundColor: NexGenPalette.cyan,
                        foregroundColor: NexGenPalette.matteBlack,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                      child: _pushing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: NexGenPalette.matteBlack),
                            )
                          : const Text('Push Schedule'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canAdvance() {
    switch (_step) {
      case 0:
        return _selectedScheduleId != null;
      case 1:
        return _allLocations || _selectedLocationIds.isNotEmpty;
      default:
        return true;
    }
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildScheduleSelector();
      case 1:
        return _buildScopeSelector();
      case 2:
        return _buildLockOptions();
      case 3:
        return _buildImpactSummary();
      case 4:
        return _buildConfirmation();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildScheduleSelector() {
    // Placeholder: in production, fetch saved schedules from Firestore
    return Column(
      children: [
        _ScheduleOption(
          id: 'default_ambient',
          name: 'Default Ambient',
          selected: _selectedScheduleId == 'default_ambient',
          onTap: () =>
              setState(() => _selectedScheduleId = 'default_ambient'),
        ),
        _ScheduleOption(
          id: 'weekend_special',
          name: 'Weekend Special',
          selected: _selectedScheduleId == 'weekend_special',
          onTap: () =>
              setState(() => _selectedScheduleId = 'weekend_special'),
        ),
        _ScheduleOption(
          id: 'holiday_theme',
          name: 'Holiday Theme',
          selected: _selectedScheduleId == 'holiday_theme',
          onTap: () =>
              setState(() => _selectedScheduleId = 'holiday_theme'),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NexGenPalette.matteBlack,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: const Text(
            'Saved schedules will load from your organization',
            style: TextStyle(
                color: NexGenPalette.textMedium, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildScopeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ScopeOption(
          label: 'All Locations',
          subtitle: '${widget.org.locationIds.length} locations',
          selected: _allLocations,
          onTap: () => setState(() => _allLocations = true),
        ),
        const SizedBox(height: 8),
        _ScopeOption(
          label: 'Selected Locations',
          subtitle: _selectedLocationIds.isEmpty
              ? 'Choose specific locations'
              : '${_selectedLocationIds.length} selected',
          selected: !_allLocations,
          onTap: () => setState(() => _allLocations = false),
        ),
        if (!_allLocations) ...[
          const SizedBox(height: 12),
          const Text('Select locations:',
              style: TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 12)),
          const SizedBox(height: 8),
          // Location checkboxes
          for (final locId in widget.org.locationIds)
            CheckboxListTile(
              value: _selectedLocationIds.contains(locId),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedLocationIds.add(locId);
                  } else {
                    _selectedLocationIds.remove(locId);
                  }
                });
              },
              title: Text(locId,
                  style: const TextStyle(
                      color: NexGenPalette.textHigh, fontSize: 13)),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: NexGenPalette.cyan,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
        ],
      ],
    );
  }

  Widget _buildLockOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ScopeOption(
          label: 'Advisory (Recommended)',
          subtitle: 'Locations can override locally',
          selected: !_locked,
          onTap: () => setState(() => _locked = false),
        ),
        const SizedBox(height: 8),
        _ScopeOption(
          label: 'Locked',
          subtitle: 'Prevents local edits until unlocked',
          selected: _locked,
          onTap: () => setState(() => _locked = true),
        ),
        if (_locked) ...[
          const SizedBox(height: 16),
          const Text('Lock Expiry (optional)',
              style: TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 12)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now().add(const Duration(days: 7)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _lockExpiry = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 16, color: NexGenPalette.textMedium),
                  const SizedBox(width: 8),
                  Text(
                    _lockExpiry != null
                        ? '${_lockExpiry!.month}/${_lockExpiry!.day}/${_lockExpiry!.year}'
                        : 'No expiry (indefinite)',
                    style: const TextStyle(
                        color: NexGenPalette.textHigh, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImpactSummary() {
    final targetIds = _allLocations
        ? widget.org.locationIds
        : _selectedLocationIds.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
                color: NexGenPalette.cyan.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Schedule: ${_selectedScheduleId ?? "None"}',
                style: const TextStyle(
                    color: NexGenPalette.textHigh, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Scope: ${_allLocations ? "All Locations" : "${targetIds.length} selected"}',
                style: const TextStyle(
                    color: NexGenPalette.textHigh, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                'Lock: ${_locked ? "Locked" : "Advisory"}${_lockExpiry != null ? " until ${_lockExpiry!.month}/${_lockExpiry!.day}" : ""}',
                style: const TextStyle(
                    color: NexGenPalette.textHigh, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('AFFECTED LOCATIONS',
            style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
        const SizedBox(height: 8),
        for (final locId in targetIds)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const Icon(Icons.store_rounded,
                    size: 14, color: NexGenPalette.textMedium),
                const SizedBox(width: 8),
                Text(locId,
                    style: const TextStyle(
                        color: NexGenPalette.textHigh, fontSize: 13)),
                const Spacer(),
                Text(
                  _locked ? 'Will be locked' : 'Advisory',
                  style: TextStyle(
                    color: _locked
                        ? NexGenPalette.amber
                        : NexGenPalette.textMedium,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildConfirmation() {
    final targetCount = _allLocations
        ? widget.org.locationIds.length
        : _selectedLocationIds.length;

    return Column(
      children: [
        Icon(Icons.send_rounded,
            size: 48, color: NexGenPalette.cyan.withValues(alpha: 0.6)),
        const SizedBox(height: 12),
        Text(
          'Push "$_selectedScheduleId" to $targetCount location${targetCount == 1 ? "" : "s"}?',
          style: const TextStyle(
              color: NexGenPalette.textHigh,
              fontSize: 16,
              fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        if (_locked) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_rounded,
                  size: 14, color: NexGenPalette.amber),
              const SizedBox(width: 4),
              const Text('Locations will be locked after push',
                  style: TextStyle(
                      color: NexGenPalette.amber, fontSize: 12)),
            ],
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Future<void> _executePush() async {
    setState(() => _pushing = true);
    try {
      final pushService = ref.read(corporatePushServiceProvider);
      final targetIds = _allLocations
          ? widget.org.locationIds
          : _selectedLocationIds.toList();

      // Create a schedule object from the selected schedule ID
      final schedule = CommercialSchedule(
        locationId: 'template',
        defaultAmbientDesignId: _selectedScheduleId,
      );

      await pushService.pushScheduleToLocations(
        schedule,
        targetIds,
        locked: _locked,
        lockExpiry: _lockExpiry,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Schedule pushed to ${targetIds.length} locations'),
            backgroundColor: NexGenPalette.gunmetal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Push failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }
}

class _ScheduleOption extends StatelessWidget {
  final String id;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  const _ScheduleOption({
    required this.id,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? NexGenPalette.cyan.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected
                  ? NexGenPalette.cyan.withValues(alpha: 0.4)
                  : NexGenPalette.line,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                size: 18,
                color: selected
                    ? NexGenPalette.cyan
                    : NexGenPalette.textMedium,
              ),
              const SizedBox(width: 10),
              Text(name,
                  style: TextStyle(
                    color: selected
                        ? NexGenPalette.textHigh
                        : NexGenPalette.textMedium,
                    fontSize: 14,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ScopeOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? NexGenPalette.cyan.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected
                ? NexGenPalette.cyan.withValues(alpha: 0.4)
                : NexGenPalette.line,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 18,
              color: selected
                  ? NexGenPalette.cyan
                  : NexGenPalette.textMedium,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    )),
                Text(subtitle,
                    style: const TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// PUSH CAMPAIGN WIZARD
// =============================================================================

class _PushCampaignWizard extends ConsumerStatefulWidget {
  final CommercialOrganization org;
  const _PushCampaignWizard({required this.org});

  @override
  ConsumerState<_PushCampaignWizard> createState() =>
      _PushCampaignWizardState();
}

class _PushCampaignWizardState extends ConsumerState<_PushCampaignWizard> {
  String _campaignName = '';
  String? _scheduleId;
  bool _allLocations = true;
  final Set<String> _selectedLocationIds = {};
  DateTime? _startDate;
  DateTime? _endDate;
  bool _pushing = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dragHandle(),
              const SizedBox(height: 12),
              const Text('New Campaign',
                  style: TextStyle(
                      color: NexGenPalette.textHigh,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              // Campaign name
              TextField(
                onChanged: (v) => setState(() => _campaignName = v),
                style: const TextStyle(color: NexGenPalette.textHigh),
                decoration: InputDecoration(
                  labelText: 'Campaign Name',
                  labelStyle: const TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: NexGenPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: NexGenPalette.cyan),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              // Schedule
              TextField(
                onChanged: (v) => setState(() => _scheduleId = v),
                style: const TextStyle(color: NexGenPalette.textHigh),
                decoration: InputDecoration(
                  labelText: 'Schedule ID',
                  labelStyle: const TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 13),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: NexGenPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    borderSide: const BorderSide(color: NexGenPalette.cyan),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              // Scope
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('All Locations'),
                    selected: _allLocations,
                    onSelected: (v) => setState(() => _allLocations = true),
                    selectedColor: NexGenPalette.cyan.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: _allLocations
                          ? NexGenPalette.cyan
                          : NexGenPalette.textMedium,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: _allLocations
                          ? NexGenPalette.cyan.withValues(alpha: 0.4)
                          : NexGenPalette.line,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Selected'),
                    selected: !_allLocations,
                    onSelected: (v) => setState(() => _allLocations = false),
                    selectedColor: NexGenPalette.cyan.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: !_allLocations
                          ? NexGenPalette.cyan
                          : NexGenPalette.textMedium,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: !_allLocations
                          ? NexGenPalette.cyan.withValues(alpha: 0.4)
                          : NexGenPalette.line,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Date range
              Row(
                children: [
                  Expanded(
                    child: _DatePickerField(
                      label: 'Start Date',
                      value: _startDate,
                      onPicked: (d) => setState(() => _startDate = d),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DatePickerField(
                      label: 'End Date',
                      value: _endDate,
                      onPicked: (d) => setState(() => _endDate = d),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _canSubmit() ? _executeCampaign : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.gold,
                    foregroundColor: NexGenPalette.matteBlack,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: _pushing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: NexGenPalette.matteBlack),
                        )
                      : const Text('Launch Campaign',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  bool _canSubmit() =>
      !_pushing &&
      _campaignName.trim().isNotEmpty &&
      _scheduleId != null &&
      _scheduleId!.trim().isNotEmpty &&
      _startDate != null &&
      _endDate != null;

  Future<void> _executeCampaign() async {
    setState(() => _pushing = true);
    try {
      final pushService = ref.read(corporatePushServiceProvider);
      final targetIds = _allLocations
          ? widget.org.locationIds
          : _selectedLocationIds.toList();

      final schedule = CommercialSchedule(
        locationId: 'campaign',
        defaultAmbientDesignId: _scheduleId,
      );

      await pushService.pushCampaign(
        _campaignName.trim(),
        schedule,
        targetIds,
        _startDate!,
        _endDate!,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Campaign "$_campaignName" launched'),
            backgroundColor: NexGenPalette.gunmetal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Campaign launch failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPicked;

  const _DatePickerField({
    required this.label,
    this.value,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: NexGenPalette.textMedium, fontSize: 10)),
            const SizedBox(height: 2),
            Text(
              value != null
                  ? '${value!.month}/${value!.day}/${value!.year}'
                  : 'Select',
              style: const TextStyle(
                  color: NexGenPalette.textHigh, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// MANAGE LOCKS SHEET
// =============================================================================

class _ManageLocksSheet extends ConsumerStatefulWidget {
  const _ManageLocksSheet();

  @override
  ConsumerState<_ManageLocksSheet> createState() => _ManageLocksSheetState();
}

class _ManageLocksSheetState extends ConsumerState<_ManageLocksSheet> {
  List<LocationLockStatus>? _locks;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLocks();
  }

  Future<void> _loadLocks() async {
    try {
      final pushService = ref.read(corporatePushServiceProvider);
      final locks = await pushService.getActiveLocks();
      if (mounted) setState(() { _locks = locks; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dragHandle(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.lock_rounded,
                      size: 18, color: NexGenPalette.amber),
                  const SizedBox(width: 8),
                  const Text('Active Locks',
                      style: TextStyle(
                          color: NexGenPalette.textHigh,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(
                      color: NexGenPalette.cyan),
                ))
              else if (_locks == null || _locks!.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No active locks',
                        style: TextStyle(
                            color: NexGenPalette.textMedium)),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _locks!.length,
                    itemBuilder: (context, i) {
                      final lock = _locks![i];
                      return _LockTile(
                        lock: lock,
                        onUnlock: () => _unlockLocation(lock.locationId),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _unlockLocation(String locationId) async {
    try {
      final pushService = ref.read(corporatePushServiceProvider);
      await pushService.unlockLocation(locationId);
      _loadLocks(); // refresh
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location unlocked'),
            backgroundColor: NexGenPalette.gunmetal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unlock failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }
}

class _LockTile extends StatelessWidget {
  final LocationLockStatus lock;
  final VoidCallback onUnlock;

  const _LockTile({required this.lock, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.matteBlack,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
            color: NexGenPalette.amber.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_rounded,
              size: 16, color: NexGenPalette.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(lock.locationName,
                    style: const TextStyle(
                        color: NexGenPalette.textHigh,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(
                  lock.lockExpiryDate != null
                      ? 'Expires: ${lock.lockExpiryDate!.month}/${lock.lockExpiryDate!.day}/${lock.lockExpiryDate!.year}'
                      : 'No expiry',
                  style: const TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 11),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onUnlock,
            style: OutlinedButton.styleFrom(
              foregroundColor: NexGenPalette.amber,
              side: BorderSide(
                  color: NexGenPalette.amber.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm)),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Unlock', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SHARED HELPERS
// =============================================================================

Color _statusColor(LocationStatus s) {
  switch (s) {
    case LocationStatus.online:
      return const Color(0xFF4CAF50);
    case LocationStatus.warning:
      return NexGenPalette.amber;
    case LocationStatus.offline:
      return const Color(0xFFFF5252);
    case LocationStatus.inactive:
      return NexGenPalette.textMedium;
  }
}

String _statusLabel(LocationStatus s) {
  switch (s) {
    case LocationStatus.online:
      return 'Online — Running';
    case LocationStatus.warning:
      return 'Online — Warning';
    case LocationStatus.offline:
      return 'Offline';
    case LocationStatus.inactive:
      return 'Inactive';
  }
}

Color _roleColor(ChannelRoleType role) {
  switch (role) {
    case ChannelRoleType.interior:
      return NexGenPalette.cyan;
    case ChannelRoleType.outdoorFacade:
      return NexGenPalette.green;
    case ChannelRoleType.windowDisplay:
      return NexGenPalette.violet;
    case ChannelRoleType.patio:
      return const Color(0xFFFF8A50);
    case ChannelRoleType.canopy:
      return const Color(0xFF64B5F6);
    case ChannelRoleType.signage:
      return NexGenPalette.amber;
  }
}

Widget _dragHandle() => Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: NexGenPalette.textSecondary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
