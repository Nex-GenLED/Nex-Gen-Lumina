import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/theme.dart';

/// Represents a single suggestion from Lumina
class LuminaSuggestion {
  final String id;
  final String title;
  final String description;
  final LuminaSuggestionType type;
  final Map<String, dynamic> payload;
  final double confidence; // 0.0 to 1.0 based on user history match

  const LuminaSuggestion({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.payload,
    this.confidence = 0.5,
  });
}

enum LuminaSuggestionType {
  colorPalette,
  effect,
  completeDesign,
  adjustment,
}

/// Analyzes user preferences and generates personalized suggestions
class LuminaDesignBrain {
  final UserModel? userProfile;
  final List<Map<String, dynamic>> patternHistory;

  LuminaDesignBrain({
    this.userProfile,
    this.patternHistory = const [],
  });

  /// Analyze color usage history and return top colors
  List<Color> getPreferredColors() {
    final colorCounts = <String, int>{};

    for (final usage in patternHistory) {
      final colors = usage['colors'] as List<dynamic>?;
      if (colors != null) {
        for (final color in colors) {
          final name = color.toString().toLowerCase();
          colorCounts[name] = (colorCounts[name] ?? 0) + 1;
        }
      }
    }

    // Convert color names to Color objects (top 5)
    final topColors = colorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return topColors.take(5).map((e) => _colorFromName(e.key)).toList();
  }

  /// Get most used effects
  List<int> getPreferredEffects() {
    final effectCounts = <int, int>{};

    for (final usage in patternHistory) {
      final effectId = usage['effect_id'] as int?;
      if (effectId != null) {
        effectCounts[effectId] = (effectCounts[effectId] ?? 0) + 1;
      }
    }

    final topEffects = effectCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return topEffects.take(5).map((e) => e.key).toList();
  }

  /// Generate suggestions based on user context
  List<LuminaSuggestion> generateSuggestions() {
    final suggestions = <LuminaSuggestion>[];

    // 1. Sports team suggestions (if user has teams in profile)
    if (userProfile != null && userProfile!.sportsTeams.isNotEmpty) {
      for (final team in userProfile!.sportsTeams.take(2)) {
        final colors = _getTeamColors(team);
        if (colors != null) {
          suggestions.add(LuminaSuggestion(
            id: 'team_$team',
            title: '$team Colors',
            description: 'Show your team spirit with official colors',
            type: LuminaSuggestionType.colorPalette,
            payload: {'colors': colors, 'team': team},
            confidence: 0.9,
          ));
        }
      }
    }

    // 2. Holiday suggestions (based on current date and user preferences)
    final holiday = _getCurrentHoliday();
    if (holiday != null) {
      final userLikesHoliday = userProfile?.favoriteHolidays.any(
        (h) => h.toLowerCase().contains(holiday.name.toLowerCase()),
      ) ?? false;

      suggestions.add(LuminaSuggestion(
        id: 'holiday_${holiday.name}',
        title: '${holiday.name} Theme',
        description: holiday.description,
        type: LuminaSuggestionType.colorPalette,
        payload: {'colors': holiday.colors, 'holiday': holiday.name},
        confidence: userLikesHoliday ? 0.95 : 0.6,
      ));
    }

    // 3. Suggestions from usage history
    final preferredColors = getPreferredColors();
    if (preferredColors.isNotEmpty) {
      suggestions.add(LuminaSuggestion(
        id: 'history_colors',
        title: 'Your Favorites',
        description: 'Colors you use most often',
        type: LuminaSuggestionType.colorPalette,
        payload: {
          'colors': preferredColors.map((c) => [c.red, c.green, c.blue, 0]).toList(),
        },
        confidence: 0.85,
      ));
    }

    // 4. Effect suggestions based on vibe level
    final vibeLevel = userProfile?.vibeLevel ?? 0.5;
    if (vibeLevel < 0.3) {
      // Subtle/classy user - suggest calm effects
      suggestions.add(LuminaSuggestion(
        id: 'effect_subtle',
        title: 'Elegant Glow',
        description: 'Soft breathing effect for a refined look',
        type: LuminaSuggestionType.effect,
        payload: {'effectId': 2, 'speed': 80, 'intensity': 100}, // Breathe
        confidence: 0.8,
      ));
    } else if (vibeLevel > 0.7) {
      // Bold/energetic user - suggest dynamic effects
      suggestions.add(LuminaSuggestion(
        id: 'effect_bold',
        title: 'Dynamic Chase',
        description: 'Energetic movement for a bold statement',
        type: LuminaSuggestionType.effect,
        payload: {'effectId': 28, 'speed': 180, 'intensity': 200}, // Chase
        confidence: 0.8,
      ));
    }

    // 5. Time-based suggestions
    final hour = DateTime.now().hour;
    if (hour >= 18 || hour < 6) {
      suggestions.add(LuminaSuggestion(
        id: 'time_evening',
        title: 'Evening Ambiance',
        description: 'Warm, relaxing tones for the evening',
        type: LuminaSuggestionType.colorPalette,
        payload: {
          'colors': [
            [255, 180, 100, 80], // Warm white
            [255, 140, 60, 0], // Amber
          ],
        },
        confidence: 0.7,
      ));
    }

    // Sort by confidence
    suggestions.sort((a, b) => b.confidence.compareTo(a.confidence));

    return suggestions;
  }

