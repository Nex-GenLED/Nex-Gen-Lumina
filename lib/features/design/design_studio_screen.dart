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
            'Design Style:',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(width: 12),
          SegmentedButton<DesignMode>(
            segments: const [
              ButtonSegment(
                value: DesignMode.channel,
                label: Text('Simple'),
                icon: Icon(Icons.palette, size: 16),
              ),
              ButtonSegment(
                value: DesignMode.segment,
                label: Text('Advanced'),
                icon: Icon(Icons.auto_awesome, size: 16),
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
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('Setup'),
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
    final hasRooflineConfig = ref.watch(hasRooflineConfigProvider);

    // If no roofline config, show setup prompt
    if (!hasRooflineConfig) {
      return _buildNoRooflineConfigPrompt();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Roofline info bar with quick actions
          _buildRooflineInfoBar(),
          const SizedBox(height: 16),

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

  /// Prompt shown when no roofline configuration exists.
  Widget _buildNoRooflineConfigPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.roofing,
                size: 40,
                color: NexGenPalette.cyan,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Set Up Your Roofline',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Configure your LED segments to enable smart pattern generation, spacing algorithms, and roofline-aware recommendations.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.push(AppRoutes.rooflineSetupWizard),
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Start Setup Wizard'),
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.push(AppRoutes.segmentSetup),
              child: const Text('Manual Segment Setup'),
            ),
          ],
        ),
      ),
    );
  }

  /// Info bar showing roofline configuration summary.
  Widget _buildRooflineInfoBar() {
    final config = ref.watch(currentRooflineConfigProvider);

    return config.maybeWhen(
      data: (rooflineConfig) {
        if (rooflineConfig == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              const Icon(Icons.roofing, color: NexGenPalette.cyan, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rooflineConfig.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${rooflineConfig.totalPixelCount} LEDs • ${rooflineConfig.segmentCount} segments',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                color: Colors.white54,
                tooltip: 'Edit Roofline',
                onPressed: () => context.push(AppRoutes.rooflineSetupWizard),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
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

          // Action buttons - large and easy to tap
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _isApplying ? null : _applyToDevice,
              icon: _isApplying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.visibility, size: 24),
              label: Text(
                _isApplying ? 'Sending to lights...' : 'See It On My Lights',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _saveDesign,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bookmark_add_outlined),
              label: Text(
                _isSaving ? 'Saving...' : 'Save for Later',
                style: const TextStyle(fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildChannelSelector(CustomDesign design) {
    final selectedId = ref.watch(selectedChannelIdProvider);

    // If only one channel, simplify the UI
    if (design.channels.length == 1) {
      return const SizedBox.shrink(); // Hide channel selector for single zone
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: Colors.white54, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Lighting Zones',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Tap to select',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
    // Convert 0-255 to percentage for user-friendly display
    final percentage = ((design.brightness / 255) * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                percentage > 70 ? Icons.light_mode : (percentage > 30 ? Icons.brightness_6 : Icons.brightness_low),
                color: NexGenPalette.cyan,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'How Bright?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$percentage%',
                  style: const TextStyle(
                    color: NexGenPalette.cyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            ),
            child: Slider(
              value: design.brightness.toDouble(),
              min: 0,
              max: 255,
              activeColor: NexGenPalette.cyan,
              inactiveColor: Colors.white.withValues(alpha: 0.1),
              onChanged: (value) {
                ref.read(currentDesignProvider.notifier).setBrightness(value.round());
              },
            ),
          ),
          // Friendly labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dim', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                Text('Medium', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                Text('Bright', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
              ],
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
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
              inactiveColor: Colors.white.withValues(alpha: 0.1),
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
            (_activePattern!.anchorColor.r * 255).round().clamp(0, 255),
            (_activePattern!.anchorColor.g * 255).round().clamp(0, 255),
            (_activePattern!.anchorColor.b * 255).round().clamp(0, 255),
          ],
          'spaced_color': [
            (_activePattern!.spacedColor.r * 255).round().clamp(0, 255),
            (_activePattern!.spacedColor.g * 255).round().clamp(0, 255),
            (_activePattern!.spacedColor.b * 255).round().clamp(0, 255),
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

class _ChannelChip extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: () => _showLedCountDialog(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? NexGenPalette.cyan.withValues(alpha: 0.25)
              : channel.included
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? NexGenPalette.cyan
                : channel.included
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color preview - larger and more prominent
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: channel.primaryColor,
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: channel.primaryColor.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: channel.included
                  ? null
                  : const Icon(Icons.visibility_off, size: 14, color: Colors.white54),
            ),
            const SizedBox(width: 10),
            // Zone name - friendly display
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  channel.channelName,
                  style: TextStyle(
                    color: channel.included ? Colors.white : Colors.white54,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                if (isSelected)
                  Text(
                    channel.included ? 'Selected' : 'Tap to include',
                    style: TextStyle(
                      color: NexGenPalette.cyan.withValues(alpha: 0.8),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 8),
            // Include toggle - simplified
            if (!isSelected)
              Icon(
                channel.included ? Icons.check_circle : Icons.radio_button_unchecked,
                color: channel.included ? NexGenPalette.cyan : Colors.white38,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLedCountDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: channel.ledCount > 0 ? channel.ledCount.toString() : '',
    );

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: Row(
          children: [
            const Icon(Icons.tune, color: NexGenPalette.cyan, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Advanced Settings',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Zone: ${channel.channelName}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Number of lights in this zone:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                hintText: 'e.g., 130',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: NexGenPalette.cyan, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blue, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This was set up during installation. Only change if advised by support.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value != null && value > 0 && value <= 2000) {
                Navigator.pop(ctx, value);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a number between 1 and 2000'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      ref.read(currentDesignProvider.notifier).setChannelLedCount(
        channel.channelId,
        result,
      );
    }
  }
}
