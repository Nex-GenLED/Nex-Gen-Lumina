/// Custom WLED design card attached to a [BrandLibraryEntry] beyond the
/// five canonical auto-generated designs (Solid, Breathe, Chase, Event
/// Mode, Welcome). Used when a brand wants a signature effect that does
/// not fit those five templates — e.g. a "Shimmer" twinkle for jewelry,
/// a "Wave" running pattern for a beach resort, etc.
///
/// At brand-design generation time, each custom design is materialized
/// into a /users/{uid}/favorites/{patternId} doc using the same schema
/// as the five auto-generated designs (`autoAdded: true`, name,
/// usageCount, lastUsed, wledPayload). Downstream code that reads
/// favorites cannot tell the two apart by design.
///
/// Schema is snake_case in Firestore (project convention, matches every
/// other model in lib/models/commercial/) and camelCase at the Dart
/// layer.
class BrandCustomDesign {
  /// Stable, slugified id, e.g. 'shimmer'. Combined with the brand id at
  /// favorite-write time as `brand_{brandId}_{designId}` so re-runs of
  /// the generator update the existing favorite in place rather than
  /// creating duplicates.
  final String designId;

  /// User-visible label, e.g. 'Shimmer'. Concatenated with the company
  /// name at generation time: "[CompanyName] [displayName]".
  final String displayName;

  /// Human-readable WLED effect label, e.g. 'Twinkle'. Cosmetic only —
  /// only the numeric [wledEffectId] is sent to the WLED device.
  final String wledEffectName;

  /// Numeric WLED effect ID (the `fx` field in /json/state), e.g. 50 for
  /// Twinkle. Authoritative for the device.
  final int wledEffectId;

  /// Free-form passthrough of WLED segment params merged into the
  /// generated payload's `seg[0]` map. Common keys: `sx` (speed 0–255),
  /// `ix` (intensity 0–255), `pal` (palette id). Unknown keys flow
  /// through unchanged — WLED ignores fields it doesn't understand,
  /// which keeps this model stable across firmware versions and effect
  /// variants.
  ///
  /// `bri` is honored at the top level of the payload (matching the
  /// auto-generated designs' shape). `fx` and `col` are reserved for
  /// the generator and are stripped if present.
  final Map<String, dynamic> effectParams;

  /// Optional descriptive caption, e.g. "Subtle jewelry-like glimmer".
  /// Surfaces in admin tooling; not used at the WLED layer.
  final String? description;

  /// Mood tag, drawn from the same vocabulary as [BrandSignature.mood]:
  /// 'trustworthy', 'energetic', 'stable', 'inviting', 'welcoming',
  /// 'luxurious', 'calm', 'elegant', 'dynamic', 'professional'. Free-form
  /// for forward compatibility.
  final String mood;

  const BrandCustomDesign({
    required this.designId,
    required this.displayName,
    required this.wledEffectName,
    required this.wledEffectId,
    this.effectParams = const {},
    this.description,
    this.mood = 'professional',
  });

  factory BrandCustomDesign.fromJson(Map<String, dynamic> json) {
    final raw = json['effect_params'];
    final params = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    return BrandCustomDesign(
      designId: (json['design_id'] as String?) ?? '',
      displayName: (json['display_name'] as String?) ?? '',
      wledEffectName: (json['wled_effect_name'] as String?) ?? '',
      wledEffectId: (json['wled_effect_id'] as num?)?.toInt() ?? 0,
      effectParams: params,
      description: json['description'] as String?,
      mood: (json['mood'] as String?) ?? 'professional',
    );
  }

  Map<String, dynamic> toJson() => {
        'design_id': designId,
        'display_name': displayName,
        'wled_effect_name': wledEffectName,
        'wled_effect_id': wledEffectId,
        'effect_params': effectParams,
        if (description != null) 'description': description,
        'mood': mood,
      };

  BrandCustomDesign copyWith({
    String? designId,
    String? displayName,
    String? wledEffectName,
    int? wledEffectId,
    Map<String, dynamic>? effectParams,
    String? description,
    String? mood,
  }) {
    return BrandCustomDesign(
      designId: designId ?? this.designId,
      displayName: displayName ?? this.displayName,
      wledEffectName: wledEffectName ?? this.wledEffectName,
      wledEffectId: wledEffectId ?? this.wledEffectId,
      effectParams: effectParams ?? this.effectParams,
      description: description ?? this.description,
      mood: mood ?? this.mood,
    );
  }
}
