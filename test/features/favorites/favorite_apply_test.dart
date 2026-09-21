// applyFavoritePayloadWith — the ONE routine that decides how a favorite
// reaches the lights. A per-pixel (Static) favorite must take the chunked
// spine My Designs uses; everything else stays one channel-filtered applyJson.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/editable_pattern_design.dart';
import 'package:nexgen_command/features/design/manual_editor/design_apply.dart';
import 'package:nexgen_command/features/favorites/favorite_apply.dart';
import 'package:nexgen_command/features/favorites/favorite_design_payload.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/wled/per_pixel.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channels = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 128, gpioPin: 0),
  DeviceChannel(id: 1, name: 'Channel 2', start: 128, stop: 290, gpioPin: 1),
];
const _editorChannels = [
  PatternEditorChannel(id: 0, name: 'Channel 1', ledCount: 128),
  PatternEditorChannel(id: 1, name: 'Channel 2', ledCount: 162),
];

EditablePattern _chiefs(int fx) => EditablePattern.fromGradientColors(
      id: 'team_nfl_chiefs',
      name: 'Kansas City Chiefs',
      colors: const [Color(0xFFE31837), Color(0xFFFFB81C)],
      effectId: fx,
    ).copyWith(actionColors: const [
      Color(0xFFE31837),
      Color(0xFFFFB81C),
      Color(0xFFFFFFFF),
    ], brightness: 180);

Map<String, dynamic> _staticFavorite() =>
    buildPerPixelFavoritePayload(customDesignFromEditablePattern(
      pattern: _chiefs(0),
      name: 'Kansas City Chiefs',
      ownerId: '',
      channels: _editorChannels,
    ));

