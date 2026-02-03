import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design_studio/design_studio_providers.dart';
import 'package:nexgen_command/features/design_studio/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/design_studio/widgets/ai_understanding_panel.dart';
import 'package:nexgen_command/features/design_studio/widgets/clarification_dialog.dart';
import 'package:nexgen_command/features/design_studio/widgets/live_preview_canvas.dart';
import 'package:nexgen_command/features/design_studio/widgets/voice_input_button.dart';
import 'package:nexgen_command/theme.dart';

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
    final livePreviewEnabled = ref.watch(livePreviewEnabledProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: Column(
          children: [
            // Live preview canvas
            Expanded(
              flex: 3,
              child: LivePreviewCanvas(
                enabled: livePreviewEnabled,
              ),
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
      title: const Text(
        'Design Studio',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
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
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Save design button
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _handleSaveDesign,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
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

          // Apply to lights button
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _handleApplyToLights,
              icon: const Icon(Icons.lightbulb),
              label: const Text('Apply to Lights'),
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

  void _handleSubmit() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    // Trigger processing
    ref.read(processInputProvider(text));
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

  void _handleClarificationsComplete() {
    // Apply clarifications and continue
    ref.read(applyClarificationsProvider);
  }

  void _handleSaveDesign() {
    final pattern = ref.read(composedPatternProvider);
    if (pattern == null) return;

    // TODO: Implement save to library
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Design saved to library'),
        backgroundColor: NexGenPalette.cyan,
      ),
    );
  }

  void _handleApplyToLights() {
    final pattern = ref.read(composedPatternProvider);
    if (pattern == null) return;

    // TODO: Send to WLED devices
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Applying design to lights...'),
        backgroundColor: NexGenPalette.cyan,
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
