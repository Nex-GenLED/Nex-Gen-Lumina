import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/simple/simple_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/voice/dashboard_voice_control.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Simplified dashboard for less tech-savvy users.
/// Shows large, easy-to-use controls with minimal complexity.
class SimpleDashboard extends ConsumerStatefulWidget {
  const SimpleDashboard({super.key});

  @override
  ConsumerState<SimpleDashboard> createState() => _SimpleDashboardState();
}

class _SimpleDashboardState extends ConsumerState<SimpleDashboard> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  bool _voiceListening = false;
  String? _voiceFeedbackMessage;
  bool _brightnessExpanded = false;

  @override
  void dispose() {
    _chatController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final wledState = ref.watch(wledStateProvider);
    final brightness = wledState.brightness;
    final isOn = wledState.isOn;

    return Scaffold(
      backgroundColor: NexGenPalette.deepNavy,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Compact Header with inline brightness
                _buildCompactHeader(context, ref, brightness, isOn),

                // Main scrollable content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    children: [
                      // Compact Power Buttons
                      _buildCompactPowerButtons(context, ref, isOn),
                      const SizedBox(height: 20),

                      // Expanded Brightness Slider (when tapped)
                      if (_brightnessExpanded)
                        _buildExpandedBrightnessSlider(context, ref, brightness),

                      // My Favorites Section (2x2 Grid)
                      _buildFavoritesGrid(context, ref),
                      const SizedBox(height: 20),

                      // Quick Actions Row
                      _buildQuickActions(context),
                      const SizedBox(height: 24),

                      // Suggestion chips
                      _buildSuggestionChips(context),
                      const SizedBox(height: 100), // Space for chat bar
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Lumina Chat Bar (pinned to bottom)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildLuminaChatBar(context),
          ),

          // Voice feedback overlay
          if (_voiceFeedbackMessage != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 120,
              child: Center(
                child: _VoiceFeedbackCard(
                  message: _voiceFeedbackMessage!,
                  onDismiss: () => setState(() => _voiceFeedbackMessage = null),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Toggle voice listening and process the command when speech is recognized
  Future<void> _toggleVoice() async {
    if (_voiceListening) {
      await _speech.stop();
      setState(() => _voiceListening = false);
      return;
    }

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          debugPrint('Voice status: $status');
        },
        onError: (error) {
          debugPrint('Voice error: ${error.errorMsg}');
          if (mounted) {
            setState(() {
              _voiceListening = false;
              _voiceFeedbackMessage = 'Voice recognition error';
            });
          }
        },
      );

      if (!available) {
        if (mounted) {
          setState(() {
            _voiceFeedbackMessage = 'Voice recognition not available';
          });
        }
        return;
      }

      setState(() => _voiceListening = true);

      await _speech.listen(
        onResult: (result) async {
          if (!mounted) return;

          final recognizedWords = result.recognizedWords;
          debugPrint('Voice recognized: $recognizedWords (final: ${result.finalResult})');

          // Only process final results
          if (result.finalResult && recognizedWords.isNotEmpty) {
            setState(() => _voiceListening = false);
            await _speech.stop();

            // Process the voice command
            final handler = ref.read(voiceCommandHandlerProvider);
            final feedback = await handler.processCommand(recognizedWords);

            if (mounted) {
              setState(() {
                _voiceFeedbackMessage = feedback;
              });

              // Clear feedback after 2.5 seconds
              Future.delayed(const Duration(milliseconds: 2500), () {
                if (mounted) {
                  setState(() {
                    _voiceFeedbackMessage = null;
                  });
                }
              });
            }
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          partialResults: true,
        ),
      );
    } catch (e) {
      debugPrint('Voice initialization failed: $e');
      if (mounted) {
        setState(() {
          _voiceListening = false;
          _voiceFeedbackMessage = 'Failed to start voice recognition';
        });
      }
    }
  }

  /// Compact header with inline brightness indicator
  Widget _buildCompactHeader(BuildContext context, WidgetRef ref, int brightness, bool isOn) {
    final brightnessPercent = (brightness / 255 * 100).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: NexGenPalette.deepNavy,
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Lights',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  isOn ? 'Lights are on' : 'Lights are off',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isOn ? NexGenPalette.cyan : Colors.white.withOpacity(0.5),
                      ),
                ),
              ],
            ),
          ),

          // Brightness indicator (tap to expand)
          GestureDetector(
            onTap: () => setState(() => _brightnessExpanded = !_brightnessExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _brightnessExpanded
                    ? NexGenPalette.cyan.withOpacity(0.2)
                    : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _brightnessExpanded
                      ? NexGenPalette.cyan
                      : Colors.white.withOpacity(0.15),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.brightness_6,
                    color: _brightnessExpanded ? NexGenPalette.cyan : Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$brightnessPercent%',
                    style: TextStyle(
                      color: _brightnessExpanded ? NexGenPalette.cyan : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _brightnessExpanded ? Icons.expand_less : Icons.expand_more,
                    color: _brightnessExpanded ? NexGenPalette.cyan : Colors.white54,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact power buttons (80px height instead of 150px)
  Widget _buildCompactPowerButtons(BuildContext context, WidgetRef ref, bool isOn) {
    return Row(
      children: [
        Expanded(
          child: _CompactPowerButton(
            label: 'All On',
            icon: Icons.lightbulb,
            isActive: isOn,
            activeColor: NexGenPalette.cyan,
            onPressed: () => _turnOn(ref),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _CompactPowerButton(
            label: 'All Off',
            icon: Icons.lightbulb_outline,
            isActive: !isOn,
            activeColor: Colors.grey.shade600,
            onPressed: () => _turnOff(ref),
          ),
        ),
      ],
    );
  }

  /// Expanded brightness slider (shows when header brightness is tapped)
  Widget _buildExpandedBrightnessSlider(BuildContext context, WidgetRef ref, int brightness) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.cyan.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexGenPalette.cyan.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 10,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
              activeTrackColor: NexGenPalette.cyan,
              inactiveTrackColor: Colors.white.withOpacity(0.1),
              thumbColor: NexGenPalette.cyan,
              overlayColor: NexGenPalette.cyan.withOpacity(0.2),
            ),
            child: Slider(
              value: brightness.toDouble(),
              min: 0,
              max: 255,
              divisions: 255,
              onChanged: (value) {
                HapticFeedback.selectionClick();
                _setBrightness(ref, value.toInt());
              },
            ),
          ),
          const SizedBox(height: 8),
          // Quick brightness presets
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _BrightnessPreset(label: '25%', value: 64, onTap: () => _setBrightness(ref, 64)),
              _BrightnessPreset(label: '50%', value: 128, onTap: () => _setBrightness(ref, 128)),
              _BrightnessPreset(label: '75%', value: 192, onTap: () => _setBrightness(ref, 192)),
              _BrightnessPreset(label: '100%', value: 255, onTap: () => _setBrightness(ref, 255)),
            ],
          ),
        ],
      ),
    );
  }

  /// Favorites section with 2x2 grid layout
  Widget _buildFavoritesGrid(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(simpleFavoritesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star, color: NexGenPalette.violet, size: 22),
            const SizedBox(width: 8),
            Text(
              'My Favorites',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _showBrowseSheet(context),
              child: Text(
                'Edit',
                style: TextStyle(color: NexGenPalette.cyan, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        favoritesAsync.when(
          data: (favoriteIds) {
            if (favoriteIds.isEmpty) {
              return _buildEmptyFavorites(context);
            }
            // Take only the first 4 for 2x2 grid
            final topFour = favoriteIds.take(4).toList();
            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: topFour.map((patternId) {
                return _FavoriteGridCard(patternId: patternId);
              }).toList(),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, stack) => _buildEmptyFavorites(context),
        ),
      ],
    );
  }

  Widget _buildEmptyFavorites(BuildContext context) {
    return GestureDetector(
      onTap: () => _showBrowseSheet(context),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: NexGenPalette.violet.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.add, color: NexGenPalette.violet, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add Favorites',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to browse designs',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withOpacity(0.5),
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
          ],
        ),
      ),
    );
  }

  /// Quick Actions row with Schedule and Browse buttons
  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            icon: Icons.calendar_today,
            label: 'Schedule',
            onTap: () => _showScheduleSheet(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _QuickActionButton(
            icon: Icons.explore,
            label: 'Browse Designs',
            onTap: () => _showBrowseSheet(context),
          ),
        ),
      ],
    );
  }

  /// Show the schedule page as a full-screen sheet
  void _showScheduleSheet(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => const MySchedulePage(),
      ),
    );
  }

  /// Suggestion chips for quick actions
  Widget _buildSuggestionChips(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SuggestionChip(
          label: 'Warm White',
          onTap: () => _processTextCommand('Set warm white'),
        ),
        _SuggestionChip(
          label: 'Turn lights on',
          onTap: () => _processTextCommand('Turn lights on'),
        ),
        _SuggestionChip(
          label: 'Schedule sunset',
          onTap: () => _processTextCommand('Schedule lights to turn on at sunset'),
        ),
      ],
    );
  }

  /// Lumina Chat Bar with text + voice input
  Widget _buildLuminaChatBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Lumina avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [NexGenPalette.violet, NexGenPalette.cyan],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),

          // Text input
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withOpacity(0.15)),
              ),
              child: TextField(
                controller: _chatController,
                focusNode: _chatFocusNode,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Ask Lumina anything...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (text) {
                  if (text.isNotEmpty) {
                    _processTextCommand(text);
                    _chatController.clear();
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Voice button
          GestureDetector(
            onTap: _toggleVoice,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _voiceListening
                    ? NexGenPalette.cyan
                    : Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
                boxShadow: _voiceListening
                    ? [
                        BoxShadow(
                          color: NexGenPalette.cyan.withOpacity(0.5),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                _voiceListening ? Icons.mic : Icons.mic_none,
                color: _voiceListening ? Colors.black : Colors.white70,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Process a text command through the voice handler
  Future<void> _processTextCommand(String command) async {
    final handler = ref.read(voiceCommandHandlerProvider);
    final feedback = await handler.processCommand(command);

    if (mounted) {
      setState(() {
        _voiceFeedbackMessage = feedback;
      });

      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) {
          setState(() {
            _voiceFeedbackMessage = null;
          });
        }
      });
    }
  }

  /// Show the browse patterns sheet
  void _showBrowseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _SimpleBrowseSheet(),
    );
  }

  void _turnOn(WidgetRef ref) {
    HapticFeedback.mediumImpact();
    ref.read(wledStateProvider.notifier).togglePower(true);
  }

  void _turnOff(WidgetRef ref) {
    HapticFeedback.mediumImpact();
    ref.read(wledStateProvider.notifier).togglePower(false);
  }

  void _setBrightness(WidgetRef ref, int brightness) {
    ref.read(wledStateProvider.notifier).setBrightness(brightness);
  }
}

