import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/score_alert_config.dart';
import '../services/sports_background_service.dart';

/// SharedPreferences key — must match the one in
/// `sports_background_service.dart` so both isolates share configs.
const _kConfigsKey = 'sports_alert_configs';

/// Manages the list of [ScoreAlertConfig]s in memory and persists changes
/// to SharedPreferences (so the background isolate can read them).
///
/// Automatically starts / stops the background service when configs change.
class SportsAlertNotifier extends StateNotifier<List<ScoreAlertConfig>> {
  SportsAlertNotifier() : super([]) {
    _load();
  }

  // ---------- Lifecycle ----------

  Future<void> _load() async {
    try {
      final configs = await _loadFromPrefs();
      state = configs;
      debugPrint('[SportsAlertNotifier] Loaded ${configs.length} configs');
    } catch (e) {
      debugPrint('[SportsAlertNotifier] Error loading configs: $e');
    }
  }

  // ---------- CRUD ----------

  /// Add a new alert config and persist.
  Future<void> addConfig(ScoreAlertConfig config) async {
    state = [...state, config];
    await _persist();
  }

  /// Remove a config by [id] and persist.
  Future<void> removeConfig(String id) async {
    state = state.where((c) => c.id != id).toList();
    await _persist();
  }

  /// Replace a config (matched by [config.id]) with an updated copy.
  Future<void> updateConfig(ScoreAlertConfig config) async {
    state = [
      for (final c in state)
        if (c.id == config.id) config else c,
    ];
    await _persist();
  }

  /// Toggle the [isEnabled] flag of a config.
  Future<void> toggleConfig(String id) async {
    state = [
      for (final c in state)
        if (c.id == id) c.copyWith(isEnabled: !c.isEnabled) else c,
    ];
    await _persist();
  }

  // ---------- Persistence ----------

  Future<void> _persist() async {
    await saveAlertConfigs(state);
    await _syncBackgroundService();
  }

  /// If any config is enabled, ensure the background service is running;
  /// otherwise stop it.
  Future<void> _syncBackgroundService() async {
    final anyEnabled = state.any((c) => c.isEnabled);
    if (anyEnabled) {
      await startSportsService();
    } else {
      await stopSportsService();
    }
  }

  /// Load configs from SharedPreferences using the same key as the
  /// background service isolate.
  Future<List<ScoreAlertConfig>> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kConfigsKey);
    if (raw == null || raw.isEmpty) return const [];
    return raw.map((jsonStr) {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return ScoreAlertConfig.fromJson(map);
    }).toList();
  }
}
