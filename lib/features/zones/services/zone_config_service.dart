import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fixture_type.dart';
import '../models/zone_assignment.dart';

const _kStorageKey = 'ngl_zone_assignments';

class ZoneConfigService {
  Future<List<ZoneAssignment>> loadAssignments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStorageKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ZoneAssignment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAssignments(List<ZoneAssignment> assignments) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(assignments.map((a) => a.toJson()).toList());
    await prefs.setString(_kStorageKey, encoded);
  }

  Future<void> upsertAssignment(ZoneAssignment assignment) async {
    final assignments = await loadAssignments();
    final index = assignments.indexWhere(
      (a) => a.segmentId == assignment.segmentId,
    );
    if (index >= 0) {
      assignments[index] = assignment;
    } else {
      assignments.add(assignment);
    }
    await saveAssignments(assignments);
  }

  Future<void> removeAssignment(int segmentId) async {
    final assignments = await loadAssignments();
    assignments.removeWhere((a) => a.segmentId == segmentId);
    await saveAssignments(assignments);
  }

  Future<List<ZoneAssignment>> getAssignmentsForFixtureType(
    FixtureType type,
  ) async {
    final assignments = await loadAssignments();
    return assignments.where((a) => a.fixtureType == type).toList();
  }
}

final zoneConfigServiceProvider =
    Provider<ZoneConfigService>((ref) => ZoneConfigService());

final zoneAssignmentsProvider =
    FutureProvider<List<ZoneAssignment>>((ref) {
  return ref.read(zoneConfigServiceProvider).loadAssignments();
});
