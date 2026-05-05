import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/models/commercial/brand_color.dart';
import 'package:nexgen_command/models/commercial/commercial_brand_profile.dart';

/// Auto-generates the five canonical brand-aligned WLED designs and
/// saves them as favorites + records their names on the customer's
/// /users/{uid}/brand_profile/brand doc.
///
/// Called by BrandSetupScreen after a successful profile save.
///
/// Design naming convention (no folder/grouping infrastructure exists in
/// FavoritesNotifier — see Conflict A directive in the architectural
/// notes — so brand designs are kept findable via name prefix):
///
///   "[CompanyName] Solid"
///   "[CompanyName] Breathe"
///   "[CompanyName] Chase"
///   "[CompanyName] Event Mode"
///   "[CompanyName] Welcome"
///
/// Pattern IDs are stable derivatives of the brand id ("brand_state-farm_solid"
/// etc.) so re-saving the brand profile updates the existing favorites
/// in-place rather than creating duplicates.
class BrandDesignGenerator {
  BrandDesignGenerator({
    required FavoritesNotifier favoritesNotifier,
    required FirebaseFirestore firestore,
  })  : _favorites = favoritesNotifier,
        _firestore = firestore;

  final FavoritesNotifier _favorites;
  final FirebaseFirestore _firestore;

  /// Generate and persist all five designs for [brand]. Writes favorites
  /// under [userId] and updates that user's brand_profile doc with the
  /// list of names that were generated (so the Brand tab can list them
  /// without scanning favorites by prefix).
  ///
  /// Skips silently and returns an empty list if [brand] has no colors —
  /// nothing meaningful to render without at least a primary color.
  Future<List<String>> generateBrandDesigns({
    required String userId,
    required CommercialBrandProfile brand,
  }) async {
    if (brand.colors.isEmpty) {
      debugPrint('BrandDesignGenerator: brand has no colors, skipping');
      return const [];
    }

    final designs = <_BrandDesign>[
      _buildSolid(brand),
      _buildBreathe(brand),
      _buildChase(brand),
      _buildEventMode(brand),
      _buildWelcome(brand),
    ];

    for (final d in designs) {
      try {
        await _favorites.addFavorite(
          patternId: d.patternId,
          patternName: d.name,
          patternData: d.payload,
          autoAdded: true,
        );
      } catch (e) {
        // One failure shouldn't take down the rest. Log and continue.
        debugPrint(
            'BrandDesignGenerator: failed to save "${d.name}" — $e');
      }
    }

    final names = designs.map((d) => d.name).toList(growable: false);

    // Persist the list of generated names on the brand_profile doc so
    // the Brand tab on CommercialHomeScreen can render them with one
    // doc read instead of scanning all favorites by name prefix.
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('brand_profile')
          .doc('brand')
          .set(
        {'generated_designs': names},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint(
          'BrandDesignGenerator: failed to update generated_designs — $e');
    }

    return names;
  }

  // ─── Public preview/apply API ────────────────────────────────────────────
  // Used by the Brand tab on CommercialHomeScreen and the Dashboard quick
  // actions to APPLY a design without writing to favorites. Each method
  // returns the WLED payload only — the favorite-saving lifecycle is
  // owned by [generateBrandDesigns].
  //
  // Returns null when [brand] has no usable colors (each design needs at
  // least a primary color; some need two or three).

  Map<String, dynamic>? solidPayloadFor(CommercialBrandProfile brand) {
    if (brand.colors.isEmpty) return null;
    return _buildSolid(brand).payload;
  }

  Map<String, dynamic>? breathePayloadFor(CommercialBrandProfile brand) {
    if (brand.colors.isEmpty) return null;
    return _buildBreathe(brand).payload;
  }

  Map<String, dynamic>? chasePayloadFor(CommercialBrandProfile brand) {
    if (brand.colors.isEmpty) return null;
    return _buildChase(brand).payload;
  }

  Map<String, dynamic>? eventModePayloadFor(CommercialBrandProfile brand) {
    if (brand.colors.isEmpty) return null;
    return _buildEventMode(brand).payload;
  }

  Map<String, dynamic>? welcomePayloadFor(CommercialBrandProfile brand) {
    if (brand.colors.isEmpty) return null;
    return _buildWelcome(brand).payload;
  }

