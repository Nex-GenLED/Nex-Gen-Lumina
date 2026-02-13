import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/schedule/schedule_entity_extractor.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_signal_words.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// Complexity level for a schedule request, determining how the Cloud AI
/// should handle it.
enum ScheduleComplexity {
  /// Single event, all parameters clear — AI returns ready_to_execute.
  simple,

  /// Recurring or has one ambiguity — AI returns confirm_plan.
  moderate,

  /// Multi-part, creative, or conflict-prone — AI asks clarifications first.
  complex,
}

/// The routing instruction sent to the Cloud AI alongside the request.
enum ScheduleRoutingInstruction {
  /// AI should return a fully formed schedule, ready to apply immediately.
  readyToExecute,

  /// AI should return a plan with assumptions noted for user confirmation.
  confirmPlan,

  /// AI should ask clarifying questions before generating a plan.
  needsClarificationFirst,
}

/// Result of running the [ScheduleComplexityClassifier] on a natural-language
/// scheduling request.
class ScheduleClassificationResult {
  /// The determined complexity level.
  final ScheduleComplexity complexity;

  /// Which signal categories contributed to this classification.
  final List<String> signals;

  /// Structured entities extracted from the input text.
  final ScheduleEntities extractedEntities;

  /// The routing instruction for the Cloud AI.
  final ScheduleRoutingInstruction routingInstruction;

  /// Cumulative score for simple signals.
  final double simpleScore;

  /// Cumulative score for moderate signals.
  final double moderateScore;

  /// Cumulative score for complex signals.
  final double complexScore;

  /// Human-readable explanation for debug logs.
  final String reasoning;

  /// Number of existing schedules that may conflict.
  final int existingScheduleCount;

  const ScheduleClassificationResult({
    required this.complexity,
    required this.signals,
    required this.extractedEntities,
    required this.routingInstruction,
    required this.simpleScore,
    required this.moderateScore,
    required this.complexScore,
    required this.reasoning,
    required this.existingScheduleCount,
  });

  /// Serialize to the JSON output format described in the spec.
  Map<String, dynamic> toJson() => {
        'complexity': complexity.name,
        'signals': signals,
        'extractedEntities': extractedEntities.toJson(),
        'routingInstruction': _routingInstructionToString(routingInstruction),
        'scores': {
          'simple': double.parse(simpleScore.toStringAsFixed(2)),
          'moderate': double.parse(moderateScore.toStringAsFixed(2)),
          'complex': double.parse(complexScore.toStringAsFixed(2)),
        },
        'reasoning': reasoning,
        'existingScheduleCount': existingScheduleCount,
      };

  static String _routingInstructionToString(ScheduleRoutingInstruction ri) {
    switch (ri) {
      case ScheduleRoutingInstruction.readyToExecute:
        return 'ready_to_execute';
      case ScheduleRoutingInstruction.confirmPlan:
        return 'confirm_plan';
      case ScheduleRoutingInstruction.needsClarificationFirst:
        return 'needs_clarification_first';
    }
  }

  @override
  String toString() =>
      'ScheduleClassificationResult(${complexity.name}, '
      's=${simpleScore.toStringAsFixed(2)}, '
      'm=${moderateScore.toStringAsFixed(2)}, '
      'c=${complexScore.toStringAsFixed(2)}, '
      'signals=${signals.length})';
}

// ---------------------------------------------------------------------------
// Provider — stores the latest schedule classification
// ---------------------------------------------------------------------------

/// The most recent schedule classification result.
///
/// Set by the schedule command pipeline before routing to AI. Read by
/// downstream consumers to inject context into the AI system prompt.
final latestScheduleClassificationProvider =
    StateProvider<ScheduleClassificationResult?>((ref) => null);

// ---------------------------------------------------------------------------
// Classifier
// ---------------------------------------------------------------------------

/// Classifies natural-language scheduling requests by complexity level
/// BEFORE sending to the Cloud AI.
///
/// Runs entirely on-device using keyword scoring and entity extraction.
/// The classification determines:
/// 1. What instruction to give the AI (execute immediately vs. confirm vs.
///    ask questions first)
/// 2. What structured entities to pass alongside the raw text
/// 3. How to set user expectations for response time
///
/// ## Classification pipeline
/// 1. Tokenize and normalize input text
/// 2. Extract entities (times, dates, teams, zones, etc.)
/// 3. Score against simple / moderate / complex signal word lists
/// 4. Apply contextual bonuses (multi-zone, variation + multi-day, etc.)
/// 5. Check for conflict risk against existing schedule count
/// 6. Return classification + routing instruction + extracted entities
class ScheduleComplexityClassifier {
  ScheduleComplexityClassifier._();

