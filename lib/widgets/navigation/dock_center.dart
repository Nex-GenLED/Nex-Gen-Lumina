import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// Center dock item with Lumina branding and glow effect
class DockCenter extends StatelessWidget {
  final bool active;
  final Color selected;
  final VoidCallback onTap;

  const DockCenter({
    super.key,
    required this.active,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 84,
            height: 84,
            child: Container(
              decoration: BoxDecoration(
                color: NexGenPalette.matteBlack,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: selected.withValues(alpha: active ? 0.8 : 0.35), blurRadius: active ? 20 : 12, spreadRadius: 1),
                ],
                border: Border.all(color: selected.withValues(alpha: 0.7), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/Gemini_Generated_Image_n4fr1en4fr1en4fr.png',
                    height: 32.0,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(Icons.auto_awesome_rounded, color: selected, size: 32),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Lumina',
                    style: TextStyle(color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
