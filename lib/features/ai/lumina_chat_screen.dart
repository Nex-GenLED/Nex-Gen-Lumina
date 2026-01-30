import 'dart:async';
import 'dart:ui';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/openai/openai_config.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/ai/suggestion_history.dart';
import 'package:nexgen_command/features/ai/vibe_feedback_dialog.dart';
import 'package:nexgen_command/features/wled/semantic_pattern_matcher.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/services/architectural_parser_service.dart';
import 'package:nexgen_command/services/segment_pattern_generator.dart';
import 'package:nexgen_command/services/pattern_analytics_service.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class LuminaChatScreen extends ConsumerStatefulWidget {
  const LuminaChatScreen({super.key});

  @override
  ConsumerState<LuminaChatScreen> createState() => _LuminaChatScreenState();
}

class _LuminaChatScreenState extends ConsumerState<LuminaChatScreen> with TickerProviderStateMixin {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();

  // Static list to persist messages across tab navigation
  static final List<_Msg> _messages = [];
  bool _isThinking = false;
  bool _listening = false;
  late final stt.SpeechToText _speech;
  late final AnimationController _pulse;

  // === Active Pattern Context ===
  // Stores the currently displayed pattern for refinement operations.
  // When user taps "make it slower", we modify this instead of doing a new search.
  // Static to persist across tab navigation
  static Map<String, dynamic>? _activePatternContext;
  static _PatternPreview? _activePreview;

  // === Preview preparation ===
  // Cached background image for real-time previews (user's house or placeholder)
  ImageProvider<Object>? _houseImageProvider;
  // Controls visibility of the upcoming preview bar (static to persist)
  static bool showPreviewBar = false;
  // Colors currently previewed (updated when a new pattern is proposed, static to persist)
  static List<Color> currentPreviewColors = [];
  // Slide up/down animation controller for the preview bar
  late final AnimationController _previewBarAnim;

  // === Feedback Tracking ===
  // Track the last query for feedback recording (static to persist)
  static String? _lastQueryForFeedback;
  
