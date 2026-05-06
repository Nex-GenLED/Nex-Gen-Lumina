import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/models/inventory/product_catalog_item.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Product Catalog Providers
//
// All read from /product_catalog (global). Writes go through the
// catalog management screen (Part 9) — this file is read-only.
//
// Filters in code (category, search) instead of at query time so a
// single underlying stream of active SKUs can feed every screen and
// stay live even as filters change. Catalog size is small (<100 SKUs)
// so the bandwidth cost is negligible.
// ─────────────────────────────────────────────────────────────────────────────

/// Streams every active SKU in the catalog, ordered by category then name.
/// Inactive SKUs (is_active == false) are filtered out — those are
/// products Tyler has retired but kept around for historical-order
/// rendering.
final allProductsProvider =
    StreamProvider<List<ProductCatalogItem>>((ref) {
  return FirebaseFirestore.instance
      .collection('product_catalog')
      .where('is_active', isEqualTo: true)
      .snapshots()
      .map((snap) {
    final items = snap.docs
        .map((d) => ProductCatalogItem.fromJson(d.data()))
        .toList();
    items.sort((a, b) {
      final cat = a.category.compareTo(b.category);
      if (cat != 0) return cat;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  });
});

/// Same stream as [allProductsProvider] but includes inactive SKUs.
/// Used by the catalog management screen and by historical-order
/// rendering (so a line-item SKU that has since been deactivated still
/// resolves to a name).
final allProductsIncludingInactiveProvider =
    StreamProvider<List<ProductCatalogItem>>((ref) {
  return FirebaseFirestore.instance
      .collection('product_catalog')
      .snapshots()
      .map((snap) {
    final items = snap.docs
        .map((d) => ProductCatalogItem.fromJson(d.data()))
        .toList();
    items.sort((a, b) {
      final cat = a.category.compareTo(b.category);
      if (cat != 0) return cat;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  });
});

/// Catalog filtered to a single category (e.g. 'lights', 'rails').
/// Falls through [allProductsProvider] so the stream stays live.
final productsByCategoryProvider =
    Provider.family<List<ProductCatalogItem>, String>((ref, category) {
  final all = ref.watch(allProductsProvider).valueOrNull ?? const [];
  return all.where((p) => p.category == category).toList();
});

/// Single SKU lookup. Returns null while loading or if the SKU is
/// missing/inactive. Use [allProductsIncludingInactiveProvider] +
/// firstWhereOrNull for historical-order rendering where inactive
/// items need to resolve.
final productBySkuProvider =
    Provider.family<ProductCatalogItem?, String>((ref, sku) {
  final all = ref.watch(allProductsProvider).valueOrNull;
  if (all == null) return null;
  for (final p in all) {
    if (p.sku == sku) return p;
  }
  return null;
});

/// Case-insensitive search across name, sku, and description. Empty
/// query returns the full active catalog.
final catalogSearchProvider =
    Provider.family<List<ProductCatalogItem>, String>((ref, query) {
  final all = ref.watch(allProductsProvider).valueOrNull ?? const [];
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return all;
  return all.where((p) {
    return p.name.toLowerCase().contains(q) ||
        p.sku.toLowerCase().contains(q) ||
        p.description.toLowerCase().contains(q);
  }).toList();
});

// ─────────────────────────────────────────────────────────────────────────────
// ProductCatalogNotifier
//
// Write surface for the global /product_catalog. Used by the
// corporate catalog management screen (Part 9). All writes are
// gated by the firestore.rules /product_catalog/{sku} rule
// (isUserRoleAdmin OR hasAdminOrOwnerClaim) — the notifier itself
// adds no in-process auth checks; the rule layer is the boundary.
// ─────────────────────────────────────────────────────────────────────────────

class ProductCatalogNotifier {
  final FirebaseFirestore _db;
  ProductCatalogNotifier(this._db);

  CollectionReference<Map<String, dynamic>> get _catalog =>
      _db.collection('product_catalog');

  /// Set unit_price for a single SKU.
  Future<void> updateUnitPrice({
    required String sku,
    required double unitPrice,
  }) async {
    await _catalog.doc(sku).update({
      'unit_price': unitPrice,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Set unit_price for every active SKU in [category]. Returns the
  /// number of docs updated. Bulk updates run in a single batch so
  /// they're atomic — a partial failure won't leave the category in
  /// a half-updated state.
  Future<int> bulkUpdateCategoryPrice({
    required String category,
    required double unitPrice,
  }) async {
    final snap = await _catalog
        .where('category', isEqualTo: category)
        .where('is_active', isEqualTo: true)
        .get();
    if (snap.docs.isEmpty) return 0;
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'unit_price': unitPrice,
        'updated_at': now,
      });
    }
    await batch.commit();
    return snap.docs.length;
  }

  /// Toggle is_active. Deactivated SKUs disappear from the dealer
  /// order screen but remain in /product_catalog so historical
  /// orders that reference them can still resolve names + pack info
  /// via allProductsIncludingInactiveProvider.
  Future<void> setActive({
    required String sku,
    required bool isActive,
  }) async {
    await _catalog.doc(sku).update({
      'is_active': isActive,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Create a brand-new SKU. Throws StateError if the SKU id is
  /// already taken — the spec forbids overwriting existing catalog
  /// docs (would silently lose price history on collision).
  Future<void> createProduct(ProductCatalogItem item) async {
    final ref = _catalog.doc(item.sku);
    final existing = await ref.get();
    if (existing.exists) {
      throw StateError(
          'SKU ${item.sku} already exists in the catalog.');
    }
    final now = Timestamp.now();
    await ref.set({
      ...item.toJson(),
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Update arbitrary fields on an existing SKU (name, description,
  /// pack info, voltage flags). SKU id itself is immutable — to
  /// rename, deactivate the old and create a new one.
  Future<void> updateProduct(ProductCatalogItem item) async {
    await _catalog.doc(item.sku).update({
      ...item.toJson(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }
}

/// Singleton notifier provider.
final productCatalogNotifierProvider = Provider<ProductCatalogNotifier>(
  (ref) => ProductCatalogNotifier(FirebaseFirestore.instance),
);
