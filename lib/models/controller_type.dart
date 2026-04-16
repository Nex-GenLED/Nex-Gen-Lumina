/// Registry of supported WLED controller hardware variants.
enum ControllerType {
  digOcta,
  skikbily,
  genericWled;

  /// Deserialise a Firestore string back to an enum value.
  /// Falls back to [genericWled] for any unrecognised value.
  static ControllerType fromFirestore(String value) {
    switch (value) {
      case 'dig_octa':
        return ControllerType.digOcta;
      case 'skikbily':
        return ControllerType.skikbily;
      case 'generic_wled':
        return ControllerType.genericWled;
      default:
        return ControllerType.genericWled;
    }
  }

  /// Snake-case string for Firestore storage.
  String toFirestore() {
    switch (this) {
      case ControllerType.digOcta:
        return 'dig_octa';
      case ControllerType.skikbily:
        return 'skikbily';
      case ControllerType.genericWled:
        return 'generic_wled';
    }
  }
}

extension ControllerTypeExtension on ControllerType {
  String get shortLabel {
    switch (this) {
      case ControllerType.digOcta:
        return 'DO';
      case ControllerType.skikbily:
        return 'S';
      case ControllerType.genericWled:
        return 'WLED';
    }
  }

  String get fullName {
    switch (this) {
      case ControllerType.digOcta:
        return 'QuinLED Dig-Octa';
      case ControllerType.skikbily:
        return 'SKIKBILY 4-Channel';
      case ControllerType.genericWled:
        return 'Generic WLED Device';
    }
  }

  int? get defaultChannelCount {
    switch (this) {
      case ControllerType.digOcta:
        return 8;
      case ControllerType.skikbily:
        return 4;
      case ControllerType.genericWled:
        return null;
    }
  }

  String get defaultLedType => 'SK6812';

  String get defaultColorOrder => 'GRBW';

  bool get supportsEthernet {
    switch (this) {
      case ControllerType.digOcta:
        return true;
      case ControllerType.skikbily:
        return false;
      case ControllerType.genericWled:
        return false;
    }
  }

  String get iconAsset {
    switch (this) {
      case ControllerType.digOcta:
        return 'assets/icons/controller_do.svg';
      case ControllerType.skikbily:
        return 'assets/icons/controller_s.svg';
      case ControllerType.genericWled:
        return 'assets/icons/controller_wled.svg';
    }
  }
}
