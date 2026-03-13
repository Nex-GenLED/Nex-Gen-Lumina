enum FixtureType {
  rooflineRail,
  flushLandscape,
  diffusedRope,
  stairLight,
  soffitUplight,
  wallWash,
}

extension FixtureTypeExtension on FixtureType {
  String get displayName => switch (this) {
        FixtureType.rooflineRail => 'Roofline Rail',
        FixtureType.flushLandscape => 'Flush Landscape',
        FixtureType.diffusedRope => 'Diffused Rope',
        FixtureType.stairLight => 'Stair Light',
        FixtureType.soffitUplight => 'Soffit Uplight',
        FixtureType.wallWash => 'Wall Wash',
      };

  String get iconAsset => switch (this) {
        FixtureType.rooflineRail => 'roofline',
        FixtureType.flushLandscape => 'landscape',
        FixtureType.diffusedRope => 'light_mode',
        FixtureType.stairLight => 'stairs',
        FixtureType.soffitUplight => 'highlight',
        FixtureType.wallWash => 'wallpaper',
      };

  String get behaviorHint => switch (this) {
        FixtureType.rooflineRail =>
          'Typically the primary focal fixture — follows all themes',
        FixtureType.flushLandscape =>
          'Accent lighting that complements the roofline with simpler effects',
        FixtureType.diffusedRope =>
          'Continuous glow strip — suited for chases, gradients, and color flows',
        FixtureType.stairLight =>
          'Individual node accents — best with subtle or synchronized static colors',
        FixtureType.soffitUplight =>
          'Ambient up-wash — usually static or slow-fade to avoid distraction',
        FixtureType.wallWash =>
          'Broad surface illumination — supports most effects at moderate intensity',
      };

  bool get isStripType => switch (this) {
        FixtureType.rooflineRail => true,
        FixtureType.diffusedRope => true,
        FixtureType.wallWash => true,
        FixtureType.flushLandscape => false,
        FixtureType.stairLight => false,
        FixtureType.soffitUplight => false,
      };

  int get effectCompatibilityTier => switch (this) {
        FixtureType.rooflineRail => 1,
        FixtureType.diffusedRope => 1,
        FixtureType.wallWash => 2,
        FixtureType.flushLandscape => 2,
        FixtureType.stairLight => 2,
        FixtureType.soffitUplight => 3,
      };
}
