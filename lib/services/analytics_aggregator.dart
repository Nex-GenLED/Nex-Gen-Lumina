import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/models/analytics_models.dart';

/// Service for aggregating anonymized analytics across all users.
///
/// This service pushes privacy-preserving analytics to global collections
/// to track pattern trends, color preferences, and effect popularity.
///
/// PRIVACY: All user IDs are hashed before storage. No PII is stored.
class AnalyticsAggregator {
  final FirebaseFirestore _firestore;
  final String userId;

  AnalyticsAggregator({
    required this.userId,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  // ==================== Privacy Helpers ====================

  /// Hash user ID for privacy (SHA-256)
  String _hashUserId(String uid) {
    final bytes = utf8.encode(uid);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Sanitize pattern name (remove any potential PII)
  String _sanitizePatternName(String? name) {
    if (name == null || name.isEmpty) return 'unknown';
    // Remove any email-like patterns, phone numbers, etc.
    final sanitized = name.replaceAll(RegExp(r'[^\w\s-]'), '');
    return sanitized.trim().toLowerCase();
  }

  // ==================== Global Analytics ====================

  /// Contribute pattern usage to global analytics
  Future<void> contributePatternUsage(PatternUsageEvent event) async {
    try {
      final anonymousId = _hashUserId(userId);
      final patternId = _sanitizePatternName(event.patternName ?? 'effect_${event.effectId}');

      // Update pattern stats
      final patternRef = _firestore
          .collection('analytics')
          .doc('global_pattern_stats')
          .collection('patterns')
          .doc(patternId);

      await patternRef.set({
        'pattern_name': patternId,
        'total_applications': FieldValue.increment(1),
        'effect_id': event.effectId,
        'effect_name': event.effectName,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Track unique users (using subcollection with hashed IDs)
      await patternRef.collection('users').doc(anonymousId).set({
        'last_seen': FieldValue.serverTimestamp(),
      });

      // Update color preferences if available
      if (event.colorNames != null && event.colorNames!.isNotEmpty) {
        await _contributeColorUsage(event.colorNames!);
      }

      // Update effect popularity if available
      if (event.effectId != null) {
        await _contributeEffectUsage(
          effectId: event.effectId!,
          effectName: event.effectName,
          speed: event.speed,
          intensity: event.intensity,
        );
      }
    } catch (e) {
      debugPrint('❌ contributePatternUsage failed: $e');
    }
  }

  /// Contribute color usage to global analytics
  Future<void> _contributeColorUsage(List<String> colorNames) async {
    try {
      final weekId = _getWeekId(DateTime.now());
      final colorRef = _firestore.collection('analytics').doc('color_trends').collection('weekly').doc(weekId);

      for (final colorName in colorNames) {
        final sanitizedColor = _sanitizePatternName(colorName);
        await colorRef.set({
          'week_of': FieldValue.serverTimestamp(),
          'colors.$sanitizedColor': FieldValue.increment(1),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('❌ _contributeColorUsage failed: $e');
    }
  }

  /// Contribute effect usage to global analytics
  Future<void> _contributeEffectUsage({
    required int effectId,
    String? effectName,
    int? speed,
    int? intensity,
  }) async {
    try {
      final effectRef = _firestore.collection('analytics').doc('effect_popularity').collection('effects').doc('effect_$effectId');

      final updateData = <String, dynamic>{
        'effect_id': effectId,
        'effect_name': effectName ?? 'Unknown',
        'usage_count': FieldValue.increment(1),
        'last_updated': FieldValue.serverTimestamp(),
      };

      // Track average speed/intensity if provided
      if (speed != null) {
        updateData['total_speed'] = FieldValue.increment(speed);
      }
      if (intensity != null) {
        updateData['total_intensity'] = FieldValue.increment(intensity);
      }

      await effectRef.set(updateData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ _contributeEffectUsage failed: $e');
    }
  }

  /// Submit pattern feedback (rating, saved, etc.)
  Future<void> submitPatternFeedback({
    required String patternName,
    required int rating,
    String? comment,
    required bool saved,
    String? source,
  }) async {
    try {
      final anonymousId = _hashUserId(userId);
      final sanitizedPattern = _sanitizePatternName(patternName);

      // Store in user's personal feedback (for their records)
      await _firestore.collection('users').doc(userId).collection('pattern_feedback').add({
        'pattern_name': sanitizedPattern,
        'rating': rating.clamp(1, 5),
        'comment': comment,
        'saved': saved,
        'created_at': FieldValue.serverTimestamp(),
        'source': source,
      });

      // Aggregate to global feedback stats
      final feedbackRef = _firestore
          .collection('analytics')
          .doc('pattern_feedback')
          .collection('patterns')
          .doc(sanitizedPattern);

      await feedbackRef.set({
        'pattern_name': sanitizedPattern,
        'total_ratings': FieldValue.increment(1),
        'total_stars': FieldValue.increment(rating),
        'save_count': saved ? FieldValue.increment(1) : 0,
        'rating_distribution.stars_$rating': FieldValue.increment(1),
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Track anonymous rater
      await feedbackRef.collection('raters').doc(anonymousId).set({
        'last_rated': FieldValue.serverTimestamp(),
      });

      debugPrint('✅ Pattern feedback submitted: $sanitizedPattern (rating: $rating)');
    } catch (e) {
      debugPrint('❌ submitPatternFeedback failed: $e');
    }
  }

  /// Request a missing pattern
  Future<void> requestPattern({
    required String requestedTheme,
    String? description,
    List<String>? suggestedColors,
    String? suggestedCategory,
  }) async {
    try {
      final anonymousId = _hashUserId(userId);
      final sanitizedTheme = _sanitizePatternName(requestedTheme);

      // Check if this request already exists
      final existingQuery = await _firestore
          .collection('analytics')
          .doc('pattern_requests')
          .collection('requests')
          .where('requested_theme', isEqualTo: sanitizedTheme)
          .where('fulfilled', isEqualTo: false)
          .limit(1)
          .get();

      if (existingQuery.docs.isNotEmpty) {
        // Increment vote count on existing request
        final docId = existingQuery.docs.first.id;
        await _firestore
            .collection('analytics')
            .doc('pattern_requests')
            .collection('requests')
            .doc(docId)
            .update({
          'vote_count': FieldValue.increment(1),
          'last_voted': FieldValue.serverTimestamp(),
        });

        // Track this user voted
        await _firestore
            .collection('analytics')
            .doc('pattern_requests')
            .collection('requests')
            .doc(docId)
            .collection('voters')
            .doc(anonymousId)
            .set({'voted_at': FieldValue.serverTimestamp()});

        debugPrint('✅ Upvoted existing pattern request: $sanitizedTheme');
      } else {
        // Create new request
        final docRef = await _firestore.collection('analytics').doc('pattern_requests').collection('requests').add({
          'requested_theme': sanitizedTheme,
          'description': description,
          'suggested_colors': suggestedColors,
          'suggested_category': suggestedCategory,
          'created_at': FieldValue.serverTimestamp(),
          'vote_count': 1,
          'fulfilled': false,
        });

        // Track creator as first voter
        await docRef.collection('voters').doc(anonymousId).set({
          'voted_at': FieldValue.serverTimestamp(),
        });

        debugPrint('✅ New pattern request created: $sanitizedTheme');
      }
    } catch (e) {
      debugPrint('❌ requestPattern failed: $e');
    }
  }

  /// Vote on an existing pattern request
  Future<void> voteForPatternRequest(String requestId) async {
    try {
      final anonymousId = _hashUserId(userId);

      // Check if user already voted
      final voterDoc = await _firestore
          .collection('analytics')
          .doc('pattern_requests')
          .collection('requests')
          .doc(requestId)
          .collection('voters')
          .doc(anonymousId)
          .get();

      if (voterDoc.exists) {
        debugPrint('⚠️ User already voted for this pattern request');
        return;
      }

      // Increment vote count
      await _firestore.collection('analytics').doc('pattern_requests').collection('requests').doc(requestId).update({
        'vote_count': FieldValue.increment(1),
        'last_voted': FieldValue.serverTimestamp(),
      });

      // Track voter
      await _firestore
          .collection('analytics')
          .doc('pattern_requests')
          .collection('requests')
          .doc(requestId)
          .collection('voters')
          .doc(anonymousId)
          .set({'voted_at': FieldValue.serverTimestamp()});

      debugPrint('✅ Voted for pattern request: $requestId');
    } catch (e) {
      debugPrint('❌ voteForPatternRequest failed: $e');
    }
  }

  // ==================== Helper Methods ====================

  /// Get week identifier (e.g., "2026-W04")
  String _getWeekId(DateTime date) {
    final weekNumber = _getWeekNumber(date);
    return '${date.year}-W${weekNumber.toString().padLeft(2, '0')}';
  }

  /// Calculate ISO week number
  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSinceFirstDay = date.difference(firstDayOfYear).inDays;
    return ((daysSinceFirstDay + firstDayOfYear.weekday) / 7).ceil();
  }

  // ==================== Query Methods (for displaying trends in app) ====================

  /// Get top trending patterns
  Future<List<GlobalPatternStats>> getTrendingPatterns({int limit = 10}) async {
    try {
      final snapshot = await _firestore
          .collection('analytics')
          .doc('global_pattern_stats')
          .collection('patterns')
          .orderBy('total_applications', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => GlobalPatternStats.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('❌ getTrendingPatterns failed: $e');
      return [];
    }
  }

  /// Get most requested patterns
  Future<List<PatternRequest>> getMostRequestedPatterns({int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection('analytics')
          .doc('pattern_requests')
          .collection('requests')
          .where('fulfilled', isEqualTo: false)
          .orderBy('vote_count', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => PatternRequest.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('❌ getMostRequestedPatterns failed: $e');
      return [];
    }
  }

  /// Get effect popularity stats
  Future<List<EffectPopularity>> getEffectPopularity({int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection('analytics')
          .doc('effect_popularity')
          .collection('effects')
          .orderBy('usage_count', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => EffectPopularity.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('❌ getEffectPopularity failed: $e');
      return [];
    }
  }

  /// Stream trending patterns (real-time)
  Stream<List<GlobalPatternStats>> streamTrendingPatterns({int limit = 10}) {
    return _firestore
        .collection('analytics')
        .doc('global_pattern_stats')
        .collection('patterns')
        .orderBy('total_applications', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => GlobalPatternStats.fromFirestore(doc)).toList());
  }

  /// Stream most requested patterns (real-time)
  Stream<List<PatternRequest>> streamMostRequestedPatterns({int limit = 20}) {
    return _firestore
        .collection('analytics')
        .doc('pattern_requests')
        .collection('requests')
        .where('fulfilled', isEqualTo: false)
        .orderBy('vote_count', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => PatternRequest.fromFirestore(doc)).toList());
  }
}
