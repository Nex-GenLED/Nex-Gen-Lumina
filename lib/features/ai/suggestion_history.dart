import 'package:flutter/foundation.dart';

/// Tracks patterns suggested during the current session to avoid repetition.
///
/// For open-ended queries like "surprise me" or "give me a party", users expect
/// variety. This service maintains a rolling history of recent suggestions so
/// the AI can generate fresh alternatives instead of repeating the same pattern.
class SuggestionHistoryService {
  SuggestionHistoryService._();
  static final SuggestionHistoryService _instance = SuggestionHistoryService._();
  static SuggestionHistoryService get instance => _instance;

  static const int _maxHistorySize = 20;

  final List<_SuggestionEntry> _history = [];

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

  static final List<RegExp> _specificThemeIndicators = [
    RegExp(r"(st\.?\s*patrick|saint\s*patrick|shamrock)", caseSensitive: false),
    RegExp(r"(christmas|xmas|holiday\s+lights)", caseSensitive: false),
    RegExp(r"(halloween|spooky|trick.or.treat)", caseSensitive: false),
    RegExp(r"(valentine|romantic\s+heart)", caseSensitive: false),
    RegExp(r"(easter|spring\s+pastel)", caseSensitive: false),
    RegExp(r"(4th\s+of\s+july|independence\s+day|patriotic|america)", caseSensitive: false),
    RegExp(r"(thanksgiving|harvest|autumn)", caseSensitive: false),
    RegExp(r"(hanukkah|chanukah|diwali|kwanzaa)", caseSensitive: false),
    RegExp(r"(new\s+year|nye)", caseSensitive: false),
    RegExp(r"(mardi\s+gras|cinco\s+de\s+mayo|pride)", caseSensitive: false),
    RegExp(r"(memorial\s+day|veterans?\s+day|labor\s+day)", caseSensitive: false),
    RegExp(r"(cowboys|eagles|chiefs|packers|steelers|niners|49ers)", caseSensitive: false),
    RegExp(r"(lakers|celtics|bulls|warriors|yankees|dodgers)", caseSensitive: false),
    RegExp(r"(sunset|sunrise|ocean|forest|aurora|rainbow)", caseSensitive: false),
  ];

  static bool isOpenEndedQuery(String query) {
    final normalized = query.toLowerCase().trim();
    final matchesOpenPattern =
        _openEndedPatterns.any((pattern) => pattern.hasMatch(normalized));
    if (!matchesOpenPattern) return false;
    if (_specificThemeIndicators.any((pattern) => pattern.hasMatch(normalized))) {
      return false;
    }
    return true;
  }

  void recordSuggestion({
    required String patternName,
    List<String>? colorNames,
    int? effectId,
    String? effectName,
    String? queryType,
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

    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }

    debugPrint('📝 Recorded suggestion: $patternName '
        '(type: ${queryType ?? "unclassified"}, history size: ${_history.length})');
  }

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

  /// Count suggestions by query type.
  ///
  /// Used by [UserVarietyProfileAnalyzer] to detect open-ended vs consistency
  /// preferences from real session history.
  ///
  /// Known types: 'open_ended', 'specific', 'scheduled', 'consistency'
  int countByQueryType(String queryType) =>
      _history.where((e) => e.queryType == queryType).length;

  List<String> get recentPatternNames =>
      _history.map((e) => e.patternName.toLowerCase()).toList();

  Set<String> get recentColorCombinations {
    final combos = <String>{};
    for (final entry in _history) {
      if (entry.colorNames.length >= 2) {
        final sorted = List<String>.from(entry.colorNames)..sort();
        combos.add(sorted.join('|'));
      }
    }
    return combos;
  }

  Set<int> get recentEffectIds =>
      _history.where((e) => e.effectId != null).map((e) => e.effectId!).toSet();

  bool wasRecentlySuggested(String patternName) {
    final normalized = patternName.toLowerCase().trim();
    return _history.any((e) =>
        e.patternName.toLowerCase().trim() == normalized ||
        e.patternName.toLowerCase().contains(normalized) ||
        normalized.contains(e.patternName.toLowerCase()));
  }

  int get historySize => _history.length;

  void clearHistory() {
    _history.clear();
    debugPrint('🗑️ Suggestion history cleared');
  }

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
  String toString() =>
      'SuggestionEntry($patternName, colors: $colorNames, effect: $effectName, type: $queryType)';
}