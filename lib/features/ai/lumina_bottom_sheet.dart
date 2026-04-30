import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/app_providers.dart' show activePresetLabelProvider;
import 'package:nexgen_command/features/wled/display_pattern_providers.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_command_router.dart';
import 'package:nexgen_command/features/ai/pattern_label_resolver.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/lumina_waveform_painter.dart';
import 'package:nexgen_command/features/ai/lumina_response_card.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/app_providers.dart' show selectedTabIndexProvider;
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// Brand color constants (visual-only)
// ---------------------------------------------------------------------------

const _kVoid = Color(0xFF07091A);
const _kCarbon = Color(0xFF111527);
const _kFrost = Color(0xFFDCF0FF);
const _kPulse = Color(0xFF6E2FFF); // SMART layer
const _kFast = Color(0xFF00FF9D); // FAST layer

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
// Lumina Avatar — glowing cyan ✦ symbol
// ---------------------------------------------------------------------------

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
      child: Center(
        child: Text(
          '✦',
          style: TextStyle(
            fontSize: size * 0.46,
            color: NexGenPalette.cyan,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FAST / SMART layer pill
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Three-dot thinking indicator
// ---------------------------------------------------------------------------

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
            // Staggered phase: each dot offset by 0.2
            final phase = (_controller.value + i * 0.2) % 1.0;
            // Sine wave for smooth pulse
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

// ---------------------------------------------------------------------------
// Meta row: pattern name badge + effect name + color swatches
// ---------------------------------------------------------------------------

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
          // Pattern name badge
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

          // Effect name
          if (preview.effectName != null && preview.effectName!.isNotEmpty)
            Text(
              preview.effectName!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _kFrost.withValues(alpha: 0.55),
              ),
            ),

          // Color swatches
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

  // Track whether text field has content (for send button glow)
  bool _hasText = false;

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

    _textController.addListener(() {
      final hasText = _textController.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });

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
              final aiName = preview?.patternName ??
                  result.command?.parameters['patternName'] as String?;
              final label = resolveLuminaDisplayName(aiName, prompt);
              if (label != null) {
                ref.read(activePresetLabelProvider.notifier).state = label;
              } else {
                ref.read(activePresetLabelProvider.notifier).clear();
              }
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

      // Sync voice refinement results to the adjustment panel if active
      final adjState = ref.read(adjustmentStateProvider);
      if (adjState != null && adjState.isExpanded && preview != null) {
        final updated = LuminaLightingSuggestion.fromPreview(
          responseText: result.responseText,
          preview: preview,
          wledPayload: result.wledPayload,
        );
        ref.read(adjustmentStateProvider.notifier).applyFromVoice(updated);
      }
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
      // Use go() for within-shell routes so nav bar stays visible;
      // use push() for fullscreen/modal routes (outside shell).
      // Note: '/dashboard/...' (nested home-branch routes like
      // /dashboard/design-studio, /dashboard/my-designs, /dashboard/game-day)
      // must also use go() so the home branch navigates to the nested path
      // instead of pushing on the root navigator.
      final isShellRoute = route.startsWith('/explore') ||
          route.startsWith('/settings') ||
          route.startsWith('/schedule') ||
          route.startsWith('/wled/') ||
          route.startsWith('/dashboard');
      if (isShellRoute) {
        context.go(route);
      } else {
        context.push(route);
      }
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
                // 1. VOID background
                color: _kVoid.withValues(alpha: 0.92),
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
            color: _kFrost.withValues(alpha: 0.25),
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
          // Greeting + branding + layer pills
          Row(
            children: [
              const _LuminaAvatar(size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${_greeting()} — Lumina',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: _kFrost,
                      ),
                ),
              ),
              // 9. Layer pills in header
              _LayerPill(label: 'FAST', color: _kFast, active: sheetState.isThinking),
              const SizedBox(width: 4),
              _LayerPill(label: 'SMART', color: _kPulse, active: sheetState.isThinking),
              if (sheetState.hasActiveSession) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: _kFrost.withValues(alpha: 0.5),
                  tooltip: 'Clear session',
                  onPressed: () {
                    ref.read(luminaSheetProvider.notifier).clearSession();
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'How can I light up your home?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _kFrost.withValues(alpha: 0.55),
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
                color: _kFrost,
                fontSize: 13,
              ),
            ),
            // 2. CARBON surface
            backgroundColor: _kCarbon,
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
                      color: _kFrost,
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
              // 8. Avatar with ✦ symbol
              const _LuminaAvatar(size: 24),
              const SizedBox(width: 8),
              Text(
                'Lumina',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: _kFrost,
                    ),
              ),
              const SizedBox(width: 10),
              // 9. Layer pills in expanded header — glow while thinking
              _LayerPill(label: 'FAST', color: _kFast, active: sheetState.isThinking),
              const SizedBox(width: 4),
              _LayerPill(label: 'SMART', color: _kPulse, active: sheetState.isThinking),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: _kFrost.withValues(alpha: 0.5),
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
        Divider(
          color: NexGenPalette.line.withValues(alpha: 0.4),
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
                        ? () => _applyPattern(
                              msg.wledPayload!,
                              msg.preview,
                              originalPrompt:
                                  _priorUserPrompt(sheetState.messages, i),
                            )
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

  // 6. Three animated cyan dots instead of spinner
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

  Future<void> _applyPattern(
    Map<String, dynamic> wled,
    LuminaPatternPreview? preview, {
    String? originalPrompt,
  }) async {
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
        final aiName = preview?.patternName ?? wled['patternName'] as String?;
        final label = resolveLuminaDisplayName(aiName, originalPrompt);
        if (label != null) {
          ref.read(activePresetLabelProvider.notifier).state = label;
        } else {
          ref.read(activePresetLabelProvider.notifier).clear();
        }
        final displayLabel = ref.read(displayPatternNameProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$displayLabel applied!')),
        );
      }
    } catch (e) {
      debugPrint('Apply from sheet failed: $e');
    }
  }

  /// Walks back from [assistantIndex] to find the prompt that produced the
  /// bubble at that index. Used by the bubble-tap apply path.
  String? _priorUserPrompt(List<LuminaMessage> messages, int assistantIndex) {
    for (int i = assistantIndex - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.role == LuminaMessageRole.user && m.text.trim().isNotEmpty) {
        return m.text;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Input bar
  // -------------------------------------------------------------------------

  Widget _buildInputBar(LuminaSheetState sheetState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          // 2. CARBON surface for input bar
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
            // Mic button (left side)
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
                      // 3. FROST text
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
            // 7. Rounded square send button with up arrow
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
    // If there's a lighting preview, render the full response card
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
              // 8. Lumina avatar with ✦
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
          // 10. Meta row after assistant messages with lighting data
          if (hasLightingSuggestion) _LightingMetaRow(preview: preview!),
        ],
      ),
    );
  }

  /// Full response card with preview, parameter summary, and actions.
  Widget _buildResponseCard(BuildContext context) {
    final suggestion = LuminaLightingSuggestion.fromPreview(
      responseText: text,
      preview: preview!,
      wledPayload: wledPayload,
    );

    return LuminaResponseCard(
      suggestion: suggestion,
      onApply: onApply,
      onAdjust: () {
        // Placeholder for expanding inline adjustment panel
      },
      onSaveFavorite: wledPayload != null
          ? () {
              // Placeholder for save-as-favorite flow
            }
          : null,
    );
  }

  /// Simple text-only bubble for conversational responses without lighting data.
  Widget _buildPlainBubble(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        // 2. CARBON surface
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
              // 3. FROST text
              color: _kFrost,
            ),
      ),
    );
  }
}
