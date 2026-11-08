// Roofline slice 1, item 1 — a saved design carries a LAYOUT STAMP: the
// controller it was painted for and the LED count of every bus at save time.
//
// This file is the fail-before proof, written against raw Firestore maps only
// so it compiles on the code as it was. Before the stamp existed,
// CustomDesign.toFirestore() wrote `name`, `channels`, `brightness` … and
// nothing about the layout, so a design loaded from a document that carried
// `controller_id` / `bus_lengths` lost both on the next save (rename, tuner,
// duplicate, edit). After: the two fields round-trip untouched, and a legacy
// document without them is still read and written exactly as before.
//
// Fixture: one controller, three buses of 100 LEDs each (ids 0, 1, 2).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_models.dart';

final _now = DateTime(2026, 11, 4);

Map<String, dynamic> _paintedDoc({bool stamped = true}) => {
      'name': 'Porch stripes',
      'created_at': Timestamp.fromDate(_now),
      'updated_at': Timestamp.fromDate(_now),
      'owner_id': 'customer-uid',
      'per_pixel': true,
      'brightness': 120,
      'brightness_stated': true,
      'tags': <String>[],
      'is_segment_aware': false,
      'channels': [
        for (var id = 0; id < 3; id++)
          {
            'channel_id': id,
            'channel_name': 'Channel ${id + 1}',
            'included': true,
            'led_count': 100,
            'color_groups': [
              {'start_led': 0, 'end_led': 49, 'color': [255, 0, 0, 0]},
              {'start_led': 50, 'end_led': 99, 'color': [0, 0, 255, 0]},
            ],
          },
      ],
      if (stamped) 'controller_id': 'ctl-a',
      if (stamped) 'bus_lengths': [100, 100, 100],
    };

void main() {
  test('controller_id and bus_lengths survive a load → save round trip', () {
    final loaded = CustomDesign.fromFirestoreData('d1', _paintedDoc());
    final written = loaded.toFirestore();
    expect(written['controller_id'], 'ctl-a',
        reason: 'the stamp used to be dropped by toFirestore()');
    expect(written['bus_lengths'], [100, 100, 100]);
  });

  test('the stamp survives copyWith (rename, tuner, duplicate all copy)', () {
    final loaded = CustomDesign.fromFirestoreData('d1', _paintedDoc());
    final renamed = loaded.copyWith(name: 'Renamed').toFirestore();
    expect(renamed['controller_id'], 'ctl-a');
    expect(renamed['bus_lengths'], [100, 100, 100]);
  });

  test('a legacy document without a stamp is written without one — nothing '
      'is invented for designs saved before the stamp existed', () {
    final loaded = CustomDesign.fromFirestoreData('d0', _paintedDoc(stamped: false));
    final written = loaded.toFirestore();
    expect(written.containsKey('controller_id'), isFalse);
    expect(written.containsKey('bus_lengths'), isFalse);
    expect(loaded.isPositional, isTrue, reason: 'everything else unchanged');
    expect(loaded.channels, hasLength(3));
  });

  test('a malformed stamp (non-integer lengths) is read as no stamp', () {
    final doc = _paintedDoc()..['bus_lengths'] = ['a', null, 3.5];
    final loaded = CustomDesign.fromFirestoreData('d2', doc);
    expect(loaded.toFirestore().containsKey('bus_lengths'), isFalse);
  });
}