  Future<void> _handleThumbsUp(_Msg msg) async {
    // Update UI immediately to show feedback was received
    setState(() {
      msg.feedbackGiven = true;
    });
    try {
      final user = ref.read(authStateProvider).maybeWhen(data: (u) => u, orElse: () => null);
      if (user == null) return;
      final svc = ref.read(userServiceProvider);
      final colorNames = msg.preview != null ? msg.preview!.colors.take(3).map(_colorName).toList() : <String>[];

      // Record to user-specific preferences
      await svc.logPatternUsage(
        userId: user.uid,
        colorNames: colorNames,
        effectId: msg.preview?.effectId,
        paletteId: msg.preview?.paletteId,
        wled: msg.wledPayload,
      );

      // Record to global analytics for cross-user learning
      if (msg.wledPayload != null && _lastQueryForFeedback != null) {
        final analyticsService = ref.read(patternAnalyticsServiceProvider);
        final colors = msg.preview?.colors.map((c) => [c.red, c.green, c.blue]).toList() ?? <List<int>>[];
        await analyticsService.recordThumbsUp(
          query: _lastQueryForFeedback!,
          effectId: msg.preview?.effectId ?? 0,
          effectName: msg.preview?.effectName ?? 'Unknown',
          colors: colors,
          colorNames: msg.preview?.colorNames ?? colorNames,
          userId: user.uid,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks! I\'ll suggest more like this.')));
      }
    } catch (e) {
      debugPrint('ThumbsUp failed: $e');
    }
  }

  Future<bool?> _showRunSetupSheet(BuildContext context, {required Map<String, dynamic> wled, _PatternPreview? preview, required String fallbackText}) async {
    return showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      backgroundColor: NexGenPalette.gunmetal90,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Text('Run setup?', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(color: NexGenPalette.textHigh)),
              ]),
              const SizedBox(height: 10),
              Text(fallbackText, style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: NexGenPalette.textMedium)),
              const SizedBox(height: 12),
              if (preview != null) _PatternTile(preview: preview),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    icon: const Icon(Icons.bolt_rounded, color: Colors.black),
                    label: const Text('Apply to Lights', style: TextStyle(color: Colors.black)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    icon: const Icon(Icons.visibility_rounded, color: NexGenPalette.textHigh),
                    label: const Text('Preview only'),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Not now'),
                ),
              )
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleThumbsDown(_Msg msg) async {
    try {
      // Use enhanced feedback dialog for richer vibe clarification
      final result = await showEnhancedFeedbackDialog(context);
      if (result == null) return;

      // Update UI immediately to show feedback was received
      setState(() {
        msg.feedbackGiven = false;
      });

      final user = ref.read(authStateProvider).maybeWhen(data: (u) => u, orElse: () => null);
      if (user == null) return;

      final svc = ref.read(userServiceProvider);
      final analyticsService = ref.read(patternAnalyticsServiceProvider);

      // Map feedback type to dislike keywords for user-specific preferences
      final List<String> keywords = [];
      if (result.feedbackType == 'Wrong Colors') {
        final names = msg.preview != null ? msg.preview!.colors.take(2).map(_colorName).toList() : <String>[];
        if (names.isNotEmpty) {
          keywords.addAll(names);
        } else {
          keywords.add('Colors');
        }
      } else if (result.feedbackType == 'Too Fast') {
        keywords.add('Fast');
      } else if (result.feedbackType == 'Too Slow') {
        keywords.add('Slow');
      } else if (result.feedbackType == 'Wrong Vibe') {
        keywords.add('Wrong Vibe');
        // If user specified a desired vibe, record it for learning
        if (result.desiredVibe != null) {
          keywords.add(result.desiredVibe!);
        }
      } else if (result.feedbackType == 'Too Bright') {
        keywords.add('Bright');
      }

      // Record user-specific dislikes
      for (final k in keywords) {
        await svc.addDislike(user.uid, k);
      }

      // Record to global analytics for cross-user learning
      if (_lastQueryForFeedback != null) {
        // Build feedback reason string
        String reason = result.feedbackType;
        if (result.desiredVibe != null && result.desiredVibe != 'custom') {
          reason = '${result.feedbackType}: wanted ${result.desiredVibe}';
        } else if (result.customFeedback != null) {
          reason = '${result.feedbackType}: ${result.customFeedback}';
        }

        await analyticsService.recordThumbsDown(
          query: _lastQueryForFeedback!,
          effectId: msg.preview?.effectId ?? 0,
          effectName: msg.preview?.effectName ?? 'Unknown',
          reason: reason,
          userId: user.uid,
        );

        // If this was a "Wrong Vibe" feedback with clarification, record vibe correction
        if (result.feedbackType == 'Wrong Vibe' && result.desiredVibe != null) {
          // Detect what vibe the AI thought it was providing
          final detectedVibe = _detectVibeFromPattern(msg.preview);
          final desiredVibe = result.desiredVibe == 'custom'
              ? result.customFeedback ?? 'unknown'
              : result.desiredVibe!;

          await analyticsService.recordVibeCorrection(
            query: _lastQueryForFeedback!,
            detectedVibe: detectedVibe,
            desiredVibe: desiredVibe,
            originalEffectId: msg.preview?.effectId,
            userId: user.uid,
          );
        }
      }

      if (mounted) {
        String snackMessage = 'Got it — I\'ll improve next time.';
        if (result.desiredVibe != null && result.desiredVibe != 'custom') {
          snackMessage = 'Got it — I\'ll aim for ${result.desiredVibe!.toLowerCase()} next time.';
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(snackMessage)));
      }
    } catch (e) {
      debugPrint('ThumbsDown failed: $e');
    }
  }

  /// Attempts to detect what vibe the AI intended based on the pattern preview.
  String _detectVibeFromPattern(_PatternPreview? preview) {
    if (preview == null) return 'unknown';

    // Check effect name for vibe hints
    final effectName = preview.effectName?.toLowerCase() ?? '';
    if (effectName.contains('chase') || effectName.contains('running')) return 'energetic';
    if (effectName.contains('breathe') || effectName.contains('fade')) return 'calm';
    if (effectName.contains('twinkle') || effectName.contains('sparkle')) return 'playful';
    if (effectName.contains('rainbow') || effectName.contains('colorful')) return 'vibrant';
    if (effectName.contains('pulse')) return 'dynamic';
    if (effectName.contains('solid') || effectName.contains('static')) return 'subtle';

    // Check colors for vibe hints
    final hasWarm = preview.colors.any((c) {
      final hsv = HSVColor.fromColor(c);
      return hsv.hue < 60 || hsv.hue > 300;
    });
    final hasCool = preview.colors.any((c) {
      final hsv = HSVColor.fromColor(c);
      return hsv.hue >= 180 && hsv.hue <= 270;
    });

    if (hasWarm && !hasCool) return 'warm';
    if (hasCool && !hasWarm) return 'cool';

    return 'balanced';
  }

  /// Records a pattern application to the global analytics service for cross-user learning.
  Future<void> _recordPatternApplied(String query, _PatternPreview? preview, Map<String, dynamic> wledPayload) async {
    try {
      final user = ref.read(authStateProvider).maybeWhen(data: (u) => u, orElse: () => null);
      final analyticsService = ref.read(patternAnalyticsServiceProvider);

      // Extract colors as RGB arrays
      final colors = preview?.colors.map((c) => [c.red, c.green, c.blue]).toList() ?? <List<int>>[];
      final colorNames = preview?.colorNames.isNotEmpty == true
          ? preview!.colorNames
          : preview?.colors.map(_colorName).toList() ?? <String>[];

      // Extract speed, intensity, brightness from wled payload
      int speed = preview?.speed ?? 128;
      int intensity = preview?.intensity ?? 128;
      int brightness = 210;
      final seg = wledPayload['seg'];
      if (seg is List && seg.isNotEmpty && seg.first is Map) {
        final first = seg.first as Map;
        speed = (first['sx'] as num?)?.toInt() ?? speed;
        intensity = (first['ix'] as num?)?.toInt() ?? intensity;
      }
      if (wledPayload['bri'] is num) {
        brightness = (wledPayload['bri'] as num).toInt();
      }

      await analyticsService.recordPatternApplied(
        query: query,
        effectId: preview?.effectId ?? 0,
        effectName: preview?.effectName ?? 'Unknown',
        colors: colors,
        colorNames: colorNames,
        speed: speed,
        intensity: intensity,
        brightness: brightness,
        userId: user?.uid,
        wledPayload: wledPayload,
      );
    } catch (e) {
      debugPrint('Failed to record pattern applied: $e');
    }
  }

  /// Applies a pattern directly from a chat message's Apply button
  Future<void> _applyPatternFromChat(Map<String, dynamic> wledPayload, _PatternPreview? preview) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No controller connected')),
      );
      return;
    }

    try {
      final ok = await repo.applyJson(wledPayload);
      if (!ok) {
        debugPrint('WLED rejected payload from chat Apply button');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to apply pattern')),
          );
        }
        return;
      }

      if (mounted) {
        // Store pattern metadata for home screen display
        if (preview != null) {
          ref.read(wledStateProvider.notifier).setLuminaPatternMetadata(
            colorSequence: preview.colors,
            colorNames: preview.colorNames,
            effectName: preview.effectName,
          );
        }

        // Update the active preset label
        String patternLabel = preview?.patternName ?? 'Lumina Pattern';
        ref.read(activePresetLabelProvider.notifier).state = patternLabel;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$patternLabel applied!')),
        );

        // Clear chat history after successful application
        _clearChatHistory();
        setState(() {});
      }
    } catch (e) {
      debugPrint('Apply pattern from chat failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error applying pattern: $e')),
        );
      }
    }
  }

  String _colorName(Color c) {
    final hsv = HSVColor.fromColor(c);
    final h = hsv.hue;
    final s = hsv.saturation;
    final v = hsv.value;
    if (v > 0.9 && s < 0.1) return 'White';
    if (s < 0.2) return 'White';
    if (h < 15 || h >= 345) return 'Red';
    if (h < 45) return 'Orange';
    if (h < 70) return 'Yellow';
    if (h < 170) return 'Green';
    if (h < 250) return 'Blue';
    if (h < 300) return 'Purple';
    return 'Pink';
  }

  Color _colorNameToColorObject(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'red':
        return const Color(0xFFFF0000);
      case 'green':
        return const Color(0xFF00FF00);
      case 'blue':
        return const Color(0xFF0000FF);
      case 'white':
        return const Color(0xFFFFFFFF);
      case 'warm white':
        return const Color(0xFFFFFAF4);
      case 'cool white':
        return const Color(0xFFC8DCFF);
      case 'yellow':
        return const Color(0xFFFFFF00);
      case 'orange':
        return const Color(0xFFFFA500);
      case 'purple':
        return const Color(0xFF800080);
      case 'pink':
        return const Color(0xFFFFC0CB);
      case 'cyan':
        return const Color(0xFF00FFFF);
      default:
        return const Color(0xFFFFFFFF);
    }
  }

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _previewBarAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));

    // Seed with placeholder immediately; will be replaced when profile arrives
    _setHouseImageFromUrl(null);

    // Hide the live preview as soon as the user begins composing a new message
    _input.addListener(() {
      if (showPreviewBar && _input.text.isNotEmpty) {
        setState(() => showPreviewBar = false);
        if (mounted) _previewBarAnim.reverse();
      }
    });

  }

  @override
  void dispose() {
    _previewBarAnim.dispose();
    _pulse.dispose();
    _speech.stop();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Clears the chat history and resets pattern context
  void _clearChatHistory() {
    _messages.clear();
    _activePatternContext = null;
    _activePreview = null;
    showPreviewBar = false;
    currentPreviewColors = [];
    _lastQueryForFeedback = null;
  }

  // Load and cache the background image used for real-time previews.
  // If url is null or empty, fall back to a local placeholder asset.
  void _setHouseImageFromUrl(String? url) {
    try {
      ImageProvider<Object> provider;
      if (url != null && url.isNotEmpty) {
        // Prefer network URL (as commonly stored in profile photoUrl)
        if (url.startsWith('http')) {
          provider = NetworkImage(url);
        } else {
          // Unsupported path for web or unknown scheme; use placeholder
          provider = const AssetImage('assets/images/Demohomephoto.jpg');
        }
      } else {
        provider = const AssetImage('assets/images/Demohomephoto.jpg');
      }

      if (mounted) {
        setState(() => _houseImageProvider = provider);
        // Cache image for fast future paints
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            precacheImage(provider, context);
          } catch (e) {
            debugPrint('precacheImage failed: $e');
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to set house image: $e');
    }
  }

  Future<void> _send(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty) return;
    setState(() {
      _messages.add(_Msg.user(prompt));
      _isThinking = true;
      // Clear the preview bar when starting a new query
      // This prevents stale patterns from visually persisting
      showPreviewBar = false;
      currentPreviewColors = [];
      // Track query for feedback recording
      _lastQueryForFeedback = prompt;
    });
    _previewBarAnim.reverse();
    _input.clear();
    _scrollToEndSoon();

    try {
      final repo = ref.read(wledRepositoryProvider);
      // We proceed even if repo is null, to at least show the verbal response.

      // === SCHEDULE DETECTION ===
      // Check if this is a schedule request before processing as a pattern
      if (_detectScheduleIntent(prompt)) {
        final confirmation = await _parseAndCreateSchedule(prompt);
        if (confirmation != null) {
          setState(() {
            _messages.add(_Msg.assistant(confirmation));
            _isThinking = false;
          });
          _scrollToEndSoon();
          return; // Exit early - schedule created successfully
        }
        // If schedule parsing failed, fall through to pattern generation
        // The user might want an immediate pattern instead
      }

      // === PHASE 2: Architectural Parser ===
      // Try to parse the command with architectural understanding
      final rooflineConfig = ref.read(currentRooflineConfigProvider).maybeWhen(
            data: (config) => config,
            orElse: () => null,
          );

      if (rooflineConfig != null && rooflineConfig.segments.isNotEmpty) {
        final parser = ArchitecturalParserService();
        final architecturalCommand = parser.parseCommand(prompt, rooflineConfig);

        // If we successfully parsed an architectural command, handle it directly
        if (architecturalCommand != null) {
          final targetDescription = parser.describeTargets(architecturalCommand.targetSegments);
          final effectDesc = architecturalCommand.effect;
          final colorDesc = architecturalCommand.colors.isNotEmpty
              ? architecturalCommand.colors.join(', ')
              : 'current colors';

          // === PHASE 3: Intelligent Pattern Generation ===
          // Generate a segment-aware pattern using the advanced generator
          final generatedPattern = parser.generateIntelligentPattern(
            config: rooflineConfig,
            command: architecturalCommand,
          );

          // Build friendly response
          final verbal = 'Perfect! I\'ve created "${generatedPattern.name}" - ${generatedPattern.description}';

          // Get WLED payload from generated pattern
          final patternGenerator = SegmentPatternGenerator();
          final wled = patternGenerator.patternToWledPayload(generatedPattern);

          // Create preview from generated pattern
          final preview = _PatternPreview(
            colors: generatedPattern.colors,
            effectId: generatedPattern.primaryEffectId,
            patternName: generatedPattern.name.toUpperCase(),
          );

          // Record this suggestion in history for variety in open-ended queries
          SuggestionHistoryService.instance.recordSuggestion(
            patternName: generatedPattern.name,
            colorNames: generatedPattern.colors.map(_colorName).toList(),
            effectId: generatedPattern.primaryEffectId,
            queryType: 'architectural',
          );

          // Show confirmation and apply
          if (repo != null) {
            try {
              final shouldApply = await _showRunSetupSheet(
                context,
                wled: wled,
                preview: preview,
                fallbackText: verbal,
              );

              if (shouldApply == true) {
                final ok = await repo.applyJson(wled);
                if (!ok) debugPrint('WLED rejected architectural payload');
                if (mounted && ok) {
                  // Store pattern metadata for home screen display
                  ref.read(wledStateProvider.notifier).setLuminaPatternMetadata(
                    colorSequence: preview.colors,
                    colorNames: preview.colors.map(_colorName).toList(),
                    effectName: null, // Architectural patterns don't have a single effect name
                  );

                  ref.read(activePresetLabelProvider.notifier).state = preview.patternName ?? 'Architectural Pattern';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Applied to $targetDescription!')),
                  );
                  _clearChatHistory();
                }
              }
            } catch (e) {
              debugPrint('Architectural command application failed: $e');
            }
          }

          setState(() {
            _messages.add(_Msg.assistant(verbal, preview: preview, wledPayload: wled));
            _activePatternContext = {'wled': wled};
            _activePreview = preview;
            currentPreviewColors = preview.colors;
            showPreviewBar = true;
            _previewBarAnim.forward();
          });

          if (mounted) setState(() => _isThinking = false);
          _scrollToEndSoon();
          return; // Exit early - architectural command handled
        }
      }

      // === FALLBACK: Standard Lumina AI ===
      // Ask Lumina with the new system instruction. The reply may include a
      // hidden JSON object to apply immediately.
      final content = await LuminaBrain.chat(ref, prompt);

      // Response Handler: detect JSON, extract wled, and show only verbal text.
      final parsed = _extractJsonFromContent(content);
      Map<String, dynamic>? wled;
      String verbal = content.trim();
      if (parsed != null) {
        final obj = parsed.object;
        // Extract wled object if present, else treat the top-level map as WLED
        final candidate = obj['wled'];
        if (candidate is Map<String, dynamic>) {
          wled = candidate;
        } else {
          // Heuristic: if it looks like WLED (seg/on/bri), use it.
          if (obj.containsKey('seg') || obj.containsKey('on') || obj.containsKey('bri')) {
            wled = obj.cast<String, dynamic>();
          }
        }
        // Remove the JSON substring and any code fence markers from the verbal text.
        verbal = _cleanVerbalText(verbal.replaceFirst(parsed.substring, ''));
      }

      _PatternPreview? preview;
      if (wled != null) {
        // Prepare preview info - pass full parsed object to get rich schema data
        preview = _extractPreview(parsed?.object ?? {'wled': wled});

        // Record this suggestion in history to avoid repetition for open-ended queries
        if (preview != null) {
          final context = SemanticPatternMatcher.extractContext(prompt);
          SuggestionHistoryService.instance.recordSuggestion(
            patternName: preview.patternName ?? 'Pattern',
            colorNames: preview.colorNames.isNotEmpty
                ? preview.colorNames
                : preview.colors.map(_colorName).toList(),
            effectId: preview.effectId,
            effectName: preview.effectName,
            queryType: context,
          );
        }

        // Ask the user to confirm running the setup before applying to lights
        if (repo != null) {
          try {
            final shouldApply = await _showRunSetupSheet(context, wled: wled, preview: preview, fallbackText: _buildAssistantReply(wled, fallback: 'Apply this to your lights?'));
            if (shouldApply == true) {
              final ok = await repo.applyJson(wled);
              if (!ok) debugPrint('WLED rejected payload from Lumina');
              if (mounted && ok) {
                // Store Lumina pattern metadata for home screen display
                // This preserves the full color sequence and effect name from AI
                if (preview != null) {
                  ref.read(wledStateProvider.notifier).setLuminaPatternMetadata(
                    colorSequence: preview.colors,
                    colorNames: preview.colorNames,
                    effectName: preview.effectName,
                  );
                }

                // Record pattern application to global analytics for learning
                _recordPatternApplied(prompt, preview, wled);

                // Extract pattern label: prefer patternName > thought > verbal
                String patternLabel = 'Lumina Pattern';
                if (parsed != null && parsed.object['patternName'] is String) {
                  patternLabel = parsed.object['patternName'] as String;
                } else if (preview?.patternName != null) {
                  patternLabel = preview!.patternName!;
                } else if (parsed != null && parsed.object['thought'] is String) {
                  final thought = parsed.object['thought'] as String;
                  patternLabel = thought.length > 30 ? '${thought.substring(0, 27)}...' : thought;
                } else if (verbal.isNotEmpty && verbal.length < 50) {
                  patternLabel = verbal.split('.').first.trim();
                  if (patternLabel.length > 30) patternLabel = '${patternLabel.substring(0, 27)}...';
                }
                // Update the active preset label so the dashboard shows the current pattern
                ref.read(activePresetLabelProvider.notifier).state = patternLabel;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$patternLabel applied!')));
                // Clear chat history after successful pattern application
                _clearChatHistory();
              }
            }
          } catch (e) {
            debugPrint('Run setup sheet failed: $e');
          }
        }
      }

      final reply = verbal.isEmpty ? 'Done.' : verbal;
      setState(() {
        _messages.add(_Msg.assistant(reply, preview: preview, wledPayload: wled));
        // If a WLED payload exists, extract the primary color and trigger the live preview
        if (wled != null) {
          // Store as active pattern context for refinement operations
          _activePatternContext = parsed?.object ?? {'wled': wled};
          _activePreview = preview;

          final Color? primary = _primaryColorFromWled(wled);
          if (primary != null) {
            currentPreviewColors = [primary];
          } else if (preview != null) {
            currentPreviewColors = preview.colors;
          } else {
            currentPreviewColors = const [NexGenPalette.cyan, Color(0xFF102040)];
          }
          showPreviewBar = true;
          // Animate the preview bar in
          _previewBarAnim.forward();
        }
      });
    } catch (e) {
      debugPrint('LuminaChat error: $e');
      setState(() => _messages.add(_Msg.assistant('I hit a snag: $e')));
    } finally {
      if (mounted) setState(() => _isThinking = false);
      _scrollToEndSoon();
    }
  }

  /// Handles refinement requests (e.g., "make it slower") that modify the active pattern
  /// instead of triggering a new search.
  Future<void> _sendRefinement(String refinementPrompt) async {
    // If there's no active pattern, fall back to regular search
    if (_activePatternContext == null) {
      return _send(refinementPrompt);
    }

    setState(() {
      _messages.add(_Msg.user(refinementPrompt));
      _isThinking = true;
      // Clear the preview bar while processing refinement
      showPreviewBar = false;
    });
    _previewBarAnim.reverse();
    _scrollToEndSoon();

    try {
      final repo = ref.read(wledRepositoryProvider);

      // Call the refinement-specific AI method that preserves context
      final content = await LuminaBrain.chatRefinement(
        ref,
        refinementPrompt,
        currentPattern: _activePatternContext!,
      );

      // Parse response - same as _send
      final parsed = _extractJsonFromContent(content);
      Map<String, dynamic>? wled;
      String verbal = content.trim();
      if (parsed != null) {
        final obj = parsed.object;
        final candidate = obj['wled'];
        if (candidate is Map<String, dynamic>) {
          wled = candidate;
        } else if (obj.containsKey('seg') || obj.containsKey('on') || obj.containsKey('bri')) {
          wled = obj.cast<String, dynamic>();
        }
        // Remove the JSON substring and any code fence markers from the verbal text.
        verbal = _cleanVerbalText(verbal.replaceFirst(parsed.substring, ''));
      }

      _PatternPreview? preview;
      if (wled != null) {
        preview = _extractPreview(parsed?.object ?? {'wled': wled});

        // Record refined pattern in history
        if (preview != null) {
          SuggestionHistoryService.instance.recordSuggestion(
            patternName: preview.patternName ?? 'Refined Pattern',
            colorNames: preview.colorNames.isNotEmpty
                ? preview.colorNames
                : preview.colors.map(_colorName).toList(),
            effectId: preview.effectId,
            effectName: preview.effectName,
            queryType: 'refinement',
          );
        }

        if (repo != null) {
          try {
            final shouldApply = await _showRunSetupSheet(
              context,
              wled: wled,
              preview: preview,
              fallbackText: _buildAssistantReply(wled, fallback: 'Apply this adjustment?'),
            );
            if (shouldApply == true) {
              final ok = await repo.applyJson(wled);
              if (!ok) debugPrint('WLED rejected refined payload from Lumina');
              if (mounted && ok) {
                // Store pattern metadata for home screen display
                if (preview != null) {
                  ref.read(wledStateProvider.notifier).setLuminaPatternMetadata(
                    colorSequence: preview.colors,
                    colorNames: preview.colorNames,
                    effectName: preview.effectName,
                  );
                }

                String patternLabel = 'Lumina Pattern';
                if (parsed != null && parsed.object['patternName'] is String) {
                  patternLabel = parsed.object['patternName'] as String;
                } else if (preview?.patternName != null) {
                  patternLabel = preview!.patternName!;
                }
                ref.read(activePresetLabelProvider.notifier).state = patternLabel;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$patternLabel applied!')));
                // Clear chat history after successful pattern application
                _clearChatHistory();
              }
            }
          } catch (e) {
            debugPrint('Run setup sheet failed: $e');
          }
        }
      }

      final reply = verbal.isEmpty ? 'Done.' : verbal;
      setState(() {
        _messages.add(_Msg.assistant(reply, preview: preview, wledPayload: wled));
        if (wled != null) {
          // Update active pattern context with the refined pattern
          _activePatternContext = parsed?.object ?? {'wled': wled};
          _activePreview = preview;

          final Color? primary = _primaryColorFromWled(wled);
          if (primary != null) {
            currentPreviewColors = [primary];
          } else if (preview != null) {
            currentPreviewColors = preview.colors;
          } else {
            currentPreviewColors = const [NexGenPalette.cyan, Color(0xFF102040)];
          }
          showPreviewBar = true;
          _previewBarAnim.forward();
        }
      });
    } catch (e) {
      debugPrint('LuminaChat refinement error: $e');
      setState(() => _messages.add(_Msg.assistant('I hit a snag adjusting the pattern: $e')));
    } finally {
      if (mounted) setState(() => _isThinking = false);
      _scrollToEndSoon();
    }
  }

  void _scrollToEndSoon() => Future.delayed(const Duration(milliseconds: 100), () {
        if (!_scroll.hasClients) return;
        // Scroll to the very end with extra padding to ensure visibility above keyboard
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 200,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });

  Future<void> _toggleVoice() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    try {
      final available = await _speech.initialize(onStatus: (s) {}, onError: (e) => debugPrint('speech error: ${e.errorMsg}'));
      if (!available) return;
      setState(() => _listening = true);
      await _speech.listen(
        onResult: (res) {
          if (!mounted) return;
          final recognized = res.recognizedWords;
          if (recognized.isNotEmpty) {
            _input.text = recognized;
            _input.selection = TextSelection.fromPosition(TextPosition(offset: _input.text.length));
          }
          if (res.finalResult) setState(() => _listening = false);
        },
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
      );
    } catch (e) {
      debugPrint('Voice init failed: $e');
    }
  }

  _PatternPreview? _extractPreview(Map<String, dynamic> payload) {
    try {
      // Try to extract from the rich schema first
      String? patternName = payload['patternName'] as String?;
      String? effectName;
      String? direction;
      bool isStatic = false;
      int? speed;
      int? intensity;
      List<String> colorNames = [];

      // Extract from rich "colors" array if present
      final colorsArray = payload['colors'];
      List<Color> colors = [];
      if (colorsArray is List) {
        for (final c in colorsArray) {
          if (c is Map) {
            final name = c['name'] as String?;
            if (name != null) colorNames.add(name);
            final rgb = c['rgb'];
            if (rgb is List && rgb.length >= 3) {
              final r = (rgb[0] as num).toInt();
              final g = (rgb[1] as num).toInt();
              final b = (rgb[2] as num).toInt();
              colors.add(Color.fromARGB(255, r, g, b));
            }
          }
        }
      }

      // Extract from rich "effect" object if present
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

      // Fallback: extract from wled payload if rich fields not present
      final wled = payload['wled'] ?? payload;
      final seg = wled['seg'];
      int? pal;
      if (seg is List && seg.isNotEmpty && seg.first is Map) {
        final first = seg.first as Map;
        effect ??= (first['fx'] as num?)?.toInt();
        pal = (first['pal'] as num?)?.toInt();
        speed ??= (first['sx'] as num?)?.toInt();
        intensity ??= (first['ix'] as num?)?.toInt();

        // Extract colors from wled if not already extracted
        if (colors.isEmpty) {
          final col = first['col'];
          if (col is List) {
            for (final c in col) {
              if (c is List && c.length >= 3) {
                final r = (c[0] as num).toInt();
                final g = (c[1] as num).toInt();
                final b = (c[2] as num).toInt();
                colors.add(Color.fromARGB(255, r, g, b));
              }
            }
          }
        }
      }

      if (colors.isEmpty) {
        colors = const [NexGenPalette.cyan, Color(0xFF102040)];
      }

      return _PatternPreview(
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

  // Extract the primary color from a WLED JSON payload at seg[0].col[0]
  Color? _primaryColorFromWled(Map<String, dynamic> payload) {
    try {
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final first = seg.first;
        if (first is Map<String, dynamic>) {
          final col = first['col'];
          if (col is List && col.isNotEmpty) {
            final p = col.first;
            if (p is List && p.length >= 3) {
              final r = (p[0] as num).toInt();
              final g = (p[1] as num).toInt();
              final b = (p[2] as num).toInt();
              return Color.fromARGB(255, r, g, b);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('primaryColorFromWled failed: $e');
    }
    return null;
  }

  String _buildAssistantReply(Map<String, dynamic> payload, {required String fallback}) {
    try {
      final isOn = payload['on'];
      final bri = payload['bri'];
      String msg = '';
      if (isOn is bool) msg += isOn ? 'Power is on. ' : 'Power is off. ';
      if (bri is int) msg += 'Brightness set to ${((bri / 255) * 100).round()}%. ';
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty && seg.first is Map) {
        final first = seg.first as Map;
        final fx = first['fx'];
        if (fx is int) msg += 'Effect #$fx applied.';
      }
      return msg.isEmpty ? fallback : msg.trim();
    } catch (_) {
      return fallback;
    }
  }

  // --- Response Handler helpers ---
  _JsonExtraction? _extractJsonFromContent(String content) {
    try {
      final start = content.indexOf('{');
      if (start < 0) return null;
      int depth = 0;
      for (int i = start; i < content.length; i++) {
        final ch = content[i];
        if (ch == '{') depth++;
        if (ch == '}') {
          depth--;
          if (depth == 0) {
            final sub = content.substring(start, i + 1);
            final obj = jsonDecode(sub);
            if (obj is Map<String, dynamic>) {
              return _JsonExtraction(object: obj, substring: sub);
            }
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('extractJsonFromContent failed: $e');
    }
    return null;
  }

  /// Cleans up verbal text by removing markdown code fence markers and extra whitespace.
  /// Handles patterns like ```json ... ``` or ''' ... '''
  String _cleanVerbalText(String text) {
    String cleaned = text;
    // Remove markdown code fences (```json, ```, etc.)
    cleaned = cleaned.replaceAll(RegExp(r"```\w*\s*"), '');
    cleaned = cleaned.replaceAll(RegExp(r"```"), '');
    // Remove triple single quotes (sometimes used by AI)
    cleaned = cleaned.replaceAll(RegExp(r"'''\w*\s*"), '');
    cleaned = cleaned.replaceAll(RegExp(r"'''"), '');
    // Clean up extra whitespace and newlines
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n'), '\n');
    return cleaned.trim();
  }

  // ==========================================================================
  // SCHEDULE DETECTION AND CREATION
  // These methods enable Lumina to understand and create schedules from
  // natural language requests like "run Chiefs pattern sunset to sunrise daily"
  // ==========================================================================

  /// Detects if the user's message is a schedule-related request.
  /// Returns true if the message contains scheduling intent keywords.
  bool _detectScheduleIntent(String text) {
    final lowerText = text.toLowerCase();

    // Schedule-specific keywords
    final scheduleKeywords = [
      'schedule',
      'automate',
      'automation',
      'every day',
      'every night',
      'every evening',
      'every morning',
      'daily',
      'nightly',
      'weekly',
      'weeknight',
      'weekend',
      'for the week',
      'for the entire week',
      'all week',
      'each night',
      'each day',
      'recurring',
    ];

    // Time range patterns indicating scheduling
    final timeRangePatterns = [
      'sunset to sunrise',
      'sunrise to sunset',
      'dusk to dawn',
      'dawn to dusk',
      'until sunrise',
      'until sunset',
      'from sunset',
      'from sunrise',
      'at sunset',
      'at sunrise',
    ];

    // Day of week mentions (strong indicator of scheduling)
    final dayKeywords = [
      'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
      'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun',
    ];

    // Check for explicit schedule keywords
    for (final keyword in scheduleKeywords) {
      if (lowerText.contains(keyword)) return true;
    }

    // Check for time range patterns (strong schedule indicators)
    for (final pattern in timeRangePatterns) {
      if (lowerText.contains(pattern)) return true;
    }

    // Check for day mentions combined with time indicators
    final hasDayMention = dayKeywords.any((day) => lowerText.contains(day));
    final hasTimeIndicator = lowerText.contains('pm') ||
                             lowerText.contains('am') ||
                             lowerText.contains('sunset') ||
                             lowerText.contains('sunrise');

    if (hasDayMention && hasTimeIndicator) return true;

    // Pattern: "run X at Y" or "set X at Y" with time
    final runAtPattern = RegExp(r'(run|set|play|start)\s+.+\s+(at|from)\s+\d{1,2}', caseSensitive: false);
    if (runAtPattern.hasMatch(lowerText)) return true;

    return false;
  }

  /// Parses a schedule request and creates the schedule.
  /// Returns a friendly confirmation message or null if parsing failed.
  Future<String?> _parseAndCreateSchedule(String text) async {
    final lowerText = text.toLowerCase();

    // =========================================================================
    // STEP 1: Extract the pattern/action from the request
    // =========================================================================
    String? patternName;
    String actionLabel;

    // Look for pattern names in the request
    // Common patterns: sports teams, holidays, colors, effects
    final patternMatchers = [
      // Sports teams
      RegExp(r'(chiefs|titans|patriots|cowboys|raiders|eagles|packers|steelers|broncos|chargers|ravens|bengals|browns|49ers|seahawks|rams|cardinals|saints|falcons|panthers|buccaneers|vikings|bears|lions|giants|jets|dolphins|bills|colts|texans|jaguars|commanders)\s*(pattern|mode)?', caseSensitive: false),
      // NCAA teams
      RegExp(r'(vols|volunteers|crimson tide|tide|bulldogs|gators|seminoles|hurricanes|longhorns|sooners|buckeyes|wolverines|spartans|wildcats|tigers|jayhawks|cornhuskers|badgers|hawkeyes|golden gophers)\s*(pattern|mode)?', caseSensitive: false),
      // Holidays
      RegExp(r'(christmas|halloween|thanksgiving|fourth of july|independence day|valentines|easter|st patricks|new years|holiday)\s*(pattern|mode)?', caseSensitive: false),
      // Generic patterns
      RegExp(r'(warm white|cool white|bright white|rainbow|festive|party|calm|relaxing|cozy|romantic)\s*(pattern|mode)?', caseSensitive: false),
    ];

    for (final pattern in patternMatchers) {
      final match = pattern.firstMatch(lowerText);
      if (match != null) {
        patternName = match.group(1)!;
        // Capitalize first letter of each word
        patternName = patternName.split(' ').map((word) =>
          word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : word
        ).join(' ');
        break;
      }
    }

    // Determine action label
    if (patternName != null) {
      actionLabel = 'Pattern: $patternName';
    } else if (lowerText.contains('off') || lowerText.contains('turn off')) {
      actionLabel = 'Turn Off';
      patternName = 'Off';
    } else if (lowerText.contains('on') || lowerText.contains('turn on')) {
      actionLabel = 'Turn On';
      patternName = 'On';
    } else if (lowerText.contains('warm')) {
      actionLabel = 'Pattern: Warm White';
      patternName = 'Warm White';
    } else if (lowerText.contains('cool')) {
      actionLabel = 'Pattern: Cool White';
      patternName = 'Cool White';
    } else {
      // Try to extract a custom pattern name from quotes or after "run"/"play"
      final quotedMatch = RegExp(r'"([^"]+)"').firstMatch(text);
      if (quotedMatch != null) {
        patternName = quotedMatch.group(1);
        actionLabel = 'Pattern: $patternName';
      } else {
        // Default to "Custom Pattern" from Lumina
        actionLabel = 'Pattern: Lumina Custom';
        patternName = 'Lumina Custom';
      }
    }

    // =========================================================================
    // STEP 2: Determine ON time
    // =========================================================================
    String timeLabel;

    if (lowerText.contains('sunset') || lowerText.contains('dusk') || lowerText.contains('evening')) {
      timeLabel = 'Sunset';
    } else if (lowerText.contains('sunrise') || lowerText.contains('dawn') || lowerText.contains('morning')) {
      timeLabel = 'Sunrise';
    } else if (lowerText.contains('midnight')) {
      timeLabel = '12:00 AM';
    } else if (lowerText.contains('noon')) {
      timeLabel = '12:00 PM';
    } else {
      // Try to parse specific time like "8 pm" or "8:00 pm"
      final timeMatch = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)', caseSensitive: false).firstMatch(lowerText);
      if (timeMatch != null) {
        final hour = timeMatch.group(1)!;
        final minute = timeMatch.group(2) ?? '00';
        final ampm = timeMatch.group(3)!.toUpperCase();
        timeLabel = '$hour:$minute $ampm';
      } else {
        // Default to sunset for lighting schedules
        timeLabel = 'Sunset';
      }
    }

    // =========================================================================
    // STEP 3: Determine OFF time
    // =========================================================================
    String? offTimeLabel;

    final offTimePatterns = [
      RegExp(r'(?:to|until|through|->|→|-)\s*(sunrise|dawn)', caseSensitive: false),
      RegExp(r'(?:to|until|through|->|→|-)\s*(sunset|dusk)', caseSensitive: false),
      RegExp(r'(?:to|until|through|->|→|-)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)', caseSensitive: false),
    ];

    for (final pattern in offTimePatterns) {
      final match = pattern.firstMatch(lowerText);
      if (match != null) {
        final captured = match.group(1)!.toLowerCase();
        if (captured == 'sunrise' || captured == 'dawn') {
          offTimeLabel = 'Sunrise';
        } else if (captured == 'sunset' || captured == 'dusk') {
          offTimeLabel = 'Sunset';
        } else {
          final hour = match.group(1)!;
          final minute = match.group(2) ?? '00';
          final ampm = match.group(3)!.toUpperCase();
          offTimeLabel = '$hour:$minute $ampm';
        }
        break;
      }
    }

    // Check for common patterns
    if (offTimeLabel == null) {
      if (lowerText.contains('dusk to dawn') || lowerText.contains('sunset to sunrise')) {
        offTimeLabel = 'Sunrise';
      } else if (lowerText.contains('dawn to dusk') || lowerText.contains('sunrise to sunset')) {
        offTimeLabel = 'Sunset';
      }
    }

    // =========================================================================
    // STEP 4: Determine repeat days
    // =========================================================================
    List<String> repeatDays;

    if (lowerText.contains('every night') || lowerText.contains('nightly') ||
        lowerText.contains('every evening') || lowerText.contains('daily') ||
        lowerText.contains('every day') || lowerText.contains('for the week') ||
        lowerText.contains('for the entire week') || lowerText.contains('all week')) {
      repeatDays = ['Daily'];
    } else if (lowerText.contains('weeknight')) {
      repeatDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    } else if (lowerText.contains('weekend')) {
      repeatDays = ['Sat', 'Sun'];
    } else {
      // Check for specific days mentioned
      final dayMap = {
        'monday': 'Mon', 'mon': 'Mon',
        'tuesday': 'Tue', 'tue': 'Tue',
        'wednesday': 'Wed', 'wed': 'Wed',
        'thursday': 'Thu', 'thu': 'Thu',
        'friday': 'Fri', 'fri': 'Fri',
        'saturday': 'Sat', 'sat': 'Sat',
        'sunday': 'Sun', 'sun': 'Sun',
      };

      final foundDays = <String>{};
      for (final entry in dayMap.entries) {
        if (lowerText.contains(entry.key)) {
          foundDays.add(entry.value);
        }
      }

      repeatDays = foundDays.isNotEmpty ? foundDays.toList() : ['Daily'];
    }

    // =========================================================================
    // STEP 5: Create the schedule
    // =========================================================================
    final scheduleId = DateTime.now().millisecondsSinceEpoch.toString();
    final schedule = ScheduleItem(
      id: scheduleId,
      timeLabel: timeLabel,
      offTimeLabel: offTimeLabel,
      repeatDays: repeatDays,
      actionLabel: actionLabel,
      enabled: true,
    );

    // Add to the schedules provider
    try {
      await ref.read(schedulesProvider.notifier).add(schedule);
    } catch (e) {
      debugPrint('Failed to create schedule: $e');
      return null;
    }

    // =========================================================================
    // STEP 6: Generate friendly confirmation message
    // =========================================================================
    final daysDescription = repeatDays.contains('Daily')
        ? 'every day'
        : repeatDays.length == 5 && !repeatDays.contains('Sat') && !repeatDays.contains('Sun')
            ? 'on weeknights'
            : repeatDays.length == 2 && repeatDays.contains('Sat') && repeatDays.contains('Sun')
                ? 'on weekends'
                : 'on ${repeatDays.join(", ")}';

    final timeDesc = timeLabel.toLowerCase();
    final offTimeDesc = offTimeLabel?.toLowerCase();

    String confirmation;
    if (offTimeDesc != null) {
      confirmation = 'Perfect! I\'ve scheduled your $patternName pattern to run $daysDescription from $timeDesc until $offTimeDesc. You can view and manage this in your Schedule tab.';
    } else {
      confirmation = 'Perfect! I\'ve scheduled your $patternName pattern to start $daysDescription at $timeDesc. You can view and manage this in your Schedule tab.';
    }

    return confirmation;
  }

  @override
  Widget build(BuildContext context) {
    // Listen for user profile updates to pick up the house image URL
    ref.listen(currentUserProfileProvider, (previous, next) {
      final url = next.maybeWhen(data: (u) => u?.housePhotoUrl, orElse: () => null);
      _setHouseImageFromUrl(url);
    });

    // Listen for pending voice messages from long-press on Lumina nav button
    ref.listen(pendingVoiceMessageProvider, (previous, next) {
      if (next != null && next.isNotEmpty) {
        // Consume the message immediately
        ref.read(pendingVoiceMessageProvider.notifier).state = null;
        // Send it to the AI
        _send(next);
      }
    });

    // Note: Chat history now persists across tab navigation until app exit
    // Chat is only cleared when pattern is applied or user fully exits the app

    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final isKeyboard = keyboard > 0.0;
    // Reserve space at the bottom of the list so messages aren't obscured by the floating console
    // When keyboard is open, add much more space to ensure messages are visible above keyboard + input
    final double overlayReserve = isKeyboard ? keyboard + 100 : 160;
    // Reserve space at the top for the house hero so the list scrolls beneath it
    // Use a compact hero height - roughly 1/4 of screen or aspect-based, whichever is smaller
    // Reduced by 15% to give more space for chat messages on smaller screens
    final double _aspectBased = media.size.width * 9 / 16;
    final double _screenFraction = media.size.height * 0.238;
    final double heroHeight = _aspectBased < _screenFraction ? _aspectBased : _screenFraction;
    final double clampedHeroHeight = heroHeight.clamp(140.0, 238.0);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(title: const Text('Lumina')),
      body: SafeArea(
        bottom: true,
        child: Stack(children: [
          // Top hero: user's house image with optional AI preview overlay
          // Animates up and out of view when keyboard is open
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            top: isKeyboard ? -clampedHeroHeight : 0,
            left: 0,
            right: 0,
            child: _HouseHero(
              height: clampedHeroHeight,
              imageProvider: _houseImageProvider,
              overlayColors: showPreviewBar ? currentPreviewColors : const [],
              effectId: (showPreviewBar && _activePreview != null) ? (_activePreview!.effectId ?? 0) : 0,
              speed: (showPreviewBar && _activePreview != null) ? (_activePreview!.speed ?? 128) : 128,
            ),
          ),
          // Main chat stream
          Positioned.fill(
            child: _MessageList(
              scrollController: _scroll,
              messages: _messages,
              isThinking: _isThinking,
              bottomReserve: overlayReserve,
              topReserve: isKeyboard ? 12 : clampedHeroHeight + 12,
              onThumbsUp: _handleThumbsUp,
              onThumbsDown: _handleThumbsDown,
              onRefinement: _sendRefinement,
              onApply: _applyPatternFromChat,
            ),
          ),

          // Input console positioned at the bottom, above the navigation bar
          Positioned(
            left: 0,
            right: 0,
            bottom: isKeyboard ? keyboard + 12 : 95, // 95 = space for bottom nav bar with extra clearance
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _InputConsole(
                      controller: _input,
                      focusNode: _focus,
                      onSend: () => _send(_input.text),
                      onMic: _toggleVoice,
                      listening: _listening,
                      pulse: _pulse,
                      prompts: const ['Make it Spooky', 'Titans Mode', 'Turn Off', 'Surprise Me'],
                      onPromptTap: _send,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Compose button removed for cleaner layout - input field is always visible
        ]),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final ScrollController scrollController;
  final List<_Msg> messages;
  final bool isThinking;
  final double bottomReserve;
  final double topReserve;
  final void Function(_Msg) onThumbsUp;
  final void Function(_Msg) onThumbsDown;
  final void Function(String)? onRefinement;
  final void Function(Map<String, dynamic> wledPayload, _PatternPreview? preview)? onApply;
  const _MessageList({required this.scrollController, required this.messages, required this.isThinking, this.bottomReserve = 12, this.topReserve = 0, required this.onThumbsUp, required this.onThumbsDown, this.onRefinement, this.onApply});

  @override
  Widget build(BuildContext context) {
    final items = [...messages];
    if (isThinking) items.add(_Msg.thinking());

    // If no messages yet, don't show the background
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        // Create a gradient that fades the top edge of the message area
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
          ],
          stops: const [0.0, 0.05],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: Container(
        margin: EdgeInsets.only(top: topReserve),
        decoration: BoxDecoration(
          // High-opacity dark background for better text visibility over house image
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              NexGenPalette.matteBlack.withValues(alpha: 0.92),
              NexGenPalette.matteBlack.withValues(alpha: 0.97),
              NexGenPalette.matteBlack,
            ],
            stops: const [0.0, 0.12, 0.25],
          ),
        ),
        child: ListView.builder(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomReserve),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final m = items[index];
            // Only show refinement chips on the most recent assistant message with a preview
            final isLastAssistantWithPreview = m.role == _Role.assistant &&
                m.preview != null &&
                index == items.lastIndexWhere((msg) => msg.role == _Role.assistant && msg.preview != null);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: switch (m.role) {
                _Role.user => _UserBubble(text: m.text),
                _Role.assistant => _AssistantBubble(
                  text: m.text,
                  preview: m.preview,
                  wledPayload: m.wledPayload,
                  feedbackGiven: m.feedbackGiven,
                  onThumbsUp: () => onThumbsUp(m),
                  onThumbsDown: () => onThumbsDown(m),
                  onRefinement: isLastAssistantWithPreview ? onRefinement : null,
                  onApply: (m.wledPayload != null && onApply != null)
                      ? () => onApply!(m.wledPayload!, m.preview)
                      : null,
                ),
                _Role.thinking => const _ThinkingBubble(),
              },
            );
          },
        ),
      ),
    );
  }
}

enum _Role { user, assistant, thinking }

class _Msg {
  final _Role role;
  final String text;
  final _PatternPreview? preview;
  final Map<String, dynamic>? wledPayload;
  // Track if user gave feedback (null = no feedback, true = thumbs up, false = thumbs down)
  bool? feedbackGiven;
  _Msg(this.role, this.text, {this.preview, this.wledPayload, this.feedbackGiven});
  factory _Msg.user(String t) => _Msg(_Role.user, t);
  factory _Msg.assistant(String t, { _PatternPreview? preview, Map<String, dynamic>? wledPayload }) => _Msg(_Role.assistant, t, preview: preview, wledPayload: wledPayload);
  factory _Msg.thinking() => _Msg(_Role.thinking, '');
}

class _JsonExtraction {
  final Map<String, dynamic> object;
  final String substring;
  const _JsonExtraction({required this.object, required this.substring});
}

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble({required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Flexible(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0A1B4A), NexGenPalette.cyan], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16), topRight: Radius.circular(16)),
          ),
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white)),
        ),
      ),
    ]);
  }
}