  /// Check for dislikes before applying
  bool wouldViolateDislikes(LuminaSuggestion suggestion) {
    if (userProfile == null) return false;
    final dislikes = userProfile!.dislikes.map((d) => d.toLowerCase()).toList();

    // Check color dislikes
    if (suggestion.payload['colors'] != null) {
      for (final color in suggestion.payload['colors'] as List) {
        final colorName = _colorToName(color);
        if (dislikes.any((d) => colorName.toLowerCase().contains(d))) {
          return true;
        }
      }
    }

    // Check effect dislikes
    if (suggestion.payload['effectId'] != null) {
      final effectName = kDesignEffects[suggestion.payload['effectId']] ?? '';
      if (dislikes.any((d) => effectName.toLowerCase().contains(d))) {
        return true;
      }
    }

    return false;
  }

  Color _colorFromName(String name) {
    final colorMap = {
      'red': Colors.red,
      'green': Colors.green,
      'blue': Colors.blue,
      'white': Colors.white,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'purple': Colors.purple,
      'pink': Colors.pink,
      'cyan': Colors.cyan,
      'navy': const Color(0xFF002244),
      'gold': const Color(0xFFFFD700),
    };
    return colorMap[name] ?? Colors.white;
  }

  String _colorToName(dynamic color) {
    if (color is List && color.length >= 3) {
      final r = color[0] as int;
      final g = color[1] as int;
      final b = color[2] as int;

      if (r > 200 && g < 100 && b < 100) return 'red';
      if (r < 100 && g > 200 && b < 100) return 'green';
      if (r < 100 && g < 100 && b > 200) return 'blue';
      if (r > 200 && g > 200 && b > 200) return 'white';
      if (r > 200 && g > 200 && b < 100) return 'yellow';
      if (r > 200 && g > 100 && b < 100) return 'orange';
      if (r > 100 && g < 100 && b > 200) return 'purple';
    }
    return 'unknown';
  }

  List<List<int>>? _getTeamColors(String team) {
    final teamColors = {
      'chiefs': [[227, 24, 55, 0], [255, 184, 28, 0]], // Red, Gold
      'patriots': [[0, 48, 135, 0], [198, 12, 48, 0]], // Navy, Red
      'packers': [[32, 55, 49, 0], [255, 182, 18, 0]], // Green, Gold
      'cowboys': [[0, 53, 148, 0], [255, 255, 255, 0]], // Navy, Silver/White
      'royals': [[0, 70, 135, 0], [189, 155, 96, 0]], // Blue, Gold
      'steelers': [[255, 182, 18, 0], [0, 0, 0, 0]], // Gold, Black
      'broncos': [[251, 79, 20, 0], [0, 34, 68, 0]], // Orange, Navy
      'raiders': [[0, 0, 0, 0], [165, 172, 175, 0]], // Black, Silver
      '49ers': [[170, 0, 0, 0], [173, 153, 93, 0]], // Red, Gold
      'seahawks': [[0, 34, 68, 0], [105, 190, 40, 0]], // Navy, Green
    };
    return teamColors[team.toLowerCase()];
  }

  _HolidayInfo? _getCurrentHoliday() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    // Check upcoming holidays within 2 weeks
    if (month == 12 && day >= 10) {
      return _HolidayInfo('Christmas', 'Festive red and green', [
        [255, 0, 0, 0],
        [0, 255, 0, 0],
        [255, 255, 255, 100],
      ]);
    }
    if (month == 10 && day >= 15) {
      return _HolidayInfo('Halloween', 'Spooky orange and purple', [
        [255, 100, 0, 0],
        [128, 0, 128, 0],
        [0, 255, 0, 0],
      ]);
    }
    if (month == 7 && day >= 1 && day <= 7) {
      return _HolidayInfo('4th of July', 'Patriotic red, white, and blue', [
        [255, 0, 0, 0],
        [255, 255, 255, 0],
        [0, 0, 255, 0],
      ]);
    }
    if (month == 2 && day >= 7 && day <= 14) {
      return _HolidayInfo("Valentine's Day", 'Romantic pinks and reds', [
        [255, 20, 147, 0],
        [255, 0, 0, 0],
        [255, 182, 193, 0],
      ]);
    }
    if (month == 3 && day >= 10 && day <= 17) {
      return _HolidayInfo("St. Patrick's Day", 'Lucky green', [
        [0, 128, 0, 0],
        [50, 205, 50, 0],
        [255, 215, 0, 0],
      ]);
    }
    if (month == 11 && day >= 20 && day <= 28) {
      return _HolidayInfo('Thanksgiving', 'Warm autumn colors', [
        [255, 140, 0, 0],
        [139, 69, 19, 0],
        [255, 215, 0, 0],
      ]);
    }

