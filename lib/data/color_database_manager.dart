import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexgen_command/data/team_color_database.dart';
import 'package:nexgen_command/data/holiday_color_database.dart';

/// Manages Firestore-synced overlay data for the color databases.
///
/// The bundled data in [TeamColorDatabase] and [HolidayColorDatabase] ships
/// with the app.  This manager downloads "overlay" patches from Firestore
/// (new teams, corrected colours, new holidays) so the database can be
/// updated without an app release.
///
/// Overlay data is cached in SharedPreferences for offline access.
class ColorDatabaseManager {
  ColorDatabaseManager._();

  static const _versionKey = 'color_db_version';
  static const _overlayKey = 'color_db_overlay';
  static const _lastSyncKey = 'color_db_last_sync';
  static const _firestoreCollection = 'color_database';
  static const _firestoreDoc = 'current';

  /// Version of the data bundled inside the app binary.
  /// Bump this whenever the hardcoded palette files are updated.
  static const int bundledVersion = 1;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class ColorDatabaseState {
  final int localVersion;
  final int? remoteVersion;
  final bool isSyncing;
  final DateTime? lastSynced;
  final List<UnifiedTeamEntry> overlayTeams;
  final List<HolidayColorEntry> overlayHolidays;

  const ColorDatabaseState({
    this.localVersion = 1,
    this.remoteVersion,
    this.isSyncing = false,
    this.lastSynced,
    this.overlayTeams = const [],
    this.overlayHolidays = const [],
  });

  ColorDatabaseState copyWith({
    int? localVersion,
    int? remoteVersion,
    bool? isSyncing,
    DateTime? lastSynced,
    List<UnifiedTeamEntry>? overlayTeams,
    List<HolidayColorEntry>? overlayHolidays,
  }) {
    return ColorDatabaseState(
      localVersion: localVersion ?? this.localVersion,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSynced: lastSynced ?? this.lastSynced,
      overlayTeams: overlayTeams ?? this.overlayTeams,
      overlayHolidays: overlayHolidays ?? this.overlayHolidays,
    );
  }

  /// Whether an overlay is available (either from cache or from remote).
  bool get hasOverlay => overlayTeams.isNotEmpty || overlayHolidays.isNotEmpty;

  /// Effective version: the highest version we know about.
  int get effectiveVersion => remoteVersion ?? localVersion;

  Map<String, dynamic> toJson() => {
        'localVersion': localVersion,
        'remoteVersion': remoteVersion,
        'lastSynced': lastSynced?.toIso8601String(),
        'overlayTeams': overlayTeams.map(_teamToJson).toList(),
        'overlayHolidays': overlayHolidays.map(_holidayToJson).toList(),
      };

  static Map<String, dynamic> _teamToJson(UnifiedTeamEntry t) => {
        'id': t.id,
        'officialName': t.officialName,
        'city': t.city,
        'league': t.league,
        'country': t.country,
        'aliases': t.aliases,
        'colors': t.colors
            .map((c) => {'name': c.name, 'r': c.r, 'g': c.g, 'b': c.b})
            .toList(),
        'suggestedEffects': t.suggestedEffects,
        'defaultSpeed': t.defaultSpeed,
        'defaultIntensity': t.defaultIntensity,
      };

  static Map<String, dynamic> _holidayToJson(HolidayColorEntry h) => {
        'id': h.id,
        'name': h.name,
        'aliases': h.aliases,
        'type': h.type.name,
        'colors': h.colors
            .map((c) => {'name': c.name, 'r': c.r, 'g': c.g, 'b': c.b})
            .toList(),
        'suggestedEffects': h.suggestedEffects,
        'defaultSpeed': h.defaultSpeed,
        'defaultIntensity': h.defaultIntensity,
        'isColorful': h.isColorful,
        'month': h.month,
        'day': h.day,
      };
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class ColorDatabaseManagerNotifier extends Notifier<ColorDatabaseState> {
  @override
  ColorDatabaseState build() {
    _loadFromCache();
    return const ColorDatabaseState();
  }

  /// Check Firestore for updates and sync if a newer version is available.
  Future<void> syncFromFirestore() async {
    if (state.isSyncing) return;
    state = state.copyWith(isSyncing: true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection(ColorDatabaseManager._firestoreCollection)
          .doc(ColorDatabaseManager._firestoreDoc)
          .get();

      if (!doc.exists) {
        debugPrint('ColorDatabaseManager: No remote document found.');
        state = state.copyWith(isSyncing: false);
        return;
      }

      final data = doc.data()!;
      final remoteVersion = data['version'] as int? ?? 1;

      if (remoteVersion <= state.effectiveVersion) {
        debugPrint(
            'ColorDatabaseManager: Already up to date (v${state.effectiveVersion}).');
        state = state.copyWith(
          isSyncing: false,
          remoteVersion: remoteVersion,
        );
        return;
      }

      // Parse overlay teams
      final teamsAdditions =
          (data['teams_additions'] as List<dynamic>?) ?? [];
      final overlayTeams = <UnifiedTeamEntry>[];
      for (final raw in teamsAdditions) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          overlayTeams.add(_parseTeamOverlay(raw));
        } catch (e) {
          debugPrint('ColorDatabaseManager: Failed to parse team overlay: $e');
        }
      }

      // Parse overlay holidays
      final holidaysAdditions =
          (data['holidays_additions'] as List<dynamic>?) ?? [];
      final overlayHolidays = <HolidayColorEntry>[];
      for (final raw in holidaysAdditions) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          overlayHolidays.add(_parseHolidayOverlay(raw));
        } catch (e) {
          debugPrint(
              'ColorDatabaseManager: Failed to parse holiday overlay: $e');
        }
      }