class _AssistantBubble extends StatelessWidget {
  final String text;
  final _PatternPreview? preview;
  final Map<String, dynamic>? wledPayload;
  final bool? feedbackGiven; // null = no feedback, true = thumbs up, false = thumbs down
  final VoidCallback onThumbsUp;
  final VoidCallback onThumbsDown;
  final void Function(String)? onRefinement;
  final VoidCallback? onApply;
  const _AssistantBubble({required this.text, this.preview, this.wledPayload, this.feedbackGiven, required this.onThumbsUp, required this.onThumbsDown, this.onRefinement, this.onApply});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Avatar with glow
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.7), blurRadius: 12, spreadRadius: 1)]),
        child: ClipOval(
          child: Image.asset('assets/images/nexgen_logo.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.auto_awesome, color: NexGenPalette.cyan, size: 20)),
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xE62A2A2A), // 90% opacity for better text visibility
            borderRadius: const BorderRadius.only(topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: NexGenPalette.textHigh)),
            if (preview != null) ...[
              const SizedBox(height: 10),
              _PatternTile(preview: preview!),
              // Apply button - always visible when there's a pattern with payload
              if (onApply != null) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onApply,
                    icon: const Icon(Icons.bolt_rounded, color: Colors.black, size: 18),
                    label: const Text('Apply to Lights', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                    style: FilledButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
              // Refinement chips for pattern adjustments
              if (onRefinement != null) ...[
                const SizedBox(height: 10),
                _RefinementChips(onRefinement: onRefinement!),
              ],
            ],
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Tooltip(
                message: 'Thumbs up',
                child: IconButton(
                  onPressed: feedbackGiven == null ? onThumbsUp : null,
                  icon: Icon(feedbackGiven == true ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined),
                  color: feedbackGiven == true ? NexGenPalette.cyan : NexGenPalette.textMedium,
                  iconSize: 18,
                ),
              ),
              Tooltip(
                message: 'Thumbs down',
                child: IconButton(
                  onPressed: feedbackGiven == null ? onThumbsDown : null,
                  icon: Icon(feedbackGiven == false ? Icons.thumb_down_alt : Icons.thumb_down_alt_outlined),
                  color: feedbackGiven == false ? NexGenPalette.cyan : NexGenPalette.textMedium,
                  iconSize: 18,
                ),
              ),
            ])
          ]),
        ),
      )
    ]);
  }
}

