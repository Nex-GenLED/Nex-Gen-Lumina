// Store window item 6, group 1: holiday and character display names (App
// Review 5.2). Display names only. Ids are unchanged, so saved favorites,
// schedules and the Neighborhood featured strip (which refers to
// 'xmas_grinch' by id) keep working. The old Grinch names stay as hidden
// aliases: never shown, still found.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/data/holiday_palettes.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';

void main() {
  test('holiday palettes carry the new names; ids unchanged', () async {
    final repo = PatternRepository();
    Future<String?> nameOf(String id) async => (await repo.getNodeById(id))?.name;
    expect(await nameOf('xmas_grinch'), 'Grumpy Green Guy');
    expect(await nameOf('xmas_frosty'), 'Snowman');
    expect(await nameOf('xmas_rudolph'), 'Reindeer Glow');
    expect((await repo.getNodeById('xmas_rudolph'))?.description,
        'Bright red with brown and gold');
  });

  test('no old name is displayed anywhere in the holiday, party or nature libraries', () {
    final shown = [
      for (final n in HolidayPalettes.getAllHolidayPaletteNodes()) ...[n.name, n.description ?? ''],
    ].join(' | ');
    for (final old in const ['Grinch', 'Frosty', 'Rudolph', 'Red nose']) {
      expect(shown, isNot(contains(old)), reason: old);
    }
  });

  test('"grinch" still finds the palette through its hidden alias', () async {
    final r = await PatternRepository().searchLibrary('grinch');
    expect(r.palettes.map((n) => n.id), contains('xmas_grinch'));
    expect(r.palettes.firstWhere((n) => n.id == 'xmas_grinch').name,
        'Grumpy Green Guy');
  });

  test('party and nature renames', () async {
    final r1 = await PatternRepository().searchLibrary('rainbow burst');
    expect(r1.palettes.map((n) => n.name), contains('Rainbow Burst'));
    final r2 = await PatternRepository().searchLibrary('lunar night');
    expect(r2.palettes.map((n) => n.name), contains('Lunar Night'));
  });

  test('the Grinch preset answers to its old name (voice and suggestions)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final all = c.read(publicPatternLibraryProvider).all;
    final p = all.firstWhere((p) => p.answersTo('Christmas - The Grinch'));
    expect(p.name, 'Christmas - Grumpy Green Guy');
    expect(p.answersTo('christmas - grumpy green guy'), isTrue);
    expect(all.where((p) => p.name.contains('Grinch')), isEmpty,
        reason: 'the old name is never displayed');
  });
}
