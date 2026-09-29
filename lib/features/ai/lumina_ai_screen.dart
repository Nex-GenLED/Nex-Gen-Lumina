import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/ai/lumina_conversation_driver.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/lumina_response_card.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Brand color constants
// ---------------------------------------------------------------------------

const _kVoid = Color(0xFF07091A);
const _kCarbon = Color(0xFF111527);
const _kFrost = Color(0xFFDCF0FF);
const _kPulse = Color(0xFF6E2FFF); // SMART layer
const _kFast = Color(0xFF00FF9D); // FAST layer

// ===========================================================================
// LuminaAIScreen — full-screen Lumina AI chat
// ===========================================================================

class LuminaAIScreen extends ConsumerStatefulWidget {
  const LuminaAIScreen({super.key});

  @override
  ConsumerState<LuminaAIScreen> createState() => _LuminaAIScreenState();
}

class _LuminaAIScreenState extends ConsumerState<LuminaAIScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Speech recognition
  late final stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;

  // Track whether text field has content (for send button glow)
  bool _hasText = false;

  // Silence timer for auto-stop
  Timer? _silenceTimer;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();

    _textController.addListener(() {
      final hasText = _textController.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _speech.stop();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Speech-to-text
  // -------------------------------------------------------------------------

  Future<void> _startListening() async {
    if (_isListening) return;

    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (mounted && _isListening) {
              _stopListening(submit: true);
            }
          }
        },
        onError: (error) {
          debugPrint('Lumina STT error: ${error.errorMsg}');
          if (mounted) _stopListening();
        },
      );

      if (!_speechAvailable) {
        debugPrint('Speech recognition not available');
        return;
      }

      HapticFeedback.mediumImpact();
      setState(() => _isListening = true);

      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final words = result.recognizedWords;

          // Reset silence timer on new speech
          _silenceTimer?.cancel();
          if (words.isNotEmpty) {
            _silenceTimer = Timer(const Duration(seconds: 2), () {
              if (mounted && _isListening) {
                _stopListening(submit: true);
              }
            });
          }

          if (result.finalResult && words.isNotEmpty) {
            _textController.text = words;
            _stopListening(submit: true);
          } else {
            _textController.text = words;
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          partialResults: true,
        ),
      );
    } catch (e) {
      debugPrint('Lumina STT init failed: $e');
      if (mounted) _stopListening();
    }
  }

  void _stopListening({bool submit = false}) {
    _silenceTimer?.cancel();
    _speech.stop();
    setState(() {
      _isListening = false;
    });

    if (submit) {
      final text = _textController.text.trim();
      if (text.isNotEmpty) {
        _sendMessage(text);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Send message / conversation
  // -------------------------------------------------------------------------

  /// The shared conversation driver, bound to this surface. Built per use:
  /// it holds no state, and nothing Riverpod-owned is kept on this State.
  LuminaConversationDriver get _driver => LuminaConversationDriver(
        services: RiverpodLuminaConversationServices(ref),
        host: LuminaConversationHost(
          surface: LuminaSurface.screen,
          isMounted: () => mounted,
          clearInput: () {
            _textController.clear();
            _focusNode.unfocus();
          },
          scrollToEnd: _scrollToEnd,
          closeSurface: () => Navigator.of(context).pop(),
          goRoute: (route) => context.go(route),
          pushRoute: (route) {
            context.push(route);
          },
          showSnackBar: (message) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          },
        ),
      );

  Future<void> _sendMessage(String text) => _driver.send(text);

  void _scrollToEnd() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // -------------------------------------------------------------------------
  // Greeting helper
  // -------------------------------------------------------------------------

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // -------------------------------------------------------------------------
  // Apply pattern from bubble
  // -------------------------------------------------------------------------

  Future<void> _applyPattern(
    Map<String, dynamic> wled,
    LuminaPatternPreview? preview, {
    String? originalPrompt,
  }) =>
      _driver.applyFromBubble(wled, preview, originalPrompt: originalPrompt);

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final sheetState = ref.watch(luminaSheetProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _kVoid,
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          _buildHeader(sheetState),
          Divider(
            color: NexGenPalette.line.withValues(alpha: 0.4),
            height: 1,
            indent: 20,
            endIndent: 20,
          ),
          Expanded(
            child: sheetState.messages.isEmpty
                ? _buildEmptyState(sheetState)
                : _buildMessageList(sheetState),
          ),
          _buildInputBar(sheetState),
          SizedBox(height: bottomInset > 0 ? 8 : bottomPadding + 8),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Header
  // -------------------------------------------------------------------------

  Widget _buildHeader(LuminaSheetState sheetState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 22),
            color: _kFrost.withValues(alpha: 0.8),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'LUMINA AI',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _kFrost,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'NEX-GEN LED \u00B7 INTELLIGENT CONTROL',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: _kFrost.withValues(alpha: 0.4),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LayerPill(
                  label: 'FAST',
                  color: _kFast,
                  active: sheetState.isThinking),
              const SizedBox(width: 4),
              _LayerPill(
                  label: 'SMART',
                  color: _kPulse,
                  active: sheetState.isThinking),
              if (sheetState.hasActiveSession) ...[
                const SizedBox(width: 2),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: _kFrost.withValues(alpha: 0.5),
                  tooltip: 'Clear conversation',
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    ref.read(luminaSheetProvider.notifier).clearSession();
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Empty state
  // -------------------------------------------------------------------------

  Widget _buildEmptyState(LuminaSheetState sheetState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _LuminaAvatar(size: 48),
          const SizedBox(height: 16),
          Text(
            '${_greeting()} \u2014 I\'m Lumina',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: _kFrost,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'How can I light up your home?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _kFrost.withValues(alpha: 0.55),
                ),
          ),
          const SizedBox(height: 24),
          _buildSuggestionChips(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Message list
  // -------------------------------------------------------------------------

  Widget _buildMessageList(LuminaSheetState sheetState) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount:
          sheetState.messages.length + (sheetState.isThinking ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == sheetState.messages.length && sheetState.isThinking) {
          return _buildThinkingIndicator();
        }
        final msg = sheetState.messages[i];
        switch (msg.role) {
          case LuminaMessageRole.user:
            return _UserBubble(text: msg.text);
          case LuminaMessageRole.assistant:
            return _AssistantBubble(
              text: msg.text,
              preview: msg.preview,
              wledPayload: msg.wledPayload,
              onApply: msg.wledPayload != null
                  ? () => _applyPattern(
                        msg.wledPayload!,
                        msg.preview,
                        originalPrompt:
                            priorLuminaUserPrompt(sheetState.messages, i),
                      )
                  : null,
            );
          case LuminaMessageRole.thinking:
            return _buildThinkingIndicator();
        }
      },
    );
  }

  // -------------------------------------------------------------------------
  // Suggestion chips
  // -------------------------------------------------------------------------

  Widget _buildSuggestionChips() {
    final suggestions = [
      'Warm white',
      'Sunset vibes',
      'Party mode',
      'Calm & cozy',
      'Surprise me',
      'Game day',
    ];

    // Sized by the chips, not a fixed 36: at large text a fixed-height strip
    // cut the labels off. 36 stays the minimum, so default size looks as before.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < suggestions.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              ActionChip(
                label: Text(
                  suggestions[i],
                  style: const TextStyle(
                    color: _kFrost,
                    fontSize: 13,
                  ),
                ),
                backgroundColor: _kCarbon,
                side: BorderSide(
                  color: NexGenPalette.cyan.withValues(alpha: 0.3),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                onPressed: () => _sendMessage(suggestions[i]),
                // The strip no longer forces a height, so keep the chip at its
                // drawn size instead of a 48-point touch box: same look as
                // before at default size.
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Thinking indicator
  // -------------------------------------------------------------------------

  Widget _buildThinkingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const _LuminaAvatar(size: 20),
          const SizedBox(width: 10),
          const _ThinkingDots(),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Input bar
  // -------------------------------------------------------------------------

  Widget _buildInputBar(LuminaSheetState sheetState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: _kCarbon,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _focusNode.hasFocus
                ? NexGenPalette.cyan.withValues(alpha: 0.5)
                : NexGenPalette.line.withValues(alpha: 0.4),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _startListening();
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NexGenPalette.cyan.withValues(alpha: 0.08),
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none_rounded,
                  color: NexGenPalette.cyan.withValues(alpha: 0.7),
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: _kFrost,
                    ),
                decoration: InputDecoration(
                  hintText: LuminaBrain.contextualPlaceholder(),
                  hintStyle: TextStyle(
                    color: _kFrost.withValues(alpha: 0.3),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                ),
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (text) {
                  if (text.trim().isNotEmpty) _sendMessage(text);
                },
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () {
                if (_hasText) _sendMessage(_textController.text);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: _hasText
                      ? const LinearGradient(
                          colors: [NexGenPalette.cyan, Color(0xFF00B8D4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: _hasText ? null : _kCarbon,
                  border: _hasText
                      ? null
                      : Border.all(
                          color: NexGenPalette.line.withValues(alpha: 0.3),
                        ),
                  boxShadow: _hasText
                      ? [
                          BoxShadow(
                            color: NexGenPalette.cyan.withValues(alpha: 0.4),
                            blurRadius: 10,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 18,
                  color: _hasText ? _kVoid : _kFrost.withValues(alpha: 0.25),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Lumina Avatar
// ===========================================================================

class _LuminaAvatar extends StatelessWidget {
  final double size;
  const _LuminaAvatar({this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: NexGenPalette.cyan.withValues(alpha: 0.13),
        border: Border.all(
          color: NexGenPalette.cyan.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: NexGenPalette.cyan.withValues(alpha: 0.25),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      // The glyph is the avatar's icon, and the circle is a fixed size, so the
      // glyph scales DOWN to fit rather than spilling out of it at large text.
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '\u2726',
            style: TextStyle(
              fontSize: size * 0.46,
              color: NexGenPalette.cyan,
              height: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// FAST / SMART layer pill
// ===========================================================================

class _LayerPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool active;

  const _LayerPill({
    required this.label,
    required this.color,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.6) : color.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: active ? color : color.withValues(alpha: 0.4),
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ===========================================================================
// Three-dot thinking indicator
// ===========================================================================

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_controller.value + i * 0.2) % 1.0;
            final scale = 0.5 + 0.5 * math.sin(phase * math.pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Opacity(
                opacity: 0.35 + 0.65 * scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: NexGenPalette.cyan,
                    boxShadow: [
                      BoxShadow(
                        color: NexGenPalette.cyan.withValues(alpha: 0.5 * scale),
                        blurRadius: 4 * scale,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ===========================================================================
// Meta row: pattern name badge + effect name + color swatches
// ===========================================================================

class _LightingMetaRow extends StatelessWidget {
  final LuminaPatternPreview preview;
  const _LightingMetaRow({required this.preview});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2, left: 36),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (preview.patternName != null && preview.patternName!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: NexGenPalette.cyan.withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
              child: Text(
                preview.patternName!,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: NexGenPalette.cyan,
                ),
              ),
            ),
          if (preview.effectName != null && preview.effectName!.isNotEmpty)
            Text(
              preview.effectName!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _kFrost.withValues(alpha: 0.55),
              ),
            ),
          if (preview.colors.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: preview.colors.take(5).map((c) {
                return Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Chat bubbles
// ===========================================================================

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0A1B4A), NexGenPalette.cyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final String text;
  final LuminaPatternPreview? preview;
  final Map<String, dynamic>? wledPayload;
  final VoidCallback? onApply;

  const _AssistantBubble({
    required this.text,
    this.preview,
    this.wledPayload,
    this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final hasLightingSuggestion =
        preview != null && preview!.colors.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 8, top: 2),
                child: _LuminaAvatar(size: 28),
              ),
              Flexible(
                child: hasLightingSuggestion
                    ? _buildResponseCard(context)
                    : _buildPlainBubble(context),
              ),
            ],
          ),
          if (hasLightingSuggestion) _LightingMetaRow(preview: preview!),
        ],
      ),
    );
  }

  Widget _buildResponseCard(BuildContext context) {
    final suggestion = LuminaLightingSuggestion.fromPreview(
      responseText: text,
      preview: preview!,
      wledPayload: wledPayload,
    );

    return LuminaResponseCard(
      suggestion: suggestion,
      onApply: onApply,
      onAdjust: () {},
      onSaveFavorite: wledPayload != null ? () {} : null,
    );
  }

  Widget _buildPlainBubble(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kCarbon,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(
          color: NexGenPalette.line.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: _kFrost,
            ),
      ),
    );
  }
}