      state = state.copyWith(
        isSyncing: false,
        remoteVersion: remoteVersion,
        lastSynced: DateTime.now(),
        overlayTeams: overlayTeams,
        overlayHolidays: overlayHolidays,
      );

      // Inject overlay data into databases
      if (overlayTeams.isNotEmpty) {
        TeamColorDatabase.addOverlayTeams(overlayTeams);
      }
      if (overlayHolidays.isNotEmpty) {
        HolidayColorDatabase.addOverlayEntries(overlayHolidays);
      }

      await _persistToCache();
      debugPrint(
          'ColorDatabaseManager: Synced to v$remoteVersion '
          '(${overlayTeams.length} teams, ${overlayHolidays.length} holidays).');
    } catch (e) {
      debugPrint('ColorDatabaseManager: Sync failed: $e');
      state = state.copyWith(isSyncing: false);
    }
  }

  // ── Parsing helpers ─────────────────────────────────────────────────────

  UnifiedTeamEntry _parseTeamOverlay(Map<String, dynamic> raw) {
    final colorsRaw = (raw['colors'] as List<dynamic>?) ?? [];
    final colors = colorsRaw
        .whereType<Map<String, dynamic>>()
        .map((c) => TeamColor(
              c['name'] as String? ?? 'Color',
              c['r'] as int? ?? 0,
              c['g'] as int? ?? 0,
              c['b'] as int? ?? 0,
            ))
        .toList();

    return UnifiedTeamEntry(
      id: raw['id'] as String? ?? 'overlay_${DateTime.now().millisecondsSinceEpoch}',
      officialName: raw['officialName'] as String? ?? 'Unknown Team',
      city: raw['city'] as String? ?? '',
      league: raw['league'] as String? ?? '',
      country: raw['country'] as String?,
      aliases: (raw['aliases'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      colors: colors,
      suggestedEffects: (raw['suggestedEffects'] as List<dynamic>?)
              ?.whereType<int>()
              .toList() ??
          const [12, 41, 0],
      defaultSpeed: raw['defaultSpeed'] as int? ?? 85,
      defaultIntensity: raw['defaultIntensity'] as int? ?? 180,
    );
  }

  HolidayColorEntry _parseHolidayOverlay(Map<String, dynamic> raw) {
    final colorsRaw = (raw['colors'] as List<dynamic>?) ?? [];
    final colors = colorsRaw
        .whereType<Map<String, dynamic>>()
        .map((c) => TeamColor(
              c['name'] as String? ?? 'Color',
              c['r'] as int? ?? 0,
              c['g'] as int? ?? 0,
              c['b'] as int? ?? 0,
            ))
        .toList();

    final typeStr = raw['type'] as String? ?? 'popular';
    final type = HolidayType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => HolidayType.popular,
    );

    return HolidayColorEntry(
      id: raw['id'] as String? ?? 'overlay_${DateTime.now().millisecondsSinceEpoch}',
      name: raw['name'] as String? ?? 'Unknown Holiday',
      aliases: (raw['aliases'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
      type: type,
      colors: colors,
      suggestedEffects: (raw['suggestedEffects'] as List<dynamic>?)
              ?.whereType<int>()
              .toList() ??
          const [0],
      defaultSpeed: raw['defaultSpeed'] as int? ?? 128,
      defaultIntensity: raw['defaultIntensity'] as int? ?? 128,
      isColorful: raw['isColorful'] as bool? ?? true,
      month: raw['month'] as int?,
      day: raw['day'] as int?,
    );
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  Future<void> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final overlayJson = prefs.getString(ColorDatabaseManager._overlayKey);
      final cachedVersion =
          prefs.getInt(ColorDatabaseManager._versionKey);

      if (overlayJson == null) return;

      final data = jsonDecode(overlayJson) as Map<String, dynamic>;

      final teamsRaw = (data['overlayTeams'] as List<dynamic>?) ?? [];
      final overlayTeams = <UnifiedTeamEntry>[];
      for (final raw in teamsRaw) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          overlayTeams.add(_parseTeamOverlay(raw));
        } catch (_) {}
      }

      final holidaysRaw =
          (data['overlayHolidays'] as List<dynamic>?) ?? [];
      final overlayHolidays = <HolidayColorEntry>[];
      for (final raw in holidaysRaw) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          overlayHolidays.add(_parseHolidayOverlay(raw));
        } catch (_) {}
      }

      final lastSyncStr = data['lastSynced'] as String?;
      final lastSynced =
          lastSyncStr != null ? DateTime.tryParse(lastSyncStr) : null;

      state = state.copyWith(
        remoteVersion: cachedVersion,
        lastSynced: lastSynced,
        overlayTeams: overlayTeams,
        overlayHolidays: overlayHolidays,
      );

      // Inject cached overlay data into databases
      if (overlayTeams.isNotEmpty) {
        TeamColorDatabase.addOverlayTeams(overlayTeams);
      }
      if (overlayHolidays.isNotEmpty) {
        HolidayColorDatabase.addOverlayEntries(overlayHolidays);
      }

      debugPrint(
          'ColorDatabaseManager: Loaded cache (v${cachedVersion ?? "?"}, '
          '${overlayTeams.length} teams, ${overlayHolidays.length} holidays).');
    } catch (e) {
      debugPrint('ColorDatabaseManager: Cache load failed: $e');
    }
  }

  Future<void> _persistToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(state.toJson());
      await prefs.setString(ColorDatabaseManager._overlayKey, json);
      if (state.remoteVersion != null) {
        await prefs.setInt(
            ColorDatabaseManager._versionKey, state.remoteVersion!);
      }
    } catch (e) {
      debugPrint('ColorDatabaseManager: Cache persist failed: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final colorDatabaseManagerProvider =
    NotifierProvider<ColorDatabaseManagerNotifier, ColorDatabaseState>(
  ColorDatabaseManagerNotifier.new,
);
