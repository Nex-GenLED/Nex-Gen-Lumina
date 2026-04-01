import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Lightweight geocoding using Photon (primary) with Nominatim fallback.
/// Both are free, no API key required. Photon provides much better
/// fuzzy/partial matching for address autocomplete.
class GeocodingService {
  const GeocodingService();

  /// Search for address suggestions as the user types.
  /// Uses Photon (komoot.io) for better partial-address matching,
  /// falls back to Nominatim if Photon returns no results.
  Future<List<AddressSuggestion>> searchAddresses(String query, {int limit = 5}) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return [];

    // Try Photon first — much better at partial/fuzzy address matching
    final photonResults = await _searchPhoton(trimmed, limit: limit);
    if (photonResults.isNotEmpty) return photonResults;

    // Fall back to Nominatim
    return _searchNominatim(trimmed, limit: limit);
  }

  /// Photon geocoder — designed for autocomplete, great fuzzy matching.
  Future<List<AddressSuggestion>> _searchPhoton(String query, {int limit = 5}) async {
    try {
      final uri = Uri.parse(
        'https://photon.komoot.io/api/'
        '?q=${Uri.encodeComponent(query)}'
        '&limit=$limit'
        '&lang=en'
        '&layer=house&layer=street',
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

          // Build short address
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

          // Build full display name
          final allParts = <String>[...parts];
          final country = props['country'] as String?;
          if (country != null && !allParts.contains(country)) allParts.add(country);
          final displayName = allParts.join(', ');

          return AddressSuggestion(
            displayName: displayName,
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

  /// Nominatim fallback — more complete database, slower fuzzy matching.
  Future<List<AddressSuggestion>> _searchNominatim(String query, {int limit = 5}) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json'
        '&limit=$limit'
        '&addressdetails=1'
        '&dedupe=1'
        '&q=${Uri.encodeComponent(query)}',
      );
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      req.headers.set(HttpHeaders.userAgentHeader, 'NexGenCommand/1.0');
      final res = await req.close().timeout(const Duration(seconds: 5));
      final body = await res.transform(utf8.decoder).join();
      client.close(force: true);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(body);
        if (data is List) {
          return data.map((item) {
            final map = item as Map<String, dynamic>;
            final lat = double.tryParse(map['lat']?.toString() ?? '') ?? 0;
            final lon = double.tryParse(map['lon']?.toString() ?? '') ?? 0;
            final displayName = map['display_name'] as String? ?? '';
            final type = map['type'] as String?;

            final addr = map['address'] as Map<String, dynamic>?;
            String shortAddr = displayName;
            if (addr != null) {
              final parts = <String>[];
              final houseNumber = addr['house_number'] as String?;
              final road = addr['road'] as String?;
              final city = addr['city'] ?? addr['town'] ?? addr['village'];
              final state = addr['state'] as String?;
              final postcode = addr['postcode'] as String?;

              if (houseNumber != null && road != null) {
                parts.add('$houseNumber $road');
              } else if (road != null) {
                parts.add(road);
              }
              if (city != null) parts.add(city.toString());
              if (state != null) parts.add(state);
              if (postcode != null) parts.add(postcode);

              if (parts.isNotEmpty) shortAddr = parts.join(', ');
            }

            final houseNumber = addr?['house_number'] as String?;
            final road = addr?['road'] as String?;
            final cityVal = addr?['city'] ?? addr?['town'] ?? addr?['village'];
            final stateVal = addr?['state'] as String?;
            final postcodeVal = addr?['postcode'] as String?;

            return AddressSuggestion(
              displayName: displayName,
              shortAddress: shortAddr,
              lat: lat,
              lon: lon,
              type: type,
              houseNumber: houseNumber,
              street: road,
              city: cityVal?.toString(),
              state: stateVal,
              postcode: postcodeVal,
            );
          }).toList();
        }
      } else {
        debugPrint('GeocodingService: Nominatim search status ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('GeocodingService: Nominatim search error $e');
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