  /// Classify [text] and return a [ScheduleClassificationResult].
  ///
  /// [ref] provides access to existing schedule state for conflict detection.
  static ScheduleClassificationResult classify(Ref ref, String text) {
    final lower = text.toLowerCase().trim();
    final signals = <String>[];
    double simpleScore = 0.0;
    double moderateScore = 0.0;
    double complexScore = 0.0;

    // -----------------------------------------------------------------
    // 1. Extract entities
    // -----------------------------------------------------------------
    final entities = ScheduleEntityExtractor.extract(text);

    // -----------------------------------------------------------------
    // 2. Score against simple signals
    // -----------------------------------------------------------------
    for (final signal in simpleScheduleSignals) {
      if (_matches(lower, signal)) {
        simpleScore += signal.weight;
        signals.add('simple:${signal.keyword}');
      }
    }

    // -----------------------------------------------------------------
    // 3. Score against moderate signals
    // -----------------------------------------------------------------
    for (final signal in moderateScheduleSignals) {
      if (_matches(lower, signal)) {
        moderateScore += signal.weight;
        signals.add('moderate:${signal.keyword}');
      }
    }

    // -----------------------------------------------------------------
    // 4. Score against complex signals
    // -----------------------------------------------------------------
    for (final signal in complexScheduleSignals) {
      if (_matches(lower, signal)) {
        complexScore += signal.weight;
        signals.add('complex:${signal.keyword}');
      }
    }

    // -----------------------------------------------------------------
    // 5. Score multi-day indicators
    // -----------------------------------------------------------------
    bool hasMultiDay = false;
    for (final signal in multiDaySignals) {
      if (_matches(lower, signal)) {
        hasMultiDay = true;
        // Multi-day alone pushes toward moderate
        moderateScore += signal.weight * 0.4;
        signals.add('multiday:${signal.keyword}');
      }
    }

    // -----------------------------------------------------------------
    // 6. Score creative indicators
    // -----------------------------------------------------------------
    bool hasCreative = false;
    for (final signal in creativeSignals) {
      if (_matches(lower, signal)) {
        hasCreative = true;
        // Creative alone pushes toward moderate-to-complex
        moderateScore += signal.weight * 0.3;
        complexScore += signal.weight * 0.3;
        signals.add('creative:${signal.keyword}');
      }
    }

    // -----------------------------------------------------------------
    // 7. Contextual bonuses
    // -----------------------------------------------------------------

    // Multi-zone bonus: multiple zones → complex
    if (entities.zoneReferences.length > 1) {
      complexScore += kMultiZoneBonus;
      signals.add('ctx:multi_zone');
    }

    // Variation + multi-day together → strong complex signal
    if (entities.variation != null && hasMultiDay) {
      complexScore += kVariationMultiDayBonus;
      signals.add('ctx:variation_multi_day');
    }

    // Creative + multi-day → pushes toward complex
    if (hasCreative && hasMultiDay) {
      complexScore += 0.25;
      signals.add('ctx:creative_multi_day');
    }

    // Team reference + variation → complex (need to generate varied designs)
    if (entities.teamReference != null && entities.variation != null) {
      complexScore += 0.30;
      signals.add('ctx:team_variation');
    }

    // Cancel/delete penalty — these are inherently simple
    if (entities.actionReferences.any((a) =>
        a == 'cancel' || a == 'delete' || a == 'remove' || a == 'disable')) {
      complexScore -= kCancelPenalty;
      moderateScore -= kCancelPenalty * 0.5;
      signals.add('ctx:cancel_penalty');
    }

    // -----------------------------------------------------------------
    // 8. Check conflict risk against existing schedules
    // -----------------------------------------------------------------
    final existingSchedules = ref.read(schedulesProvider);
    final existingCount = existingSchedules.length;

    // Many existing schedules + new multi-day request = conflict risk
    if (existingCount >= 5 && hasMultiDay) {
      complexScore += 0.20;
      signals.add('ctx:conflict_risk_high');
    } else if (existingCount >= 3 && hasMultiDay) {
      moderateScore += 0.15;
      signals.add('ctx:conflict_risk_moderate');
    }

    // -----------------------------------------------------------------
    // 9. Determine classification
    // -----------------------------------------------------------------
    // Clamp scores to zero
    if (simpleScore < 0) simpleScore = 0;
    if (moderateScore < 0) moderateScore = 0;
    if (complexScore < 0) complexScore = 0;

    ScheduleComplexity complexity;
    String reasoning;

    if (complexScore >= kComplexOverrideThreshold) {
      // Strong complex signals override everything
      complexity = ScheduleComplexity.complex;
      reasoning = 'Complex override: score ${complexScore.toStringAsFixed(2)} '
          '>= threshold $kComplexOverrideThreshold';
    } else if (complexScore > simpleScore + kComplexMargin &&
        complexScore > moderateScore) {
      // Complex wins by margin
      complexity = ScheduleComplexity.complex;
      reasoning = 'Complex wins by margin: '
          'c=${complexScore.toStringAsFixed(2)} > '
          's=${simpleScore.toStringAsFixed(2)}+$kComplexMargin';
    } else if (simpleScore >= kSimpleThreshold &&
        simpleScore > moderateScore &&
        simpleScore > complexScore) {
      // Simple wins clearly
      complexity = ScheduleComplexity.simple;
      reasoning = 'Simple wins: s=${simpleScore.toStringAsFixed(2)} '
          '(>= $kSimpleThreshold, beats m=${moderateScore.toStringAsFixed(2)}, '
          'c=${complexScore.toStringAsFixed(2)})';
    } else if (moderateScore >= kModerateThreshold ||
        (hasCreative && !hasMultiDay && entities.variation == null)) {
      // Moderate: has theme/ambiguity but not multi-day variation
      complexity = ScheduleComplexity.moderate;
      reasoning = 'Moderate: m=${moderateScore.toStringAsFixed(2)}, '
          'creative=$hasCreative, multiDay=$hasMultiDay';
    } else if (simpleScore > 0 &&
        simpleScore >= moderateScore &&
        simpleScore >= complexScore) {
      // Simple has some score and nothing else is stronger
      complexity = ScheduleComplexity.simple;
      reasoning = 'Simple default: s=${simpleScore.toStringAsFixed(2)} '
          '>= m=${moderateScore.toStringAsFixed(2)}, '
          'c=${complexScore.toStringAsFixed(2)}';
    } else if (complexScore > moderateScore) {
      complexity = ScheduleComplexity.complex;
      reasoning = 'Complex edges moderate: '
          'c=${complexScore.toStringAsFixed(2)} > '
          'm=${moderateScore.toStringAsFixed(2)}';
    } else if (moderateScore > 0) {
      complexity = ScheduleComplexity.moderate;
      reasoning = 'Moderate fallback: m=${moderateScore.toStringAsFixed(2)}';
    } else {
      // No strong signals at all — default to moderate to be safe
      complexity = ScheduleComplexity.moderate;
      reasoning = 'No strong signals — defaulting to moderate '
          '(s=${simpleScore.toStringAsFixed(2)}, '
          'm=${moderateScore.toStringAsFixed(2)}, '
          'c=${complexScore.toStringAsFixed(2)})';
    }

    // -----------------------------------------------------------------
    // 10. Determine routing instruction
    // -----------------------------------------------------------------
    final routingInstruction = _determineRouting(complexity, entities);

    final result = ScheduleClassificationResult(
      complexity: complexity,
      signals: signals,
      extractedEntities: entities,
      routingInstruction: routingInstruction,
      simpleScore: simpleScore,
      moderateScore: moderateScore,
      complexScore: complexScore,
      reasoning: reasoning,
      existingScheduleCount: existingCount,
    );

    debugPrint('📋 Schedule classification: ${result.complexity.name} — '
        '${result.reasoning} [${signals.length} signals]');

    return result;
  }

