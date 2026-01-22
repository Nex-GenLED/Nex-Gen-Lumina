import 'dart:async';
import 'dart:ui';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/openai/openai_config.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';
import 'package:nexgen_command/app_providers.dart';
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

  final List<_Msg> _messages = [];
  bool _isThinking = false;
  bool _listening = false;
  late final stt.SpeechToText _speech;
  late final AnimationController _pulse;

  // === Active Pattern Context ===
  // Stores the currently displayed pattern for refinement operations.
  // When user taps "make it slower", we modify this instead of doing a new search.
  Map<String, dynamic>? _activePatternContext;
  _PatternPreview? _activePreview;

  // === Preview preparation ===
  // Cached background image for real-time previews (user's house or placeholder)
  ImageProvider<Object>? _houseImageProvider;
  // Controls visibility of the upcoming preview bar
  bool showPreviewBar = false;
  // Colors currently previewed (updated when a new pattern is proposed)
  List<Color> currentPreviewColors = [];
  // Slide up/down animation controller for the preview bar
  late final AnimationController _previewBarAnim;
  
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
      await svc.logPatternUsage(
        userId: user.uid,
        colorNames: colorNames,
        effectId: msg.preview?.effectId,
        paletteId: msg.preview?.paletteId,
        wled: msg.wledPayload,
      );
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
      final choice = await showDialog<String>(context: context, builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text('What was wrong?', style: TextStyle(color: Colors.white)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(title: const Text('Wrong Colors', style: TextStyle(color: Colors.white70)), onTap: () => Navigator.of(ctx).pop('Wrong Colors')),
            ListTile(title: const Text('Too Fast', style: TextStyle(color: Colors.white70)), onTap: () => Navigator.of(ctx).pop('Too Fast')),
            ListTile(title: const Text('Wrong Vibe', style: TextStyle(color: Colors.white70)), onTap: () => Navigator.of(ctx).pop('Wrong Vibe')),
          ]),
        );
      });
      if (choice == null) return;
      // Update UI immediately to show feedback was received
      setState(() {
        msg.feedbackGiven = false;
      });
      final user = ref.read(authStateProvider).maybeWhen(data: (u) => u, orElse: () => null);
      if (user == null) return;
      final svc = ref.read(userServiceProvider);
      // Map choice to dislike keywords
      final List<String> keywords = [];
      if (choice == 'Wrong Colors') {
        final names = msg.preview != null ? msg.preview!.colors.take(2).map(_colorName).toList() : <String>[];
        if (names.isNotEmpty) {
          keywords.addAll(names);
        } else {
          keywords.add('Colors');
        }
      } else if (choice == 'Too Fast') {
        keywords.add('Fast');
      } else if (choice == 'Wrong Vibe') {
        keywords.add('Wrong Vibe');
      }
      for (final k in keywords) {
        await svc.addDislike(user.uid, k);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Got it — I\'ll avoid that.')));
      }
    } catch (e) {
      debugPrint('ThumbsDown failed: $e');
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
    });
    _input.clear();
    _scrollToEndSoon();

    try {
      final repo = ref.read(wledRepositoryProvider);
      // We proceed even if repo is null, to at least show the verbal response.

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

        // Ask the user to confirm running the setup before applying to lights
        if (repo != null) {
          try {
            final shouldApply = await _showRunSetupSheet(context, wled: wled, preview: preview, fallbackText: _buildAssistantReply(wled, fallback: 'Apply this to your lights?'));
            if (shouldApply == true) {
              final ok = await repo.applyJson(wled);
              if (!ok) debugPrint('WLED rejected payload from Lumina');
              if (mounted) {
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
    });
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
              if (mounted) {
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

  void _scrollToEndSoon() => Future.delayed(const Duration(milliseconds: 50), () {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(_scroll.position.maxScrollExtent + 120, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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

  @override
  Widget build(BuildContext context) {
    // Listen for user profile updates to pick up the house image URL
    ref.listen(currentUserProfileProvider, (previous, next) {
      final url = next.maybeWhen(data: (u) => u?.housePhotoUrl, orElse: () => null);
      _setHouseImageFromUrl(url);
    });

    // Listen for tab changes - clear chat history when navigating away from Lumina (tab index 2)
    ref.listen(selectedTabIndexProvider, (previous, next) {
      // If we were on Lumina (tab 2) and now we're not, clear the chat
      if (previous == 2 && next != 2 && _messages.isNotEmpty) {
        _clearChatHistory();
        if (mounted) setState(() {});
      }
    });

    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final isKeyboard = keyboard > 0.0;
    // Reserve space at the bottom of the list so messages aren't obscured by the floating console
    const double overlayReserve = 160; // compact input area needs less space
    // Reserve space at the top for the house hero so the list scrolls beneath it
    // Use a more compact hero height - roughly 1/3 of screen or aspect-based, whichever is smaller
    final double _aspectBased = media.size.width * 9 / 16;
    final double _screenThird = media.size.height * 0.28;
    final double heroHeight = _aspectBased < _screenThird ? _aspectBased : _screenThird;
    final double clampedHeroHeight = heroHeight.clamp(160.0, 280.0);

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
              messages: _messages,
              isThinking: _isThinking,
              bottomReserve: overlayReserve,
              topReserve: isKeyboard ? 12 : clampedHeroHeight + 12,
              onThumbsUp: _handleThumbsUp,
              onThumbsDown: _handleThumbsDown,
              onRefinement: _sendRefinement,
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
                    // Live preview bar, appears just above the input console
                    LivePreviewContainer(
                      show: showPreviewBar,
                      animation: _previewBarAnim,
                      imageProvider: _houseImageProvider,
                      colors: currentPreviewColors,
                      effectId: _activePreview?.effectId ?? 0,
                      speed: _activePreview?.speed ?? 128,
                      onClose: () {
                        setState(() => showPreviewBar = false);
                        _previewBarAnim.reverse();
                      },
                    ),
                    const SizedBox(height: 10),
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
  final List<_Msg> messages;
  final bool isThinking;
  final double bottomReserve;
  final double topReserve;
  final void Function(_Msg) onThumbsUp;
  final void Function(_Msg) onThumbsDown;
  final void Function(String)? onRefinement;
  const _MessageList({required this.messages, required this.isThinking, this.bottomReserve = 12, this.topReserve = 0, required this.onThumbsUp, required this.onThumbsDown, this.onRefinement});

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
          // Semi-transparent dark background so messages are readable
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              NexGenPalette.matteBlack.withValues(alpha: 0.85),
              NexGenPalette.matteBlack.withValues(alpha: 0.95),
              NexGenPalette.matteBlack,
            ],
            stops: const [0.0, 0.15, 0.3],
          ),
        ),
        child: ListView.builder(
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
                  feedbackGiven: m.feedbackGiven,
                  onThumbsUp: () => onThumbsUp(m),
                  onThumbsDown: () => onThumbsDown(m),
                  onRefinement: isLastAssistantWithPreview ? onRefinement : null,
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
  final bool? feedbackGiven; // null = no feedback, true = thumbs up, false = thumbs down
  final VoidCallback onThumbsUp;
  final VoidCallback onThumbsDown;
  final void Function(String)? onRefinement;
  const _AssistantBubble({required this.text, this.preview, this.feedbackGiven, required this.onThumbsUp, required this.onThumbsDown, this.onRefinement});

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
            color: const Color(0xCC2A2A2A),
            borderRadius: const BorderRadius.only(topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: NexGenPalette.textHigh)),
            if (preview != null) ...[
              const SizedBox(height: 10),
              _PatternTile(preview: preview!),
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

  @override
  Widget build(BuildContext context) {
    final hasImage = imageProvider != null;
    final hasOverlay = overlayColors.isNotEmpty;
    return SizedBox(
      height: height,
      child: ClipRRect(
        child: Stack(fit: StackFit.expand, children: [
          // Base image
          if (hasImage)
            Image(image: imageProvider!, fit: BoxFit.cover, alignment: Alignment.center)
          else
            Image.asset('assets/images/Demohomephoto.jpg', fit: BoxFit.cover, alignment: Alignment.center),

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
          if (hasOverlay)
            Positioned.fill(
              child: AnimatedRooflineOverlay(
                previewColors: overlayColors,
                previewEffectId: effectId,
                previewSpeed: speed,
                forceOn: true,
                brightness: 255,
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