  /// Returns all five payloads keyed by display name suffix
  /// ("Solid", "Breathe", "Chase", "Event Mode", "Welcome"). Used by
  /// the Brand tab's horizontal design-card scroll so it can iterate
  /// without hard-coding the five method calls.
  Map<String, Map<String, dynamic>> allPayloadsFor(
      CommercialBrandProfile brand) {
    if (brand.colors.isEmpty) return const {};
    return {
      'Solid': _buildSolid(brand).payload,
      'Breathe': _buildBreathe(brand).payload,
      'Chase': _buildChase(brand).payload,
      'Event Mode': _buildEventMode(brand).payload,
      'Welcome': _buildWelcome(brand).payload,
    };
  }

  // ─── Design builders ─────────────────────────────────────────────────────

  /// Design 1 — Solid pattern alternating brand colors.
  ///
  ///   • fx=83 when 2 colors, fx=84 when 3+ (matches WLED's solid-pattern
  ///     dual / tri color variants — same convention used by the rest of
  ///     the app's colorway generators).
  ///   • ix=8 (small group size: 2 LEDs per color).
  ///   • pal=5 (Colors Only) — forces WLED to use the col[] array
  ///     verbatim, no palette tinting. Required for accurate brand
  ///     reproduction.
  _BrandDesign _buildSolid(CommercialBrandProfile brand) {
    final activeColors = _activeColors(brand).take(3).toList();
    final fx = activeColors.length >= 3 ? 84 : 83;
    return _BrandDesign(
      patternId: _patternId(brand, 'solid'),
      name: '${brand.companyName} Solid',
      payload: {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': fx,
            'sx': 8,
            'ix': 8,
            'pal': 5,
            'col': activeColors.map(_toRgbw).toList(),
          },
        ],
      },
    );
  }

  /// Design 2 — Breathe on the primary color.
  ///
  ///   • fx=2 (Breathe).
  ///   • Primary color only.
  ///   • sx=64 (slow, calming).
  _BrandDesign _buildBreathe(CommercialBrandProfile brand) {
    final primary = _primaryColor(brand);
    return _BrandDesign(
      patternId: _patternId(brand, 'breathe'),
      name: '${brand.companyName} Breathe',
      payload: {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': 2,
            'sx': 64,
            'col': [_toRgbw(primary)],
          },
        ],
      },
    );
  }

  /// Design 3 — Chase across primary + secondary.
  ///
  ///   • fx=28 (Chase).
  ///   • Primary chasing on secondary.
  ///   • sx=128 (medium).
  _BrandDesign _buildChase(CommercialBrandProfile brand) {
    final primary = _primaryColor(brand);
    final secondary = _secondaryColor(brand) ?? primary;
    return _BrandDesign(
      patternId: _patternId(brand, 'chase'),
      name: '${brand.companyName} Chase',
      payload: {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': 28,
            'sx': 128,
            'col': [_toRgbw(primary), _toRgbw(secondary)],
          },
        ],
      },
    );
  }

  /// Design 4 — Event mode running pattern across every brand color.
  ///
  ///   • fx=41 (Running).
  ///   • All brand colors.
  ///   • sx=150, pal=5 (Colors Only).
  _BrandDesign _buildEventMode(CommercialBrandProfile brand) {
    final activeColors = _activeColors(brand);
    return _BrandDesign(
      patternId: _patternId(brand, 'event'),
      name: '${brand.companyName} Event Mode',
      payload: {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': 41,
            'sx': 150,
            'pal': 5,
            'col': activeColors.map(_toRgbw).toList(),
          },
        ],
      },
    );
  }

  /// Design 5 — Subtle ambient solid on the primary color.
  ///
  ///   • fx=0 (Solid).
  ///   • Primary only.
  ///   • bri=180 (≈70%) for warm welcome ambience.
  _BrandDesign _buildWelcome(CommercialBrandProfile brand) {
    final primary = _primaryColor(brand);
    return _BrandDesign(
      patternId: _patternId(brand, 'welcome'),
      name: '${brand.companyName} Welcome',
      payload: {
        'on': true,
        'bri': 180,
        'seg': [
          {
            'fx': 0,
            'col': [_toRgbw(primary)],
          },
        ],
      },
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Filters [brand.colors] down to the ones the customer has marked
  /// `active_in_engine`. If none are active (legacy / corrupt profile),
  /// falls back to all colors so we still generate something usable.
  List<BrandColor> _activeColors(CommercialBrandProfile brand) {
    final active = brand.colors.where((c) => c.activeInEngine).toList();
    if (active.isNotEmpty) return active;
    return List<BrandColor>.from(brand.colors);
  }

  /// Resolves the primary color: first `role_tag == 'primary'`, then
  /// the first active color, then the first color overall.
  BrandColor _primaryColor(CommercialBrandProfile brand) {
    for (final c in brand.colors) {
      if (c.activeInEngine && c.roleTag.toLowerCase() == 'primary') return c;
    }
    final active = _activeColors(brand);
    return active.first;
  }

  /// Resolves the secondary color: first `role_tag == 'secondary'`, then
  /// the second active color, or null if neither exists.
  BrandColor? _secondaryColor(CommercialBrandProfile brand) {
    for (final c in brand.colors) {
      if (c.activeInEngine && c.roleTag.toLowerCase() == 'secondary') return c;
    }
    final active = _activeColors(brand);
    if (active.length >= 2) return active[1];
    return null;
  }

  /// Convert a [BrandColor]'s `hex_code` into a WLED RGBW array
  /// `[r, g, b, 0]`. White channel is forced to 0 — the brand's hex is
  /// the source of truth and the white LED would desaturate it.
  ///
  /// Strips `#` defensively. The seed script and BrandSetupScreen both
  /// store hex without the prefix, but legacy data or third-party
  /// imports might include one.
  List<int> _toRgbw(BrandColor color) {
    final hex = color.hexCode.replaceAll('#', '').trim();
    if (hex.length != 6) {
      // Malformed — fall back to off (zeros). Caller may also skip the
      // design entirely; here we let it through so the rest of the
      // payload is structurally valid.
      return const [0, 0, 0, 0];
    }
    final r = int.tryParse(hex.substring(0, 2), radix: 16) ?? 0;
    final g = int.tryParse(hex.substring(2, 4), radix: 16) ?? 0;
    final b = int.tryParse(hex.substring(4, 6), radix: 16) ?? 0;
    return [r, g, b, 0];
  }

  /// Build a stable pattern id from the brand. Prefers the library id
  /// (canonical, slugified at seed time); falls back to a slugified
  /// company name. Re-running with the same brand overwrites in place
  /// rather than creating duplicates.
  String _patternId(CommercialBrandProfile brand, String suffix) {
    final base = brand.brandLibraryId?.trim().isNotEmpty == true
        ? brand.brandLibraryId!.trim()
        : _slug(brand.companyName);
    return 'brand_${base}_$suffix';
  }

  String _slug(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '')
        .trim();
  }
}