  /// Build a context string suitable for injection into the AI system prompt.
  ///
  /// Tells the AI how to handle this schedule request based on its
  /// classification and extracted entities.
  static String buildAIContextHint(ScheduleClassificationResult result) {
    final buf = StringBuffer('SCHEDULE COMPLEXITY CLASSIFICATION:\n');

    switch (result.complexity) {
      case ScheduleComplexity.simple:
        buf.writeln('- Classification: SIMPLE');
        buf.writeln('- Instruction: Return a ready_to_execute schedule.');
        buf.writeln('  All parameters are clear. Build the ScheduleItem(s) '
            'directly with WLED payload and return them.');
        buf.writeln('  Do NOT ask clarifying questions.');

      case ScheduleComplexity.moderate:
        buf.writeln('- Classification: MODERATE');
        buf.writeln('- Instruction: Return a confirm_plan with assumptions noted.');
        buf.writeln('  Some parameters need smart defaults. State your '
            'assumptions clearly so the user can confirm or adjust.');
        buf.writeln('  Return the proposed schedule(s) with a brief summary '
            'of what you assumed.');

      case ScheduleComplexity.complex:
        buf.writeln('- Classification: COMPLEX');
        buf.writeln('- Instruction: Return needs_clarification first.');
        buf.writeln('  This request involves multi-day variation, creative '
            'generation, or potential schedule conflicts.');
        buf.writeln('  Ask 1-3 targeted clarifying questions before '
            'generating the full plan.');
        buf.writeln('  After clarification, return confirm_multi_day_plan '
            'with the full set of schedule items.');
    }

    // Add extracted entities as grounding data
    final entities = result.extractedEntities;
    if (entities.hasEntities) {
      buf.writeln('\nEXTRACTED ENTITIES (pre-parsed on device):');
      if (entities.timeReferences.isNotEmpty) {
        buf.writeln('- Times: ${entities.timeReferences.join(", ")}');
      }
      if (entities.dateReferences.isNotEmpty) {
        buf.writeln('- Dates: ${entities.dateReferences.join(", ")}');
      }
      if (entities.duration != null) {
        buf.writeln('- Duration: ${entities.duration}');
      }
      if (entities.recurrence != null) {
        buf.writeln('- Recurrence: ${entities.recurrence}');
      }
      if (entities.teamReference != null) {
        buf.writeln('- Team: ${entities.teamReference!.fullName} '
            '(${entities.teamReference!.league})');
      }
      if (entities.holidayReference != null) {
        buf.writeln('- Holiday: ${entities.holidayReference}');
      }
      if (entities.zoneReferences.isNotEmpty) {
        buf.writeln('- Zones: ${entities.zoneReferences.join(", ")}');
      }
      if (entities.actionReferences.isNotEmpty) {
        buf.writeln('- Actions: ${entities.actionReferences.join(", ")}');
      }
      if (entities.variation != null) {
        buf.writeln('- Variation: ${entities.variation}');
      }
      if (entities.timeHint != null) {
        buf.writeln('- Time of day: ${entities.timeHint}');
      }
    }

    // Add conflict context
    if (result.existingScheduleCount > 0) {
      buf.writeln('\nSCHEDULE CONTEXT:');
      buf.writeln('- Existing schedules: ${result.existingScheduleCount}');
      if (result.existingScheduleCount >= 5) {
        buf.writeln('- WARNING: Schedule slots are filling up. WLED supports '
            'max 20 timers. Check for conflicts before adding more.');
      }
    }

    return buf.toString();
  }

