import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/device_identity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/nav.dart' show AppRoutes;
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/design_frame.dart';
import 'package:nexgen_command/features/design/manual_editor/design_preview.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/design_studio_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_off_warning.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/design/widgets/ai_understanding_panel.dart';
import 'package:nexgen_command/features/design/widgets/clarification_dialog.dart';
import 'package:nexgen_command/features/design/widgets/voice_input_button.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Which authoring surface the Design Studio is showing (Slice 4).
enum _StudioMode { ai, manual }

/// AI-first Design Studio screen.
///
/// Users describe their lighting in natural language, and the system
/// interprets, validates, clarifies when needed, and composes the pattern.
class AIDesignStudioScreen extends ConsumerStatefulWidget {
  const AIDesignStudioScreen({super.key});

  @override
  ConsumerState<AIDesignStudioScreen> createState() => _AIDesignStudioScreenState();
}

class _AIDesignStudioScreenState extends ConsumerState<AIDesignStudioScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _showManualControls = false;
  bool _isSaving = false;
  bool _isApplying = false;
  _StudioMode _mode = _StudioMode.ai;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(designStudioStateProvider);
    final isProcessing = ref.watch(isProcessingProvider);
    final isClarifying = ref.watch(isClarifyingProvider);
    final patternReady = ref.watch(patternReadyProvider);
    final intent = ref.watch(currentDesignIntentProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: _buildAppBar(context),
      // SafeArea(bottom: false) handles the top notch; the bottom is
      // reserved via navBarTotalHeight(context) so the persistent glass
      // dock doesn't occlude the bottom-most widgets (input section,
      // action buttons, clarification dialog's Continue/Back row, quick
      // ideas). navBarTotalHeight already includes the device's bottom
      // inset — using SafeArea(bottom:true) on top would double-count it.
      // Matches the wider-codebase convention (pattern_grid_widgets.dart:62,
      // current_colors_editor_screen.dart:73).
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: navBarTotalHeight(context)),
          child: Column(
            children: [
              // Roofline SETUP entry — architectural structure (corners/peaks/
              // columns), distinct from the AI/Manual DESIGN mode pill. Routes
              // to the existing SegmentSetupScreen (no new editor); it loads the
              // existing map on entry (edit, never blank). Visible in BOTH modes
              // — architectural setup is orthogonal to design coloring, and this
              // is where users look for it.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.segmentSetup),
                    icon: const Icon(Icons.roofing, size: 18),
                    label: const Text('Roofline setup'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: NexGenPalette.cyan,
                      side: BorderSide(
                          color: NexGenPalette.cyan.withValues(alpha: 0.4)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _mode == _StudioMode.manual
                    ? const ManualDesignEditor()
                    : Column(
                        children: [
              // Unified preview (Slice 4 1b) — the SAME house-photo overlay
              // both modes render on, fed the AI ComposedPattern as a per-LED
              // frame. Falls back to a strip only when there's no trace/photo.
              Expanded(
                flex: 3,
                child: DesignPreview(frame: _aiFrame(), height: double.infinity),
              ),

              // Understanding panel (shows what we understood)
              if (intent != null && !isClarifying)
                AIUnderstandingPanel(
                  intent: intent,
                  onEditLayer: _handleEditLayer,
                  onOpenManual: () => setState(() => _showManualControls = true),
                ),

              // Clarification dialog (when needed)
              if (isClarifying)
                Expanded(
                  flex: 2,
                  child: ClarificationDialogWidget(
                    onComplete: _handleClarificationsComplete,
                    onManualRequested: (aspect) {
                      setState(() => _showManualControls = true);
                    },
                  ),
                ),

              // Input section
              if (!isClarifying)
                _buildInputSection(context, isProcessing),

              // Action buttons
              if (patternReady) _buildActionButtons(context),

              // Quick ideas
              if (state == DesignStudioStatus.idle && intent == null)
                _buildQuickIdeas(context),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the AI ComposedPattern's global color groups into the mode-agnostic
  /// per-LED frame the unified [DesignPreview] renders (Slice 4 1b).
  DesignFrame _aiFrame() {
    final composed = ref.watch(composedPatternProvider);
    if (composed == null) return const {};
    final channels = ref.watch(deviceChannelsProvider);
    int fallback = 0;
    for (final g in composed.colorGroups) {
      if (g.endLed + 1 > fallback) fallback = g.endLed + 1;
    }
    return frameFromGlobalGroups(
      groups: composed.colorGroups,
      channels: channels,
      fallbackLength: fallback,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final livePreviewEnabled = ref.watch(livePreviewEnabledProvider);

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: SegmentedButton<_StudioMode>(
        segments: const [
          ButtonSegment(value: _StudioMode.ai, label: Text('AI'), icon: Icon(Icons.auto_awesome, size: 16)),
          ButtonSegment(value: _StudioMode.manual, label: Text('Manual'), icon: Icon(Icons.brush, size: 16)),
        ],
        selected: {_mode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => _mode = s.first),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: WidgetStatePropertyAll(
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
      actions: [
        // Live preview toggle
        IconButton(
          icon: Icon(
            livePreviewEnabled ? Icons.visibility : Icons.visibility_off,
            color: livePreviewEnabled ? NexGenPalette.cyan : Colors.white54,
          ),
          onPressed: () {
            ref.read(livePreviewEnabledProvider.notifier).state = !livePreviewEnabled;
          },
          tooltip: livePreviewEnabled ? 'Preview on lights: ON' : 'Preview on lights: OFF',
        ),
        // Manual controls button
        IconButton(
          icon: const Icon(Icons.tune, color: Colors.white70),
          onPressed: () => setState(() => _showManualControls = !_showManualControls),
          tooltip: 'Manual controls',
        ),
      ],
    );
  }

  Widget _buildInputSection(BuildContext context, bool isProcessing) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Input prompt
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: NexGenPalette.cyan.withValues(alpha: 0.8),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Describe your lighting...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Text input with voice button
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Text field
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _focusNode.hasFocus
                          ? NexGenPalette.cyan.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'e.g., "Dark green with red accents on corners, wave effect moving right to left"',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    onSubmitted: isProcessing ? null : (_) => _handleSubmit(),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Voice input button
              VoiceInputButton(
                onTranscript: (transcript) {
                  _textController.text = transcript;
                  _handleSubmit();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Submit button
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: isProcessing ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: NexGenPalette.cyan.withValues(alpha: 0.3),
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black54),
                      ),
                    )
                  : const Text(
                      'Create Design',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    // #86: SAVE is implemented (option-b — preserves the AI sourceIntent +
    // derived channels; writes /users/{uid}/designs/{autoId} via
    // DesignService.saveDesign). APPLY remains DISABLED: it is firmware-gated
    // — the composer's wledPayload has three hardware-fidelity issues
    // (single whole-roofline seg vs the device's multi-bus split; RGB-only
    // static `i` payload dropping the W channel; relay payload size) that need
    // real-controller verification before wiring. Tracked as the remaining
    // #86 sub-task. Apply renders in its disabled style so users aren't misled
    // by a fake success snackbar (the #85 lesson).
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Save design button — #86 option-b
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _handleSaveDesign,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_isSaving ? 'Saving…' : 'Save'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Apply to Lights — #86 ENABLED (Design Studio Slice 4). Routes the
          // composed design through the shared per-pixel spine
          // (applyCustomDesignToLights): per-channel `i` spans with rgbToRgbw,
          // multi-bus-correct targeting, chunked transport — the three
          // firmware-fidelity concerns from the old disable comment resolved.
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _isApplying ? null : _handleApplyToLights,
              icon: _isApplying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black54),
                      ),
                    )
                  : const Icon(Icons.lightbulb),
              label: Text(_isApplying ? 'Applying…' : 'Apply to Lights'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickIdeas(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Ideas',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickIdeaChip(
                label: 'Warm White',
                onTap: () => _useQuickIdea('Warm white glow on the entire roofline'),
              ),
              _QuickIdeaChip(
                label: 'Team Colors',
                onTap: () => _useQuickIdea('Alternating blue and orange'),
              ),
              _QuickIdeaChip(
                label: 'Holiday',
                onTap: () => _useQuickIdea('Red and green with white accents on peaks and corners'),
              ),
              _QuickIdeaChip(
                label: 'Downlighting',
                onTap: () => _useQuickIdea('Bright white on corners and peaks, soft white spaced evenly in between'),
              ),
              _QuickIdeaChip(
                label: 'Chase Effect',
                onTap: () => _useQuickIdea('Blue chase effect moving left to right'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // Set state to processing
    ref.read(designStudioStateProvider.notifier).state = DesignStudioStatus.processing;
    ref.read(designStudioInputProvider.notifier).state = text;

    try {
      final orchestrator = ref.read(designStudioOrchestratorProvider);
      final configAsync = ref.read(currentRooflineConfigProvider);
      final config = configAsync.valueOrNull;

      final result = await orchestrator.processUserInput(
        prompt: text,
        config: config,
      );

      if (!mounted) return;

      // Update state based on result
      ref.read(designStudioStateProvider.notifier).state = result.status;

      if (result.intent != null) {
        ref.read(currentDesignIntentProvider.notifier).setIntent(result.intent!);
      }

      if (result.needsClarification && result.pendingQuestions != null) {
        ref.read(pendingClarificationsProvider.notifier).state = result.pendingQuestions!;
        ref.read(currentQuestionIndexProvider.notifier).state = 0;
        ref.read(clarificationChoicesProvider.notifier).state = {};
      }

      if (result.isReady && result.pattern != null) {
        ref.read(composedPatternProvider.notifier).state = result.pattern;
      }
    } catch (e) {
      _handleOrchestratorError(e);
    }
  }

  /// Shared catch handler for the two screens-level orchestrator entry
  /// points (_handleSubmit, _handleClarificationsComplete). On a thrown
  /// orchestrator error, both code paths must:
  ///   - reset status out of `processing` so the input UI re-enables
  ///     instead of staying spinner-locked (status == error makes
  ///     isProcessing false → _buildInputSection re-enables Submit),
  ///   - surface a user-facing toast so the failure is visible, not
  ///     silent.
  /// debugPrint preserves the raw error for log triage without exposing
  /// internal stack info to the user.
  void _handleOrchestratorError(Object e) {
    debugPrint('DesignStudio orchestrator error: $e');
    if (!mounted) return;
    ref.read(designStudioStateProvider.notifier).state = DesignStudioStatus.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Couldn't process that — please try again."),
        backgroundColor: Colors.red.shade800,
      ),
    );
  }

  void _useQuickIdea(String idea) {
    _textController.text = idea;
    _handleSubmit();
  }

  void _handleEditLayer(String layerId) {
    // Open manual controls for this specific layer
    setState(() => _showManualControls = true);
    // TODO: Focus on the specific layer in manual controls
  }

  Future<void> _handleClarificationsComplete() async {
    // applyClarificationsProvider is a FutureProvider<DesignStudioResult>
    // whose body runs the orchestrator and writes results back to the
    // state providers this screen watches. ref.read(provider) on a
    // FutureProvider returns an AsyncValue snapshot without triggering
    // execution — earlier code did exactly that, so Continue was a no-op.
    // refresh(provider.future) invalidates any cached value and kicks the
    // body fresh.
    //
    // We must await INSIDE try/catch: the provider body flips status to
    // `processing` before its async work, so an unhandled throw leaves
    // the UI stuck on the spinner. _handleOrchestratorError resets status
    // and toasts on failure. The happy path is unchanged — the provider's
    // own writes drive the UI rebuild.
    try {
      // We await for the side-effect (provider body runs + writes state)
      // and to surface a throw into our catch; the resolved value is read
      // off the providers the body wrote, not the return here.
      // ignore: unused_result
      await ref.refresh(applyClarificationsProvider.future);
    } catch (e) {
      _handleOrchestratorError(e);
    }
  }

  /// #86 option-b SAVE. Persists the current [ComposedPattern] as a
  /// [CustomDesign] via the canonical [saveComposedDesignProvider]: derived
  /// per-channel denormalization (My Designs previews + legacy apply) PLUS the
  /// full composedPattern map preserving the AI sourceIntent for re-edit.
  ///
  /// The write is awaited BEFORE any success UI — no optimistic success (the
  /// #85 lesson). A failed/empty result surfaces a red snackbar; a throw is
  /// caught and surfaced the same way. composedPattern is jsonEncoded inside
  /// CustomDesign.toFirestore so its nested arrays never hit the #84 codec.
  Future<void> _handleSaveDesign() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final saveFn = ref.read(saveComposedDesignProvider);
      final designId = await saveFn();

      if (!mounted) return;

      if (designId == null || designId.isEmpty) {
        // No composed pattern or no signed-in user — nothing was written.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Couldn't save — no design or you're signed out."),
            backgroundColor: Colors.red.shade800,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to My Designs'),
          backgroundColor: NexGenPalette.cyan,
        ),
      );
    } catch (e) {
      debugPrint('DesignStudio save error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't save that design — please try again."),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// #86 apply — builds the current ComposedPattern into an in-memory
  /// CustomDesign and applies it through the SHARED per-pixel spine (the same
  /// [applyCustomDesignToLights] the manual editor's "Apply to Lights" uses).
  Future<void> _handleApplyToLights() async {
    if (_isApplying) return;
    final design = ref.read(composedDesignForApplyProvider);
    if (design == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Describe a design first, then apply it.'),
          backgroundColor: Colors.red.shade800,
        ),
      );
      return;
    }
    setState(() => _isApplying = true);
    try {
      final result = await applyCustomDesignToLights(ref, design);
      if (!mounted) return;
      final (msg, color) = switch (result) {
        DesignApplyResult.applied ||
        DesignApplyResult.staleApplied =>
          ('Applied to your lights', NexGenPalette.cyan),
        DesignApplyResult.noMap => (
            'This design has no lit pixels to apply.',
            Colors.orange.shade800
          ),
        DesignApplyResult.error => (
            // #94 — an identity refusal must say so, not blame the network.
            takeIdentityRefusalMessage() ??
                "Couldn't reach your lights. Check the connection.",
            Colors.red.shade800
          ),
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color),
      );
      if (result == DesignApplyResult.applied ||
          result == DesignApplyResult.staleApplied) {
        maybeShowManualApplyOffWarning(ref);
      }
    } catch (e) {
      debugPrint('DesignStudio apply error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Couldn't apply that design — please try again."),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }
}

/// Quick idea chip widget.
class _QuickIdeaChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickIdeaChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
