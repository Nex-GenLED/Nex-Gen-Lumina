import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/device_identity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/nav.dart' show AppRoutes;
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/design_studio_gate.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/design/manual_editor/design_frame.dart';
import 'package:nexgen_command/features/design/manual_editor/design_preview.dart';
import 'package:nexgen_command/features/design/manual_editor/manual_design_editor.dart';
import 'package:nexgen_command/features/design/models/composed_pattern.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/roofline_feature_walkthrough.dart';
import 'package:nexgen_command/features/design/design_studio_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_off_warning.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/design/widgets/ai_understanding_panel.dart';
import 'package:nexgen_command/features/design/widgets/clarification_dialog.dart';
import 'package:nexgen_command/features/design/widgets/voice_input_button.dart';
import 'package:nexgen_command/features/wled/device_write_reporter.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Which authoring surface the Design Studio is showing (Slice 4).
enum _StudioMode { ai, manual }

/// AI-first Design Studio screen.
///
/// Users describe their lighting in natural language, and the system
/// interprets, validates, clarifies when needed, and composes the pattern.
///
/// +110 package E2:
///  * item 1 — gated on a SEGMENTED roofline ([designStudioGateProvider]).
///    The blocked view names what is missing and opens the feature
///    walkthrough. It never no-ops.
///  * row 2 — an orchestrator error shows its message and suggestions, and a
///    "no roofline" error routes to setup.
///  * row 115 — "Start over"; the studio resets on entry.
///  * row 116 — "Preview on lights" is wired: while it is on, every composed
///    design is sent to the lights as a preview.
///  * row 117 — the manual editor opens ON the composed design.
///  * rows 40–42 — Apply goes through the shared spine with its report.
class AIDesignStudioScreen extends ConsumerStatefulWidget {
  const AIDesignStudioScreen({super.key});

  @override
  ConsumerState<AIDesignStudioScreen> createState() => _AIDesignStudioScreenState();
}