  // -----------------------------------------------------------------------
  // Internal helpers
  // -----------------------------------------------------------------------

  /// Check if [text] matches a [ScheduleSignal].
  static bool _matches(String text, ScheduleSignal signal) {
    if (signal.isRegex) {
      return RegExp(signal.keyword, caseSensitive: false).hasMatch(text);
    }
    return text.contains(signal.keyword.toLowerCase());
  }

  /// Determine the routing instruction based on complexity and entities.
  static ScheduleRoutingInstruction _determineRouting(
    ScheduleComplexity complexity,
    ScheduleEntities entities,
  ) {
    switch (complexity) {
      case ScheduleComplexity.simple:
        return ScheduleRoutingInstruction.readyToExecute;

      case ScheduleComplexity.moderate:
        return ScheduleRoutingInstruction.confirmPlan;

      case ScheduleComplexity.complex:
        // If we already have strong entities, we can go straight to
        // confirm_plan instead of asking more questions
        final hasStrongEntities = entities.timeReferences.isNotEmpty &&
            (entities.duration != null || entities.recurrence != null) &&
            (entities.teamReference != null ||
                entities.holidayReference != null ||
                entities.actionReferences.isNotEmpty);

        if (hasStrongEntities) {
          return ScheduleRoutingInstruction.confirmPlan;
        }
        return ScheduleRoutingInstruction.needsClarificationFirst;
    }
  }
}