    return null;
  }
}

class _HolidayInfo {
  final String name;
  final String description;
  final List<List<int>> colors;

  _HolidayInfo(this.name, this.description, this.colors);
}

/// Provider for pattern usage history
final patternHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return [];

  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('pattern_usage')
        .orderBy('created_at', descending: true)
        .limit(50)
        .get();

    return snapshot.docs.map((doc) => doc.data()).toList();
  } catch (e) {
    debugPrint('Error fetching pattern history: $e');
    return [];
  }
});

/// Provider for Lumina Design Brain
final luminaDesignBrainProvider = Provider<LuminaDesignBrain>((ref) {
  final profile = ref.watch(currentUserProfileProvider).valueOrNull;
  final history = ref.watch(patternHistoryProvider).valueOrNull ?? [];

  return LuminaDesignBrain(
    userProfile: profile,
    patternHistory: history,
  );
});

/// Provider for current suggestions
final luminaSuggestionsProvider = Provider<List<LuminaSuggestion>>((ref) {
  final brain = ref.watch(luminaDesignBrainProvider);
  final suggestions = brain.generateSuggestions();

  // Filter out suggestions that violate dislikes
  return suggestions.where((s) => !brain.wouldViolateDislikes(s)).toList();
});

/// Compact Lumina assistant widget for Design Studio
class LuminaDesignAssistant extends ConsumerStatefulWidget {
  const LuminaDesignAssistant({super.key});

  @override
  ConsumerState<LuminaDesignAssistant> createState() => _LuminaDesignAssistantState();
}

class _LuminaDesignAssistantState extends ConsumerState<LuminaDesignAssistant> {
  bool _isExpanded = false;
  String? _pendingSuggestionId;

  @override
  Widget build(BuildContext context) {
    final suggestions = ref.watch(luminaSuggestionsProvider);
    final profile = ref.watch(currentUserProfileProvider).valueOrNull;

    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NexGenPalette.violet.withOpacity(0.15),
            NexGenPalette.cyan.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexGenPalette.violet.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [NexGenPalette.violet, NexGenPalette.cyan],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lumina Suggestions',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (profile != null)
                          Text(
                            _getPersonalizedGreeting(profile),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white60,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),

          // Suggestions list
          if (_isExpanded) ...[
            const Divider(height: 1, color: Colors.white12),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (final suggestion in suggestions.take(4))
                    _SuggestionTile(
                      suggestion: suggestion,
                      isPending: _pendingSuggestionId == suggestion.id,
                      onApply: () => _applySuggestion(suggestion),
                      onPreview: () => _previewSuggestion(suggestion),
                    ),
                ],
              ),
            ),
          ] else ...[
            // Collapsed quick chips
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final suggestion in suggestions.take(3))
                    _QuickChip(
                      suggestion: suggestion,
                      onTap: () => _showConfirmation(suggestion),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getPersonalizedGreeting(UserModel profile) {
    final hour = DateTime.now().hour;
    final name = profile.displayName.split(' ').first;

    if (hour < 12) {
      return 'Good morning, $name';
    } else if (hour < 17) {
      return 'Good afternoon, $name';
    } else {
      return 'Good evening, $name';
    }
  }

  Future<void> _showConfirmation(LuminaSuggestion suggestion) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: NexGenPalette.violet),
            const SizedBox(width: 8),
            Expanded(child: Text(suggestion.title, style: const TextStyle(color: Colors.white))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              suggestion.description,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            if (suggestion.type == LuminaSuggestionType.colorPalette)
              _ColorPreviewRow(colors: suggestion.payload['colors'] as List),
            const SizedBox(height: 8),
            Text(
              'Apply this to your current design?',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _applySuggestion(suggestion);
    }
  }

  void _previewSuggestion(LuminaSuggestion suggestion) {
    setState(() => _pendingSuggestionId = suggestion.id);
    // Just highlight for now - real preview would update canvas temporarily
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _pendingSuggestionId = null);
    });
  }

  void _applySuggestion(LuminaSuggestion suggestion) {
    final selectedChannelId = ref.read(selectedChannelIdProvider);

    switch (suggestion.type) {
      case LuminaSuggestionType.colorPalette:
        _applyColorPalette(suggestion.payload['colors'] as List, selectedChannelId);
        break;
      case LuminaSuggestionType.effect:
        _applyEffect(suggestion.payload, selectedChannelId);
        break;
      case LuminaSuggestionType.completeDesign:
        // Future: apply entire design
        break;
      case LuminaSuggestionType.adjustment:
        // Future: incremental adjustments
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied: ${suggestion.title}'),
        backgroundColor: NexGenPalette.violet,
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.white,
          onPressed: () {
            // TODO: Implement undo
          },
        ),
      ),
    );
  }

  void _applyColorPalette(List colors, int? channelId) {
    if (channelId == null) return;

    final design = ref.read(currentDesignProvider);
    if (design == null) return;

    final channel = design.channels.firstWhere(
      (ch) => ch.channelId == channelId,
      orElse: () => design.channels.first,
    );

    // Apply first color to entire channel
    if (colors.isNotEmpty) {
      final color = colors.first as List;
      final flutterColor = Color.fromARGB(255, color[0] as int, color[1] as int, color[2] as int);
      ref.read(selectedColorProvider.notifier).state = flutterColor;
      ref.read(currentDesignProvider.notifier).fillChannel(channelId, flutterColor);

      // Add to recent colors
      ref.read(recentColorsProvider.notifier).addColor(flutterColor);
    }
  }

  void _applyEffect(Map<String, dynamic> payload, int? channelId) {
    if (channelId == null) return;

    final effectId = payload['effectId'] as int?;
    final speed = payload['speed'] as int?;
    final intensity = payload['intensity'] as int?;

    if (effectId != null) {
      ref.read(currentDesignProvider.notifier).setChannelEffect(channelId, effectId);
    }
    if (speed != null) {
      ref.read(currentDesignProvider.notifier).setChannelSpeed(channelId, speed);
    }
    if (intensity != null) {
      ref.read(currentDesignProvider.notifier).setChannelIntensity(channelId, intensity);
    }
  }
}

