import 'dart:math';

import 'package:nexgen_command/constants/commercial/geo_team_regions.dart';
import 'package:nexgen_command/models/commercial/commercial_team_profile.dart';

/// Suggests local professional sports teams based on business latitude/longitude.
///
/// Uses a static lookup table of US metro regions — no external API required.
/// Suggestions are labelled "Suggested based on your location" and should be
/// presented as removable, not pre-accepted defaults.
class GeoTeamSuggestionService {
  const GeoTeamSuggestionService();

  /// Returns a list of [CommercialTeamProfile] for the closest metro region
  /// to [lat]/[lng]. Each profile has [priorityRank] set sequentially from 1.
  ///
  /// Returns an empty list if no region is within range.
  List<CommercialTeamProfile> getSuggestedTeams(double lat, double lng) {
    GeoRegion? closest;
    double closestDist = double.infinity;

    for (final region in kGeoTeamRegions) {
      final dist = _haversineKm(lat, lng, region.lat, region.lng);
      if (dist <= region.radiusKm && dist < closestDist) {
        closest = region;
        closestDist = dist;
      }
    }

    if (closest == null) return const [];

    // Assign sequential priority ranks starting at 1.
    return closest.teams.asMap().entries.map((entry) {
      return entry.value.copyWith(priorityRank: entry.key + 1);
    }).toList();
  }

  /// Haversine distance in kilometres.
  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLng = _deg2rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _deg2rad(double deg) => deg * (pi / 180);
}
