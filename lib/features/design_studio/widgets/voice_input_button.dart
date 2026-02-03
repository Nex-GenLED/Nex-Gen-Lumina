import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design_studio/design_studio_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Voice input button for the Design Studio.
///
/// Features:
/// - Microphone button with visual feedback
/// - Pulsing animation while listening
/// - Transcript display during speech
/// - Error handling for permissions
class VoiceInputButton extends ConsumerStatefulWidget {
  final void Function(String transcript) onTranscript;

  const VoiceInputButton({
    super.key,
    required this.onTranscript,
  });

  @override
  ConsumerState<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends ConsumerState<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isAvailable = false;
  bool _isListening = false;
  String _currentTranscript = '';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initSpeech() async {
    try {
      _isAvailable = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _stopListening();
          }
        },
        onError: (error) {
          debugPrint('Speech error: $error');
          _stopListening();
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Speech init error: $e');
      _isAvailable = false;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (!_isAvailable) {
      _showUnavailableSnackbar();
      return;
    }

    setState(() {
      _isListening = true;
      _currentTranscript = '';
    });
    ref.read(voiceInputActiveProvider.notifier).state = true;
    _pulseController.repeat(reverse: true);

    try {
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _currentTranscript = result.recognizedWords;
          });

          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            widget.onTranscript(result.recognizedWords);
            _stopListening();
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.dictation,
      );
    } catch (e) {
      debugPrint('Listen error: $e');
      _stopListening();
    }
  }

  void _stopListening() {
    _speech.stop();
    _pulseController.stop();
    _pulseController.reset();
    setState(() {
      _isListening = false;
    });
    ref.read(voiceInputActiveProvider.notifier).state = false;
  }

  void _showUnavailableSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Voice input is not available on this device'),
        backgroundColor: Colors.orange.shade800,
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Transcript display while listening
        if (_isListening && _currentTranscript.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _WaveformIndicator(),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _currentTranscript,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        // Microphone button
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _isListening ? _pulseAnimation.value : 1.0,
              child: child,
            );
          },
          child: GestureDetector(
            onTap: _isListening ? _stopListening : _startListening,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _isListening
                    ? NexGenPalette.cyan
                    : Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isListening
                      ? NexGenPalette.cyan
                      : Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
                boxShadow: _isListening
                    ? [
                        BoxShadow(
                          color: NexGenPalette.cyan.withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: _isListening ? Colors.black : Colors.white70,
                size: 28,
              ),
            ),
          ),
        ),

        // Label
        const SizedBox(height: 6),
        Text(
          _isListening ? 'Listening...' : 'Speak',
          style: TextStyle(
            color: _isListening ? NexGenPalette.cyan : Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Animated waveform indicator.
class _WaveformIndicator extends StatefulWidget {
  const _WaveformIndicator();

  @override
  State<_WaveformIndicator> createState() => _WaveformIndicatorState();
}

class _WaveformIndicatorState extends State<_WaveformIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
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
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final value = (((_controller.value + delay) % 1.0) * 2 - 1).abs();
            return Container(
              width: 3,
              height: 8 + (value * 8),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        );
      },
    );
  }
}
