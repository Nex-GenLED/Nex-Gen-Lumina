/// Lighting signature for a commercial brand — a high-level description
/// of how the brand "feels" when lit, encoded as four enum-like strings
/// that map to concrete WLED parameters at design-generation time.
///
/// Seeded onto every /brand_library entry by scripts/seed_brand_library.js
/// (industry-driven defaults plus a warm/cool fallback heuristic) and may
/// be overridden by the customer in their per-business
/// CommercialBrandProfile.
class BrandSignature {
  /// One of: 'breathe', 'chase', 'fade', 'twinkle', 'solid', 'running'.
  /// Seed signatures only emit the first five today; 'running' is reserved
  /// for future industry mappings.
  final String primaryEffect;

  /// One of: 'slow', 'medium', 'fast'.
  final String speed;

  /// One of: 'low', 'medium', 'high'.
  final String intensity;

  /// One of: 'trustworthy', 'energetic', 'stable', 'inviting',
  /// 'welcoming', 'luxurious', 'calm', 'elegant', 'dynamic',
  /// 'professional'. Free-form for forward compatibility.
  final String mood;

  const BrandSignature({
    this.primaryEffect = 'breathe',
    this.speed = 'medium',
    this.intensity = 'medium',
    this.mood = 'professional',
  });

  factory BrandSignature.fromJson(Map<String, dynamic> json) {
    return BrandSignature(
      primaryEffect: (json['primary_effect'] as String?) ?? 'breathe',
      speed: (json['speed'] as String?) ?? 'medium',
      intensity: (json['intensity'] as String?) ?? 'medium',
      mood: (json['mood'] as String?) ?? 'professional',
    );
  }

  Map<String, dynamic> toJson() => {
        'primary_effect': primaryEffect,
        'speed': speed,
        'intensity': intensity,
        'mood': mood,
      };

  BrandSignature copyWith({
    String? primaryEffect,
    String? speed,
    String? intensity,
    String? mood,
  }) {
    return BrandSignature(
      primaryEffect: primaryEffect ?? this.primaryEffect,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      mood: mood ?? this.mood,
    );
  }

  // ── WLED parameter mappings ────────────────────────────────────────────
  // Used by BrandDesignGenerator (Part 5) to translate a high-level
  // signature into concrete WLED state. Effect IDs match the
  // color-respecting effect set documented in the Lumina AI smart prompt
  // (lib/lumina_ai/lumina_ai_service.dart).

  /// WLED effect ID for [primaryEffect]. Defaults to 2 (Breathe) for
  /// unknown values so the design still renders.
  int get wledEffectId {
    switch (primaryEffect) {
      case 'solid':
        return 0;
      case 'breathe':
        return 2;
      case 'fade':
        return 12;
      case 'running':
        return 15;
      case 'twinkle':
        return 17;
      case 'chase':
        return 28;
      default:
        return 2;
    }
  }

  /// WLED `sx` (speed) value, 0–255.
  int get wledSpeed {
    switch (speed) {
      case 'slow':
        return 64;
      case 'fast':
        return 200;
      case 'medium':
      default:
        return 128;
    }
  }

  /// WLED `ix` (intensity) value, 0–255. Tuned against the
  /// CALM/ELEGANT/FESTIVE intensity ranges documented in the Lumina AI
  /// smart prompt.
  int get wledIntensity {
    switch (intensity) {
      case 'low':
        return 100;
      case 'high':
        return 220;
      case 'medium':
      default:
        return 150;
    }
  }
}
