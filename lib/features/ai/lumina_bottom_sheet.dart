import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/app_providers.dart' show activePresetLabelProvider;
import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_command_router.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/lumina_waveform_painter.dart';
import 'package:nexgen_command/features/ai/light_preview_strip.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/dashboard/main_scaffold.dart' show selectedTabIndexProvider;
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Public API: show the Lumina sheet
// ---------------------------------------------------------------------------

/// Shows the Lumina voice assistant bottom sheet.
///
/// [mode] determines the initial size and state:
///  - `compact` (~30%) with text input and suggestions
///  - `listening` (~40%) with mic active and waveform
Future<void> showLuminaSheet(
  BuildContext context,
  WidgetRef ref, {
  LuminaSheetMode mode = LuminaSheetMode.compact,
}) async {
  final controller = ref.read(luminaSheetProvider.notifier);

  // Don't open twice
  if (ref.read(luminaSheetProvider).isOpen) return;

  if (mode == LuminaSheetMode.listening) {
    controller.openListening();
  } else {
    controller.openCompact();
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.3),
    useSafeArea: true,
    builder: (_) => const _LuminaSheetBody(),
  );

  // Sheet was dismissed
  controller.close();
}

// ---------------------------------------------------------------------------
// Sheet body (root widget inside the modal)
// ---------------------------------------------------------------------------

class _LuminaSheetBody extends ConsumerStatefulWidget {
  const _LuminaSheetBody();

  @override
  ConsumerState<_LuminaSheetBody> createState() => _LuminaSheetBodyState();
}

