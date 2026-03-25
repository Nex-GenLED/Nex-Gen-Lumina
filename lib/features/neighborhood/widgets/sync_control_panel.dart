import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wled/library_hierarchy_models.dart';
import '../../wled/pattern_providers.dart';
import '../../wled/wled_models.dart';
import '../neighborhood_models.dart';
import '../neighborhood_providers.dart';
import '../neighborhood_sync_engine.dart';
import '../services/group_autopilot_service.dart';
import 'game_day_setup_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// FEATURED PATTERNS — Curated quick-picks for the horizontal strip
// ═══════════════════════════════════════════════════════════════════════════════

/// Popular effect + color combos well-suited for roofline neighborhood syncs.
/// Not a hard cap — the full Explore Patterns library is always 1 tap away.
const _kFeaturedPatterns = <SyncPatternAssignment>[
  SyncPatternAssignment(name: 'Cyan Chase', effectId: 28, colors: [0x00BCD4, 0xFFFFFF], speed: 128, intensity: 128, brightness: 200),
  SyncPatternAssignment(name: 'Warm Meteor', effectId: 77, colors: [0xFF9800, 0xFFEB3B], speed: 140, intensity: 128, brightness: 200),
  SyncPatternAssignment(name: 'Ocean Flow', effectId: 106, colors: [0x2196F3, 0x00BCD4], speed: 100, intensity: 180, brightness: 200),
  SyncPatternAssignment(name: 'Crimson Wipe', effectId: 3, colors: [0xF44336, 0xFFFFFF], speed: 128, intensity: 128, brightness: 200),
  SyncPatternAssignment(name: 'Purple Pulse', effectId: 2, colors: [0x9C27B0, 0xE91E63], speed: 90, intensity: 200, brightness: 200),
  SyncPatternAssignment(name: 'Running Lights', effectId: 15, colors: [0x00E5FF, 0x6E2FFF], speed: 128, intensity: 128, brightness: 200),
  SyncPatternAssignment(name: 'Emerald Ripple', effectId: 80, colors: [0x4CAF50, 0x2196F3], speed: 128, intensity: 128, brightness: 200),
  SyncPatternAssignment(name: 'Fire Scan', effectId: 10, colors: [0xFF0000, 0xFFD700], speed: 160, intensity: 128, brightness: 200),
  SyncPatternAssignment(name: 'Solid White', effectId: 0, colors: [0xFFFFFF], speed: 128, intensity: 128, brightness: 255),
  SyncPatternAssignment(name: 'Warm White', effectId: 0, colors: [0xFFD4A0], speed: 128, intensity: 128, brightness: 200),
  SyncPatternAssignment(name: 'Rainbow Chase', effectId: 28, colors: [0xFF0000, 0x00FF00, 0x0000FF], speed: 128, intensity: 128, brightness: 200),
  SyncPatternAssignment(name: 'Soft Breathe', effectId: 2, colors: [0x00BCD4], speed: 60, intensity: 255, brightness: 180),
  SyncPatternAssignment(name: 'Candy Wipe', effectId: 3, colors: [0xFF69B4, 0xFFFFFF], speed: 128, intensity: 128, brightness: 200),
  SyncPatternAssignment(name: 'Electric Storm', effectId: 80, colors: [0x6E2FFF, 0x00E5FF], speed: 200, intensity: 200, brightness: 220),
  SyncPatternAssignment(name: 'Gold Scan', effectId: 10, colors: [0xFFD700, 0xFFFFFF], speed: 120, intensity: 128, brightness: 200),
  SyncPatternAssignment(name: 'Sunset Flow', effectId: 106, colors: [0xFF5722, 0xFFEB3B], speed: 80, intensity: 160, brightness: 200),
];

// ═══════════════════════════════════════════════════════════════════════════════
// SYNC CONTROL PANEL — Unified Setup Flow
// ═══════════════════════════════════════════════════════════════════════════════

