import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wled/wled_models.dart';
import '../neighborhood_models.dart';
import '../neighborhood_providers.dart';
import '../neighborhood_sync_engine.dart';

/// Control panel for starting/stopping neighborhood sync and configuring timing.
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
  int _selectedEffectId = 28; // Chase
  int _selectedSpeed = 128;
  int _selectedIntensity = 128;
  int _selectedBrightness = 200;
  List<Color> _selectedColors = [const Color(0xFF00BCD4), const Color(0xFFFFFFFF)];
  SyncType _selectedSyncType = SyncType.sequentialFlow;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.group.isActive;
    final timingConfig = ref.watch(syncTimingConfigProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? Colors.cyan.withOpacity(0.5) : Colors.grey.shade800,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
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
                    color: Colors.cyan.withOpacity(0.2),
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
          ),
          const SizedBox(height: 16),

          if (!isActive) ...[
            // Sync type selector
            _buildSyncTypeSelector(),
            const SizedBox(height: 16),

            // Effect selector
            _buildEffectSelector(),
            const SizedBox(height: 16),

            // Color selector
            _buildColorSelector(),
            const SizedBox(height: 16),

            // Speed/Intensity sliders
            _buildParameterSliders(),
            const SizedBox(height: 16),

            // Timing configuration (only for Sequential Flow)
            if (_selectedSyncType == SyncType.sequentialFlow) ...[
              _buildTimingConfig(timingConfig),
              const SizedBox(height: 20),
            ],
          ],

          // Start/Stop button
          _buildActionButton(isActive),
        ],
      ),
    );
  }

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
                    color: isSelected ? Colors.cyan.withOpacity(0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(color: Colors.cyan.withOpacity(0.5))
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

  Widget _buildEffectSelector() {
    // Common chase/flow effects good for neighborhood sync
    final syncEffects = <int, String>{
      28: 'Chase',
      77: 'Meteor',
      3: 'Wipe',
      15: 'Running',
      80: 'Ripple',
      106: 'Flow',
      10: 'Scan',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Effect',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: syncEffects.entries.map((entry) {
            final isSelected = _selectedEffectId == entry.key;
            return ChoiceChip(
              label: Text(entry.value),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedEffectId = entry.key);
                }
              },
              selectedColor: Colors.cyan.withOpacity(0.3),
              backgroundColor: Colors.grey.shade800,
              labelStyle: TextStyle(
                color: isSelected ? Colors.cyan : Colors.grey.shade400,
              ),
              side: BorderSide(
                color: isSelected ? Colors.cyan : Colors.grey.shade700,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildColorSelector() {
    final presetColors = <List<Color>>[
      [const Color(0xFF00BCD4), const Color(0xFFFFFFFF)], // Cyan + White
      [const Color(0xFFF44336), const Color(0xFF4CAF50)], // Red + Green
      [const Color(0xFF9C27B0), const Color(0xFFE91E63)], // Purple + Pink
      [const Color(0xFFFF9800), const Color(0xFFFFEB3B)], // Orange + Yellow
      [const Color(0xFF2196F3), const Color(0xFF00BCD4)], // Blue + Cyan
      [const Color(0xFFFF0000), const Color(0xFFFFD700)], // Chiefs
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Colors',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presetColors.asMap().entries.map((entry) {
            final colors = entry.value;
            final isSelected = _colorsMatch(colors, _selectedColors);

            return GestureDetector(
              onTap: () => setState(() => _selectedColors = List<Color>.from(colors)),
              child: Container(
                width: 48,
                height: 28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                    width: isSelected ? 2 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  bool _colorsMatch(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value) return false;
    }
    return true;
  }

  Widget _buildParameterSliders() {
    return Column(
      children: [
        // Speed slider
        Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(
                'Speed',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Slider(
                value: _selectedSpeed.toDouble(),
                min: 0,
                max: 255,
                activeColor: Colors.cyan,
                inactiveColor: Colors.grey.shade800,
                onChanged: (v) => setState(() => _selectedSpeed = v.round()),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$_selectedSpeed',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                ),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),

        // Intensity slider
        Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(
                'Intensity',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Slider(
                value: _selectedIntensity.toDouble(),
                min: 0,
                max: 255,
                activeColor: Colors.cyan,
                inactiveColor: Colors.grey.shade800,
                onChanged: (v) => setState(() => _selectedIntensity = v.round()),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$_selectedIntensity',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                ),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),

        // Brightness slider
        Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(
                'Brightness',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Slider(
                value: _selectedBrightness.toDouble(),
                min: 0,
                max: 255,
                activeColor: Colors.cyan,
                inactiveColor: Colors.grey.shade800,
                onChanged: (v) => setState(() => _selectedBrightness = v.round()),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$_selectedBrightness',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                ),
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ],
    );
  }

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
              // Pixels per second
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      'Animation Speed',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
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
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),

              // Gap delay
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      'Gap Delay',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
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
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),

              // Direction toggle
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      'Direction',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.arrow_forward, size: 16),
                        label: Text('L→R'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.arrow_back, size: 16),
                        label: Text('R→L'),
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
                          return Colors.cyan.withOpacity(0.2);
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

  Widget _buildActionButton(bool isActive) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: isActive ? _stopSync : _startSync,
        icon: Icon(isActive ? Icons.stop : Icons.play_arrow),
        label: Text(isActive ? 'Stop Neighborhood Sync' : 'Start Neighborhood Sync'),
        style: ElevatedButton.styleFrom(
          backgroundColor: isActive ? Colors.red.shade700 : Colors.cyan,
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

    // Create sync command
    final command = engine.createSyncCommand(
      groupId: widget.group.id,
      members: widget.members,
      effectId: _selectedEffectId,
      colors: _selectedColors.map((c) => c.value).toList(),
      speed: _selectedSpeed,
      intensity: _selectedIntensity,
      brightness: _selectedBrightness,
      timingConfig: timingConfig,
      syncType: _selectedSyncType,
      patternName: kEffectNames[_selectedEffectId] ?? 'Effect #$_selectedEffectId',
    );

    // Broadcast to all members
    ref.read(neighborhoodNotifierProvider.notifier).broadcastSync(command);

    // Start listening for commands
    ref.read(syncEngineActiveProvider.notifier).state = true;
  }

  void _stopSync() {
    ref.read(neighborhoodNotifierProvider.notifier).stopSync();
    ref.read(syncEngineActiveProvider.notifier).state = false;
  }
}
