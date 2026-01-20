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

  const AddressSuggestion({
    required this.displayName,
    required this.shortAddress,
    required this.lat,
    required this.lon,
    this.type,
  });
}

/// Lightweight geocoding via OpenStreetMap Nominatim (no API key required).
/// Best-effort; rate-limited service. Do not spam requests.
class GeocodingService {
  const GeocodingService();

  /// Search for address suggestions as the user types.
  Future<List<AddressSuggestion>> searchAddresses(String query, {int limit = 5}) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return [];

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json'
        '&limit=$limit'
        '&addressdetails=1'
        '&countrycodes=us'
        '&q=${Uri.encodeComponent(trimmed)}',
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

            // Build a shorter address from address details
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

              if (parts.isNotEmpty) {
                shortAddr = parts.join(', ');
              }
            }

            return AddressSuggestion(
              displayName: displayName,
              shortAddress: shortAddr,
              lat: lat,
              lon: lon,
              type: type,
            );
          }).toList();
        }
      } else {
        debugPrint('GeocodingService: search status ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('GeocodingService: search error $e');
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
