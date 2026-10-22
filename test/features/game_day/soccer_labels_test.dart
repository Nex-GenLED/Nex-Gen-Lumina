// Store window item 6, group 4: the FIFA World Cup and Champions League
// labels become generic display names (App Review 5.2). Only the labels
// change. The league TOKENS on team rows, which match teams to folders and
// ESPN, stay exactly as they were.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/explore_patterns/ui/explore_design_system.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/sports_library_builder.dart';

void main() {
  test('pickers show the generic labels', () {
    expect(SportType.fifa.displayName, 'International Soccer');
    expect(SportType.championsLeague.displayName, 'European Club Soccer');
  });

  test('Explore folders show the generic labels, no year, no mark', () {
    final names =
        SportsLibraryBuilder.getLeagueFolders().map((n) => n.name).toList();
    expect(names, containsAll(const ['International Soccer', 'European Club Soccer']));
    for (final n in names) {
      expect(n, isNot(contains('FIFA')));
      expect(n, isNot(contains('World Cup')));
      expect(n, isNot(contains('Champions League')));
      expect(n, isNot(contains('2026')));
    }
  });

  test('the renamed folders keep their Explore colours and emoji', () {
    // The theme map is keyed by display name; a stale key silently drops
    // the folder to the default look.
    expect(kFolderThemes['international soccer'], isNotNull);
    expect(kFolderThemes['european club soccer'], isNotNull);
  });
}
