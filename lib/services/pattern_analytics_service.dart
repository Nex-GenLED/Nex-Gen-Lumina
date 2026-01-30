import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/models/pattern_analytics_models.dart';

/// Service for recording and retrieving pattern analytics for global learning.
///
/// This service enables Lumina to learn from all users' feedback:
/// - Records when patterns are applied
/// - Tracks thumbs up/down reactions
/// - Aggregates data to find winning configurations
/// - Provides context for AI recommendations
class PatternAnalyticsService {
  final FirebaseFirestore _firestore;

  PatternAnalyticsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // Collection references
  CollectionReference<Map<String, dynamic>> get _analyticsCollection =>
      _firestore.collection('pattern_analytics');

  CollectionReference<Map<String, dynamic>> get _feedbackCollection =>
      _firestore.collection('pattern_feedback');

  CollectionReference<Map<String, dynamic>> get _vibeCorrectionsCollection =>
      _firestore.collection('vibe_corrections');

  CollectionReference<Map<String, dynamic>> get _learnedPatternsCollection =>
      _firestore.collection('learned_patterns');

  // ═══════════════════════════════════════════════════════════════════════════
  // Query Normalization & Hashing
  // ═══════════════════════════════════════════════════════════════════════════

  /// Normalize a query for consistent matching
  /// Removes filler words, lowercases, trims
  static String normalizeQuery(String query) {
    final lower = query.toLowerCase().trim();

    // Remove common filler words
    final fillers = [
      'please', 'can you', 'could you', 'would you',
      'i want', 'i\'d like', 'give me', 'show me',
      'let\'s', 'let me', 'make it', 'set the',
      'lights to', 'the lights', 'my lights',
      'something', 'a bit', 'kind of', 'sort of',
    ];

    var normalized = lower;
    for (final filler in fillers) {
      normalized = normalized.replaceAll(filler, '').trim();
    }

    // Remove extra whitespace
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    return normalized;
  }

  /// Create a hash for a normalized query
  static String createQueryHash(String query) {
    final normalized = normalizeQuery(query);
    final bytes = utf8.encode(normalized);
    final digest = md5.convert(bytes);
    return digest.toString().substring(0, 12); // Shorter hash for readability
  }

