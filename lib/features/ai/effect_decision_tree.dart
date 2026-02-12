import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/light_effect_animator.dart';
import 'package:nexgen_command/features/wled/effect_database.dart';
import 'package:nexgen_command/features/wled/semantic_pattern_matcher.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart' hide MotionType;

// ---------------------------------------------------------------------------
// Output model
// ---------------------------------------------------------------------------

/// Result of the effect decision tree.
class EffectSelection {
  /// Fully-formed effect info (id, name, EffectType category).
  final EffectInfo effectInfo;

  /// Recommended speed in the 0.0–1.0 range.
  final double normalizedSpeed;

  /// Whether this was inferred from context or a pure fallback.
  final bool isInferred;

  const EffectSelection({
    required this.effectInfo,
    required this.normalizedSpeed,
    required this.isInferred,
  });
}

// ---------------------------------------------------------------------------
// Decision tree
// ---------------------------------------------------------------------------

/// Selects the optimal WLED effect based on semantic query attributes.
///
/// Wraps [SemanticPatternMatcher.suggestEffects] and [EffectDatabase] with
/// fallback logic, user-preference boosting, and per-effect speed defaults.
class EffectDecisionTree {
  EffectDecisionTree._();

  /// Select the best effect for a given [QueryAnalysis].
  ///
  /// Priority cascade:
  /// 1. `suggestEffects()` — semantic mood/motion/energy matching
  /// 2. Top-pick fallback by energy level
  /// 3. Solid (id 0) as final fallback
  ///
  /// [hasUserColors]: when true, filters to color-respecting effects so the
  /// user's palette isn't overridden by rainbow/fire effects.
  ///
  /// [userPreferredStyles]: from `UserModel.preferredEffectStyles` — boosts
  /// effects whose category matches (e.g. "twinkle", "chase", "static").
  static EffectSelection selectEffect({
    required QueryAnalysis analysis,
    bool hasUserColors = false,
    List<String>? userPreferredStyles,
  }) {
    // --- 1. Semantic matching via existing infrastructure ---
    final candidates = SemanticPatternMatcher.suggestEffects(
      analysis,
      requireColorRespect: hasUserColors,
    );

    if (candidates.isNotEmpty) {
      // Optionally boost candidates that match user preferred styles
      int bestId = candidates.first;
      if (userPreferredStyles != null && userPreferredStyles.isNotEmpty) {
        for (final id in candidates) {
          final cat = effectTypeFromWledId(id).name.toLowerCase();
          if (userPreferredStyles.any((s) => s.toLowerCase() == cat)) {
            bestId = id;
            break;
          }
        }
      }

      return EffectSelection(
        effectInfo: _effectInfoFromId(bestId),
        normalizedSpeed: recommendSpeed(bestId, analysis.energyLevel),
        isInferred: true,
      );
    }

    // --- 2. Fallback by energy level using topPicks ---
    final fallbackId = _fallbackByEnergy(analysis.energyLevel);
    return EffectSelection(
      effectInfo: _effectInfoFromId(fallbackId),
      normalizedSpeed: recommendSpeed(fallbackId, analysis.energyLevel),
      isInferred: false,
    );
  }

  // -------------------------------------------------------------------------
  // Speed recommendation
  // -------------------------------------------------------------------------

  /// Get a 0.0–1.0 speed recommendation for an effect, adjusted by energy.
  ///
  /// Uses [EffectDatabase.effects] metadata when available, then shifts
  /// toward min/max speed based on energy level.
  static double recommendSpeed(int effectId, EnergyLevel? energy) {
    final meta = EffectDatabase.effects[effectId];
    if (meta == null) return 0.5;

    // If static effect, speed is irrelevant
    if (meta.motionType == MotionType.static) return 0.0;

    // Start with the effect's default speed (0–255)
    double rawSpeed;
    switch (energy) {
      case EnergyLevel.veryLow:
        rawSpeed = meta.minSpeed.toDouble();
      case EnergyLevel.low:
        rawSpeed = _lerp(meta.minSpeed.toDouble(), meta.defaultSpeed.toDouble(), 0.35);
      case EnergyLevel.medium || EnergyLevel.dynamic || null:
        rawSpeed = meta.defaultSpeed.toDouble();
      case EnergyLevel.high:
        rawSpeed = _lerp(meta.defaultSpeed.toDouble(), meta.maxSpeed.toDouble(), 0.65);
      case EnergyLevel.veryHigh:
        rawSpeed = meta.maxSpeed.toDouble();
    }

    // Normalize to 0.0–1.0
    return (rawSpeed / 255.0).clamp(0.0, 1.0);
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  /// Build an [EffectInfo] from a WLED effect ID.
  static EffectInfo _effectInfoFromId(int id) {
    final meta = EffectDatabase.effects[id];
    final name = meta?.name ?? 'Effect $id';
    return EffectInfo(
      id: id,
      name: name,
      category: effectTypeFromWledId(id),
    );
  }

  /// Pick a sensible fallback effect from [WledEffectsCatalog.topPickIds]
  /// based on energy level.
  static int _fallbackByEnergy(EnergyLevel? energy) {
    switch (energy) {
      case EnergyLevel.veryLow:
        return 0;   // Solid
      case EnergyLevel.low:
        return 2;   // Breathe
      case EnergyLevel.medium || EnergyLevel.dynamic:
        return 17;  // Twinkle
      case EnergyLevel.high:
        return 28;  // Chase
      case EnergyLevel.veryHigh:
        return 28;  // Chase (fast)
      case null:
        return 0;   // Solid — safest default
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
