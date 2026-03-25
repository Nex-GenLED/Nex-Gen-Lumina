import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/models/commercial/commercial_team_profile.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';
import 'package:nexgen_command/services/commercial/commercial_providers.dart';

class YourTeamsScreen extends ConsumerStatefulWidget {
  const YourTeamsScreen({super.key, required this.onNext});
  final VoidCallback onNext;

  @override
  ConsumerState<YourTeamsScreen> createState() => _YourTeamsScreenState();
}

class _YourTeamsScreenState extends ConsumerState<YourTeamsScreen> {
  final _searchCtrl = TextEditingController();
  bool _suggestionsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuggestions());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadSuggestions() {
    if (_suggestionsLoaded) return;
    _suggestionsLoaded = true;
    final draft = ref.read(commercialOnboardingProvider);
    if (draft.teams.isNotEmpty) return;

    // Use a simple lat/lng fallback — in production this would geocode the address.
    // For now, pick a central US default; the geo service handles radius matching.
    final svc = ref.read(geoTeamSuggestionServiceProvider);
    final suggested = svc.getSuggestedTeams(39.8283, -98.5795); // US center
    if (suggested.isNotEmpty) {
      ref.read(commercialOnboardingProvider.notifier).update(
            (d) => d.copyWith(teams: suggested.take(5).toList()),
          );
    }
  }

  void _removeTeam(int index) {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final list = List<CommercialTeamProfile>.from(d.teams)..removeAt(index);
      // Re-rank
      final ranked = list.asMap().entries.map(
            (e) => e.value.copyWith(priorityRank: e.key + 1),
          );
      return d.copyWith(teams: ranked.toList());
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final list = List<CommercialTeamProfile>.from(d.teams);
      final item = list.removeAt(oldIndex);
      list.insert(newIndex, item);
      final ranked = list.asMap().entries.map(
            (e) => e.value.copyWith(priorityRank: e.key + 1),
          );
      return d.copyWith(teams: ranked.toList());
    });
  }

  void _updateTeam(int index, CommercialTeamProfile updated) {
    ref.read(commercialOnboardingProvider.notifier).update((d) {
      final list = List<CommercialTeamProfile>.from(d.teams);
      list[index] = updated;
      return d.copyWith(teams: list);
    });
  }

  void _addFromSearch(CommercialTeamProfile team) {
    final draft = ref.read(commercialOnboardingProvider);
    if (draft.teams.any((t) => t.teamId == team.teamId && t.sport == team.sport)) return;
    final ranked = team.copyWith(priorityRank: draft.teams.length + 1);
    ref.read(commercialOnboardingProvider.notifier).update(
          (d) => d.copyWith(teams: [...d.teams, ranked]),
        );
    _searchCtrl.clear();
    setState(() {});
  }

  List<MapEntry<String, TeamColors>> _searchResults(String query) {
    if (query.length < 2) return [];
    final q = query.toLowerCase();
    return kTeamColors.entries.where((e) {
      final tc = e.value;
      return tc.teamName.toLowerCase().contains(q) ||
          e.key.toLowerCase().contains(q) ||
          tc.sport.displayName.toLowerCase().contains(q);
    }).take(8).toList();
  }

  bool get _showBrandColorToggle {
    final type = ref.read(commercialOnboardingProvider).businessType;
    return type == 'restaurant_fine_dining' || type == 'retail_boutique';
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(commercialOnboardingProvider);
    final teams = draft.teams;
    final query = _searchCtrl.text;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text('Your Teams',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: NexGenPalette.textHigh)),
        const SizedBox(height: 4),
        Text('Suggested based on your location',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13)),
        const SizedBox(height: 12),

        // Brand color toggle for fine dining / boutique
        if (_showBrandColorToggle) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: draft.useBrandColorsForAlerts,
            activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.4),
            thumbColor: const WidgetStatePropertyAll(NexGenPalette.cyan),
            onChanged: (v) => ref
                .read(commercialOnboardingProvider.notifier)
                .update((d) => d.copyWith(useBrandColorsForAlerts: v)),
            title: const Text(
              'Use brand colors for alert pulses instead of team colors',
              style: TextStyle(color: NexGenPalette.textHigh, fontSize: 14),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Search field
        TextField(
          controller: _searchCtrl,
          style: const TextStyle(color: NexGenPalette.textHigh),
          decoration: InputDecoration(
            hintText: 'Search by city, team, or sport...',
            hintStyle: const TextStyle(color: NexGenPalette.textMedium),
            prefixIcon: const Icon(Icons.search, color: NexGenPalette.textMedium),
            filled: true,
            fillColor: NexGenPalette.gunmetal90,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: NexGenPalette.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: NexGenPalette.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: NexGenPalette.cyan),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),

        // Search results
        if (query.length >= 2) ...[
          const SizedBox(height: 8),
          ..._searchResults(query).map((e) {
            final tc = e.value;
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tc.sport.sportEmoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  _ColorDot(tc.primary),
                  const SizedBox(width: 2),
                  _ColorDot(tc.secondary),
                ],
              ),
              title: Text(tc.teamName,
                  style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 14)),
              trailing: const Icon(Icons.add_circle_outline,
                  color: NexGenPalette.cyan, size: 20),
              onTap: () => _addFromSearch(CommercialTeamProfile(
                priorityRank: 0,
                teamId: tc.espnTeamId,
                teamName: tc.teamName,
                sport: tc.sport.name,
                primaryColor: tc.primary.toARGB32().toRadixString(16).substring(2),
                secondaryColor: tc.secondary.toARGB32().toRadixString(16).substring(2),
              )),
            );
          }),
        ],

        const SizedBox(height: 16),

        // Team list — reorderable
        if (teams.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: teams.length,
            onReorder: _reorder,
            itemBuilder: (context, i) {
              final team = teams[i];
              return _TeamCard(
                key: ValueKey('${team.teamId}_${team.sport}'),
                index: i,
                team: team,
                onRemove: () => _removeTeam(i),
                onUpdate: (t) => _updateTeam(i, t),
              );
            },
          ),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: widget.onNext,
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Next', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: widget.onNext,
            child: const Text('No sports alerts needed',
                style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13)),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Team card