  /// Extract the primary theme from a query
  static String? extractPrimaryTheme(String query) {
    final normalized = normalizeQuery(query);

    // Priority order for theme detection
    final themes = [
      // Holidays
      'christmas', 'xmas', 'holiday',
      'halloween', 'spooky',
      '4th of july', 'fourth of july', 'independence day', 'patriotic',
      'valentines', 'valentine', 'romantic',
      'st patricks', 'st paddys', 'irish',
      'easter', 'spring',
      'thanksgiving', 'autumn', 'fall',
      'new years', 'new year',
      // Sports
      'chiefs', 'cowboys', 'royals', 'titans',
      // Moods
      'party', 'celebration', 'celebrate',
      'calm', 'relaxing', 'relax',
      'elegant', 'classy', 'fancy',
      'cozy', 'warm',
      'ocean', 'beach', 'water',
      'sunset', 'sunrise',
      'neon', 'cyberpunk',
    ];

    for (final theme in themes) {
      if (normalized.contains(theme)) {
        return theme;
      }
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Feedback Recording
  // ═══════════════════════════════════════════════════════════════════════════

  /// Record when a pattern is applied
  Future<void> recordPatternApplied({
    required String query,
    required int effectId,
    required String effectName,
    required List<List<int>> colors,
    required List<String> colorNames,
    required int speed,
    required int intensity,
    required int brightness,
    String? userId,
    Map<String, dynamic>? wledPayload,
  }) async {
    try {
      final queryHash = createQueryHash(query);

      final event = PatternFeedbackEvent(
        id: '', // Will be auto-generated
        userId: userId,
        queryHash: queryHash,
        originalQuery: query,
        feedbackType: FeedbackType.applied,
        effectId: effectId,
        effectName: effectName,
        colors: colors,
        colorNames: colorNames,
        speed: speed,
        intensity: intensity,
        brightness: brightness,
        createdAt: DateTime.now(),
        wledPayload: wledPayload,
      );

      await _feedbackCollection.add(event.toFirestore());

      // Update aggregated analytics
      await _updateAggregatedAnalytics(
        queryHash: queryHash,
        originalQuery: query,
        effectId: effectId,
        effectName: effectName,
        colors: colors,
        colorNames: colorNames,
        speed: speed,
        intensity: intensity,
        brightness: brightness,
        incrementApplications: true,
        userId: userId,
      );

      debugPrint('📊 Recorded pattern applied: $queryHash');
    } catch (e) {
      debugPrint('Error recording pattern applied: $e');
    }
  }

  /// Record thumbs up feedback
  Future<void> recordThumbsUp({
    required String query,
    required int effectId,
    required String effectName,
    required List<List<int>> colors,
    required List<String> colorNames,
    String? userId,
  }) async {
    try {
      final queryHash = createQueryHash(query);

      final event = PatternFeedbackEvent(
        id: '',
        userId: userId,
        queryHash: queryHash,
        originalQuery: query,
        feedbackType: FeedbackType.thumbsUp,
        effectId: effectId,
        effectName: effectName,
        colors: colors,
        colorNames: colorNames,
        createdAt: DateTime.now(),
      );

      await _feedbackCollection.add(event.toFirestore());

      // Update aggregated analytics
      await _updateAggregatedAnalytics(
        queryHash: queryHash,
        originalQuery: query,
        effectId: effectId,
        effectName: effectName,
        colors: colors,
        colorNames: colorNames,
        incrementThumbsUp: true,
        userId: userId,
      );

      debugPrint('👍 Recorded thumbs up: $queryHash');
    } catch (e) {
      debugPrint('Error recording thumbs up: $e');
    }
  }

  /// Record thumbs down feedback with reason
  Future<void> recordThumbsDown({
    required String query,
    required int effectId,
    required String effectName,
    required String reason,
    String? userId,
  }) async {
    try {
      final queryHash = createQueryHash(query);

      final event = PatternFeedbackEvent(
        id: '',
        userId: userId,
        queryHash: queryHash,
        originalQuery: query,
        feedbackType: FeedbackType.thumbsDown,
        effectId: effectId,
        effectName: effectName,
        feedbackReason: reason,
        createdAt: DateTime.now(),
      );

      await _feedbackCollection.add(event.toFirestore());

      // Update aggregated analytics
      await _updateAggregatedAnalytics(
        queryHash: queryHash,
        originalQuery: query,
        incrementThumbsDown: true,
        userId: userId,
      );

      debugPrint('👎 Recorded thumbs down: $queryHash - $reason');
    } catch (e) {
      debugPrint('Error recording thumbs down: $e');
    }
  }

  /// Record a refinement request
  Future<void> recordRefinement({
    required String query,
    required String refinementType,
    required int originalEffectId,
    int? newEffectId,
    String? userId,
  }) async {
    try {
      final queryHash = createQueryHash(query);

      final event = PatternFeedbackEvent(
        id: '',
        userId: userId,
        queryHash: queryHash,
        originalQuery: query,
        feedbackType: FeedbackType.refined,
        effectId: originalEffectId,
        refinementType: refinementType,
        createdAt: DateTime.now(),
      );

      await _feedbackCollection.add(event.toFirestore());

      // Update refinement counts in analytics
      final docRef = _analyticsCollection.doc(queryHash);
      await docRef.set({
        'common_refinements': {
          refinementType: FieldValue.increment(1),
        },
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('🔧 Recorded refinement: $queryHash - $refinementType');
    } catch (e) {
      debugPrint('Error recording refinement: $e');
    }
  }

  /// Record a vibe correction (when user says "Wrong Vibe")
  Future<void> recordVibeCorrection({
    required String query,
    required String detectedVibe,
    required String desiredVibe,
    int? originalEffectId,
    String? userId,
  }) async {
    try {
      final record = VibeCorrectionRecord(
        id: '',
        userId: userId,
        originalQuery: query,
        detectedVibe: detectedVibe,
        desiredVibe: desiredVibe,
        originalEffectId: originalEffectId,
        createdAt: DateTime.now(),
      );

      await _vibeCorrectionsCollection.add(record.toFirestore());
      debugPrint('🎭 Recorded vibe correction: $detectedVibe → $desiredVibe');
    } catch (e) {
      debugPrint('Error recording vibe correction: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Aggregation
  // ═══════════════════════════════════════════════════════════════════════════

  /// Update aggregated analytics for a query
  Future<void> _updateAggregatedAnalytics({
    required String queryHash,
    required String originalQuery,
    int? effectId,
    String? effectName,
    List<List<int>>? colors,
    List<String>? colorNames,
    int? speed,
    int? intensity,
    int? brightness,
    bool incrementApplications = false,
    bool incrementThumbsUp = false,
    bool incrementThumbsDown = false,
    String? userId,
  }) async {
    try {
      final docRef = _analyticsCollection.doc(queryHash);
      final doc = await docRef.get();

      if (!doc.exists) {
        // Create new analytics entry
        final analytics = PatternAnalytics(
          id: queryHash,
          queryVariants: [originalQuery],
          normalizedQuery: normalizeQuery(originalQuery),
          totalApplications: incrementApplications ? 1 : 0,
          thumbsUp: incrementThumbsUp ? 1 : 0,
          thumbsDown: incrementThumbsDown ? 1 : 0,
          bestEffectId: effectId,
          bestEffectName: effectName,
          bestColors: colors,
          bestColorNames: colorNames,
          avgSpeed: speed,
          avgIntensity: intensity,
          avgBrightness: brightness,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          uniqueUsers: userId != null ? 1 : 0,
        );

        await docRef.set(analytics.toFirestore());
      } else {
        // Update existing entry
        final updates = <String, dynamic>{
          'updated_at': FieldValue.serverTimestamp(),
        };

        if (incrementApplications) {
          updates['total_applications'] = FieldValue.increment(1);
        }
        if (incrementThumbsUp) {
          updates['thumbs_up'] = FieldValue.increment(1);

          // If thumbs up, this config is successful - update best values
          if (effectId != null) updates['best_effect_id'] = effectId;
          if (effectName != null) updates['best_effect_name'] = effectName;
          if (colors != null) updates['best_colors'] = colors;
          if (colorNames != null) updates['best_color_names'] = colorNames;
        }
        if (incrementThumbsDown) {
          updates['thumbs_down'] = FieldValue.increment(1);
        }

        // Add query variant if not already present
        final existingVariants =
            (doc.data()?['query_variants'] as List?)?.cast<String>() ?? [];
        if (!existingVariants.contains(originalQuery)) {
          updates['query_variants'] = FieldValue.arrayUnion([originalQuery]);
        }

        await docRef.update(updates);
      }
    } catch (e) {
      debugPrint('Error updating aggregated analytics: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Retrieval for AI Context
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get analytics for a specific query
  Future<PatternAnalytics?> getAnalyticsForQuery(String query) async {
    try {
      final queryHash = createQueryHash(query);
      final doc = await _analyticsCollection.doc(queryHash).get();

      if (!doc.exists) return null;
      return PatternAnalytics.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getting analytics for query: $e');
      return null;
    }
  }

  /// Get top-rated patterns for a theme
  Future<List<PatternAnalytics>> getTopRatedPatternsForTheme(
    String theme, {
    int limit = 5,
    double minApprovalRate = 0.7,
    int minSampleSize = 10,
  }) async {
    try {
      // Query patterns that contain this theme in their normalized query
      final snapshot = await _analyticsCollection
          .where('total_applications', isGreaterThanOrEqualTo: minSampleSize)
          .orderBy('total_applications', descending: true)
          .limit(50) // Get more to filter
          .get();

      final results = <PatternAnalytics>[];
      final themeLower = theme.toLowerCase();

      for (final doc in snapshot.docs) {
        final analytics = PatternAnalytics.fromFirestore(doc);

        // Check if this matches our theme
        if (analytics.normalizedQuery.contains(themeLower) ||
            analytics.queryVariants.any((v) => v.toLowerCase().contains(themeLower))) {
          // Check approval rate
          if (analytics.approvalRate >= minApprovalRate) {
            results.add(analytics);
          }
        }

        if (results.length >= limit) break;
      }

      // Sort by approval rate
      results.sort((a, b) => b.approvalRate.compareTo(a.approvalRate));

      return results;
    } catch (e) {
      debugPrint('Error getting top rated patterns: $e');
      return [];
    }
  }

  /// Get globally top-performing patterns
  Future<List<LearnedPatternPreference>> getTopPerformingPatterns({
    int limit = 10,
  }) async {
    try {
      final snapshot = await _learnedPatternsCollection
          .orderBy('approval_rate', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => LearnedPatternPreference.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error getting top performing patterns: $e');
      return [];
    }
  }

  /// Build AI context string from global learning data
  Future<String?> buildGlobalLearningContext(String query) async {
    try {
      final theme = extractPrimaryTheme(query);
      if (theme == null) return null;

      final topPatterns = await getTopRatedPatternsForTheme(theme, limit: 3);
      if (topPatterns.isEmpty) return null;

      final buffer = StringBuffer();
      buffer.writeln('GLOBAL USER PREFERENCES (learned from all users):');

      for (final pattern in topPatterns) {
        final colorDesc = pattern.bestColorNames?.join(', ') ?? 'N/A';
        final effectDesc = pattern.bestEffectName ?? 'N/A';
        final approval = (pattern.approvalRate * 100).toStringAsFixed(0);

        buffer.writeln(
          '- "${pattern.normalizedQuery}" → $effectDesc with $colorDesc ($approval% approval, ${pattern.totalApplications} uses)',
        );
      }

      // Add common refinements if any
      final analytics = await getAnalyticsForQuery(query);
      if (analytics != null && analytics.commonRefinements.isNotEmpty) {
        final topRefinements = analytics.commonRefinements.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        if (topRefinements.isNotEmpty) {
          buffer.writeln(
            'Common adjustments users make: ${topRefinements.take(3).map((e) => e.key).join(", ")}',
          );
        }
      }

      return buffer.toString();
    } catch (e) {
      debugPrint('Error building global learning context: $e');
      return null;
    }
  }
}

/// Provider for PatternAnalyticsService
final patternAnalyticsServiceProvider = Provider<PatternAnalyticsService>((ref) {
  return PatternAnalyticsService();
});

/// Provider for global learning context for a query
final globalLearningContextProvider =
    FutureProvider.family<String?, String>((ref, query) async {
  final service = ref.read(patternAnalyticsServiceProvider);
  return service.buildGlobalLearningContext(query);
});