/// Refinement chips that appear after a pattern is applied, allowing users to
/// request variations like "more subtle", "brighter", "different effect", etc.
class _RefinementChips extends StatelessWidget {
  final void Function(String) onRefinement;
  const _RefinementChips({required this.onRefinement});

  static const _refinements = [
    _Refinement('More subtle', Icons.contrast, 'Make it more subtle'),
    _Refinement('Brighter', Icons.wb_sunny_outlined, 'Make it brighter'),
    _Refinement('Slower', Icons.slow_motion_video, 'Make it slower'),
    _Refinement('Faster', Icons.speed, 'Make it faster'),
    _Refinement('Different effect', Icons.auto_awesome_mosaic, 'Try a different effect'),
    _Refinement('Warmer', Icons.whatshot_outlined, 'Make the colors warmer'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _refinements.map((r) => _RefinementChip(
        label: r.label,
        icon: r.icon,
        onTap: () => onRefinement(r.prompt),
      )).toList(),
    );
  }
}

class _Refinement {
  final String label;
  final IconData icon;
  final String prompt;
  const _Refinement(this.label, this.icon, this.prompt);
}

class _RefinementChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _RefinementChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: NexGenPalette.cyan),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: NexGenPalette.textHigh,
                  fontSize: 12,
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

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();
  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.transparent),
        child: const Icon(Icons.auto_awesome_rounded, color: NexGenPalette.cyan, size: 22),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xCC2A2A2A), borderRadius: BorderRadius.circular(16), border: Border.all(color: NexGenPalette.line)),
          child: const _DotsWave(),
        ),
      )
    ]);
  }
}