/// Control panel for starting/stopping neighborhood sync and configuring timing.
///
/// Unified setup flow (no mode switching):
///   - "For Everyone" section with featured patterns + full library access
///   - "Customize Per House" expandable section for per-house assignments
///   - Complement Mode with Game Day integration (separate section)
class SyncControlPanel extends ConsumerStatefulWidget {
  final List<NeighborhoodMember> members;
  final NeighborhoodGroup group;

  const SyncControlPanel({
    super.key,
    required this.members,
    required this.group,
  });

  @override
  ConsumerState<SyncControlPanel> createState() => _SyncControlPanelState();
}

class _SyncControlPanelState extends ConsumerState<SyncControlPanel> {
  // ── Global "For Everyone" selection ────────────────────────────────────
  SyncPatternAssignment? _globalPattern;
  int _selectedSpeed = 128;
  int _selectedIntensity = 128;
  int _selectedBrightness = 200;

  // ── Sync config ────────────────────────────────────────────────────────
  SyncType _selectedSyncType = SyncType.sequentialFlow;
  ComplementTheme _selectedComplementTheme = ComplementThemes.july4th;

  // ── Game Day ───────────────────────────────────────────────────────────
  GameDaySyncConfig? _gameDayConfig;

  // ── Per-house customization ────────────────────────────────────────────
  bool _perHouseExpanded = false;
  final Map<String, SyncPatternAssignment> _perHouseAssignments = {};

