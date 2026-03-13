/// Describes what audio-reactive features the connected WLED controller
/// supports (SR WLED usermod, onboard mic, available effects).
class AudioReactiveCapability {
  final bool hasAudioReactiveUsermod;
  final bool hasMicHardware;
  final List<int> audioReactiveEffects;
  final String? usermodeVersion;

  const AudioReactiveCapability({
    required this.hasAudioReactiveUsermod,
    required this.hasMicHardware,
    required this.audioReactiveEffects,
    this.usermodeVersion,
  });

  /// Controller does not support audio reactivity.
  factory AudioReactiveCapability.notSupported() {
    return const AudioReactiveCapability(
      hasAudioReactiveUsermod: false,
      hasMicHardware: false,
      audioReactiveEffects: [],
    );
  }

  bool get isSupported => hasAudioReactiveUsermod && hasMicHardware;

  AudioReactiveCapability copyWith({
    bool? hasAudioReactiveUsermod,
    bool? hasMicHardware,
    List<int>? audioReactiveEffects,
    String? usermodeVersion,
  }) {
    return AudioReactiveCapability(
      hasAudioReactiveUsermod: hasAudioReactiveUsermod ?? this.hasAudioReactiveUsermod,
      hasMicHardware: hasMicHardware ?? this.hasMicHardware,
      audioReactiveEffects: audioReactiveEffects ?? this.audioReactiveEffects,
      usermodeVersion: usermodeVersion ?? this.usermodeVersion,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hasAudioReactiveUsermod': hasAudioReactiveUsermod,
      'hasMicHardware': hasMicHardware,
      'audioReactiveEffects': audioReactiveEffects,
      'usermodeVersion': usermodeVersion,
    };
  }

  factory AudioReactiveCapability.fromJson(Map<String, dynamic> json) {
    return AudioReactiveCapability(
      hasAudioReactiveUsermod: json['hasAudioReactiveUsermod'] as bool? ?? false,
      hasMicHardware: json['hasMicHardware'] as bool? ?? false,
      audioReactiveEffects: (json['audioReactiveEffects'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      usermodeVersion: json['usermodeVersion'] as String?,
    );
  }

  @override
  String toString() =>
      'AudioReactiveCapability(usermod=$hasAudioReactiveUsermod, mic=$hasMicHardware, '
      'effects=${audioReactiveEffects.length}, version=$usermodeVersion)';
}
