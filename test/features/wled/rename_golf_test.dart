// Store window item 6, group 2: golf majors and trophies become descriptive
// names (App Review 5.2). Display names and descriptions only: folder and
// palette ids are unchanged. Hidden search keywords such as "masters" and
// "augusta" stay, so search still finds the folders. "Augusta Golf" is the
// owner's decision for the former Masters folder (on the attorney list).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/golf_library_builder.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';

void main() {
  final nodes = GolfLibraryBuilder.buildFullGolfHierarchy();
  final shown = [for (final n in nodes) ...[n.name, n.description ?? '']].join(' | ');

  test('the folders carry the approved names', () {
    final folders = GolfLibraryBuilder.getGolfSubfolders().map((n) => n.name).toList();
    expect(folders, containsAll(const [
      'Augusta Golf', 'Team Match Play', 'National Championship',
      'Links Classic', 'Pro Championship',
    ]));
  });

  test('palettes carry the approved names', () {
    for (final name in const [
      'Clubhouse Green', 'Back Nine', 'Magnolia Drive', 'USA Red, White & Blue',
      'Europe Blue & Gold', 'Match Play Gold & Navy', 'Championship Classic',
      'Deep Rough', 'Sandhills', 'Links Trophy Silver', 'Navy & Gold Classic',
      'Silver Trophy', 'Fairway Glory',
    ]) {
      expect(nodes.map((n) => n.name), contains(name), reason: name);
    }
  });

  test('no tournament, trophy or venue mark is displayed', () {
    for (final old in const [
      'The Masters', 'Masters Green', 'Amen Corner', 'Magnolia Lane',
      'Ryder Cup', 'US Open', 'The Open', 'British Open', 'PGA', 'USGA',
      'Claret Jug', 'Wanamaker', 'Pinehurst', 'Augusta National', 'Team USA',
      'Team Europe',
    ]) {
      expect(shown, isNot(contains(old)), reason: old);
    }
  });

  test('hidden keywords still find the renamed themes, never displayed', () async {
    expect(GolfLibraryBuilder.searchGolfThemes('masters').map((n) => n.name),
        contains('Clubhouse Green'));
    final r = await PatternRepository().searchLibrary('masters');
    expect(r.palettes.map((n) => n.name), contains('Clubhouse Green'));
    expect(r.palettes.map((n) => n.name).where((n) => n.contains('Masters')),
        isEmpty);
  });
}
