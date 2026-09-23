// M7 — Twinkle (and the rest of the sparkle-over-a-field family) must not be
// sent a field colour that hides its own sparkles.
//
// WLED v0.15.1: Twinkle calls fade_out() toward col[1]. Architectural's two
// near-identical whites went out as col[0], col[1] → bench-measured SOLID
// (97/97 lit LEDs constant, ~93 % exactly col[1], 10 LEDs changed in 10 s).
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/selector_payload.dart';
import 'package:nexgen_command/features/wled/sparkle_background.dart';

const _warm1 = [255, 177, 110, 0]; // 3000K slot 1
const _warm2 = [255, 207, 160, 0]; // 3000K slot 2

Map<String, dynamic> _seg(Map<String, dynamic> payload) =>
    (payload['seg'] as List).first as Map<String, dynamic>;

void main() {
  group('readableSparkleColors', () {
    test('near-identical whites → dim field, pal 0, sparkle colour untouched', () {
      final r = readableSparkleColors(17, const [_warm1, _warm2]);
      expect(r.fieldReplaced, isTrue);
      expect(r.colors[0], _warm1);
      expect(r.colors[1], [77, 53, 33, 0], reason: '30 % of the sparkle colour');
      expect(r.paletteOverride, 0,
          reason: 'pal 5 builds the sparkle palette FROM col[] — the dim field '
              'would become half the sparkles');
    });

    test('clearly different colours are left exactly alone (red sparkles on green)', () {
      const cols = [[255, 0, 0, 0], [0, 255, 0, 0]];
      final r = readableSparkleColors(17, cols);
      expect(r.fieldReplaced, isFalse);
      expect(r.colors, cols);
      expect(r.paletteOverride, isNull);
    });

    test('single colour / already-dark field / non-sparkle effect → untouched', () {
      expect(readableSparkleColors(17, const [_warm1]).fieldReplaced, isFalse);
      expect(readableSparkleColors(17, const [_warm1, [0, 0, 0, 0]]).fieldReplaced, isFalse);
      // Chase (28) labels slot 2 "Bg" too, but a second palette colour there IS
      // the look — it is deliberately not in the family.
      expect(readableSparkleColors(28, const [_warm1, _warm2]).fieldReplaced, isFalse);
      expect(readableSparkleColors(0, const [_warm1, _warm2]).fieldReplaced, isFalse);
    });

    test('Twinklefox keeps its palette (it is palette-driven) but gets the dim field', () {
      final r = readableSparkleColors(80, const [_warm1, _warm2]);
      expect(r.fieldReplaced, isTrue);
      expect(r.paletteOverride, isNull);
    });

    test('an RGBW white that lives in the W channel is compared on W as well', () {
      final r = readableSparkleColors(17, const [[0, 0, 0, 255], [0, 0, 0, 230]]);
      expect(r.fieldReplaced, isTrue);
      expect(r.colors[1], [0, 0, 0, 77]);
    });
  });

  test('the tuner builder applies it (one builder → preview, apply, save-to-design)', () {
    final seg = _seg(buildSelectorPayload(SelectorState(
      effectId: 17,
      speed: getSpeedProfile(17).rawDefault,
      intensity: 128,
      grouping: 1,
      spacing: 2,
      colors: const [_warm1, _warm2],
    )));
    expect(seg['fx'], 17, reason: 'still genuine Twinkle — nothing is substituted');
    expect(seg['pal'], 0);
    expect((seg['col'] as List)[1], [77, 53, 33, 0]);
    expect(seg['grp'], 1);
    expect(seg['spc'], 2, reason: 'the Architectural spacing is preserved');
    expect(seg['sx'], greaterThanOrEqualTo(180),
        reason: 'was 40 = one new pixel every ~1.1 s');
  });

  test('an explicit paletteOverride from the caller still wins', () {
    final seg = _seg(buildSelectorPayload(const SelectorState(
      effectId: 17, speed: 200, intensity: 128,
      colors: [_warm1, _warm2], paletteOverride: 7)));
    expect(seg['pal'], 7);
  });

  group('library cards', () {
    final repo = PatternRepository();

    test('EVERY Architectural card in the family has a readable field', () async {
      int checked = 0;
      for (final kelvin in ['k2000', 'k2700', 'k3000', 'k3500', 'k4000', 'k4500', 'k5000', 'k5500', 'k6500']) {
        for (final id in ['arch_${kelvin}_all', 'arch_${kelvin}_1on2off']) {
          final node = await repo.getNodeById(id);
          if (node == null) continue;
          for (final item in await repo.generatePatternsForNode(node)) {
            final seg = _seg(item.wledPayload);
            if (!kSparkleOverFieldEffectIds.contains(seg['fx'])) continue;
            final col = (seg['col'] as List).cast<List>();
            final sparkle = col[0].cast<int>(), field = col[1].cast<int>();
            final lumS = sparkle[0] + sparkle[1] + sparkle[2];
            final lumF = field[0] + field[1] + field[2];
            expect(lumF, lessThan(lumS * 0.4),
                reason: '${item.name} (fx ${seg['fx']}): field $field hides sparkle $sparkle');
            checked++;
          }
        }
      }
      // 9 Kelvin styles x 2 cards, each yielding exactly one sparkle-family
      // item (fx 51 Fairytwinkle) = 18. The floor was 20 while the Galaxy &
      // Starlight twinkle cards still existed; they were removed 2026-09-23
      // (their spacing rendered half the strip permanently black).
      expect(checked, greaterThanOrEqualTo(18));
    });

    test('Twinkle picked from Top Picks is genuine fx 17 at a readable speed', () {
      // Used to target the Galaxy "Classic Twinkle" card, removed 2026-09-23.
      // The live route to Twinkle on an Architectural white is the tuner's
      // Top Picks entry: fx 17 at its profile default, via buildSelectorPayload.
      final seg = _seg(buildSelectorPayload(SelectorState(
        effectId: 17,
        speed: getSpeedProfile(17).rawDefault,
        intensity: 128,
        colors: const [_warm1, _warm2],
      )));
      expect(seg['fx'], 17);
      expect(seg['sx'], 200);
      expect(seg['pal'], 0);
    });

    test('a holiday red/green Twinkle card is byte-for-byte what it was', () async {
      // Any 2-colour palette with clearly different colours: nothing changes.
      final seg = withReadableSparkleField({
        'fx': 17, 'pal': 5, 'sx': 60, 'ix': 128,
        'col': [[255, 0, 0, 0], [0, 255, 0, 0], [0, 0, 0, 0]],
      });
      expect(seg['pal'], 5);
      expect(seg['col'], [[255, 0, 0, 0], [0, 255, 0, 0], [0, 0, 0, 0]]);
    });
  });
}