/// Voice feedback card for Simple Mode
class _VoiceFeedbackCard extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const _VoiceFeedbackCard({
    required this.message,
    required this.onDismiss,
  });

  @override
  State<_VoiceFeedbackCard> createState() => _VoiceFeedbackCardState();
}

class _VoiceFeedbackCardState extends State<_VoiceFeedbackCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    // Auto-dismiss after 2 seconds
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
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
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: NexGenPalette.cyan.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: NexGenPalette.cyan,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact power button for Simple Mode (80px height)
class _CompactPowerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onPressed;

  const _CompactPowerButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onPressed();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 80,
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? activeColor : Colors.white.withOpacity(0.1),
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: isActive ? activeColor : Colors.white.withOpacity(0.5),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: isActive ? activeColor : Colors.white.withOpacity(0.5),
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brightness preset button
class _BrightnessPreset extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback onTap;

  const _BrightnessPreset({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Quick action button
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: NexGenPalette.cyan, size: 22),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Suggestion chip for quick commands
class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: NexGenPalette.cyan.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: NexGenPalette.cyan.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: NexGenPalette.cyan,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Favorite pattern grid card for Simple Mode (2x2 grid)
class _FavoriteGridCard extends ConsumerWidget {
  final String patternId;

  const _FavoriteGridCard({required this.patternId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patterns = ref.watch(publicPatternLibraryProvider);

    // Find the pattern by ID
    GradientPattern? pattern;
    for (final p in patterns.all) {
      if (p.name.toLowerCase().replaceAll(' ', '_') == patternId.toLowerCase()) {
        pattern = p;
        break;
      }
    }

    final displayName = pattern?.name ?? _getFallbackName(patternId);
    final displayIcon = pattern != null ? _getIconForPattern(pattern) : Icons.lightbulb;

    return GestureDetector(
      onTap: () => _applyPattern(ref, pattern),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              NexGenPalette.cyan.withOpacity(0.12),
              NexGenPalette.violet.withOpacity(0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(displayIcon, color: NexGenPalette.cyan, size: 24),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                displayName,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getFallbackName(String id) {
    return id.split('_').map((word) => word[0].toUpperCase() + word.substring(1)).join(' ');
  }

  IconData _getIconForPattern(GradientPattern pattern) {
    final name = pattern.name.toLowerCase();
    if (name.contains('white')) return Icons.wb_sunny;
    if (name.contains('christmas') || name.contains('holiday')) return Icons.celebration;
    if (name.contains('halloween')) return Icons.auto_awesome;
    if (name.contains('fire') || name.contains('flame')) return Icons.local_fire_department;
    if (name.contains('rainbow')) return Icons.water_drop;
    if (name.contains('patriot') || name.contains('america')) return Icons.flag;
    return Icons.auto_awesome;
  }

  void _applyPattern(WidgetRef ref, GradientPattern? pattern) async {
    if (pattern == null) return;

    HapticFeedback.mediumImpact();

    final patternId = pattern.name.toLowerCase().replaceAll(' ', '_');
    ref.read(patternUsageProvider.notifier).recordUsage(patternId);

    final repo = ref.read(wledRepositoryProvider);
    if (repo != null) {
      await repo.applyJson(pattern.toWledPayload());
    }
  }
}

/// Simple browse sheet with curated categories
class _SimpleBrowseSheet extends ConsumerWidget {
  const _SimpleBrowseSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patterns = ref.watch(publicPatternLibraryProvider);

    // Curated categories for Simple Mode
    final categories = [
      _BrowseCategory(
        name: 'Popular',
        icon: Icons.trending_up,
        color: NexGenPalette.cyan,
        patterns: patterns.architecturalElegant.take(6).toList(),
      ),
      _BrowseCategory(
        name: 'Warm & Cozy',
        icon: Icons.wb_sunny,
        color: Colors.amber,
        patterns: patterns.all.where((p) =>
          p.name.toLowerCase().contains('white') ||
          p.name.toLowerCase().contains('warm')
        ).take(4).toList(),
      ),
      _BrowseCategory(
        name: 'Holidays',
        icon: Icons.celebration,
        color: Colors.red,
        patterns: patterns.holidaysEvents.take(6).toList(),
      ),
      _BrowseCategory(
        name: 'Fun Effects',
        icon: Icons.auto_awesome,
        color: NexGenPalette.violet,
        patterns: patterns.all.where((p) =>
          p.name.toLowerCase().contains('rainbow') ||
          p.name.toLowerCase().contains('fire') ||
          p.name.toLowerCase().contains('twinkle')
        ).take(4).toList(),
      ),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text(
                      'Browse Designs',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white54),
                    ),
                  ],
                ),
              ),

              // Categories list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return _CategorySection(category: category);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Browse category model
class _BrowseCategory {
  final String name;
  final IconData icon;
  final Color color;
  final List<GradientPattern> patterns;

  const _BrowseCategory({
    required this.name,
    required this.icon,
    required this.color,
    required this.patterns,
  });
}

/// Category section in browse sheet
class _CategorySection extends ConsumerWidget {
  final _BrowseCategory category;

  const _CategorySection({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (category.patterns.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category header
        Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: category.color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(category.icon, color: category.color, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                category.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),

        // Horizontal pattern list
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: category.patterns.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final pattern = category.patterns[index];
              return _BrowsePatternCard(pattern: pattern, accentColor: category.color);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Pattern card in browse sheet
class _BrowsePatternCard extends ConsumerWidget {
  final GradientPattern pattern;
  final Color accentColor;

  const _BrowsePatternCard({
    required this.pattern,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _applyAndClose(context, ref),
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getIconForPattern(),
              color: accentColor,
              size: 28,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                pattern.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForPattern() {
    final name = pattern.name.toLowerCase();
    if (name.contains('white')) return Icons.wb_sunny;
    if (name.contains('christmas') || name.contains('holiday')) return Icons.celebration;
    if (name.contains('halloween')) return Icons.auto_awesome;
    if (name.contains('fire') || name.contains('flame')) return Icons.local_fire_department;
    if (name.contains('rainbow')) return Icons.water_drop;
    if (name.contains('twinkle')) return Icons.star;
    return Icons.lightbulb;
  }

  void _applyAndClose(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();

    final patternId = pattern.name.toLowerCase().replaceAll(' ', '_');
    ref.read(patternUsageProvider.notifier).recordUsage(patternId);

    final repo = ref.read(wledRepositoryProvider);
    if (repo != null) {
      await repo.applyJson(pattern.toWledPayload());
    }

    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Favorite pattern card for Simple Mode (kept for backwards compatibility)
class _FavoritePatternCard extends ConsumerWidget {
  final String patternId;

  const _FavoritePatternCard({required this.patternId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patterns = ref.watch(publicPatternLibraryProvider);

    // Find the pattern by ID (searching through all pattern lists)
    GradientPattern? pattern;
    for (final p in patterns.all) {
      if (p.name.toLowerCase().replaceAll(' ', '_') == patternId.toLowerCase()) {
        pattern = p;
        break;
      }
    }

    // Fallback pattern if not found
    final displayName = pattern?.name ?? _getFallbackName(patternId);
    final displayIcon = pattern != null ? _getIconForPattern(pattern) : Icons.lightbulb;

    return GestureDetector(
      onTap: () => _applyPattern(ref, pattern),
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              NexGenPalette.cyan.withOpacity(0.1),
              NexGenPalette.violet.withOpacity(0.1),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 20),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(displayIcon, color: NexGenPalette.cyan, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                displayName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  String _getFallbackName(String id) {
    // Convert ID to readable name
    return id.split('_').map((word) => word[0].toUpperCase() + word.substring(1)).join(' ');
  }

  IconData _getIconForPattern(GradientPattern pattern) {
    final name = pattern.name.toLowerCase();
    if (name.contains('white')) return Icons.wb_sunny;
    if (name.contains('christmas') || name.contains('holiday')) return Icons.celebration;
    if (name.contains('halloween')) return Icons.auto_awesome;
    if (name.contains('fire') || name.contains('flame')) return Icons.local_fire_department;
    if (name.contains('rainbow')) return Icons.water_drop;
    if (name.contains('patriot') || name.contains('america')) return Icons.flag;
    return Icons.auto_awesome;
  }

  void _applyPattern(WidgetRef ref, GradientPattern? pattern) async {
    if (pattern == null) return;

    HapticFeedback.mediumImpact();

    // Record usage for analytics (using pattern name as ID)
    final patternId = pattern.name.toLowerCase().replaceAll(' ', '_');
    ref.read(patternUsageProvider.notifier).recordUsage(patternId);

    // Apply the pattern
    final repo = ref.read(wledRepositoryProvider);
    if (repo != null) {
      await repo.applyJson(pattern.toWledPayload());
    }
  }
}
