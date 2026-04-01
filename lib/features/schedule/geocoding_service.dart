import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/firebase_options.dart';

class GeocodeResult {
  final double lat;
  final double lon;
  final String? displayName;
  const GeocodeResult({required this.lat, required this.lon, this.displayName});
}

/// Address suggestion result for autocomplete
class AddressSuggestion {
  final String displayName;
  final String shortAddress;
  final double lat;
  final double lon;
  final String? type;

  /// Parsed address components for auto-fill
  final String? houseNumber;
  final String? street;
  final String? city;
  final String? state;
  final String? postcode;

  const AddressSuggestion({
    required this.displayName,
    required this.shortAddress,
    required this.lat,
    required this.lon,
    this.type,
    this.houseNumber,
    this.street,
    this.city,
    this.state,
    this.postcode,
  });

  /// Returns the street address (house number + street name)
  String get streetAddress {
    if (houseNumber != null && street != null) {
      return '$houseNumber $street';
    }
    return street ?? '';
  }
}

/// Geocoding service using Google Places Autocomplete (primary) with
/// Photon fallback. Google Places has the best US residential address
/// coverage; Photon (OSM-based) serves as a free fallback.
class GeocodingService {
  const GeocodingService();

  /// Platform-appropriate Google API key from Firebase config.
  String get _googleApiKey {
    if (kIsWeb) return DefaultFirebaseOptions.web.apiKey;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return DefaultFirebaseOptions.ios.apiKey;
      default:
        return DefaultFirebaseOptions.android.apiKey;
    }
  }

  /// Search for address suggestions as the user types.
  Future<List<AddressSuggestion>> searchAddresses(String query, {int limit = 5}) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return [];

    // Try Google Places first — best residential address coverage
    final googleResults = await _searchGooglePlaces(trimmed, limit: limit);
    if (googleResults.isNotEmpty) return googleResults;

    // Fall back to Photon (OSM-based, free, no key needed)
    return _searchPhoton(trimmed, limit: limit);
  }

  /// Google Places Autocomplete (New) — best coverage for US residential addresses.
  Future<List<AddressSuggestion>> _searchGooglePlaces(String query, {int limit = 5}) async {
    try {
      final uri = Uri.parse('https://places.googleapis.com/v1/places:autocomplete');
      final requestBody = jsonEncode({
        'input': query,
        'includedPrimaryTypes': ['street_address', 'subpremise', 'premise'],
        'includedRegionCodes': ['us'],
      });

      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.postUrl(uri);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set('X-Goog-Api-Key', _googleApiKey);
      req.write(requestBody);
      final res = await req.close().timeout(const Duration(seconds: 5));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);

      if (res.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final suggestions = data['suggestions'] as List? ?? [];
        final results = <AddressSuggestion>[];

        for (final suggestion in suggestions.take(limit)) {
          final s = suggestion as Map<String, dynamic>;
          final placePrediction = s['placePrediction'] as Map<String, dynamic>?;
          if (placePrediction == null) continue;

          final placeId = placePrediction['placeId'] as String? ?? '';
          final text = placePrediction['text'] as Map<String, dynamic>?;
          final structuredFormat = placePrediction['structuredFormat'] as Map<String, dynamic>?;

          final fullText = text?['text'] as String? ?? '';
          final mainText = (structuredFormat?['mainText'] as Map<String, dynamic>?)?['text'] as String? ?? fullText;
          final secondaryText = (structuredFormat?['secondaryText'] as Map<String, dynamic>?)?['text'] as String? ?? '';

          // Fetch details for lat/lng and address components
          double lat = 0, lon = 0;
          String? city, state, postcode;
          if (placeId.isNotEmpty) {
            final details = await _getPlaceDetails(placeId);
            if (details != null) {
              lat = details['lat'] ?? 0;
              lon = details['lon'] ?? 0;
              city = details['city'];
              state = details['state'];
              postcode = details['postcode'];
            }
          }

          // Parse house number and street from main text
          String? houseNumber, street;
          final mainParts = mainText.split(' ');
          if (mainParts.length >= 2 && RegExp(r'^\d').hasMatch(mainParts.first)) {
            houseNumber = mainParts.first;
            street = mainParts.sublist(1).join(' ');
          } else {
            street = mainText;
          }

          // Build short address: "123 Main St, City, ST"
          final shortParts = <String>[mainText];
          if (city != null) shortParts.add(city);
          if (state != null) shortParts.add(state);

          results.add(AddressSuggestion(
            displayName: fullText.isNotEmpty ? fullText : '$mainText, $secondaryText',
            shortAddress: shortParts.join(', '),
            lat: lat,
            lon: lon,
            type: 'house',
            houseNumber: houseNumber,
            street: street,
            city: city,
            state: state,
            postcode: postcode,
          ));
        }
        return results;
      } else if (res.statusCode == 403) {
        debugPrint('GeocodingService: Google Places API (New) not enabled — '
            'enable at https://console.developers.google.com/apis/api/places.googleapis.com/overview');
      } else {
        debugPrint('GeocodingService: Google Places status ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('GeocodingService: Google Places error $e');
    }
    return [];
  }

  /// Fetch lat/lng and address components for a Google place_id.
  Future<Map<String, dynamic>?> _getPlaceDetails(String placeId) async {
    try {
      final uri = Uri.parse(
        'https://places.googleapis.com/v1/places/$placeId',
      );
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(uri);
      req.headers.set('X-Goog-Api-Key', _googleApiKey);
      req.headers.set('X-Goog-FieldMask', 'location,addressComponents');
      final res = await req.close().timeout(const Duration(seconds: 5));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);

      if (res.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final location = data['location'] as Map<String, dynamic>?;
        final components = data['addressComponents'] as List? ?? [];

        String? city, state, postcode;
        for (final c in components) {
          final comp = c as Map<String, dynamic>;
          final types = (comp['types'] as List?)?.cast<String>() ?? [];
          final longName = comp['longText'] as String?;
          final shortName = comp['shortText'] as String?;
          if (types.contains('locality')) city = longName;
          if (types.contains('administrative_area_level_1')) state = shortName ?? longName;
          if (types.contains('postal_code')) postcode = longName;
        }

        return {
          'lat': (location?['latitude'] as num?)?.toDouble(),
          'lon': (location?['longitude'] as num?)?.toDouble(),
          'city': city,
          'state': state,
          'postcode': postcode,
        };
      }
    } catch (e) {
      debugPrint('GeocodingService: Place details error $e');
    }
    return null;
  }

  /// Photon geocoder fallback — free, OSM-based, decent fuzzy matching.
  Future<List<AddressSuggestion>> _searchPhoton(String query, {int limit = 5}) async {
    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/api/'
        '?q=${Uri.encodeComponent(query)}'
        '&limit=$limit'
        '&lang=en',
      );
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'NexGenCommand/1.0');
      final res = await req.close().timeout(const Duration(seconds: 5));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final features = data['features'] as List? ?? [];

        return features.map((feature) {
          final props = (feature as Map<String, dynamic>)['properties'] as Map<String, dynamic>? ?? {};
          final geometry = feature['geometry'] as Map<String, dynamic>? ?? {};
          final coords = geometry['coordinates'] as List? ?? [0, 0];
          final lon = (coords[0] as num?)?.toDouble() ?? 0;
          final lat = (coords[1] as num?)?.toDouble() ?? 0;

          final houseNumber = props['housenumber'] as String?;
          final street = props['street'] as String?;
          final city = props['city'] as String?;
          final state = props['state'] as String?;
          final postcode = props['postcode'] as String?;
          final name = props['name'] as String?;
          final type = props['type'] as String?;

          final parts = <String>[];
          if (houseNumber != null && street != null) {
            parts.add('$houseNumber $street');
          } else if (name != null && name.isNotEmpty) {
            parts.add(name);
          } else if (street != null) {
            parts.add(street);
          }
          if (city != null) parts.add(city);
          if (state != null) parts.add(state);
          if (postcode != null) parts.add(postcode);

          final shortAddr = parts.isNotEmpty ? parts.join(', ') : (name ?? '');
          final allParts = <String>[...parts];
          final country = props['country'] as String?;
          if (country != null && !allParts.contains(country)) allParts.add(country);

          return AddressSuggestion(
            displayName: allParts.join(', '),
            shortAddress: shortAddr,
            lat: lat,
            lon: lon,
            type: type,
            houseNumber: houseNumber,
            street: street,
            city: city,
            state: state,
            postcode: postcode,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('GeocodingService: Photon search error $e');
    }
    return [];
  }

  Future<GeocodeResult?> geocode(String address) async {
    final query = address.trim();
    if (query.isEmpty) return null;
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${Uri.encodeComponent(query)}');
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'NexGenCommand/1.0');
      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(body);
        if (data is List && data.isNotEmpty) {
          final first = data.first as Map<String, dynamic>;
          final latStr = first['lat']?.toString();
          final lonStr = first['lon']?.toString();
          if (latStr != null && lonStr != null) {
            final lat = double.tryParse(latStr);
            final lon = double.tryParse(lonStr);
            if (lat != null && lon != null) {
              return GeocodeResult(lat: lat, lon: lon, displayName: first['display_name'] as String?);
            }
          }
        }
      } else {
        debugPrint('GeocodingService: status ${res.statusCode}: $body');
      }
    } catch (e) {
      debugPrint('GeocodingService: error $e');
    }
    return null;
  }
}

final geocodingServiceProvider = Provider<GeocodingService>((ref) => const GeocodingService());
