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
