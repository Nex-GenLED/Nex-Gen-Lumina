import 'package:flutter/foundation.dart';

/// Tracks patterns suggested during the current session to avoid repetition.
///
/// For open-ended queries like "surprise me" or "give me a party", users expect
/// variety. This service maintains a rolling history of recent suggestions so
/// the AI can generate fresh alternatives instead of repeating the same pattern.
///
/// Key features:
/// - Session-scoped (clears on app restart)
/// - Rolling history with configurable max size
/// - Provides context strings for AI prompt injection
/// - Detects "open-ended" queries that should receive varied responses
class SuggestionHistoryService {
  SuggestionHistoryService._();
  static final SuggestionHistoryService _instance = SuggestionHistoryService._();
  static SuggestionHistoryService get instance => _instance;

  /// Maximum number of suggestions to remember
  static const int _maxHistorySize = 20;

  /// Recent suggestions: stores pattern name/description and key attributes
  final List<_SuggestionEntry> _history = [];

  /// Patterns that indicate a user wants something creative/varied
  static final List<RegExp> _openEndedPatterns = [
    RegExp(r'\bsurprise\s*(me|us)?\b', caseSensitive: false),
    RegExp(r'\bsomething\s+(different|new|else|random|fun|cool|interesting)\b', caseSensitive: false),
    RegExp(r'\bshow\s+me\s+something\b', caseSensitive: false),
    RegExp(r'\bwhat\s+(do\s+you\s+)?(suggest|recommend|have|got)\b', caseSensitive: false),
    RegExp(r'\bgive\s+(me|us)\s+(a|some|any)\b', caseSensitive: false),
    RegExp(r"\bdealer'?s?\s+choice\b", caseSensitive: false),
    RegExp(r'\byou\s+(pick|choose|decide)\b', caseSensitive: false),
    RegExp(r'\brandom\b', caseSensitive: false),
    RegExp(r'\banything\b', caseSensitive: false),
    RegExp(r'\bwhatever\b', caseSensitive: false),
    RegExp(r'\bimpress\s+me\b', caseSensitive: false),
  ];

  /// Checks if the query is open-ended and should receive varied responses
  static bool isOpenEndedQuery(String query) {
    final normalized = query.toLowerCase().trim();
    return _openEndedPatterns.any((pattern) => pattern.hasMatch(normalized));
  }

  /// Records a suggestion in the history
  void recordSuggestion({
    required String patternName,
    List<String>? colorNames,
    int? effectId,
    String? effectName,
    String? queryType, // e.g., 'party', 'celebration', 'surprise'
  }) {
    final entry = _SuggestionEntry(
      patternName: patternName,
      colorNames: colorNames ?? [],
      effectId: effectId,
      effectName: effectName,
      queryType: queryType,
      timestamp: DateTime.now(),
    );

    _history.add(entry);

    // Trim to max size, keeping most recent
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }

    debugPrint('📝 Recorded suggestion: $patternName (history size: ${_history.length})');
  }

  /// Gets recent suggestions as a context string for AI prompt injection
  /// Returns null if no relevant history exists
  String? getAvoidanceContext({int limit = 5}) {
    if (_history.isEmpty) return null;

    final recent = _history.reversed.take(limit).toList();

    final buffer = StringBuffer();
    buffer.writeln('IMPORTANT - AVOID REPEATING THESE RECENT SUGGESTIONS:');

    for (final entry in recent) {
      buffer.write('- "${entry.patternName}"');
      if (entry.colorNames.isNotEmpty) {
        buffer.write(' (colors: ${entry.colorNames.take(3).join(", ")})');
      }
      if (entry.effectName != null) {
        buffer.write(' [${entry.effectName}]');
      }
      buffer.writeln();
    }

    buffer.writeln();
    buffer.writeln('Generate something DIFFERENT from the above. Use different colors, effects, or themes.');
    buffer.writeln('Be creative and offer variety - the user wants to see new options!');

    return buffer.toString();
  }

  /// Gets a list of recent pattern names (useful for checking duplicates)
  List<String> get recentPatternNames =>
      _history.map((e) => e.patternName.toLowerCase()).toList();

  /// Gets recent color combinations to avoid
  Set<String> get recentColorCombinations {
    final combos = <String>{};
    for (final entry in _history) {
      if (entry.colorNames.length >= 2) {
        // Create a sorted key so [red, blue] == [blue, red]
        final sorted = List<String>.from(entry.colorNames)..sort();
        combos.add(sorted.join('|'));
      }
    }
    return combos;
  }

  /// Gets recent effect IDs to potentially avoid
  Set<int> get recentEffectIds =>
      _history.where((e) => e.effectId != null).map((e) => e.effectId!).toSet();

  /// Checks if a pattern name was recently suggested
  bool wasRecentlySuggested(String patternName) {
    final normalized = patternName.toLowerCase().trim();
    return _history.any((e) =>
        e.patternName.toLowerCase().trim() == normalized ||
        e.patternName.toLowerCase().contains(normalized) ||
        normalized.contains(e.patternName.toLowerCase()));
  }

  /// Gets the number of suggestions in history
  int get historySize => _history.length;

  /// Clears all history (e.g., when user explicitly wants to reset)
  void clearHistory() {
    _history.clear();
    debugPrint('🗑️ Suggestion history cleared');
  }

  /// Clears history for a specific query type
  void clearHistoryForType(String queryType) {
    _history.removeWhere((e) => e.queryType == queryType);
    debugPrint('🗑️ Cleared history for query type: $queryType');
  }
}

class _SuggestionEntry {
  final String patternName;
  final List<String> colorNames;
  final int? effectId;
  final String? effectName;
  final String? queryType;
  final DateTime timestamp;

  const _SuggestionEntry({
    required this.patternName,
    required this.colorNames,
    this.effectId,
    this.effectName,
    this.queryType,
    required this.timestamp,
  });

  @override
  String toString() => 'SuggestionEntry($patternName, colors: $colorNames, effect: $effectName)';
}