class _DotsWave extends StatefulWidget {
  const _DotsWave();
  @override
  State<_DotsWave> createState() => _DotsWaveState();
}

class _DotsWaveState extends State<_DotsWave> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = (_c.value + i * 0.2) % 1.0;
            final scale = 0.6 + 0.4 * (0.5 - (t - 0.5).abs()) * 2; // pulse
            final alpha = 0.4 + 0.6 * (0.5 - (t - 0.5).abs()) * 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: 8 * scale,
                height: 8 * scale,
                decoration: BoxDecoration(color: NexGenPalette.cyan.withValues(alpha: alpha), shape: BoxShape.circle),
              ),
            );
          },
        );
      })),
    );
  }
}

class _InputConsole extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final bool listening;
  final AnimationController pulse;
  final List<String> prompts;
  final void Function(String) onPromptTap;
  const _InputConsole({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onMic,
    required this.listening,
    required this.pulse,
    this.prompts = const [],
    required this.onPromptTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Compact prompt chips - single row, smaller
          if (prompts.isNotEmpty)
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemBuilder: (_, i) {
                  final label = prompts[i];
                  return GestureDetector(
                    onTap: () => onPromptTap(label),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F1F1F),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: NexGenPalette.textMedium,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemCount: prompts.length,
              ),
            ),
          if (prompts.isNotEmpty) const SizedBox(height: 6),
          // Compact input field
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3), width: 1),
                ),
                child: Row(children: [
                  // Mic button - smaller
                  Stack(alignment: Alignment.center, children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: AnimatedBuilder(
                        animation: pulse,
                        builder: (context, _) {
                          final glow = listening ? (0.35 + 0.35 * (0.5 - (pulse.value - 0.5).abs()) * 2) : 0.0;
                          return Container(
                            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                              BoxShadow(color: NexGenPalette.cyan.withValues(alpha: glow), blurRadius: listening ? 18 : 0, spreadRadius: listening ? 2 : 0),
                            ]),
                          );
                        },
                      ),
                    ),
                    IconButton(
                      onPressed: onMic,
                      icon: Icon(listening ? Icons.mic : Icons.mic_none, size: 20),
                      color: NexGenPalette.violet,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: NexGenPalette.textHigh),
                      decoration: InputDecoration(
                        hintText: 'Ask Lumina…',
                        hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.6), fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Send button - compact
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: NexGenPalette.cyan,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: onSend,
                      icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                      color: Colors.black,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// _StarterChips integrated into _InputConsole via prompts