class _BrandDesign {
  const _BrandDesign({
    required this.patternId,
    required this.name,
    required this.payload,
  });
  final String patternId;
  final String name;
  final Map<String, dynamic> payload;
}

/// Riverpod provider for [BrandDesignGenerator]. Singleton at root scope.
///
/// Note: the FavoritesNotifier and the generator share the same root
/// ProviderScope lifetime — capturing the notifier reference here is
/// safe because neither is rebuilt for the duration of the app session.
final brandDesignGeneratorProvider = Provider<BrandDesignGenerator>((ref) {
  final favorites = ref.read(favoritesNotifierProvider.notifier);
  return BrandDesignGenerator(
    favoritesNotifier: favorites,
    firestore: FirebaseFirestore.instance,
  );
});

/// Convenience: pulls the generator from the provider and runs it for
/// the currently-signed-in user. Returns the names that were generated,
/// or an empty list if no user is signed in or [brand] has no colors.
///
/// Takes [WidgetRef] (not [Ref]) because the only caller is
/// BrandSetupScreen, which lives inside the widget tree. WidgetRef
/// carries the same `.read` method needed to resolve the provider.
Future<List<String>> runBrandDesignGenerator(
  WidgetRef ref,
  CommercialBrandProfile brand,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return const [];
  final gen = ref.read(brandDesignGeneratorProvider);
  return gen.generateBrandDesigns(userId: user.uid, brand: brand);
}