class _LuminaSheetBodyState extends ConsumerState<_LuminaSheetBody>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Speech recognition
  late final stt.SpeechToText _speech;
  bool _speechAvailable = false;
  bool _isListening = false;
  double _micAmplitude = 0.0;

  // Waveform animation
  late final AnimationController _waveAnim;

  // Pulse animation for mic button in listening state
  late final AnimationController _pulseAnim;

  // DraggableScrollableSheet controller
  final DraggableScrollableController _dragController =
      DraggableScrollableController();

  // Snap sizes: compact 0.33, listening 0.42, expanded 0.85
  static const double _compactSize = 0.33;
  static const double _listeningSize = 0.42;
  static const double _expandedSize = 0.85;
  static const double _minSize = 0.15;

  // Silence timer for auto-stop
  Timer? _silenceTimer;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();

    _waveAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // If opened in listening mode, start mic after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sheetState = ref.read(luminaSheetProvider);
      if (sheetState.mode == LuminaSheetMode.listening) {
        _startListening();
      }
      // Animate to initial size
      _animateToMode(sheetState.mode);
    });
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _speech.stop();
    _waveAnim.dispose();
    _pulseAnim.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _dragController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Size helpers
  // -------------------------------------------------------------------------

  double _sizeForMode(LuminaSheetMode mode) {
    switch (mode) {
      case LuminaSheetMode.compact:
        return _compactSize;
      case LuminaSheetMode.listening:
        return _listeningSize;
      case LuminaSheetMode.expanded:
        return _expandedSize;
    }
  }

  void _animateToMode(LuminaSheetMode mode) {
    try {
      _dragController.animateTo(
        _sizeForMode(mode),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      // Controller may not be attached yet
    }
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
      ref.read(luminaSheetProvider.notifier).setMode(LuminaSheetMode.listening);
      _animateToMode(LuminaSheetMode.listening);

      await _speech.listen(
        onResult: (result) {
          if (!mounted) return;
          final words = result.recognizedWords;

          ref.read(luminaSheetProvider.notifier).updateTranscription(words);

          // Reset silence timer on new speech
          _silenceTimer?.cancel();
          if (words.isNotEmpty) {
            _silenceTimer = Timer(const Duration(seconds: 2), () {
              if (mounted && _isListening) {
                _stopListening(submit: true);
              }
            });
          }

          // Simulate amplitude from word count changes
          setState(() {
            _micAmplitude =
                result.finalResult ? 0.0 : (0.3 + (words.length % 5) * 0.14);
          });

          if (result.finalResult && words.isNotEmpty) {
            _stopListening(submit: true);
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
      _micAmplitude = 0.0;
    });

    if (submit) {
      final transcript = ref.read(luminaSheetProvider).transcription.trim();
      if (transcript.isNotEmpty) {
        _sendMessage(transcript);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Send message / conversation
  // -------------------------------------------------------------------------

  Future<void> _sendMessage(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty) return;

    _textController.clear();
    _focusNode.unfocus();

    final controller = ref.read(luminaSheetProvider.notifier);
    controller.addUserMessage(prompt);
    controller.updateTranscription('');
    _animateToMode(LuminaSheetMode.expanded);
    _scrollToEnd();

    try {
      final sheetState = ref.read(luminaSheetProvider);

      // Route through the two-tier command pipeline
      final result = await LuminaCommandRouter.route(
        ref,
        prompt,
        history: sheetState.messages,
        activePatternContext: sheetState.activePatternContext,
      );

      // Handle navigation commands (close sheet and navigate)
      if (result.command?.type == LuminaCommandType.navigate) {
        _handleNavigation(result);
        return;
      }

      // Apply WLED payload to lights if available
      LuminaPatternPreview? preview;
      if (result.wledPayload != null) {
        preview = _extractPreview(result.wledPayload!);
        final repo = ref.read(wledRepositoryProvider);
        if (repo != null) {
          try {
            final ok = await repo.applyJson(result.wledPayload!);
            if (ok && mounted) {
              if (preview != null) {
                ref.read(wledStateProvider.notifier).setLuminaPatternMetadata(
                      colorSequence: preview.colors,
                      colorNames: preview.colorNames,
                      effectName: preview.effectName,
                    );
              }
              final label = preview?.patternName ??
                  result.command?.parameters['patternName'] as String? ??
                  'Lumina Pattern';
              ref.read(activePresetLabelProvider.notifier).state = label;
            }
          } catch (e) {
            debugPrint('Apply from Lumina sheet failed: $e');
          }
        }
      } else if (result.previewColors.isNotEmpty) {
        // Build a preview from colors even without full WLED payload
        preview = LuminaPatternPreview(colors: result.previewColors);
      }

      controller.addAssistantMessage(
        result.responseText,
        preview: preview,
        wledPayload: result.wledPayload,
      );
    } catch (e) {
      debugPrint('Lumina sheet send error: $e');
      controller.addAssistantMessage('I hit a snag: $e');
    }

    _scrollToEnd();
  }

  /// Handles navigation commands by closing the sheet and navigating.
  void _handleNavigation(LuminaCommandResult result) {
    final params = result.command?.parameters ?? {};
    final route = params['route'] as String?;
    final tabIndex = params['tabIndex'] as int?;

    // Close the sheet first
    Navigator.of(context).pop();

    if (tabIndex != null) {
      ref.read(selectedTabIndexProvider.notifier).state = tabIndex;
    } else if (route != null && mounted) {
      context.push(route);
    }

    ref.read(luminaSheetProvider.notifier).addAssistantMessage(
          result.responseText,
        );
  }

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
  // Preview extraction helper
  // -------------------------------------------------------------------------

  LuminaPatternPreview? _extractPreview(Map<String, dynamic> payload) {
    try {
      String? patternName = payload['patternName'] as String?;
      String? effectName;
      String? direction;
      bool isStatic = false;
      int? speed;
      int? intensity;
      List<String> colorNames = [];
      List<Color> colors = [];

      // Rich colors array
      final colorsArray = payload['colors'];
      if (colorsArray is List) {
        for (final c in colorsArray) {
          if (c is Map) {
            final name = c['name'] as String?;
            if (name != null) colorNames.add(name);
            final rgb = c['rgb'];
            if (rgb is List && rgb.length >= 3) {
              colors.add(Color.fromARGB(
                255,
                (rgb[0] as num).toInt(),
                (rgb[1] as num).toInt(),
                (rgb[2] as num).toInt(),
              ));
            }
          }
        }
      }

      // Rich effect object
      final effectObj = payload['effect'];
      int? effect;
      if (effectObj is Map) {
        effectName = effectObj['name'] as String?;
        effect = (effectObj['id'] as num?)?.toInt();
        direction = effectObj['direction'] as String?;
        isStatic = effectObj['isStatic'] == true;
      }

      speed = (payload['speed'] as num?)?.toInt();
      intensity = (payload['intensity'] as num?)?.toInt();

      // Fallback to wled segment data
      final wled = payload['wled'] ?? payload;
      final seg = wled['seg'];
      int? pal;
      if (seg is List && seg.isNotEmpty && seg.first is Map) {
        final first = seg.first as Map;
        effect ??= (first['fx'] as num?)?.toInt();
        pal = (first['pal'] as num?)?.toInt();
        speed ??= (first['sx'] as num?)?.toInt();
        intensity ??= (first['ix'] as num?)?.toInt();

        if (colors.isEmpty) {
          final col = first['col'];
          if (col is List) {
            for (final c in col) {
              if (c is List && c.length >= 3) {
                colors.add(Color.fromARGB(
                  255,
                  (c[0] as num).toInt(),
                  (c[1] as num).toInt(),
                  (c[2] as num).toInt(),
                ));
              }
            }
          }
        }
      }

      if (colors.isEmpty) {
        colors = const [NexGenPalette.cyan, Color(0xFF102040)];
      }

      return LuminaPatternPreview(
        patternName: patternName,
        colors: colors.take(5).toList(),
        colorNames: colorNames,
        effectId: effect,
        effectName: effectName,
        direction: direction,
        isStatic: isStatic,
        speed: speed,
        intensity: intensity,
        paletteId: pal,
      );
    } catch (e) {
      debugPrint('extractPreview failed: $e');
      return null;
    }
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
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final sheetState = ref.watch(luminaSheetProvider);

    // Listen for mode changes from provider (e.g. addUserMessage sets expanded)
    ref.listen<LuminaSheetState>(luminaSheetProvider, (prev, next) {
      if (prev?.mode != next.mode) {
        _animateToMode(next.mode);
      }
    });

    return DraggableScrollableSheet(
      controller: _dragController,
      initialChildSize: _sizeForMode(sheetState.mode),
      minChildSize: _minSize,
      maxChildSize: _expandedSize,
      snap: true,
      snapSizes: const [_compactSize, _listeningSize, _expandedSize],
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Container(
              decoration: BoxDecoration(
                color: NexGenPalette.matteBlack.withValues(alpha: 0.85),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: NexGenPalette.cyan.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  // Drag handle
                  _buildDragHandle(),

                  // Content area
                  Expanded(
                    child: _buildContent(sheetState, scrollController),
                  ),

                  // Input bar (always visible except in listening)
                  if (sheetState.mode != LuminaSheetMode.listening)
                    _buildInputBar(sheetState),

                  SizedBox(
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 8
                          : MediaQuery.of(context).padding.bottom + 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Drag handle
  // -------------------------------------------------------------------------

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: NexGenPalette.textMedium.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Content routing
  // -------------------------------------------------------------------------

  Widget _buildContent(
      LuminaSheetState sheetState, ScrollController scrollController) {
    switch (sheetState.mode) {
      case LuminaSheetMode.compact:
        return _buildCompactContent(sheetState);
      case LuminaSheetMode.listening:
        return _buildListeningContent(sheetState);
      case LuminaSheetMode.expanded:
        return _buildExpandedContent(sheetState, scrollController);
    }
  }

  // -------------------------------------------------------------------------
  // COMPACT STATE
  // -------------------------------------------------------------------------

  Widget _buildCompactContent(LuminaSheetState sheetState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          // Greeting + branding
          Row(
            children: [
              Image.asset(
                'assets/images/Gemini_Generated_Image_n4fr1en4fr1en4fr.png',
                height: 28,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.auto_awesome_rounded,
                  color: NexGenPalette.cyan,
                  size: 28,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_greeting()} — Lumina',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: NexGenPalette.textHigh,
                      ),
                ),
              ),
              if (sheetState.hasActiveSession)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: NexGenPalette.textMedium,
                  tooltip: 'Clear session',
                  onPressed: () {
                    ref.read(luminaSheetProvider.notifier).clearSession();
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'How can I light up your home?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),
          const SizedBox(height: 16),
          // Quick suggestion chips
          _buildSuggestionChips(),
        ],
      ),
    );
  }

  Widget _buildSuggestionChips() {
    final suggestions = [
      'Warm white',
      'Sunset vibes',
      'Party mode',
      'Calm & cozy',
      'Surprise me',
      'Game day',
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          return ActionChip(
            label: Text(
              suggestions[i],
              style: const TextStyle(
                color: NexGenPalette.textHigh,
                fontSize: 13,
              ),
            ),
            backgroundColor: NexGenPalette.gunmetal,
            side: BorderSide(
              color: NexGenPalette.cyan.withValues(alpha: 0.3),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            onPressed: () => _sendMessage(suggestions[i]),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // LISTENING STATE
  // -------------------------------------------------------------------------

  Widget _buildListeningContent(LuminaSheetState sheetState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // "Lumina is listening..." header with pulse
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, child) {
              return Opacity(
                opacity: 0.6 + _pulseAnim.value * 0.4,
                child: Text(
                  'Lumina is listening...',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: NexGenPalette.cyan,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          // Waveform visualization
          SizedBox(
            height: 60,
            child: AnimatedBuilder(
              animation: _waveAnim,
              builder: (context, _) {
                return CustomPaint(
                  size: Size(MediaQuery.of(context).size.width - 40, 60),
                  painter: LuminaWaveformPainter(
                    amplitude: _micAmplitude,
                    phase: _waveAnim.value,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Live transcription
          if (sheetState.transcription.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                sheetState.transcription,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: NexGenPalette.textHigh,
                    ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: 20),

          // Large pulsing mic button
          GestureDetector(
            onTap: () => _stopListening(submit: true),
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, _) {
                final scale = 1.0 + _pulseAnim.value * 0.08;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: NexGenPalette.cyan.withValues(alpha: 0.15),
                      border: Border.all(
                        color: NexGenPalette.cyan,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: NexGenPalette.cyan.withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mic_rounded,
                      color: NexGenPalette.cyan,
                      size: 30,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // EXPANDED / CONVERSATIONAL STATE
  // -------------------------------------------------------------------------

  Widget _buildExpandedContent(
      LuminaSheetState sheetState, ScrollController scrollController) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Image.asset(
                'assets/images/Gemini_Generated_Image_n4fr1en4fr1en4fr.png',
                height: 24,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.auto_awesome_rounded,
                  color: NexGenPalette.cyan,
                  size: 24,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Lumina',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: NexGenPalette.textHigh,
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: NexGenPalette.textMedium,
                tooltip: 'Clear conversation',
                onPressed: () {
                  ref.read(luminaSheetProvider.notifier).clearSession();
                  ref
                      .read(luminaSheetProvider.notifier)
                      .setMode(LuminaSheetMode.compact);
                },
              ),
            ],
          ),
        ),
        const Divider(
          color: NexGenPalette.line,
          height: 1,
          indent: 20,
          endIndent: 20,
        ),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            itemCount: sheetState.messages.length +
                (sheetState.isThinking ? 1 : 0),
            itemBuilder: (context, i) {
              // Thinking indicator
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
                        ? () => _applyPattern(msg.wledPayload!, msg.preview)
                        : null,
                  );
                case LuminaMessageRole.thinking:
                  return _buildThinkingIndicator();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildThinkingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: NexGenPalette.cyan.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Lumina is thinking...',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: NexGenPalette.textMedium,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyPattern(
      Map<String, dynamic> wled, LuminaPatternPreview? preview) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;

    try {
      final ok = await repo.applyJson(wled);
      if (ok && mounted) {
        if (preview != null) {
          ref.read(wledStateProvider.notifier).setLuminaPatternMetadata(
                colorSequence: preview.colors,
                colorNames: preview.colorNames,
                effectName: preview.effectName,
              );
        }
        final label = preview?.patternName ?? 'Lumina Pattern';
        ref.read(activePresetLabelProvider.notifier).state = label;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label applied!')),
        );
      }
    } catch (e) {
      debugPrint('Apply from sheet failed: $e');
    }
  }

  // -------------------------------------------------------------------------
  // Input bar
  // -------------------------------------------------------------------------

  Widget _buildInputBar(LuminaSheetState sheetState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: _focusNode.hasFocus
                ? NexGenPalette.cyan.withValues(alpha: 0.5)
                : NexGenPalette.line,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: NexGenPalette.textHigh,
                    ),
                decoration: InputDecoration(
                  hintText: 'Ask Lumina anything...',
                  hintStyle: TextStyle(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.6),
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
            // Mic button
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _startListening();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NexGenPalette.cyan.withValues(alpha: 0.12),
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none_rounded,
                  color: NexGenPalette.cyan,
                  size: 22,
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
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0A1B4A), NexGenPalette.cyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lumina avatar
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NexGenPalette.cyan.withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: NexGenPalette.cyan,
              size: 16,
            ),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Text response
                Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: NexGenPalette.gunmetal,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(
                      color: NexGenPalette.line,
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: NexGenPalette.textHigh,
                        ),
                  ),
                ),

                // LED preview strip
                if (preview != null && preview!.colors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  LightPreviewStrip(
                    colors: preview!.colors,
                    ledCount: 20,
                    ledSize: 8,
                  ),
                ],

                // Action buttons
                if (wledPayload != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (onApply != null)
                        _ActionChip(
                          label: 'Apply',
                          icon: Icons.bolt_rounded,
                          onTap: onApply!,
                          primary: true,
                        ),
                      _ActionChip(
                        label: 'Adjust',
                        icon: Icons.tune_rounded,
                        onTap: () {
                          // Focus input for refinement
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: primary
                ? NexGenPalette.cyan.withValues(alpha: 0.15)
                : NexGenPalette.gunmetal,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primary
                  ? NexGenPalette.cyan.withValues(alpha: 0.5)
                  : NexGenPalette.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: primary ? NexGenPalette.cyan : NexGenPalette.textMedium,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: primary
                      ? NexGenPalette.cyan
                      : NexGenPalette.textHigh,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
