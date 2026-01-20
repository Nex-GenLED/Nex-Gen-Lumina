import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/lumina_design_assistant.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/segment_pattern_generator.dart';
import 'package:nexgen_command/features/design/widgets/led_strip_canvas.dart';
import 'package:nexgen_command/features/design/widgets/color_palette_picker.dart';
import 'package:nexgen_command/features/design/widgets/effect_selector.dart';
import 'package:nexgen_command/features/design/widgets/segment_led_canvas.dart';
import 'package:nexgen_command/features/design/widgets/pattern_template_selector.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/segment_aware_pattern.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/app_providers.dart';

/// Provider for tracking the current design mode (channel vs segment).
final designModeProvider = StateProvider<DesignMode>((ref) => DesignMode.channel);

/// Design mode enum.
enum DesignMode {
  channel,  // Traditional channel-based design
  segment,  // Segment-aware pattern design
}

/// Main Design Studio screen for creating custom lighting designs.
class DesignStudioScreen extends ConsumerStatefulWidget {
  /// Optional design ID to load for editing
  final String? designId;

  const DesignStudioScreen({super.key, this.designId});

  @override
  ConsumerState<DesignStudioScreen> createState() => _DesignStudioScreenState();
}

class _DesignStudioScreenState extends ConsumerState<DesignStudioScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isApplying = false;

  // Segment mode state
  List<LedColorGroup>? _generatedPattern;
  SegmentAwarePattern? _activePattern;

  @override
  void initState() {
    super.initState();
    // Defer initialization to after the widget tree is built to avoid
    // "Tried to modify a provider while the widget tree was building" error
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeDesign();
    });
  }

  Future<void> _initializeDesign() async {
    if (widget.designId != null) {
      // TODO: Load existing design by ID
      // For now, create new
      await ref.read(currentDesignProvider.notifier).createNew();
    } else {
      await ref.read(currentDesignProvider.notifier).createNew();
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final design = ref.watch(currentDesignProvider);
    final selectedChannelId = ref.watch(selectedChannelIdProvider);
    final wledState = ref.watch(wledStateProvider);
    final supportsRgbw = wledState.supportsRgbw;
    final designMode = ref.watch(designModeProvider);
    final hasSegmentConfig = ref.watch(hasRooflineConfigProvider);

    if (_isLoading) {
      return Scaffold(
        appBar: const GlassAppBar(title: Text('Design Studio')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: GlassAppBar(
        title: GestureDetector(
          onTap: () => _showRenameDialog(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                design?.name ?? 'Untitled Design',
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit, size: 16, color: Colors.white54),
            ],
          ),
        ),
        actions: [
          // Segment config button
          IconButton(
            onPressed: () => context.push(AppRoutes.segmentSetup),
            tooltip: 'Configure Roofline Segments',
            icon: Badge(
              isLabelVisible: hasSegmentConfig,
              backgroundColor: NexGenPalette.cyan,
              smallSize: 8,
              child: const Icon(Icons.roofing),
            ),
          ),
          // Preview/Apply button
          IconButton(
            onPressed: _isApplying ? null : _applyToDevice,
            tooltip: 'Preview on Device',
            icon: _isApplying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
          ),
          // Save button
          IconButton(
            onPressed: _isSaving ? null : _saveDesign,
            tooltip: 'Save Design',
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
          ),
        ],
      ),
      body: design == null
          ? const Center(child: Text('Failed to initialize design'))
          : Column(
              children: [
                // Mode toggle
                _buildModeToggle(designMode),
                // Body based on mode
                Expanded(
                  child: designMode == DesignMode.channel
                      ? _buildBody(context, design, selectedChannelId, supportsRgbw)
                      : _buildSegmentModeBody(context, design),
                ),
              ],
            ),
    );
  }

  Widget _buildModeToggle(DesignMode currentMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Mode:',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 12),
          SegmentedButton<DesignMode>(
            segments: const [
              ButtonSegment(
                value: DesignMode.channel,
                label: Text('Channel'),
                icon: Icon(Icons.layers, size: 16),
              ),
              ButtonSegment(
                value: DesignMode.segment,
                label: Text('Segment'),
                icon: Icon(Icons.roofing, size: 16),
              ),
            ],
            selected: {currentMode},
            onSelectionChanged: (values) {
              ref.read(designModeProvider.notifier).state = values.first;
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
            ),
          ),
          const Spacer(),
          if (currentMode == DesignMode.segment)
            TextButton.icon(
              onPressed: () => context.push(AppRoutes.segmentSetup),
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('Configure'),
              style: TextButton.styleFrom(
                foregroundColor: NexGenPalette.cyan,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSegmentModeBody(BuildContext context, CustomDesign design) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Segment LED canvas with generated pattern
          SegmentLedCanvas(
            colorGroups: _generatedPattern,
            showAnchors: true,
          ),
          const SizedBox(height: 16),

          // Pattern template selector
          PatternTemplateSelector(
            onApply: (groups, pattern) {
              setState(() {
                _generatedPattern = groups;
                _activePattern = pattern;
              });
            },
          ),
          const SizedBox(height: 16),

          // Pattern preview info
          if (_activePattern != null) ...[
            _buildPatternInfo(),
            const SizedBox(height: 16),
          ],

          // Brightness slider
          _buildBrightnessSlider(design),
          const SizedBox(height: 24),

          // Apply button for segment mode
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _generatedPattern != null && !_isApplying
                      ? _applySegmentPattern
                      : null,
                  icon: _isApplying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_isApplying ? 'Applying...' : 'Apply Pattern'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _generatedPattern != null && !_isSaving
                      ? _saveDesign
                      : null,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Saving...' : 'Save Design'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPatternInfo() {
    if (_activePattern == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.cyan.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            _activePattern!.templateType.icon,
            color: NexGenPalette.cyan,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _activePattern!.templateType.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${_generatedPattern?.length ?? 0} LED groups generated',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Color preview
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _activePattern!.anchorColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _activePattern!.spacedColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _applySegmentPattern() async {
    if (_generatedPattern == null || _generatedPattern!.isEmpty) return;

    setState(() => _isApplying = true);
    try {
      final design = ref.read(currentDesignProvider);
      final generator = ref.read(segmentPatternGeneratorProvider);

      // Build WLED payload for individual LED control
      final payload = generator.toWledIndividualPayload(
        groups: _generatedPattern!,
        brightness: design?.brightness ?? 200,
      );

      // Apply via WLED repository
      final wledRepo = ref.read(wledRepositoryProvider);
      if (wledRepo == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No device connected'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      final success = await wledRepo.applyJson(payload);

      if (success) {
        // Update the active preset label so home page shows the pattern name
        final patternName = _activePattern?.templateType.displayName ??
                           design?.name ??
                           'Custom Design';
        ref.read(activePresetLabelProvider.notifier).state = patternName;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'Pattern applied to device' : 'Failed to apply pattern',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Widget _buildBody(BuildContext context, CustomDesign design, int? selectedChannelId, bool supportsRgbw) {
    // Use different layouts for portrait vs landscape
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;

        if (isWide) {
          return _buildWideLayout(design, selectedChannelId, supportsRgbw);
        } else {
          return _buildNarrowLayout(design, selectedChannelId, supportsRgbw);
        }
      },
    );
  }

  Widget _buildWideLayout(CustomDesign design, int? selectedChannelId, bool supportsRgbw) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left panel: LED canvas
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  height: 400,
                  child: const LedStripCanvas(),
                ),
                const SizedBox(height: 16),
                _buildChannelSelector(design),
                const SizedBox(height: 16),
                _buildBrightnessSlider(design),
              ],
            ),
          ),
        ),
        // Right panel: Controls
        SizedBox(
          width: 320,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Lumina AI Assistant
                const LuminaDesignAssistant(),
                const SizedBox(height: 16),
                const ColorPalettePicker(),
                if (supportsRgbw) ...[
                  const SizedBox(height: 16),
                  _buildWhiteSlider(),
                ],
                const SizedBox(height: 16),
                const EffectSelector(),
                const SizedBox(height: 16),
                const ChannelQuickActions(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(CustomDesign design, int? selectedChannelId, bool supportsRgbw) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Lumina AI Assistant
          const LuminaDesignAssistant(),
          const SizedBox(height: 16),

          // LED canvas
          SizedBox(
            height: 280,
            child: const LedStripCanvas(),
          ),
          const SizedBox(height: 16),

          // Channel selector
          _buildChannelSelector(design),
          const SizedBox(height: 16),

          // Brightness
          _buildBrightnessSlider(design),
          const SizedBox(height: 16),

          // Color palette
          const ColorPalettePicker(),
          if (supportsRgbw) ...[
            const SizedBox(height: 16),
            _buildWhiteSlider(),
          ],
          const SizedBox(height: 16),

          // Effect selector
          const EffectSelector(),
          const SizedBox(height: 16),

          // Quick actions
          const ChannelQuickActions(),
          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isApplying ? null : _applyToDevice,
                  icon: _isApplying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_isApplying ? 'Applying...' : 'Preview'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _saveDesign,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Saving...' : 'Save Design'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildChannelSelector(CustomDesign design) {
    final selectedId = ref.watch(selectedChannelIdProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Channels',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final channel in design.channels)
                _ChannelChip(
                  channel: channel,
                  isSelected: selectedId == channel.channelId,
                  onTap: () {
                    ref.read(selectedChannelIdProvider.notifier).state = channel.channelId;
                  },
                  onIncludeChanged: (included) {
                    ref.read(currentDesignProvider.notifier).toggleChannelIncluded(channel.channelId);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrightnessSlider(CustomDesign design) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.brightness_6, color: Colors.white54, size: 20),
          const SizedBox(width: 12),
          const Text(
            'Brightness',
            style: TextStyle(color: Colors.white70),
          ),
          Expanded(
            child: Slider(
              value: design.brightness.toDouble(),
              min: 0,
              max: 255,
              activeColor: NexGenPalette.cyan,
              inactiveColor: Colors.white.withOpacity(0.1),
              onChanged: (value) {
                ref.read(currentDesignProvider.notifier).setBrightness(value.round());
              },
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${design.brightness}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhiteSlider() {
    final white = ref.watch(selectedWhiteProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.light_mode, color: Colors.white54, size: 20),
          const SizedBox(width: 12),
          const Text(
            'White LED',
            style: TextStyle(color: Colors.white70),
          ),
          Expanded(
            child: Slider(
              value: white.toDouble(),
              min: 0,
              max: 255,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withOpacity(0.1),
              onChanged: (value) {
                ref.read(selectedWhiteProvider.notifier).state = value.round();
              },
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$white',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final design = ref.read(currentDesignProvider);
    if (design == null) return;

    final controller = TextEditingController(text: design.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Rename Design', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Design Name',
            labelStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      ref.read(currentDesignProvider.notifier).setName(result);
    }
  }

  Future<void> _applyToDevice() async {
    setState(() => _isApplying = true);
    try {
      final design = ref.read(currentDesignProvider);
      final success = await ref.read(applyDesignProvider)();

      if (success) {
        // Update the active preset label so home page shows the design name
        final designName = design?.name.isNotEmpty == true && design?.name != 'Untitled Design'
            ? design!.name
            : 'Custom Design';
        ref.read(activePresetLabelProvider.notifier).state = designName;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Design applied to device' : 'Failed to apply design'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _saveDesign() async {
    final design = ref.read(currentDesignProvider);
    if (design == null) return;

    final designMode = ref.read(designModeProvider);

    // For segment mode, sync the generated pattern to the design
    if (designMode == DesignMode.segment) {
      if (_generatedPattern == null || _generatedPattern!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Generate a pattern first before saving'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Get roofline config ID
      final configAsync = ref.read(currentRooflineConfigProvider);
      final configId = configAsync.valueOrNull?.id;

      // Build pattern config from the active pattern
      Map<String, dynamic>? patternConfig;
      if (_activePattern != null) {
        patternConfig = {
          'anchor_color': [
            _activePattern!.anchorColor.red,
            _activePattern!.anchorColor.green,
            _activePattern!.anchorColor.blue,
          ],
          'spaced_color': [
            _activePattern!.spacedColor.red,
            _activePattern!.spacedColor.green,
            _activePattern!.spacedColor.blue,
          ],
          'spacing_count': _activePattern!.spacingCount,
          'anchor_always_on': _activePattern!.anchorAlwaysOn,
        };
      }

      // Update the design with segment mode data
      ref.read(currentDesignProvider.notifier).updateSegmentMode(
        isSegmentAware: true,
        templateType: _activePattern?.templateType,
        segmentColorGroups: _generatedPattern,
        segmentPatternConfig: patternConfig,
        rooflineConfigId: configId,
      );
    }

    // Validate name
    if (design.name.isEmpty || design.name == 'Untitled Design') {
      await _showRenameDialog(context);
      final updatedDesign = ref.read(currentDesignProvider);
      if (updatedDesign?.name.isEmpty == true || updatedDesign?.name == 'Untitled Design') {
        return; // User cancelled
      }
    }

    setState(() => _isSaving = true);
    try {
      final designId = await ref.read(saveDesignProvider)();
      if (mounted) {
        if (designId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Design saved!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save design'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _ChannelChip extends StatelessWidget {
  final ChannelDesign channel;
  final bool isSelected;
  final VoidCallback onTap;
  final ValueChanged<bool> onIncludeChanged;

  const _ChannelChip({
    required this.channel,
    required this.isSelected,
    required this.onTap,
    required this.onIncludeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? NexGenPalette.cyan.withOpacity(0.2)
              : channel.included
                  ? Colors.white.withOpacity(0.05)
                  : Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? NexGenPalette.cyan
                : channel.included
                    ? Colors.white.withOpacity(0.2)
                    : Colors.white.withOpacity(0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Include checkbox
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: channel.included,
                onChanged: (v) => onIncludeChanged(v ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            // Channel name
            Text(
              channel.channelName,
              style: TextStyle(
                color: channel.included ? Colors.white : Colors.white54,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            // LED count badge
            if (channel.ledCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${channel.ledCount}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
            // Color preview
            const SizedBox(width: 8),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: channel.primaryColor,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: channel.primaryColor.withOpacity(0.4),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