class _PatternPreview {
  final String? patternName;
  final List<Color> colors;
  final List<String> colorNames;
  final int? effectId;
  final String? effectName;
  final String? direction;
  final bool isStatic;
  final int? speed;
  final int? intensity;
  final int? paletteId;
  const _PatternPreview({
    this.patternName,
    required this.colors,
    this.colorNames = const [],
    this.effectId,
    this.effectName,
    this.direction,
    this.isStatic = false,
    this.speed,
    this.intensity,
    this.paletteId,
  });
}

class _PatternTile extends StatelessWidget {
  final _PatternPreview preview;
  const _PatternTile({required this.preview});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
        gradient: LinearGradient(
          colors: preview.colors.length >= 2
              ? preview.colors.map((c) => c.withValues(alpha: 0.3)).toList()
              : [preview.colors.first.withValues(alpha: 0.3), preview.colors.first.withValues(alpha: 0.3)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pattern name header
          if (preview.patternName != null) ...[
            Row(
              children: [
                Icon(Icons.auto_awesome, color: NexGenPalette.cyan, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    preview.patternName!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: NexGenPalette.textHigh,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Colors row with names
          Row(
            children: [
              ...List.generate(preview.colors.length.clamp(1, 5), (i) {
                final c = preview.colors[i % preview.colors.length];
                final name = i < preview.colorNames.length ? preview.colorNames[i] : null;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c,
                          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 8)],
                          border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                        ),
                      ),
                      if (name != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          name.length > 10 ? '${name.substring(0, 8)}...' : name,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: NexGenPalette.textMedium,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ],
          ),

          const SizedBox(height: 10),

          // Effect info row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              // Effect type chip
              if (preview.effectName != null)
                _InfoChip(
                  icon: preview.isStatic ? Icons.pause_circle_outline : Icons.motion_photos_on,
                  label: preview.effectName!,
                ),

              // Direction chip
              if (preview.direction != null && preview.direction != 'none')
                _InfoChip(
                  icon: _directionIcon(preview.direction!),
                  label: _formatDirection(preview.direction!),
                ),

              // Speed chip
              if (preview.speed != null && !preview.isStatic)
                _InfoChip(
                  icon: Icons.speed,
                  label: _speedLabel(preview.speed!),
                ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _directionIcon(String direction) {
    switch (direction.toLowerCase()) {
      case 'left': return Icons.arrow_back;
      case 'right': return Icons.arrow_forward;
      case 'center-out': return Icons.unfold_more;
      case 'alternating': return Icons.swap_horiz;
      default: return Icons.compare_arrows;
    }
  }

  String _formatDirection(String direction) {
    switch (direction.toLowerCase()) {
      case 'left': return 'Left';
      case 'right': return 'Right';
      case 'center-out': return 'Center Out';
      case 'alternating': return 'Alternating';
      default: return direction;
    }
  }

  String _speedLabel(int speed) {
    if (speed < 64) return 'Slow';
    if (speed < 128) return 'Medium-Slow';
    if (speed < 192) return 'Medium';
    return 'Fast';
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: NexGenPalette.cyan),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposeButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ComposeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(boxShadow: [BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.25), blurRadius: 20, spreadRadius: 1)]),
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.black),
        label: const Text('Compose', style: TextStyle(color: Colors.black)),
        style: ButtonStyle(
          backgroundColor: const MaterialStatePropertyAll(NexGenPalette.cyan),
          shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
          padding: const MaterialStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          elevation: const MaterialStatePropertyAll(8),
          shadowColor: MaterialStatePropertyAll(NexGenPalette.cyan.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}

/// LivePreviewContainer shows color swatches and pattern details for the
/// suggested lighting effect. Slides open above the input console and can be
/// dismissed with the close button. No house image here - the main hero above
/// already shows the pattern preview on the home.
class LivePreviewContainer extends StatelessWidget {
  final bool show;
  final AnimationController animation;
  final ImageProvider<Object>? imageProvider; // kept for API compatibility, not used
  final List<Color> colors;
  final int effectId;
  final int speed;
  final VoidCallback onClose;

  const LivePreviewContainer({
    super.key,
    required this.show,
    required this.animation,
    required this.imageProvider,
    required this.colors,
    this.effectId = 0,
    this.speed = 128,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // Drive the size animation depending on `show`
    if (show && !animation.isAnimating && animation.value == 0) {
      animation.forward();
    } else if (!show && !animation.isAnimating && animation.value == 1) {
      animation.reverse();
    }

    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
      axisAlignment: -1.0,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border.all(color: NexGenPalette.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                // Color swatches
                if (colors.isNotEmpty) ...[
                  ...colors.take(5).map((c) => Container(
                    width: 28,
                    height: 28,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c,
                      boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 8)],
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
                    ),
                  )),
                ],
                const Spacer(),
                // Pattern info text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          effectId == 0 ? Icons.pause_circle_outline : Icons.motion_photos_on,
                          size: 14,
                          color: NexGenPalette.cyan,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          effectId == 0 ? 'Solid' : 'Effect #$effectId',
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    if (effectId != 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        _speedLabel(speed),
                        style: TextStyle(
                          color: NexGenPalette.textMedium,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 8),
                // Close button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                    onPressed: onClose,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _speedLabel(int speed) {
    if (speed < 64) return 'Slow';
    if (speed < 128) return 'Medium-Slow';
    if (speed < 192) return 'Medium';
    return 'Fast';
  }
}

/// Full-width hero at top of Lumina page showing the user's house photo
/// with an optional preview overlay (animated LED effects) to simulate lighting on
/// the roofline. Uses the same image source as the dashboard (profile photo
/// URL or the Demohomephoto asset fallback).
class _HouseHero extends StatelessWidget {
  final double height;
  final ImageProvider<Object>? imageProvider;
  final List<Color> overlayColors;
  final int effectId;
  final int speed;
  const _HouseHero({
    required this.height,
    required this.imageProvider,
    required this.overlayColors,
    this.effectId = 0,
    this.speed = 128,
  });

  // Match dashboard image alignment (shifted down 30%)
  static const _imageAlignment = Alignment(0, 0.3);

  @override
  Widget build(BuildContext context) {
    final hasImage = imageProvider != null;
    final hasOverlay = overlayColors.isNotEmpty;
    return SizedBox(
      height: height,
      child: ClipRRect(
        child: Stack(fit: StackFit.expand, children: [
          // Base image - use same alignment as dashboard
          if (hasImage)
            Image(image: imageProvider!, fit: BoxFit.cover, alignment: _imageAlignment)
          else
            Image.asset('assets/images/Demohomephoto.jpg', fit: BoxFit.cover, alignment: _imageAlignment),

          // Subtle dark gradient from bottom for legibility
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                ),
              ),
            ),
          ),

          // AR preview overlay with animated LED effects on roofline
          // Uses LayoutBuilder to pass proper BoxFit.cover parameters for correct alignment
          if (hasOverlay)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final targetAspectRatio = constraints.maxWidth / constraints.maxHeight;
                  return AnimatedRooflineOverlay(
                    previewColors: overlayColors,
                    previewEffectId: effectId,
                    previewSpeed: speed,
                    forceOn: true,
                    brightness: 255,
                    // Match dashboard BoxFit.cover parameters for correct roofline positioning
                    targetAspectRatio: targetAspectRatio,
                    imageAlignment: const Offset(0, 0.3), // Matches _imageAlignment
                    useBoxFitCover: true,
                  );
                },
              ),
            ),

          // Label chip
          if (hasOverlay)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: Row(children: [
                  const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text('Previewing on your home', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
