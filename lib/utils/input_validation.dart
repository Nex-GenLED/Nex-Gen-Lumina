import 'dart:math';

/// Utility class for validating and sanitizing user input
///
/// SECURITY: Prevents XSS, injection attacks, and data corruption
class InputValidation {
  /// Sanitize a string by removing potentially dangerous characters
  ///
  /// Removes: < > " ' / \ to prevent script injection
  static String sanitizeString(String? input, {int maxLength = 100}) {
    if (input == null || input.isEmpty) return '';

    // Remove dangerous characters
    String sanitized = input
        .replaceAll(RegExp(r'''[<>"'/\\]'''), '')
        .trim();

    // Limit length
    return sanitized.substring(0, min(sanitized.length, maxLength));
  }

  /// Validate and sanitize display name
  ///
  /// Requirements:
  /// - 1-50 characters
  /// - No special characters that could cause injection
  /// - No leading/trailing whitespace
  static String? validateDisplayName(String? input) {
    if (input == null || input.trim().isEmpty) {
      return null;
    }

    final sanitized = sanitizeString(input, maxLength: 50);

    if (sanitized.isEmpty) {
      return null;
    }

    // Must have at least 1 character after sanitization
    if (sanitized.length < 1) {
      return null;
    }

    return sanitized;
  }

  /// Validate and sanitize email address
  ///
  /// Returns sanitized email or null if invalid
  static String? validateEmail(String? input) {
    if (input == null || input.trim().isEmpty) {
      return null;
    }

    final email = input.trim().toLowerCase();

    // Basic email validation regex
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );

    if (!emailRegex.hasMatch(email)) {
      return null;
    }

    // Limit length to prevent DOS
    if (email.length > 320) {
      return null;
    }

    return email;
  }

  /// Validate dealer email (must be from authorized domain)
  ///
  /// SECURITY: Only allow emails from verified dealer domains
  static String? validateDealerEmail(String? input) {
    final email = validateEmail(input);
    if (email == null) return null;

    // List of authorized dealer domains
    const authorizedDomains = [
      'nexgenled.com',
      'authorized-dealer.com', // Update with real dealer domains
    ];

    // Check if email is from authorized domain
    for (final domain in authorizedDomains) {
      if (email.endsWith('@$domain')) {
        return email;
      }
    }

    // Not from authorized domain
    return null;
  }

  /// Validate and sanitize address
  ///
  /// Max 200 characters, removes dangerous chars
  static String? validateAddress(String? input) {
    if (input == null || input.trim().isEmpty) {
      return null;
    }

    // Allow alphanumeric, spaces, commas, periods, hyphens, #
    final sanitized = input
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s,.\-#]'), '')
        .trim();

    if (sanitized.isEmpty || sanitized.length > 200) {
      return null;
    }

    return sanitized;
  }

  /// Validate phone number
  ///
  /// Accepts various formats, returns digits only
  static String? validatePhoneNumber(String? input) {
    if (input == null || input.trim().isEmpty) {
      return null;
    }

    // Extract only digits
    final digitsOnly = input.replaceAll(RegExp(r'[^\d]'), '');

    // Must have 10-15 digits (international numbers)
    if (digitsOnly.length < 10 || digitsOnly.length > 15) {
      return null;
    }

    return digitsOnly;
  }

  /// Validate URL (for webhook URL)
  ///
  /// SECURITY: Ensure URL is properly formatted and uses HTTPS
  static String? validateWebhookUrl(String? input) {
    if (input == null || input.trim().isEmpty) {
      return null;
    }

    final url = input.trim().toLowerCase();

    try {
      final uri = Uri.parse(url);

      // SECURITY: Only allow HTTPS for webhooks
      if (uri.scheme != 'https') {
        return null;
      }

      // Must have a host
      if (uri.host.isEmpty) {
        return null;
      }

      // Limit length
      if (url.length > 500) {
        return null;
      }

      return input.trim(); // Return original case
    } catch (e) {
      return null;
    }
  }

  /// Validate WiFi SSID
  ///
  /// Max 32 characters (WiFi standard limit)
  static String? validateSsid(String? input) {
    if (input == null || input.trim().isEmpty) {
      return null;
    }

    final ssid = input.trim();

    // WiFi SSID max length is 32 bytes
    if (ssid.length > 32) {
      return null;
    }

    return ssid;
  }

  /// Validate list of tags/teams/interests
  ///
  /// Each item max 50 chars, list max 20 items
  static List<String> validateStringList(List<String>? input, {int maxItems = 20, int maxItemLength = 50}) {
    if (input == null || input.isEmpty) {
      return [];
    }

    final validated = <String>[];

    for (final item in input.take(maxItems)) {
      final sanitized = sanitizeString(item, maxLength: maxItemLength);
      if (sanitized.isNotEmpty) {
        validated.add(sanitized);
      }
    }

    return validated;
  }

  /// Validate integer within range
  static int? validateIntRange(int? value, {int? min, int? max}) {
    if (value == null) return null;

    if (min != null && value < min) return min;
    if (max != null && value > max) return max;

    return value;
  }

  /// Validate double within range
  static double? validateDoubleRange(double? value, {double? min, double? max}) {
    if (value == null) return null;

    if (min != null && value < min) return min;
    if (max != null && value > max) return max;

    return value;
  }

  /// Validate latitude (-90 to 90)
  static double? validateLatitude(double? lat) {
    return validateDoubleRange(lat, min: -90.0, max: 90.0);
  }

  /// Validate longitude (-180 to 180)
  static double? validateLongitude(double? lon) {
    return validateDoubleRange(lon, min: -180.0, max: 180.0);
  }

  /// Validate year (reasonable range for building construction)
  static int? validateBuildYear(int? year) {
    if (year == null) return null;

    final currentYear = DateTime.now().year;
    return validateIntRange(year, min: 1800, max: currentYear + 2);
  }

  /// Validate autonomy level (0-2)
  static int? validateAutonomyLevel(int? level) {
    return validateIntRange(level, min: 0, max: 2);
  }

  /// Validate change tolerance level (0-5)
  static int? validateChangeTolerance(int? level) {
    return validateIntRange(level, min: 0, max: 5);
  }

  /// Validate vibe level (0.0-1.0)
  static double? validateVibeLevel(double? level) {
    return validateDoubleRange(level, min: 0.0, max: 1.0);
  }

  /// Validate quiet hours (0-1439 minutes from midnight)
  static int? validateQuietHoursMinutes(int? minutes) {
    return validateIntRange(minutes, min: 0, max: 1439);
  }
}
