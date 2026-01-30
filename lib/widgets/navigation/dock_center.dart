import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// Center dock item with Lumina branding and glow effect
/// Supports long-press for voice input activation
class DockCenter extends StatelessWidget {
  final bool active;
  final Color selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isListening;

  const DockCenter({
    super.key,
    required this.active,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.isListening = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: NexGenPalette.matteBlack,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: isListening
                      ? NexGenPalette.cyan.withValues(alpha: 0.9)
                      : selected.withValues(alpha: active ? 0.8 : 0.35),
                  blurRadius: isListening ? 25 : (active ? 20 : 12),
                  spreadRadius: isListening ? 3 : 1,
                ),
              ],
              border: Border.all(
                color: isListening
                    ? NexGenPalette.cyan
                    : selected.withValues(alpha: 0.7),
                width: isListening ? 2.5 : 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Show microphone icon when listening, otherwise show Lumina logo
                if (isListening)
                  Icon(Icons.mic, color: NexGenPalette.cyan, size: 32)
                else
                  Image.asset(
                    'assets/images/Gemini_Generated_Image_n4fr1en4fr1en4fr.png',
                    height: 32.0,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(Icons.auto_awesome_rounded, color: selected, size: 32),
                  ),
                const SizedBox(height: 4),
                Text(
                  isListening ? 'Listening...' : 'Lumina',
                  style: TextStyle(
                    color: isListening ? NexGenPalette.cyan : Colors.white,
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
