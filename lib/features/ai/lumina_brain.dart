import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/openai/openai_config.dart';

/// LuminaBrain aggregates local context (who/where/when) and injects it into
/// every OpenAI request for improved grounding and personalization.
class LuminaBrain {
  /// Sends a conversational request enriched with context.
  static Future<String> chat(WidgetRef ref, String userPrompt) async {
    final contextBlock = _buildContextBlock(ref);
    return LuminaAI.chat(userPrompt, contextBlock: contextBlock);
  }

  /// Requests a strict WLED JSON payload with context aware instructions.
  static Future<Map<String, dynamic>> generateWledJson(WidgetRef ref, String userPrompt) async {
    final contextBlock = _buildContextBlock(ref);
    return LuminaAI.generateWledJson(userPrompt, contextBlock: contextBlock);
  }

  /// Sends a refinement request that modifies an existing pattern.
  /// The [currentPattern] is the full pattern context including colors, effect, speed, etc.
  /// The [refinementPrompt] describes what to change (e.g., "Make it slower").
  static Future<String> chatRefinement(
    WidgetRef ref,
    String refinementPrompt, {
    required Map<String, dynamic> currentPattern,
  }) async {
    final contextBlock = _buildContextBlock(ref);
    return LuminaAI.chatRefinement(
      refinementPrompt,
      currentPattern: currentPattern,
      contextBlock: contextBlock,
    );
  }

  static String _buildContextBlock(WidgetRef ref) {
    String location = 'Unknown';
    String interests = 'None';
    String avoid = '';
    try {
      final profile = ref.read(currentUserProfileProvider).maybeWhen(
            data: (u) => u,
            orElse: () => null,
          );
      if (profile != null) {
        // Prefer explicit location field (e.g., "Kansas City, MO").
        if (profile.location != null && profile.location!.trim().isNotEmpty) {
          location = profile.location!.trim();
        }
        // Build interests list from interestTags.
        if (profile.interestTags.isNotEmpty) {
          interests = profile.interestTags.join(', ');
        }
        if (profile.dislikes.isNotEmpty) {
          avoid = profile.dislikes.join(', ');
        }
      }
    } catch (e) {
      debugPrint('LuminaBrain context profile read error: $e');
    }

    final now = DateTime.now();
    final dateStr = _formatFullDate(now);
    final tod = _timeOfDayLabel(now);

    // Per spec: append this block to the system message.
    // Plaintext
    // CONTEXT:
    // - User Location: [City, State]
    // - Current Date: [Date_String]
    // - Known Interests: [Interests_List]
    // - Time of Day: [Morning/Night]
    final base = 'CONTEXT:\n'
        '- User Location: $location\n'
        '- Current Date: $dateStr\n'
        '- Known Interests: $interests\n'
        '- Time of Day: $tod';
    return avoid.isEmpty ? base : '$base\n- AVOID THESE: $avoid';
  }

  static String _timeOfDayLabel(DateTime dt) {
    final h = dt.hour;
    // Minimal spec asks Morning/Night. We'll treat 5:00–16:59 as Morning, else Night.
    return (h >= 5 && h < 17) ? 'Morning' : 'Night';
  }

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String _formatFullDate(DateTime dt) {
    // Example: "Sunday, Jan 5, 2026, 1:00 PM"
    final weekday = _weekdays[(dt.weekday - 1).clamp(0, 6)];
    final month = _months[(dt.month - 1).clamp(0, 11)];
    final day = dt.day;
    final year = dt.year;
    final hour12 = ((dt.hour + 11) % 12) + 1;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$weekday, $month $day, $year, $hour12:$minute $ampm';
  }
}
