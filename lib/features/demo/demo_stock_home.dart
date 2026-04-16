import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nexgen_command/models/roofline_configuration.dart';

/// Loader for the pre-authored demo stock home roofline configuration.
///
/// Parses `assets/demo/demo_home_trace.json` into a [RooflineConfiguration]
/// with fully-populated segment points, ready to feed into the production
/// roofline rendering pipeline.
class DemoStockHome {
  static const String assetPath = 'assets/demo/demo_home_trace.json';
  static const String imageAssetPath = 'assets/images/Demohomephoto.jpg';

  static RooflineConfiguration? _cached;

  /// Load the stock home configuration. Cached after first load.
  static Future<RooflineConfiguration> load() async {
    if (_cached != null) return _cached!;

    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;

    // The JSON omits Firestore-specific timestamp fields. Inject them now
    // so RooflineConfiguration.fromJson accepts the payload unchanged.
    final now = Timestamp.fromDate(DateTime.now());
    json['created_at'] = now;
    json['updated_at'] = now;

    _cached = RooflineConfiguration.fromJson('demo_stock_home', json);
    return _cached!;
  }
}
