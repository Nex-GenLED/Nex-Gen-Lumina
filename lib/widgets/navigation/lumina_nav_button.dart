import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexgen_command/theme.dart';

/// Enhanced center dock button for Lumina with:
/// - Quick tap: opens sheet in compact mode
/// - Long press with haptic: opens sheet in listening mode
/// - Subtle cyan glow when a conversation session is active
class LuminaNavButton extends StatefulWidget {
  /// Called on quick tap (open compact sheet).
  final VoidCallback onTap;

  /// Called on long press (open listening sheet).
  final VoidCallback? onLongPress;

  /// Whether a conversation session is active (shows glow).
  final bool hasActiveSession;

  /// Whether the mic is currently listening (shows mic icon + strong glow).
  final bool isListening;

  const LuminaNavButton({
    super.key,
    required this.onTap,
    this.onLongPress,
    this.hasActiveSession = false,
    this.isListening = false,
  });

  @override
  State<LuminaNavButton> createState() => _LuminaNavButtonState();
}

class _LuminaNavButtonState extends State<LuminaNavButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _updateGlow();
  }

  @override
  void didUpdateWidget(LuminaNavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasActiveSession != widget.hasActiveSession ||
        oldWidget.isListening != widget.isListening) {
      _updateGlow();
    }
  }

  void _updateGlow() {
    if (widget.isListening || widget.hasActiveSession) {
      if (!_glowAnim.isAnimating) _glowAnim.repeat(reverse: true);
    } else {
      _glowAnim.stop();
      _glowAnim.value = 0;
    }
  }

  @override
  void dispose() {
    _glowAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: () {
            HapticFeedback.heavyImpact();
            widget.onLongPress?.call();
          },
          child: AnimatedBuilder(
            animation: _glowAnim,
            builder: (context, child) {
              // Base glow
              double glowAlpha = 0.35;
              double blurRadius = 12.0;
              double spreadRadius = 1.0;
              Color glowColor = NexGenPalette.cyan;

              if (widget.isListening) {
                // Strong pulsing glow when listening
                glowAlpha = 0.6 + _glowAnim.value * 0.3;
                blurRadius = 20 + _glowAnim.value * 8;
                spreadRadius = 2 + _glowAnim.value * 2;
              } else if (widget.hasActiveSession) {
                // Subtle breathing glow when session active
                glowAlpha = 0.4 + _glowAnim.value * 0.2;
                blurRadius = 14 + _glowAnim.value * 4;
                spreadRadius = 1;
              }

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: NexGenPalette.matteBlack,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withValues(alpha: glowAlpha),
                      blurRadius: blurRadius,
                      spreadRadius: spreadRadius,
                    ),
                  ],
                  border: Border.all(
                    color: widget.isListening
                        ? NexGenPalette.cyan
                        : NexGenPalette.cyan.withValues(alpha: 0.7),
                    width: widget.isListening ? 2.5 : 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isListening)
                      const Icon(Icons.mic, color: NexGenPalette.cyan, size: 32)
                    else
                      Image.asset(
                        'assets/images/Gemini_Generated_Image_n4fr1en4fr1en4fr.png',
                        height: 32.0,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.auto_awesome_rounded,
                          color: NexGenPalette.cyan,
                          size: 32,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      widget.isListening ? 'Listening...' : 'Lumina',
                      style: TextStyle(
                        color: widget.isListening
                            ? NexGenPalette.cyan
                            : Colors.white,
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