/// Applies the production size rule to `applyJson`, so a test cannot pass by
/// sending something the real transport would have refused.
class _Repo implements WledRepository, PerPixelWriter {
  _Repo({this.failPixelsOn});
  final int? failPixelsOn;
  final json = <Map<String, dynamic>>[];
  final refused = <int>[];
  final pixels = <int, List<PixelSpan>>{};

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    final bytes = utf8.encode(jsonEncode(payload)).length;
    if (bytes > kMaxApplyPayloadBytes) {
      refused.add(bytes);
      return false;
    }
    json.add(payload);
    return true;
  }

  @override
  Future<bool> applyPerPixel({
    int segmentId = 0,
    required List<PixelSpan> spans,
    int chunkSize = kDefaultPixelChunkSize,
  }) async {
    if (segmentId == failPixelsOn) return false;
    pixels[segmentId] = spans;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

ProviderContainer _container(WledRepository? repo,
        {List<int> effective = const [0, 1]}) =>
    ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWith((ref) => repo),
      deviceChannelsProvider.overrideWithValue(_channels),
      effectiveChannelIdsProvider.overrideWithValue(effective),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('the OLD path — what My Favorites used to do — refuses a Static '
      'favorite by size, which is the bug', () async {
    final repo = _Repo();
    // The grid's old inline apply, for the pre-fix Static payload.
    final legacy = _chiefs(0).toWledPayload(290);
    expect(await repo.applyJson(legacy), isFalse);
    expect(repo.refused.single, greaterThan(kMaxApplyPayloadBytes));
  });

  test('a per-pixel favorite goes through the spine: base + one paint per '
      'channel, never one oversized message', () async {
    final repo = _Repo();
    final c = _container(repo);
    addTearDown(c.dispose);

    final outcome = await applyFavoritePayloadWith(c.read, _staticFavorite());

    expect(outcome.status, FavoriteApplyStatus.applied);
    expect(outcome.perPixel, isTrue);
    expect(repo.refused, isEmpty, reason: 'nothing was sent as one message');

    // The base write: solid black on both channels, carrying the brightness.
    expect(repo.json, hasLength(1));
    expect(repo.json.single['bri'], 180);
    expect(repo.json.single.containsKey(kFavoriteDesignKey), isFalse,
        reason: 'the design never reaches the wire');

    // The paints: every LED of both channels, red/gold/white from each
    // channel's own LED 0.
    expect(repo.pixels.keys, [0, 1]);
    for (final e in {0: 128, 1: 162}.entries) {
      final leds = <int, String>{
        for (final s in repo.pixels[e.key]!)
          for (int i = s.start; i <= s.end; i++) i: s.color.join(','),
      };
      expect(leds.length, e.value);
      expect([leds[0], leds[1], leds[2], leds[3]],
          ['227,24,55,0', '255,184,28,0', '255,255,255,0', '227,24,55,0']);
    }
  });

  test('…and it is byte-for-byte what My Designs sends for the same pattern',
      () async {
    final design = customDesignFromEditablePattern(
      pattern: _chiefs(0),
      name: 'Kansas City Chiefs',
      ownerId: 'u1',
      channels: _editorChannels,
    );
    final viaDesigns = _Repo(), viaFavorites = _Repo();
    final a = _container(viaDesigns), b = _container(viaFavorites);
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    await applyPositionalDesignWith(a.read, design);
    await applyFavoritePayloadWith(b.read, _staticFavorite());

    expect(jsonEncode(viaFavorites.json), jsonEncode(viaDesigns.json));
    expect('${viaFavorites.pixels}', '${viaDesigns.pixels}');
  });

  test('an ordinary favorite is still ONE channel-filtered applyJson', () async {
    final repo = _Repo();
    final c = _container(repo);
    addTearDown(c.dispose);
    final animated = _chiefs(15).toWledPayload(290);

    final outcome = await applyFavoritePayloadWith(c.read, animated);

    expect(outcome.status, FavoriteApplyStatus.applied);
    expect(outcome.perPixel, isFalse);
    expect(repo.pixels, isEmpty);
    expect(repo.json, hasLength(1));
    expect(identical(outcome.payload, repo.json.single), isTrue,
        reason: 'the caller previews/logs the payload AS SENT');
    final ids = [
      for (final s in (repo.json.single['seg'] as List).cast<Map>()) s['id'],
    ];
    expect(ids, containsAll([0, 1]), reason: 'fanned out by the channel filter');
  });

  test('a channel outside the effective set is not painted', () async {
    final repo = _Repo();
    final c = _container(repo, effective: const [1]);
    addTearDown(c.dispose);
    final outcome = await applyFavoritePayloadWith(c.read, _staticFavorite());
    expect(outcome.isApplied, isTrue);
    expect(repo.pixels.keys, [1]);
  });

  test('a refused paint is a FAILURE, not an "Applied" toast', () async {
    final repo = _Repo(failPixelsOn: 1);
    final c = _container(repo);
    addTearDown(c.dispose);
    final outcome = await applyFavoritePayloadWith(c.read, _staticFavorite());
    expect(outcome.status, FavoriteApplyStatus.failed);
    expect(outcome.isApplied, isFalse);
  });

  test('no controller / no channels are reported, and nothing is sent',
      () async {
    final none = _container(null);
    addTearDown(none.dispose);
    expect((await applyFavoritePayloadWith(none.read, _staticFavorite())).status,
        FavoriteApplyStatus.noDevice);

    final repo = _Repo();
    final gated = _container(repo, effective: const []);
    addTearDown(gated.dispose);
    expect((await applyFavoritePayloadWith(gated.read, _staticFavorite())).status,
        FavoriteApplyStatus.noChannels);
    expect(repo.json, isEmpty);
    expect(repo.pixels, isEmpty);
  });

  test('through the REAL WledService (simulated host): the chunks it would post '
      'rebuild the picture LED for LED — 290/290', () async {
    // NOT a hardware test. The transport is the production WledService with
    // its mock host, which records each per-pixel request body instead of
    // posting it — so this proves the favorite → spine → chunker → `i` payload
    // chain is exact, and nothing about what a controller then does with it.
    final svc = WledService('http://mock');
    final c = _container(svc);
    addTearDown(c.dispose);

    final outcome = await applyFavoritePayloadWith(c.read, _staticFavorite());
    expect(outcome.status, FavoriteApplyStatus.applied);

    final requests = svc.lastSimulatedPerPixelChunks;
    expect(requests.length, 2, reason: 'one paint request per channel');
    final buffer = <int, Map<int, String>>{0: {}, 1: {}};
    for (final body in requests) {
      expect(utf8.encode(jsonEncode(body)).length, lessThan(6000),
          reason: "under the device's ~6 KB JSON buffer");
      final seg = (body['seg'] as List).single as Map;
      expect(seg['fx'], 0);
      final i = seg['i'] as List;
      int k = 0;
      while (k < i.length) {
        final start = i[k] as int;
        if (i[k + 1] is int) {
          for (int x = start; x < (i[k + 1] as int); x++) {
            buffer[seg['id']]![x] = (i[k + 2] as List).join(',');
          }
          k += 3;
        } else {
          buffer[seg['id']]![start] = (i[k + 1] as List).join(',');
          k += 2;
        }
      }
    }

    final want = _chiefs(0).staticColorsRgbw();
    var wrong = 0;
    for (final e in {0: 128, 1: 162}.entries) {
      expect(buffer[e.key]!.length, e.value);
      for (int led = 0; led < e.value; led++) {
        if (buffer[e.key]![led] != want[led % want.length].join(',')) wrong++;
      }
    }
    expect(wrong, 0, reason: 'of 290 LEDs');
  });

  test('a channel longer than one chunk is split — the chunker engages', () {
    // The bench's channels (128, 162) each fit one 224-LED chunk, so the split
    // WITHIN a channel cannot be shown there. This is the same code path the
    // transport runs, on a 300-LED channel of all-distinct neighbours.
    final design = customDesignFromEditablePattern(
      pattern: _chiefs(0),
      name: 'Long',
      ownerId: '',
      channels: const [PatternEditorChannel(id: 0, name: 'Long', ledCount: 300)],
    );
    final back = perPixelDesignOfFavorite(jsonDecode(
        jsonEncode(buildPerPixelFavoritePayload(design))) as Map<String, dynamic>)!;
    final spans = normalizeAndMergePixelSpans(customDesignToSpans(back)[0]!);
    final chunks = chunkPixelSpans(spans, kDefaultPixelChunkSize);
    expect(chunks.length, 2);
    expect(chunks.map((c) => c.fold<int>(0, (n, s) => n + s.length)), [224, 76]);
    for (final chunk in chunks) {
      expect(utf8.encode(jsonEncode(buildPerPixelPayload(chunk, 0))).length,
          lessThan(6000), reason: 'under the device\'s ~6 KB JSON buffer');
    }
  });
}
