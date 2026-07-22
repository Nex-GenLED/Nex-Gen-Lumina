import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_colors.dart';
import '../../../theme.dart';
import '../../../widgets/glass_app_bar.dart';
import '../data/team_colors.dart';
import '../models/sport_type.dart';
import '../providers/sports_alert_providers.dart';
import 'zone_assignment_screen.dart';

/// Filter chip state — null means "ALL".
final _sportFilterProvider = StateProvider<SportType?>((ref) => null);

/// Filtered teams considering both search query and sport filter.
final _filteredWithSportProvider =
    Provider<List<MapEntry<String, TeamColors>>>((ref) {
  final base = ref.watch(filteredTeamsProvider);
  final sport = ref.watch(_sportFilterProvider);
  if (sport == null) return base;
  return base.where((e) => e.value.sport == sport).toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TeamPickerScreen extends ConsumerStatefulWidget {
  const TeamPickerScreen({super.key});

  @override
  ConsumerState<TeamPickerScreen> createState() => _TeamPickerScreenState();
}

class _TeamPickerScreenState extends ConsumerState<TeamPickerScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Reset search on enter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(teamSearchProvider.notifier).state = '';
      ref.read(_sportFilterProvider.notifier).state = null;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(_filteredWithSportProvider);
    final activeSport = ref.watch(_sportFilterProvider);
    final existingSlugs = ref
        .watch(sportsAlertConfigsProvider)
        .map((c) => c.teamSlug)
        .toSet();

    return Scaffold(
      appBar: const GlassAppBar(title: Text('Choose a Team')),
      body: Column(
        children: [
          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) =>
                  ref.read(teamSearchProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: 'Search teams...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(teamSearchProvider.notifier).state = '';
                        },
                      )
                    : null,
                filled: true,
                fillColor: NexGenPalette.gunmetal,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: NexGenPalette.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: NexGenPalette.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: NexGenPalette.cyan),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // ── Sport filter chips ──
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _SportChip(
                  label: 'ALL',
                  selected: activeSport == null,
                  onTap: () =>
                      ref.read(_sportFilterProvider.notifier).state = null,
                ),
                ...SportType.values.map((s) => _SportChip(
                      label: s.displayName,
                      selected: activeSport == s,
                      onTap: () =>
                          ref.read(_sportFilterProvider.notifier).state = s,
                    )),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // ── Team list ──
          Expanded(
            child: teams.isEmpty
                ? Center(
                    child: Text(
                      'No teams found',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: NexGenPalette.textMedium,
                          ),
                    ),
                  )
                : ListView.builder(
                    // Bottom padding clears the GlassDockNavBar so the
                    // last team row isn't hidden behind it.
                    padding: EdgeInsets.fromLTRB(
                        16, 4, 16, navBarTotalHeight(context) + 16),
                    itemCount: teams.length,
                    itemBuilder: (context, i) {
                      final entry = teams[i];
                      final slug = entry.key;
                      final team = entry.value;
                      final alreadyAdded = existingSlugs.contains(slug);

                      return _TeamRow(
                        slug: slug,
                        team: team,
                        alreadyAdded: alreadyAdded,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sport filter chip
// ---------------------------------------------------------------------------

class _SportChip extends StatelessWidget {
  const _SportChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? NexGenPalette.cyan.withValues(alpha: 0.15)
                : NexGenPalette.gunmetal,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? NexGenPalette.cyan.withValues(alpha: 0.6)
                  : NexGenPalette.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team row
// ---------------------------------------------------------------------------

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.slug,
    required this.team,
    required this.alreadyAdded,
  });

  final String slug;
  final TeamColors team;
  final bool alreadyAdded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: alreadyAdded
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ZoneAssignmentScreen(teamSlug: slug),
                    ),
                  ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Row(
              children: [
                // Color swatch
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [team.primary, team.secondary],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: team.primary.withValues(alpha: 0.3),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Team name
                Expanded(
                  child: Text(
                    team.teamName,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: alreadyAdded
                              ? NexGenPalette.textMedium
                              : Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),

                // Sport badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    team.sport.displayName,
                    style: TextStyle(
                      color: NexGenPalette.cyan.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Status icon
                if (alreadyAdded)
                  Icon(Icons.check_circle,
                      color: NexGenPalette.cyan, size: 20)
                else
                  Icon(Icons.chevron_right,
                      color: NexGenPalette.textMedium, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