class _AIDesignStudioScreenState extends ConsumerState<AIDesignStudioScreen> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSaving = false;
  bool _isApplying = false;
  _StudioMode _mode = _StudioMode.ai;
  final _previewReporter = DeviceWriteReporter(what: 'preview');
  Timer? _previewThrottle;

  @override
  void initState() {
    super.initState();
    // Row 115: a fresh studio every visit. The state providers are global,
    // so without this a question left pending on the last visit (from any
    // tab) was still there on the next one. Deferred one frame: a provider
    // may not be written while the tree is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) resetDesignStudio(ref);
    });
  }

  @override
  void dispose() {
    _previewThrottle?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gate = ref.watch(designStudioGateProvider);
    final state = ref.watch(designStudioStateProvider);
    final isProcessing = ref.watch(isProcessingProvider);
    final isClarifying = ref.watch(isClarifyingProvider);
    final patternReady = ref.watch(patternReadyProvider);
    final intent = ref.watch(currentDesignIntentProvider);
    final lastError = ref.watch(designStudioLastErrorProvider);

    // Row 116: a newly composed design goes to the lights while the preview
    // toggle is on.
    ref.listen<ComposedPattern?>(composedPatternProvider, (prev, next) {
      if (next != null && !identical(prev, next) &&
          ref.read(livePreviewEnabledProvider)) {
        _scheduleLivePreview();
      }
    });

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: _buildAppBar(context, gate),
      // SafeArea(bottom: false) handles the top notch; the bottom is
      // reserved via navBarTotalHeight(context) so the persistent glass
      // dock doesn't occlude the bottom-most widgets (input section,
      // action buttons, clarification dialog's Continue/Back row, quick
      // ideas). navBarTotalHeight already includes the device's bottom
      // inset — using SafeArea(bottom:true) on top would double-count it.
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: navBarTotalHeight(context)),
          child: !gate.isReady
              ? _StudioBlockedView(gate: gate, onWalkthrough: _openWalkthrough)
              : Column(
                  children: [
                    // Roofline SETUP entry — architectural structure
                    // (corners/peaks/columns), distinct from the AI/Manual
                    // DESIGN mode pill. Visible in BOTH modes.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
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
                          Text(
                            _sectionsSummary(gate),
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _mode == _StudioMode.manual
                          ? _buildManualEditor()
                          : SingleChildScrollView(
                              child: Column(
                                children: [
                                  // Unified preview (Slice 4 1b) — the SAME
                                  // house-photo overlay both modes render on.
                                  DesignPreview(frame: _aiFrame(), height: 200),

                                  // Understanding panel (what we understood)
                                  if (intent != null && !isClarifying)
                                    AIUnderstandingPanel(
                                      intent: intent,
                                      onEditLayer: _handleEditLayer,
                                      onOpenManual: _openManual,
                                    ),

                                  // Row 2: what went wrong, and what to do.
                                  if (lastError != null && !isClarifying)
                                    _StudioErrorPanel(
                                      result: lastError,
                                      onRooflineSetup: () =>
                                          context.push(AppRoutes.segmentSetup),
                                      onOpenManual: _openManual,
                                      onStartOver: _startOver,
                                    ),

                                  // Clarification dialog (when needed)
                                  if (isClarifying)
                                    ClarificationDialogWidget(
                                      onComplete: _handleClarificationsComplete,
                                      // "Set manually" in a clarification question.
                                      onManualRequested: (aspect) => _openManual(),
                                      onStartOver: _startOver,
                                    ),

                                  // Input section
                                  if (!isClarifying)
                                    _buildInputSection(context, isProcessing),

                                  // Action buttons
                                  if (patternReady) _buildActionButtons(context),

                                  // Quick ideas
                                  if (state == DesignStudioStatus.idle &&
                                      intent == null)
                                    _buildQuickIdeas(context),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  String _sectionsSummary(DesignStudioGate gate) {
    final s = gate.segmentation;
    final parts = <String>[
      if (s.corners > 0) '${s.corners} corner${s.corners == 1 ? '' : 's'}',
      if (s.peaks > 0) '${s.peaks} peak${s.peaks == 1 ? '' : 's'}',
      if (s.runs > 0) '${s.runs} run${s.runs == 1 ? '' : 's'}',
    ];
    return parts.isEmpty ? 'Sections marked' : parts.join(' · ');
  }

  /// Row 117: the manual editor opens ON the composed design when there is
  /// one, so the pencil, the tune icon and "Set manually" edit THIS design
  /// rather than a blank canvas. The key re-creates the editor when the
  /// composed design changes.
  Widget _buildManualEditor() {
    final design = ref.watch(composedDesignForApplyProvider);
    return ManualDesignEditor(
      key: ValueKey(design?.composedPattern?['composed_at'] ?? 'blank'),
      initialDesign: design,
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

  PreferredSizeWidget _buildAppBar(BuildContext context, DesignStudioGate gate) {
    final livePreviewEnabled = ref.watch(livePreviewEnabledProvider);
    final hasWork = ref.watch(currentDesignIntentProvider) != null ||
        ref.watch(composedPatternProvider) != null ||
        ref.watch(designStudioLastErrorProvider) != null ||
        ref.watch(isClarifyingProvider);

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: gate.isReady
          ? FittedBox(
              fit: BoxFit.scaleDown,
              child: SegmentedButton<_StudioMode>(
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
            )
          : const Text('Design Studio'),
      actions: [
        if (gate.isReady) ...[
          // Row 115: Start over.
          if (hasWork && _mode == _StudioMode.ai)
            IconButton(
              icon: const Icon(Icons.restart_alt, color: Colors.white70),
              onPressed: _startOver,
              tooltip: 'Start over',
            ),
          // Row 116: live preview toggle — wired.
          if (_mode == _StudioMode.ai)
            IconButton(
              icon: Icon(
                livePreviewEnabled ? Icons.visibility : Icons.visibility_off,
                color: livePreviewEnabled ? NexGenPalette.cyan : Colors.white54,
              ),
              onPressed: _toggleLivePreview,
              tooltip: livePreviewEnabled ? 'Preview on lights: ON' : 'Preview on lights: OFF',
            ),
          // Manual controls button — a second, labelled door to the SAME
          // place the AI | Manual toggle in the title leads. Hidden once there.
          if (_mode == _StudioMode.ai)
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white70),
              onPressed: _openManual,
              tooltip: ref.watch(composedPatternProvider) != null
                  ? 'Edit this design by hand'
                  : 'Manual controls',
            ),
        ],
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
              Expanded(
                child: Text(
                  'Describe your lighting...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
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
                    maxLines: 4,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'e.g. "Dark green with red accents on corners, wave effect moving right to left"',
                      hintMaxLines: 4,
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
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
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

          // Apply to Lights — through the shared spine, with its report.
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

      if (result.needsClarification) {
        ref.read(clarificationChoicesProvider.notifier).state = {};
      }
      // Row 2: an error is RECORDED, and the panel above the prompt shows
      // its message and suggestions. It used to be dropped here.
      recordDesignStudioResultWith(ref.read, result);
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
  ///   - surface a user-facing message so the failure is visible, not
  ///     silent.
  /// debugPrint preserves the raw error for log triage without exposing
  /// internal stack info to the user.
  void _handleOrchestratorError(Object e) {
    debugPrint('DesignStudio orchestrator error: $e');
    if (!mounted) return;
    recordDesignStudioResultWith(
      ref.read,
      DesignStudioResult.error(
        "Couldn't process that — please try again.",
        recommendManual: true,
      ),
    );
  }

  void _useQuickIdea(String idea) {
    _textController.text = idea;
    _handleSubmit();
  }

  /// Row 115: back to a blank studio.
  void _startOver() {
    _textController.clear();
    FocusScope.of(context).unfocus();
    resetDesignStudio(ref);
    setState(() => _mode = _StudioMode.ai);
  }

  Future<void> _openWalkthrough() async {
    await openRooflineFeatureWalkthrough(context);
    // The gate re-reads the map stream on return; nothing to do here.
  }

  /// Every "manual controls" affordance on this screen lands here: the tune
  /// icon in the app bar, "open manual" in the AI understanding panel, a
  /// layer's edit button, and "Set manually" in a clarification question.
  /// Row 117: the editor opens on the composed design (see
  /// [_buildManualEditor]).
  void _openManual() {
    if (_mode == _StudioMode.manual) return;
    FocusScope.of(context).unfocus(); // drop the AI prompt keyboard
    setState(() => _mode = _StudioMode.manual);
  }

  void _handleEditLayer(String layerId) {
    // The paint editor works on pixels, not on AI layers, so there is no
    // per-layer focus to restore — it opens the editor on the whole design.
    _openManual();
  }

  Future<void> _handleClarificationsComplete() async {
    // applyClarificationsProvider is a FutureProvider<DesignStudioResult>
    // whose body runs the orchestrator and writes results back to the
    // state providers this screen watches. refresh(provider.future)
    // invalidates any cached value and kicks the body fresh.
    try {
      // ignore: unused_result
      await ref.refresh(applyClarificationsProvider.future);
    } catch (e) {
      _handleOrchestratorError(e);
    }
  }

  // ── Row 116: preview on lights ───────────────────────────────────────────

  void _toggleLivePreview() {
    final next = !ref.read(livePreviewEnabledProvider);
    ref.read(livePreviewEnabledProvider.notifier).state = next;
    if (next) {
      if (ref.read(composedPatternProvider) != null) {
        _scheduleLivePreview();
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text(
                'Preview is on — each design you create will show on your '
                'lights.'),
            duration: Duration(seconds: 3),
          ));
      }
    }
  }

  void _scheduleLivePreview() {
    _previewThrottle?.cancel();
    _previewThrottle = Timer(const Duration(milliseconds: 300), () async {
      final design = ref.read(composedDesignForApplyProvider);
      if (design == null || !mounted) return;
      final report = await applyCustomDesignDetailed(ref, design);
      if (!mounted) return;
      final ok = _previewReporter.report(context, report.ok);
      if (!ok && report.message != null && report.wire != SpineWriteResult.baseFailed) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(report.message!),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 5),
          ));
      }
    });
  }

  /// #86 option-b SAVE. Persists the current [ComposedPattern] as a
  /// [CustomDesign] via the canonical [saveComposedDesignProvider].
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

  /// Apply — builds the current ComposedPattern into an in-memory
  /// CustomDesign and applies it through the SHARED spine (the same one the
  /// manual editor's "Apply to Lights" uses). Rows 40–42: every channel the
  /// design paints; motion runs as its effect; the report's own sentence.
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
      final report = await applyCustomDesignDetailed(ref, design);
      if (!mounted) return;
      final (msg, color) = switch (report.result) {
        DesignApplyResult.applied ||
        DesignApplyResult.staleApplied =>
          (
            motionEffectOf(design) != null
                ? 'Applied to your lights, with motion'
                : 'Applied to your lights',
            NexGenPalette.cyan
          ),
        DesignApplyResult.noMap => (
            'This design has no lit pixels to apply.',
            Colors.orange.shade800
          ),
        DesignApplyResult.error => (
            // #94 — an identity refusal must say so, not blame the network.
            takeIdentityRefusalMessage() ??
                report.message ??
                "Couldn't reach your lights. Check the connection.",
            Colors.red.shade800
          ),
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: color,
          duration: Duration(seconds: report.ok ? 3 : 6),
        ),
      );
      if (report.ok) maybeShowManualApplyOffWarning(ref);
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

/// Item 1a — the studio is closed until the roofline is segmented. Names what
/// is missing and opens the walkthrough. Never a silent no-op.
class _StudioBlockedView extends StatelessWidget {
  const _StudioBlockedView({required this.gate, required this.onWalkthrough});

  final DesignStudioGate gate;
  final Future<void> Function() onWalkthrough;

  @override
  Widget build(BuildContext context) {
    final loading = gate.state == DesignStudioGateState.loading;
    return SingleChildScrollView(
      key: const ValueKey('studio-gate'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: loading
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    gate.state == DesignStudioGateState.noController
                        ? Icons.router_outlined
                        : Icons.roofing,
                    size: 48,
                    color: NexGenPalette.cyan.withValues(alpha: 0.8),
                  ),
          ),
          const SizedBox(height: 20),
          Text(
            gate.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            gate.message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 24),
          if (gate.opensWalkthrough)
            FilledButton.icon(
              key: const ValueKey('studio-gate-walkthrough'),
              onPressed: onWalkthrough,
              icon: const Icon(Icons.touch_app_outlined),
              label: Text(gate.actionLabel ?? 'Mark corners and peaks'),
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          if (gate.opensWalkthrough) ...[
            const SizedBox(height: 10),
            Text(
              'Takes a few minutes. One light at a time lights up on your '
              'house; you say whether it sits on a corner, a peak or a run.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
            ),
          ],
          if (gate.state == DesignStudioGateState.chooseController) ...[
            FilledButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Back to Home'),
              style: FilledButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Row 2 — the orchestrator's message and suggestions, with the action that
/// matches: roofline setup for a roofline problem, the manual editor when the
/// orchestrator recommends it, and Start over.
class _StudioErrorPanel extends StatelessWidget {
  const _StudioErrorPanel({
    required this.result,
    required this.onRooflineSetup,
    required this.onOpenManual,
    required this.onStartOver,
  });

  final DesignStudioResult result;
  final VoidCallback onRooflineSetup;
  final VoidCallback onOpenManual;
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final roofline = isRooflineSetupError(result);
    return Container(
      key: const ValueKey('studio-error'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.errorMessage ?? 'Something went wrong.',
                  style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
                ),
              ),
            ],
          ),
          for (final s in result.suggestions)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 30),
              child: Text(
                '• $s',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (roofline)
                FilledButton.icon(
                  key: const ValueKey('studio-error-roofline'),
                  onPressed: onRooflineSetup,
                  icon: const Icon(Icons.roofing, size: 18),
                  label: const Text('Roofline setup'),
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (result.recommendManual)
                OutlinedButton.icon(
                  onPressed: onOpenManual,
                  icon: const Icon(Icons.brush, size: 18),
                  label: const Text('Paint it by hand'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              TextButton(
                onPressed: onStartOver,
                child: const Text('Start over'),
              ),
            ],
          ),
        ],
      ),
    );
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
