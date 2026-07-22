import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// BATTERY OPTIMIZATION PROMPT
// ═════════════════════════════════════════════════════════════════════════════
//
// Shows a contextual prompt the first time a user schedules a Sync Event on
// Android, asking them to exempt Lumina from battery optimization. This is
// required for reliable background execution on Android 8+ (Doze mode).
//
// The prompt is shown once and remembered via SharedPreferences.
// ═════════════════════════════════════════════════════════════════════════════

const _kPromptShownKey = 'battery_optimization_prompt_shown';

/// Check if the battery optimization prompt should be shown.
/// Returns true on Android if the prompt hasn't been shown yet.
Future<bool> shouldShowBatteryOptimizationPrompt() async {
  if (!Platform.isAndroid) return false;
  final prefs = await SharedPreferences.getInstance();
  return !(prefs.getBool(_kPromptShownKey) ?? false);
}

/// Mark the prompt as shown.
Future<void> markBatteryOptimizationPromptShown() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kPromptShownKey, true);
}

/// Show the battery optimization dialog.
/// Call this the first time a sync event is scheduled.
Future<void> showBatteryOptimizationPrompt(BuildContext context) async {
  if (!Platform.isAndroid) return;

  final shouldShow = await shouldShowBatteryOptimizationPrompt();
  if (!shouldShow) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => const _BatteryOptimizationDialog(),
  );

  await markBatteryOptimizationPromptShown();
}

class _BatteryOptimizationDialog extends StatelessWidget {
  const _BatteryOptimizationDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NexGenPalette.gunmetal,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.battery_saver, color: Colors.orange, size: 24),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Background Execution',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'For reliable Sync Event triggers when the app is closed, '
            'Lumina needs to be exempted from battery optimization.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: NexGenPalette.cyan.withValues(alpha: 0.3),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How to enable:',
                  style: TextStyle(
                    color: NexGenPalette.cyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                _StepRow(number: '1', text: 'Open Settings > Apps > Lumina'),
                SizedBox(height: 4),
                _StepRow(number: '2', text: 'Tap Battery'),
                SizedBox(height: 4),
                _StepRow(
                  number: '3',
                  text: 'Select "Unrestricted" or "Don\'t optimize"',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Without this, Android may delay or prevent sync triggers '
            'when the app is in the background.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Got it',
            style: TextStyle(color: NexGenPalette.cyan),
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final String number;
  final String text;

  const _StepRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: NexGenPalette.cyan,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
