import 'dart:async';
import 'dart:math' as math;

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
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/lumina_response_card.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';
import 'package:nexgen_command/services/autopilot_scheduler.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/app_providers.dart' show selectedTabIndexProvider;
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

  Future<void> _sendMessage(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty) return;

    _textController.clear();
    _focusNode.unfocus();

    final controller = ref.read(luminaSheetProvider.notifier);
    controller.addUserMessage(prompt);
    controller.updateTranscription('');
    _scrollToEnd();

    try {
      final sheetState = ref.read(luminaSheetProvider);

      final result = await LuminaCommandRouter.route(
        ref,
        prompt,
        history: sheetState.messages,
        activePatternContext: sheetState.activePatternContext,
      );

      // Handle navigation commands
      if (result.command?.type == LuminaCommandType.navigate) {
        _handleNavigation(result);
        return;
      }

      // ── Schedule detection ────────────────────────────────────────────────
      // When the AI returns a multi-day schedule plan, we apply night 1 as a
      // live preview and route the full plan to the scheduling system.
      if (result.wledPayload != null &&
          result.wledPayload!['isSchedule'] == true) {
        await _handleScheduleResult(result);
        return;
      }

      // ── Scheduling intent (recurring weekly/daily) ────────────────────────
      // The AI emits `schedulingIntent` in its JSON when the user asks for a
      // recurring or future schedule (e.g. "every Thursday at sunset"). We
      // post the AI's confirmation message to the chat, then offer a one-tap
      // SnackBar action to persist a ScheduleItem.
      final schedulingIntent = result.wledPayload?['schedulingIntent'];
      if (schedulingIntent is Map) {
        await _handleSchedulingIntent(
          Map<String, dynamic>.from(schedulingIntent),
          result,
        );
        return;
      }

      // ── Normal single-pattern apply ───────────────────────────────────────
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
                  result.command?.parameters['patternName'] as String?;
              if (label != null) {
                ref.read(activePresetLabelProvider.notifier).state = label;
              } else {
                ref.read(activePresetLabelProvider.notifier).clear();
              }
            }
          } catch (e) {
            debugPrint('Apply from Lumina screen failed: $e');
          }
        }
      } else if (result.previewColors.isNotEmpty) {
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
      debugPrint('Lumina screen send error: $e');
      controller.addAssistantMessage('I hit a snag: $e');
    }

    _scrollToEnd();
  }

  /// Handles a smart schedule result from the AI.
  ///
  /// 1. Applies the FIRST occurrence as a live preview so the user
  ///    immediately sees something on their lights.
  /// 2. Routes the full schedule to [AutopilotScheduler.importSmartSchedule].
  ///    Night 1 is already applied — the scheduler marks it approved and
  ///    queues/suggests nights 2+ based on the user's autonomy level.
  /// 3. Posts the conversational response card to the chat thread.
  Future<void> _handleScheduleResult(LuminaCommandResult result) async {
    final payload = result.wledPayload!;
    final schedule = payload['schedule'] as List<dynamic>?;
    final dayCount = payload['dayCount'] as int? ?? 0;
    final hasVariety = payload['hasVariety'] as bool? ?? false;
    final controller = ref.read(luminaSheetProvider.notifier);

    debugPrint('📅 Smart schedule: $dayCount days, hasVariety=$hasVariety');

    // Step 1 — Apply night 1 as immediate live preview
    if (schedule != null && schedule.isNotEmpty) {
      final firstWled =
          (schedule.first as Map<String, dynamic>?)?['wled'] as Map<String, dynamic>?;
      if (firstWled != null) {
        final repo = ref.read(wledRepositoryProvider);
        if (repo != null) {
          try {
            await repo.applyJson(firstWled);
            debugPrint('📅 Night 1 preview applied to lights');
          } catch (e) {
            debugPrint('📅 Night 1 preview apply failed: $e');
          }
        }
      }
    }

    // Step 2 — Hand full plan off to AutopilotScheduler.
    // Night 1 is already applied above; the scheduler marks it approved so
    // the check loop never re-fires it. Nights 2+ are queued as suggestions
    // (autonomy level 1) or auto-scheduled (autonomy level 2).
    try {
      await ref.read(autopilotSchedulerProvider).importSmartSchedule(payload);
      debugPrint('📅 Imported $dayCount-night schedule into AutopilotScheduler');
    } catch (e) {
      debugPrint('📅 Schedule import failed: $e');
    }

    // Step 3 — Build preview strip from night 1 colors for the response card
    LuminaPatternPreview? preview;
    if (schedule != null && schedule.isNotEmpty) {
      final first = schedule.first as Map<String, dynamic>?;
      if (first != null) {
        final firstWled = first['wled'] as Map<String, dynamic>?;
        if (firstWled != null) preview = _extractPreview(firstWled);
      }
    }
    preview ??= result.previewColors.isNotEmpty
        ? LuminaPatternPreview(colors: result.previewColors)
        : null;

    // Set the preset label to the full schedule name
    final scheduleLabel = payload['patternName'] as String?;
    if (scheduleLabel != null && mounted) {
      ref.read(activePresetLabelProvider.notifier).state = scheduleLabel;
    }

    // Step 4 — Post response card to chat thread
    controller.addAssistantMessage(
      result.responseText,
      preview: preview,
      wledPayload: payload,
    );

    _scrollToEnd();
  }

  /// Handles a recurring/future scheduling intent from the AI.
  ///
  /// The AI emits `schedulingIntent` in its JSON when the user's request
  /// implies a recurring schedule ("every Thursday at sunset", "warm white
  /// nightly"). We post the AI's confirmation to the chat thread, then offer
  /// a one-tap SnackBar action to persist a ScheduleItem via [schedulesProvider].
  Future<void> _handleSchedulingIntent(
    Map<String, dynamic> intent,
    LuminaCommandResult result,
  ) async {
    final controller = ref.read(luminaSheetProvider.notifier);

    // Show a preview if the AI returned light data alongside the schedule
    LuminaPatternPreview? preview;
    if (result.wledPayload != null) {
      preview = _extractPreview(result.wledPayload!);
    } else if (result.previewColors.isNotEmpty) {
      preview = LuminaPatternPreview(colors: result.previewColors);
    }

    // Post the AI's response to the chat thread first so the user sees the
    // confirmation message Claude crafted.
    controller.addAssistantMessage(
      result.responseText,
      preview: preview,
      wledPayload: result.wledPayload,
    );

    _scrollToEnd();

    // Pull the schedule fields. ScheduleItem.repeatDays expects three-letter
    // day codes ('Sun','Mon',…); the prompt instructs the AI to emit them
    // that way, but we fall back to the full week for safety.
    final timeLabel = intent['timeLabel'] as String? ?? 'Sunset';
    final offTimeLabel = intent['offTimeLabel'] as String?;
    final repeatDays = (intent['repeatDays'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final patternName = intent['patternName'] as String? ?? 'Custom';

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Add "$patternName" to your schedule at $timeLabel?',
          style: const TextStyle(color: _kFrost),
        ),
        backgroundColor: NexGenPalette.gunmetal90,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Add',
          textColor: NexGenPalette.cyan,
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              final item = ScheduleItem(
                id: 'ai-${DateTime.now().millisecondsSinceEpoch}',
                timeLabel: timeLabel,
                offTimeLabel: offTimeLabel,
                repeatDays: repeatDays,
                actionLabel: 'Pattern: $patternName',
                enabled: true,
                wledPayload: result.wledPayload,
              );
              await ref.read(schedulesProvider.notifier).add(item);
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: const Text('Schedule added'),
                  backgroundColor: Colors.green.shade700,
                  duration: const Duration(seconds: 2),
                ),
              );
            } catch (e) {
              debugPrint('Schedule add from Lumina screen failed: $e');
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Could not add schedule: $e'),
                  backgroundColor: Colors.red.shade700,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  void _handleNavigation(LuminaCommandResult result) {
    final params = result.command?.parameters ?? {};
    final route = params['route'] as String?;
    final tabIndex = params['tabIndex'] as int?;

    Navigator.of(context).pop();

    if (tabIndex != null) {
      ref.read(selectedTabIndexProvider.notifier).state = tabIndex;
    } else if (route != null && mounted) {
      final isShellRoute = route.startsWith('/explore') ||
          route.startsWith('/settings') ||
          route.startsWith('/schedule') ||
          route.startsWith('/wled/') ||
          route == '/dashboard';
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
  // Apply pattern from bubble
  // -------------------------------------------------------------------------

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
        final label = preview?.patternName ??
            wled['patternName'] as String?;
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
      debugPrint('Apply from screen failed: $e');
    }
  }

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
                  ? () => _applyPattern(msg.wledPayload!, msg.preview)
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
      child: Center(
        child: Text(
          '\u2726',
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