class _SuggestionTile extends StatelessWidget {
  final LuminaSuggestion suggestion;
  final bool isPending;
  final VoidCallback onApply;
  final VoidCallback onPreview;

  const _SuggestionTile({
    required this.suggestion,
    required this.isPending,
    required this.onApply,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isPending
            ? NexGenPalette.cyan.withOpacity(0.2)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPending
              ? NexGenPalette.cyan
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          // Type icon
          Icon(
            _getTypeIcon(),
            color: _getTypeColor(),
            size: 20,
          ),
          const SizedBox(width: 10),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  suggestion.description,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Confidence indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getConfidenceColor().withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(suggestion.confidence * 100).round()}%',
              style: TextStyle(
                color: _getConfidenceColor(),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Apply button
          IconButton(
            onPressed: onApply,
            icon: const Icon(Icons.add_circle_outline),
            color: NexGenPalette.cyan,
            tooltip: 'Apply',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  IconData _getTypeIcon() {
    switch (suggestion.type) {
      case LuminaSuggestionType.colorPalette:
        return Icons.palette;
      case LuminaSuggestionType.effect:
        return Icons.auto_awesome;
      case LuminaSuggestionType.completeDesign:
        return Icons.design_services;
      case LuminaSuggestionType.adjustment:
        return Icons.tune;
    }
  }

  Color _getTypeColor() {
    switch (suggestion.type) {
      case LuminaSuggestionType.colorPalette:
        return NexGenPalette.cyan;
      case LuminaSuggestionType.effect:
        return NexGenPalette.violet;
      case LuminaSuggestionType.completeDesign:
        return Colors.amber;
      case LuminaSuggestionType.adjustment:
        return Colors.green;
    }
  }

  Color _getConfidenceColor() {
    if (suggestion.confidence >= 0.8) return Colors.green;
    if (suggestion.confidence >= 0.5) return Colors.amber;
    return Colors.orange;
  }
}

class _QuickChip extends StatelessWidget {
  final LuminaSuggestion suggestion;
  final VoidCallback onTap;

  const _QuickChip({
    required this.suggestion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(
        suggestion.type == LuminaSuggestionType.colorPalette
            ? Icons.palette
            : Icons.auto_awesome,
        size: 16,
        color: NexGenPalette.violet,
      ),
      label: Text(
        suggestion.title,
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: onTap,
      backgroundColor: Colors.white.withOpacity(0.05),
      side: BorderSide(color: NexGenPalette.violet.withOpacity(0.3)),
    );
  }
}

class _ColorPreviewRow extends StatelessWidget {
  final List colors;

  const _ColorPreviewRow({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final color in colors.take(5))
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Color.fromARGB(
                255,
                (color as List)[0] as int,
                color[1] as int,
                color[2] as int,
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Color.fromARGB(
                    100,
                    color[0] as int,
                    color[1] as int,
                    color[2] as int,
                  ),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
