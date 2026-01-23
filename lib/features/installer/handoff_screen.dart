import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/simple/simple_providers.dart';

/// Customer handoff screen for installer setup wizard.
/// Allows installer to configure user preferences before handing off.
class HandoffScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  const HandoffScreen({
    super.key,
    this.onBack,
    this.onNext,
  });

  @override
  ConsumerState<HandoffScreen> createState() => _HandoffScreenState();
}

class _HandoffScreenState extends ConsumerState<HandoffScreen> {
  bool _useSimpleMode = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NexGenPalette.gunmetal90,
              border: Border.all(color: NexGenPalette.line),
            ),
            child: const Icon(Icons.handshake_outlined, size: 64, color: NexGenPalette.cyan),
          ),
          const SizedBox(height: 32),
          const Text(
            'Customer Handoff',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Configure user preferences before completing setup.',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 16),
          ),
          const SizedBox(height: 32),

          // Simple Mode Configuration Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [NexGenPalette.cyan, NexGenPalette.violet],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Simple Mode',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch(
                      value: _useSimpleMode,
                      onChanged: (value) => setState(() => _useSimpleMode = value),
                      activeColor: NexGenPalette.cyan,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Recommended for:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                _buildRecommendationItem('Older users who prefer simplicity'),
                _buildRecommendationItem('First-time smart home users'),
                _buildRecommendationItem('Users who want easy, one-tap control'),
                const SizedBox(height: 16),
                const Divider(color: NexGenPalette.line),
                const SizedBox(height: 16),
                const Text(
                  'Simple Mode Features:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                _buildFeatureItem(Icons.check_circle_outline, 'Large, easy-to-tap buttons', NexGenPalette.cyan),
                _buildFeatureItem(Icons.check_circle_outline, 'Only Home & Settings tabs', NexGenPalette.cyan),
                _buildFeatureItem(Icons.check_circle_outline, '3-5 favorite patterns for quick access', NexGenPalette.cyan),
                _buildFeatureItem(Icons.check_circle_outline, 'Simple brightness control with haptic feedback', NexGenPalette.cyan),
                _buildFeatureItem(Icons.check_circle_outline, 'Voice assistant setup guides', NexGenPalette.cyan),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: NexGenPalette.cyan.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: NexGenPalette.cyan, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Users can always switch between Simple and Full modes in Settings.',
                          style: TextStyle(
                            color: NexGenPalette.cyan,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Navigation buttons
          Row(
            children: [
              if (widget.onBack != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onBack,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: NexGenPalette.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Back', style: TextStyle(color: Colors.white)),
                  ),
                ),
              if (widget.onBack != null) const SizedBox(width: 16),
              if (widget.onNext != null)
                Expanded(
                  child: ElevatedButton(
                    onPressed: _completeHandoff,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Complete Setup',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: NexGenPalette.cyan, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _completeHandoff() {
    // Apply Simple Mode preference
    if (_useSimpleMode) {
      ref.read(simpleModeProvider.notifier).enable();
    } else {
      ref.read(simpleModeProvider.notifier).disable();
    }

    // Call the onNext callback to complete setup
    widget.onNext?.call();
  }
}