// ---------------------------------------------------------------------------

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    super.key,
    required this.index,
    required this.team,
    required this.onRemove,
    required this.onUpdate,
  });
  final int index;
  final CommercialTeamProfile team;
  final VoidCallback onRemove;
  final ValueChanged<CommercialTeamProfile> onUpdate;

  String get _priorityLabel {
    if (index == 0) return '#1 Primary';
    if (index == 1) return '#2 Secondary';
    if (index == 2) return '#3 Tertiary';
    return '#${index + 1}';
  }

  Color get _priorityColor {
    if (index == 0) return NexGenPalette.cyan;
    if (index == 1) return NexGenPalette.violet;
    return NexGenPalette.textMedium;
  }

  @override
  Widget build(BuildContext context) {
    final primary = _parseHex(team.primaryColor);
    final secondary = _parseHex(team.secondaryColor);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.drag_handle, size: 18, color: NexGenPalette.textMedium),
              const SizedBox(width: 8),
              _ColorDot(primary),
              const SizedBox(width: 2),
              _ColorDot(secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(team.teamName,
                    style: const TextStyle(
                        color: NexGenPalette.textHigh, fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _priorityColor.withValues(alpha: 0.5)),
                ),
                child: Text(_priorityLabel,
                    style: TextStyle(color: _priorityColor, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close, size: 16, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Intensity selector
          Row(
            children: [
              const Text('Intensity: ', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
              ...AlertIntensity.values.map((v) {
                final isActive = team.alertIntensity == v;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(v.name[0].toUpperCase() + v.name.substring(1),
                        style: const TextStyle(fontSize: 11)),
                    selected: isActive,
                    selectedColor: NexGenPalette.cyan.withValues(alpha: 0.15),
                    backgroundColor: NexGenPalette.gunmetal,
                    labelStyle: TextStyle(
                      color: isActive ? NexGenPalette.cyan : NexGenPalette.textMedium),
                    side: BorderSide(
                      color: isActive ? NexGenPalette.cyan : NexGenPalette.line),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onUpdate(team.copyWith(alertIntensity: v)),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 6),
          // Channel scope
          Row(
            children: [
              const Text('Scope: ', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
              ...AlertChannelScope.values.map((v) {
                final isActive = team.alertChannelScope == v;
                final label = v == AlertChannelScope.allChannels
                    ? 'All'
                    : v == AlertChannelScope.indoorOnly
                        ? 'Indoor'
                        : 'Selected';
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 11)),
                    selected: isActive,
                    selectedColor: NexGenPalette.cyan.withValues(alpha: 0.15),
                    backgroundColor: NexGenPalette.gunmetal,
                    labelStyle: TextStyle(
                      color: isActive ? NexGenPalette.cyan : NexGenPalette.textMedium),
                    side: BorderSide(
                      color: isActive ? NexGenPalette.cyan : NexGenPalette.line),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onUpdate(team.copyWith(alertChannelScope: v)),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _ColorDot extends StatelessWidget {
  const _ColorDot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14, height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: NexGenPalette.line, width: 0.5),
      ),
    );
  }
}

Color _parseHex(String hex) {
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length == 6) {
    final v = int.tryParse('FF$cleaned', radix: 16);
    if (v != null) return Color(v);
  }
  return Colors.grey;
}