  @override
  Widget build(BuildContext context) {
    final isActive = widget.group.isActive;
    final timingConfig = ref.watch(syncTimingConfigProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? Colors.cyan.withValues(alpha: 0.5) : Colors.grey.shade800,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isActive),
          const SizedBox(height: 16),

          if (!isActive) ...[
            _buildSyncTypeSelector(),
            const SizedBox(height: 16),

            if (_selectedSyncType == SyncType.complement)
              _buildComplementContent()
            else
              _buildUnifiedContent(timingConfig),
          ],

          _buildActionButton(isActive),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeader(bool isActive) {
    return Row(
      children: [
        Icon(
          isActive ? Icons.sync : Icons.sync_disabled,
          color: isActive ? Colors.cyan : Colors.grey,
        ),
        const SizedBox(width: 8),
        Text(
          isActive ? 'Sync Active' : 'Sync Controls',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.cyan,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.group.activePatternName ?? 'Running',
                  style: const TextStyle(
                    color: Colors.cyan,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC TYPE SELECTOR
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSyncTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sync Mode',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: SyncType.values.map((syncType) {
              final isSelected = _selectedSyncType == syncType;
              return InkWell(
                onTap: () => setState(() => _selectedSyncType = syncType),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.cyan.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(color: Colors.cyan.withValues(alpha: 0.5))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        syncType.icon,
                        color: isSelected ? Colors.cyan : Colors.grey.shade500,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              syncType.displayName,
                              style: TextStyle(
                                color: isSelected ? Colors.cyan : Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              syncType.description,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle, color: Colors.cyan, size: 18),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UNIFIED CONTENT — "For Everyone" + Per-House + Sliders + Timing
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildUnifiedContent(SyncTimingConfig timingConfig) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildForEveryoneSection(),
        const SizedBox(height: 16),
        _buildParameterSliders(),
        const SizedBox(height: 16),
        _buildPerHouseSection(),
        const SizedBox(height: 16),
        if (_selectedSyncType == SyncType.sequentialFlow) ...[
          _buildTimingConfig(timingConfig),
          const SizedBox(height: 20),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // "For Everyone" — Featured strip + Browse All
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildForEveryoneSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            const Icon(Icons.groups, color: Colors.cyan, size: 18),
            const SizedBox(width: 8),
            Text(
              'For Everyone',
              style: TextStyle(
                color: Colors.grey.shade300,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Current selection (from library browse)
        if (_globalPattern != null && !_isFeaturedPattern(_globalPattern!))
          _buildLibrarySelectionCard(),

        // "Popular" label
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Popular',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        // Featured horizontal strip
        _buildFeaturedStrip(),
        const SizedBox(height: 12),

        // Browse All button
        _buildBrowseAllButton(),
      ],
    );
  }

  bool _isFeaturedPattern(SyncPatternAssignment pattern) {
    return _kFeaturedPatterns.any((f) =>
        f.name == pattern.name &&
        f.effectId == pattern.effectId);
  }

  Widget _buildLibrarySelectionCard() {
    final pattern = _globalPattern!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.cyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.cyan.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            _PatternColorPreview(colors: pattern.colorObjects),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pattern.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    kEffectNames[pattern.effectId] ?? 'Effect #${pattern.effectId}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.check_circle, color: Colors.cyan, size: 18),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() => _globalPattern = null),
              child: Icon(Icons.close, color: Colors.grey.shade500, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedStrip() {
    return SizedBox(
      height: 88,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _kFeaturedPatterns.length,
        itemBuilder: (ctx, i) {
          final pattern = _kFeaturedPatterns[i];
          final isSelected = _globalPattern != null &&
              _globalPattern!.name == pattern.name &&
              _globalPattern!.effectId == pattern.effectId;
          return _FeaturedPatternCard(
            pattern: pattern,
            isSelected: isSelected,
            onTap: () => setState(() {
              _globalPattern = pattern;
              _selectedSpeed = pattern.speed;
              _selectedIntensity = pattern.intensity;
              _selectedBrightness = pattern.brightness;
            }),
          );
        },
      ),
    );
  }

  Widget _buildBrowseAllButton() {
    return InkWell(
      onTap: () => _openPatternPicker(onSelected: (assignment) {
        setState(() {
          _globalPattern = assignment;
          _selectedSpeed = assignment.speed;
          _selectedIntensity = assignment.intensity;
          _selectedBrightness = assignment.brightness;
        });
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade700),
        ),
        child: Row(
          children: [
            Icon(Icons.palette_outlined, color: Colors.grey.shade400, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Browse All Patterns',
                style: TextStyle(color: Colors.grey.shade300, fontSize: 14),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 20),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Parameter sliders
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildParameterSliders() {
    return Column(
      children: [
        _SliderRow(
          label: 'Speed',
          value: _selectedSpeed,
          onChanged: (v) => setState(() => _selectedSpeed = v),
        ),
        _SliderRow(
          label: 'Intensity',
          value: _selectedIntensity,
          onChanged: (v) => setState(() => _selectedIntensity = v),
        ),
        _SliderRow(
          label: 'Brightness',
          value: _selectedBrightness,
          onChanged: (v) => setState(() => _selectedBrightness = v),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // "Customize Per House" — Expandable section
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPerHouseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _perHouseExpanded = !_perHouseExpanded),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _perHouseExpanded ? Colors.cyan.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _perHouseExpanded ? Colors.cyan.withValues(alpha: 0.3) : Colors.grey.shade800,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.home_work_outlined,
                  color: _perHouseExpanded ? Colors.cyan : Colors.grey.shade500,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Customize Per House',
                        style: TextStyle(
                          color: _perHouseExpanded ? Colors.cyan : Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        _perHouseAssignments.isEmpty
                            ? 'Give each home its own pattern'
                            : '${_perHouseAssignments.length} custom assignment${_perHouseAssignments.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _perHouseExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more,
                    color: _perHouseExpanded ? Colors.cyan : Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded per-house content
        if (_perHouseExpanded) ...[
          const SizedBox(height: 12),
          _buildPerHouseAssignments(),
        ],
      ],
    );
  }

  Widget _buildPerHouseAssignments() {
    final sortedMembers = List<NeighborhoodMember>.from(widget.members)
      ..sort((a, b) => a.positionIndex.compareTo(b.positionIndex));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.home, color: Colors.cyan.shade300, size: 16),
            const SizedBox(width: 6),
            Text(
              'House Assignments',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            if (_perHouseAssignments.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(() => _perHouseAssignments.clear()),
                icon: const Icon(Icons.clear_all, size: 14),
                label: const Text('Reset All', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade500,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: Column(
            children: sortedMembers.asMap().entries.map((entry) {
              final index = entry.key;
              final member = entry.value;
              final assignment = _perHouseAssignments[member.oderId];
              final hasOverride = assignment != null;

              return Column(
                children: [
                  if (index > 0)
                    Divider(color: Colors.grey.shade800, height: 1),
                  _PerHouseRow(
                    member: member,
                    positionIndex: index,
                    assignment: assignment,
                    globalPattern: _globalPattern,
                    onTap: () => _openPatternPicker(
                      memberName: member.displayName,
                      onSelected: (a) {
                        setState(() => _perHouseAssignments[member.oderId] = a);
                      },
                    ),
                    onClear: hasOverride
                        ? () => setState(() => _perHouseAssignments.remove(member.oderId))
                        : null,
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _perHouseAssignments.isEmpty
              ? 'Tap a house to assign a unique pattern. Unassigned houses use the selection above.'
              : '${_perHouseAssignments.length} of ${sortedMembers.length} houses have custom assignments',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 11,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pattern Picker (full library browser)
  // ─────────────────────────────────────────────────────────────────────────

  void _openPatternPicker({
    String? memberName,
    required ValueChanged<SyncPatternAssignment> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PatternPickerSheet(
        title: memberName != null ? 'Choose for $memberName' : 'Choose Pattern',
        onSelected: (assignment) {
          onSelected(assignment);
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Timing configuration
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTimingConfig(SyncTimingConfig config) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Timing Configuration',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      'Animation Speed',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: config.pixelsPerSecond,
                      min: 10,
                      max: 200,
                      activeColor: Colors.cyan,
                      inactiveColor: Colors.grey.shade800,
                      onChanged: (v) {
                        ref.read(syncTimingConfigProvider.notifier).state =
                            config.copyWith(pixelsPerSecond: v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${config.pixelsPerSecond.round()} px/s',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      'Gap Delay',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: config.gapDelayMs,
                      min: 0,
                      max: 1000,
                      activeColor: Colors.cyan,
                      inactiveColor: Colors.grey.shade800,
                      onChanged: (v) {
                        ref.read(syncTimingConfigProvider.notifier).state =
                            config.copyWith(gapDelayMs: v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${config.gapDelayMs.round()} ms',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      'Direction',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.arrow_forward, size: 16),
                        label: Text('L\u2192R'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.arrow_back, size: 16),
                        label: Text('R\u2192L'),
                      ),
                    ],
                    selected: {config.reverseDirection},
                    onSelectionChanged: (selected) {
                      ref.read(syncTimingConfigProvider.notifier).state =
                          config.copyWith(reverseDirection: selected.first);
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.cyan.withValues(alpha: 0.2);
                        }
                        return Colors.grey.shade800;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.cyan;
                        }
                        return Colors.grey.shade500;
                      }),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPLEMENT MODE CONTENT (with Game Day)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildComplementContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildComplementThemeSelector(),
        const SizedBox(height: 16),
        _buildComplementPreview(),
        const SizedBox(height: 16),
        _buildParameterSliders(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildComplementThemeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Complement Theme',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: ComplementThemes.all.map((theme) {
              final isGameDay = theme.id == 'gameday';
              final isSelected = isGameDay
                  ? _gameDayConfig != null && _selectedComplementTheme.id == 'gameday'
                  : _selectedComplementTheme.id == theme.id && _gameDayConfig == null;
              final displayTheme = (isGameDay && _gameDayConfig != null)
                  ? _gameDayConfig!.toComplementTheme()
                  : theme;
              return InkWell(
                onTap: () async {
                  if (isGameDay) {
                    final currentMember = ref.read(currentUserMemberProvider);
                    final isHost = currentMember != null &&
                        currentMember.oderId == widget.group.creatorUid;
                    final result = await showGameDaySetupFull(context, isHost: isHost);
                    if (result.config != null && mounted) {
                      setState(() {
                        _gameDayConfig = result.config;
                        _selectedComplementTheme = result.config!.toComplementTheme();
                      });
                    }
                  } else {
                    setState(() {
                      _gameDayConfig = null;
                      _selectedComplementTheme = theme;
                    });
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.cyan.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(color: Colors.cyan.withValues(alpha: 0.5))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        displayTheme.icon,
                        color: isSelected ? Colors.cyan : Colors.grey.shade500,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayTheme.name,
                              style: TextStyle(
                                color: isSelected ? Colors.cyan : Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              displayTheme.description,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isGameDay && _gameDayConfig == null)
                        Text(
                          'Set up',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: displayTheme.colorObjects.take(4).map((color) {
                            return Container(
                              width: 16,
                              height: 16,
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      const SizedBox(width: 8),
                      if (isSelected)
                        const Icon(Icons.check_circle, color: Colors.cyan, size: 18)
                      else if (isGameDay)
                        Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 18),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildComplementPreview() {
    final sortedMembers = List<NeighborhoodMember>.from(widget.members)
      ..sort((a, b) => a.positionIndex.compareTo(b.positionIndex));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.palette, color: Colors.cyan.shade300, size: 16),
            const SizedBox(width: 6),
            Text(
              'Color Assignment Preview',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: Column(
            children: sortedMembers.asMap().entries.map((entry) {
              final index = entry.key;
              final member = entry.value;
              final color = Color(_selectedComplementTheme.getColorForIndex(index) | 0xFF000000);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        member.displayName,
                        style: TextStyle(
                          color: Colors.grey.shade300,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '#${index + 1}',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tip: Reorder homes in the Members section to change color assignments',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 11,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION BUTTON + SYNC LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionButton(bool isActive) {
    // Can always start complement mode; for standard mode need a pattern or per-house assignments
    final bool canStart = isActive ||
        _selectedSyncType == SyncType.complement ||
        _globalPattern != null ||
        _perHouseAssignments.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isActive
            ? _stopSync
            : (canStart ? _startSync : null),
        icon: Icon(isActive ? Icons.stop : Icons.play_arrow),
        label: Text(isActive ? 'Stop Neighborhood Sync' : 'Start Neighborhood Sync'),
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive
              ? Colors.red.shade700
              : (canStart ? Colors.cyan : Colors.grey.shade700),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  void _startSync() {
    final timingConfig = ref.read(syncTimingConfigProvider);
    final engine = ref.read(neighborhoodSyncEngineProvider);

    SyncCommand command;

    if (_selectedSyncType == SyncType.complement) {
      // Complement mode: use theme + optional Game Day overrides
      final effectOverride = _gameDayConfig?.effectId ?? 0;
      final speed = _gameDayConfig?.speed ?? _selectedSpeed;
      final intensity = _gameDayConfig?.intensity ?? _selectedIntensity;
      final brightness = _gameDayConfig?.brightness ?? _selectedBrightness;

      command = engine.createComplementCommand(
        groupId: widget.group.id,
        members: widget.members,
        theme: _selectedComplementTheme,
        effectIdOverride: effectOverride,
        speed: speed,
        intensity: intensity,
        brightness: brightness,
      );
    } else {
      // Unified mode: use global pattern + optional per-house overrides
      final global = _globalPattern ??
          const SyncPatternAssignment(
            name: 'Solid White',
            effectId: 0,
            colors: [0xFFFFFF],
          );

      command = engine.createSyncCommand(
        groupId: widget.group.id,
        members: widget.members,
        effectId: global.effectId,
        colors: global.colors,
        speed: _selectedSpeed,
        intensity: _selectedIntensity,
        brightness: _selectedBrightness,
        timingConfig: timingConfig,
        syncType: _selectedSyncType,
        patternName: global.name,
      );

      // Attach per-house overrides if any
      if (_perHouseAssignments.isNotEmpty) {
        command = SyncCommand(
          id: command.id,
          groupId: command.groupId,
          effectId: command.effectId,
          colors: command.colors,
          speed: command.speed,
          intensity: command.intensity,
          brightness: command.brightness,
          startTimestamp: command.startTimestamp,
          memberDelays: command.memberDelays,
          timingConfig: command.timingConfig,
          syncType: command.syncType,
          patternName: command.patternName,
          scheduleId: command.scheduleId,
          memberColorOverrides: command.memberColorOverrides,
          complementTheme: command.complementTheme,
          memberPatternOverrides: Map<String, SyncPatternAssignment>.from(_perHouseAssignments),
        );
      }
    }

    ref.read(neighborhoodNotifierProvider.notifier).broadcastSync(command);
    ref.read(syncEngineActiveProvider.notifier).state = true;
  }

  void _stopSync() {
    ref.read(neighborhoodNotifierProvider.notifier).stopSync();
    ref.read(syncEngineActiveProvider.notifier).state = false;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

/// Featured pattern card for the horizontal strip.
class _FeaturedPatternCard extends StatelessWidget {
  final SyncPatternAssignment pattern;
  final bool isSelected;
  final VoidCallback onTap;

  const _FeaturedPatternCard({
    required this.pattern,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = pattern.colorObjects;
    final effectName = kEffectNames[pattern.effectId] ?? '';

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 110,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors.isEmpty
                  ? [Colors.grey.shade700, Colors.grey.shade800]
                  : [
                      colors.first.withValues(alpha: isSelected ? 0.5 : 0.3),
                      (colors.length > 1 ? colors.last : colors.first)
                          .withValues(alpha: isSelected ? 0.3 : 0.15),
                    ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.cyan : Colors.grey.shade700,
              width: isSelected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Color bar
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors.isEmpty ? [Colors.grey] : colors,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Spacer(),
              // Pattern name
              Text(
                pattern.name,
                style: TextStyle(
                  color: isSelected ? Colors.cyan : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (effectName.isNotEmpty)
                Text(
                  effectName,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (isSelected)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_circle, color: Colors.cyan, size: 14),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slider row for parameter adjustment.
class _SliderRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            activeColor: Colors.cyan,
            inactiveColor: Colors.grey.shade800,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

/// Color swatch preview for pattern assignments.
class _PatternColorPreview extends StatelessWidget {
  final List<Color> colors;

  const _PatternColorPreview({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 24,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors.isEmpty ? [Colors.grey] : colors,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
    );
  }
}

/// Per-house assignment row showing member info and current pattern.
class _PerHouseRow extends StatelessWidget {
  final NeighborhoodMember member;
  final int positionIndex;
  final SyncPatternAssignment? assignment;
  final SyncPatternAssignment? globalPattern;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _PerHouseRow({
    required this.member,
    required this.positionIndex,
    required this.assignment,
    required this.globalPattern,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final display = assignment ?? globalPattern;
    final hasOverride = assignment != null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Position badge
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: hasOverride ? Colors.cyan.withValues(alpha: 0.2) : Colors.grey.shade800,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                '#${positionIndex + 1}',
                style: TextStyle(
                  color: hasOverride ? Colors.cyan : Colors.grey.shade400,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // House name & pattern info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.displayName,
                    style: TextStyle(
                      color: Colors.grey.shade200,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (display != null)
                    Row(
                      children: [
                        _PatternColorPreview(colors: display.colorObjects),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            hasOverride ? display.name : '${display.name} (default)',
                            style: TextStyle(
                              color: hasOverride ? Colors.cyan.shade300 : Colors.grey.shade500,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'No pattern selected',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                    ),
                ],
              ),
            ),
            // Clear button (if has override)
            if (onClear != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close, size: 16),
                color: Colors.grey.shade500,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Reset to default',
              ),
            Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 20),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// GROUP AUTOPILOT — Member opt-in/out card for Sync Control Center
// ═════════════════════════════════════════════════════════════════════════════

/// Displays the Group Autopilot opt-in/opt-out toggle for each member's
/// home card in the host's Sync Control Center.
///
/// Opted-out members show a muted/grey state. Only the member themselves
/// can toggle back in — the host cannot force opt a member back in.
class GroupAutopilotMemberCard extends ConsumerWidget {
  final NeighborhoodMember member;
  final bool isCurrentUser;
  final String groupId;

  const GroupAutopilotMemberCard({
    super.key,
    required this.member,
    required this.isCurrentUser,
    required this.groupId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optInAsync = ref.watch(_memberOptInFamily(member.oderId));
    final isOptedIn = optInAsync.valueOrNull ?? true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isOptedIn
            ? Colors.grey.shade900.withValues(alpha: 0.5)
            : Colors.grey.shade900.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOptedIn
              ? Colors.cyan.withValues(alpha: 0.3)
              : Colors.grey.shade800.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Status indicator dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOptedIn ? Colors.cyan : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 10),
          // Member name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName,
                  style: TextStyle(
                    color: isOptedIn
                        ? Colors.grey.shade200
                        : Colors.grey.shade500,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isOptedIn ? 'Opted in' : 'Opted out',
                  style: TextStyle(
                    color: isOptedIn
                        ? Colors.cyan.shade300
                        : Colors.grey.shade600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Toggle — only enabled for the current user
          if (isCurrentUser)
            SizedBox(
              height: 28,
              child: Switch.adaptive(
                value: isOptedIn,
                onChanged: (value) async {
                  final service = ref.read(_groupAutopilotServiceProvider);
                  await service.setOptIn(groupId, value);
                  ref.invalidate(_memberOptInFamily(member.oderId));
                },
                activeTrackColor: Colors.cyan.withValues(alpha: 0.5),
                activeThumbColor: Colors.cyan,
                inactiveTrackColor: Colors.grey.shade700,
              ),
            )
          else
            // For non-current users (host view), show status label
            Text(
              isOptedIn ? 'Group Autopilot' : 'Excluded',
              style: TextStyle(
                color: isOptedIn
                    ? Colors.cyan.withValues(alpha: 0.7)
                    : Colors.grey.shade600,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

/// Family provider: opt-in status per member for the active group.
final _memberOptInFamily =
    FutureProvider.family<bool, String>((ref, userId) async {
  final groupId = ref.watch(activeNeighborhoodIdProvider);
  if (groupId == null) return true;
  final service = ref.watch(_groupAutopilotServiceProvider);
  return service.getMemberOptIn(groupId, userId);
});

final _groupAutopilotServiceProvider =
    Provider<_GroupAutopilotServiceLazy>((ref) {
  return _GroupAutopilotServiceLazy();
});

/// Lazy import wrapper to avoid circular deps — delegates to the real service.
class _GroupAutopilotServiceLazy {
  late final _inner = GroupAutopilotService();

  Future<bool> getMemberOptIn(String groupId, String userId) =>
      _inner.getMemberOptIn(groupId, userId);

  Future<void> setOptIn(String groupId, bool optIn) =>
      _inner.setOptIn(groupId, optIn);
}

// ═════════════════════════════════════════════════════════════════════════════
// PATTERN PICKER BOTTOM SHEET — Reuses Explore Patterns library hierarchy
// ═════════════════════════════════════════════════════════════════════════════

/// Full-screen-ish bottom sheet that lets the user browse the Explore Patterns
/// library hierarchy (categories → folders → palettes) and pick one for sync.
class _PatternPickerSheet extends ConsumerStatefulWidget {
  final String title;
  final ValueChanged<SyncPatternAssignment> onSelected;

  const _PatternPickerSheet({
    required this.title,
    required this.onSelected,
  });

  @override
  ConsumerState<_PatternPickerSheet> createState() => _PatternPickerSheetState();
}

class _PatternPickerSheetState extends ConsumerState<_PatternPickerSheet> {
  /// Navigation stack: list of (parentId, title) pairs. null = root.
  final List<_NavEntry> _navStack = [_NavEntry(null, 'Design Library')];

  /// If a palette is selected for effect picking.
  LibraryNode? _selectedPalette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header with back button and title
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                if (_navStack.length > 1 || _selectedPalette != null)
                  IconButton(
                    onPressed: _goBack,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  )
                else
                  const SizedBox(width: 48),
                Expanded(
                  child: Text(
                    _selectedPalette?.name ?? _navStack.last.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
          ),
          // Breadcrumb
          if (_navStack.length > 1 && _selectedPalette == null)
            _buildBreadcrumb(),
          const Divider(color: Colors.grey, height: 1),
          // Content
          Expanded(
            child: _selectedPalette != null
                ? _buildEffectPicker(_selectedPalette!)
                : _buildNodeBrowser(),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: _navStack.asMap().entries.map((entry) {
          final index = entry.key;
          final nav = entry.value;
          final isLast = index == _navStack.length - 1;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 14),
                ),
              GestureDetector(
                onTap: isLast
                    ? null
                    : () => setState(() {
                          _navStack.removeRange(index + 1, _navStack.length);
                        }),
                child: Text(
                  nav.title,
                  style: TextStyle(
                    color: isLast ? Colors.cyan : Colors.grey.shade500,
                    fontSize: 11,
                    fontWeight: isLast ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildNodeBrowser() {
    final parentId = _navStack.last.parentId;
    final childrenAsync = ref.watch(libraryChildNodesProvider(parentId));

    return childrenAsync.when(
      data: (children) {
        if (children.isEmpty) {
          return Center(
            child: Text(
              'No items found',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          );
        }

        final allPalettes = children.every((n) => n.isPalette);

        if (allPalettes) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: children.length,
            itemBuilder: (context, index) {
              final node = children[index];
              return _PalettePickerCard(
                node: node,
                onTap: () => setState(() => _selectedPalette = node),
              );
            },
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.3,
          ),
          itemCount: children.length,
          itemBuilder: (context, index) {
            final node = children[index];
            return _FolderPickerCard(
              node: node,
              onTap: () {
                if (node.isPalette) {
                  setState(() => _selectedPalette = node);
                } else {
                  setState(() {
                    _navStack.add(_NavEntry(node.id, node.name));
                  });
                }
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.cyan)),
      error: (e, _) => Center(
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  Widget _buildEffectPicker(LibraryNode palette) {
    final colors = palette.themeColors ?? [Colors.white];
    final suggestedEffects = palette.suggestedEffects;
    final syncEffects = <int>{...suggestedEffects, 0, 28, 77, 3, 15, 80, 106, 10, 2};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Choose an Effect',
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        ...syncEffects.map((effectId) {
          final name = kEffectNames[effectId] ?? 'Effect #$effectId';
          final isSuggested = suggestedEffects.contains(effectId);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () {
                final assignment = SyncPatternAssignment.fromLibraryNode(
                  name: '${palette.name} - $name',
                  themeColors: colors,
                  effectId: effectId,
                  speed: palette.defaultSpeed,
                  intensity: palette.defaultIntensity,
                );
                widget.onSelected(assignment);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 20,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: colors),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isSuggested)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.cyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Suggested',
                          style: TextStyle(color: Colors.cyan, fontSize: 9),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Icon(Icons.play_arrow, color: Colors.grey.shade500, size: 18),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  void _goBack() {
    if (_selectedPalette != null) {
      setState(() => _selectedPalette = null);
    } else if (_navStack.length > 1) {
      setState(() => _navStack.removeLast());
    }
  }
}

class _NavEntry {
  final String? parentId;
  final String title;
  const _NavEntry(this.parentId, this.title);
}

/// Card for a palette node inside the picker.
class _PalettePickerCard extends StatelessWidget {
  final LibraryNode node;
  final VoidCallback onTap;

  const _PalettePickerCard({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = node.themeColors ?? [Colors.grey];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (node.description != null)
                      Text(
                        node.description!,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade600, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card for a folder/category node inside the picker.
class _FolderPickerCard extends StatelessWidget {
  final LibraryNode node;
  final VoidCallback onTap;

  const _FolderPickerCard({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = node.previewColors ?? node.themeColors ?? [Colors.grey.shade700, Colors.grey.shade800];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.first.withValues(alpha: 0.3),
              colors.last.withValues(alpha: 0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade800),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (node.isPalette)
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            const Spacer(),
            Text(
              node.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (node.description != null) ...[
              const SizedBox(height: 2),
              Text(
                node.description!,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
