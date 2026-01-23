import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';
import 'dart:ui';

/// Giant microphone FAB with cyan glow animation for voice control
/// Displays on dashboard with persistent visibility and prominent size (80px)
class VoiceControlFab extends StatefulWidget {
  final VoidCallback onTap;
  final bool isListening;

  const VoiceControlFab({
    super.key,
    required this.onTap,
    required this.isListening,
  });

  @override
  State<VoiceControlFab> createState() => _VoiceControlFabState();
}

class _VoiceControlFabState extends State<VoiceControlFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          // Calculate glow intensity based on listening state and pulse animation
          final glowIntensity = widget.isListening
              ? 0.5 + (0.5 * _pulseController.value)
              : 0.0;

          final glowRadius = widget.isListening
              ? 20.0 + (10.0 * _pulseController.value)
              : 0.0;

          return Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  NexGenPalette.cyan.withValues(alpha: 0.9),
                  NexGenPalette.violet.withValues(alpha: 0.9),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                // Animated glow when listening
                BoxShadow(
                  color: NexGenPalette.cyan.withValues(alpha: glowIntensity),
                  blurRadius: glowRadius,
                  spreadRadius: glowRadius / 2,
                ),
                // Base shadow for depth
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        NexGenPalette.cyan.withValues(alpha: 0.9),
                        NexGenPalette.violet.withValues(alpha: 0.9),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      widget.isListening ? Icons.mic : Icons.mic_none_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Visual feedback overlay for voice command confirmation
/// Shows a brief success message with checkmark animation
class VoiceCommandFeedback extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const VoiceCommandFeedback({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  @override
  State<VoiceCommandFeedback> createState() => _VoiceCommandFeedbackState();
}

class _VoiceCommandFeedbackState extends State<VoiceCommandFeedback>
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
