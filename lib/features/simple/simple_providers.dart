import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';

/// Storage key for Simple Mode setting
const String _simpleModeKey = 'simple_mode_enabled';

/// Notifier that persists Simple Mode state to SharedPreferences
class SimpleModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    _loadPersistedValue();
    return false;
  }

  Future<void> _loadPersistedValue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_simpleModeKey) ?? false;
      state = saved;
    } catch (e) {
      // Ignore errors - will default to false
    }
  }

  @override
  set state(bool value) {
    super.state = value;
    _persistValue(value);
  }

  Future<void> _persistValue(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_simpleModeKey, value);
    } catch (e) {
      // Ignore persistence errors
    }
  }

  void toggle() {
    state = !state;
  }

  void enable() {
    state = true;
  }

  void disable() {
    state = false;
  }
}

/// Tracks whether Simple Mode is enabled.
/// When true, the app shows a simplified UI with only Home and Settings tabs.
final simpleModeProvider = NotifierProvider<SimpleModeNotifier, bool>(
  SimpleModeNotifier.new,
);

/// Manages the user's favorite patterns for Simple Mode.
/// Favorites are stored in Firestore at /users/{uid}/favorites
class SimpleFavoritesNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return [];

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('simple_mode')
        .doc('favorites')
        .get();

    if (!doc.exists || doc.data() == null) {
      // Auto-populate with default favorites on first access
      return _getDefaultFavorites();
    }

    final data = doc.data()!;
    final favoriteIds = (data['pattern_ids'] as List<dynamic>?)?.cast<String>() ?? [];
    return favoriteIds;
  }

  /// Default favorites to auto-populate for new users
  List<String> _getDefaultFavorites() {
    return [
      'warm_white',
      'cool_white',
      'red_white_blue',
      'halloween',
      'christmas',
    ];
  }

  /// Add a pattern to favorites
  Future<void> addFavorite(String patternId) async {
    final user = await ref.read(authStateProvider.future);
    if (user == null) return;

    final current = state.valueOrNull ?? [];
    if (current.contains(patternId)) return;

    final updated = [...current, patternId];
    state = AsyncValue.data(updated);

    await _saveFavorites(user.uid, updated);
  }

  /// Remove a pattern from favorites
  Future<void> removeFavorite(String patternId) async {
    final user = await ref.read(authStateProvider.future);
    if (user == null) return;

    final current = state.valueOrNull ?? [];
    final updated = current.where((id) => id != patternId).toList();
    state = AsyncValue.data(updated);

    await _saveFavorites(user.uid, updated);
  }

  /// Reorder favorites
  Future<void> reorderFavorites(List<String> newOrder) async {
    final user = await ref.read(authStateProvider.future);
    if (user == null) return;

    state = AsyncValue.data(newOrder);
    await _saveFavorites(user.uid, newOrder);
  }

  /// Save favorites to Firestore
  Future<void> _saveFavorites(String uid, List<String> favorites) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('simple_mode')
          .doc('favorites')
          .set({
        'pattern_ids': favorites,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Ignore save errors - will retry on next change
    }
  }

  /// Reset to default favorites
  Future<void> resetToDefaults() async {
    final user = await ref.read(authStateProvider.future);
    if (user == null) return;

    final defaults = _getDefaultFavorites();
    state = AsyncValue.data(defaults);
    await _saveFavorites(user.uid, defaults);
  }
}

/// User's favorite patterns for Simple Mode quick access.
/// Limited to 3-5 patterns for simplified UI.
final simpleFavoritesProvider = AsyncNotifierProvider<SimpleFavoritesNotifier, List<String>>(
  SimpleFavoritesNotifier.new,
);

/// Pattern usage analytics for auto-populating favorites.
/// Tracks how many times each pattern has been applied.
class PatternUsageNotifier extends AsyncNotifier<Map<String, int>> {
  @override
  Future<Map<String, int>> build() async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return {};

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('simple_mode')
        .doc('pattern_usage')
        .get();

    if (!doc.exists || doc.data() == null) return {};

    final data = doc.data()!;
    return Map<String, int>.from(data['usage'] ?? {});
  }

  /// Increment usage count for a pattern
  Future<void> recordUsage(String patternId) async {
    final user = await ref.read(authStateProvider.future);
    if (user == null) return;

    final current = state.valueOrNull ?? {};
    final updated = Map<String, int>.from(current);
    updated[patternId] = (updated[patternId] ?? 0) + 1;
    state = AsyncValue.data(updated);

    await _saveUsage(user.uid, updated);
  }

  /// Save usage data to Firestore
  Future<void> _saveUsage(String uid, Map<String, int> usage) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('simple_mode')
          .doc('pattern_usage')
          .set({
        'usage': usage,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Ignore save errors
    }
  }

  /// Get top N most-used patterns for auto-populating favorites
  List<String> getTopPatterns(int count) {
    final usage = state.valueOrNull ?? {};
    final sorted = usage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(count).map((e) => e.key).toList();
  }
}

/// Tracks pattern usage analytics for auto-populating Simple Mode favorites.
final patternUsageProvider = AsyncNotifierProvider<PatternUsageNotifier, Map<String, int>>(
  PatternUsageNotifier.new,
);
