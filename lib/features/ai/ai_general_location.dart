// What Lumina AI is told about where the user lives: city and state only.
//
// The profile's `location` field is free text, and Edit Profile copies the
// full home street address into it (edit_profile_screen.dart). The model
// needs a region (climate, local holidays, the local team), never a house.
// The profile keeps the full address; only what goes to the model changes.
// This matches the consent sheet line "Your general location (city and
// state) from your profile."
//
// Fails toward saying less: if nothing city-like survives, the model gets
// "Unknown".

const String kUnknownLocation = 'Unknown';

final RegExp _leadingNumber = RegExp(r'^\d');
final RegExp _zip = RegExp(r'\b\d{5}(?:-\d{4})?\b');
final RegExp _streetOrUnit = RegExp(
  r'\b(st|street|ave|avenue|rd|road|dr|drive|ln|lane|blvd|boulevard|ct|court|'
  r'way|pkwy|parkway|cir|circle|ter|terrace|pl|place|hwy|highway|trl|trail|'
  r'apt|apartment|suite|ste|unit|po box|p\.o\. box|box)\b|#',
  caseSensitive: false,
);
const Set<String> _countries = {
  'usa', 'us', 'u.s.', 'u.s.a.', 'united states', 'united states of america',
};

/// City and state from a free-text location or address. For example
/// "123 Main St, Kansas City, MO 64105, USA" becomes "Kansas City, MO".
String generalLocationForAi(String? raw) {
  if (raw == null) return kUnknownLocation;
  var parts = raw
      .split(RegExp(r'[,\n]'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isNotEmpty && _countries.contains(parts.last.toLowerCase())) {
    parts.removeLast();
  }
  // Street, unit and PO-box lines go.
  parts = parts
      .where((p) => !_leadingNumber.hasMatch(p) && !_streetOrUnit.hasMatch(p))
      .map((p) => p.replaceAll(_zip, '').trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return kUnknownLocation;
  final kept = parts.length > 2 ? parts.sublist(parts.length - 2) : parts;
  return kept.join(', ');
}
