import 'package:cloud_firestore/cloud_firestore.dart';

/// Seeds the material catalog and inventory collections for a dealer.
///
/// Writes to:
///   /dealers/{dealerCode}/materialCatalog/{materialId}
///   /dealers/{dealerCode}/inventory/{materialId}
///
/// Call from a dev screen or button. Total: 35 catalog + 35 inventory = 70 docs.
Future<void> seedMaterialCatalog(String dealerCode) async {
  final db = FirebaseFirestore.instance;
  final catalogRef = db.collection('dealers/$dealerCode/materialCatalog');
  final inventoryRef = db.collection('dealers/$dealerCode/inventory');
  final batch = db.batch();
  final now = DateTime.now();

  void add(String id, Map<String, dynamic> catalog, {double reorderThreshold = 10}) {
    batch.set(catalogRef.doc(id), catalog);
    batch.set(inventoryRef.doc(id), {
      'quantityOnHand': 0,
      'quantityReserved': 0,
      'reorderThreshold': reorderThreshold,
      'lastUpdated': Timestamp.fromDate(now),
      'lastUpdatedBy': 'seed_script',
    });
  }

  // ────────────────────────────────────────────────────
  // LIGHT PCS — 24V  (3 items)
  // ────────────────────────────────────────────────────
  add('light_1pcs_24v', {
    'name': '1-Light PCS 24V',
    'category': 'lightPcs',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'voltage': 'v24',
    'isActive': true,
  });
  add('light_5pcs_24v', {
    'name': '5-Light PCS 24V',
    'category': 'lightPcs',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'voltage': 'v24',
    'isActive': true,
  });
  add('light_10pcs_24v', {
    'name': '10-Light PCS 24V',
    'category': 'lightPcs',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'voltage': 'v24',
    'isActive': true,
  });

  // ────────────────────────────────────────────────────
  // LIGHT PCS — 36V  (3 items)
  // ────────────────────────────────────────────────────
  add('light_1pcs_36v', {
    'name': '1-Light PCS 36V',
    'category': 'lightPcs',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'voltage': 'v36',
    'isActive': true,
  });
  add('light_5pcs_36v', {
    'name': '5-Light PCS 36V',
    'category': 'lightPcs',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'voltage': 'v36',
    'isActive': true,
  });
  add('light_10pcs_36v', {
    'name': '10-Light PCS 36V',
    'category': 'lightPcs',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'voltage': 'v36',
    'isActive': true,
  });

  // ────────────────────────────────────────────────────
  // ROPE LIGHTING  (1 item)
  // ────────────────────────────────────────────────────
  add('rope_diffused_5m', {
    'name': 'Diffused Rope Light 5m',
    'category': 'ropeLighting',
    'unit': 'piece',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'isActive': true,
  });

  // ────────────────────────────────────────────────────
  // 1-PIECE RAILS — per color  (7 items)
  // ────────────────────────────────────────────────────
  const railColors = ['black', 'brown', 'beige', 'white', 'navy', 'silver', 'grey'];
  for (final color in railColors) {
    add('rail_1pc_$color', {
      'name': '1-Piece Rail ${color[0].toUpperCase()}${color.substring(1)}',
      'category': 'railOnePiece',
      'unit': 'each',
      'unitCostCents': 0,
      'overageRate': 0.0,
      'colorVariant': color,
      'isActive': true,
    });
  }

  // ────────────────────────────────────────────────────
  // 2-PIECE RAILS — per color  (7 items)
  // ────────────────────────────────────────────────────
  for (final color in railColors) {
    add('rail_2pc_$color', {
      'name': '2-Piece Rail ${color[0].toUpperCase()}${color.substring(1)}',
      'category': 'railTwoPiece',
      'unit': 'each',
      'unitCostCents': 0,
      'overageRate': 0.0,
      'colorVariant': color,
      'isActive': true,
    });
  }

  // ────────────────────────────────────────────────────
  // CONNECTOR WIRES — per length  (5 items)
  // ────────────────────────────────────────────────────
  const wireLengths = ['1ft', '2ft', '5ft', '10ft', '20ft'];
  for (final len in wireLengths) {
    add('wire_conn_$len', {
      'name': 'Connector Wire $len',
      'category': 'connectorWire',
      'unit': 'each',
      'unitCostCents': 0,
      'overageRate': 0.0,
      'lengthVariant': len,
      'isActive': true,
    });
  }

  // ────────────────────────────────────────────────────
  // ACCESSORIES  (4 items)
  // ────────────────────────────────────────────────────
  add('t_connector', {
    'name': 'T-Connector',
    'category': 'accessories',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'isActive': true,
  });
  add('y_connector', {
    'name': 'Y-Connector',
    'category': 'accessories',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'isActive': true,
  });
  add('amplifier', {
    'name': 'Amplifier',
    'category': 'accessories',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'isActive': true,
  });
  add('radar_sensor', {
    'name': 'Radar Sensor',
    'category': 'accessories',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'isActive': true,
  });

  // ────────────────────────────────────────────────────
  // CONTROLLER  (1 item)
  // ────────────────────────────────────────────────────
  add('controller', {
    'name': 'Controller Unit',
    'category': 'controller',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'isActive': true,
  });

  // ────────────────────────────────────────────────────
  // POWER SUPPLIES — 24V  (2 items)
  // ────────────────────────────────────────────────────
  add('psu_350w_24v', {
    'name': 'Power Supply 350W 24V',
    'category': 'powerSupply',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'voltage': 'v24',
    'isActive': true,
  });
  add('psu_600w_24v', {
    'name': 'Power Supply 600W 24V',
    'category': 'powerSupply',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'voltage': 'v24',
    'isActive': true,
  });

  // ────────────────────────────────────────────────────
  // POWER SUPPLIES — 36V  (2 items)
  // ────────────────────────────────────────────────────
  add('psu_350w_36v', {
    'name': 'Power Supply 350W 36V',
    'category': 'powerSupply',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'voltage': 'v36',
    'isActive': true,
  });
  add('psu_600w_36v', {
    'name': 'Power Supply 600W 36V',
    'category': 'powerSupply',
    'unit': 'each',
    'unitCostCents': 0,
    'overageRate': 0.0,
    'voltage': 'v36',
    'isActive': true,
  });

  // ── Commit ──────────────────────────────────────────
  await batch.commit();
}
